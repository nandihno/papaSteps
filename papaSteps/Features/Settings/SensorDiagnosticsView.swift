#if DEBUG
import SwiftUI
import UIKit

struct SensorDiagnosticsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SensorDiagnosticsStore.self) private var store

    var body: some View {
        Form {
            if store.snapshot.environment == .simulator {
                Section {
                    Label(
                        "Simulator sensor results are expected to be unavailable or simulated. Use a physical iPhone before deciding hardware support.",
                        systemImage: "iphone.gen3.slash"
                    )
                    .foregroundStyle(Color.textSecondary)
                }
            }

            capabilitySection(
                title: "Motion",
                statuses: store.snapshot.motion
            )

            capabilitySection(
                title: "Location",
                statuses: store.snapshot.location
            )

            capabilitySection(
                title: "Apple Health",
                statuses: store.snapshot.health
            )

            actionsSection
        }
        .navigationTitle("Sensor Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if store.isWorking {
                ProgressView("Checking…")
                    .padding()
                    .background(.regularMaterial, in: .rect(cornerRadius: 12))
            }
        }
        .task {
            await store.refresh(requestLocationFix: true)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await store.refresh(requestLocationFix: true)
            }
        }
    }

    private var actionsSection: some View {
        Section("Actions") {
            if store.motionAuthorization == .notDetermined {
                Button("Request Motion Access") {
                    Task { await store.requestMotionAuthorization() }
                }
            }

            if store.locationAuthorization == .notDetermined {
                Button("Request When In Use Location") {
                    Task { await store.requestLocationAuthorization() }
                }
            }

            if store.locationAuthorization.permitsLocation,
               store.locationAccuracy == .reduced {
                Button("Request Precise Location") {
                    Task { await store.requestTemporaryFullAccuracy() }
                }
            }

            if store.motionAuthorization == .denied
                || store.locationAuthorization == .denied {
                Button("Open Settings") {
                    openSettings()
                }
            }

            Button("Refresh Diagnostics") {
                Task { await store.refresh(requestLocationFix: true) }
            }
        }
    }

    private func capabilitySection(
        title: String,
        statuses: [CapabilityStatus]
    ) -> some View {
        Section(title) {
            ForEach(statuses) { status in
                CapabilityStatusRow(status: status)
            }
        }
    }

    private func openSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        openURL(settingsURL)
    }
}
#endif
