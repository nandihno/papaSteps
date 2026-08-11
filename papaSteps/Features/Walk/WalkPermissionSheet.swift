import SwiftUI
import UIKit

struct WalkPermissionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let store: WalkSessionStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Motion & Fitness")
                                .font(.headline)
                            Text("Provides live steps, pedometer distance, and movement evidence.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "figure.walk.motion")
                    }

                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Location While Using the App")
                                .font(.headline)
                            Text("Provides GPS speed, direction, altitude, and the current-position map.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "location")
                    }
                } header: {
                    Text("Used during a walk")
                } footer: {
                    Text("papaSteps continues with the available sensors when one permission is declined. Apple Health remains optional and is not requested here.")
                }

                if store.permissionSnapshot.locationAccuracy == .reduced {
                    Section("Precise Location") {
                        Label(
                            "Precise Location improves route distance, GPS speed, direction, and map position. You can continue without it.",
                            systemImage: "location.slash.circle"
                        )
                    }
                }

                Section {
                    if store.canOpenSettings {
                        Button("Open Settings") {
                            openSettings()
                        }
                    }

                    Button(primaryActionTitle) {
                        dismiss()
                        Task {
                            await store.start(requestPermissions: true)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAttemptWalk)
                    .accessibilityIdentifier("walk.permissions.continue")
                }
            }
            .navigationTitle("Prepare Your Walk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var canAttemptWalk: Bool {
        store.permissionSnapshot.hasUsableTrackingSource
            || store.permissionSnapshot.motionAuthorization == .notDetermined
            || store.permissionSnapshot.locationAuthorization == .notDetermined
    }

    private var primaryActionTitle: String {
        if store.canOpenSettings {
            return store.permissionSnapshot.hasUsableTrackingSource
                ? "Start With Available Sensors"
                : "Permissions Required"
        }
        if store.permissionSnapshot.locationAccuracy == .reduced {
            return "Request Precise Location & Start"
        }
        return "Continue"
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}
