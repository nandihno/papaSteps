import Foundation

enum WalkFinalizationStatus: String, Codable, Sendable {
    case draft
    case finalizing
    case completed
    case interrupted
}

enum WalkOrigin: String, Codable, Equatable, Sendable {
    case papaSteps
    case appleHealth

    var displayName: String {
        switch self {
        case .papaSteps: "papaSteps"
        case .appleHealth: "Apple Health"
        }
    }
}

enum DistanceSource: String, Codable, Sendable {
    case unavailable
    case route
    case pedometer
    case health
}

enum StepSource: String, Codable, Sendable {
    case unavailable
    case motion
    case health
}

enum AltitudeSource: String, Codable, Sendable {
    case unavailable
    case barometer
    case location
}

enum MetricQuality: String, Codable, Sendable {
    case unavailable
    case degraded
    case good
}

enum RouteQuality: String, Codable, Sendable {
    case unavailable
    case degraded
    case good
}

enum RouteQualityReason: String, Codable, Sendable {
    case reducedAccuracy
    case permissionChanged
    case poorSignal
    case insufficientPoints
    case locationUnavailable

    var explanation: String {
        switch self {
        case .reducedAccuracy:
            "Precise Location was off, so route, GPS speed, and direction were unavailable."
        case .permissionChanged:
            "Location access changed during the walk. The saved route ends at the last accepted point."
        case .poorSignal:
            "Some GPS fixes were too inaccurate or implied an impossible jump."
        case .insufficientPoints:
            "There were not enough reliable GPS points to build a route."
        case .locationUnavailable:
            "Location was unavailable while this walk was recorded."
        }
    }
}

enum WalkRecoveryState: String, Codable, Sendable {
    case active
    case paused
}

enum WalkRecoveryCause: String, Codable, Sendable {
    case appRelaunched
    case locationAccessChanged
    case motionAccessChanged

    var explanation: String {
        switch self {
        case .appRelaunched:
            "papaSteps found an unfinished walk from an earlier app session. A recording gap may exist after the last checkpoint."
        case .locationAccessChanged:
            "Location access changed in Settings while this walk was active. The route stops at the last accepted GPS point."
        case .motionAccessChanged:
            "Motion & Fitness access changed in Settings while this walk was active. Step and elevation updates stop at the last checkpoint."
        }
    }
}

enum HealthEnrichmentStatus: String, Codable, Sendable {
    case notRequested
    case pending
    case completed
    case unavailable
    case failed
}

struct NewTrackPoint: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let horizontalAccuracy: Double
    let verticalAccuracy: Double
    let speed: Double?
    let speedAccuracy: Double?
    let course: Double?
    let courseAccuracy: Double?
    let isAccepted: Bool
    let rejectionReason: String?
    let startsNewSegment: Bool

    var coordinate: WalkCoordinate {
        WalkCoordinate(latitude: latitude, longitude: longitude)
    }
}

struct NewWalkRecord: Codable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    let startDate: Date
    let endDate: Date
    let timeZoneIdentifier: String
    let elapsedDuration: TimeInterval
    let movingDuration: TimeInterval
    let pausedDuration: TimeInterval
    let displayDistance: Double?
    let distanceSource: DistanceSource
    let routeDistance: Double?
    let pedometerDistance: Double?
    let displaySteps: Int?
    let stepSource: StepSource
    let motionSteps: Int?
    let averageSpeed: Double?
    let maximumSustainedSpeed: Double?
    let startAltitude: Double?
    let endAltitude: Double?
    let elevationGain: Double?
    let altitudeSource: AltitudeSource
    let altitudeQuality: MetricQuality
    let routeQuality: RouteQuality
    let routeQualityReason: RouteQualityReason?
    let acceptedLocationCount: Int
    let rejectedLocationCount: Int
    let trackPoints: [NewTrackPoint]

    static func sample(
        id: UUID = UUID(),
        startDate: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> NewWalkRecord {
        let endDate = startDate.addingTimeInterval(600)
        return NewWalkRecord(
            id: id,
            createdAt: startDate,
            startDate: startDate,
            endDate: endDate,
            timeZoneIdentifier: "Australia/Melbourne",
            elapsedDuration: 600,
            movingDuration: 540,
            pausedDuration: 60,
            displayDistance: 780,
            distanceSource: .route,
            routeDistance: 780,
            pedometerDistance: 760,
            displaySteps: 1_040,
            stepSource: .motion,
            motionSteps: 1_040,
            averageSpeed: 1.44,
            maximumSustainedSpeed: 1.8,
            startAltitude: 31,
            endAltitude: 38,
            elevationGain: 9,
            altitudeSource: .barometer,
            altitudeQuality: .good,
            routeQuality: .good,
            routeQualityReason: nil,
            acceptedLocationCount: 2,
            rejectedLocationCount: 0,
            trackPoints: [
                NewTrackPoint(
                    id: UUID(),
                    timestamp: startDate,
                    latitude: -37.8136,
                    longitude: 144.9631,
                    altitude: 31,
                    horizontalAccuracy: 8,
                    verticalAccuracy: 6,
                    speed: 1.4,
                    speedAccuracy: 0.2,
                    course: 45,
                    courseAccuracy: 8,
                    isAccepted: true,
                    rejectionReason: nil,
                    startsNewSegment: true
                ),
                NewTrackPoint(
                    id: UUID(),
                    timestamp: endDate,
                    latitude: -37.8088,
                    longitude: 144.9682,
                    altitude: 38,
                    horizontalAccuracy: 10,
                    verticalAccuracy: 7,
                    speed: 1.3,
                    speedAccuracy: 0.3,
                    course: 50,
                    courseAccuracy: 10,
                    isAccepted: true,
                    rejectionReason: nil,
                    startsNewSegment: false
                )
            ]
        )
    }
}

struct WalkSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let startDate: Date
    let endDate: Date?
    let timeZoneIdentifier: String
    let elapsedDuration: TimeInterval
    let movingDuration: TimeInterval
    let displayDistance: Double?
    let distanceSource: DistanceSource
    let displaySteps: Int?
    let stepSource: StepSource
    let averageSpeed: Double?
    let elevationGain: Double?
    let routeQuality: RouteQuality
    let routeQualityReason: RouteQualityReason?
    let healthEnrichmentStatus: HealthEnrichmentStatus
    let origin: WalkOrigin
    let healthSourceName: String?
    /// The rule version current when this source walk was saved. Progress always
    /// re-evaluates source data using its active rule set, rather than mutating this value.
    let eligibilityRulesVersion: Int

    init(
        id: UUID,
        startDate: Date,
        endDate: Date?,
        timeZoneIdentifier: String,
        elapsedDuration: TimeInterval,
        movingDuration: TimeInterval,
        displayDistance: Double?,
        distanceSource: DistanceSource,
        displaySteps: Int?,
        stepSource: StepSource,
        averageSpeed: Double?,
        elevationGain: Double?,
        routeQuality: RouteQuality,
        routeQualityReason: RouteQualityReason?,
        healthEnrichmentStatus: HealthEnrichmentStatus,
        origin: WalkOrigin,
        healthSourceName: String?,
        eligibilityRulesVersion: Int = 1
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.elapsedDuration = elapsedDuration
        self.movingDuration = movingDuration
        self.displayDistance = displayDistance
        self.distanceSource = distanceSource
        self.displaySteps = displaySteps
        self.stepSource = stepSource
        self.averageSpeed = averageSpeed
        self.elevationGain = elevationGain
        self.routeQuality = routeQuality
        self.routeQualityReason = routeQualityReason
        self.healthEnrichmentStatus = healthEnrichmentStatus
        self.origin = origin
        self.healthSourceName = healthSourceName
        self.eligibilityRulesVersion = eligibilityRulesVersion
    }
}

struct WalkDetail: Identifiable, Equatable, Sendable {
    let id: UUID
    let summary: WalkSummary
    let pausedDuration: TimeInterval
    let routeDistance: Double?
    let pedometerDistance: Double?
    let healthDistance: Double?
    let healthDistanceSourceIdentifier: String?
    let healthDistanceSourceName: String?
    let motionSteps: Int?
    let healthSteps: Int?
    let healthStepSourceIdentifier: String?
    let healthStepSourceName: String?
    let maximumSustainedSpeed: Double?
    let startAltitude: Double?
    let endAltitude: Double?
    let elevationGain: Double?
    let altitudeSource: AltitudeSource
    let altitudeQuality: MetricQuality
    let averageHeartRate: Double?
    let heartRateSampleCount: Int
    let heartRateCoveredDuration: TimeInterval?
    let heartRateQuality: MetricQuality
    let heartRateSourceName: String?
    let walkingAsymmetryAverage: Double?
    let walkingAsymmetrySampleCount: Int
    let walkingAsymmetryCoveredDuration: TimeInterval?
    let walkingAsymmetryQuality: MetricQuality
    let walkingAsymmetrySourceName: String?
    let healthKitWorkoutUUID: UUID?
    let healthWorkoutExportStatus: HealthWorkoutExportStatus
    let healthWorkoutExportError: String?
    let healthEnrichmentStatus: HealthEnrichmentStatus
    let healthEnrichmentError: String?
    let healthEnrichedAt: Date?
    let acceptedLocationCount: Int
    let rejectedLocationCount: Int
    let trackPoints: [NewTrackPoint]
    let origin: WalkOrigin
    let healthSourceName: String?
    let healthSourceBundleIdentifier: String?
    let healthImportedAt: Date?

    var routeCoordinates: [WalkCoordinate] {
        trackPoints.filter(\.isAccepted).map(\.coordinate)
    }

    var routeSegments: [[WalkCoordinate]] {
        trackPoints
            .filter(\.isAccepted)
            .reduce(into: [[WalkCoordinate]]()) { segments, point in
                if point.startsNewSegment || segments.isEmpty {
                    segments.append([point.coordinate])
                } else {
                    segments[segments.count - 1].append(point.coordinate)
                }
            }
    }

    var healthInput: HealthWalkInput? {
        guard let endDate = summary.endDate else { return nil }
        return HealthWalkInput(
            id: id,
            startDate: summary.startDate,
            endDate: endDate,
            movingDuration: summary.movingDuration,
            displayDistance: summary.displayDistance,
            routeDistance: routeDistance,
            pedometerDistance: pedometerDistance,
            motionSteps: motionSteps,
            routeQuality: summary.routeQuality,
            trackPoints: trackPoints
        )
    }
}

struct WalkEngineCheckpoint: Codable, Equatable, Sendable {
    let id: UUID
    let startDate: Date
    let timeZoneIdentifier: String
    let lastCheckpointDate: Date
    let recoveryState: WalkRecoveryState
    var recoveryCause: WalkRecoveryCause?

    let lastTickDate: Date?
    let elapsedDuration: TimeInterval
    let movingDuration: TimeInterval
    let pausedDuration: TimeInterval

    let rawSteps: Int?
    let rawPedometerDistance: Double?
    let latestPedometerEndDate: Date?
    let pausedStepsOffset: Int
    let pausedDistanceOffset: Double
    let pauseStepsBaseline: Int?
    let pauseDistanceBaseline: Double?
    let lastStepChangeDate: Date?
    let pedometerSpeed: Double?
    let pedometerSpeedDate: Date?
    let pedometerUnavailableReason: String?

    let routeDistance: Double
    let acceptedLocationCount: Int
    let rejectedLocationCount: Int
    let lastAcceptedLocation: WalkLocationSample?
    let currentCoordinate: WalkCoordinate?
    let locationAccuracy: LocationAccuracyState
    let routeLimitation: RouteLimitation?
    let locationUnavailableReason: String?
    let routeSegmentStartPending: Bool
    let trackPoints: [NewTrackPoint]

    let smoothedSpeed: Double?
    let maximumSustainedSpeed: Double?
    let lastSpeedDate: Date?
    let smoothedDirection: Double?
    let lastDirectionDate: Date?

    let relativeAltitudeStreamID: UUID?
    let filteredRelativeAltitude: Double?
    let relativeAltitudeReference: Double?
    let accumulatedAscent: Double
    let hasRelativeAltitudeSample: Bool
    let relativeAltitudeUnavailableReason: String?

    let startAbsoluteAltitude: Double?
    let currentAbsoluteAltitude: Double?
    let absoluteAltitudeDate: Date?
    let altitudeSource: AltitudeSource
    let altitudeQuality: MetricQuality
    let absoluteAltitudeUnavailableReason: String?

    let displayDistance: Double?
    let distanceSource: DistanceSource
    let displaySteps: Int?
    let averageSpeed: Double?
    let routeQuality: RouteQuality
    let routeQualityReason: RouteQualityReason?

    static func sample(
        id: UUID,
        startDate: Date,
        state: WalkRecoveryState = .active
    ) -> WalkEngineCheckpoint {
        WalkEngineCheckpoint(
            id: id,
            startDate: startDate,
            timeZoneIdentifier: "Australia/Melbourne",
            lastCheckpointDate: startDate,
            recoveryState: state,
            recoveryCause: nil,
            lastTickDate: startDate,
            elapsedDuration: 0,
            movingDuration: 0,
            pausedDuration: 0,
            rawSteps: nil,
            rawPedometerDistance: nil,
            latestPedometerEndDate: nil,
            pausedStepsOffset: 0,
            pausedDistanceOffset: 0,
            pauseStepsBaseline: nil,
            pauseDistanceBaseline: nil,
            lastStepChangeDate: nil,
            pedometerSpeed: nil,
            pedometerSpeedDate: nil,
            pedometerUnavailableReason: nil,
            routeDistance: 0,
            acceptedLocationCount: 0,
            rejectedLocationCount: 0,
            lastAcceptedLocation: nil,
            currentCoordinate: nil,
            locationAccuracy: .full,
            routeLimitation: nil,
            locationUnavailableReason: nil,
            routeSegmentStartPending: true,
            trackPoints: [],
            smoothedSpeed: nil,
            maximumSustainedSpeed: nil,
            lastSpeedDate: nil,
            smoothedDirection: nil,
            lastDirectionDate: nil,
            relativeAltitudeStreamID: nil,
            filteredRelativeAltitude: nil,
            relativeAltitudeReference: nil,
            accumulatedAscent: 0,
            hasRelativeAltitudeSample: false,
            relativeAltitudeUnavailableReason: nil,
            startAbsoluteAltitude: nil,
            currentAbsoluteAltitude: nil,
            absoluteAltitudeDate: nil,
            altitudeSource: .unavailable,
            altitudeQuality: .unavailable,
            absoluteAltitudeUnavailableReason: nil,
            displayDistance: nil,
            distanceSource: .unavailable,
            displaySteps: nil,
            averageSpeed: nil,
            routeQuality: .unavailable,
            routeQualityReason: .insufficientPoints
        )
    }
}
