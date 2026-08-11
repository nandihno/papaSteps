import Foundation

actor WalkMetricsEngine {
    private let configuration: TrackingConfiguration

    private var walkID: UUID?
    private var startDate: Date?
    private var timeZoneIdentifier = TimeZone.current.identifier
    private var lastTickDate: Date?
    private var isActive = false
    private var isPaused = false

    private var elapsedDuration: TimeInterval = 0
    private var movingDuration: TimeInterval = 0
    private var pausedDuration: TimeInterval = 0

    private var rawSteps: Int?
    private var rawPedometerDistance: Double?
    private var latestPedometerEndDate: Date?
    private var pausedStepsOffset = 0
    private var pausedDistanceOffset: Double = 0
    private var pauseStepsBaseline: Int?
    private var pauseDistanceBaseline: Double?
    private var lastStepChangeDate: Date?
    private var pedometerSpeed: Double?
    private var pedometerSpeedDate: Date?
    private var pedometerUnavailableReason: String?

    private var routeDistance: Double = 0
    private var acceptedLocationCount = 0
    private var rejectedLocationCount = 0
    private var lastAcceptedLocation: WalkLocationSample?
    private var currentCoordinate: WalkCoordinate?
    private var locationAccuracy: LocationAccuracyState = .unknown
    private var routeLimitation: RouteLimitation?
    private var locationUnavailableReason: String?
    private var routeSegmentStartPending = true
    private var trackPoints: [NewTrackPoint] = []
    private var recoveryCause: WalkRecoveryCause?

    private var smoothedSpeed: Double?
    private var maximumSustainedSpeed: Double?
    private var lastSpeedDate: Date?
    private var smoothedDirection: Double?
    private var lastDirectionDate: Date?

    private var relativeAltitudeStreamID: UUID?
    private var filteredRelativeAltitude: Double?
    private var relativeAltitudeReference: Double?
    private var accumulatedAscent: Double = 0
    private var hasRelativeAltitudeSample = false
    private var relativeAltitudeUnavailableReason: String?

    private var startAbsoluteAltitude: Double?
    private var currentAbsoluteAltitude: Double?
    private var absoluteAltitudeDate: Date?
    private var altitudeSource: AltitudeSource = .unavailable
    private var altitudeQuality: MetricQuality = .unavailable
    private var absoluteAltitudeUnavailableReason: String?

    init(configuration: TrackingConfiguration = .live) {
        self.configuration = configuration
    }

    func start(
        id: UUID,
        at date: Date,
        timeZoneIdentifier: String
    ) -> WalkMetricsSnapshot {
        reset()
        walkID = id
        startDate = date
        self.timeZoneIdentifier = timeZoneIdentifier
        lastTickDate = date
        isActive = true
        return snapshot(at: date)
    }

    func ingestPedometer(
        _ sample: PedometerSample,
        receivedAt date: Date
    ) -> WalkMetricsSnapshot {
        if let latestPedometerEndDate,
           sample.endDate < latestPedometerEndDate {
            return snapshot(at: date)
        }

        let previousSteps = rawSteps
        pedometerUnavailableReason = nil
        latestPedometerEndDate = sample.endDate
        rawSteps = max(0, sample.cumulativeSteps)
        rawPedometerDistance = sample.cumulativeDistance.map { max(0, $0) }

        if (previousSteps == nil && sample.cumulativeSteps > 0)
            || (previousSteps.map { sample.cumulativeSteps > $0 } ?? false) {
            lastStepChangeDate = date
        }

        if isPaused {
            if pauseStepsBaseline == nil {
                pauseStepsBaseline = rawSteps
            }
            if pauseDistanceBaseline == nil {
                pauseDistanceBaseline = rawPedometerDistance
            }
        }

        if let pace = sample.currentPace, pace > 0, pace.isFinite {
            let speed = 1 / pace
            if speed <= configuration.maximumWalkingSpeed {
                pedometerSpeed = speed
                pedometerSpeedDate = date
            }
        }

        return snapshot(at: date)
    }

    func ingestLocation(
        _ sample: WalkLocationSample,
        receivedAt date: Date
    ) -> WalkMetricsSnapshot {
        locationAccuracy = sample.accuracyAuthorization

        guard sample.horizontalAccuracy >= 0 else {
            rejectLocation(.poorSignal)
            return snapshot(at: date)
        }

        if sample.accuracyAuthorization == .full {
            locationUnavailableReason = nil
        }

        guard isActive, !isPaused else {
            lastAcceptedLocation = nil
            return snapshot(at: date)
        }

        guard sample.accuracyAuthorization == .full else {
            rejectLocation(.reducedAccuracy)
            return snapshot(at: date)
        }

        let age = date.timeIntervalSince(sample.timestamp)
        guard age >= -1, age <= configuration.maximumLocationAge,
              sample.horizontalAccuracy <= configuration.maximumHorizontalAccuracy else {
            rejectLocation(.poorSignal)
            return snapshot(at: date)
        }

        if let previous = lastAcceptedLocation {
            let interval = sample.timestamp.timeIntervalSince(previous.timestamp)
            guard interval > 0 else {
                rejectLocation(.poorSignal)
                return snapshot(at: date)
            }

            let segmentDistance = distance(
                from: previous.coordinate,
                to: sample.coordinate
            )
            guard segmentDistance / interval <= configuration.maximumWalkingSpeed else {
                rejectLocation(.poorSignal)
                return snapshot(at: date)
            }
            routeDistance += segmentDistance
        }

        acceptedLocationCount += 1
        lastAcceptedLocation = sample
        currentCoordinate = sample.coordinate
        trackPoints.append(
            NewTrackPoint(
                id: UUID(),
                timestamp: sample.timestamp,
                latitude: sample.coordinate.latitude,
                longitude: sample.coordinate.longitude,
                altitude: sample.altitude,
                horizontalAccuracy: sample.horizontalAccuracy,
                verticalAccuracy: sample.verticalAccuracy,
                speed: sample.speed >= 0 ? sample.speed : nil,
                speedAccuracy: sample.speedAccuracy >= 0 ? sample.speedAccuracy : nil,
                course: sample.course >= 0 ? sample.course : nil,
                courseAccuracy: sample.courseAccuracy >= 0 ? sample.courseAccuracy : nil,
                isAccepted: true,
                rejectionReason: nil,
                startsNewSegment: routeSegmentStartPending
            )
        )
        routeSegmentStartPending = false
        if routeLimitation == .poorSignal || routeLimitation == .unavailable {
            routeLimitation = nil
        }

        if sample.verticalAccuracy >= 0,
           sample.verticalAccuracy <= configuration.maximumVerticalAccuracy,
           currentAbsoluteAltitude == nil || altitudeSource != .barometer {
            recordAbsoluteAltitude(
                sample.altitude,
                at: sample.timestamp,
                source: .location,
                quality: sample.verticalAccuracy <= 15 ? .good : .degraded
            )
        }

        ingestSpeedAndDirection(sample, receivedAt: date)
        return snapshot(at: date)
    }

    func ingestRelativeAltitude(
        _ sample: RelativeAltitudeSample,
        receivedAt date: Date
    ) -> WalkMetricsSnapshot {
        hasRelativeAltitudeSample = true
        relativeAltitudeUnavailableReason = nil
        altitudeSource = .barometer
        if altitudeQuality == .unavailable {
            altitudeQuality = .good
        }

        if relativeAltitudeStreamID != sample.streamID {
            relativeAltitudeStreamID = sample.streamID
            filteredRelativeAltitude = sample.relativeAltitude
            relativeAltitudeReference = sample.relativeAltitude
            return snapshot(at: date)
        }

        let previousFiltered = filteredRelativeAltitude ?? sample.relativeAltitude
        let filtered = previousFiltered
            + configuration.elevationSmoothingFactor
            * (sample.relativeAltitude - previousFiltered)
        filteredRelativeAltitude = filtered

        guard isActive, !isPaused, isMoving(at: date) else {
            relativeAltitudeReference = filtered
            return snapshot(at: date)
        }

        guard let reference = relativeAltitudeReference else {
            relativeAltitudeReference = filtered
            return snapshot(at: date)
        }

        let change = filtered - reference
        if change >= configuration.elevationHysteresis {
            accumulatedAscent += change
            relativeAltitudeReference = filtered
        } else if change <= -configuration.elevationHysteresis {
            relativeAltitudeReference = filtered
        }

        return snapshot(at: date)
    }

    func ingestAbsoluteAltitude(
        _ sample: AbsoluteAltitudeSample,
        receivedAt date: Date
    ) -> WalkMetricsSnapshot {
        guard sample.altitude.isFinite,
              sample.accuracy >= 0,
              sample.accuracy <= configuration.maximumVerticalAccuracy else {
            return snapshot(at: date)
        }

        recordAbsoluteAltitude(
            sample.altitude,
            at: sample.timestamp,
            source: .barometer,
            quality: sample.accuracy <= 10 ? .good : .degraded
        )
        absoluteAltitudeUnavailableReason = nil
        return snapshot(at: date)
    }

    func updateLocationAuthorization(
        _ authorization: LocationAuthorizationState,
        accuracy: LocationAccuracyState,
        at date: Date
    ) -> WalkMetricsSnapshot {
        let previouslyUsable = locationAccuracy == .full
        locationAccuracy = accuracy
        if !authorization.permitsLocation {
            routeLimitation = authorization == .denied
                ? .permissionDenied
                : .unavailable
            lastAcceptedLocation = nil
            routeSegmentStartPending = true
            locationUnavailableReason = "Location access is unavailable."
            if isActive, previouslyUsable {
                recoveryCause = .locationAccessChanged
            }
        } else if accuracy == .reduced {
            routeLimitation = .reducedAccuracy
            lastAcceptedLocation = nil
            routeSegmentStartPending = true
            locationUnavailableReason = "Precise Location is off."
            if isActive, previouslyUsable {
                recoveryCause = .locationAccessChanged
            }
        } else {
            if routeLimitation == .permissionDenied
                || routeLimitation == .reducedAccuracy
                || routeLimitation == .unavailable {
                routeLimitation = nil
            }
            locationUnavailableReason = nil
        }
        return snapshot(at: date)
    }

    func markMotionUnavailable(
        _ metric: WalkMotionMetric,
        reason: String,
        at date: Date
    ) -> WalkMetricsSnapshot {
        switch metric {
        case .pedometer:
            pedometerUnavailableReason = reason
            if rawSteps == nil {
                pedometerSpeed = nil
            }
        case .relativeAltitude:
            relativeAltitudeUnavailableReason = reason
        case .absoluteAltitude:
            absoluteAltitudeUnavailableReason = reason
        }
        return snapshot(at: date)
    }

    func markLocationUnavailable(_ reason: String, at date: Date) -> WalkMetricsSnapshot {
        routeLimitation = .unavailable
        lastAcceptedLocation = nil
        routeSegmentStartPending = true
        locationUnavailableReason = reason
        return snapshot(at: date)
    }

    func tick(at date: Date) -> WalkMetricsSnapshot {
        guard let previous = lastTickDate else {
            lastTickDate = date
            return snapshot(at: date)
        }

        let interval = max(0, date.timeIntervalSince(previous))
        lastTickDate = date
        elapsedDuration += interval

        if isPaused {
            pausedDuration += interval
        } else if isActive, isMoving(at: date) {
            movingDuration += interval
        }

        return snapshot(at: date)
    }

    func pause(at date: Date) -> WalkMetricsSnapshot {
        _ = tick(at: date)
        guard isActive, !isPaused else { return snapshot(at: date) }
        isPaused = true
        pauseStepsBaseline = rawSteps
        pauseDistanceBaseline = rawPedometerDistance
        lastAcceptedLocation = nil
        routeSegmentStartPending = true
        relativeAltitudeReference = nil
        return snapshot(at: date)
    }

    func resume(at date: Date) -> WalkMetricsSnapshot {
        _ = tick(at: date)
        guard isActive, isPaused else { return snapshot(at: date) }
        commitPausedOffsets()
        isPaused = false
        lastAcceptedLocation = nil
        routeSegmentStartPending = true
        relativeAltitudeReference = nil
        lastStepChangeDate = nil
        if smoothedSpeed != nil {
            lastSpeedDate = date.addingTimeInterval(
                -(configuration.metricStaleInterval + 1)
            )
        }
        if smoothedDirection != nil {
            lastDirectionDate = date.addingTimeInterval(
                -(configuration.metricStaleInterval + 1)
            )
        }
        return snapshot(at: date)
    }

    func finalize(at date: Date) throws -> NewWalkRecord {
        _ = tick(at: date)
        guard let walkID, let startDate else {
            throw WalkSessionError.noActiveWalk
        }

        if isPaused {
            commitPausedOffsets()
        }
        isActive = false
        isPaused = false

        let finalSnapshot = snapshot(at: date)
        let selectedDistance = selectedDistance()
        let effectiveSteps = effectiveStepCount()
        let averageSpeed = selectedDistance.value.flatMap { distance in
            movingDuration > 0 ? distance / movingDuration : nil
        }

        return NewWalkRecord(
            id: walkID,
            createdAt: startDate,
            startDate: startDate,
            endDate: date,
            timeZoneIdentifier: timeZoneIdentifier,
            elapsedDuration: elapsedDuration,
            movingDuration: movingDuration,
            pausedDuration: pausedDuration,
            displayDistance: selectedDistance.value,
            distanceSource: selectedDistance.source,
            routeDistance: routeDistance > 0 ? routeDistance : nil,
            pedometerDistance: effectivePedometerDistance(),
            displaySteps: effectiveSteps,
            stepSource: effectiveSteps == nil ? .unavailable : .motion,
            motionSteps: effectiveSteps,
            averageSpeed: averageSpeed,
            maximumSustainedSpeed: maximumSustainedSpeed,
            startAltitude: startAbsoluteAltitude,
            endAltitude: currentAbsoluteAltitude,
            elevationGain: hasRelativeAltitudeSample ? accumulatedAscent : nil,
            altitudeSource: altitudeSource,
            altitudeQuality: altitudeQuality,
            routeQuality: finalSnapshot.routeQuality,
            routeQualityReason: currentRouteQualityReason(),
            acceptedLocationCount: acceptedLocationCount,
            rejectedLocationCount: rejectedLocationCount,
            trackPoints: trackPoints
        )
    }

    func checkpoint(at date: Date) throws -> WalkEngineCheckpoint {
        guard let walkID, let startDate else {
            throw WalkSessionError.noActiveWalk
        }

        let selectedDistance = selectedDistance()
        let steps = effectiveStepCount()
        return WalkEngineCheckpoint(
            id: walkID,
            startDate: startDate,
            timeZoneIdentifier: timeZoneIdentifier,
            lastCheckpointDate: date,
            recoveryState: isPaused ? .paused : .active,
            recoveryCause: recoveryCause,
            lastTickDate: lastTickDate,
            elapsedDuration: elapsedDuration,
            movingDuration: movingDuration,
            pausedDuration: pausedDuration,
            rawSteps: rawSteps,
            rawPedometerDistance: rawPedometerDistance,
            latestPedometerEndDate: latestPedometerEndDate,
            pausedStepsOffset: pausedStepsOffset,
            pausedDistanceOffset: pausedDistanceOffset,
            pauseStepsBaseline: pauseStepsBaseline,
            pauseDistanceBaseline: pauseDistanceBaseline,
            lastStepChangeDate: lastStepChangeDate,
            pedometerSpeed: pedometerSpeed,
            pedometerSpeedDate: pedometerSpeedDate,
            pedometerUnavailableReason: pedometerUnavailableReason,
            routeDistance: routeDistance,
            acceptedLocationCount: acceptedLocationCount,
            rejectedLocationCount: rejectedLocationCount,
            lastAcceptedLocation: lastAcceptedLocation,
            currentCoordinate: currentCoordinate,
            locationAccuracy: locationAccuracy,
            routeLimitation: routeLimitation,
            locationUnavailableReason: locationUnavailableReason,
            routeSegmentStartPending: routeSegmentStartPending,
            trackPoints: trackPoints,
            smoothedSpeed: smoothedSpeed,
            maximumSustainedSpeed: maximumSustainedSpeed,
            lastSpeedDate: lastSpeedDate,
            smoothedDirection: smoothedDirection,
            lastDirectionDate: lastDirectionDate,
            relativeAltitudeStreamID: relativeAltitudeStreamID,
            filteredRelativeAltitude: filteredRelativeAltitude,
            relativeAltitudeReference: relativeAltitudeReference,
            accumulatedAscent: accumulatedAscent,
            hasRelativeAltitudeSample: hasRelativeAltitudeSample,
            relativeAltitudeUnavailableReason: relativeAltitudeUnavailableReason,
            startAbsoluteAltitude: startAbsoluteAltitude,
            currentAbsoluteAltitude: currentAbsoluteAltitude,
            absoluteAltitudeDate: absoluteAltitudeDate,
            altitudeSource: altitudeSource,
            altitudeQuality: altitudeQuality,
            absoluteAltitudeUnavailableReason: absoluteAltitudeUnavailableReason,
            displayDistance: selectedDistance.value,
            distanceSource: selectedDistance.source,
            displaySteps: steps,
            averageSpeed: selectedDistance.value.flatMap {
                movingDuration > 0 ? $0 / movingDuration : nil
            },
            routeQuality: currentRouteQuality(),
            routeQualityReason: currentRouteQualityReason()
        )
    }

    func restore(from checkpoint: WalkEngineCheckpoint, at date: Date) -> WalkMetricsSnapshot {
        reset()
        walkID = checkpoint.id
        startDate = checkpoint.startDate
        timeZoneIdentifier = checkpoint.timeZoneIdentifier
        lastTickDate = checkpoint.lastTickDate
        isActive = true
        isPaused = checkpoint.recoveryState == .paused
        elapsedDuration = checkpoint.elapsedDuration
        movingDuration = checkpoint.movingDuration
        pausedDuration = checkpoint.pausedDuration
        rawSteps = checkpoint.rawSteps
        rawPedometerDistance = checkpoint.rawPedometerDistance
        latestPedometerEndDate = checkpoint.latestPedometerEndDate
        pausedStepsOffset = checkpoint.pausedStepsOffset
        pausedDistanceOffset = checkpoint.pausedDistanceOffset
        pauseStepsBaseline = checkpoint.pauseStepsBaseline
        pauseDistanceBaseline = checkpoint.pauseDistanceBaseline
        lastStepChangeDate = checkpoint.lastStepChangeDate
        pedometerSpeed = checkpoint.pedometerSpeed
        pedometerSpeedDate = checkpoint.pedometerSpeedDate
        pedometerUnavailableReason = checkpoint.pedometerUnavailableReason
        routeDistance = checkpoint.routeDistance
        acceptedLocationCount = checkpoint.acceptedLocationCount
        rejectedLocationCount = checkpoint.rejectedLocationCount
        lastAcceptedLocation = nil
        currentCoordinate = checkpoint.currentCoordinate
        locationAccuracy = checkpoint.locationAccuracy
        routeLimitation = checkpoint.routeLimitation
        locationUnavailableReason = checkpoint.locationUnavailableReason
        routeSegmentStartPending = true
        trackPoints = checkpoint.trackPoints
        recoveryCause = checkpoint.recoveryCause
        smoothedSpeed = checkpoint.smoothedSpeed
        maximumSustainedSpeed = checkpoint.maximumSustainedSpeed
        lastSpeedDate = checkpoint.lastSpeedDate
        smoothedDirection = checkpoint.smoothedDirection
        lastDirectionDate = checkpoint.lastDirectionDate
        relativeAltitudeStreamID = nil
        filteredRelativeAltitude = checkpoint.filteredRelativeAltitude
        relativeAltitudeReference = nil
        accumulatedAscent = checkpoint.accumulatedAscent
        hasRelativeAltitudeSample = checkpoint.hasRelativeAltitudeSample
        relativeAltitudeUnavailableReason = checkpoint.relativeAltitudeUnavailableReason
        startAbsoluteAltitude = checkpoint.startAbsoluteAltitude
        currentAbsoluteAltitude = checkpoint.currentAbsoluteAltitude
        absoluteAltitudeDate = checkpoint.absoluteAltitudeDate
        altitudeSource = checkpoint.altitudeSource
        altitudeQuality = checkpoint.altitudeQuality
        absoluteAltitudeUnavailableReason = checkpoint.absoluteAltitudeUnavailableReason

        // The gap is elapsed time, never invented moving time or route distance.
        if let lastTickDate, date > lastTickDate {
            elapsedDuration += date.timeIntervalSince(lastTickDate)
        }
        lastTickDate = date
        isPaused = false
        return snapshot(at: date)
    }

    func discard() {
        reset()
    }

    func currentSnapshot(at date: Date) -> WalkMetricsSnapshot {
        snapshot(at: date)
    }

    private func ingestSpeedAndDirection(
        _ sample: WalkLocationSample,
        receivedAt date: Date
    ) {
        let speedIsValid = sample.speed >= 0
            && sample.speed.isFinite
            && sample.speed <= configuration.maximumWalkingSpeed
            && (sample.speedAccuracy < 0
                || sample.speedAccuracy <= configuration.maximumSpeedAccuracy)

        if speedIsValid {
            if let smoothedSpeed {
                self.smoothedSpeed = smoothedSpeed
                    + configuration.speedSmoothingFactor
                    * (sample.speed - smoothedSpeed)
            } else {
                smoothedSpeed = sample.speed
            }
            lastSpeedDate = date
            if let smoothedSpeed {
                maximumSustainedSpeed = max(maximumSustainedSpeed ?? 0, smoothedSpeed)
            }
        }

        guard speedIsValid,
              sample.speed >= configuration.movingSpeedThreshold,
              sample.course >= 0,
              sample.course.isFinite,
              (sample.courseAccuracy < 0
                || sample.courseAccuracy <= configuration.maximumCourseAccuracy) else {
            return
        }

        smoothedDirection = circularBlend(
            previous: smoothedDirection,
            next: sample.course,
            factor: configuration.directionSmoothingFactor
        )
        lastDirectionDate = date
    }

    private func rejectLocation(_ limitation: RouteLimitation) {
        guard isActive, !isPaused else { return }
        rejectedLocationCount += 1
        routeLimitation = limitation
        lastAcceptedLocation = nil
        routeSegmentStartPending = true
    }

    private func recordAbsoluteAltitude(
        _ altitude: Double,
        at date: Date,
        source: AltitudeSource,
        quality: MetricQuality
    ) {
        if startAbsoluteAltitude == nil {
            startAbsoluteAltitude = altitude
        }
        currentAbsoluteAltitude = altitude
        absoluteAltitudeDate = date
        altitudeSource = source
        altitudeQuality = quality
    }

    private func effectiveStepCount() -> Int? {
        guard let rawSteps else { return nil }
        var offset = pausedStepsOffset
        if isPaused, let pauseStepsBaseline {
            offset += max(0, rawSteps - pauseStepsBaseline)
        }
        return max(0, rawSteps - offset)
    }

    private func effectivePedometerDistance() -> Double? {
        guard let rawPedometerDistance else { return nil }
        var offset = pausedDistanceOffset
        if isPaused, let pauseDistanceBaseline {
            offset += max(0, rawPedometerDistance - pauseDistanceBaseline)
        }
        return max(0, rawPedometerDistance - offset)
    }

    private func commitPausedOffsets() {
        if let rawSteps, let pauseStepsBaseline {
            pausedStepsOffset += max(0, rawSteps - pauseStepsBaseline)
        }
        if let rawPedometerDistance, let pauseDistanceBaseline {
            pausedDistanceOffset += max(0, rawPedometerDistance - pauseDistanceBaseline)
        }
        pauseStepsBaseline = nil
        pauseDistanceBaseline = nil
    }

    private func selectedDistance() -> (value: Double?, source: DistanceSource) {
        let quality = currentRouteQuality()
        if routeDistance > 0, quality != .unavailable {
            return (routeDistance, .route)
        }
        if let pedometerDistance = effectivePedometerDistance() {
            return (pedometerDistance, .pedometer)
        }
        return (nil, .unavailable)
    }

    private func currentRouteQuality() -> RouteQuality {
        if routeLimitation == .reducedAccuracy
            || routeLimitation == .permissionDenied
            || routeLimitation == .unavailable {
            return .unavailable
        }
        guard acceptedLocationCount >= 2 else { return .unavailable }
        let total = acceptedLocationCount + rejectedLocationCount
        guard total > 0 else { return .unavailable }
        let rejectedRatio = Double(rejectedLocationCount) / Double(total)
        return rejectedRatio <= 0.3 ? .good : .degraded
    }

    private func currentRouteQualityReason() -> RouteQualityReason? {
        if recoveryCause == .locationAccessChanged || routeLimitation == .permissionDenied {
            return .permissionChanged
        }
        switch routeLimitation {
        case .reducedAccuracy:
            return .reducedAccuracy
        case .poorSignal:
            return .poorSignal
        case .unavailable:
            return .locationUnavailable
        case .permissionDenied:
            return .permissionChanged
        case nil:
            if acceptedLocationCount < 2 { return .insufficientPoints }
            return currentRouteQuality() == .degraded ? .poorSignal : nil
        }
    }

    private func currentRouteSegments() -> [[WalkCoordinate]] {
        trackPoints
            .filter(\.isAccepted)
            .reduce(into: [[WalkCoordinate]]()) { segments, point in
                if point.startsNewSegment || segments.isEmpty {
                    segments.append([])
                }
                segments[segments.index(before: segments.endIndex)].append(point.coordinate)
            }
    }

    private func isMoving(at date: Date) -> Bool {
        let speedIsFresh = lastSpeedDate.map {
            date.timeIntervalSince($0) <= configuration.movementEvidenceInterval
        } ?? false
        let hasWalkingSpeed = speedIsFresh
            && (smoothedSpeed ?? 0) >= configuration.movingSpeedThreshold

        let stepsAreFresh = lastStepChangeDate.map {
            date.timeIntervalSince($0) <= configuration.movementEvidenceInterval
        } ?? false

        return hasWalkingSpeed || stepsAreFresh
    }

    private func snapshot(at date: Date) -> WalkMetricsSnapshot {
        let selectedDistance = selectedDistance()
        let moving = isActive && !isPaused && isMoving(at: date)

        let stepMetric: LiveMetric<Int>
        if let steps = effectiveStepCount() {
            stepMetric = LiveMetric(value: steps, availability: .available)
        } else if let pedometerUnavailableReason {
            stepMetric = .unavailable(pedometerUnavailableReason)
        } else {
            stepMetric = .acquiring
        }

        let distanceMetric: LiveMetric<Double>
        if let distance = selectedDistance.value {
            distanceMetric = LiveMetric(value: distance, availability: .available)
        } else if let locationUnavailableReason, rawPedometerDistance == nil {
            distanceMetric = .unavailable(locationUnavailableReason)
        } else {
            distanceMetric = .acquiring
        }

        var speedMetric = timedMetric(
            primaryValue: smoothedSpeed,
            primaryDate: lastSpeedDate,
            fallbackValue: pedometerSpeed,
            fallbackDate: pedometerSpeedDate,
            at: date
        )
        var directionMetric = timedMetric(
            primaryValue: smoothedDirection,
            primaryDate: lastDirectionDate,
            fallbackValue: nil,
            fallbackDate: nil,
            at: date
        )
        var altitudeMetric = timedMetric(
            primaryValue: currentAbsoluteAltitude,
            primaryDate: absoluteAltitudeDate,
            fallbackValue: nil,
            fallbackDate: nil,
            at: date
        )

        if speedMetric.availability == .acquiring,
           let locationUnavailableReason,
           pedometerSpeed == nil {
            speedMetric = .unavailable(locationUnavailableReason)
        }
        if directionMetric.availability == .acquiring,
           let locationUnavailableReason {
            directionMetric = .unavailable(locationUnavailableReason)
        }
        if altitudeMetric.availability == .acquiring,
           let absoluteAltitudeUnavailableReason,
           locationUnavailableReason != nil {
            altitudeMetric = .unavailable(absoluteAltitudeUnavailableReason)
        }

        let elevationMetric: LiveMetric<Double>
        if hasRelativeAltitudeSample {
            elevationMetric = LiveMetric(value: accumulatedAscent, availability: .available)
        } else if let relativeAltitudeUnavailableReason {
            elevationMetric = .unavailable(relativeAltitudeUnavailableReason)
        } else {
            elevationMetric = .acquiring
        }

        return WalkMetricsSnapshot(
            elapsedDuration: elapsedDuration,
            movingDuration: movingDuration,
            pausedDuration: pausedDuration,
            steps: stepMetric,
            distance: distanceMetric,
            distanceSource: selectedDistance.source,
            speed: speedMetric,
            direction: directionMetric,
            absoluteAltitude: altitudeMetric,
            elevationGain: elevationMetric,
            currentCoordinate: currentCoordinate,
            routeCoordinates: trackPoints.filter(\.isAccepted).map(\.coordinate),
            routeSegments: currentRouteSegments(),
            routeQuality: currentRouteQuality(),
            routeLimitation: routeLimitation,
            locationAccuracy: locationAccuracy,
            acceptedLocationCount: acceptedLocationCount,
            rejectedLocationCount: rejectedLocationCount,
            isMoving: moving
        )
    }

    private func timedMetric(
        primaryValue: Double?,
        primaryDate: Date?,
        fallbackValue: Double?,
        fallbackDate: Date?,
        at date: Date
    ) -> LiveMetric<Double> {
        if let primaryValue, let primaryDate {
            let availability: MetricAvailability = date.timeIntervalSince(primaryDate)
                <= configuration.metricStaleInterval ? .available : .stale
            return LiveMetric(value: primaryValue, availability: availability)
        }
        if let fallbackValue, let fallbackDate {
            let availability: MetricAvailability = date.timeIntervalSince(fallbackDate)
                <= configuration.metricStaleInterval ? .available : .stale
            return LiveMetric(value: fallbackValue, availability: availability)
        }
        return .acquiring
    }

    private func circularBlend(
        previous: Double?,
        next: Double,
        factor: Double
    ) -> Double {
        guard let previous else { return normalizedDegrees(next) }
        let previousRadians = previous * .pi / 180
        let nextRadians = next * .pi / 180
        let x = (1 - factor) * cos(previousRadians) + factor * cos(nextRadians)
        let y = (1 - factor) * sin(previousRadians) + factor * sin(nextRadians)
        return normalizedDegrees(atan2(y, x) * 180 / .pi)
    }

    private func normalizedDegrees(_ value: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }

    private func distance(from start: WalkCoordinate, to end: WalkCoordinate) -> Double {
        let earthRadius = 6_371_000.0
        let startLatitude = start.latitude * .pi / 180
        let endLatitude = end.latitude * .pi / 180
        let latitudeDelta = (end.latitude - start.latitude) * .pi / 180
        let longitudeDelta = (end.longitude - start.longitude) * .pi / 180
        let a = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(startLatitude) * cos(endLatitude)
            * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        let clampedA = min(1, max(0, a))
        return earthRadius * 2 * atan2(sqrt(clampedA), sqrt(1 - clampedA))
    }

    private func reset() {
        walkID = nil
        startDate = nil
        timeZoneIdentifier = TimeZone.current.identifier
        lastTickDate = nil
        isActive = false
        isPaused = false
        elapsedDuration = 0
        movingDuration = 0
        pausedDuration = 0
        rawSteps = nil
        rawPedometerDistance = nil
        latestPedometerEndDate = nil
        pausedStepsOffset = 0
        pausedDistanceOffset = 0
        pauseStepsBaseline = nil
        pauseDistanceBaseline = nil
        lastStepChangeDate = nil
        pedometerSpeed = nil
        pedometerSpeedDate = nil
        pedometerUnavailableReason = nil
        routeDistance = 0
        acceptedLocationCount = 0
        rejectedLocationCount = 0
        lastAcceptedLocation = nil
        currentCoordinate = nil
        locationAccuracy = .unknown
        routeLimitation = nil
        locationUnavailableReason = nil
        routeSegmentStartPending = true
        trackPoints = []
        recoveryCause = nil
        smoothedSpeed = nil
        maximumSustainedSpeed = nil
        lastSpeedDate = nil
        smoothedDirection = nil
        lastDirectionDate = nil
        relativeAltitudeStreamID = nil
        filteredRelativeAltitude = nil
        relativeAltitudeReference = nil
        accumulatedAscent = 0
        hasRelativeAltitudeSample = false
        relativeAltitudeUnavailableReason = nil
        startAbsoluteAltitude = nil
        currentAbsoluteAltitude = nil
        absoluteAltitudeDate = nil
        altitudeSource = .unavailable
        altitudeQuality = .unavailable
        absoluteAltitudeUnavailableReason = nil
    }
}
