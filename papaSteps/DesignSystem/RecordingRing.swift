import SwiftUI

/// The live-walk recording indicator: a green ring that breathes while
/// recording, holds still and turns amber when paused, and drains to gray when
/// the walk is only waiting for movement.
///
/// The ring is decorative — the state it shows is also stated in words beside
/// it, so nothing here is the sole carrier of meaning.
enum RecordingRingState {
    case recording
    case waiting
    case paused

    var tint: Color {
        switch self {
        case .recording: .brandGreen
        case .waiting: .textSecondary
        case .paused: .signalCaution
        }
    }
}

struct RecordingRing<Content: View>: View {
    let state: RecordingRingState
    @ViewBuilder let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    var body: some View {
        content
            .padding(Spacing.xl)
            .background {
                Circle()
                    .stroke(state.tint.opacity(0.20), lineWidth: 10)
                    .overlay {
                        Circle()
                            .stroke(
                                state.tint.opacity(state == .waiting ? 0.5 : 1),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round)
                            )
                    }
                    .scaleEffect(isBreathing ? 1.03 : 1)
                    .opacity(isBreathing ? 1 : 0.85)
                    .animation(breathingAnimation, value: isBreathing)
                    .animation(.easeInOut(duration: 0.3), value: state)
            }
            .onAppear { isBreathing = shouldBreathe }
            .onChange(of: state) { _, _ in isBreathing = shouldBreathe }
            .accessibilityHidden(true)
    }

    private var shouldBreathe: Bool {
        state == .recording && !reduceMotion
    }

    private var breathingAnimation: Animation? {
        guard shouldBreathe else { return nil }
        return .easeInOut(duration: 1.6).repeatForever(autoreverses: true)
    }
}

/// The pinned Pause/Resume and Done pair on the live walk screen.
///
/// Liquid Glass sits behind it so map and route stay partly visible, and the
/// bar never scrolls away — mid-walk, these two controls must be reachable
/// without looking for them.
struct GlassControlBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GlassEffectContainer(spacing: Spacing.small) {
            HStack(spacing: Spacing.small) {
                content
            }
            .padding(.horizontal, Spacing.small)
            .padding(.vertical, Spacing.small)
            .glassEffect(.regular, in: .rect(cornerRadius: Radius.hero, style: .continuous))
        }
        .padding(.horizontal, Spacing.medium)
    }
}
