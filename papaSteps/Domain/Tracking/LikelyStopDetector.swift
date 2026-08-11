import Foundation

enum LikelyStopDecision: Equatable, Sendable {
    case none
    case finishCandidate
    case movementResumed
}

struct LikelyStopSample: Equatable, Sendable {
    let date: Date
    let elapsedDuration: TimeInterval
    let steps: Int?
    let speed: LiveMetric<Double>
    let coordinate: WalkCoordinate?
    let motionActivity: WalkMotionActivitySample?
}

struct LikelyStopDetector: Sendable {
    private let configuration: TrackingConfiguration

    private var isRunning = false
    private var candidateIsActive = false
    private var stationaryStartedAt: Date?
    private var stationarySteps: Int?
    private var stationaryCoordinate: WalkCoordinate?
    private var suppressionUntil: Date?

    init(configuration: TrackingConfiguration = .live) {
        self.configuration = configuration
    }

    mutating func start() {
        isRunning = true
        candidateIsActive = false
        stationaryStartedAt = nil
        stationarySteps = nil
        stationaryCoordinate = nil
        suppressionUntil = nil
    }

    mutating func stop() {
        isRunning = false
        candidateIsActive = false
        stationaryStartedAt = nil
        stationarySteps = nil
        stationaryCoordinate = nil
        suppressionUntil = nil
    }

    mutating func suppressCandidate(at date: Date) {
        candidateIsActive = false
        suppressionUntil = date.addingTimeInterval(
            configuration.finishPromptSuppressionInterval
        )
        resetStationaryWindow()
    }

    mutating func evaluate(_ sample: LikelyStopSample) -> LikelyStopDecision {
        guard isRunning else { return .none }

        if hasMeaningfulMovement(sample) {
            let decision: LikelyStopDecision = candidateIsActive
                ? .movementResumed : .none
            candidateIsActive = false
            resetStationaryWindow()
            return decision
        }

        guard sample.elapsedDuration
                >= configuration.minimumFinishPromptWalkDuration,
              hasCorroboratedStationaryEvidence(sample) else {
            resetStationaryWindow()
            return .none
        }

        if stationaryStartedAt == nil {
            stationaryStartedAt = sample.date
            stationarySteps = sample.steps
            stationaryCoordinate = sample.coordinate
            return .none
        }

        guard !candidateIsActive,
              suppressionUntil.map({ sample.date >= $0 }) ?? true,
              let stationaryStartedAt,
              sample.date.timeIntervalSince(stationaryStartedAt)
                >= configuration.likelyStopWindow else {
            return .none
        }

        candidateIsActive = true
        return .finishCandidate
    }

    private func hasMeaningfulMovement(_ sample: LikelyStopSample) -> Bool {
        if let baseline = stationarySteps,
           let steps = sample.steps,
           steps - baseline > configuration.stopDetectorMaximumStepIncrease {
            return true
        }

        if let baseline = stationaryCoordinate,
           let coordinate = sample.coordinate,
           distance(from: baseline, to: coordinate)
                > configuration.stopDetectorMaximumDisplacement {
            return true
        }

        if sample.speed.availability == .available,
           let speed = sample.speed.value,
           speed > configuration.stopDetectorMaximumSpeed {
            return true
        }

        if let activity = freshActivity(from: sample),
           activity.confidence >= .medium,
           activity.activity != .stationary,
           activity.activity != .unknown {
            return true
        }

        return false
    }

    private func hasCorroboratedStationaryEvidence(
        _ sample: LikelyStopSample
    ) -> Bool {
        var availableSignals = 0
        var stationarySignals = 0

        if let steps = sample.steps {
            availableSignals += 1
            let baseline = stationarySteps ?? steps
            if steps - baseline <= configuration.stopDetectorMaximumStepIncrease {
                stationarySignals += 1
            }
        }

        if let coordinate = sample.coordinate {
            availableSignals += 1
            let baseline = stationaryCoordinate ?? coordinate
            if distance(from: baseline, to: coordinate)
                <= configuration.stopDetectorMaximumDisplacement {
                stationarySignals += 1
            }
        }

        if sample.speed.availability == .available,
           let speed = sample.speed.value {
            availableSignals += 1
            if speed <= configuration.stopDetectorMaximumSpeed {
                stationarySignals += 1
            }
        }

        if let activity = freshActivity(from: sample) {
            availableSignals += 1
            if activity.activity == .stationary,
               activity.confidence >= .medium {
                stationarySignals += 1
            }
        }

        return availableSignals >= 2 && stationarySignals == availableSignals
    }

    private func freshActivity(
        from sample: LikelyStopSample
    ) -> WalkMotionActivitySample? {
        guard let activity = sample.motionActivity,
              sample.date.timeIntervalSince(activity.timestamp) >= -1,
              sample.date.timeIntervalSince(activity.timestamp)
                <= configuration.stopDetectorActivityFreshness else {
            return nil
        }
        return activity
    }

    private mutating func resetStationaryWindow() {
        stationaryStartedAt = nil
        stationarySteps = nil
        stationaryCoordinate = nil
    }

    private func distance(
        from start: WalkCoordinate,
        to end: WalkCoordinate
    ) -> Double {
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
}
