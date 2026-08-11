import Foundation
import SwiftData

enum PapaStepsSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [WalkRecord.self, WalkTrackPoint.self]
    }

    @Model
    final class WalkRecord {
        #Index<WalkRecord>([\.startDate])

        @Attribute(.unique) var id: UUID
        var schemaVersion: Int
        var createdAt: Date
        var updatedAt: Date
        var startDate: Date
        var endDate: Date?
        var timeZoneIdentifier: String

        var elapsedDuration: TimeInterval
        var movingDuration: TimeInterval
        var pausedDuration: TimeInterval

        var finalizationStatus: WalkFinalizationStatus
        var recoveryNote: String?
        var recoveryState: WalkRecoveryState?
        var recoveryCause: WalkRecoveryCause?
        var checkpointData: Data?

        var displayDistance: Double?
        var distanceSource: DistanceSource
        var routeDistance: Double?
        var pedometerDistance: Double?
        var healthDistance: Double?
        var healthDistanceSourceIdentifier: String?
        var healthDistanceSourceName: String?

        var displaySteps: Int?
        var stepSource: StepSource
        var motionSteps: Int?
        var healthSteps: Int?
        var healthStepSourceIdentifier: String?
        var healthStepSourceName: String?

        var averageSpeed: Double?
        var maximumSustainedSpeed: Double?

        var startAltitude: Double?
        var endAltitude: Double?
        var elevationGain: Double?
        var elevationLoss: Double?
        var altitudeSource: AltitudeSource
        var altitudeQuality: MetricQuality

        var averageHeartRate: Double?
        var heartRateSampleCount: Int
        var heartRateCoveredDuration: TimeInterval?
        var heartRateQuality: MetricQuality
        var heartRateSourceIdentifier: String?
        var heartRateSourceName: String?

        var walkingAsymmetryAverage: Double?
        var walkingAsymmetrySampleCount: Int
        var walkingAsymmetryCoveredDuration: TimeInterval?
        var walkingAsymmetryQuality: MetricQuality
        var walkingAsymmetrySourceIdentifier: String?
        var walkingAsymmetrySourceName: String?

        var routeQuality: RouteQuality
        var routeQualityReason: RouteQualityReason?
        var acceptedPointCount: Int
        var rejectedPointCount: Int

        var healthKitWorkoutUUID: UUID?
        var healthWorkoutExportStatusRawValue: String?
        var healthWorkoutExportError: String?
        var healthEnrichmentStatus: HealthEnrichmentStatus
        var healthEnrichmentError: String?
        var healthEnrichedAt: Date?
        var eligibilityRulesVersion: Int

        @Relationship(deleteRule: .cascade, inverse: \WalkTrackPoint.walk)
        var trackPoints: [WalkTrackPoint]

        init(
            id: UUID,
            createdAt: Date,
            startDate: Date,
            timeZoneIdentifier: String
        ) {
            self.id = id
            schemaVersion = 3
            self.createdAt = createdAt
            updatedAt = createdAt
            self.startDate = startDate
            endDate = nil
            self.timeZoneIdentifier = timeZoneIdentifier
            elapsedDuration = 0
            movingDuration = 0
            pausedDuration = 0
            finalizationStatus = .draft
            recoveryNote = nil
            recoveryState = nil
            recoveryCause = nil
            checkpointData = nil
            displayDistance = nil
            distanceSource = .unavailable
            routeDistance = nil
            pedometerDistance = nil
            healthDistance = nil
            healthDistanceSourceIdentifier = nil
            healthDistanceSourceName = nil
            displaySteps = nil
            stepSource = .unavailable
            motionSteps = nil
            healthSteps = nil
            healthStepSourceIdentifier = nil
            healthStepSourceName = nil
            averageSpeed = nil
            maximumSustainedSpeed = nil
            startAltitude = nil
            endAltitude = nil
            elevationGain = nil
            elevationLoss = nil
            altitudeSource = .unavailable
            altitudeQuality = .unavailable
            averageHeartRate = nil
            heartRateSampleCount = 0
            heartRateCoveredDuration = nil
            heartRateQuality = .unavailable
            heartRateSourceIdentifier = nil
            heartRateSourceName = nil
            walkingAsymmetryAverage = nil
            walkingAsymmetrySampleCount = 0
            walkingAsymmetryCoveredDuration = nil
            walkingAsymmetryQuality = .unavailable
            walkingAsymmetrySourceIdentifier = nil
            walkingAsymmetrySourceName = nil
            routeQuality = .unavailable
            routeQualityReason = nil
            acceptedPointCount = 0
            rejectedPointCount = 0
            healthKitWorkoutUUID = nil
            healthWorkoutExportStatusRawValue = HealthWorkoutExportStatus.disabled.rawValue
            healthWorkoutExportError = nil
            healthEnrichmentStatus = .notRequested
            healthEnrichmentError = nil
            healthEnrichedAt = nil
            eligibilityRulesVersion = 1
            trackPoints = []
        }
    }

    @Model
    final class WalkTrackPoint {
        #Index<WalkTrackPoint>([\.timestamp])

        @Attribute(.unique) var id: UUID
        var timestamp: Date
        var latitude: Double
        var longitude: Double
        var altitude: Double
        var horizontalAccuracy: Double
        var verticalAccuracy: Double
        var speed: Double?
        var speedAccuracy: Double?
        var course: Double?
        var courseAccuracy: Double?
        var isAccepted: Bool
        var rejectionReason: String?
        var startsNewSegment: Bool = false
        var walk: WalkRecord?

        init(
            id: UUID,
            timestamp: Date,
            latitude: Double,
            longitude: Double,
            altitude: Double,
            horizontalAccuracy: Double,
            verticalAccuracy: Double,
            speed: Double?,
            speedAccuracy: Double?,
            course: Double?,
            courseAccuracy: Double?,
            isAccepted: Bool,
            rejectionReason: String?,
            startsNewSegment: Bool
        ) {
            self.id = id
            self.timestamp = timestamp
            self.latitude = latitude
            self.longitude = longitude
            self.altitude = altitude
            self.horizontalAccuracy = horizontalAccuracy
            self.verticalAccuracy = verticalAccuracy
            self.speed = speed
            self.speedAccuracy = speedAccuracy
            self.course = course
            self.courseAccuracy = courseAccuracy
            self.isAccepted = isAccepted
            self.rejectionReason = rejectionReason
            self.startsNewSegment = startsNewSegment
            walk = nil
        }
    }
}
