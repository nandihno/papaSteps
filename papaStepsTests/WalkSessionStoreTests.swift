import Foundation
import Testing
@testable import papaSteps

@MainActor
struct WalkSessionStoreTests {
    @Test
    func lifecycleSupportsPauseKeepWalkingFinishAndReset() async {
        let coordinator = FakeWalkSessionCoordinator()
        let repository = RecordingWalkRepository()
        let store = makeStore(coordinator: coordinator, repository: repository)

        await store.start()
        await store.pause()
        await store.resume()
        store.requestFinish()
        store.keepWalking()
        store.requestFinish()
        await store.finish()
        await store.finish()

        #expect(store.state == .completed)
        #expect(repository.insertCallCount == 1)
        #expect(coordinator.finalizeCallCount == 1)
        #expect(store.completedSummary != nil)
        #expect(
            store.stateHistory == [
                .idle,
                .preparing,
                .active,
                .paused,
                .active,
                .finishCandidate,
                .active,
                .finishCandidate,
                .finalizing,
                .completed
            ]
        )

        await store.reset()
        #expect(store.state == .idle)
    }

    @Test
    func duplicateStartAndFinishCallsDoNotCreateDuplicateWalks() async {
        let coordinator = FakeWalkSessionCoordinator()
        let repository = RecordingWalkRepository()
        let store = makeStore(coordinator: coordinator, repository: repository)

        await store.start()
        await store.start()
        await store.finish()
        await store.finish()

        #expect(coordinator.prepareCallCount == 1)
        #expect(coordinator.finalizeCallCount == 1)
        #expect(repository.insertCallCount == 1)
        #expect(repository.records.count == 1)
    }

    @Test
    func pausedWalkCanFinishDirectly() async {
        let coordinator = FakeWalkSessionCoordinator()
        let repository = RecordingWalkRepository()
        let store = makeStore(coordinator: coordinator, repository: repository)

        await store.start()
        await store.pause()
        await store.finish()

        #expect(store.state == .completed)
        #expect(store.stateHistory.suffix(2) == [.finalizing, .completed])
    }

    @Test
    func discardFromFinishCandidateCreatesNoRecord() async {
        let coordinator = FakeWalkSessionCoordinator()
        let repository = RecordingWalkRepository()
        let store = makeStore(coordinator: coordinator, repository: repository)

        await store.start()
        store.requestFinish()
        await store.discard()

        #expect(store.state == .idle)
        #expect(repository.records.isEmpty)
        #expect(coordinator.discardCallCount == 1)
    }

    @Test
    func preparationFailureHasDiscardExit() async {
        let coordinator = FakeWalkSessionCoordinator(
            preparationError: .preparationFailed
        )
        let repository = RecordingWalkRepository()
        let store = makeStore(coordinator: coordinator, repository: repository)

        await store.start()
        #expect(store.state == .recoverableFailure)

        await store.discard()
        #expect(store.state == .idle)
    }

    @Test
    func preparationFailureCanRetryToActive() async {
        let coordinator = FakeWalkSessionCoordinator(
            preparationError: .preparationFailed
        )
        let repository = RecordingWalkRepository()
        let store = makeStore(coordinator: coordinator, repository: repository)

        await store.start()
        coordinator.resolvePreparationFailure()
        await store.retry()

        #expect(store.state == .active)
        #expect(coordinator.prepareCallCount == 2)
    }

    @Test
    func finalizationFailureHasDiscardExit() async {
        let coordinator = FakeWalkSessionCoordinator(
            finalizationError: .finalizationFailed
        )
        let repository = RecordingWalkRepository()
        let store = makeStore(coordinator: coordinator, repository: repository)

        await store.start()
        await store.finish()
        #expect(store.state == .recoverableFailure)

        await store.discard()
        #expect(store.state == .idle)
        #expect(repository.records.isEmpty)
    }

    @Test
    func finalizationFailureCanRetryWithoutDuplicatingRecord() async {
        let coordinator = FakeWalkSessionCoordinator(
            finalizationError: .finalizationFailed
        )
        let repository = RecordingWalkRepository()
        let store = makeStore(coordinator: coordinator, repository: repository)

        await store.start()
        await store.finish()
        coordinator.resolveFinalizationFailure()
        await store.retry()

        #expect(store.state == .completed)
        #expect(repository.records.count == 1)
        #expect(repository.insertCallCount == 1)
    }

    @Test
    func contextualStartRequestsUndeterminedPermissions() async {
        let coordinator = FakeWalkSessionCoordinator(
            permissionSnapshot: WalkPermissionSnapshot(
                motionAuthorization: .notDetermined,
                locationAuthorization: .notDetermined,
                locationAccuracy: .unknown,
                stepCountingAvailable: true,
                pedometerDistanceAvailable: true,
                relativeAltitudeAvailable: true,
                absoluteAltitudeAvailable: true
            )
        )
        let repository = RecordingWalkRepository()
        let store = makeStore(coordinator: coordinator, repository: repository)

        #expect(store.needsPermissionExplanation)
        await store.start(requestPermissions: true)

        #expect(store.state == .active)
        #expect(store.permissionSnapshot.motionAuthorization == .authorized)
        #expect(store.permissionSnapshot.locationAuthorization == .whenInUse)
    }

    @Test
    func interruptedDraftRequiresAnExplicitRecoveryChoice() async {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let checkpoint = WalkEngineCheckpoint.sample(id: UUID(), startDate: start)
        let coordinator = FakeWalkSessionCoordinator()
        let repository = RecordingWalkRepository(draft: checkpoint)
        let store = makeStore(coordinator: coordinator, repository: repository)

        #expect(store.state == .recoverableFailure)
        #expect(store.recoveredCheckpoint?.recoveryCause == .appRelaunched)
        #expect(repository.records.isEmpty)

        await store.resumeRecoveredWalk()
        #expect(store.state == .active)
        #expect(store.recoveredCheckpoint == nil)
        #expect(repository.records.isEmpty)
        #expect(coordinator.lastRestoreResumedSensors == true)
    }

    @Test
    func finishingRecoveredDraftCreatesExactlyOneCompletedRecord() async {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let checkpoint = WalkEngineCheckpoint.sample(id: UUID(), startDate: start)
        let coordinator = FakeWalkSessionCoordinator()
        let repository = RecordingWalkRepository(draft: checkpoint)
        let store = makeStore(coordinator: coordinator, repository: repository)

        await store.finishRecoveredWalk()

        #expect(store.state == .completed)
        #expect(repository.records.count == 1)
        #expect(repository.drafts.isEmpty)
        #expect(coordinator.finalizeCallCount == 1)
        #expect(coordinator.lastRestoreResumedSensors == false)
    }

    private func makeStore(
        coordinator: FakeWalkSessionCoordinator,
        repository: RecordingWalkRepository
    ) -> WalkSessionStore {
        WalkSessionStore(
            coordinator: coordinator,
            repository: repository,
            clock: FixedWalkClock(
                instant: Date(timeIntervalSince1970: 1_800_000_000)
            ),
            makeUUID: {
                UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
            }
        )
    }
}

private struct FixedWalkClock: WalkClock {
    let instant: Date

    func now() -> Date { instant }

    func ticks(every interval: TimeInterval) -> AsyncStream<Date> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

@MainActor
private final class RecordingWalkRepository: WalkRepository {
    private(set) var records: [UUID: NewWalkRecord] = [:]
    private(set) var drafts: [UUID: WalkEngineCheckpoint] = [:]
    private(set) var insertCallCount = 0

    init(draft: WalkEngineCheckpoint? = nil) {
        if let draft {
            drafts[draft.id] = draft
        }
    }

    func insert(_ newWalk: NewWalkRecord) throws -> WalkSummary {
        try complete(newWalk)
    }

    func complete(_ newWalk: NewWalkRecord) throws -> WalkSummary {
        insertCallCount += 1
        records[newWalk.id] = newWalk
        drafts[newWalk.id] = nil
        return summary(newWalk)
    }

    func saveDraft(_ checkpoint: WalkEngineCheckpoint) throws {
        drafts[checkpoint.id] = checkpoint
    }

    func fetchRecoverableDraft() throws -> WalkEngineCheckpoint? {
        drafts.values.first
    }

    func markDraftInterrupted(
        id: UUID,
        cause: WalkRecoveryCause
    ) throws -> WalkEngineCheckpoint? {
        guard var checkpoint = drafts[id] else { return nil }
        checkpoint.recoveryCause = cause
        drafts[id] = checkpoint
        return checkpoint
    }

    func fetchSummaries() throws -> [WalkSummary] {
        records.values.map(summary)
    }

    func importedHealthWorkoutIDs(in ids: Set<UUID>) throws -> Set<UUID> {
        []
    }

    func importHealthWorkout(
        _ importedWorkout: HealthWalkingWorkoutImport,
        importedAt: Date,
        fallbackTimeZoneIdentifier: String
    ) throws -> WalkSummary {
        throw HealthDataError.workoutNotFound
    }

    func updateHealthEnrichmentStatus(
        id: UUID,
        status: HealthEnrichmentStatus,
        errorMessage: String?
    ) throws {}

    func applyHealthEnrichment(
        id: UUID,
        enrichment: WalkHealthEnrichment
    ) throws -> WalkDetail? {
        nil
    }

    func updateWorkoutExport(
        id: UUID,
        status: HealthWorkoutExportStatus,
        workoutUUID: UUID?,
        errorMessage: String?
    ) throws -> WalkDetail? {
        nil
    }

    func deleteWalk(id: UUID) throws {
        records[id] = nil
        drafts[id] = nil
    }

    func deleteAllWalks() throws {
        records = [:]
        drafts = [:]
    }

    func fetchRoutePreview(id: UUID, maximumPoints: Int) throws -> [WalkCoordinate] {
        []
    }

    func fetchDetail(id: UUID) throws -> WalkDetail? {
        nil
    }

    private func summary(_ walk: NewWalkRecord) -> WalkSummary {
        WalkSummary(
            id: walk.id,
            startDate: walk.startDate,
            endDate: walk.endDate,
            timeZoneIdentifier: walk.timeZoneIdentifier,
            elapsedDuration: walk.elapsedDuration,
            movingDuration: walk.movingDuration,
            displayDistance: walk.displayDistance,
            distanceSource: walk.distanceSource,
            displaySteps: walk.displaySteps,
            stepSource: walk.stepSource,
            averageSpeed: walk.averageSpeed,
            elevationGain: walk.elevationGain,
            routeQuality: walk.routeQuality,
            routeQualityReason: walk.routeQualityReason,
            healthEnrichmentStatus: .notRequested,
            origin: .papaSteps,
            healthSourceName: nil
        )
    }
}
