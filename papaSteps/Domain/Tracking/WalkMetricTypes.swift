import Foundation

struct TrackingConfiguration: Equatable, Sendable {
    var maximumLocationFutureSkew: TimeInterval = 1
    var preferredHorizontalAccuracy: Double = 20
    var maximumHorizontalAccuracy: Double = 50
    var maximumRouteGap: TimeInterval = 30
    var maximumVerticalAccuracy: Double = 30
    var maximumSpeedAccuracy: Double = 3
    var maximumCourseAccuracy: Double = 30
    var maximumWalkingSpeed: Double = 4.5
    var movingSpeedThreshold: Double = 0.45
    var speedSmoothingFactor: Double = 0.35
    var directionSmoothingFactor: Double = 0.35
    var metricStaleInterval: TimeInterval = 8
    var movementEvidenceInterval: TimeInterval = 4
    var elevationSmoothingFactor: Double = 0.25
    var elevationHysteresis: Double = 1
    var checkpointInterval: TimeInterval = 60
    /// Bucket size for rebuilding moving time from pedometer history at
    /// finalization (§ moving-time reconstruction).
    var movingTimeBucket: TimeInterval = 60
    /// Upper bound on the number of pedometer queries one reconstruction may
    /// issue. Longer walks widen the bucket instead of issuing more queries.
    var movingTimeMaximumBuckets = 180
    /// Steps per second assumed for ordinary walking, used to convert a
    /// bucket's step count into time spent walking. About 105 steps/minute.
    var assumedWalkingCadence: Double = 1.75
    var trackPointBatchSize = 10
    var minimumFinishPromptWalkDuration: TimeInterval = 180
    var likelyStopWindow: TimeInterval = 180
    var finishPromptSuppressionInterval: TimeInterval = 300
    var stopDetectorMaximumStepIncrease = 2
    var stopDetectorMaximumDisplacement: Double = 15
    var stopDetectorMaximumSpeed: Double = 0.35
    var stopDetectorActivityFreshness: TimeInterval = 300

    static let live = TrackingConfiguration()
}

enum MetricAvailability: Equatable, Sendable {
    case acquiring
    case available
    case stale
    case unavailable(String)
}

struct LiveMetric<Value: Equatable & Sendable>: Equatable, Sendable {
    var value: Value?
    var availability: MetricAvailability

    static var acquiring: LiveMetric<Value> {
        LiveMetric(value: nil, availability: .acquiring)
    }

    static func unavailable(_ reason: String) -> LiveMetric<Value> {
        LiveMetric(value: nil, availability: .unavailable(reason))
    }
}

struct WalkCoordinate: Codable, Equatable, Sendable {
    let latitude: Double
    let longitude: Double
}

enum RouteLimitation: String, Codable, Equatable, Sendable {
    case reducedAccuracy
    case permissionDenied
    case unavailable
    case poorSignal
}

enum LocationRejectionReason: String, Codable, Equatable, Sendable {
    case invalidAccuracy
    case outsideWalkInterval
    case reducedAccuracy
    case accuracyExceedsLimit
    case nonMonotonicTimestamp
    case impossibleJump
    case reacquisitionUnconfirmed
}

struct WalkMetricsSnapshot: Equatable, Sendable {
    var elapsedDuration: TimeInterval
    var movingDuration: TimeInterval
    var pausedDuration: TimeInterval
    var steps: LiveMetric<Int>
    var distance: LiveMetric<Double>
    var distanceSource: DistanceSource
    var speed: LiveMetric<Double>
    var direction: LiveMetric<Double>
    var absoluteAltitude: LiveMetric<Double>
    var elevationGain: LiveMetric<Double>
    var currentCoordinate: WalkCoordinate?
    var routeCoordinates: [WalkCoordinate]
    var routeSegments: [[WalkCoordinate]]
    var routeQuality: RouteQuality
    var routeLimitation: RouteLimitation?
    var locationAccuracy: LocationAccuracyState
    var acceptedLocationCount: Int
    var rejectedLocationCount: Int
    var isMoving: Bool

    static let empty = WalkMetricsSnapshot(
        elapsedDuration: 0,
        movingDuration: 0,
        pausedDuration: 0,
        steps: .acquiring,
        distance: .acquiring,
        distanceSource: .unavailable,
        speed: .acquiring,
        direction: .acquiring,
        absoluteAltitude: .acquiring,
        elevationGain: .acquiring,
        currentCoordinate: nil,
        routeCoordinates: [],
        routeSegments: [],
        routeQuality: .unavailable,
        routeLimitation: nil,
        locationAccuracy: .unknown,
        acceptedLocationCount: 0,
        rejectedLocationCount: 0,
        isMoving: false
    )
}

/// Steps recorded over one wall-clock window, from `queryPedometerData`.
///
/// Live pedometer callbacks are irregular and stop entirely while the process
/// is suspended, so moving time cannot be measured only by watching them
/// arrive. This is the after-the-fact record used to rebuild it.
struct PedometerInterval: Equatable, Sendable {
    let interval: DateInterval
    let steps: Int

    init(interval: DateInterval, steps: Int) {
        self.interval = interval
        self.steps = max(0, steps)
    }
}

struct PedometerSample: Codable, Equatable, Sendable {
    let startDate: Date
    let endDate: Date
    let cumulativeSteps: Int
    let cumulativeDistance: Double?
    let currentPace: Double?
    let currentCadence: Double?
}

struct RelativeAltitudeSample: Codable, Equatable, Sendable {
    let streamID: UUID
    let timestamp: Date
    let relativeAltitude: Double
}

struct AbsoluteAltitudeSample: Codable, Equatable, Sendable {
    let timestamp: Date
    let altitude: Double
    let accuracy: Double
}

enum WalkMotionEvent: Equatable, Sendable {
    case pedometer(PedometerSample)
    case relativeAltitude(RelativeAltitudeSample)
    case absoluteAltitude(AbsoluteAltitudeSample)
    case activity(WalkMotionActivitySample)
    case unavailable(WalkMotionMetric, String)
}

enum WalkMotionActivity: String, Codable, Equatable, Sendable {
    case stationary
    case walking
    case running
    case cycling
    case automotive
    case unknown
}

enum WalkMotionConfidence: Int, Codable, Comparable, Equatable, Sendable {
    case low = 0
    case medium = 1
    case high = 2

    static func < (lhs: WalkMotionConfidence, rhs: WalkMotionConfidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct WalkMotionActivitySample: Codable, Equatable, Sendable {
    let timestamp: Date
    let activity: WalkMotionActivity
    let confidence: WalkMotionConfidence
}

enum WalkMotionMetric: Equatable, Sendable {
    case pedometer
    case relativeAltitude
    case absoluteAltitude
}

struct WalkLocationSample: Codable, Equatable, Sendable {
    let coordinate: WalkCoordinate
    let timestamp: Date
    let altitude: Double
    let horizontalAccuracy: Double
    let verticalAccuracy: Double
    let speed: Double
    let speedAccuracy: Double
    let course: Double
    let courseAccuracy: Double
    let accuracyAuthorization: LocationAccuracyState
}

enum WalkLocationEvent: Equatable, Sendable {
    case location(WalkLocationSample)
    case authorization(LocationAuthorizationState, LocationAccuracyState)
    case unavailable(String)
}

struct WalkPermissionSnapshot: Equatable, Sendable {
    let motionAuthorization: PermissionAuthorizationState
    let locationAuthorization: LocationAuthorizationState
    let locationAccuracy: LocationAccuracyState
    let stepCountingAvailable: Bool
    let pedometerDistanceAvailable: Bool
    let relativeAltitudeAvailable: Bool
    let absoluteAltitudeAvailable: Bool

    var needsExplanation: Bool {
        motionAuthorization == .notDetermined
            || motionAuthorization == .denied
            || motionAuthorization == .restricted
            || locationAuthorization == .notDetermined
            || locationAuthorization == .denied
            || locationAuthorization == .restricted
            || locationAccuracy == .reduced
    }

    var hasUsableTrackingSource: Bool {
        (motionAuthorization == .authorized && stepCountingAvailable)
            || locationAuthorization.permitsLocation
    }
}
