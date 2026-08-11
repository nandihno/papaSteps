import Foundation
import Testing
@testable import papaSteps

struct HealthWorkoutPayloadTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func distanceSampleBeginsAfterWorkoutStart() throws {
        let input = makeInput()

        let payload = try HealthWorkoutPayload(input: input)
        let distanceStartDate = try #require(payload.distanceStartDate)

        #expect(payload.distanceMeters == 120)
        #expect(distanceStartDate > input.startDate)
        #expect(distanceStartDate < input.endDate)
    }

    @Test
    func routePayloadSortsAndRejectsArgumentsOutsideHealthKitBounds() throws {
        let validLater = point(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, offset: 20)
        let validEarlier = point(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, offset: 10)
        let duplicateTimestamp = point(offset: 10, latitude: -37.82)
        let beforeWorkout = point(offset: -1)
        let invalidCoordinate = point(offset: 30, latitude: .nan)
        let rejected = point(offset: 40, isAccepted: false)
        let input = makeInput(
            trackPoints: [
                validLater,
                duplicateTimestamp,
                beforeWorkout,
                invalidCoordinate,
                rejected,
                validEarlier
            ]
        )

        let payload = try HealthWorkoutPayload(input: input)

        #expect(payload.routePoints.map(\.id) == [validEarlier.id, validLater.id])
    }

    @Test
    func nonFiniteDistanceIsNotSentToHealthKit() throws {
        let payload = try HealthWorkoutPayload(
            input: makeInput(displayDistance: .infinity)
        )

        #expect(payload.distanceMeters == nil)
        #expect(payload.distanceStartDate == nil)
    }

    @Test
    func zeroLengthWorkoutIsRejectedBeforeCallingHealthKit() {
        let input = makeInput(endDate: start)

        #expect(throws: HealthDataError.invalidWorkoutInterval) {
            try HealthWorkoutPayload(input: input)
        }
    }

    private func makeInput(
        endDate: Date? = nil,
        displayDistance: Double? = 120,
        trackPoints: [NewTrackPoint] = []
    ) -> HealthWalkInput {
        HealthWalkInput(
            id: UUID(),
            startDate: start,
            endDate: endDate ?? start.addingTimeInterval(60),
            movingDuration: 50,
            displayDistance: displayDistance,
            routeDistance: displayDistance,
            pedometerDistance: displayDistance,
            motionSteps: 81,
            routeQuality: .good,
            trackPoints: trackPoints
        )
    }

    private func point(
        id: UUID = UUID(),
        offset: TimeInterval,
        latitude: Double = -37.81,
        isAccepted: Bool = true
    ) -> NewTrackPoint {
        NewTrackPoint(
            id: id,
            timestamp: start.addingTimeInterval(offset),
            latitude: latitude,
            longitude: 144.96,
            altitude: 20,
            horizontalAccuracy: 5,
            verticalAccuracy: 8,
            speed: 1.4,
            speedAccuracy: 0.2,
            course: 90,
            courseAccuracy: 5,
            isAccepted: isAccepted,
            rejectionReason: isAccepted ? nil : "test",
            startsNewSegment: false
        )
    }
}
