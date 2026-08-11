import Foundation
import Testing
@testable import papaSteps

@MainActor
struct HealthWorkoutImportStoreTests {
    @Test
    func loadsSelectsAndImportsHealthWorkoutOnlyOnce() async throws {
        let container = try PersistenceContainer.make(isStoredInMemoryOnly: true)
        let repository = SwiftDataWalkRepository(modelContainer: container)
        let client = FakeHealthCapabilityClient()
        let preferences = FakeHealthPreferences(insightsRequested: false)
        let healthStore = WalkHealthStore(
            client: client,
            preferences: preferences,
            repository: repository
        )
        let now = Date(timeIntervalSince1970: 1_800_100_000)
        let workout = HealthWalkingWorkout(
            id: UUID(),
            startDate: now.addingTimeInterval(-3_600),
            endDate: now.addingTimeInterval(-3_000),
            movingDuration: 540,
            distanceMeters: 800,
            sourceName: "Apple Watch",
            sourceBundleIdentifier: "com.apple.health",
            timeZoneIdentifier: nil
        )
        client.walkingWorkoutCandidates = [workout]
        client.walkingWorkoutImports[workout.id] = HealthWalkingWorkoutImport(
            workout: workout,
            routePoints: []
        )
        let store = HealthWorkoutImportStore(
            client: client,
            repository: repository,
            healthStore: healthStore,
            now: { now },
            fallbackTimeZoneIdentifier: { "Australia/Melbourne" }
        )

        await store.load()
        store.toggleSelection(id: workout.id)
        let count = await store.importSelected()

        #expect(client.walkingWorkoutReadAuthorizationCount == 2)
        #expect(count == 1)
        #expect(store.items.first?.isImported == true)
        #expect(store.selectedIDs.isEmpty)
        #expect(try repository.fetchSummaries().count == 1)

        store.toggleSelection(id: workout.id)
        #expect(store.selectedIDs.isEmpty)
        #expect(await store.importSelected() == 0)
        #expect(try repository.fetchSummaries().count == 1)
    }

    @Test
    func importedWorkoutCannotBeExportedBackToHealth() async throws {
        let container = try PersistenceContainer.make(isStoredInMemoryOnly: true)
        let repository = SwiftDataWalkRepository(modelContainer: container)
        let client = FakeHealthCapabilityClient()
        let preferences = FakeHealthPreferences(
            insightsRequested: true,
            workoutExportEnabled: true
        )
        let healthStore = WalkHealthStore(
            client: client,
            preferences: preferences,
            repository: repository
        )
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let workout = HealthWalkingWorkout(
            id: UUID(),
            startDate: start,
            endDate: start.addingTimeInterval(600),
            movingDuration: 550,
            distanceMeters: 750,
            sourceName: "Apple Watch",
            sourceBundleIdentifier: "com.apple.health",
            timeZoneIdentifier: "Australia/Melbourne"
        )
        let summary = try repository.importHealthWorkout(
            HealthWalkingWorkoutImport(workout: workout, routePoints: []),
            importedAt: start.addingTimeInterval(1_000),
            fallbackTimeZoneIdentifier: "UTC"
        )

        _ = await healthStore.enrichWalk(id: summary.id)

        #expect(client.enrichmentRequestCount == 1)
        #expect(client.workoutEnsureCount == 0)
        #expect(try repository.fetchDetail(id: summary.id)?.origin == .appleHealth)
    }
}
