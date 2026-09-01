import SwiftUI

struct HealthSettingsView: View {
    @Environment(WalkHealthStore.self) private var store
    @Environment(HealthWorkoutAutoImporter.self) private var autoImporter
    @State private var isConfirmingWorkoutExport = false

    var body: some View {
        Form {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Optional Health insights")
                            .font(.headline)
                        Text("After a walk, papaSteps can look for heart rate, walking asymmetry, steps, and distance in Apple Health.")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }
                } icon: {
                    Image(systemName: WalkSymbol.healthDetail)
                        .foregroundStyle(Color.signalHealth)
                }
            }

            Section("Access") {
                LabeledContent("Apple Health") {
                    Text(store.accessState.displayName)
                        .foregroundStyle(store.accessState.signalColor)
                }

                if store.accessState == .notRequested {
                    Button("Connect Apple Health") {
                        Task { await store.requestAccess() }
                    }
                    .accessibilityIdentifier("health.connect")
                } else if store.accessState == .requested {
                    Text("Access has been requested. For privacy, an empty result may mean no matching samples or declined read access; papaSteps does not guess which.")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                } else {
                    Text("Apple Health is unavailable on this device. Walk recording remains fully usable.")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            Section("Workout export") {
                Toggle(
                    "Save new walks to Apple Health",
                    isOn: Binding(
                        get: { store.workoutExportEnabled },
                        set: { enabled in
                            if enabled {
                                isConfirmingWorkoutExport = true
                            } else {
                                Task { await store.setWorkoutExportEnabled(false) }
                            }
                        }
                    )
                )
                .disabled(store.accessState == .unavailable)
                .accessibilityIdentifier("health.workout.toggle")

                Text("When enabled, each completed walk and accepted route is written once using the local walk ID as an Apple Health correlation key. Turning this off does not delete existing workouts.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
            }

            Section("Workout import") {
                NavigationLink {
                    HealthWorkoutImportView()
                } label: {
                    Label("Import walking workouts", systemImage: WalkSymbol.importWorkouts)
                }
                .disabled(store.accessState == .unavailable)
                .accessibilityIdentifier("health.import.open")

                Text("Review walking workouts from the last 90 days and choose which ones to copy into papaSteps. Existing papaSteps exports are omitted and workouts are imported only once.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)

                Toggle(
                    "Import new walks automatically",
                    isOn: Binding(
                        get: { autoImporter.isEnabled },
                        set: { enabled in
                            Task { await autoImporter.setEnabled(enabled) }
                        }
                    )
                )
                .disabled(!autoImporter.isAvailable)
                .accessibilityIdentifier("health.autoImport.toggle")

                Text("Apple Health can wake papaSteps when a walking workout is saved, so an Apple Watch walk — recorded with the watch's own GPS — appears here without opening this screen. Only walks recorded after you turn this on are imported; use Import Walks for older ones.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)

                if let message = autoImporter.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            Section("Privacy") {
                Text("Health and precise route data stay on this iPhone and in Apple Health. papaSteps does not upload them.")
                    .foregroundStyle(Color.textSecondary)
            }

            if let message = store.lastMessage {
                Section("Status") {
                    Text(message)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .navigationTitle("Apple Health")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if store.isWorking {
                ProgressView("Contacting Apple Health…")
                    .padding()
                    .background(.regularMaterial, in: .rect(cornerRadius: 12))
            }
        }
        .confirmationDialog(
            "Save new walks to Apple Health?",
            isPresented: $isConfirmingWorkoutExport,
            titleVisibility: .visible
        ) {
            Button("Enable Workout Export") {
                Task { await store.setWorkoutExportEnabled(true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Apple will show a permission sheet for workout and route writes. Retries use a metadata key so the same local walk is not written twice.")
        }
    }
}
