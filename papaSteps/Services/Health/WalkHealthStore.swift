import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class WalkHealthStore {
    private static let logger = Logger(
        subsystem: "org.nando.papaSteps",
        category: "HealthWorkoutExport"
    )

    private(set) var isWorking = false
    private(set) var lastMessage: String?

    private let client: any HealthDataProviding
    private let preferences: any HealthPreferencesProviding
    private let repository: any WalkRepository
    private let now: @Sendable () -> Date

    init(
        client: any HealthDataProviding,
        preferences: any HealthPreferencesProviding,
        repository: any WalkRepository,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.client = client
        self.preferences = preferences
        self.repository = repository
        self.now = now
    }

    var accessState: HealthAccessState {
        guard client.isAvailable else { return .unavailable }
        return preferences.insightsRequested ? .requested : .notRequested
    }

    var workoutExportEnabled: Bool {
        preferences.workoutExportEnabled
    }

    func requestAccess() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await client.requestAuthorization(
                includeWorkoutWrite: preferences.workoutExportEnabled
            )
            preferences.insightsRequested = true
            lastMessage = "Apple Health access was requested. Empty results remain neutral because Apple does not reveal whether read access was declined."
        } catch {
            lastMessage = error.localizedDescription
        }
    }

    func setWorkoutExportEnabled(_ enabled: Bool) async {
        guard enabled else {
            preferences.workoutExportEnabled = false
            lastMessage = "New walks will no longer be saved to Apple Health. Existing Health workouts are unchanged."
            return
        }

        isWorking = true
        defer { isWorking = false }
        do {
            try await client.requestAuthorization(includeWorkoutWrite: true)
            preferences.insightsRequested = true
            preferences.workoutExportEnabled = true
            lastMessage = "New completed walks will be saved to Apple Health."
        } catch {
            preferences.workoutExportEnabled = false
            lastMessage = error.localizedDescription
        }
    }

    @discardableResult
    func enrichWalk(id: UUID) async -> WalkDetail? {
        guard var detail = try? repository.fetchDetail(id: id),
              let input = detail.healthInput else {
            lastMessage = "This walk could not be prepared for Apple Health."
            return nil
        }

        guard client.isAvailable else {
            try? repository.updateHealthEnrichmentStatus(
                id: id,
                status: .unavailable,
                errorMessage: nil
            )
            return try? repository.fetchDetail(id: id)
        }
        guard preferences.insightsRequested else {
            return detail
        }

        isWorking = true
        defer { isWorking = false }
        try? repository.updateHealthEnrichmentStatus(
            id: id,
            status: .pending,
            errorMessage: nil
        )

        do {
            let enrichment = try await client.fetchEnrichment(
                for: input,
                at: now()
            )
            if let updated = try repository.applyHealthEnrichment(
                id: id,
                enrichment: enrichment
            ) {
                detail = updated
            }
            lastMessage = enrichment.heartRate.value == nil
                && enrichment.walkingAsymmetry.value == nil
                ? "No matching Health samples are available yet. You can refresh after Apple Watch or Health synchronization completes."
                : "Health insights were refreshed."
        } catch {
            try? repository.updateHealthEnrichmentStatus(
                id: id,
                status: .failed,
                errorMessage: "Health insights could not be refreshed."
            )
            lastMessage = "Health insights could not be refreshed. Core walk data is unchanged."
        }

        // Imported workouts must never be exported back to Health. The Health
        // workout UUID is import provenance and the feedback-loop guard.
        if preferences.workoutExportEnabled, detail.origin == .papaSteps {
            detail = await exportWorkout(input: input) ?? detail
        }
        return (try? repository.fetchDetail(id: id)) ?? detail
    }

    private func exportWorkout(input: HealthWalkInput) async -> WalkDetail? {
        do {
            try await client.requestAuthorization(includeWorkoutWrite: true)
            _ = try repository.updateWorkoutExport(
                id: input.id,
                status: .pending,
                workoutUUID: nil,
                errorMessage: nil
            )
            let workoutUUID = try await client.ensureWorkout(for: input)
            return try repository.updateWorkoutExport(
                id: input.id,
                status: .completed,
                workoutUUID: workoutUUID,
                errorMessage: nil
            )
        } catch {
            if error as? HealthDataError == .workoutSharingDenied {
                preferences.workoutExportEnabled = false
            }
            if let exportError = error as? HealthWorkoutExportError {
                Self.logger.error(
                    "Workout export failed: stage=\(exportError.stage.rawValue, privacy: .public) domain=\(exportError.underlyingDomain, privacy: .public) code=\(exportError.underlyingCode)"
                )
            } else {
                let nsError = error as NSError
                Self.logger.error(
                    "Workout export failed: domain=\(nsError.domain, privacy: .public) code=\(nsError.code)"
                )
            }
            let failureMessage = workoutFailureMessage(for: error)
            lastMessage = "The local walk is safe. \(failureMessage)"
            return try? repository.updateWorkoutExport(
                id: input.id,
                status: .failed,
                workoutUUID: nil,
                errorMessage: failureMessage
            )
        }
    }

    private func workoutFailureMessage(for error: any Error) -> String {
        if let healthError = error as? HealthDataError {
            return healthError.localizedDescription
        }
        if let exportError = error as? HealthWorkoutExportError {
            return exportError.localizedDescription
        }
        let nsError = error as NSError
        return "Apple Health could not save this workout (\(nsError.domain) \(nsError.code)). The local walk is safe; try again."
    }
}
