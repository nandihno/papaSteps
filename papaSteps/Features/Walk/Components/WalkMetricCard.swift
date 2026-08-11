import SwiftUI

/// Grid tile used by History and Progress.
///
/// Presentation now lives in `MetricTile`; this remains as the call site those
/// tabs already use, and retires as each one migrates (U2, U3).
struct WalkMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    var isStale = false

    var body: some View {
        MetricTile(
            title: title,
            value: value,
            detail: detail,
            systemImage: systemImage,
            isStale: isStale
        )
    }
}

struct WalkMetricGrid<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(
            columns: dynamicTypeSize.isAccessibilitySize
                ? [GridItem(.flexible())]
                : [GridItem(.flexible()), GridItem(.flexible())],
            spacing: Spacing.gridGutter,
            content: { content }
        )
    }
}

enum WalkMetricFormatting {
    static func duration(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    static func distance(
        _ meters: Double?,
        configuration: WalkDisplayConfiguration = .metricSpeed
    ) -> String {
        guard let meters else { return "—" }
        let measurement = lengthMeasurement(meters, unit: configuration.distanceUnit.distanceUnit)
        return measurementText(
            measurement.value,
            unit: configuration.distanceUnit.distanceSymbol,
            fractionLength: 0...1
        )
    }

    static func speed(
        _ metersPerSecond: Double?,
        configuration: WalkDisplayConfiguration = .metricSpeed
    ) -> String {
        guard let metersPerSecond else { return "—" }
        switch configuration.speedDisplay {
        case .speed:
            let unit: UnitSpeed = configuration.distanceUnit == .metric
                ? .kilometersPerHour
                : .milesPerHour
            let measurement = Measurement(value: metersPerSecond, unit: UnitSpeed.metersPerSecond)
                .converted(to: unit)
            return measurementText(
                measurement.value,
                unit: configuration.distanceUnit.speedSymbol,
                fractionLength: 0...1
            )
        case .pace:
            guard metersPerSecond > 0, metersPerSecond.isFinite else { return "—" }
            let metersPerUnit = configuration.distanceUnit == .metric ? 1_000.0 : 1_609.344
            let totalSeconds = Int((metersPerUnit / metersPerSecond).rounded())
            return String(
                format: "%d:%02d min/%@",
                totalSeconds / 60,
                totalSeconds % 60,
                configuration.distanceUnit == .metric ? "km" : "mi"
            )
        }
    }

    static func altitude(
        _ meters: Double?,
        configuration: WalkDisplayConfiguration = .metricSpeed
    ) -> String {
        guard let meters else { return "—" }
        let measurement = lengthMeasurement(meters, unit: configuration.distanceUnit.altitudeUnit)
        return measurementText(
            measurement.value,
            unit: configuration.distanceUnit.altitudeSymbol,
            fractionLength: 0...0
        )
    }

    static func direction(_ degrees: Double?) -> String {
        guard let degrees else { return "—" }
        return "\(cardinalDirection(degrees)) · \(Int(degrees.rounded()))°"
    }

    static func cardinalDirection(_ degrees: Double) -> String {
        let labels = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let normalized = degrees.truncatingRemainder(dividingBy: 360) + 360
        let index = Int((normalized.truncatingRemainder(dividingBy: 360) + 22.5) / 45) % 8
        return labels[index]
    }

    static func detail(for availability: MetricAvailability) -> String {
        switch availability {
        case .acquiring:
            "Acquiring"
        case .available:
            "Live"
        case .stale:
            "Stale — start moving"
        case .unavailable(let reason):
            reason
        }
    }

    static func isStale(_ availability: MetricAvailability) -> Bool {
        availability == .stale
    }

    private static func lengthMeasurement(
        _ meters: Double,
        unit: UnitLength
    ) -> Measurement<UnitLength> {
        Measurement(value: meters, unit: UnitLength.meters).converted(to: unit)
    }

    private static func measurementText(
        _ value: Double,
        unit: String,
        fractionLength: ClosedRange<Int>
    ) -> String {
        "\(value.formatted(.number.precision(.fractionLength(fractionLength)))) \(unit)"
    }
}

private extension WalkDistanceUnit {
    var distanceUnit: UnitLength {
        self == .metric ? .kilometers : .miles
    }

    var altitudeUnit: UnitLength {
        self == .metric ? .meters : .feet
    }

    var distanceSymbol: String {
        self == .metric ? "km" : "mi"
    }

    var altitudeSymbol: String {
        self == .metric ? "m" : "ft"
    }

    var speedSymbol: String {
        self == .metric ? "km/h" : "mph"
    }
}
