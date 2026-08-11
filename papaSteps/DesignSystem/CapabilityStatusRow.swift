import SwiftUI

struct CapabilityStatusRow: View {
    let status: CapabilityStatus

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(status.title)
                    .font(.body.weight(.medium))
                Text(status.detail)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(accessibilityValue)
    }

    private var iconName: String {
        status.availability.symbolName
    }

    private var iconColor: Color {
        status.availability.signalColor
    }

    private var accessibilityValue: String {
        "\(status.availability.displayName). \(status.detail)"
    }
}
