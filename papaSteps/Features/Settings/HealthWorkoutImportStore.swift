import Foundation
import Observation

@MainActor
@Observable
final class HealthWorkoutImportStore {
    struct Item: Identifiable, Equatable, Sendable {
        let workout: HealthWalkingWorkout
        /// Imported *and* complete. A walk still missing its route reports
        /// `false` so it can be selected again.
        let isImported: Bool
        /// Imported before Apple Health finished syncing the location series.
        /// Re-importing is what fills the route in.
        let isAwaitingRoute: Bool

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
            let candidateIDs = Set(workouts.map(\.id))
            let importedIDs = try repository.importedHealthWorkoutIDs(
                in: candidateIDs
            )
            let routelessIDs = try repository.healthWorkoutIDsAwaitingRoute(
                in: candidateIDs
            )
            items = workouts.map { workout in
                // A route-less walk is only worth re-offering while its route
                // could still be syncing; after that it simply has none.
                let isAwaitingRoute = routelessIDs.contains(workout.id)
                    && workout.mayStillBeAwaitingRoute(at: referenceDate)
                return Item(
                    workout: workout,
                    isImported: importedIDs.contains(workout.id)
                        && !isAwaitingRoute,
                    isAwaitingRoute: isAwaitingRoute
                )
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
        var repairedCount = 0
        var stillSyncingCount = 0
        var failedCount = 0
        for item in items where ids.contains(item.id) && !item.isImported {
            do {
                let payload = try await client.walkingWorkoutImport(id: item.id)
                if item.isAwaitingRoute && payload.routePoints.isEmpty {
                    // Apple Health has not handed over the route yet; the walk
                    // is already saved, so there is nothing to write.
                    stillSyncingCount += 1
                    continue
                }
                let summary = try repository.importHealthWorkout(
                    payload,
                    importedAt: now(),
                    fallbackTimeZoneIdentifier: fallbackTimeZoneIdentifier()
                )
                if item.isAwaitingRoute {
                    repairedCount += 1
                } else {
                    importedCount += 1
                }
                _ = await healthStore.enrichWalk(id: summary.id)
            } catch {
                failedCount += 1
            }
        }
        selectedIDs = []
        await load()
        var parts: [String] = []
        if importedCount > 0 || (repairedCount == 0 && failedCount == 0 && stillSyncingCount == 0) {
            parts.append("Imported \(importedCount) walking workout\(importedCount == 1 ? "" : "s") into papaSteps.")
        }
        if repairedCount > 0 {
            parts.append("Added the route to \(repairedCount) previously imported walk\(repairedCount == 1 ? "" : "s").")
        }
        if stillSyncingCount > 0 {
            parts.append("\(stillSyncingCount) walk\(stillSyncingCount == 1 ? " is" : "s are") still waiting on route data from Apple Health; try again shortly.")
        }
        if failedCount > 0 {
            parts.append("\(failedCount) could not be imported.")
        }
        message = parts.joined(separator: " ")
        return importedCount + repairedCount
    }
}
