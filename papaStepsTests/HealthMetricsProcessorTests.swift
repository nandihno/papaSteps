import Foundation
import Testing
@testable import papaSteps

struct HealthMetricsProcessorTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func emptyHealthResultsRemainUnavailableInsteadOfBecomingZero() {
        let result = HealthMetricsProcessor.enrichment(
            heartRate: [],
            walkingAsymmetry: [],
            steps: [],
            distance: [],
            input: input(),
            enrichedAt: start.addingTimeInterval(700)
        )

        #expect(result.heartRate.value == nil)
        #expect(result.walkingAsymmetry.value == nil)
        #expect(result.steps.value == nil)
        #expect(result.distance.value == nil)
        #expect(result.heartRate.quality == .unavailable)
    }

    @Test
    func overlappingPhoneAndWatchTotalsChooseOneSourceWithoutDoubleCounting() {
        let result = HealthMetricsProcessor.enrichment(
            heartRate: [],
            walkingAsymmetry: [],
            steps: [
                observation(source: "iphone", name: "Fernando’s iPhone", value: 1_045),
                observation(source: "watch", name: "Fernando’s Apple Watch", value: 1_190)
            ],
            distance: [
                observation(source: "iphone", name: "Fernando’s iPhone", value: 755),
                observation(source: "watch", name: "Fernando’s Apple Watch", value: 890)
            ],
            input: input(),
            enrichedAt: start.addingTimeInterval(700)
        )

        #expect(result.steps.value == 1_045)
        #expect(result.steps.sourceIdentifier == "iphone")
        #expect(result.steps.value != 2_235)
        #expect(result.distance.value == 755)
        #expect(result.distance.sourceIdentifier == "iphone")
        #expect(result.distance.value != 1_645)
    }

    @Test
    func malformedHealthValuesAreIgnoredAndDiscreteMetricsKeepCoverage() {
        let result = HealthMetricsProcessor.enrichment(
            heartRate: [
                observation(source: "watch", name: "Apple Watch", value: .nan),
                observation(source: "watch", name: "Apple Watch", value: 12),
                observation(source: "watch", name: "Apple Watch", value: 80),
                observation(source: "watch", name: "Apple Watch", value: 100, offset: 300)
            ],
            walkingAsymmetry: [
                observation(source: "iphone", name: "iPhone", value: 0.04),
                observation(source: "iphone", name: "iPhone", value: 1.4)
            ],
            steps: [observation(source: "iphone", name: "iPhone", value: -20)],
            distance: [],
            input: input(),
            enrichedAt: start.addingTimeInterval(700)
        )

        #expect(result.heartRate.value == 90)
        #expect(result.heartRate.sampleCount == 2)
        #expect(result.heartRate.sourceName == "Apple Watch")
        #expect(result.walkingAsymmetry.value == 0.04)
        #expect(result.walkingAsymmetry.sampleCount == 1)
        #expect(result.steps.value == nil)
    }

    private func input() -> HealthWalkInput {
        let sample = NewWalkRecord.sample(startDate: start)
        return HealthWalkInput(
            id: sample.id,
            startDate: sample.startDate,
            endDate: sample.endDate,
            movingDuration: sample.movingDuration,
            displayDistance: sample.displayDistance,
            routeDistance: sample.routeDistance,
            pedometerDistance: sample.pedometerDistance,
            motionSteps: sample.motionSteps,
            routeQuality: sample.routeQuality,
            trackPoints: sample.trackPoints
        )
    }

    private func observation(
        source: String,
        name: String,
        value: Double,
        offset: TimeInterval = 0
    ) -> HealthQuantityObservation {
        HealthQuantityObservation(
            sourceIdentifier: source,
            sourceName: name,
            startDate: start.addingTimeInterval(offset),
            endDate: start.addingTimeInterval(offset + 120),
            value: value
        )
    }
}
