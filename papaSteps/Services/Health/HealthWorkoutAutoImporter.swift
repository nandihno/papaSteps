import Foundation
import Observation
import OSLog

/// Copies new Apple Health walking workouts into papaSteps without the user
/// visiting the import screen.
///
/// This exists so an Apple Watch walk — whose route comes from the watch's own
/// GPS rather than a pocketed iPhone — lands in the app on its own. HealthKit
/// background delivery wakes the app when a walking workout is written, and
/// each notification triggers a bounded catch-up pass.
///
/// Two rules keep the feature predictable:
///
/// - Nothing older than the opt-in date is imported, so enabling the toggle
///   never backfills months of history. ``HealthWorkoutImportView`` remains the
///   way to pull in older walks.
/// - papaSteps' own exports are skipped by ``HealthDataProviding``, and the
///   repository is asked which workout IDs it already holds, so a walk cannot
///   round-trip back into the app as a duplicate.
@MainActor
@Observable
final class HealthWorkoutAutoImporter {
    private static let logger = Logger(
        subsystem: "org.nando.papaSteps",
        category: "HealthWorkoutAutoImport"
    )

    /// How far back a catch-up pass looks. Long enough to cover an app that was
    /// asleep for a weekend, short enough that a wake never turns into a
    /// full-history import. Route backfill is bounded by the same span, via
    /// ``HealthWalkingWorkout/routeSyncGracePeriod``.
    private static let catchUpWindow: TimeInterval = 7 * 24 * 60 * 60
    private static let workoutFetchLimit = 25

    private(set) var lastImportedCount = 0
    private(set) var lastRouteBackfillCount = 0
    private(set) var lastImportDate: Date?
    private(set) var message: String?

    private let client: any HealthDataProviding
    private let repository: any WalkRepository
    private let healthStore: WalkHealthStore
    private let preferences: any HealthPreferencesProviding
    private let now: @Sendable () -> Date
    private let fallbackTimeZoneIdentifier: @Sendable () -> String

    private var observationTask: Task<Void, Never>?
    private var activePass: Task<Void, Never>?

    /// Called on the main actor after a pass imports at least one walk, so the
    /// history and progress screens can refresh.
    var onWalksImported: (@MainActor () -> Void)?

    init(
        client: any HealthDataProviding,
        repository: any WalkRepository,
        healthStore: WalkHealthStore,
        preferences: any HealthPreferencesProviding,
        now: @escaping @Sendable () -> Date = Date.init,
        fallbackTimeZoneIdentifier: @escaping @Sendable () -> String = {
            TimeZone.current.identifier
        }
    ) {
        self.client = client
        self.repository = repository
        self.healthStore = healthStore
        self.preferences = preferences
        self.now = now
        self.fallbackTimeZoneIdentifier = fallbackTimeZoneIdentifier
    }

    var isEnabled: Bool {
        preferences.workoutAutoImportEnabled
    }

    var isAvailable: Bool {
        client.isAvailable
    }

    /// Resumes observation if the user previously opted in.
    ///
    /// Called during dependency construction rather than from a view, because a
    /// HealthKit background launch may never render one.
    func activate() {
        guard preferences.workoutAutoImportEnabled, client.isAvailable else {
            return
        }
        startObserving()
        Task { await self.runCatchUpPass() }
    }

    func setEnabled(_ enabled: Bool) async {
        guard enabled else {
            preferences.workoutAutoImportEnabled = false
            preferences.workoutAutoImportSince = nil
            stopObserving()
            await client.disableWalkingWorkoutBackgroundDelivery()
            message = "New Apple Health walks will no longer import on their own. Existing walks are unchanged."
            return
        }

        do {
            try await client.requestWalkingWorkoutReadAuthorization()
            try await client.enableWalkingWorkoutBackgroundDelivery()
            preferences.insightsRequested = true
            preferences.workoutAutoImportEnabled = true
            // Anchor the window at opt-in so turning this on does not import
            // history the user never asked for.
            preferences.workoutAutoImportSince = now()
            startObserving()
            message = "Walking workouts recorded from now on — including Apple Watch walks — will import automatically. Use Import Walks for anything older."
        } catch {
            preferences.workoutAutoImportEnabled = false
            preferences.workoutAutoImportSince = nil
            message = error.localizedDescription
        }
    }

    private func startObserving() {
        guard observationTask == nil else { return }
        let changes = client.walkingWorkoutChanges()
        observationTask = Task { [weak self] in
            for await change in changes {
                guard let self else {
                    change.acknowledge()
                    return
                }
                // Acknowledging last keeps the app awake for the whole pass,
                // which matters when HealthKit launched it into the background.
                await self.runCatchUpPass()
                change.acknowledge()
            }
        }
    }

    private func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
    }

    /// Imports every eligible walking workout inside the catch-up window.
    ///
    /// Safe to call repeatedly: already-imported workouts are filtered out.
    /// Overlapping calls are serialised rather than dropped — a caller that
    /// dropped its pass could acknowledge HealthKit for a workout that the
    /// in-flight pass had already queried past, losing it until the next wake.
    func runCatchUpPass() async {
        let previous = activePass
        let pass = Task { @MainActor [weak self] in
            await previous?.value
            await self?.performCatchUpPass()
        }
        activePass = pass
        await pass.value
    }

    private func performCatchUpPass() async {
        guard preferences.workoutAutoImportEnabled, client.isAvailable else {
            return
        }
        guard let optInDate = preferences.workoutAutoImportSince else { return }

        let reference = now()
        let windowStart = max(
            optInDate,
            reference.addingTimeInterval(-Self.catchUpWindow)
        )

        do {
            let workouts = try await client.walkingWorkouts(
                since: windowStart,
                limit: Self.workoutFetchLimit
            )
            guard !workouts.isEmpty else { return }

            let candidateIDs = Set(workouts.map(\.id))
            let alreadyImported = try repository.importedHealthWorkoutIDs(
                in: candidateIDs
            )
            // A workout can reach the phone ahead of its route: ending a
            // mirrored session on the phone finalises the workout locally while
            // the watch is still transferring the location series, and nothing
            // re-notifies for the type we imported. Re-import those walks each
            // pass until the route lands or they age out of the window.
            let routeless = try repository.healthWorkoutIDsAwaitingRoute(
                in: candidateIDs
            )
            let awaitingRoute = Set(
                workouts
                    .filter {
                        routeless.contains($0.id)
                            && $0.mayStillBeAwaitingRoute(at: reference)
                    }
                    .map(\.id)
            )
            let pending = workouts.filter {
                !alreadyImported.contains($0.id) || awaitingRoute.contains($0.id)
            }
            guard !pending.isEmpty else { return }

            var importedCount = 0
            var backfilledCount = 0
            for workout in pending {
                let isBackfill = awaitingRoute.contains(workout.id)
                do {
                    let payload = try await client.walkingWorkoutImport(
                        id: workout.id
                    )
                    if isBackfill && payload.routePoints.isEmpty {
                        // Still syncing. Leave the walk alone and try again on
                        // the next notification or foreground pass.
                        continue
                    }
                    let summary = try repository.importHealthWorkout(
                        payload,
                        importedAt: now(),
                        fallbackTimeZoneIdentifier: fallbackTimeZoneIdentifier()
                    )
                    if isBackfill {
                        backfilledCount += 1
                    } else {
                        importedCount += 1
                    }
                    await healthStore.enrichWalk(id: summary.id)
                } catch {
                    // One bad workout must not abandon the rest of the pass.
                    Self.logger.error(
                        "Auto-import skipped a workout: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }

            guard importedCount > 0 || backfilledCount > 0 else { return }
            lastImportedCount = importedCount
            lastRouteBackfillCount = backfilledCount
            lastImportDate = now()
            message = Self.summaryMessage(
                imported: importedCount,
                backfilled: backfilledCount
            )
            Self.logger.info(
                "Auto-imported \(importedCount) walking workout(s); backfilled routes for \(backfilledCount)."
            )
            onWalksImported?()
        } catch {
            Self.logger.error(
                "Auto-import pass failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private static func summaryMessage(
        imported: Int,
        backfilled: Int
    ) -> String {
        let routes = "route\(backfilled == 1 ? "" : "s")"
        let walks = "walk\(imported == 1 ? "" : "s")"
        return switch (imported, backfilled) {
        case (0, _):
            "Added the Apple Health \(routes) to \(backfilled) walk\(backfilled == 1 ? "" : "s")."
        case (_, 0):
            "Automatically imported \(imported) \(walks) from Apple Health."
        default:
            "Automatically imported \(imported) \(walks) from Apple Health, and added the \(routes) to \(backfilled) earlier walk\(backfilled == 1 ? "" : "s")."
        }
    }
}
