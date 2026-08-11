import Foundation
import Observation

@MainActor
@Observable
final class HealthWorkoutImportStore {
    struct Item: Identifiable, Equatable, Sendable {
        let workout: HealthWalkingWorkout
        let isImported: Bool

        var id: UUID { workout.id }
    }

    private(set) var items: [Item] = []
    private(set) var selectedIDs: Set<UUID> = []
    private(set) var isLoading = false
    private(set) var isImporting = false
    private(set) var message: String?

    private let client: any HealthDataProviding
    private let repository: any WalkRepository
    private let healthStore: WalkHealthStore
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private let fallbackTimeZoneIdentifier: @Sendable () -> String

    init(
        client: any HealthDataProviding,
        repository: any WalkRepository,
        healthStore: WalkHealthStore,
        now: @escaping @Sendable () -> Date = Date.init,
        calendar: Calendar = .current,
        fallbackTimeZoneIdentifier: @escaping @Sendable () -> String = {
            TimeZone.current.identifier
        }
    ) {
        self.client = client
        self.repository = repository
        self.healthStore = healthStore
        self.now = now
        self.calendar = calendar
        self.fallbackTimeZoneIdentifier = fallbackTimeZoneIdentifier
    }

    var selectableCount: Int {
        items.lazy.filter { !$0.isImported }.count
    }

    var canImport: Bool {
        !selectedIDs.isEmpty && !isLoading && !isImporting
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        message = nil
        defer { isLoading = false }

        do {
            try await client.requestWalkingWorkoutReadAuthorization()
            let referenceDate = now()
            let startDate = calendar.date(
                byAdding: .day,
                value: -90,
                to: referenceDate
            ) ?? referenceDate.addingTimeInterval(-90 * 24 * 60 * 60)
            let workouts = try await client.walkingWorkouts(
                since: startDate,
                limit: 100
            )
            let importedIDs = try repository.importedHealthWorkoutIDs(
                in: Set(workouts.map(\.id))
            )
            items = workouts.map {
                Item(workout: $0, isImported: importedIDs.contains($0.id))
            }
            selectedIDs.formIntersection(
                Set(items.filter { !$0.isImported }.map(\.id))
            )
            if items.isEmpty {
                message = "No walking workouts were returned for the last 90 days. This can also occur when read access is declined."
            }
        } catch {
            items = []
            selectedIDs = []
            message = error.localizedDescription
        }
    }

    func toggleSelection(id: UUID) {
        guard items.contains(where: { $0.id == id && !$0.isImported }) else {
            return
        }
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    func selectAllAvailable() {
        selectedIDs = Set(items.filter { !$0.isImported }.map(\.id))
    }

    func clearSelection() {
        selectedIDs = []
    }

    @discardableResult
    func importSelected() async -> Int {
        guard canImport else { return 0 }
        isImporting = true
        message = nil
        defer { isImporting = false }

        let ids = selectedIDs
        var importedCount = 0
        var failedCount = 0
        for item in items where ids.contains(item.id) && !item.isImported {
            do {
                let payload = try await client.walkingWorkoutImport(id: item.id)
                let summary = try repository.importHealthWorkout(
                    payload,
                    importedAt: now(),
                    fallbackTimeZoneIdentifier: fallbackTimeZoneIdentifier()
                )
                importedCount += 1
                _ = await healthStore.enrichWalk(id: summary.id)
            } catch {
                failedCount += 1
            }
        }
        selectedIDs = []
        await load()
        if failedCount == 0 {
            message = "Imported \(importedCount) walking workout\(importedCount == 1 ? "" : "s") into papaSteps."
        } else {
            message = "Imported \(importedCount) workout\(importedCount == 1 ? "" : "s"); \(failedCount) could not be imported."
        }
        return importedCount
    }
}
