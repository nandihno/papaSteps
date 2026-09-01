@preconcurrency import CoreLocation
import Foundation
import Testing
@testable import papaSteps

struct WalkMetricsEngineTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func deterministicSamplesProduceStepsDistanceDirectionMovingTimeAndAscent() async {
        var configuration = TrackingConfiguration.live
        configuration.speedSmoothingFactor = 1
        configuration.directionSmoothingFactor = 0.5
        configuration.elevationSmoothingFactor = 1
        configuration.elevationHysteresis = 1
        configuration.movementEvidenceInterval = 10
        let engine = WalkMetricsEngine(configuration: configuration)
        let streamID = UUID()

        _ = await engine.start(
            id: UUID(),
            at: start,
            timeZoneIdentifier: "Australia/Melbourne"
        )
        _ = await engine.ingestPedometer(
            pedometer(steps: 0, distance: 0, at: start),
            receivedAt: start
        )
        _ = await engine.ingestLocation(
            location(
                latitude: -37.81360,
                longitude: 144.96310,
                speed: 1.2,
                course: 359,
                at: start.addingTimeInterval(1)
            ),
            receivedAt: start.addingTimeInterval(1)
        )
        _ = await engine.ingestPedometer(
            pedometer(steps: 120, distance: 90, at: start.addingTimeInterval(2)),
            receivedAt: start.addingTimeInterval(2)
        )
        _ = await engine.ingestRelativeAltitude(
            RelativeAltitudeSample(
                streamID: streamID,
                timestamp: start.addingTimeInterval(2),
                relativeAltitude: 0
            ),
            receivedAt: start.addingTimeInterval(2)
        )
        _ = await engine.ingestRelativeAltitude(
            RelativeAltitudeSample(
                streamID: streamID,
                timestamp: start.addingTimeInterval(3),
                relativeAltitude: 3
            ),
            receivedAt: start.addingTimeInterval(3)
        )
        _ = await engine.ingestLocation(
            location(
                latitude: -37.81351,
                longitude: 144.96310,
                speed: 1.4,
                course: 1,
                at: start.addingTimeInterval(5)
            ),
            receivedAt: start.addingTimeInterval(5)
        )

        let snapshot = await engine.tick(at: start.addingTimeInterval(5))

        #expect(snapshot.steps.value == 120)
        #expect(snapshot.distanceSource == .route)
        #expect((snapshot.distance.value ?? 0) > 9)
        #expect(snapshot.speed.value == 1.4)
        #expect(snapshot.movingDuration == 5)
        #expect(snapshot.elevationGain.value == 3)
        let direction = snapshot.direction.value ?? 180
        #expect(direction < 2 || direction > 358)
    }

    @Test
    func invalidAndStaleLocationValuesNeverBecomeValidZeroes() async {
        let engine = WalkMetricsEngine()
        _ = await engine.start(
            id: UUID(),
            at: start,
            timeZoneIdentifier: "Australia/Melbourne"
        )

        let invalid = await engine.ingestLocation(
            location(
                latitude: -37.8136,
                longitude: 144.9631,
                horizontalAccuracy: 200,
                speed: -1,
                speedAccuracy: -1,
                course: -1,
                at: start.addingTimeInterval(1)
            ),
            receivedAt: start.addingTimeInterval(1)
        )

        #expect(invalid.speed.value == nil)
        #expect(invalid.distance.value == nil)
        #expect(invalid.rejectedLocationCount == 1)

        _ = await engine.ingestLocation(
            location(
                latitude: -37.8136,
                longitude: 144.9631,
                speed: 1.2,
                course: 45,
                at: start.addingTimeInterval(2)
            ),
            receivedAt: start.addingTimeInterval(2)
        )
        let stale = await engine.tick(at: start.addingTimeInterval(20))

        #expect(stale.speed.value == 1.2)
        #expect(stale.speed.availability == .stale)
        #expect(stale.direction.availability == .stale)
    }

    @Test
    func pauseExcludesStepsAndDistanceAndAscentSurvivesStreamRestart() async throws {
        var configuration = TrackingConfiguration.live
        configuration.elevationSmoothingFactor = 1
        configuration.elevationHysteresis = 1
        configuration.movementEvidenceInterval = 10
        let engine = WalkMetricsEngine(configuration: configuration)
        let firstStream = UUID()
        let secondStream = UUID()

        _ = await engine.start(
            id: UUID(),
            at: start,
            timeZoneIdentifier: "Australia/Melbourne"
        )
        _ = await engine.ingestPedometer(
            pedometer(steps: 0, distance: 0, at: start),
            receivedAt: start
        )
        _ = await engine.ingestPedometer(
            pedometer(steps: 10, distance: 10, at: start.addingTimeInterval(1)),
            receivedAt: start.addingTimeInterval(1)
        )
        _ = await engine.ingestRelativeAltitude(
            RelativeAltitudeSample(
                streamID: firstStream,
                timestamp: start.addingTimeInterval(1),
                relativeAltitude: 0
            ),
            receivedAt: start.addingTimeInterval(1)
        )
        let beforePause = await engine.ingestRelativeAltitude(
            RelativeAltitudeSample(
                streamID: firstStream,
                timestamp: start.addingTimeInterval(2),
                relativeAltitude: 4
            ),
            receivedAt: start.addingTimeInterval(2)
        )
        #expect(beforePause.elevationGain.value == 4)

        _ = await engine.pause(at: start.addingTimeInterval(2))
        _ = await engine.ingestPedometer(
            pedometer(steps: 30, distance: 30, at: start.addingTimeInterval(3)),
            receivedAt: start.addingTimeInterval(3)
        )
        _ = await engine.ingestRelativeAltitude(
            RelativeAltitudeSample(
                streamID: firstStream,
                timestamp: start.addingTimeInterval(3),
                relativeAltitude: 8
            ),
            receivedAt: start.addingTimeInterval(3)
        )
        _ = await engine.resume(at: start.addingTimeInterval(4))
        _ = await engine.ingestPedometer(
            pedometer(steps: 35, distance: 35, at: start.addingTimeInterval(5)),
            receivedAt: start.addingTimeInterval(5)
        )
        let restartBaseline = await engine.ingestRelativeAltitude(
            RelativeAltitudeSample(
                streamID: secondStream,
                timestamp: start.addingTimeInterval(5),
                relativeAltitude: 0
            ),
            receivedAt: start.addingTimeInterval(5)
        )
        #expect(restartBaseline.elevationGain.value == 4)

        let afterRestart = await engine.ingestRelativeAltitude(
            RelativeAltitudeSample(
                streamID: secondStream,
                timestamp: start.addingTimeInterval(6),
                relativeAltitude: 3
            ),
            receivedAt: start.addingTimeInterval(6)
        )

        #expect(afterRestart.steps.value == 15)
        #expect(afterRestart.distance.value == 15)
        #expect(afterRestart.elevationGain.value == 7)

        let record = try await engine.finalize(at: start.addingTimeInterval(7))
        #expect(record.motionSteps == 15)
        #expect(record.pedometerDistance == 15)
        #expect(record.elevationGain == 7)
        #expect(record.pausedDuration == 2)
    }

    @Test
    func reconciliationUsesQueriedCumulativeValueWithoutDoubleCounting() async {
        let engine = WalkMetricsEngine()
        _ = await engine.start(
            id: UUID(),
            at: start,
            timeZoneIdentifier: "Australia/Melbourne"
        )
        _ = await engine.ingestPedometer(
            pedometer(steps: 5, distance: 4, at: start.addingTimeInterval(1)),
            receivedAt: start.addingTimeInterval(1)
        )
        let reconciled = await engine.ingestPedometer(
            pedometer(steps: 12, distance: 10, at: start.addingTimeInterval(2)),
            receivedAt: start.addingTimeInterval(2)
        )

        #expect(reconciled.steps.value == 12)
        #expect(reconciled.distance.value == 10)
    }

    @Test
    func olderLivePedometerCallbackCannotOverwriteNewerReconciliation() async {
        let engine = WalkMetricsEngine()
        _ = await engine.start(
            id: UUID(),
            at: start,
            timeZoneIdentifier: "Australia/Melbourne"
        )
        _ = await engine.ingestPedometer(
            pedometer(steps: 20, distance: 16, at: start.addingTimeInterval(10)),
            receivedAt: start.addingTimeInterval(10)
        )
        let snapshot = await engine.ingestPedometer(
            pedometer(steps: 12, distance: 9, at: start.addingTimeInterval(8)),
            receivedAt: start.addingTimeInterval(11)
        )

        #expect(snapshot.steps.value == 20)
        #expect(snapshot.distance.value == 16)
    }

    @Test
    func reducedAccuracyRejectsRouteButKeepsPedometerMetrics() async {
        let engine = WalkMetricsEngine()
        _ = await engine.start(
            id: UUID(),
            at: start,
            timeZoneIdentifier: "Australia/Melbourne"
        )
        _ = await engine.ingestPedometer(
            pedometer(steps: 100, distance: 80, at: start.addingTimeInterval(1)),
            receivedAt: start.addingTimeInterval(1)
        )
        _ = await engine.updateLocationAuthorization(
            .whenInUse,
            accuracy: .reduced,
            at: start.addingTimeInterval(1)
        )
        let snapshot = await engine.ingestLocation(
            location(
                latitude: -37.81,
                longitude: 144.96,
                horizontalAccuracy: 1_000,
                speed: -1,
                speedAccuracy: -1,
                course: -1,
                accuracy: .reduced,
                at: start.addingTimeInterval(2)
            ),
            receivedAt: start.addingTimeInterval(2)
        )

        #expect(snapshot.steps.value == 100)
        #expect(snapshot.distance.value == 80)
        #expect(snapshot.distanceSource == .pedometer)
        #expect(snapshot.routeQuality == .unavailable)
        #expect(snapshot.routeLimitation == .reducedAccuracy)
        #expect(snapshot.routeCoordinates.isEmpty)
        #expect(snapshot.speed.value == nil)

        let record = try? await engine.finalize(at: start.addingTimeInterval(3))
        #expect(record?.routeQualityReason == .reducedAccuracy)
    }

    @Test
    func impossibleJumpIsRejectedAndDoesNotAccumulateRouteDistance() async throws {
        let engine = WalkMetricsEngine()
        _ = await engine.start(
            id: UUID(),
            at: start,
            timeZoneIdentifier: "Australia/Melbourne"
        )
        _ = await engine.ingestLocation(
            location(
                latitude: -37.8136,
                longitude: 144.9631,
                speed: 1,
                course: 0,
                at: start.addingTimeInterval(1)
            ),
            receivedAt: start.addingTimeInterval(1)
        )
        let snapshot = await engine.ingestLocation(
            location(
                latitude: -37.8036,
                longitude: 144.9631,
                speed: 1,
                course: 0,
                at: start.addingTimeInterval(2)
            ),
            receivedAt: start.addingTimeInterval(2)
        )

        #expect(snapshot.acceptedLocationCount == 1)
        #expect(snapshot.rejectedLocationCount == 1)
        #expect(snapshot.distance.value == nil)
        #expect(
            snapshot.currentCoordinate
                == WalkCoordinate(latitude: -37.8136, longitude: 144.9631)
        )

        let record = try await engine.finalize(at: start.addingTimeInterval(3))
        #expect(record.routeDistance == nil)
        #expect(record.rejectedLocationCount == 1)
        #expect(record.trackPoints.count == 2)
        #expect(record.trackPoints.last?.isAccepted == false)
        #expect(
            record.trackPoints.last?.rejectionReason
                == LocationRejectionReason.impossibleJump.rawValue
        )
        #expect(record.routeQualityReason == .poorSignal)
    }

    @Test
    func plausibleFixesAfterImpossibleJumpStartANewRouteSegment() async throws {
        let engine = WalkMetricsEngine()
        _ = await engine.start(
            id: UUID(),
            at: start,
            timeZoneIdentifier: "Australia/Melbourne"
        )
        _ = await engine.ingestLocation(
            location(
                latitude: -37.81360,
                longitude: 144.96310,
                speed: 1.2,
                course: 0,
                at: start.addingTimeInterval(1)
            ),
            receivedAt: start.addingTimeInterval(1)
        )
        _ = await engine.ingestLocation(
            location(
                latitude: -37.80360,
                longitude: 144.96310,
                speed: 1.2,
                course: 0,
                at: start.addingTimeInterval(2)
            ),
            receivedAt: start.addingTimeInterval(2)
        )
        let provisional = await engine.ingestLocation(
            location(
                latitude: -37.80359,
                longitude: 144.96310,
                speed: 1.2,
                course: 0,
                at: start.addingTimeInterval(3)
            ),
            receivedAt: start.addingTimeInterval(3)
        )
        let recovered = await engine.ingestLocation(
            location(
                latitude: -37.80350,
                longitude: 144.96310,
                speed: 1.2,
                course: 0,
                at: start.addingTimeInterval(8)
            ),
            receivedAt: start.addingTimeInterval(8)
        )

        #expect(provisional.acceptedLocationCount == 1)
        #expect(provisional.rejectedLocationCount == 1)
        #expect(recovered.acceptedLocationCount == 3)
        #expect(recovered.rejectedLocationCount == 1)
        #expect(recovered.routeSegments.map { $0.count } == [1, 2])
        #expect((recovered.distance.value ?? 0) > 9)
        #expect(
            recovered.currentCoordinate
                == WalkCoordinate(latitude: -37.80350, longitude: 144.96310)
        )

        let record = try await engine.finalize(at: start.addingTimeInterval(9))
        #expect(record.trackPoints.count == 4)
        #expect(
            record.trackPoints[1].rejectionReason
                == LocationRejectionReason.impossibleJump.rawValue
        )
        #expect(record.trackPoints[2].isAccepted)
        #expect(record.trackPoints[2].startsNewSegment)
        #expect(record.trackPoints[3].isAccepted)
        #expect(!record.trackPoints[3].startsNewSegment)
    }

    @Test
    func inconsistentReacquisitionCandidateIsRejectedAndReplaced() async throws {
        let engine = WalkMetricsEngine()
        _ = await engine.start(
            id: UUID(),
            at: start,
            timeZoneIdentifier: "Australia/Melbourne"
        )
        _ = await engine.ingestLocation(
            location(
                latitude: -37.81360,
                longitude: 144.96310,
                at: start.addingTimeInterval(1)
            ),
            receivedAt: start.addingTimeInterval(1)
        )
        _ = await engine.ingestLocation(
            location(
                latitude: -37.80360,
                longitude: 144.96310,
                at: start.addingTimeInterval(2)
            ),
            receivedAt: start.addingTimeInterval(2)
        )
        _ = await engine.ingestLocation(
            location(
                latitude: -37.80359,
                longitude: 144.96310,
                at: start.addingTimeInterval(3)
            ),
            receivedAt: start.addingTimeInterval(3)
        )
        let replaced = await engine.ingestLocation(
            location(
                latitude: -37.79360,
                longitude: 144.96310,
                at: start.addingTimeInterval(4)
            ),
            receivedAt: start.addingTimeInterval(4)
        )
        let recovered = await engine.ingestLocation(
            location(
                latitude: -37.79351,
                longitude: 144.96310,
                at: start.addingTimeInterval(9)
            ),
            receivedAt: start.addingTimeInterval(9)
        )

        #expect(replaced.acceptedLocationCount == 1)
        #expect(replaced.rejectedLocationCount == 2)
        #expect(recovered.acceptedLocationCount == 3)
        #expect(recovered.rejectedLocationCount == 2)
        #expect(recovered.routeSegments.map { $0.count } == [1, 2])

        let record = try await engine.finalize(at: start.addingTimeInterval(10))
        #expect(
            record.trackPoints[2].rejectionReason
                == LocationRejectionReason.reacquisitionUnconfirmed.rawValue
        )
    }

    @Test
    func locationReacquisitionSurvivesCheckpointRestore() async throws {
        let id = UUID()
        let engine = WalkMetricsEngine()
        _ = await engine.start(
            id: id,
            at: start,
            timeZoneIdentifier: "Australia/Melbourne"
        )
        _ = await engine.ingestLocation(
            location(
                latitude: -37.81360,
                longitude: 144.96310,
                at: start.addingTimeInterval(1)
            ),
            receivedAt: start.addingTimeInterval(1)
        )
        _ = await engine.ingestLocation(
            location(
                latitude: -37.80360,
                longitude: 144.96310,
                at: start.addingTimeInterval(2)
            ),
            receivedAt: start.addingTimeInterval(2)
        )
        _ = await engine.ingestLocation(
            location(
                latitude: -37.80359,
                longitude: 144.96310,
                at: start.addingTimeInterval(3)
            ),
            receivedAt: start.addingTimeInterval(3)
        )
        let checkpoint = try await engine.checkpoint(at: start.addingTimeInterval(3))
        #expect(checkpoint.requiresLocationReacquisition == true)
        #expect(checkpoint.locationReacquisitionCandidate?.timestamp == start.addingTimeInterval(3))

        let restoredEngine = WalkMetricsEngine()
        _ = await restoredEngine.restore(
            from: checkpoint,
            at: start.addingTimeInterval(4)
        )
        let recovered = await restoredEngine.ingestLocation(
            location(
                latitude: -37.80350,
                longitude: 144.96310,
                at: start.addingTimeInterval(8)
            ),
            receivedAt: start.addingTimeInterval(8)
        )

        #expect(recovered.acceptedLocationCount == 3)
        #expect(recovered.rejectedLocationCount == 1)
        #expect(recovered.routeSegments.map { $0.count } == [1, 2])
        #expect((recovered.distance.value ?? 0) > 9)
    }

    @Test
    func rejectedFixDuringReacquisitionKeepsPersistedPointsChronological() async throws {
        let engine = WalkMetricsEngine()
        _ = await engine.start(
            id: UUID(),
            at: start,
            timeZoneIdentifier: "Australia/Melbourne"
        )
        _ = await engine.ingestLocation(
            location(
                latitude: -37.81360,
                longitude: 144.96310,
                at: start.addingTimeInterval(1)
            ),
            receivedAt: start.addingTimeInterval(1)
        )
        _ = await engine.ingestLocation(
            location(
                latitude: -37.80360,
                longitude: 144.96310,
                at: start.addingTimeInterval(2)
            ),
            receivedAt: start.addingTimeInterval(2)
        )
        _ = await engine.ingestLocation(
            location(
                latitude: -37.80359,
                longitude: 144.96310,
                at: start.addingTimeInterval(3)
            ),
            receivedAt: start.addingTimeInterval(3)
        )
        _ = await engine.ingestLocation(
            location(
                latitude: -37.80355,
                longitude: 144.96310,
                horizontalAccuracy: 80,
                at: start.addingTimeInterval(4)
            ),
            receivedAt: start.addingTimeInterval(4)
        )
        _ = await engine.ingestLocation(
            location(
                latitude: -37.80350,
                longitude: 144.96310,
                at: start.addingTimeInterval(8)
            ),
            receivedAt: start.addingTimeInterval(8)
        )

        let record = try await engine.finalize(at: start.addingTimeInterval(9))
        #expect(record.trackPoints.map(\.timestamp) == record.trackPoints.map(\.timestamp).sorted())
        #expect(record.acceptedLocationCount == 3)
        #expect(record.rejectedLocationCount == 2)
        #expect(record.trackPoints[2].isAccepted)
        #expect(record.trackPoints[2].startsNewSegment)
        #expect(
            record.trackPoints[3].rejectionReason
                == LocationRejectionReason.accuracyExceedsLimit.rawValue
        )
    }

    @Test
    func cityAccuracyIsRetainedAsADegradedRoute() async {
        let engine = WalkMetricsEngine()
        _ = await engine.start(
            id: UUID(),
            at: start,
            timeZoneIdentifier: "Australia/Melbourne"
        )
        _ = await engine.ingestLocation(
            location(
                latitude: -37.81360,
                longitude: 144.96310,
                horizontalAccuracy: 35,
                speed: 1.2,
                course: 0,
                at: start.addingTimeInterval(1)
            ),
            receivedAt: start.addingTimeInterval(1)
        )
        let snapshot = await engine.ingestLocation(
            location(
                latitude: -37.81351,
                longitude: 144.96310,
                horizontalAccuracy: 35,
                speed: 1.2,
                course: 0,
                at: start.addingTimeInterval(6)
            ),
            receivedAt: start.addingTimeInterval(6)
        )

        #expect(snapshot.acceptedLocationCount == 2)
        #expect(snapshot.rejectedLocationCount == 0)
        #expect(snapshot.routeQuality == .degraded)
        #expect(snapshot.routeCoordinates.count == 2)
        #expect((snapshot.distance.value ?? 0) > 9)
    }

    @Test
    func degradedCityRouteUsesAvailablePedometerDistance() async {
        let engine = WalkMetricsEngine()
        _ = await engine.start(
            id: UUID(),
            at: start,
            timeZoneIdentifier: "Australia/Melbourne"
        )
        _ = await engine.ingestPedometer(
            pedometer(steps: 20, distance: 15, at: start.addingTimeInterval(1)),
            receivedAt: start.addingTimeInterval(1)
        )
        _ = await engine.ingestLocation(
            location(
                latitude: -37.81360,
                longitude: 144.96310,
                horizontalAccuracy: 35,
                speed: 1.2,
                course: 0,
                at: start.addingTimeInterval(1)
            ),
            receivedAt: start.addingTimeInterval(1)
        )
        let snapshot = await engine.ingestLocation(
            location(
                latitude: -37.81351,
                longitude: 144.96310,
                horizontalAccuracy: 35,
                speed: 1.2,
                course: 0,
                at: start.addingTimeInterval(6)
            ),
            receivedAt: start.addingTimeInterval(6)
        )

        #expect(snapshot.routeQuality == .degraded)
        #expect(snapshot.distance.value == 15)
        #expect(snapshot.distanceSource == .pedometer)
    }

    @Test
    func delayedBackgroundLocationsWithinWalkRemainEligible() async {
        let engine = WalkMetricsEngine()
        _ = await engine.start(
            id: UUID(),
            at: start,
            timeZoneIdentifier: "Australia/Melbourne"
        )
        let deliveryDate = start.addingTimeInterval(90)
        _ = await engine.ingestLocation(
            location(
                latitude: -37.81360,
                longitude: 144.96310,
                speed: 1.2,
                course: 0,
                at: start.addingTimeInterval(61)
            ),
            receivedAt: deliveryDate
        )
        let snapshot = await engine.ingestLocation(
            location(
                latitude: -37.81351,
                longitude: 144.96310,
                speed: 1.2,
                course: 0,
                at: start.addingTimeInterval(66)
            ),
            receivedAt: deliveryDate
        )

        #expect(snapshot.acceptedLocationCount == 2)
        #expect(snapshot.rejectedLocationCount == 0)
        #expect(snapshot.routeCoordinates.count == 2)
        #expect(snapshot.speed.availability == .stale)
    }

    @Test
    func delayedLocationCapturedDuringPauseRemainsRejectedAfterResume() async throws {
        let engine = WalkMetricsEngine()
        _ = await engine.start(
            id: UUID(),
            at: start,
            timeZoneIdentifier: "Australia/Melbourne"
        )
        _ = await engine.pause(at: start.addingTimeInterval(2))
        _ = await engine.resume(at: start.addingTimeInterval(10))
        let snapshot = await engine.ingestLocation(
            location(
                latitude: -37.81360,
                longitude: 144.96310,
                speed: 1.2,
                course: 0,
                at: start.addingTimeInterval(5)
            ),
            receivedAt: start.addingTimeInterval(11)
        )

        #expect(snapshot.acceptedLocationCount == 0)
        #expect(snapshot.rejectedLocationCount == 1)
        #expect(snapshot.routeCoordinates.isEmpty)
        let record = try await engine.finalize(at: start.addingTimeInterval(12))
        #expect(
            record.trackPoints.last?.rejectionReason
                == LocationRejectionReason.outsideWalkInterval.rawValue
        )
    }

    @Test
    func isolatedRejectedFixKeepsTheLastGoodRouteAnchor() async {
        let engine = WalkMetricsEngine()
        _ = await engine.start(
            id: UUID(),
            at: start,
            timeZoneIdentifier: "Australia/Melbourne"
        )
        _ = await engine.ingestLocation(
            location(
                latitude: -37.81360,
                longitude: 144.96310,
                speed: 1.2,
                course: 0,
                at: start.addingTimeInterval(1)
            ),
            receivedAt: start.addingTimeInterval(1)
        )
        _ = await engine.ingestLocation(
            location(
                latitude: -37.81356,
                longitude: 144.96310,
                horizontalAccuracy: 80,
                speed: 1.2,
                course: 0,
                at: start.addingTimeInterval(3)
            ),
            receivedAt: start.addingTimeInterval(3)
        )
        let snapshot = await engine.ingestLocation(
            location(
                latitude: -37.81351,
                longitude: 144.96310,
                speed: 1.2,
                course: 0,
                at: start.addingTimeInterval(6)
            ),
            receivedAt: start.addingTimeInterval(6)
        )

        #expect(snapshot.acceptedLocationCount == 2)
        #expect(snapshot.rejectedLocationCount == 1)
        #expect(snapshot.routeSegments.count == 1)
        #expect(snapshot.routeSegments.first?.count == 2)
        #expect((snapshot.distance.value ?? 0) > 9)
    }

    @Test
    func longLocationGapStartsANewSegmentWithoutInventingDistance() async {
        let engine = WalkMetricsEngine()
        _ = await engine.start(
            id: UUID(),
            at: start,
            timeZoneIdentifier: "Australia/Melbourne"
        )
        _ = await engine.ingestLocation(
            location(
                latitude: -37.81360,
                longitude: 144.96310,
                speed: 1.2,
                course: 0,
                at: start.addingTimeInterval(1)
            ),
            receivedAt: start.addingTimeInterval(1)
        )
        let snapshot = await engine.ingestLocation(
            location(
                latitude: -37.81270,
                longitude: 144.96310,
                speed: 1.2,
                course: 0,
                at: start.addingTimeInterval(61)
            ),
            receivedAt: start.addingTimeInterval(61)
        )

        #expect(snapshot.acceptedLocationCount == 2)
        #expect(snapshot.rejectedLocationCount == 0)
        #expect(snapshot.routeSegments.count == 2)
        #expect(snapshot.routeSegments.allSatisfy { $0.count == 1 })
        #expect(snapshot.routeQuality == .degraded)
        #expect(snapshot.distance.value == nil)
    }

    @Test
    func coreLocationBatchPreservesEveryFixInOrder() {
        let first = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: -37.81360, longitude: 144.96310),
            altitude: 30,
            horizontalAccuracy: 8,
            verticalAccuracy: 5,
            course: 0,
            speed: 1.2,
            timestamp: start.addingTimeInterval(1)
        )
        let second = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: -37.81351, longitude: 144.96310),
            altitude: 30,
            horizontalAccuracy: 9,
            verticalAccuracy: 5,
            course: 0,
            speed: 1.2,
            timestamp: start.addingTimeInterval(2)
        )

        let samples = LocationSampleBatch.samples(
            from: [first, second],
            accuracyAuthorization: .full
        )

        #expect(samples.count == 2)
        #expect(samples.map(\.timestamp) == [first.timestamp, second.timestamp])
        #expect(samples.map(\.coordinate) == [
            WalkCoordinate(latitude: -37.81360, longitude: 144.96310),
            WalkCoordinate(latitude: -37.81351, longitude: 144.96310),
        ])
    }

    @Test
    func coreLocationUnknownIsTreatedAsATransientSignalGap() {
        let error = NSError(
            domain: kCLErrorDomain,
            code: CLError.Code.locationUnknown.rawValue
        )

        #expect(LocationFailurePolicy.isTransient(error))
        #expect(!LocationFailurePolicy.isTransient(NSError(domain: "test", code: 1)))
    }

    @Test
    func pauseStartsANewLiveRouteSegmentWithoutBridgingTheGap() async {
        let engine = WalkMetricsEngine()
        _ = await engine.start(
            id: UUID(),
            at: start,
            timeZoneIdentifier: "Australia/Melbourne"
        )
        _ = await engine.ingestLocation(
            location(
                latitude: -37.8136,
                longitude: 144.9631,
                speed: 1,
                course: 0,
                at: start.addingTimeInterval(1)
            ),
            receivedAt: start.addingTimeInterval(1)
        )
        _ = await engine.pause(at: start.addingTimeInterval(2))
        _ = await engine.resume(at: start.addingTimeInterval(3))
        let snapshot = await engine.ingestLocation(
            location(
                latitude: -37.8036,
                longitude: 144.9631,
                speed: 1,
                course: 0,
                at: start.addingTimeInterval(4)
            ),
            receivedAt: start.addingTimeInterval(4)
        )

        #expect(snapshot.routeSegments.count == 2)
        #expect(snapshot.routeSegments.allSatisfy { $0.count == 1 })
        #expect(snapshot.distance.value == nil)
    }

    @Test
    func unavailableSensorsExposeReasonsInsteadOfAcquiringForever() async {
        let engine = WalkMetricsEngine()
        _ = await engine.start(
            id: UUID(),
            at: start,
            timeZoneIdentifier: "Australia/Melbourne"
        )
        _ = await engine.markMotionUnavailable(
            .pedometer,
            reason: "Step counting is unavailable.",
            at: start
        )
        _ = await engine.markMotionUnavailable(
            .relativeAltitude,
            reason: "Relative altitude is unavailable.",
            at: start
        )
        let snapshot = await engine.updateLocationAuthorization(
            .denied,
            accuracy: .unknown,
            at: start
        )

        #expect(
            snapshot.steps.availability
                == .unavailable("Step counting is unavailable.")
        )
        #expect(
            snapshot.elevationGain.availability
                == .unavailable("Relative altitude is unavailable.")
        )
        #expect(
            snapshot.direction.availability
                == .unavailable("Location access is unavailable.")
        )
    }

    private func pedometer(
        steps: Int,
        distance: Double,
        at date: Date
    ) -> PedometerSample {
        PedometerSample(
            startDate: start,
            endDate: date,
            cumulativeSteps: steps,
            cumulativeDistance: distance,
            currentPace: nil,
            currentCadence: nil
        )
    }

    private func location(
        latitude: Double,
        longitude: Double,
        horizontalAccuracy: Double = 5,
        speed: Double = 1.2,
        speedAccuracy: Double = 0.5,
        course: Double = 0,
        accuracy: LocationAccuracyState = .full,
        at date: Date
    ) -> WalkLocationSample {
        WalkLocationSample(
            coordinate: WalkCoordinate(latitude: latitude, longitude: longitude),
            timestamp: date,
            altitude: 30,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: 5,
            speed: speed,
            speedAccuracy: speedAccuracy,
            course: course,
            courseAccuracy: 5,
            accuracyAuthorization: accuracy
        )
    }
}
