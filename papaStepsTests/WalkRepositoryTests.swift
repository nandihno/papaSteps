import Foundation
import SwiftData
import Testing
@testable import papaSteps

@MainActor
struct WalkRepositoryTests {
    @Test
    func inMemoryRepositoryCreatesFetchesAndCascadeDeletesWalk() throws {
        let container = try PersistenceContainer.make(isStoredInMemoryOnly: true)
        let repository = SwiftDataWalkRepository(modelContainer: container)
        let sample = NewWalkRecord.sample()

        let inserted = try repository.insert(sample)
        let fetched = try repository.fetchSummaries()

        #expect(inserted.id == sample.id)
        #expect(fetched == [inserted])
        #expect(
            try container.mainContext.fetchCount(
                FetchDescriptor<WalkTrackPoint>()
            ) == sample.trackPoints.count
        )

        try repository.deleteWalk(id: sample.id)

        #expect(try repository.fetchSummaries().isEmpty)
        #expect(
            try container.mainContext.fetchCount(
                FetchDescriptor<WalkTrackPoint>()
            ) == 0
        )
    }

    @Test
    func deletingAllLocalWalkDataCascadesToEverySavedTrackPoint() throws {
        let container = try PersistenceContainer.make(isStoredInMemoryOnly: true)
        let repository = SwiftDataWalkRepository(modelContainer: container)
        _ = try repository.insert(NewWalkRecord.sample())
        _ = try repository.insert(NewWalkRecord.sample())
        let draft = WalkEngineCheckpoint.sample(
            id: UUID(),
            startDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
        try repository.saveDraft(draft)

        try repository.deleteAllWalks()

        #expect(try repository.fetchSummaries().isEmpty)
        #expect(try repository.fetchRecoverableDraft() == nil)
        #expect(
            try container.mainContext.fetchCount(
                FetchDescriptor<WalkTrackPoint>()
            ) == 0
        )
    }

    @Test
    func schemaStartsAtVersionOne() {
        #expect(PapaStepsSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(PapaStepsSchemaV2.versionIdentifier == Schema.Version(2, 0, 0))
        #expect(PapaStepsSchemaV3.versionIdentifier == Schema.Version(3, 0, 0))
        #expect(PapaStepsSchemaV4.versionIdentifier == Schema.Version(4, 0, 0))
        #expect(PapaStepsMigrationPlan.schemas.count == 4)
        #expect(PapaStepsMigrationPlan.stages.count == 3)
    }

    @Test
    func versionOneStoreMigratesThroughVersionFourWithoutLosingTheWalk() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appending(path: "papaSteps-migration-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: storeURL) }

        try createVersionOneStore(at: storeURL)

        let schema = Schema(versionedSchema: PapaStepsSchemaV4.self)
        let configuration = ModelConfiguration(
            "migration-test",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let migratedContainer = try ModelContainer(
            for: schema,
            migrationPlan: PapaStepsMigrationPlan.self,
            configurations: configuration
        )
        let records = try migratedContainer.mainContext.fetch(
            FetchDescriptor<PapaStepsSchemaV4.WalkRecord>()
        )
        let migrated = try #require(records.first)

        #expect(records.count == 1)
        #expect(migrated.timeZoneIdentifier == "Australia/Melbourne")
        #expect(migrated.routeQualityReason == nil)
        #expect(migrated.recoveryState == nil)
        #expect(migrated.healthWorkoutExportStatusRawValue == nil)
        #expect(migrated.healthStepSourceIdentifier == nil)
        #expect(migrated.originRawValue == nil)
    }

    @Test
    func versionTwoStoreMigratesToVersionFourWithoutLosingPhaseTwoMetadata() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appending(path: "papaSteps-v2-migration-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: storeURL) }

        try createVersionTwoStore(at: storeURL)

        let schema = Schema(versionedSchema: PapaStepsSchemaV4.self)
        let configuration = ModelConfiguration(
            "migration-test",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: PapaStepsMigrationPlan.self,
            configurations: configuration
        )
        let migrated = try #require(
            container.mainContext.fetch(
                FetchDescriptor<PapaStepsSchemaV4.WalkRecord>()
            ).first
        )

        #expect(migrated.routeQualityReason == .reducedAccuracy)
        #expect(migrated.recoveryState == .active)
        #expect(migrated.healthWorkoutExportStatusRawValue == nil)
        #expect(migrated.heartRateSourceIdentifier == nil)
        #expect(migrated.originRawValue == nil)
    }

    @Test
    func insertingTheSameCompletedWalkTwiceIsIdempotent() throws {
        let container = try PersistenceContainer.make(isStoredInMemoryOnly: true)
        let repository = SwiftDataWalkRepository(modelContainer: container)
        let sample = NewWalkRecord.sample()

        let first = try repository.insert(sample)
        let second = try repository.insert(sample)

        #expect(first == second)
        #expect(try repository.fetchSummaries().count == 1)
    }

    @Test
    func importingHealthWorkoutIsIdempotentAndPreservesProvenance() throws {
        let container = try PersistenceContainer.make(isStoredInMemoryOnly: true)
        let repository = SwiftDataWalkRepository(modelContainer: container)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let workoutID = UUID()
        let workout = HealthWalkingWorkout(
            id: workoutID,
            startDate: start,
            endDate: start.addingTimeInterval(720),
            movingDuration: 660,
            distanceMeters: 910,
            sourceName: "Apple Watch",
            sourceBundleIdentifier: "com.apple.health",
            timeZoneIdentifier: "Australia/Melbourne"
        )
        let payload = HealthWalkingWorkoutImport(
            workout: workout,
            routePoints: NewWalkRecord.sample(startDate: start).trackPoints
        )

        let first = try repository.importHealthWorkout(
            payload,
            importedAt: start.addingTimeInterval(1_000),
            fallbackTimeZoneIdentifier: "UTC"
        )
        let second = try repository.importHealthWorkout(
            payload,
            importedAt: start.addingTimeInterval(2_000),
            fallbackTimeZoneIdentifier: "UTC"
        )
        let fetchedDetail = try repository.fetchDetail(id: first.id)
        let detail = try #require(fetchedDetail)

        #expect(first == second)
        #expect(try repository.fetchSummaries().count == 1)
        #expect(first.origin == .appleHealth)
        #expect(first.healthSourceName == "Apple Watch")
        #expect(first.distanceSource == .health)
        #expect(first.displayDistance == 910)
        #expect(detail.healthKitWorkoutUUID == workoutID)
        #expect(detail.healthSourceBundleIdentifier == "com.apple.health")
        #expect(detail.summary.timeZoneIdentifier == "Australia/Melbourne")
        #expect(
            try repository.importedHealthWorkoutIDs(in: [workoutID, UUID()])
                == [workoutID]
        )
    }

    @Test
    func healthEnrichmentUpdatesProvenanceWithoutReplacingGoodLocalTotals() throws {
        let container = try PersistenceContainer.make(isStoredInMemoryOnly: true)
        let repository = SwiftDataWalkRepository(modelContainer: container)
        let sample = NewWalkRecord.sample()
        _ = try repository.insert(sample)
        let date = sample.endDate.addingTimeInterval(60)
        let enrichment = WalkHealthEnrichment(
            heartRate: HealthMetricResult(
                value: 86,
                sampleCount: 4,
                coveredDuration: 300,
                quality: .degraded,
                sourceIdentifier: "watch",
                sourceName: "Apple Watch"
            ),
            walkingAsymmetry: .unavailable,
            steps: HealthMetricResult(
                value: 1_080,
                sampleCount: 8,
                coveredDuration: 540,
                quality: .good,
                sourceIdentifier: "iphone",
                sourceName: "iPhone"
            ),
            distance: HealthMetricResult(
                value: 790,
                sampleCount: 8,
                coveredDuration: 540,
                quality: .good,
                sourceIdentifier: "iphone",
                sourceName: "iPhone"
            ),
            enrichedAt: date
        )

        let detail = try repository.applyHealthEnrichment(
            id: sample.id,
            enrichment: enrichment
        )

        #expect(detail?.averageHeartRate == 86)
        #expect(detail?.heartRateSourceName == "Apple Watch")
        #expect(detail?.healthSteps == 1_080)
        #expect(detail?.healthStepSourceIdentifier == "iphone")
        #expect(detail?.summary.displaySteps == sample.motionSteps)
        #expect(detail?.summary.stepSource == .motion)
        #expect(detail?.summary.displayDistance == sample.routeDistance)
        #expect(detail?.summary.distanceSource == .route)
        #expect(detail?.healthEnrichmentStatus == .completed)
        #expect(try repository.fetchSummaries().count == 1)
    }

    @Test
    func interruptedDraftStaysOutOfHistoryAndCompletesInPlace() async throws {
        let container = try PersistenceContainer.make(isStoredInMemoryOnly: true)
        let repository = SwiftDataWalkRepository(modelContainer: container)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let id = UUID()
        let engine = WalkMetricsEngine()
        _ = await engine.start(
            id: id,
            at: start,
            timeZoneIdentifier: "Australia/Melbourne"
        )
        for (offset, latitude) in [(-37.8136), (-37.8130)].enumerated() {
            let date = start.addingTimeInterval(Double(offset + 1) * 60)
            _ = await engine.ingestLocation(
                WalkLocationSample(
                    coordinate: WalkCoordinate(latitude: latitude, longitude: 144.9631),
                    timestamp: date,
                    altitude: 30,
                    horizontalAccuracy: 6,
                    verticalAccuracy: 5,
                    speed: 1.2,
                    speedAccuracy: 0.3,
                    course: 0,
                    courseAccuracy: 5,
                    accuracyAuthorization: .full
                ),
                receivedAt: date
            )
        }

        let checkpointDate = start.addingTimeInterval(130)
        let checkpoint = try await engine.checkpoint(at: checkpointDate)
        try repository.saveDraft(checkpoint)

        #expect(try repository.fetchSummaries().isEmpty)
        #expect(try repository.fetchRecoverableDraft()?.id == id)
        #expect(
            try container.mainContext.fetchCount(FetchDescriptor<WalkTrackPoint>()) == 2
        )

        let interrupted = try repository.markDraftInterrupted(
            id: id,
            cause: .appRelaunched
        )
        #expect(interrupted?.recoveryCause == .appRelaunched)

        let completed = try await engine.finalize(at: checkpointDate)
        let summary = try repository.complete(completed)
        let loadedDetail = try repository.fetchDetail(id: id)
        let detail = try #require(loadedDetail)

        #expect(summary.id == id)
        #expect(try repository.fetchRecoverableDraft() == nil)
        #expect(try repository.fetchSummaries() == [summary])
        #expect(detail.trackPoints.count == 2)
        #expect(detail.routeCoordinates.count == 2)
    }

    private func createVersionOneStore(at storeURL: URL) throws {
        let schema = Schema(versionedSchema: PapaStepsSchemaV1.self)
        let configuration = ModelConfiguration(
            "migration-test",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            configurations: configuration
        )
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let record = PapaStepsSchemaV1.WalkRecord(
            id: UUID(),
            createdAt: start,
            startDate: start,
            timeZoneIdentifier: "Australia/Melbourne"
        )
        record.endDate = start.addingTimeInterval(600)
        record.finalizationStatus = .completed
        container.mainContext.insert(record)
        try container.mainContext.save()
    }

    private func createVersionTwoStore(at storeURL: URL) throws {
        let schema = Schema(versionedSchema: PapaStepsSchemaV2.self)
        let configuration = ModelConfiguration(
            "migration-test",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            configurations: configuration
        )
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let record = PapaStepsSchemaV2.WalkRecord(
            id: UUID(),
            createdAt: start,
            startDate: start,
            timeZoneIdentifier: "Australia/Melbourne"
        )
        record.endDate = start.addingTimeInterval(600)
        record.finalizationStatus = .completed
        record.routeQualityReason = .reducedAccuracy
        record.recoveryState = .active
        container.mainContext.insert(record)
        try container.mainContext.save()
    }
}
