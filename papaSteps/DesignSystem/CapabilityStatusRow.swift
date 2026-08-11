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
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(accessibilityValue)
    }

    private var iconName: String {
        switch status.availability {
        case .available:
            "checkmark.circle.fill"
        case .permissionRequired:
            "lock.circle.fill"
        case .limited:
            "exclamationmark.circle.fill"
        case .unavailable:
            "xmark.circle.fill"
        case .checking:
            "ellipsis.circle.fill"
        }
    }

    private var iconColor: Color {
        switch status.availability {
        case .available:
            .green
        case .permissionRequired:
            .blue
        case .limited:
            .orange
        case .unavailable:
            .secondary
        case .checking:
            .secondary
        }
    }

    private var accessibilityValue: String {
        "\(status.availability.rawValue). \(status.detail)"
    }
}
