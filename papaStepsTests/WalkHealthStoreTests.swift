import Foundation
import Testing
@testable import papaSteps

@MainActor
struct WalkHealthStoreTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func healthIsNotQueriedBeforeTheUserRequestsOptionalAccess() async throws {
        let setup = try makeSetup(insightsRequested: false)

        let detail = await setup.store.enrichWalk(id: setup.walkID)

        #expect(detail?.healthEnrichmentStatus == .notRequested)
        #expect(setup.client.enrichmentRequestCount == 0)
        #expect(try setup.repository.fetchSummaries().count == 1)
    }

    @Test
    func delayedSamplesRefreshTheExistingWalkWithoutCreatingADuplicate() async throws {
        let setup = try makeSetup(insightsRequested: true)

        let emptyDetail = await setup.store.enrichWalk(id: setup.walkID)
        #expect(emptyDetail?.averageHeartRate == nil)
        #expect(emptyDetail?.healthEnrichmentStatus == .completed)

        setup.client.heartRateObservations = [
            observation(source: "watch", name: "Apple Watch", value: 84),
            observation(source: "watch", name: "Apple Watch", value: 92, offset: 200)
        ]
        let refreshed = await setup.store.enrichWalk(id: setup.walkID)

        #expect(refreshed?.averageHeartRate == 88)
        #expect(refreshed?.heartRateSampleCount == 2)
        #expect(try setup.repository.fetchSummaries().count == 1)
        #expect(setup.client.enrichmentRequestCount == 2)
    }

    @Test
    func workoutRetryAdoptsMetadataMatchedWorkoutInsteadOfWritingAnother() async throws {
        let setup = try makeSetup(
            insightsRequested: true,
            workoutExportEnabled: true
        )
        let externallyCreated = setup.client.externallyCreateWorkout(for: setup.walkID)

        let firstRetry = await setup.store.enrichWalk(id: setup.walkID)
        let secondRetry = await setup.store.enrichWalk(id: setup.walkID)

        #expect(firstRetry?.healthKitWorkoutUUID == externallyCreated)
        #expect(secondRetry?.healthKitWorkoutUUID == externallyCreated)
        #expect(setup.client.workoutCreationCount == 1)
        #expect(setup.client.workoutEnsureCount == 2)
        #expect(setup.client.authorizationRequestCount == 2)
        #expect(secondRetry?.healthWorkoutExportStatus == .completed)
    }

    @Test
    func deniedWorkoutWriteExplainsPermissionProblemAndTurnsExportOff() async throws {
        let setup = try makeSetup(
            insightsRequested: true,
            workoutExportEnabled: true
        )
        setup.client.authorizationError = HealthDataError.workoutSharingDenied

        let detail = await setup.store.enrichWalk(id: setup.walkID)

        #expect(detail?.healthWorkoutExportStatus == .failed)
        #expect(detail?.healthWorkoutExportError?.contains("not allowing") == true)
        #expect(setup.store.workoutExportEnabled == false)
        #expect(setup.client.workoutEnsureCount == 0)
        #expect(detail?.summary.displayDistance == 780)
    }

    @Test
    func enrichmentFailureLeavesCoreMetricsIntactAndOffersRetry() async throws {
        let setup = try makeSetup(insightsRequested: true)
        setup.client.enrichmentError = HealthDataError.unavailable

        let detail = await setup.store.enrichWalk(id: setup.walkID)

        #expect(detail?.healthEnrichmentStatus == .failed)
        #expect(detail?.summary.displayDistance == 780)
        #expect(detail?.summary.displaySteps == 1_040)
        #expect(setup.store.lastMessage?.contains("Core walk data is unchanged") == true)
    }

    private func makeSetup(
        insightsRequested: Bool,
        workoutExportEnabled: Bool = false
    ) throws -> (
        store: WalkHealthStore,
        client: FakeHealthCapabilityClient,
        repository: SwiftDataWalkRepository,
        walkID: UUID
    ) {
        let container = try PersistenceContainer.make(isStoredInMemoryOnly: true)
        let repository = SwiftDataWalkRepository(modelContainer: container)
        let walk = NewWalkRecord.sample(startDate: start)
        _ = try repository.insert(walk)
        let client = FakeHealthCapabilityClient()
        let preferences = FakeHealthPreferences(
            insightsRequested: insightsRequested,
            workoutExportEnabled: workoutExportEnabled
        )
        let store = WalkHealthStore(
            client: client,
            preferences: preferences,
            repository: repository,
            now: { Date(timeIntervalSince1970: 1_800_001_000) }
        )
        return (store, client, repository, walk.id)
    }

    private func observation(
        source: String,
        name: String,
        value: Double,
        offset: TimeInterval = 0
    ) -> HealthQuantityObservation {
        HealthQuantityObservation(
            sourceIdentifier: source,
            sourceName: name,
            startDate: start.addingTimeInterval(offset),
            endDate: start.addingTimeInterval(offset + 120),
            value: value
        )
    }
}
