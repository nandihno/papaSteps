import SwiftUI

struct HealthWorkoutImportView: View {
    @Environment(HealthWorkoutImportStore.self) private var store
    @Environment(WalkHistoryStore.self) private var historyStore

    var body: some View {
        Group {
            if store.isLoading && store.items.isEmpty {
                ProgressView("Checking Apple Health…")
            } else if store.items.isEmpty {
                ContentUnavailableView {
                    Label("No walking workouts", systemImage: WalkSymbol.walk)
                } description: {
                    Text(store.message ?? "No walking workouts were returned for the last 90 days. An empty result can also mean read access was declined.")
                } actions: {
                    Button("Check Again") {
                        Task { await store.load() }
                    }
                }
            } else {
                List {
                    Section {
                        ForEach(store.items) { item in
                            Button {
                                store.toggleSelection(id: item.id)
                            } label: {
                                HealthWorkoutImportRow(
                                    item: item,
                                    isSelected: store.selectedIDs.contains(item.id)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(item.isImported || store.isImporting)
                            .accessibilityIdentifier("health.import.workout.\(item.id.uuidString)")
                        }
                    } header: {
                        Text("Last 90 days")
                    } footer: {
                        Text("Workouts already exported by papaSteps are omitted. Imported copies remain in Apple Health if you later delete them from papaSteps.")
                    }

                    if let message = store.message {
                        Section("Status") {
                            Text(message)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Import Walks")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store.items.isEmpty {
                await store.load()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if store.selectableCount > 0 {
                    Button(store.selectedIDs.isEmpty ? "Select All" : "Clear") {
                        if store.selectedIDs.isEmpty {
                            store.selectAllAvailable()
                        } else {
                            store.clearSelection()
                        }
                    }
                    .disabled(store.isImporting)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Import") {
                    Task {
                        _ = await store.importSelected()
                        historyStore.load()
                    }
                }
                .disabled(!store.canImport)
                .accessibilityIdentifier("health.import.confirm")
            }
        }
        .overlay {
            if store.isImporting {
                ProgressView("Importing selected walks…")
                    .padding()
                    .background(.regularMaterial, in: .rect(cornerRadius: 12))
            }
        }
    }
}

private struct HealthWorkoutImportRow: View {
    @Environment(WalkDisplayPreferences.self) private var displayPreferences
    let item: HealthWorkoutImportStore.Item
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: selectionImage)
                .font(.title3)
                .foregroundStyle(selectionColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.workout.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.headline)
                HStack(spacing: 12) {
                    Label(
                        WalkMetricFormatting.distance(
                            item.workout.distanceMeters,
                            configuration: displayPreferences.configuration
                        ),
                        systemImage: WalkSymbol.distance
                    )
                    Label(
                        WalkMetricFormatting.duration(item.workout.movingDuration),
                        systemImage: WalkSymbol.movingTime
                    )
                }
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                Text(item.workout.sourceName)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                if item.isAwaitingRoute {
                    Text("Imported without a route — import again to add the map.")
                        .font(.caption)
                        .foregroundStyle(Color.signalCaution)
                }
            }

            Spacer()

            if item.isImported {
                Text("Imported")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.signalGood)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        if item.isImported { return "Already imported" }
        if item.isAwaitingRoute {
            return isSelected
                ? "Imported without a route, selected to add the route"
                : "Imported without a route, not selected"
        }
        return isSelected ? "Selected" : "Not selected"
    }

    private var selectionImage: String {
        if item.isImported { return WalkSymbol.good }
        return isSelected ? WalkSymbol.good : "circle"
    }

    private var selectionColor: Color {
        item.isImported ? .signalGood : (isSelected ? .brandGreenInk : .textSecondary)
    }
}
