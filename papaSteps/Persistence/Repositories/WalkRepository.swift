import Foundation
import SwiftData

@MainActor
protocol WalkRepository: AnyObject {
    @discardableResult
    func insert(_ newWalk: NewWalkRecord) throws -> WalkSummary
    @discardableResult
    func complete(_ newWalk: NewWalkRecord) throws -> WalkSummary
    func saveDraft(_ checkpoint: WalkEngineCheckpoint) throws
    func fetchRecoverableDraft() throws -> WalkEngineCheckpoint?
    func markDraftInterrupted(
        id: UUID,
        cause: WalkRecoveryCause
    ) throws -> WalkEngineCheckpoint?
    func fetchSummaries() throws -> [WalkSummary]
    func fetchDetail(id: UUID) throws -> WalkDetail?
    /// A route reduced to at most `maximumPoints`, for list thumbnails.
    func fetchRoutePreview(id: UUID, maximumPoints: Int) throws -> [WalkCoordinate]
    func importedHealthWorkoutIDs(in ids: Set<UUID>) throws -> Set<UUID>
    @discardableResult
    func importHealthWorkout(
        _ importedWorkout: HealthWalkingWorkoutImport,
        importedAt: Date,
        fallbackTimeZoneIdentifier: String
    ) throws -> WalkSummary
    func updateHealthEnrichmentStatus(
        id: UUID,
        status: HealthEnrichmentStatus,
        errorMessage: String?
    ) throws
    @discardableResult
    func applyHealthEnrichment(
        id: UUID,
        enrichment: WalkHealthEnrichment
    ) throws -> WalkDetail?
    @discardableResult
    func updateWorkoutExport(
        id: UUID,
        status: HealthWorkoutExportStatus,
        workoutUUID: UUID?,
        errorMessage: String?
    ) throws -> WalkDetail?
    func deleteWalk(id: UUID) throws
    func deleteAllWalks() throws
}

@MainActor
enum PersistenceContainer {
    static func make(isStoredInMemoryOnly: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: PapaStepsSchemaV4.self)
        let configuration = ModelConfiguration(
            "papaSteps",
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            cloudKitDatabase: .none
        )

        return try ModelContainer(
            for: schema,
            migrationPlan: PapaStepsMigrationPlan.self,
            configurations: configuration
        )
    }
}

@MainActor
final class SwiftDataWalkRepository: WalkRepository {
    private let modelContainer: ModelContainer
    private let context: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        context = modelContainer.mainContext
        context.autosaveEnabled = false
    }

    @discardableResult
    func insert(_ newWalk: NewWalkRecord) throws -> WalkSummary {
        try complete(newWalk)
    }

    @discardableResult
    func complete(_ newWalk: NewWalkRecord) throws -> WalkSummary {
        let record = try fetchRecord(id: newWalk.id) ?? makeRecord(
            id: newWalk.id,
            createdAt: newWalk.createdAt,
            startDate: newWalk.startDate,
            timeZoneIdentifier: newWalk.timeZoneIdentifier
        )

        apply(newWalk, to: record)
        record.finalizationStatus = .completed
        record.recoveryNote = nil
        record.recoveryState = nil
        record.recoveryCause = nil
        record.checkpointData = nil
        syncTrackPoints(newWalk.trackPoints, with: record, removeMissing: true)
        try context.save()
        return summary(from: record)
    }

    func saveDraft(_ checkpoint: WalkEngineCheckpoint) throws {
        let record = try fetchRecord(id: checkpoint.id) ?? makeRecord(
            id: checkpoint.id,
            createdAt: checkpoint.startDate,
            startDate: checkpoint.startDate,
            timeZoneIdentifier: checkpoint.timeZoneIdentifier
        )

        record.schemaVersion = 4
        record.updatedAt = checkpoint.lastCheckpointDate
        record.endDate = nil
        record.elapsedDuration = checkpoint.elapsedDuration
        record.movingDuration = checkpoint.movingDuration
        record.pausedDuration = checkpoint.pausedDuration
        record.finalizationStatus = checkpoint.recoveryCause == nil ? .draft : .interrupted
        record.recoveryNote = checkpoint.recoveryCause?.explanation
        record.recoveryState = checkpoint.recoveryState
        record.recoveryCause = checkpoint.recoveryCause
        record.checkpointData = try encoder.encode(checkpoint)
        record.displayDistance = checkpoint.displayDistance
        record.distanceSource = checkpoint.distanceSource
        record.routeDistance = checkpoint.routeDistance > 0 ? checkpoint.routeDistance : nil
        record.pedometerDistance = checkpoint.rawPedometerDistance
        record.displaySteps = checkpoint.displaySteps
        record.stepSource = checkpoint.displaySteps == nil ? .unavailable : .motion
        record.motionSteps = checkpoint.displaySteps
        record.averageSpeed = checkpoint.averageSpeed
        record.maximumSustainedSpeed = checkpoint.maximumSustainedSpeed
        record.startAltitude = checkpoint.startAbsoluteAltitude
        record.endAltitude = checkpoint.currentAbsoluteAltitude
        record.elevationGain = checkpoint.hasRelativeAltitudeSample
            ? checkpoint.accumulatedAscent : nil
        record.altitudeSource = checkpoint.altitudeSource
        record.altitudeQuality = checkpoint.altitudeQuality
        record.routeQuality = checkpoint.routeQuality
        record.routeQualityReason = checkpoint.routeQualityReason
        record.acceptedPointCount = checkpoint.acceptedLocationCount
        record.rejectedPointCount = checkpoint.rejectedLocationCount
        syncTrackPoints(checkpoint.trackPoints, with: record, removeMissing: false)
        try context.save()
    }

    func fetchRecoverableDraft() throws -> WalkEngineCheckpoint? {
        let descriptor = FetchDescriptor<WalkRecord>(
            predicate: #Predicate { $0.endDate == nil },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        for record in try context.fetch(descriptor) {
            guard record.finalizationStatus != .completed,
                  let data = record.checkpointData,
                  var checkpoint = try? decoder.decode(
                    WalkEngineCheckpoint.self,
                    from: data
                  ) else {
                continue
            }
            checkpoint.recoveryCause = record.recoveryCause
            return checkpoint
        }
        return nil
    }

    func markDraftInterrupted(
        id: UUID,
        cause: WalkRecoveryCause
    ) throws -> WalkEngineCheckpoint? {
        guard let record = try fetchRecord(id: id),
              let data = record.checkpointData,
              var checkpoint = try? decoder.decode(
                WalkEngineCheckpoint.self,
                from: data
              ) else {
            return nil
        }
        checkpoint.recoveryCause = cause
        record.finalizationStatus = .interrupted
        record.recoveryCause = cause
        record.recoveryNote = cause.explanation
        record.checkpointData = try encoder.encode(checkpoint)
        try context.save()
        return checkpoint
    }

    func fetchSummaries() throws -> [WalkSummary] {
        let descriptor = FetchDescriptor<WalkRecord>(
            predicate: #Predicate { $0.endDate != nil },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        return try context.fetch(descriptor).map(summary(from:))
    }

    func fetchRoutePreview(id: UUID, maximumPoints: Int) throws -> [WalkCoordinate] {
        guard maximumPoints > 1, let record = try fetchRecord(id: id) else { return [] }

        let points = record.trackPoints
            .sorted { $0.timestamp < $1.timestamp }
        guard points.count > 1 else {
            return points.map { WalkCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
        }

        let stride = max(1, points.count / maximumPoints)
        var preview = points
            .enumerated()
            .filter { $0.offset.isMultiple(of: stride) }
            .map { WalkCoordinate(latitude: $0.element.latitude, longitude: $0.element.longitude) }
        // Keep the true end point: a thumbnail that stops short looks like a
        // truncated walk.
        if let last = points.last {
            let endpoint = WalkCoordinate(latitude: last.latitude, longitude: last.longitude)
            if preview.last != endpoint {
                preview.append(endpoint)
            }
        }
        return preview
    }

    func fetchDetail(id: UUID) throws -> WalkDetail? {
        guard let record = try fetchRecord(id: id),
              record.finalizationStatus == .completed else {
            return nil
        }
        let points = record.trackPoints
            .sorted { $0.timestamp < $1.timestamp }
            .map(newTrackPoint(from:))
        return WalkDetail(
            id: record.id,
            summary: summary(from: record),
            pausedDuration: record.pausedDuration,
            routeDistance: record.routeDistance,
            pedometerDistance: record.pedometerDistance,
            healthDistance: record.healthDistance,
            healthDistanceSourceIdentifier: record.healthDistanceSourceIdentifier,
            healthDistanceSourceName: record.healthDistanceSourceName,
            motionSteps: record.motionSteps,
            healthSteps: record.healthSteps,
            healthStepSourceIdentifier: record.healthStepSourceIdentifier,
            healthStepSourceName: record.healthStepSourceName,
            maximumSustainedSpeed: record.maximumSustainedSpeed,
            startAltitude: record.startAltitude,
            endAltitude: record.endAltitude,
            elevationGain: record.elevationGain,
            altitudeSource: record.altitudeSource,
            altitudeQuality: record.altitudeQuality,
            averageHeartRate: record.averageHeartRate,
            heartRateSampleCount: record.heartRateSampleCount,
            heartRateCoveredDuration: record.heartRateCoveredDuration,
            heartRateQuality: record.heartRateQuality,
            heartRateSourceName: record.heartRateSourceName,
            walkingAsymmetryAverage: record.walkingAsymmetryAverage,
            walkingAsymmetrySampleCount: record.walkingAsymmetrySampleCount,
            walkingAsymmetryCoveredDuration: record.walkingAsymmetryCoveredDuration,
            walkingAsymmetryQuality: record.walkingAsymmetryQuality,
            walkingAsymmetrySourceName: record.walkingAsymmetrySourceName,
            healthKitWorkoutUUID: record.healthKitWorkoutUUID,
            healthWorkoutExportStatus: record.healthWorkoutExportStatusRawValue
                .flatMap(HealthWorkoutExportStatus.init(rawValue:)) ?? .disabled,
            healthWorkoutExportError: record.healthWorkoutExportError,
            healthEnrichmentStatus: record.healthEnrichmentStatus,
            healthEnrichmentError: record.healthEnrichmentError,
            healthEnrichedAt: record.healthEnrichedAt,
            acceptedLocationCount: record.acceptedPointCount,
            rejectedLocationCount: record.rejectedPointCount,
            trackPoints: points,
            origin: origin(from: record),
            healthSourceName: record.healthSourceName,
            healthSourceBundleIdentifier: record.healthSourceBundleIdentifier,
            healthImportedAt: record.healthImportedAt
        )
    }

    func importedHealthWorkoutIDs(in ids: Set<UUID>) throws -> Set<UUID> {
        guard !ids.isEmpty else { return [] }
        let descriptor = FetchDescriptor<WalkRecord>(
            predicate: #Predicate { $0.healthKitWorkoutUUID != nil }
        )
        return Set(
            try context.fetch(descriptor)
                .compactMap(\.healthKitWorkoutUUID)
                .filter(ids.contains)
        )
    }

    @discardableResult
    func importHealthWorkout(
        _ importedWorkout: HealthWalkingWorkoutImport,
        importedAt: Date,
        fallbackTimeZoneIdentifier: String
    ) throws -> WalkSummary {
        let workout = importedWorkout.workout
        if let existing = try fetchRecord(healthKitWorkoutUUID: workout.id) {
            return summary(from: existing)
        }

        let record = makeRecord(
            id: UUID(),
            createdAt: importedAt,
            startDate: workout.startDate,
            timeZoneIdentifier: workout.timeZoneIdentifier
                ?? fallbackTimeZoneIdentifier
        )
        record.schemaVersion = 4
        record.updatedAt = importedAt
        record.endDate = workout.endDate
        record.elapsedDuration = workout.elapsedDuration
        record.movingDuration = workout.movingDuration
        record.pausedDuration = workout.pausedDuration
        record.finalizationStatus = .completed
        record.displayDistance = workout.distanceMeters
        record.distanceSource = workout.distanceMeters == nil ? .unavailable : .health
        record.healthDistance = workout.distanceMeters
        record.healthDistanceSourceIdentifier = workout.sourceBundleIdentifier
        record.healthDistanceSourceName = workout.sourceName
        record.averageSpeed = workout.distanceMeters.flatMap { distance in
            workout.movingDuration > 0 ? distance / workout.movingDuration : nil
        }
        record.startAltitude = importedWorkout.routePoints.first?.altitude
        record.endAltitude = importedWorkout.routePoints.last?.altitude
        record.altitudeSource = importedWorkout.routePoints.isEmpty
            ? .unavailable : .location
        record.altitudeQuality = .unavailable
        record.routeQuality = importedWorkout.routePoints.count >= 2
            ? .good : .unavailable
        record.routeQualityReason = importedWorkout.routePoints.count >= 2
            ? nil : .insufficientPoints
        record.acceptedPointCount = importedWorkout.routePoints.count
        record.rejectedPointCount = 0
        record.originRawValue = WalkOrigin.appleHealth.rawValue
        record.healthSourceName = workout.sourceName
        record.healthSourceBundleIdentifier = workout.sourceBundleIdentifier
        record.healthImportedAt = importedAt
        record.healthKitWorkoutUUID = workout.id
        record.healthWorkoutExportStatusRawValue = HealthWorkoutExportStatus.disabled.rawValue
        record.healthEnrichmentStatus = .notRequested
        syncTrackPoints(importedWorkout.routePoints, with: record, removeMissing: true)
        try context.save()
        return summary(from: record)
    }

    func updateHealthEnrichmentStatus(
        id: UUID,
        status: HealthEnrichmentStatus,
        errorMessage: String?
    ) throws {
        guard let record = try fetchRecord(id: id) else { return }
        record.healthEnrichmentStatus = status
        record.healthEnrichmentError = errorMessage
        try context.save()
    }

    @discardableResult
    func applyHealthEnrichment(
        id: UUID,
        enrichment: WalkHealthEnrichment
    ) throws -> WalkDetail? {
        guard let record = try fetchRecord(id: id), record.endDate != nil else {
            return nil
        }

        record.averageHeartRate = enrichment.heartRate.value
        record.heartRateSampleCount = enrichment.heartRate.sampleCount
        record.heartRateCoveredDuration = enrichment.heartRate.coveredDuration
        record.heartRateQuality = enrichment.heartRate.quality
        record.heartRateSourceIdentifier = enrichment.heartRate.sourceIdentifier
        record.heartRateSourceName = enrichment.heartRate.sourceName

        record.walkingAsymmetryAverage = enrichment.walkingAsymmetry.value
        record.walkingAsymmetrySampleCount = enrichment.walkingAsymmetry.sampleCount
        record.walkingAsymmetryCoveredDuration = enrichment.walkingAsymmetry.coveredDuration
        record.walkingAsymmetryQuality = enrichment.walkingAsymmetry.quality
        record.walkingAsymmetrySourceIdentifier = enrichment.walkingAsymmetry.sourceIdentifier
        record.walkingAsymmetrySourceName = enrichment.walkingAsymmetry.sourceName

        record.healthSteps = enrichment.steps.value.map { Int($0.rounded()) }
        record.healthStepSourceIdentifier = enrichment.steps.sourceIdentifier
        record.healthStepSourceName = enrichment.steps.sourceName
        record.healthDistance = enrichment.distance.value
        record.healthDistanceSourceIdentifier = enrichment.distance.sourceIdentifier
        record.healthDistanceSourceName = enrichment.distance.sourceName

        reconcileCanonicalMetrics(record)
        record.healthEnrichmentStatus = .completed
        record.healthEnrichmentError = nil
        record.healthEnrichedAt = enrichment.enrichedAt
        record.updatedAt = enrichment.enrichedAt
        try context.save()
        return try fetchDetail(id: id)
    }

    @discardableResult
    func updateWorkoutExport(
        id: UUID,
        status: HealthWorkoutExportStatus,
        workoutUUID: UUID?,
        errorMessage: String?
    ) throws -> WalkDetail? {
        guard let record = try fetchRecord(id: id) else { return nil }
        record.healthWorkoutExportStatusRawValue = status.rawValue
        record.healthWorkoutExportError = errorMessage
        if let workoutUUID {
            record.healthKitWorkoutUUID = workoutUUID
        }
        try context.save()
        return try fetchDetail(id: id)
    }

    func deleteWalk(id: UUID) throws {
        guard let record = try fetchRecord(id: id) else { return }
        context.delete(record)
        try context.save()
    }

    func deleteAllWalks() throws {
        let records = try context.fetch(FetchDescriptor<WalkRecord>())
        for record in records {
            context.delete(record)
        }
        try context.save()
    }

    private func makeRecord(
        id: UUID,
        createdAt: Date,
        startDate: Date,
        timeZoneIdentifier: String
    ) -> WalkRecord {
        let record = WalkRecord(
            id: id,
            createdAt: createdAt,
            startDate: startDate,
            timeZoneIdentifier: timeZoneIdentifier
        )
        context.insert(record)
        return record
    }

    private func apply(_ newWalk: NewWalkRecord, to record: WalkRecord) {
        record.schemaVersion = 4
        record.originRawValue = WalkOrigin.papaSteps.rawValue
        record.updatedAt = newWalk.endDate
        record.endDate = newWalk.endDate
        record.timeZoneIdentifier = newWalk.timeZoneIdentifier
        record.elapsedDuration = newWalk.elapsedDuration
        record.movingDuration = newWalk.movingDuration
        record.pausedDuration = newWalk.pausedDuration
        record.displayDistance = newWalk.displayDistance
        record.distanceSource = newWalk.distanceSource
        record.routeDistance = newWalk.routeDistance
        record.pedometerDistance = newWalk.pedometerDistance
        record.displaySteps = newWalk.displaySteps
        record.stepSource = newWalk.stepSource
        record.motionSteps = newWalk.motionSteps
        record.averageSpeed = newWalk.averageSpeed
        record.maximumSustainedSpeed = newWalk.maximumSustainedSpeed
        record.startAltitude = newWalk.startAltitude
        record.endAltitude = newWalk.endAltitude
        record.elevationGain = newWalk.elevationGain
        record.altitudeSource = newWalk.altitudeSource
        record.altitudeQuality = newWalk.altitudeQuality
        record.routeQuality = newWalk.routeQuality
        record.routeQualityReason = newWalk.routeQualityReason
        record.acceptedPointCount = newWalk.acceptedLocationCount
        record.rejectedPointCount = newWalk.rejectedLocationCount
    }

    private func syncTrackPoints(
        _ newPoints: [NewTrackPoint],
        with record: WalkRecord,
        removeMissing: Bool
    ) {
        let desiredIDs = Set(newPoints.map(\.id))
        let existingByID = Dictionary(
            uniqueKeysWithValues: record.trackPoints.map { ($0.id, $0) }
        )

        if removeMissing {
            for point in record.trackPoints where !desiredIDs.contains(point.id) {
                context.delete(point)
            }
        }

        for newPoint in newPoints where existingByID[newPoint.id] == nil {
            let point = WalkTrackPoint(
                id: newPoint.id,
                timestamp: newPoint.timestamp,
                latitude: newPoint.latitude,
                longitude: newPoint.longitude,
                altitude: newPoint.altitude,
                horizontalAccuracy: newPoint.horizontalAccuracy,
                verticalAccuracy: newPoint.verticalAccuracy,
                speed: newPoint.speed,
                speedAccuracy: newPoint.speedAccuracy,
                course: newPoint.course,
                courseAccuracy: newPoint.courseAccuracy,
                isAccepted: newPoint.isAccepted,
                rejectionReason: newPoint.rejectionReason,
                startsNewSegment: newPoint.startsNewSegment
            )
            point.walk = record
            context.insert(point)
        }
    }

    private func reconcileCanonicalMetrics(_ record: WalkRecord) {
        if let motionSteps = record.motionSteps {
            record.displaySteps = motionSteps
            record.stepSource = .motion
        } else if let healthSteps = record.healthSteps {
            record.displaySteps = healthSteps
            record.stepSource = .health
        } else {
            record.displaySteps = nil
            record.stepSource = .unavailable
        }

        if record.routeQuality == .good,
           let routeDistance = record.routeDistance,
           routeDistance > 0 {
            record.displayDistance = routeDistance
            record.distanceSource = .route
        } else if let pedometerDistance = record.pedometerDistance,
                  pedometerDistance > 0 {
            record.displayDistance = pedometerDistance
            record.distanceSource = .pedometer
        } else if let healthDistance = record.healthDistance,
                  healthDistance > 0 {
            record.displayDistance = healthDistance
            record.distanceSource = .health
        } else if let routeDistance = record.routeDistance,
                  routeDistance > 0 {
            record.displayDistance = routeDistance
            record.distanceSource = .route
        } else {
            record.displayDistance = nil
            record.distanceSource = .unavailable
        }

        if let distance = record.displayDistance, record.movingDuration > 0 {
            record.averageSpeed = distance / record.movingDuration
        } else {
            record.averageSpeed = nil
        }
    }

    private func fetchRecord(id: UUID) throws -> WalkRecord? {
        let targetID = id
        let descriptor = FetchDescriptor<WalkRecord>(
            predicate: #Predicate { $0.id == targetID }
        )
        return try context.fetch(descriptor).first
    }

    private func fetchRecord(healthKitWorkoutUUID: UUID) throws -> WalkRecord? {
        let targetID = healthKitWorkoutUUID
        let descriptor = FetchDescriptor<WalkRecord>(
            predicate: #Predicate { $0.healthKitWorkoutUUID == targetID }
        )
        return try context.fetch(descriptor).first
    }

    private func origin(from record: WalkRecord) -> WalkOrigin {
        record.originRawValue.flatMap(WalkOrigin.init(rawValue:)) ?? .papaSteps
    }

    private func summary(from record: WalkRecord) -> WalkSummary {
        WalkSummary(
            id: record.id,
            startDate: record.startDate,
            endDate: record.endDate,
            timeZoneIdentifier: record.timeZoneIdentifier,
            elapsedDuration: record.elapsedDuration,
            movingDuration: record.movingDuration,
            displayDistance: record.displayDistance,
            distanceSource: record.distanceSource,
            displaySteps: record.displaySteps,
            stepSource: record.stepSource,
            averageSpeed: record.averageSpeed,
            elevationGain: record.elevationGain,
            routeQuality: record.routeQuality,
            routeQualityReason: record.routeQualityReason,
            healthEnrichmentStatus: record.healthEnrichmentStatus,
            origin: origin(from: record),
            healthSourceName: record.healthSourceName,
            eligibilityRulesVersion: record.eligibilityRulesVersion
        )
    }

    private func newTrackPoint(from point: WalkTrackPoint) -> NewTrackPoint {
        NewTrackPoint(
            id: point.id,
            timestamp: point.timestamp,
            latitude: point.latitude,
            longitude: point.longitude,
            altitude: point.altitude,
            horizontalAccuracy: point.horizontalAccuracy,
            verticalAccuracy: point.verticalAccuracy,
            speed: point.speed,
            speedAccuracy: point.speedAccuracy,
            course: point.course,
            courseAccuracy: point.courseAccuracy,
            isAccepted: point.isAccepted,
            rejectionReason: point.rejectionReason,
            startsNewSegment: point.startsNewSegment
        )
    }
}
