import SwiftUI

/// A single measurement: what it is, what it reads, and where the number came
/// from. The provenance line is not decoration — it is how the app stays honest
/// about a value it only estimated.
struct MetricTile: View {
    enum Size {
        /// Two-up grid tile.
        case standard
        /// Three-up row under the hero metric, on the live walk screen.
        case compact
    }

    let title: String
    let value: String
    let detail: String
    let systemImage: String
    var size: Size = .standard
    var isStale = false
    var accentsValue = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? Spacing.xxs : Spacing.xs) {
            Label(title, systemImage: systemImage)
                .font(isCompact ? .caption.weight(.medium) : .metricTitle)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(value)
                .font(isCompact ? .title3.weight(.semibold) : .metricValue)
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .contentTransition(.numericText())

            Text(detail)
                .font(.metricCaption)
                .foregroundStyle(isStale ? Color.signalCaution : Color.textSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .topLeading)
        .padding(isCompact ? Spacing.small : Spacing.cardPadding)
        .cardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue("\(value). \(detail)")
        .accessibilityHint(isStale ? "This metric may be out of date." : "")
    }

    private var isCompact: Bool {
        size == .compact && !dynamicTypeSize.isAccessibilitySize
    }

    private var minimumHeight: CGFloat {
        isCompact ? 88 : 112
    }

    private var valueColor: Color {
        if isStale { return .textSecondary }
        return accentsValue ? .brandGreenInk : .textPrimary
    }
}

/// The one number a screen is really about, with the recording state ring
/// around it. Used for live speed and for the saved-walk distance.
struct HeroMetric<Accessory: View>: View {
    let title: String
    let value: String
    let detail: String
    var isStale = false
    @ViewBuilder let accessory: Accessory

    /// Point size before Dynamic Type scaling, which `Font.heroMetric` applies.
    private let valueSize: CGFloat = 60

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.textSecondary)
                .textCase(nil)

            Text(value)
                .font(.heroMetric(size: valueSize))
                .monospacedDigit()
                .foregroundStyle(isStale ? Color.textSecondary : Color.textPrimary)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText())

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(isStale ? Color.signalCaution : Color.textSecondary)
                .multilineTextAlignment(.center)

            accessory
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue("\(value). \(detail)")
    }
}

extension HeroMetric where Accessory == EmptyView {
    init(title: String, value: String, detail: String, isStale: Bool = false) {
        self.init(title: title, value: value, detail: detail, isStale: isStale) {
            EmptyView()
        }
    }
}

/// A capsule showing one capability and its state in plain words. Tappable when
/// there is something the user can actually do about it.
struct StatusChip: View {
    let title: String
    let state: any UserFacingState
    let systemImage: String
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { chip }
                .buttonStyle(.plain)
                .accessibilityHint("Shows what this affects.")
        } else {
            chip
        }
    }

    private var chip: some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.textPrimary)
            Text(state.shortDisplayName)
                .font(.caption)
                .foregroundStyle(state.signalColor)
                .lineLimit(1)
        }
        .padding(.horizontal, Spacing.small)
        .padding(.vertical, Spacing.xs)
        .background(Color.surfaceRaised, in: .capsule)
        .overlay(Capsule().strokeBorder(Color.strokeHairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(state.displayName)
    }
}

/// A titled card. Replaces the repeated
/// `.padding().background(.quaternary, in: .rect(cornerRadius: 16))` pattern.
struct SectionCard<Content: View>: View {
    var title: String?
    var systemImage: String?
    var tint: Color?
    var footnote: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            if let title {
                Label {
                    Text(title)
                } icon: {
                    if let systemImage {
                        Image(systemName: systemImage)
                    }
                }
                .font(.sectionHeader)
                .foregroundStyle(tint ?? .textPrimary)
            }

            content

            if let footnote {
                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SectionCardSurface(tint: tint))
    }
}

private struct SectionCardSurface: ViewModifier {
    let tint: Color?

    func body(content: Content) -> some View {
        if let tint {
            content.tintedSurface(tint)
        } else {
            content.cardSurface()
        }
    }
}

/// Lays chips out left to right, wrapping to the next line when they run out of
/// room. A horizontal scroll view would hide readiness state that the screen
/// exists to report, and clip the last chip at the screen edge.
struct WrappingChips: Layout {
    var spacing: CGFloat = Spacing.xs

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = arrange(subviews: subviews, maxWidth: maxWidth)
        let height = rows.reduce(into: 0.0) { total, row in
            total += row.height + (total > 0 ? spacing : 0)
        }
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = arrange(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
