import Foundation
import Testing
@testable import papaSteps

/// Covers the rebuild of moving time from pedometer history.
///
/// The scenario that motivated it: a nine-minute walk with the phone in a back
/// pocket recorded 35 seconds of moving time, because live movement evidence
/// arrives far less often than the four-second window that consumes it.
struct MovingTimeReconstructionTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)
    private let cadence = TrackingConfiguration.live.assumedWalkingCadence

    private func bucket(_ minute: Int, steps: Int) -> PedometerInterval {
        PedometerInterval(
            interval: DateInterval(
                start: start.addingTimeInterval(Double(minute) * 60),
                end: start.addingTimeInterval(Double(minute + 1) * 60)
            ),
            steps: steps
        )
    }

    @Test func steadyWalkingCreditsAlmostAllOfEachBucket() {
        // 110 steps a minute is ordinary walking; a minute of it is a minute of
        // moving time, not four seconds.
        let intervals = (0..<9).map { bucket($0, steps: 110) }

        let moving = MovingTimeReconstruction.movingDuration(
            from: intervals,
            pauseWindows: [],
            cadence: cadence
        )

        #expect(moving == 9 * 60)
    }

    @Test func emptyBucketsContributeNothing() {
        let intervals = [bucket(0, steps: 0), bucket(1, steps: 0)]

        #expect(
            MovingTimeReconstruction.movingDuration(
                from: intervals,
                pauseWindows: [],
                cadence: cadence
            ) == 0
        )
    }

    @Test func sparseStepsCreditTimeInProportionNotTheWholeBucket() {
        // 35 steps in a minute is a stroll to the kitchen, not a minute of
        // walking. It must not credit the full bucket.
        let moving = MovingTimeReconstruction.movingDuration(
            from: [bucket(0, steps: 35)],
            pauseWindows: [],
            cadence: cadence
        )

        #expect(moving == 35 / cadence)
        #expect(moving < 60)
    }

    @Test func pausedWindowsAreExcluded() {
        // Walking through a bucket that was half paused credits at most the
        // unpaused half.
        let pause = DateInterval(
            start: start.addingTimeInterval(30),
            end: start.addingTimeInterval(60)
        )

        let moving = MovingTimeReconstruction.movingDuration(
            from: [bucket(0, steps: 110)],
            pauseWindows: [pause],
            cadence: cadence
        )

        #expect(moving == 30)
    }

    @Test func aFullyPausedBucketCreditsNothing() {
        let pause = DateInterval(
            start: start,
            end: start.addingTimeInterval(60)
        )

        #expect(
            MovingTimeReconstruction.movingDuration(
                from: [bucket(0, steps: 110)],
                pauseWindows: [pause],
                cadence: cadence
            ) == 0
        )
    }

    @Test func rebuiltValueWinsWhenTheLiveFigureUnderCounted() {
        // The reported defect, in numbers.
        let resolved = MovingTimeReconstruction.resolve(
            live: 35,
            reconstructed: 520,
            elapsedDuration: 540,
            pausedDuration: 0
        )

        #expect(resolved == 520)
    }

    @Test func liveValueStandsWhenItIsHigher() {
        // A foreground walk with good GPS can beat a cadence estimate; the
        // rebuild must not drag a good figure down.
        let resolved = MovingTimeReconstruction.resolve(
            live: 500,
            reconstructed: 420,
            elapsedDuration: 540,
            pausedDuration: 0
        )

        #expect(resolved == 500)
    }

    @Test func resolvedValueNeverExceedsRunningUnpausedTime() {
        let resolved = MovingTimeReconstruction.resolve(
            live: 0,
            reconstructed: 10_000,
            elapsedDuration: 540,
            pausedDuration: 120
        )

        #expect(resolved == 420)
    }

    @Test func missingStepHistoryLeavesTheLiveFigureAlone() {
        let resolved = MovingTimeReconstruction.resolve(
            live: 300,
            reconstructed: nil,
            elapsedDuration: 540,
            pausedDuration: 0
        )

        #expect(resolved == 300)
    }

    @Test func bucketsCoverTheWalkWithoutGapsOrOverlap() {
        let end = start.addingTimeInterval(9 * 60)
        let buckets = MovingTimeReconstruction.buckets(
            from: start,
            to: end,
            preferredDuration: 60,
            maximumBuckets: 180
        )

        #expect(buckets.count == 9)
        #expect(buckets.first?.start == start)
        #expect(buckets.last?.end == end)
        for (earlier, later) in zip(buckets, buckets.dropFirst()) {
            #expect(earlier.end == later.start)
        }
    }

    @Test func longWalksWidenBucketsRatherThanIssueMoreQueries() {
        // Six hours at one bucket a minute would be 360 pedometer queries.
        let end = start.addingTimeInterval(6 * 60 * 60)
        let buckets = MovingTimeReconstruction.buckets(
            from: start,
            to: end,
            preferredDuration: 60,
            maximumBuckets: 180
        )

        #expect(buckets.count <= 180)
        #expect(buckets.last?.end == end)
    }

    @Test func aWalkWithNoDurationProducesNoBuckets() {
        #expect(
            MovingTimeReconstruction.buckets(
                from: start,
                to: start,
                preferredDuration: 60,
                maximumBuckets: 180
            ).isEmpty
        )
    }
}
