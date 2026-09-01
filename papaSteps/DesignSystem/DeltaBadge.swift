import SwiftUI

/// How this week compares to a reference point — best week, previous week, or
/// a rolling average — colored by whether the current week is ahead or behind.
struct DeltaBadge: View {
    enum Direction {
        case ahead
        case behind
        case even
        case unavailable
    }

    let text: String
    let direction: Direction

    init(text: String, direction: Direction) {
        self.text = text
        self.direction = direction
    }

    /// Threshold below which a change reads as "even" rather than a direction,
    /// so rounding noise near zero does not flip between up and down arrows.
    private static let evenThreshold = 0.005

    init(comparison: ProgressComparison) {
        guard let percentageChange = comparison.percentageChange,
              comparison.referenceValue != nil else {
            self.init(text: "Not enough history yet", direction: .unavailable)
            return
        }
        let referenceName = comparison.kind.title.lowercased()
        let magnitude = abs(percentageChange).formatted(.percent.precision(.fractionLength(0)))
        if percentageChange > Self.evenThreshold {
            self.init(text: "\(magnitude) ahead of your \(referenceName)", direction: .ahead)
        } else if percentageChange < -Self.evenThreshold {
            self.init(text: "\(magnitude) behind your \(referenceName)", direction: .behind)
        } else {
            self.init(text: "Even with your \(referenceName)", direction: .even)
        }
    }

    var body: some View {
        Label {
            Text(text)
                .font(.subheadline)
        } icon: {
            if let symbol {
                Image(systemName: symbol)
                    .font(.caption.weight(.bold))
            }
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String? {
        switch direction {
        case .ahead: "arrow.up"
        case .behind: "arrow.down"
        case .even, .unavailable: nil
        }
    }

    private var color: Color {
        switch direction {
        case .ahead: .signalGood
        case .behind: .signalCaution
        case .even: .textSecondary
        case .unavailable: .signalNeutral
        }
    }
}
