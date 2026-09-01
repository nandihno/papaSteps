import Foundation
import Testing
@testable import papaSteps

@MainActor
struct Phase4LifecycleTests {
    @Test
    func foregroundReconciliationDoesNotStartDuplicateSensorStreams() async throws {
        let motion = FakeMotionCapabilityClient()
        let location = FakeLocationCapabilityClient()
        let coordinator = LiveWalkSessionCoordinator(
            motionClient: motion,
            locationClient: location,
            clock: Phase4FixedClock()
        )
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        try await coordinator.prepare(
            id: UUID(),
            startDate: start,
            timeZoneIdentifier: "Australia/Melbourne",
            requestPermissions: false
        )
        await coordinator.reconcile(at: start.addingTimeInterval(60))
        await coordinator.reconcile(at: start.addingTimeInterval(120))

        #expect(motion.startWalkUpdatesCallCount == 1)
        #expect(location.startWalkUpdatesCallCount == 1)
        await coordinator.discard()
    }

    @Test
    func finishCandidateSchedulesOnceAndMovementCancelsIt() async throws {
        let coordinator = FakeWalkSessionCoordinator()
        let repository = Phase4RecordingWalkRepository()
        let liveActivity = FakeWalkLiveActivityClient()
        let notifications = FakeWalkNotificationClient()
        let reminders = FakeWalkReminderPreferences(finishRemindersEnabled: true)
        let store = WalkSessionStore(
            coordinator: coordinator,
            repository: repository,
            liveActivityClient: liveActivity,
            notificationClient: notifications,
            reminderPreferences: reminders,
            clock: Phase4FixedClock(),
            makeUUID: { Phase4RecordingWalkRepository.walkID }
        )

        await store.start()
        coordinator.emit(.finishCandidate)
        await waitUntil { store.state == .finishCandidate }

        #expect(store.state == .finishCandidate)
        #expect(notifications.scheduledWalkIDs == [Phase4RecordingWalkRepository.walkID])

        coordinator.emit(.finishCandidate)
        coordinator.emit(.movementResumed)
        await waitUntil { store.state == .active }

        #expect(notifications.scheduledWalkIDs.count == 1)
        #expect(store.state == .active)
        #expect(notifications.cancelledWalkIDs.last == Phase4RecordingWalkRepository.walkID)
    }

    @Test
    func lockScreenActionsUseTheStateMachineAndFinalizeOnce() async {
        let coordinator = FakeWalkSessionCoordinator()
        let repository = Phase4RecordingWalkRepository()
        let liveActivity = FakeWalkLiveActivityClient()
        let store = WalkSessionStore(
            coordinator: coordinator,
            repository: repository,
            liveActivityClient: liveActivity,
            clock: Phase4FixedClock(),
            makeUUID: { Phase4RecordingWalkRepository.walkID }
        )

        await store.start()
        await store.performExternalAction(
            WalkActivityActionRequest(
                walkID: Phase4RecordingWalkRepository.walkID,
                action: .pause
            )
        )
        #expect(store.state == .paused)

        await store.performExternalAction(
            WalkActivityActionRequest(
                walkID: Phase4RecordingWalkRepository.walkID,
                action: .resume
            )
        )
        #expect(store.state == .active)

        let request = WalkActivityActionRequest(
            walkID: Phase4RecordingWalkRepository.walkID,
            action: .finish
        )
        await store.performExternalAction(request)
        await store.performExternalAction(request)

        #expect(store.state == .completed)
        #expect(coordinator.finalizeCallCount == 1)
        #expect(repository.completeCallCount == 1)
        #expect(liveActivity.endCallCount == 1)
    }

    @Test
    func relaunchMarksTheSurvivingActivityAsInterrupted() async throws {
        let repository = Phase4RecordingWalkRepository()
        let checkpoint = WalkEngineCheckpoint.sample(
            id: Phase4RecordingWalkRepository.walkID,
            startDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
        try repository.saveDraft(checkpoint)
        let liveActivity = FakeWalkLiveActivityClient()
        let store = WalkSessionStore(
            coordinator: FakeWalkSessionCoordinator(),
            repository: repository,
            liveActivityClient: liveActivity,
            clock: Phase4FixedClock()
        )

        #expect(store.state == .recoverableFailure)
        await store.refreshExternalExperienceState()

        #expect(liveActivity.startCallCount == 1)
        #expect(liveActivity.lastState == .recoverableFailure)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

private struct Phase4FixedClock: WalkClock {
    let instant = Date(timeIntervalSince1970: 1_800_000_000)

    func now() -> Date { instant }

    func ticks(every interval: TimeInterval) -> AsyncStream<Date> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

@MainActor
private final class Phase4RecordingWalkRepository: WalkRepository {
    nonisolated static let walkID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4))
    private(set) var completeCallCount = 0
    private var drafts: [UUID: WalkEngineCheckpoint] = [:]

    func insert(_ newWalk: NewWalkRecord) throws -> WalkSummary {
        try complete(newWalk)
    }

    func complete(_ newWalk: NewWalkRecord) throws -> WalkSummary {
        completeCallCount += 1
        drafts[newWalk.id] = nil
        return WalkSummary(
            id: newWalk.id,
            startDate: newWalk.startDate,
            endDate: newWalk.endDate,
            timeZoneIdentifier: newWalk.timeZoneIdentifier,
            elapsedDuration: newWalk.elapsedDuration,
            movingDuration: newWalk.movingDuration,
            displayDistance: newWalk.displayDistance,
            distanceSource: newWalk.distanceSource,
            displaySteps: newWalk.displaySteps,
            stepSource: newWalk.stepSource,
            averageSpeed: newWalk.averageSpeed,
            elevationGain: newWalk.elevationGain,
            routeQuality: newWalk.routeQuality,
            routeQualityReason: newWalk.routeQualityReason,
            healthEnrichmentStatus: .notRequested,
            origin: .papaSteps,
            healthSourceName: nil
        )
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
        drafts[id]
    }
    func fetchSummaries() throws -> [WalkSummary] { [] }
    func fetchRoutePreview(id: UUID, maximumPoints: Int) throws -> [WalkCoordinate] {
        []
    }

    func fetchDetail(id: UUID) throws -> WalkDetail? { nil }
    func importedHealthWorkoutIDs(in ids: Set<UUID>) throws -> Set<UUID> { [] }
    func healthWorkoutIDsAwaitingRoute(in ids: Set<UUID>) throws -> Set<UUID> { [] }
    func importHealthWorkout(
        _ importedWorkout: HealthWalkingWorkoutImport,
        importedAt: Date,
        fallbackTimeZoneIdentifier: String
    ) throws -> WalkSummary { throw HealthDataError.workoutNotFound }
    func updateHealthEnrichmentStatus(
        id: UUID,
        status: HealthEnrichmentStatus,
        errorMessage: String?
    ) throws {}
    func applyHealthEnrichment(
        id: UUID,
        enrichment: WalkHealthEnrichment
    ) throws -> WalkDetail? { nil }
    func updateWorkoutExport(
        id: UUID,
        status: HealthWorkoutExportStatus,
        workoutUUID: UUID?,
        errorMessage: String?
    ) throws -> WalkDetail? { nil }
    func deleteWalk(id: UUID) throws { drafts[id] = nil }
    func deleteAllWalks() throws { drafts = [:] }
}
