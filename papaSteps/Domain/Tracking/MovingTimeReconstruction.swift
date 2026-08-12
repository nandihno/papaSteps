import Foundation

/// Rebuilds moving time from pedometer step history.
///
/// **Why this exists.** The live figure accrues one second per tick while
/// movement evidence is fresh — a location fix or a step increase inside
/// `movementEvidenceInterval`. That works while the app is in the foreground
/// with a clear sky, and fails badly otherwise: `CMPedometer` callbacks are
/// irregular and stop while the process is suspended, and GPS speed from a
/// phone in a pocket routinely fails its accuracy gate. Evidence then arrives
/// far less often than the freshness window, so a nine-minute walk can record
/// well under a minute of moving time.
///
/// Steps are already reconciled after the fact against `queryPedometerData`
/// (§5.1). This applies the same discipline to moving time: ask the pedometer
/// how many steps fell inside each bucket of the walk, and convert that into
/// time spent walking.
///
/// **What it does not do.** It never invents movement. A bucket with no steps
/// contributes nothing, paused windows are removed before conversion, and the
/// total is clamped so it can never exceed the time the walk was actually
/// running and unpaused.
enum MovingTimeReconstruction {
    /// Time spent walking across `intervals`, excluding `pauseWindows`.
    ///
    /// Each bucket contributes `steps / cadence`, capped at the bucket's own
    /// unpaused duration — so a bucket full of steady walking counts in full, a
    /// bucket with a handful of steps counts for a few seconds, and an empty
    /// bucket counts for nothing.
    static func movingDuration(
        from intervals: [PedometerInterval],
        pauseWindows: [DateInterval],
        cadence: Double
    ) -> TimeInterval {
        guard cadence > 0 else { return 0 }

        return intervals.reduce(into: 0) { total, bucket in
            let duration = bucket.interval.duration
            guard duration > 0 else { return }

            let pausedDuration = pauseWindows.reduce(into: 0.0) { paused, window in
                paused += bucket.interval.intersection(with: window)?.duration ?? 0
            }
            let unpausedDuration = max(0, duration - pausedDuration)
            guard unpausedDuration > 0 else { return }

            // Steps cannot be split within a bucket, so attribute them in
            // proportion to the part of the bucket that was not paused.
            let unpausedFraction = unpausedDuration / duration
            let attributedSteps = Double(bucket.steps) * unpausedFraction

            total += min(unpausedDuration, attributedSteps / cadence)
        }
    }

    /// The moving time to record for a finished walk.
    ///
    /// Takes whichever of the live and rebuilt figures is larger — each is a
    /// lower bound produced by different evidence, and the live one is the only
    /// one that sees a walk with no step data at all — then clamps to the time
    /// the walk was running and unpaused.
    static func resolve(
        live: TimeInterval,
        reconstructed: TimeInterval?,
        elapsedDuration: TimeInterval,
        pausedDuration: TimeInterval
    ) -> TimeInterval {
        let ceiling = max(0, elapsedDuration - pausedDuration)
        guard let reconstructed else { return min(live, ceiling) }
        return min(max(live, reconstructed), ceiling)
    }

    /// Splits a walk into query buckets, widening them rather than exceeding
    /// `maximumBuckets` so a long walk does not issue hundreds of queries.
    static func buckets(
        from startDate: Date,
        to endDate: Date,
        preferredDuration: TimeInterval,
        maximumBuckets: Int
    ) -> [DateInterval] {
        let total = endDate.timeIntervalSince(startDate)
        guard total > 0, preferredDuration > 0, maximumBuckets > 0 else { return [] }

        let bucketDuration = max(preferredDuration, total / Double(maximumBuckets))
        var buckets: [DateInterval] = []
        var cursor = startDate

        while cursor < endDate {
            let next = min(cursor.addingTimeInterval(bucketDuration), endDate)
            if next > cursor {
                buckets.append(DateInterval(start: cursor, end: next))
            }
            cursor = next
        }
        return buckets
    }
}
