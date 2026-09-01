import SwiftUI
import UIKit

struct WalkRecordingSettingsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(WalkSessionStore.self) private var sessionStore
    @Environment(WalkDisplayPreferences.self) private var displayPreferences

    var body: some View {
        Form {
            Section("Display") {
                Picker("Distance and elevation", selection: Bindable(displayPreferences).distanceUnit) {
                    ForEach(WalkDistanceUnit.allCases, id: \.self) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
                .accessibilityIdentifier("walk.settings.distanceUnit")

                Text("Example: \(WalkMetricFormatting.distance(5_000, configuration: displayPreferences.configuration))")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)

                Picker("Live movement", selection: Bindable(displayPreferences).speedDisplay) {
                    ForEach(WalkSpeedDisplay.allCases, id: \.self) { display in
                        Text(display.displayName).tag(display)
                    }
                }
                .accessibilityIdentifier("walk.settings.speedDisplay")

                Text("Example: \(WalkMetricFormatting.speed(1.4, configuration: displayPreferences.configuration))")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)

                Text("These choices change how current and saved walks are displayed. papaSteps always stores distance, altitude, and speed in base metric units.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
            }

            Section("Finish prompting") {
                Toggle(
                    "Notify me when a walk may be finished",
                    isOn: Binding(
                        get: { sessionStore.finishRemindersEnabled },
                        set: { enabled in
                            Task {
                                await sessionStore.setFinishRemindersEnabled(enabled)
                            }
                        }
                    )
                )
                .accessibilityIdentifier("walk.settings.finishReminders")

                Text("papaSteps waits for corroborating step, movement, location, and Motion evidence. It never finishes a walk without your confirmation.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)

                if sessionStore.notificationAuthorizationState == .denied {
                    Button("Open Notification Settings") {
                        openSettings()
                    }
                }
            }

            Section("Lock Screen") {
                Label("Live walk metrics", systemImage: WalkSymbol.motion)
                Text("During an active walk, the Lock Screen can show elapsed time, moving time, steps, distance, and Pause, Resume, Finish, or Keep Walking actions. Live Activities can be disabled separately in iPhone Settings.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
            }

            Section("Background recording") {
                Text("Location recording continues only while a walk is active and uses When In Use access. papaSteps does not request Always Location access.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
            }

            Section("Privacy & data") {
                NavigationLink {
                    PrivacyDataManagementView()
                } label: {
                    Label("Privacy & Data", systemImage: WalkSymbol.privacy)
                }
                .disabled(!canManageLocalData)

                if !canManageLocalData {
                    Text("Finish, pause and discard, or recover the current walk before deleting local data.")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .navigationTitle("Walk Recording")
        .task {
            await sessionStore.refreshExternalExperienceState()
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private var canManageLocalData: Bool {
        switch sessionStore.state {
        case .idle, .completed:
            true
        case .preparing, .active, .paused, .finishCandidate, .finalizing, .recoverableFailure:
            false
        }
    }
}
