import SwiftUI
import UIKit

/// Design tokens for papaSteps.
///
/// Colors are declared once here as dynamic `UIColor` values so a single
/// definition covers light, dark, and high-contrast appearances, and so the
/// palette can be unit tested for contrast (see `ThemeContrastTests`).
/// `AccentColor` in the asset catalog mirrors `brandGreen` for system-tinted
/// controls; every papaSteps view should name a semantic token instead of
/// relying on the accent.
enum PapaPalette {
    /// Vivid brand green. Only ever used as a *fill* behind `onBrandGreen`,
    /// never as text on a light surface: `#00C853` on white is 2.2:1 and would
    /// fail.
    static let brandGreen = dynamic(light: 0x00C853, dark: 0x00E05A)

    /// Green for text and small icons. 5.2:1 on white, 12.6:1 on black.
    static let brandGreenInk = dynamic(
        light: 0x0A7D3C,
        dark: 0x3BE477,
        highContrastLight: 0x06612F,
        highContrastDark: 0x63F09A
    )

    /// Primary text color: black on light, white on dark.
    static let brandInk = dynamic(light: 0x000000, dark: 0xFFFFFF)

    /// Label color *on top of* a `brandGreen` fill. Always black, in both
    /// appearances — the fill does not invert with the interface style, so a
    /// label that did would drop to about 1.6:1 in dark mode.
    static let onBrandGreen = dynamic(light: 0x000000, dark: 0x000000)

    /// Fill for destructive actions. Held at the darker red in both
    /// appearances so a white label stays above 4.5:1.
    static let signalAlertFill = dynamic(light: 0xC4271C, dark: 0xC4271C)

    static let surfaceBase = dynamic(light: 0xFFFFFF, dark: 0x000000)
    static let surfaceRaised = dynamic(light: 0xF6F7F8, dark: 0x121316)
    static let surfaceSunken = dynamic(light: 0xEEF0F2, dark: 0x0A0B0C)
    static let strokeHairline = dynamic(
        light: Swatch(0x000000, alpha: 0.08),
        dark: Swatch(0xFFFFFF, alpha: 0.12),
        highContrastLight: Swatch(0x000000, alpha: 0.20),
        highContrastDark: Swatch(0xFFFFFF, alpha: 0.30)
    )

    static let textPrimary = dynamic(light: 0x0B0B0C, dark: 0xFFFFFF)
    static let textSecondary = dynamic(
        light: 0x6B7078,
        dark: 0x8A8F98,
        highContrastLight: 0x4E535A,
        highContrastDark: 0xA8ADB5
    )
    static let textTertiary = dynamic(light: 0x8A8F98, dark: 0x6B7078)

    static let signalGood = dynamic(
        light: 0x0A7D3C,
        dark: 0x00E05A,
        highContrastLight: 0x06612F,
        highContrastDark: 0x3BE477
    )
    static let signalCaution = dynamic(
        light: 0xB45309,
        dark: 0xFF9F0A,
        highContrastLight: 0x8A3E06,
        highContrastDark: 0xFFB733
    )
    static let signalAlert = dynamic(
        light: 0xC4271C,
        dark: 0xFF453A,
        highContrastLight: 0x9C1F16,
        highContrastDark: 0xFF6B62
    )
    /// Apple Health attribution only.
    static let signalHealth = dynamic(light: 0xC2185B, dark: 0xFF6482)
    /// Achievements and personal bests.
    static let signalAward = dynamic(light: 0xA16207, dark: 0xFFD60A)

    /// One resolved appearance of a token: an `0xRRGGBB` value and an opacity.
    struct Swatch: Equatable, Sendable, ExpressibleByIntegerLiteral {
        let rgb: UInt32
        let alpha: Double

        init(_ rgb: UInt32, alpha: Double = 1) {
            self.rgb = rgb
            self.alpha = alpha
        }

        init(integerLiteral value: UInt32) {
            self.init(value)
        }

        var uiColor: UIColor {
            UIColor(
                red: CGFloat((rgb >> 16) & 0xFF) / 255,
                green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255,
                alpha: alpha
            )
        }
    }

    private static func dynamic(
        light: Swatch,
        dark: Swatch,
        highContrastLight: Swatch? = nil,
        highContrastDark: Swatch? = nil
    ) -> UIColor {
        UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let isHighContrast = traits.accessibilityContrast == .high
            let swatch: Swatch = switch (isDark, isHighContrast) {
            case (false, false): light
            case (false, true): highContrastLight ?? light
            case (true, false): dark
            case (true, true): highContrastDark ?? dark
            }
            return swatch.uiColor
        }
    }
}

extension Color {
    static let brandGreen = Color(uiColor: PapaPalette.brandGreen)
    static let brandGreenInk = Color(uiColor: PapaPalette.brandGreenInk)
    static let brandInk = Color(uiColor: PapaPalette.brandInk)
    static let onBrandGreen = Color(uiColor: PapaPalette.onBrandGreen)
    static let signalAlertFill = Color(uiColor: PapaPalette.signalAlertFill)

    static let surfaceBase = Color(uiColor: PapaPalette.surfaceBase)
    static let surfaceRaised = Color(uiColor: PapaPalette.surfaceRaised)
    static let surfaceSunken = Color(uiColor: PapaPalette.surfaceSunken)
    static let strokeHairline = Color(uiColor: PapaPalette.strokeHairline)

    static let textPrimary = Color(uiColor: PapaPalette.textPrimary)
    static let textSecondary = Color(uiColor: PapaPalette.textSecondary)
    static let textTertiary = Color(uiColor: PapaPalette.textTertiary)

    static let signalGood = Color(uiColor: PapaPalette.signalGood)
    static let signalCaution = Color(uiColor: PapaPalette.signalCaution)
    static let signalAlert = Color(uiColor: PapaPalette.signalAlert)
    static let signalHealth = Color(uiColor: PapaPalette.signalHealth)
    static let signalAward = Color(uiColor: PapaPalette.signalAward)
    static let signalNeutral = Color(uiColor: PapaPalette.textSecondary)
}

// MARK: - Spacing, shape, and type

enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let small: CGFloat = 12
    static let medium: CGFloat = 16
    static let large: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32

    /// Standard leading/trailing screen margin.
    static let screenMargin: CGFloat = 20
    /// Standard interior padding of a card.
    static let cardPadding: CGFloat = 16
    /// Gutter between cards in a grid.
    static let gridGutter: CGFloat = 12
}

enum Radius {
    static let card: CGFloat = 20
    static let hero: CGFloat = 28
    static let map: CGFloat = 20
    static let control: CGFloat = 14
}

extension Font {
    /// Large single-value display. Scales with Dynamic Type via `@ScaledMetric`
    /// at the call site.
    static func heroMetric(size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
    }

    /// Value inside a metric card.
    static let metricValue = Font.title2.weight(.semibold).monospacedDigit()
    /// Label above a metric value.
    static let metricTitle = Font.footnote.weight(.medium)
    /// Provenance or availability line below a metric value.
    static let metricCaption = Font.caption
    /// Heading of a card or section.
    static let sectionHeader = Font.title3.weight(.semibold)
}

// MARK: - Surfaces

private struct CardSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(Color.surfaceRaised, in: shape)
            .overlay(shape.strokeBorder(Color.strokeHairline, lineWidth: 1))
            .shadow(
                color: colorScheme == .dark ? .clear : .black.opacity(0.06),
                radius: 3,
                y: 1
            )
    }
}

extension View {
    /// The standard papaSteps card: raised fill, hairline border, and a soft
    /// shadow in light mode only. Apply after the card's own padding.
    func cardSurface(cornerRadius: CGFloat = Radius.card) -> some View {
        modifier(CardSurface(cornerRadius: cornerRadius))
    }

    /// A tinted informational panel — used for limitation banners and the
    /// Apple Health section, where the tint itself carries meaning.
    func tintedSurface(_ tint: Color, cornerRadius: CGFloat = Radius.card) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(tint.opacity(0.12), in: shape)
            .overlay(shape.strokeBorder(tint.opacity(0.28), lineWidth: 1))
    }
}

// MARK: - Buttons

/// The primary action: a bright green capsule with a black label. The label is
/// deliberately `brandInk` rather than white — white on `brandGreen` is about
/// 1.6:1 and would be unreadable.
struct PrimaryWalkButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    var isDestructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(isDestructive ? Color.white : Color.onBrandGreen)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(fill, in: .capsule)
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
            .contentShape(.capsule)
    }

    private var fill: Color {
        isDestructive ? .signalAlertFill : .brandGreen
    }
}

/// The secondary action beside a primary one: same size, neutral surface.
struct SecondaryWalkButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.surfaceRaised, in: .capsule)
            .overlay(Capsule().strokeBorder(Color.strokeHairline, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
            .contentShape(.capsule)
    }
}

extension ButtonStyle where Self == PrimaryWalkButtonStyle {
    static var primaryWalk: PrimaryWalkButtonStyle { PrimaryWalkButtonStyle() }
    static var destructiveWalk: PrimaryWalkButtonStyle {
        PrimaryWalkButtonStyle(isDestructive: true)
    }
}

extension ButtonStyle where Self == SecondaryWalkButtonStyle {
    static var secondaryWalk: SecondaryWalkButtonStyle { SecondaryWalkButtonStyle() }
}

