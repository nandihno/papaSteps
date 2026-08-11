import SwiftUI

struct WalkFinishSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDiscard = false

    let store: WalkSessionStore

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "checkered.flag.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text("Finish this walk?")
                        .font(.title2.bold())
                    Text("Your locally recorded steps, time, distance, and elevation will be saved.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                Button("Finish Walk") {
                    dismiss()
                    Task { await store.finish() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("walk.finish.confirm")

                Button("Keep Walking") {
                    store.keepWalking()
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
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
