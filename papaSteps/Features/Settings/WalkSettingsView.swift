import SwiftUI

/// The single entry point for everything under the Walk tab's toolbar.
/// Replaces three icon-only toolbar buttons — whose meaning was guesswork —
/// with one labeled "Settings" button leading here.
struct WalkSettingsView: View {
    private let versionInfo = AppVersionInfo()

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    WalkRecordingSettingsView()
                } label: {
                    Label("Walk Recording", systemImage: WalkSymbol.settings)
                }
                .accessibilityIdentifier("walk.recording.settings")

                NavigationLink {
                    HealthSettingsView()
                } label: {
                    Label("Apple Health", systemImage: WalkSymbol.healthDetail)
                }
                .accessibilityIdentifier("walk.health.settings")
            }

#if DEBUG
            Section {
                NavigationLink {
                    SensorDiagnosticsView()
                } label: {
                    Label("Sensor Diagnostics", systemImage: WalkSymbol.diagnostics)
                }
                .accessibilityIdentifier("walk.diagnostics")
            } footer: {
                Text("Visible in debug builds only.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
            }
#endif

            Section("About") {
                LabeledContent("Version") {
                    Text(versionInfo.displayValue)
                        .foregroundStyle(Color.textSecondary)
                        // Selectable so it can be copied straight into a bug report.
                        .textSelection(.enabled)
                }
                .accessibilityIdentifier("settings.version")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
