import Foundation
import Testing
@testable import papaSteps

/// End-to-end check that a finished walk records rebuilt moving time.
///
/// Reproduces the pocketed-phone case: the walk ticks for nine minutes while
/// movement evidence almost never lands inside the freshness window, so the
/// live figure collapses; pedometer history then shows steady walking.
struct MovingTimeEngineTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func pocketedWalkRecordsRebuiltMovingTimeInsteadOfTheCollapsedLiveFigure() async throws {
        let engine = WalkMetricsEngine(configuration: .live)
        let end = start.addingTimeInterval(9 * 60)

        _ = await engine.start(
            id: UUID(),
            at: start,
            timeZoneIdentifier: "Australia/Melbourne"
        )

        // Nine minutes of ticks with no fresh movement evidence: this is what
        // the app saw with the phone in a pocket.
        for second in stride(from: 1, through: 9 * 60, by: 1) {
            _ = await engine.tick(at: start.addingTimeInterval(Double(second)))
        }

        // The defect itself: nine minutes of walking, almost no moving time.
        let liveSnapshot = await engine.currentSnapshot(at: end)
        #expect(liveSnapshot.movingDuration < 60)

        let intervals = (0..<9).map { minute in
            PedometerInterval(
                interval: DateInterval(
                    start: start.addingTimeInterval(Double(minute) * 60),
                    end: start.addingTimeInterval(Double(minute + 1) * 60)
                ),
                steps: 110
            )
        }
        await engine.applyMovingTimeReconstruction(intervals, at: end)

        let record = try await engine.finalize(at: end)

        #expect(record.movingDuration == 9 * 60)
        #expect(record.elapsedDuration >= record.movingDuration)
    }

    @Test
    func rebuiltMovingTimeExcludesPausedWindows() async throws {
        let engine = WalkMetricsEngine(configuration: .live)
        let end = start.addingTimeInterval(10 * 60)

        _ = await engine.start(
            id: UUID(),
            at: start,
            timeZoneIdentifier: "Australia/Melbourne"
        )
        for second in stride(from: 1, through: 10 * 60, by: 1) {
            _ = await engine.tick(at: start.addingTimeInterval(Double(second)))
        }

        // Paused for minutes 4 and 5 of ten.
        _ = await engine.pause(at: start.addingTimeInterval(4 * 60))
        _ = await engine.resume(at: start.addingTimeInterval(6 * 60))

        let intervals = (0..<10).map { minute in
            PedometerInterval(
                interval: DateInterval(
                    start: start.addingTimeInterval(Double(minute) * 60),
                    end: start.addingTimeInterval(Double(minute + 1) * 60)
                ),
                steps: 110
            )
        }
        await engine.applyMovingTimeReconstruction(intervals, at: end)

        let record = try await engine.finalize(at: end)

        // Eight unpaused minutes of walking, and never more than the walk ran.
        #expect(record.movingDuration == 8 * 60)
        #expect(record.movingDuration <= record.elapsedDuration - record.pausedDuration)
    }

    @Test
    func withoutStepHistoryTheLiveFigureIsKept() async throws {
        var configuration = TrackingConfiguration.live
        configuration.movementEvidenceInterval = 600
        let engine = WalkMetricsEngine(configuration: configuration)
        let end = start.addingTimeInterval(60)

        _ = await engine.start(
            id: UUID(),
            at: start,
            timeZoneIdentifier: "Australia/Melbourne"
        )
        _ = await engine.ingestPedometer(
            PedometerSample(
                startDate: start,
                endDate: start,
                cumulativeSteps: 0,
                cumulativeDistance: 0,
                currentPace: nil,
                currentCadence: nil
            ),
            receivedAt: start
        )
        _ = await engine.ingestPedometer(
            PedometerSample(
                startDate: start,
                endDate: start.addingTimeInterval(1),
                cumulativeSteps: 20,
                cumulativeDistance: 15,
                currentPace: nil,
                currentCadence: nil
            ),
            receivedAt: start.addingTimeInterval(1)
        )
        for second in stride(from: 2, through: 60, by: 1) {
            _ = await engine.tick(at: start.addingTimeInterval(Double(second)))
        }

        // No reconstruction applied — the pedometer was unavailable.
        let record = try await engine.finalize(at: end)

        #expect(record.movingDuration > 0)
        #expect(record.movingDuration <= record.elapsedDuration)
    }

    @Test
    func averageSpeedUsesTheRecordedMovingTime() async throws {
        let engine = WalkMetricsEngine(configuration: .live)
        let end = start.addingTimeInterval(9 * 60)

        _ = await engine.start(
            id: UUID(),
            at: start,
            timeZoneIdentifier: "Australia/Melbourne"
        )
        _ = await engine.ingestPedometer(
            PedometerSample(
                startDate: start,
                endDate: start,
                cumulativeSteps: 0,
                cumulativeDistance: 0,
                currentPace: nil,
                currentCadence: nil
            ),
            receivedAt: start
        )
        _ = await engine.ingestPedometer(
            PedometerSample(
                startDate: start,
                endDate: end,
                cumulativeSteps: 990,
                cumulativeDistance: 720,
                currentPace: nil,
                currentCadence: nil
            ),
            receivedAt: end
        )
        for second in stride(from: 1, through: 9 * 60, by: 1) {
            _ = await engine.tick(at: start.addingTimeInterval(Double(second)))
        }

        let intervals = (0..<9).map { minute in
            PedometerInterval(
                interval: DateInterval(
                    start: start.addingTimeInterval(Double(minute) * 60),
                    end: start.addingTimeInterval(Double(minute + 1) * 60)
                ),
                steps: 110
            )
        }
        await engine.applyMovingTimeReconstruction(intervals, at: end)

        let record = try await engine.finalize(at: end)
        let distance = try #require(record.displayDistance)
        let averageSpeed = try #require(record.averageSpeed)

        // Distance over the rebuilt moving time — not over the 35-second one,
        // which would have reported a sprint.
        #expect(abs(averageSpeed - distance / record.movingDuration) < 0.001)
        #expect(averageSpeed < 3)
    }
}
