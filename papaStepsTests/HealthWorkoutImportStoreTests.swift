import Foundation
import Testing
@testable import papaSteps

@MainActor
struct HealthWorkoutImportStoreTests {
    nonisolated static let now = Date(timeIntervalSince1970: 1_800_100_000)

    private static func makeWorkout(
        endedAt: Date,
        duration: TimeInterval = 600
    ) -> HealthWalkingWorkout {
        HealthWalkingWorkout(
            id: UUID(),
            startDate: endedAt.addingTimeInterval(-duration),
            endDate: endedAt,
            movingDuration: duration * 0.9,
            distanceMeters: 800,
            sourceName: "Apple Watch",
            sourceBundleIdentifier: "com.apple.health",
            timeZoneIdentifier: nil
        )
    }

    private static func routePoints(
        for workout: HealthWalkingWorkout,
        count: Int = 3
    ) -> [NewTrackPoint] {
        (0..<count).map { index in
            NewTrackPoint(
                id: UUID(),
                timestamp: workout.startDate.addingTimeInterval(
                    Double(index) * 10
                ),
                latitude: -37.8136 + Double(index) * 0.0001,
                longitude: 144.9631,
                altitude: 25,
                horizontalAccuracy: 5,
                verticalAccuracy: 5,
                speed: 1.4,
                speedAccuracy: 0.5,
                course: 90,
                courseAccuracy: 5,
                isAccepted: true,
                rejectionReason: nil,
                startsNewSegment: index == 0
            )
        }
    }

    private static func makeStore(
        repository: SwiftDataWalkRepository,
        client: FakeHealthCapabilityClient
    ) -> HealthWorkoutImportStore {
        HealthWorkoutImportStore(
            client: client,
            repository: repository,
            healthStore: WalkHealthStore(
                client: client,
                preferences: FakeHealthPreferences(insightsRequested: false),
                repository: repository
            ),
            now: { now },
            fallbackTimeZoneIdentifier: { "Australia/Melbourne" }
        )
    }

    @Test
    func loadsSelectsAndImportsHealthWorkoutOnlyOnce() async throws {
        let container = try PersistenceContainer.make(isStoredInMemoryOnly: true)
        let repository = SwiftDataWalkRepository(modelContainer: container)
        let client = FakeHealthCapabilityClient()
        let now = Self.now
        let workout = Self.makeWorkout(endedAt: now.addingTimeInterval(-3_000))
        client.walkingWorkoutCandidates = [workout]
        client.walkingWorkoutImports[workout.id] = HealthWalkingWorkoutImport(
            workout: workout,
            routePoints: Self.routePoints(for: workout)
        )
        let store = Self.makeStore(repository: repository, client: client)

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

    /// A walk imported before Apple Health finished syncing its route stays on
    /// offer, so the user is not stuck with a permanently map-less walk.
    @Test
    func recentWalkImportedWithoutARouteStaysOfferedAndIsRepaired() async throws {
        let container = try PersistenceContainer.make(isStoredInMemoryOnly: true)
        let repository = SwiftDataWalkRepository(modelContainer: container)
        let client = FakeHealthCapabilityClient()
        let workout = Self.makeWorkout(
            endedAt: Self.now.addingTimeInterval(-3_000)
        )
        client.walkingWorkoutCandidates = [workout]
        client.walkingWorkoutImports[workout.id] = HealthWalkingWorkoutImport(
            workout: workout,
            routePoints: []
        )
        let store = Self.makeStore(repository: repository, client: client)

        await store.load()
        store.toggleSelection(id: workout.id)
        _ = await store.importSelected()

        let item = try #require(store.items.first)
        #expect(item.isAwaitingRoute)
        #expect(!item.isImported, "a route-less walk must remain selectable")

        // Re-importing while the route is still absent changes nothing.
        store.toggleSelection(id: workout.id)
        #expect(await store.importSelected() == 0)
        #expect(try repository.fetchSummaries().count == 1)

        client.walkingWorkoutImports[workout.id] = HealthWalkingWorkoutImport(
            workout: workout,
            routePoints: Self.routePoints(for: workout)
        )
        await store.load()
        store.toggleSelection(id: workout.id)

        #expect(await store.importSelected() == 1)
        #expect(try repository.fetchSummaries().count == 1)
        let walkID = try #require(try repository.fetchSummaries().first?.id)
        #expect(try repository.fetchDetail(id: walkID)?.trackPoints.count == 3)
        #expect(store.items.first?.isImported == true)
        #expect(store.items.first?.isAwaitingRoute == false)
    }

    /// An indoor walk never gets a route, so it must not be offered forever.
    @Test
    func oldWalkWithoutARouteIsTreatedAsSimplyImported() async throws {
        let container = try PersistenceContainer.make(isStoredInMemoryOnly: true)
        let repository = SwiftDataWalkRepository(modelContainer: container)
        let client = FakeHealthCapabilityClient()
        let workout = Self.makeWorkout(
            endedAt: Self.now.addingTimeInterval(
                -HealthWalkingWorkout.routeSyncGracePeriod - 60
            )
        )
        client.walkingWorkoutCandidates = [workout]
        client.walkingWorkoutImports[workout.id] = HealthWalkingWorkoutImport(
            workout: workout,
            routePoints: []
        )
        let store = Self.makeStore(repository: repository, client: client)

        await store.load()
        store.toggleSelection(id: workout.id)
        _ = await store.importSelected()

        let item = try #require(store.items.first)
        #expect(item.isImported)
        #expect(!item.isAwaitingRoute)
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
