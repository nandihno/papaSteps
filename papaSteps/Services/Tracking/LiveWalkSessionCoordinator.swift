import Foundation

@MainActor
final class LiveWalkSessionCoordinator: WalkSessionCoordinating {
    private let motionClient: any WalkMotionProviding
    private let locationClient: any WalkLocationProviding
    private let engine: WalkMetricsEngine
    private let clock: any WalkClock
    private let configuration: TrackingConfiguration

    private let updateStream: AsyncStream<WalkMetricsSnapshot>
    private let updateContinuation: AsyncStream<WalkMetricsSnapshot>.Continuation
    private let checkpointStream: AsyncStream<WalkEngineCheckpoint>
    private let checkpointContinuation: AsyncStream<WalkEngineCheckpoint>.Continuation
    private let eventStream: AsyncStream<WalkCoordinatorEvent>
    private let eventContinuation: AsyncStream<WalkCoordinatorEvent>.Continuation
    private var motionTask: Task<Void, Never>?
    private var locationTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var sessionStartDate: Date?
    private var lastCheckpointDate: Date?
    private var cachedFinalRecord: NewWalkRecord?
    private var isReconciling = false
    private var lastPersistedAcceptedPointCount = 0
    private var latestMotionActivity: WalkMotionActivitySample?
    private var stopDetector: LikelyStopDetector

    init(
        motionClient: any WalkMotionProviding,
        locationClient: any WalkLocationProviding,
        configuration: TrackingConfiguration = .live,
        clock: any WalkClock = SystemWalkClock()
    ) {
        let stream = AsyncStream<WalkMetricsSnapshot>.makeStream()
        let checkpoints = AsyncStream<WalkEngineCheckpoint>.makeStream()
        let events = AsyncStream<WalkCoordinatorEvent>.makeStream()
        updateStream = stream.stream
        updateContinuation = stream.continuation
        checkpointStream = checkpoints.stream
        checkpointContinuation = checkpoints.continuation
        eventStream = events.stream
        eventContinuation = events.continuation
        self.motionClient = motionClient
        self.locationClient = locationClient
        self.configuration = configuration
        self.clock = clock
        engine = WalkMetricsEngine(configuration: configuration)
        stopDetector = LikelyStopDetector(configuration: configuration)
    }

    var updates: AsyncStream<WalkMetricsSnapshot> {
        updateStream
    }

    var checkpoints: AsyncStream<WalkEngineCheckpoint> {
        checkpointStream
    }

    var events: AsyncStream<WalkCoordinatorEvent> {
        eventStream
    }

    var permissionSnapshot: WalkPermissionSnapshot {
        let location = locationClient.snapshot
        return WalkPermissionSnapshot(
            motionAuthorization: motionClient.authorizationState,
            locationAuthorization: location.authorization,
            locationAccuracy: location.accuracy,
            stepCountingAvailable: motionClient.stepCountingAvailable,
            pedometerDistanceAvailable: motionClient.pedometerDistanceAvailable,
            relativeAltitudeAvailable: motionClient.relativeAltitudeAvailable,
            absoluteAltitudeAvailable: motionClient.absoluteAltitudeAvailable
        )
    }

    func prepare(
        id: UUID,
        startDate: Date,
        timeZoneIdentifier: String,
        requestPermissions: Bool
    ) async throws {
        guard sessionStartDate == nil else { return }

        if requestPermissions {
            await requestNeededPermissions()
        }

        guard permissionSnapshot.hasUsableTrackingSource else {
            throw WalkSessionError.permissionsUnavailable
        }

        sessionStartDate = startDate
        lastCheckpointDate = startDate
        cachedFinalRecord = nil
        lastPersistedAcceptedPointCount = 0
        latestMotionActivity = nil
        stopDetector.start()

        let initial = await engine.start(
            id: id,
            at: startDate,
            timeZoneIdentifier: timeZoneIdentifier
        )
        emit(initial)
        startSensorTasks(from: startDate)
        await publishCheckpoint(at: startDate)
    }

    func pause(at date: Date) async {
        await reconcilePedometer(at: date)
        emit(await engine.pause(at: date))
        await publishCheckpoint(at: date)
    }

    func resume(at date: Date) async {
        await reconcilePedometer(at: date)
        emit(await engine.resume(at: date))
        await publishCheckpoint(at: date)
    }

    func reconcile(at date: Date) async {
        await reconcilePedometer(at: date)
        emit(await engine.currentSnapshot(at: date))
    }

    func requestTemporaryFullAccuracy(at date: Date) async {
        await locationClient.requestTemporaryFullAccuracy()
        let location = locationClient.snapshot
        emit(
            await engine.updateLocationAuthorization(
                location.authorization,
                accuracy: location.accuracy,
                at: date
            )
        )
        await publishCheckpoint(at: date)
    }

    func checkpoint(at date: Date) async throws -> WalkEngineCheckpoint {
        try await engine.checkpoint(at: date)
    }

    func restore(
        from checkpoint: WalkEngineCheckpoint,
        at date: Date,
        resumeSensors: Bool
    ) async {
        stopSensorTasks()
        stopDetector.stop()
        sessionStartDate = checkpoint.startDate
        lastCheckpointDate = date
        cachedFinalRecord = nil
        lastPersistedAcceptedPointCount = checkpoint.trackPoints.filter(\.isAccepted).count
        latestMotionActivity = nil
        emit(await engine.restore(from: checkpoint, at: date))
        guard resumeSensors else { return }
        stopDetector.start()
        startSensorTasks(from: checkpoint.startDate)
        await reconcilePedometer(at: date)
        await publishCheckpoint(at: date)
    }

    func finalize(at date: Date) async throws -> NewWalkRecord {
        if let cachedFinalRecord {
            return cachedFinalRecord
        }

        await reconcilePedometer(at: date)
        await reconstructMovingTime(at: date)
        let record = try await engine.finalize(at: date)
        cachedFinalRecord = record
        stopDetector.stop()
        stopSensorTasks()
        emit(await engine.currentSnapshot(at: date))
        return record
    }

    func suppressFinishCandidate(at date: Date) {
        stopDetector.suppressCandidate(at: date)
    }

    func discard() async {
        stopDetector.stop()
        stopSensorTasks()
        await engine.discard()
        sessionStartDate = nil
        lastCheckpointDate = nil
        cachedFinalRecord = nil
        lastPersistedAcceptedPointCount = 0
        latestMotionActivity = nil
        emit(.empty)
    }

    private func requestNeededPermissions() async {
        if motionClient.authorizationState == .notDetermined {
            await motionClient.requestAuthorization()
        }

        if locationClient.snapshot.authorization == .notDetermined {
            await locationClient.requestWhenInUseAuthorization()
        }

        if locationClient.snapshot.authorization.permitsLocation,
           locationClient.snapshot.accuracy == .reduced {
            await locationClient.requestTemporaryFullAccuracy()
        }
    }

    private func startSensorTasks(from startDate: Date) {
        guard motionTask == nil, locationTask == nil, clockTask == nil else {
            return
        }
        let motionUpdates = motionClient.startWalkUpdates(from: startDate)
        motionTask = Task { [weak self] in
            for await event in motionUpdates {
                guard let self, !Task.isCancelled else { break }
                await self.handleMotion(event)
            }
        }

        let locationUpdates = locationClient.startWalkUpdates()
        locationTask = Task { [weak self] in
            for await event in locationUpdates {
                guard let self, !Task.isCancelled else { break }
                await self.handleLocation(event)
            }
        }

        let ticks = clock.ticks(every: 1)
        clockTask = Task { [weak self] in
            for await date in ticks {
                guard let self, !Task.isCancelled else { break }
                await self.handleTick(at: date)
            }
        }
    }

    private func stopSensorTasks() {
        motionTask?.cancel()
        locationTask?.cancel()
        clockTask?.cancel()
        motionTask = nil
        locationTask = nil
        clockTask = nil
        motionClient.stopWalkUpdates()
        locationClient.stopWalkUpdates()
        sessionStartDate = nil
        lastCheckpointDate = nil
    }

    private func handleMotion(_ event: WalkMotionEvent) async {
        let date = clock.now()
        switch event {
        case .pedometer(let sample):
            emit(await engine.ingestPedometer(sample, receivedAt: date))
        case .relativeAltitude(let sample):
            emit(await engine.ingestRelativeAltitude(sample, receivedAt: date))
        case .absoluteAltitude(let sample):
            emit(await engine.ingestAbsoluteAltitude(sample, receivedAt: date))
        case .activity(let sample):
            latestMotionActivity = sample
            emit(await engine.currentSnapshot(at: date), at: date)
        case .unavailable(let metric, let reason):
            emit(
                await engine.markMotionUnavailable(
                    metric,
                    reason: reason,
                    at: date
                )
            )
        }
    }

    private func handleLocation(_ event: WalkLocationEvent) async {
        let date = clock.now()
        switch event {
        case .location(let sample):
            let snapshot = await engine.ingestLocation(sample, receivedAt: date)
            emit(snapshot)
            if snapshot.acceptedLocationCount - lastPersistedAcceptedPointCount
                >= configuration.trackPointBatchSize {
                await publishCheckpoint(at: date)
            }
        case .authorization(let authorization, let accuracy):
            emit(
                await engine.updateLocationAuthorization(
                    authorization,
                    accuracy: accuracy,
                    at: date
                )
            )
            await publishCheckpoint(at: date)
        case .unavailable(let reason):
            emit(await engine.markLocationUnavailable(reason, at: date))
        }
    }

    private func handleTick(at date: Date) async {
        emit(await engine.tick(at: date), at: date)

        if let lastCheckpointDate,
           date.timeIntervalSince(lastCheckpointDate) >= configuration.checkpointInterval {
            self.lastCheckpointDate = date
            await reconcilePedometer(at: date)
            await publishCheckpoint(at: date)
        }
    }

    /// Rebuilds moving time from pedometer history over the whole walk.
    ///
    /// Live movement evidence is only as dense as the sensor callbacks that
    /// carry it, which is not dense at all with the phone pocketed or the app
    /// suspended. Querying step history bucket by bucket recovers what the
    /// live figure missed. Any failure leaves the live figure in place.
    private func reconstructMovingTime(at date: Date) async {
        guard let sessionStartDate,
              motionClient.authorizationState == .authorized,
              motionClient.stepCountingAvailable else {
            return
        }

        let buckets = MovingTimeReconstruction.buckets(
            from: sessionStartDate,
            to: date,
            preferredDuration: configuration.movingTimeBucket,
            maximumBuckets: configuration.movingTimeMaximumBuckets
        )
        guard !buckets.isEmpty else { return }

        var intervals: [PedometerInterval] = []
        intervals.reserveCapacity(buckets.count)
        for bucket in buckets {
            do {
                let sample = try await motionClient.queryPedometer(
                    from: bucket.start,
                    to: bucket.end
                )
                intervals.append(
                    PedometerInterval(interval: bucket, steps: sample.cumulativeSteps)
                )
            } catch {
                // A partial history still improves on the live figure, and the
                // resolver only takes the rebuilt value when it is larger.
                continue
            }
        }

        await engine.applyMovingTimeReconstruction(intervals, at: date)
    }

    private func reconcilePedometer(at date: Date) async {
        guard !isReconciling,
              let sessionStartDate,
              motionClient.authorizationState == .authorized,
              motionClient.stepCountingAvailable else {
            return
        }

        isReconciling = true
        defer { isReconciling = false }

        do {
            let sample = try await motionClient.queryPedometer(
                from: sessionStartDate,
                to: date
            )
            emit(await engine.ingestPedometer(sample, receivedAt: date))
        } catch {
            // Live values remain usable. The next foreground/checkpoint/finalization retries.
        }
    }

    private func emit(
        _ snapshot: WalkMetricsSnapshot,
        at date: Date? = nil
    ) {
        updateContinuation.yield(snapshot)
        let evaluationDate = date ?? clock.now()
        let decision = stopDetector.evaluate(
            LikelyStopSample(
                date: evaluationDate,
                elapsedDuration: snapshot.elapsedDuration,
                steps: snapshot.steps.value,
                speed: snapshot.speed,
                coordinate: snapshot.currentCoordinate,
                motionActivity: latestMotionActivity
            )
        )
        switch decision {
        case .none:
            break
        case .finishCandidate:
            eventContinuation.yield(.finishCandidate)
        case .movementResumed:
            eventContinuation.yield(.movementResumed)
        }
    }

    private func publishCheckpoint(at date: Date) async {
        guard let checkpoint = try? await engine.checkpoint(at: date) else { return }
        lastPersistedAcceptedPointCount = checkpoint.trackPoints.filter(\.isAccepted).count
        checkpointContinuation.yield(checkpoint)
    }
}
