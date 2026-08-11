import Testing
import UIKit
@testable import papaSteps

/// Verifies the palette against WCAG contrast thresholds in both appearances,
/// so a color change is caught here rather than in a squint test on a sunny
/// pavement.
///
/// AA thresholds: 4.5:1 for body text, 3:1 for large text and meaningful
/// graphics.
@MainActor
struct ThemeContrastTests {
    private let light = UITraitCollection(userInterfaceStyle: .light)
    private let dark = UITraitCollection(userInterfaceStyle: .dark)

    @Test func primaryTextMeetsBodyContrast() {
        for traits in [light, dark] {
            #expect(ratio(PapaPalette.textPrimary, on: PapaPalette.surfaceBase, traits) >= 4.5)
            #expect(ratio(PapaPalette.textPrimary, on: PapaPalette.surfaceRaised, traits) >= 4.5)
        }
    }

    @Test func secondaryTextMeetsBodyContrast() {
        for traits in [light, dark] {
            #expect(ratio(PapaPalette.textSecondary, on: PapaPalette.surfaceBase, traits) >= 4.5)
            #expect(ratio(PapaPalette.textSecondary, on: PapaPalette.surfaceRaised, traits) >= 4.5)
        }
    }

    /// The signature pairing: a black label on a bright green fill, in both
    /// appearances. `brandInk` must *not* be used here — it inverts to white in
    /// dark mode, which lands at about 1.6:1 on the green fill.
    @Test func primaryButtonLabelIsReadableOnTheGreenFill() {
        for traits in [light, dark] {
            #expect(ratio(PapaPalette.onBrandGreen, on: PapaPalette.brandGreen, traits) >= 4.5)
        }
        #expect(ratio(PapaPalette.brandInk, on: PapaPalette.brandGreen, dark) < 4.5)
    }

    @Test func destructiveButtonLabelIsReadableOnItsFill() {
        for traits in [light, dark] {
            #expect(ratio(.white, on: PapaPalette.signalAlertFill, traits) >= 4.5)
        }
    }

    @Test func greenTextUsesTheInkVariantNotTheFill() {
        // The fill green is deliberately unreadable as text on a light surface;
        // this asserts the ink variant exists precisely because of that.
        #expect(ratio(PapaPalette.brandGreen, on: PapaPalette.surfaceBase, light) < 4.5)
        for traits in [light, dark] {
            #expect(ratio(PapaPalette.brandGreenInk, on: PapaPalette.surfaceBase, traits) >= 4.5)
            #expect(ratio(PapaPalette.brandGreenInk, on: PapaPalette.surfaceRaised, traits) >= 4.5)
        }
    }

    @Test func semanticStatesMeetBodyContrastOnCards() {
        let states = [
            PapaPalette.signalGood,
            PapaPalette.signalCaution,
            PapaPalette.signalAlert,
            PapaPalette.signalHealth,
            PapaPalette.signalAward
        ]
        for traits in [light, dark] {
            for state in states {
                #expect(ratio(state, on: PapaPalette.surfaceRaised, traits) >= 4.5)
                #expect(ratio(state, on: PapaPalette.surfaceBase, traits) >= 4.5)
            }
        }
    }

    @Test func highContrastVariantsAreNoWorseThanStandard() {
        let pairs: [(UIColor, UIColor)] = [
            (PapaPalette.textSecondary, PapaPalette.surfaceBase),
            (PapaPalette.brandGreenInk, PapaPalette.surfaceBase),
            (PapaPalette.signalGood, PapaPalette.surfaceRaised),
            (PapaPalette.signalCaution, PapaPalette.surfaceRaised),
            (PapaPalette.signalAlert, PapaPalette.surfaceRaised)
        ]
        for style in [UIUserInterfaceStyle.light, .dark] {
            let standard = UITraitCollection(userInterfaceStyle: style)
            let increased = UITraitCollection { mutable in
                mutable.userInterfaceStyle = style
                mutable.accessibilityContrast = .high
            }
            for (foreground, background) in pairs {
                #expect(
                    ratio(foreground, on: background, increased)
                        >= ratio(foreground, on: background, standard) - 0.01
                )
            }
        }
    }

    // MARK: - WCAG relative luminance

    private func ratio(
        _ foreground: UIColor,
        on background: UIColor,
        _ traits: UITraitCollection
    ) -> Double {
        let first = luminance(foreground.resolvedColor(with: traits))
        let second = luminance(background.resolvedColor(with: traits))
        let lighter = max(first, second)
        let darker = min(first, second)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func luminance(_ color: UIColor) -> Double {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func channel(_ value: CGFloat) -> Double {
            let value = Double(value)
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }
}
