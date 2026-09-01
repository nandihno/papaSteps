import Foundation
import Testing
@testable import papaSteps

@MainActor
struct HealthWorkoutAutoImporterTests {
    private struct Harness {
        let client: FakeHealthCapabilityClient
        let preferences: FakeHealthPreferences
        let repository: SwiftDataWalkRepository
        let importer: HealthWorkoutAutoImporter
        let now: Date
    }

    private static func makeHarness(
        autoImportEnabled: Bool = false,
        autoImportSince: Date? = nil,
        now: Date = Date(timeIntervalSince1970: 1_800_100_000)
    ) throws -> Harness {
        let container = try PersistenceContainer.make(isStoredInMemoryOnly: true)
        let repository = SwiftDataWalkRepository(modelContainer: container)
        let client = FakeHealthCapabilityClient()
        let preferences = FakeHealthPreferences(
            insightsRequested: true,
            workoutAutoImportEnabled: autoImportEnabled,
            workoutAutoImportSince: autoImportSince
        )
        let healthStore = WalkHealthStore(
            client: client,
            preferences: preferences,
            repository: repository
        )
        let importer = HealthWorkoutAutoImporter(
            client: client,
            repository: repository,
            healthStore: healthStore,
            preferences: preferences,
            now: { now },
            fallbackTimeZoneIdentifier: { "Australia/Melbourne" }
        )
        return Harness(
            client: client,
            preferences: preferences,
            repository: repository,
            importer: importer,
            now: now
        )
    }

    private static func makeWorkout(
        startedAt: Date,
        duration: TimeInterval = 600
    ) -> HealthWalkingWorkout {
        HealthWalkingWorkout(
            id: UUID(),
            startDate: startedAt,
            endDate: startedAt.addingTimeInterval(duration),
            movingDuration: duration * 0.9,
            distanceMeters: 900,
            sourceName: "Apple Watch",
            sourceBundleIdentifier: "com.apple.health",
            timeZoneIdentifier: nil
        )
    }

    private static func register(
        _ workout: HealthWalkingWorkout,
        on client: FakeHealthCapabilityClient,
        routePoints: [NewTrackPoint] = []
    ) {
        client.walkingWorkoutCandidates.append(workout)
        client.walkingWorkoutImports[workout.id] = HealthWalkingWorkoutImport(
            workout: workout,
            routePoints: routePoints
        )
    }

    /// Stands in for the location series Apple Health hands over once the watch
    /// has finished transferring it.
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
                altitude: 25 + Double(index),
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

    @Test
    func enablingTurnsOnBackgroundDeliveryAndAnchorsTheWindow() async throws {
        let harness = try Self.makeHarness()

        await harness.importer.setEnabled(true)

        #expect(harness.importer.isEnabled)
        #expect(harness.client.isBackgroundDeliveryEnabled)
        #expect(harness.client.backgroundDeliveryEnableCount == 1)
        #expect(harness.preferences.workoutAutoImportSince == harness.now)
    }

    @Test
    func enablingRollsBackWhenBackgroundDeliveryIsRefused() async throws {
        let harness = try Self.makeHarness()
        harness.client.backgroundDeliveryError =
            HealthDataError.backgroundDeliveryUnavailable

        await harness.importer.setEnabled(true)

        #expect(!harness.importer.isEnabled)
        #expect(harness.preferences.workoutAutoImportSince == nil)
        #expect(harness.client.isBackgroundDeliveryEnabled == false)
        #expect(harness.importer.message != nil)
    }

    @Test
    func disablingStopsBackgroundDeliveryAndClearsTheAnchor() async throws {
        let harness = try Self.makeHarness()
        await harness.importer.setEnabled(true)

        await harness.importer.setEnabled(false)

        #expect(!harness.importer.isEnabled)
        #expect(!harness.client.isBackgroundDeliveryEnabled)
        #expect(harness.preferences.workoutAutoImportSince == nil)
    }

    @Test
    func catchUpPassImportsNewWorkoutsOnce() async throws {
        let harness = try Self.makeHarness(
            autoImportEnabled: true,
            autoImportSince: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let workout = Self.makeWorkout(
            startedAt: harness.now.addingTimeInterval(-3_600)
        )
        Self.register(workout, on: harness.client)

        await harness.importer.runCatchUpPass()

        #expect(harness.importer.lastImportedCount == 1)
        let summaries = try harness.repository.fetchSummaries()
        #expect(summaries.count == 1)

        // A second pass over the same Health data must not duplicate the walk.
        await harness.importer.runCatchUpPass()
        #expect(try harness.repository.fetchSummaries().count == 1)
    }

    /// A walk ended on the phone finalises its workout locally while the watch
    /// is still transferring the location series, so the first pass sees no
    /// route. The walk must still pick one up once it arrives.
    @Test
    func routeArrivingAfterTheWorkoutIsBackfilled() async throws {
        let harness = try Self.makeHarness(
            autoImportEnabled: true,
            autoImportSince: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let workout = Self.makeWorkout(
            startedAt: harness.now.addingTimeInterval(-5_400),
            duration: 5_400
        )
        Self.register(workout, on: harness.client)

        await harness.importer.runCatchUpPass()

        let imported = try #require(try harness.repository.fetchSummaries().first)
        #expect(try harness.repository.fetchDetail(id: imported.id)?.trackPoints.isEmpty == true)

        // A pass before the route lands must not report progress it did not make.
        await harness.importer.runCatchUpPass()
        #expect(harness.importer.lastRouteBackfillCount == 0)

        harness.client.walkingWorkoutImports[workout.id] = HealthWalkingWorkoutImport(
            workout: workout,
            routePoints: Self.routePoints(for: workout)
        )

        await harness.importer.runCatchUpPass()

        #expect(harness.importer.lastRouteBackfillCount == 1)
        #expect(harness.importer.lastImportedCount == 0)
        let summaries = try harness.repository.fetchSummaries()
        #expect(summaries.count == 1, "backfill must repair the walk, not add one")
        let repaired = try #require(try harness.repository.fetchDetail(id: imported.id))
        #expect(repaired.trackPoints.count == 3)
        #expect(repaired.summary.routeQuality == .good)
        #expect(repaired.acceptedLocationCount == 3)
        #expect(repaired.altitudeSource == .location)
    }

    /// Pausing stops the watch recording locations, leaving a hole in the
    /// series. The map must break the line there rather than drawing straight
    /// across the pause.
    @Test
    func aPauseInAnImportedRouteBreaksTheDrawnLine() async throws {
        let harness = try Self.makeHarness(
            autoImportEnabled: true,
            autoImportSince: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let workout = Self.makeWorkout(
            startedAt: harness.now.addingTimeInterval(-5_400),
            duration: 5_400
        )
        let before = Self.routePoints(for: workout, count: 3)
        // Resumes well past the live recorder's segment gap.
        let after = Self.routePoints(for: workout, count: 3).map {
            NewTrackPoint(
                id: $0.id,
                timestamp: $0.timestamp.addingTimeInterval(900),
                latitude: $0.latitude,
                longitude: $0.longitude,
                altitude: $0.altitude,
                horizontalAccuracy: $0.horizontalAccuracy,
                verticalAccuracy: $0.verticalAccuracy,
                speed: $0.speed,
                speedAccuracy: $0.speedAccuracy,
                course: $0.course,
                courseAccuracy: $0.courseAccuracy,
                isAccepted: true,
                rejectionReason: nil,
                // Apple Health hands over no segment markers of its own.
                startsNewSegment: false
            )
        }
        Self.register(
            workout,
            on: harness.client,
            routePoints: before + after
        )

        await harness.importer.runCatchUpPass()

        let walkID = try #require(try harness.repository.fetchSummaries().first?.id)
        let detail = try #require(try harness.repository.fetchDetail(id: walkID))
        #expect(detail.routeSegments.count == 2)
        #expect(detail.routeSegments.map(\.count) == [3, 3])
    }

    @Test
    func aWalkThatAlreadyHasItsRouteIsLeftAlone() async throws {
        let harness = try Self.makeHarness(
            autoImportEnabled: true,
            autoImportSince: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let workout = Self.makeWorkout(
            startedAt: harness.now.addingTimeInterval(-3_600)
        )
        Self.register(
            workout,
            on: harness.client,
            routePoints: Self.routePoints(for: workout)
        )

        await harness.importer.runCatchUpPass()
        let imported = try #require(try harness.repository.fetchSummaries().first)
        let pointIDs = Set(
            try #require(try harness.repository.fetchDetail(id: imported.id))
                .trackPoints.map(\.id)
        )

        await harness.importer.runCatchUpPass()

        #expect(harness.importer.lastRouteBackfillCount == 0)
        #expect(try harness.repository.fetchSummaries().count == 1)
        let after = try #require(try harness.repository.fetchDetail(id: imported.id))
        #expect(Set(after.trackPoints.map(\.id)) == pointIDs)
    }

    @Test
    func catchUpPassIgnoresWorkoutsRecordedBeforeOptIn() async throws {
        let optInDate = Date(timeIntervalSince1970: 1_800_090_000)
        let harness = try Self.makeHarness(
            autoImportEnabled: true,
            autoImportSince: optInDate
        )
        Self.register(
            Self.makeWorkout(startedAt: optInDate.addingTimeInterval(-86_400)),
            on: harness.client
        )

        await harness.importer.runCatchUpPass()

        #expect(harness.importer.lastImportedCount == 0)
        #expect(try harness.repository.fetchSummaries().isEmpty)
    }

    @Test
    func catchUpPassDoesNothingWhileDisabled() async throws {
        let harness = try Self.makeHarness()
        Self.register(
            Self.makeWorkout(startedAt: harness.now.addingTimeInterval(-600)),
            on: harness.client
        )

        await harness.importer.runCatchUpPass()

        #expect(try harness.repository.fetchSummaries().isEmpty)
    }

    @Test
    func observedChangeImportsAndNotifiesTheHistoryStore() async throws {
        let harness = try Self.makeHarness()
        var refreshCount = 0
        harness.importer.onWalksImported = { refreshCount += 1 }

        await harness.importer.setEnabled(true)
        // Recorded at the opt-in instant, i.e. inside the window the toggle just
        // anchored — anything earlier is deliberately out of scope.
        Self.register(
            Self.makeWorkout(startedAt: harness.now),
            on: harness.client
        )

        // Resolves only once the importer acknowledges, which it does after the
        // pass completes — so the walk is already persisted here.
        await harness.client.emitWalkingWorkoutChange()

        #expect(try harness.repository.fetchSummaries().count == 1)
        #expect(refreshCount == 1)
    }
}
