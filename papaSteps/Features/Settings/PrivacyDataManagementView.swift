import SwiftUI

struct PrivacyDataManagementView: View {
    @Environment(WalkHistoryStore.self) private var historyStore
    @State private var isConfirmingDeletion = false

    var body: some View {
        Form {
            Section("Privacy") {
                Text("Walk summaries, accepted route points, and optional Health insight results are stored in papaSteps on this iPhone. papaSteps does not upload them to a server or analytics service.")
                Text("If you choose Save new walks to Apple Health, Apple Health stores a separate workout and route under Apple’s privacy controls.")
            }

            Section("Export") {
                Text("This beta does not export a file of your walk data. Your walks remain available in History on this iPhone. Export formats will be considered only after privacy, route-redaction, and support requirements are defined.")
                    .foregroundStyle(Color.textSecondary)
            }

            Section("Delete local data") {
                Button("Delete All Local Walk Data", role: .destructive) {
                    isConfirmingDeletion = true
                }
                .foregroundStyle(Color.signalAlert)
                .accessibilityIdentifier("privacy.deleteAll")

                Text("This permanently deletes all papaSteps walk summaries, drafts, and saved route points from this iPhone. It does not delete workouts already saved to Apple Health.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .navigationTitle("Privacy & Data")
        .confirmationDialog(
            "Delete all local walk data permanently?",
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete All Local Data", role: .destructive) {
                historyStore.deleteAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. Apple Health workouts will remain in Apple Health.")
        }
    }
}
