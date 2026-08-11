import Foundation

enum HealthAccessState: String, CaseIterable, Codable, Equatable, Sendable {
    case unavailable
    case notRequested
    case requested
}

enum HealthWorkoutExportStatus: String, CaseIterable, Codable, Equatable, Sendable {
    case disabled
    case pending
    case completed
    case failed
}

struct HealthWalkingWorkout: Identifiable, Equatable, Sendable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let movingDuration: TimeInterval
    let distanceMeters: Double?
    let sourceName: String
    let sourceBundleIdentifier: String
    let timeZoneIdentifier: String?

    var elapsedDuration: TimeInterval {
        max(0, endDate.timeIntervalSince(startDate))
    }

    var pausedDuration: TimeInterval {
        max(0, elapsedDuration - movingDuration)
    }
}

struct HealthWalkingWorkoutImport: Equatable, Sendable {
    let workout: HealthWalkingWorkout
    let routePoints: [NewTrackPoint]
}

struct HealthQuantityObservation: Equatable, Sendable {
    let sourceIdentifier: String
    let sourceName: String
    let startDate: Date
    let endDate: Date
    let value: Double
}

struct HealthMetricResult: Equatable, Sendable {
    let value: Double?
    let sampleCount: Int
    let coveredDuration: TimeInterval?
    let quality: MetricQuality
    let sourceIdentifier: String?
    let sourceName: String?

    static let unavailable = HealthMetricResult(
        value: nil,
        sampleCount: 0,
        coveredDuration: nil,
        quality: .unavailable,
        sourceIdentifier: nil,
        sourceName: nil
    )
}

struct WalkHealthEnrichment: Equatable, Sendable {
    let heartRate: HealthMetricResult
    let walkingAsymmetry: HealthMetricResult
    let steps: HealthMetricResult
    let distance: HealthMetricResult
    let enrichedAt: Date

    static func unavailable(at date: Date) -> WalkHealthEnrichment {
        WalkHealthEnrichment(
            heartRate: .unavailable,
            walkingAsymmetry: .unavailable,
            steps: .unavailable,
            distance: .unavailable,
            enrichedAt: date
        )
    }
}

struct HealthWalkInput: Equatable, Sendable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let movingDuration: TimeInterval
    let displayDistance: Double?
    let routeDistance: Double?
    let pedometerDistance: Double?
    let motionSteps: Int?
    let routeQuality: RouteQuality
    let trackPoints: [NewTrackPoint]
}

enum HealthMetricsProcessor {
    static func enrichment(
        heartRate: [HealthQuantityObservation],
        walkingAsymmetry: [HealthQuantityObservation],
        steps: [HealthQuantityObservation],
        distance: [HealthQuantityObservation],
        input: HealthWalkInput,
        enrichedAt: Date
    ) -> WalkHealthEnrichment {
        WalkHealthEnrichment(
            heartRate: discreteMetric(
                observations: heartRate,
                interval: input.startDate...input.endDate,
                validRange: 20...300,
                goodCoverageRatio: 0.5
            ),
            walkingAsymmetry: discreteMetric(
                observations: walkingAsymmetry,
                interval: input.startDate...input.endDate,
                validRange: 0...1,
                goodCoverageRatio: nil
            ),
            steps: cumulativeMetric(
                observations: steps,
                interval: input.startDate...input.endDate,
                referenceValue: input.motionSteps.map(Double.init)
            ),
            distance: cumulativeMetric(
                observations: distance,
                interval: input.startDate...input.endDate,
                referenceValue: input.pedometerDistance ?? input.routeDistance
            ),
            enrichedAt: enrichedAt
        )
    }

    private static func cumulativeMetric(
        observations: [HealthQuantityObservation],
        interval: ClosedRange<Date>,
        referenceValue: Double?
    ) -> HealthMetricResult {
        let grouped = validObservations(
            observations,
            interval: interval,
            validRange: 0...Double.greatestFiniteMagnitude,
            acceptsZero: false
        ).groupedBySource

        let candidates = grouped.map { source, samples in
            SourceCandidate(
                sourceIdentifier: source,
                sourceName: samples.first?.sourceName ?? source,
                value: samples.reduce(0) { $0 + $1.value },
                sampleCount: samples.count,
                coveredDuration: coveredDuration(samples, within: interval)
            )
        }
        guard let selected = selectCandidate(candidates, referenceValue: referenceValue) else {
            return .unavailable
        }
        return HealthMetricResult(
            value: selected.value,
            sampleCount: selected.sampleCount,
            coveredDuration: selected.coveredDuration,
            quality: .good,
            sourceIdentifier: selected.sourceIdentifier,
            sourceName: selected.sourceName
        )
    }

    private static func discreteMetric(
        observations: [HealthQuantityObservation],
        interval: ClosedRange<Date>,
        validRange: ClosedRange<Double>,
        goodCoverageRatio: Double?
    ) -> HealthMetricResult {
        let grouped = validObservations(
            observations,
            interval: interval,
            validRange: validRange,
            acceptsZero: true
        ).groupedBySource

        let candidates = grouped.map { source, samples in
            SourceCandidate(
                sourceIdentifier: source,
                sourceName: samples.first?.sourceName ?? source,
                value: samples.reduce(0) { $0 + $1.value } / Double(samples.count),
                sampleCount: samples.count,
                coveredDuration: coveredDuration(samples, within: interval)
            )
        }
        guard let selected = selectCandidate(candidates, referenceValue: nil) else {
            return .unavailable
        }

        let quality: MetricQuality
        if let goodCoverageRatio {
            let intervalDuration = max(1, interval.upperBound.timeIntervalSince(interval.lowerBound))
            quality = selected.coveredDuration / intervalDuration >= goodCoverageRatio
                ? .good : .degraded
        } else {
            quality = selected.sampleCount >= 3 ? .good : .degraded
        }
        return HealthMetricResult(
            value: selected.value,
            sampleCount: selected.sampleCount,
            coveredDuration: selected.coveredDuration,
            quality: quality,
            sourceIdentifier: selected.sourceIdentifier,
            sourceName: selected.sourceName
        )
    }

    private static func validObservations(
        _ observations: [HealthQuantityObservation],
        interval: ClosedRange<Date>,
        validRange: ClosedRange<Double>,
        acceptsZero: Bool
    ) -> [HealthQuantityObservation] {
        observations.filter { observation in
            observation.value.isFinite
                && validRange.contains(observation.value)
                && (acceptsZero || observation.value > 0)
                && observation.endDate >= interval.lowerBound
                && observation.startDate <= interval.upperBound
                && observation.endDate >= observation.startDate
                && !observation.sourceIdentifier.isEmpty
        }
    }

    private static func selectCandidate(
        _ candidates: [SourceCandidate],
        referenceValue: Double?
    ) -> SourceCandidate? {
        candidates.sorted { lhs, rhs in
            if let referenceValue, referenceValue > 0 {
                let lhsDifference = abs(lhs.value - referenceValue) / referenceValue
                let rhsDifference = abs(rhs.value - referenceValue) / referenceValue
                if lhsDifference != rhsDifference {
                    return lhsDifference < rhsDifference
                }
            }
            if lhs.coveredDuration != rhs.coveredDuration {
                return lhs.coveredDuration > rhs.coveredDuration
            }
            if lhs.sampleCount != rhs.sampleCount {
                return lhs.sampleCount > rhs.sampleCount
            }
            return lhs.sourceIdentifier < rhs.sourceIdentifier
        }.first
    }

    private static func coveredDuration(
        _ observations: [HealthQuantityObservation],
        within interval: ClosedRange<Date>
    ) -> TimeInterval {
        let clipped = observations
            .map { observation -> ClosedRange<Date> in
                let lowerBound = max(observation.startDate, interval.lowerBound)
                let upperBound = min(observation.endDate, interval.upperBound)
                return lowerBound...upperBound
            }
            .sorted(by: { $0.lowerBound < $1.lowerBound })
        guard var current = clipped.first else { return 0 }
        var duration: TimeInterval = 0

        for next in clipped.dropFirst() {
            if next.lowerBound <= current.upperBound {
                current = current.lowerBound...max(current.upperBound, next.upperBound)
            } else {
                duration += current.upperBound.timeIntervalSince(current.lowerBound)
                current = next
            }
        }
        return duration + current.upperBound.timeIntervalSince(current.lowerBound)
    }

    private struct SourceCandidate {
        let sourceIdentifier: String
        let sourceName: String
        let value: Double
        let sampleCount: Int
        let coveredDuration: TimeInterval
    }
}

private extension Array where Element == HealthQuantityObservation {
    var groupedBySource: [String: [HealthQuantityObservation]] {
        Dictionary(grouping: self, by: \.sourceIdentifier)
    }
}
