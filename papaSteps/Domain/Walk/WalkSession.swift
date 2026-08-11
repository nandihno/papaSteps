import Foundation
import Observation

enum WalkSessionState: String, CaseIterable, Sendable {
    case idle
    case preparing
    case active
    case paused
    case finishCandidate
    case finalizing
    case completed
    case recoverableFailure
}

enum WalkCoordinatorEvent: Equatable, Sendable {
    case finishCandidate
    case movementResumed
}

enum WalkSessionError: LocalizedError, Equatable, Sendable {
    case permissionsUnavailable
    case noActiveWalk
    case preparationFailed
    case finalizationFailed

    var errorDescription: String? {
        switch self {
        case .permissionsUnavailable:
            "Motion or Location access is needed to record a useful walk."
        case .noActiveWalk:
            "There is no active walk to finish."
        case .preparationFailed:
            "The walk could not be prepared."
        case .finalizationFailed:
            "The walk could not be saved."
        }
    }
}

@MainActor
protocol WalkSessionCoordinating: AnyObject {
    var updates: AsyncStream<WalkMetricsSnapshot> { get }
    var checkpoints: AsyncStream<WalkEngineCheckpoint> { get }
    var events: AsyncStream<WalkCoordinatorEvent> { get }
    var permissionSnapshot: WalkPermissionSnapshot { get }

    func prepare(
        id: UUID,
        startDate: Date,
        timeZoneIdentifier: String,
        requestPermissions: Bool
    ) async throws
    func pause(at date: Date) async
    func resume(at date: Date) async
    func reconcile(at date: Date) async
    func requestTemporaryFullAccuracy(at date: Date) async
    func checkpoint(at date: Date) async throws -> WalkEngineCheckpoint
    func restore(
        from checkpoint: WalkEngineCheckpoint,
        at date: Date,
        resumeSensors: Bool
    ) async
    func finalize(at date: Date) async throws -> NewWalkRecord
    func suppressFinishCandidate(at date: Date)
    func discard() async
}

@MainActor
final class FakeWalkSessionCoordinator: WalkSessionCoordinating {
    private var preparationError: WalkSessionError?
    private var finalizationError: WalkSessionError?
    private let stream: AsyncStream<WalkMetricsSnapshot>
    private let continuation: AsyncStream<WalkMetricsSnapshot>.Continuation
    private let checkpointStream: AsyncStream<WalkEngineCheckpoint>
    private let checkpointContinuation: AsyncStream<WalkEngineCheckpoint>.Continuation
    private let eventStream: AsyncStream<WalkCoordinatorEvent>
    private let eventContinuation: AsyncStream<WalkCoordinatorEvent>.Continuation
    private var preparedID: UUID?
    private var preparedStartDate: Date?
    private var cachedRecord: NewWalkRecord?

    private(set) var prepareCallCount = 0
    private(set) var finalizeCallCount = 0
    private(set) var discardCallCount = 0
    private(set) var lastRestoreResumedSensors: Bool?

    var permissionSnapshot: WalkPermissionSnapshot

    init(
        preparationError: WalkSessionError? = nil,
        finalizationError: WalkSessionError? = nil,
        permissionSnapshot: WalkPermissionSnapshot = WalkPermissionSnapshot(
            motionAuthorization: .authorized,
            locationAuthorization: .whenInUse,
            locationAccuracy: .full,
            stepCountingAvailable: true,
            pedometerDistanceAvailable: true,
            relativeAltitudeAvailable: true,
            absoluteAltitudeAvailable: true
        )
    ) {
        let updates = AsyncStream<WalkMetricsSnapshot>.makeStream()
        let checkpoints = AsyncStream<WalkEngineCheckpoint>.makeStream()
        let events = AsyncStream<WalkCoordinatorEvent>.makeStream()
        stream = updates.stream
        continuation = updates.continuation
        checkpointStream = checkpoints.stream
        checkpointContinuation = checkpoints.continuation
        eventStream = events.stream
        eventContinuation = events.continuation
        self.preparationError = preparationError
        self.finalizationError = finalizationError
        self.permissionSnapshot = permissionSnapshot
    }

    var updates: AsyncStream<WalkMetricsSnapshot> {
        stream
    }

    var checkpoints: AsyncStream<WalkEngineCheckpoint> {
        checkpointStream
    }

    var events: AsyncStream<WalkCoordinatorEvent> {
        eventStream
    }

    func emit(_ event: WalkCoordinatorEvent) {
        eventContinuation.yield(event)
    }

    func resolvePreparationFailure() {
        preparationError = nil
    }

    func resolveFinalizationFailure() {
        finalizationError = nil
    }

    func prepare(
        id: UUID,
        startDate: Date,
        timeZoneIdentifier: String,
        requestPermissions: Bool
    ) async throws {
        prepareCallCount += 1
        if let preparationError {
            throw preparationError
        }
        if requestPermissions {
            permissionSnapshot = WalkPermissionSnapshot(
                motionAuthorization: permissionSnapshot.motionAuthorization == .notDetermined
                    ? .authorized : permissionSnapshot.motionAuthorization,
                locationAuthorization: permissionSnapshot.locationAuthorization == .notDetermined
                    ? .whenInUse : permissionSnapshot.locationAuthorization,
                locationAccuracy: permissionSnapshot.locationAccuracy == .unknown
                    ? .full : permissionSnapshot.locationAccuracy,
                stepCountingAvailable: permissionSnapshot.stepCountingAvailable,
                pedometerDistanceAvailable: permissionSnapshot.pedometerDistanceAvailable,
                relativeAltitudeAvailable: permissionSnapshot.relativeAltitudeAvailable,
                absoluteAltitudeAvailable: permissionSnapshot.absoluteAltitudeAvailable
            )
        }
        preparedID = id
        preparedStartDate = startDate
        continuation.yield(.empty)
        checkpointContinuation.yield(
            .sample(id: id, startDate: startDate)
        )
    }

    func pause(at date: Date) async {}

    func resume(at date: Date) async {}

    func reconcile(at date: Date) async {}

    func requestTemporaryFullAccuracy(at date: Date) async {
        permissionSnapshot = WalkPermissionSnapshot(
            motionAuthorization: permissionSnapshot.motionAuthorization,
            locationAuthorization: permissionSnapshot.locationAuthorization,
            locationAccuracy: .full,
            stepCountingAvailable: permissionSnapshot.stepCountingAvailable,
            pedometerDistanceAvailable: permissionSnapshot.pedometerDistanceAvailable,
            relativeAltitudeAvailable: permissionSnapshot.relativeAltitudeAvailable,
            absoluteAltitudeAvailable: permissionSnapshot.absoluteAltitudeAvailable
        )
    }

    func checkpoint(at date: Date) async throws -> WalkEngineCheckpoint {
        guard let preparedID, let preparedStartDate else {
            throw WalkSessionError.noActiveWalk
        }
        return .sample(id: preparedID, startDate: preparedStartDate)
    }

    func restore(
        from checkpoint: WalkEngineCheckpoint,
        at date: Date,
        resumeSensors: Bool
    ) async {
        preparedID = checkpoint.id
        preparedStartDate = checkpoint.startDate
        lastRestoreResumedSensors = resumeSensors
        continuation.yield(.empty)
    }

    func finalize(at date: Date) async throws -> NewWalkRecord {
        finalizeCallCount += 1
        if let finalizationError {
            throw finalizationError
        }
        if let cachedRecord {
            return cachedRecord
        }
        guard let preparedID, let preparedStartDate else {
            throw WalkSessionError.noActiveWalk
        }
        let record = NewWalkRecord.sample(id: preparedID, startDate: preparedStartDate)
        cachedRecord = record
        return record
    }

    func suppressFinishCandidate(at date: Date) {}

    func discard() async {
        discardCallCount += 1
        preparedID = nil
        preparedStartDate = nil
        cachedRecord = nil
        continuation.yield(.empty)
    }
}

@MainActor
@Observable
final class WalkSessionStore {
    private enum RecoveryAction {
        case prepare
        case finalize
    }

    private(set) var state: WalkSessionState = .idle
    private(set) var stateHistory: [WalkSessionState] = [.idle]
    private(set) var metrics: WalkMetricsSnapshot = .empty
    private(set) var permissionSnapshot: WalkPermissionSnapshot
    private(set) var completedSummary: WalkSummary?
    private(set) var completedDetail: WalkDetail?
    private(set) var recoveredCheckpoint: WalkEngineCheckpoint?
    private(set) var lastErrorMessage: String?
    private(set) var notificationAuthorizationState: WalkNotificationAuthorizationState
    private(set) var finishRemindersEnabled: Bool

    private let coordinator: any WalkSessionCoordinating
    private let repository: any WalkRepository
    private let healthStore: WalkHealthStore?
    private let liveActivityClient: any WalkLiveActivityProviding
    private let notificationClient: any WalkNotificationProviding
    private let reminderPreferences: any WalkReminderPreferences
    private let clock: any WalkClock
    private let makeUUID: @Sendable () -> UUID
    private var metricsTask: Task<Void, Never>?
    private var checkpointTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var finishCandidateOrigin: WalkSessionState?
    private var recoveryAction: RecoveryAction?
    private var activeWalkID: UUID?
    private var activeWalkStartDate: Date?

    init(
        coordinator: any WalkSessionCoordinating,
        repository: any WalkRepository,
        healthStore: WalkHealthStore? = nil,
        liveActivityClient: any WalkLiveActivityProviding = FakeWalkLiveActivityClient(),
        notificationClient: any WalkNotificationProviding = FakeWalkNotificationClient(),
        reminderPreferences: any WalkReminderPreferences = FakeWalkReminderPreferences(),
        clock: any WalkClock = SystemWalkClock(),
        makeUUID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.coordinator = coordinator
        self.repository = repository
        self.healthStore = healthStore
        self.liveActivityClient = liveActivityClient
        self.notificationClient = notificationClient
        self.reminderPreferences = reminderPreferences
        self.clock = clock
        self.makeUUID = makeUUID
        permissionSnapshot = coordinator.permissionSnapshot
        notificationAuthorizationState = .notDetermined
        finishRemindersEnabled = reminderPreferences.finishRemindersEnabled

        if let draft = try? repository.fetchRecoverableDraft() {
            let cause = recoveryCause(for: draft, permissions: permissionSnapshot)
            recoveredCheckpoint = (
                try? repository.markDraftInterrupted(id: draft.id, cause: cause)
            ) ?? draft
            activeWalkID = draft.id
            activeWalkStartDate = draft.startDate
            lastErrorMessage = cause.explanation
            state = .recoverableFailure
            stateHistory = [.recoverableFailure]
        }
    }

    var needsPermissionExplanation: Bool {
        permissionSnapshot.needsExplanation
    }

    var canOpenSettings: Bool {
        permissionSnapshot.motionAuthorization == .denied
            || permissionSnapshot.locationAuthorization == .denied
    }

    func start(requestPermissions: Bool = true) async {
        guard state == .idle else { return }
        observeMetricsIfNeeded()
        observeCheckpointsIfNeeded()
        observeCoordinatorEventsIfNeeded()
        clearTransientState()
        transition(to: .preparing)

        do {
            let walkID = makeUUID()
            let startDate = clock.now()
            activeWalkID = walkID
            activeWalkStartDate = startDate
            try await coordinator.prepare(
                id: walkID,
                startDate: startDate,
                timeZoneIdentifier: TimeZone.current.identifier,
                requestPermissions: requestPermissions
            )
            permissionSnapshot = coordinator.permissionSnapshot
            transition(to: .active)
            await liveActivityClient.start(
                walkID: walkID,
                startDate: startDate,
                state: state,
                metrics: metrics
            )
        } catch {
            permissionSnapshot = coordinator.permissionSnapshot
            lastErrorMessage = userMessage(for: error)
            recoveryAction = .prepare
            transition(to: .recoverableFailure)
        }
    }

    func pause() async {
        guard state == .active else { return }
        transition(to: .paused)
        await coordinator.pause(at: clock.now())
        await persistCurrentCheckpoint()
        await syncLiveActivity(force: true)
    }

    func resume() async {
        guard state == .paused else { return }
        await coordinator.resume(at: clock.now())
        await persistCurrentCheckpoint()
        transition(to: .active)
        await syncLiveActivity(force: true)
    }

    func requestFinish() {
        guard state == .active || state == .paused else { return }
        finishCandidateOrigin = state
        transition(to: .finishCandidate)
        Task { [weak self] in
            await self?.syncLiveActivity(force: true)
        }
    }

    func keepWalking() {
        guard state == .finishCandidate else { return }
        coordinator.suppressFinishCandidate(at: clock.now())
        transition(to: finishCandidateOrigin ?? .active)
        finishCandidateOrigin = nil
        let walkID = activeWalkID
        Task { [weak self] in
            guard let self else { return }
            if let walkID {
                await notificationClient.cancelFinishPrompt(for: walkID)
            }
            await syncLiveActivity(force: true)
        }
    }

    func finish() async {
        guard state == .active
            || state == .paused
            || state == .finishCandidate else {
            return
        }
        transition(to: .finalizing)
        if let walkID = activeWalkID {
            await notificationClient.cancelFinishPrompt(for: walkID)
        }
        await syncLiveActivity(force: true)
        await finalizeCurrentWalk()
    }

    func discard() async {
        guard state == .active
            || state == .paused
            || state == .finishCandidate
            || state == .recoverableFailure else {
            return
        }
        let walkID = activeWalkID ?? recoveredCheckpoint?.id
        await coordinator.discard()
        if let walkID {
            try? repository.deleteWalk(id: walkID)
            await notificationClient.cancelFinishPrompt(for: walkID)
            await liveActivityClient.end(
                walkID: walkID,
                metrics: metrics,
                reason: .discarded
            )
        }
        clearSessionState()
        transition(to: .idle)
    }

    func retry() async {
        guard state == .recoverableFailure, let recoveryAction else { return }
        lastErrorMessage = nil

        switch recoveryAction {
        case .prepare:
            await coordinator.discard()
            transition(to: .idle)
            await start(requestPermissions: true)
        case .finalize:
            transition(to: .finalizing)
            await finalizeCurrentWalk()
        }
    }

    func reset() async {
        guard state == .completed else { return }
        await coordinator.discard()
        clearSessionState()
        transition(to: .idle)
    }

    func resumeRecoveredWalk() async {
        guard state == .recoverableFailure,
              let checkpoint = recoveredCheckpoint else {
            return
        }
        observeMetricsIfNeeded()
        observeCheckpointsIfNeeded()
        observeCoordinatorEventsIfNeeded()
        lastErrorMessage = nil
        activeWalkID = checkpoint.id
        activeWalkStartDate = checkpoint.startDate
        await coordinator.restore(
            from: checkpoint,
            at: clock.now(),
            resumeSensors: true
        )
        recoveredCheckpoint = nil
        transition(to: .active)
        await liveActivityClient.start(
            walkID: checkpoint.id,
            startDate: checkpoint.startDate,
            state: state,
            metrics: metrics
        )
    }

    func finishRecoveredWalk() async {
        guard state == .recoverableFailure,
              let checkpoint = recoveredCheckpoint else {
            return
        }
        observeMetricsIfNeeded()
        observeCoordinatorEventsIfNeeded()
        activeWalkID = checkpoint.id
        activeWalkStartDate = checkpoint.startDate
        await coordinator.restore(
            from: checkpoint,
            at: checkpoint.lastCheckpointDate,
            resumeSensors: false
        )
        recoveredCheckpoint = nil
        transition(to: .finalizing)
        await liveActivityClient.start(
            walkID: checkpoint.id,
            startDate: checkpoint.startDate,
            state: state,
            metrics: metrics
        )
        await finalizeCurrentWalk(at: checkpoint.lastCheckpointDate)
    }

    func reconcileAfterForeground() async {
        refreshPermissionSnapshot()
        guard state == .active || state == .paused || state == .finishCandidate else {
            return
        }
        await coordinator.reconcile(at: clock.now())
        await syncLiveActivity(force: true)
    }

    func checkpointBeforeBackground() async {
        guard state == .active || state == .paused || state == .finishCandidate else {
            return
        }
        await persistCurrentCheckpoint()
        await syncLiveActivity(force: true)
    }

    func requestTemporaryFullAccuracy() async {
        await coordinator.requestTemporaryFullAccuracy(at: clock.now())
        refreshPermissionSnapshot()
    }

    func refreshCompletedHealth() async {
        guard let healthStore, let walkID = completedSummary?.id,
              let detail = await healthStore.enrichWalk(id: walkID) else {
            return
        }
        completedDetail = detail
        completedSummary = detail.summary
    }

    func refreshPermissionSnapshot() {
        permissionSnapshot = coordinator.permissionSnapshot
    }

    func refreshExternalExperienceState() async {
        notificationAuthorizationState = await notificationClient.authorizationState()
        if notificationAuthorizationState == .denied, finishRemindersEnabled {
            finishRemindersEnabled = false
            reminderPreferences.finishRemindersEnabled = false
        }
        await liveActivityClient.endOrphanedActivities(except: activeWalkID)
        if state == .active || state == .paused || state == .finishCandidate
            || state == .recoverableFailure,
           let walkID = activeWalkID,
           let startDate = activeWalkStartDate {
            await liveActivityClient.start(
                walkID: walkID,
                startDate: startDate,
                state: state,
                metrics: metrics
            )
        }
    }

    func setFinishRemindersEnabled(_ enabled: Bool) async {
        if enabled {
            let state = await notificationClient.authorizationState()
            var allowed = state == .authorized
            if !allowed, state == .notDetermined {
                allowed = await notificationClient.requestAuthorization()
            }
            notificationAuthorizationState = allowed ? .authorized : .denied
            finishRemindersEnabled = allowed
            reminderPreferences.finishRemindersEnabled = allowed
        } else {
            finishRemindersEnabled = false
            reminderPreferences.finishRemindersEnabled = false
            if let walkID = activeWalkID {
                await notificationClient.cancelFinishPrompt(for: walkID)
            }
            notificationAuthorizationState = await notificationClient.authorizationState()
        }
    }

    func performExternalAction(_ request: WalkActivityActionRequest) async {
        guard request.walkID == activeWalkID else { return }
        switch request.action {
        case .pause:
            await pause()
        case .resume:
            await resume()
        case .finish:
            if state == .recoverableFailure, recoveredCheckpoint?.id == request.walkID {
                await finishRecoveredWalk()
            } else {
                await finish()
            }
        case .keepWalking:
            keepWalking()
        }
    }

    private func finalizeCurrentWalk(at finalDate: Date? = nil) async {
        do {
            let record = try await coordinator.finalize(at: finalDate ?? clock.now())
            completedSummary = try repository.complete(record)
            completedDetail = try repository.fetchDetail(id: record.id)
            activeWalkID = nil
            recoveryAction = nil
            finishCandidateOrigin = nil
            transition(to: .completed)
            await liveActivityClient.end(
                walkID: record.id,
                metrics: metrics,
                reason: .completed
            )
            if let healthStore {
                let walkID = record.id
                Task { [weak self] in
                    guard let detail = await healthStore.enrichWalk(id: walkID),
                          let self,
                          self.completedSummary?.id == walkID else {
                        return
                    }
                    self.completedDetail = detail
                    self.completedSummary = detail.summary
                }
            }
        } catch {
            lastErrorMessage = userMessage(for: error)
            recoveryAction = .finalize
            transition(to: .recoverableFailure)
            await syncLiveActivity(force: true)
        }
    }

    private func observeMetricsIfNeeded() {
        guard metricsTask == nil else { return }
        let updates = coordinator.updates
        metricsTask = Task { [weak self] in
            for await snapshot in updates {
                guard let self, !Task.isCancelled else { break }
                self.metrics = snapshot
                await self.syncLiveActivity(force: false)
            }
        }
    }

    private func observeCheckpointsIfNeeded() {
        guard checkpointTask == nil else { return }
        let checkpoints = coordinator.checkpoints
        checkpointTask = Task { [weak self] in
            for await checkpoint in checkpoints {
                guard let self, !Task.isCancelled else { break }
                do {
                    try self.repository.saveDraft(checkpoint)
                    self.activeWalkID = checkpoint.id
                } catch {
                    self.lastErrorMessage = "The latest walk checkpoint could not be saved. Recording is still active."
                }
            }
        }
    }

    private func observeCoordinatorEventsIfNeeded() {
        guard eventTask == nil else { return }
        let events = coordinator.events
        eventTask = Task { [weak self] in
            for await event in events {
                guard let self, !Task.isCancelled else { break }
                await self.handleCoordinatorEvent(event)
            }
        }
    }

    private func handleCoordinatorEvent(_ event: WalkCoordinatorEvent) async {
        switch event {
        case .finishCandidate:
            guard state == .active || state == .paused else { return }
            finishCandidateOrigin = state
            transition(to: .finishCandidate)
            await syncLiveActivity(force: true)
            if finishRemindersEnabled, let walkID = activeWalkID {
                await notificationClient.scheduleFinishPrompt(for: walkID)
            }
        case .movementResumed:
            guard state == .finishCandidate else { return }
            transition(to: finishCandidateOrigin ?? .active)
            finishCandidateOrigin = nil
            if let walkID = activeWalkID {
                await notificationClient.cancelFinishPrompt(for: walkID)
            }
            await syncLiveActivity(force: true)
        }
    }

    private func syncLiveActivity(force: Bool) async {
        guard let walkID = activeWalkID else { return }
        await liveActivityClient.update(
            walkID: walkID,
            state: state,
            metrics: metrics,
            force: force
        )
    }

    private func persistCurrentCheckpoint() async {
        guard let checkpoint = try? await coordinator.checkpoint(at: clock.now()) else {
            return
        }
        do {
            try repository.saveDraft(checkpoint)
            activeWalkID = checkpoint.id
        } catch {
            lastErrorMessage = "The latest walk checkpoint could not be saved. Recording is still active."
        }
    }

    private func clearTransientState() {
        completedSummary = nil
        completedDetail = nil
        lastErrorMessage = nil
        recoveryAction = nil
        finishCandidateOrigin = nil
    }

    private func clearSessionState() {
        metrics = .empty
        recoveredCheckpoint = nil
        activeWalkID = nil
        activeWalkStartDate = nil
        clearTransientState()
    }

    private func userMessage(for error: any Error) -> String {
        if let localizedError = error as? any LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return "The walk could not be completed. Please try again."
    }

    private func transition(to newState: WalkSessionState) {
        state = newState
        stateHistory.append(newState)
    }

    private func recoveryCause(
        for checkpoint: WalkEngineCheckpoint,
        permissions: WalkPermissionSnapshot
    ) -> WalkRecoveryCause {
        if checkpoint.locationAccuracy == .full,
           (!permissions.locationAuthorization.permitsLocation
            || permissions.locationAccuracy == .reduced) {
            return .locationAccessChanged
        }
        if permissions.motionAuthorization == .denied
            || permissions.motionAuthorization == .restricted {
            return .motionAccessChanged
        }
        return checkpoint.recoveryCause ?? .appRelaunched
    }
}
