import SwiftUI

struct WalkFinishSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDiscard = false
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize: CGFloat = 64

    let store: WalkSessionStore

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: WalkSymbol.finishPrompt)
                    .font(.system(size: symbolSize))
                    .foregroundStyle(Color.brandGreenInk)
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text("Finish this walk?")
                        .font(.title2.bold())
                    Text("Your locally recorded steps, time, distance, and elevation will be saved.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.textSecondary)
                }

                Button("Finish Walk") {
                    dismiss()
                    Task { await store.finish() }
                }
                .buttonStyle(.primaryWalk)
                .accessibilityIdentifier("walk.finish.confirm")

                Button("Keep Walking") {
                    store.keepWalking()
                    dismiss()
                }
                .buttonStyle(.secondaryWalk)
                .accessibilityIdentifier("walk.finish.keepWalking")

                Button("Discard Walk", role: .destructive) {
                    isConfirmingDiscard = true
                }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("walk.finish.discard")
            }
            .padding()
            .navigationTitle("Done")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
            .confirmationDialog(
                "Discard this walk permanently?",
                isPresented: $isConfirmingDiscard,
                titleVisibility: .visible
            ) {
                Button("Discard Permanently", role: .destructive) {
                    dismiss()
                    Task { await store.discard() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The current walk and its measurements will not be saved. This cannot be undone.")
            }
        }
        .presentationDetents([.medium])
    }
}
