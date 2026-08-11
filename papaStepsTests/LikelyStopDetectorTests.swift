import Foundation
import Testing
@testable import papaSteps

struct LikelyStopDetectorTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let coordinate = WalkCoordinate(latitude: -37.8136, longitude: 144.9631)

    @Test
    func corroboratedStationaryWindowProducesOneCandidate() {
        var detector = LikelyStopDetector(configuration: testConfiguration())
        detector.start()

        #expect(detector.evaluate(sample(at: 0)) == .none)
        #expect(detector.evaluate(sample(at: 2)) == .none)
        #expect(detector.evaluate(sample(at: 3)) == .finishCandidate)
        #expect(detector.evaluate(sample(at: 4)) == .none)
    }

    @Test
    func shortStopAndLowConfidenceClassifierDoNotPrompt() {
        var detector = LikelyStopDetector(configuration: testConfiguration())
        detector.start()

        #expect(detector.evaluate(sample(at: 0)) == .none)
        #expect(detector.evaluate(sample(at: 2.9)) == .none)

        detector.stop()
        detector.start()
        let lowConfidence = sample(
            at: 0,
            activity: WalkMotionActivitySample(
                timestamp: start,
                activity: .stationary,
                confidence: .low
            )
        )
        #expect(detector.evaluate(lowConfidence) == .none)
        #expect(
            detector.evaluate(
                sample(
                    at: 4,
                    activity: WalkMotionActivitySample(
                        timestamp: start.addingTimeInterval(4),
                        activity: .stationary,
                        confidence: .low
                    )
                )
            ) == .none
        )
    }

    @Test
    func renewedStepsCancelCandidateAndKeepWalkingSuppressesRepeat() {
        var detector = LikelyStopDetector(configuration: testConfiguration())
        detector.start()
        _ = detector.evaluate(sample(at: 0))
        #expect(detector.evaluate(sample(at: 3)) == .finishCandidate)

        #expect(detector.evaluate(sample(at: 3.1, steps: 105)) == .movementResumed)

        _ = detector.evaluate(sample(at: 4, steps: 105))
        #expect(detector.evaluate(sample(at: 7, steps: 105)) == .finishCandidate)
        detector.suppressCandidate(at: start.addingTimeInterval(7))
        #expect(detector.evaluate(sample(at: 7.1, steps: 105)) == .none)
        #expect(detector.evaluate(sample(at: 9, steps: 105)) == .none)
    }

    private func testConfiguration() -> TrackingConfiguration {
        var configuration = TrackingConfiguration.live
        configuration.minimumFinishPromptWalkDuration = 0
        configuration.likelyStopWindow = 3
        configuration.finishPromptSuppressionInterval = 5
        return configuration
    }

    private func sample(
        at offset: TimeInterval,
        steps: Int = 100,
        activity: WalkMotionActivitySample? = nil
    ) -> LikelyStopSample {
        let date = start.addingTimeInterval(offset)
        return LikelyStopSample(
            date: date,
            elapsedDuration: 600 + offset,
            steps: steps,
            speed: LiveMetric(value: 0.1, availability: .available),
            coordinate: coordinate,
            motionActivity: activity ?? WalkMotionActivitySample(
                timestamp: date,
                activity: .stationary,
                confidence: .high
            )
        )
    }
}
