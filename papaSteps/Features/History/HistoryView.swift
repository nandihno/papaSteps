import SwiftUI

struct HistoryView: View {
    @Environment(WalkHistoryStore.self) private var historyStore
    @Environment(WalkSessionStore.self) private var sessionStore
    @Environment(WalkDisplayPreferences.self) private var displayPreferences
    @State private var walkPendingDeletion: WalkSummary?

    var body: some View {
        Group {
            if historyStore.summaries.isEmpty {
                ContentUnavailableView {
                    Label("No Walks Yet", systemImage: WalkSymbol.history)
                } description: {
                    Text("Finish a walk to save its summary and accepted GPS route on this iPhone.")
                }
            } else {
                List(historyStore.summaries) { summary in
                    NavigationLink {
                        WalkDetailView(walkID: summary.id)
                    } label: {
                        WalkHistoryRow(
                            summary: summary,
                            configuration: displayPreferences.configuration
                        )
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            walkPendingDeletion = summary
                        }
                    }
                    .accessibilityIdentifier("history.walk.\(summary.id.uuidString)")
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("History")
        .task(id: sessionStore.completedSummary?.id) {
            historyStore.load()
        }
        .overlay(alignment: .bottom) {
            if let message = historyStore.errorMessage {
                Text(message)
                    .font(.footnote)
                    .padding(10)
                    .background(.regularMaterial, in: .capsule)
                    .padding()
            }
        }
        .confirmationDialog(
            "Delete this walk permanently?",
            isPresented: Binding(
                get: { walkPendingDeletion != nil },
                set: { if !$0 { walkPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Walk", role: .destructive) {
                if let id = walkPendingDeletion?.id {
                    historyStore.delete(id: id)
                }
                walkPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                walkPendingDeletion = nil
            }
        } message: {
            if walkPendingDeletion?.origin == .appleHealth {
                Text("The papaSteps copy and its stored route points will be removed. The original workout remains in Apple Health.")
            } else {
                Text("Its summary and every stored route point will be removed. Any workout already exported to Apple Health remains there.")
            }
        }
    }
}

private struct WalkHistoryRow: View {
    let summary: WalkSummary
    let configuration: WalkDisplayConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(summary.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.headline)
                Spacer()
                if summary.origin == .appleHealth {
                    Label("Health", systemImage: WalkSymbol.health)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.signalHealth)
                }
                routeQualityLabel
            }

            HStack(spacing: 16) {
                Label(
                    WalkMetricFormatting.distance(
                        summary.displayDistance,
                        configuration: configuration
                    ),
                    systemImage: WalkSymbol.distance
                )
                Label(summary.displaySteps.map(String.init) ?? "—", systemImage: WalkSymbol.steps)
                Label(
                    WalkMetricFormatting.duration(summary.movingDuration),
                    systemImage: WalkSymbol.movingTime
                )
            }
            .font(.subheadline)
            .foregroundStyle(Color.textSecondary)
        }
        .padding(.vertical, 4)
    }

    private var routeQualityLabel: some View {
        Text(summary.routeQuality.displayName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(summary.routeQuality.signalColor)
    }
}

struct WalkDetailView: View {
    @Environment(WalkHistoryStore.self) private var historyStore
    @Environment(WalkHealthStore.self) private var healthStore
    @State private var detail: WalkDetail?

    let walkID: UUID

    var body: some View {
        Group {
            if let loadedDetail = detail {
                WalkDetailContent(
                    detail: loadedDetail,
                    refreshHealth: {
                        Task {
                            if let updated = await healthStore.enrichWalk(id: walkID) {
                                detail = updated
                                historyStore.load()
                            }
                        }
                    }
                )
            } else if historyStore.errorMessage != nil {
                ContentUnavailableView(
                    "Walk Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(historyStore.errorMessage ?? "This walk could not be loaded.")
                )
            } else {
                ProgressView("Loading walk…")
            }
        }
        .navigationTitle("Walk Detail")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            detail = historyStore.detail(id: walkID)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    HealthSettingsView()
                } label: {
                    Label("Apple Health", systemImage: WalkSymbol.healthDetail)
                }
            }
        }
    }
}

struct WalkDetailContent: View {
    @Environment(WalkHealthStore.self) private var healthStore
    @Environment(WalkDisplayPreferences.self) private var displayPreferences
    let detail: WalkDetail
    let refreshHealth: (() -> Void)?

    init(detail: WalkDetail, refreshHealth: (() -> Void)? = nil) {
        self.detail = detail
        self.refreshHealth = refreshHealth
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WalkRouteMap(
                    segments: detail.routeSegments,
                    currentCoordinate: detail.routeCoordinates.last,
                    showsEndpointMarkers: true
                )

                WalkMetricGrid {
                    WalkMetricCard(
                        title: "Distance",
                        value: WalkMetricFormatting.distance(
                            detail.summary.displayDistance,
                            configuration: displayPreferences.configuration
                        ),
                        detail: distanceSourceLabel,
                        systemImage: WalkSymbol.distance
                    )
                    WalkMetricCard(
                        title: "Steps",
                        value: detail.summary.displaySteps.map(String.init) ?? "—",
                        detail: stepSourceLabel,
                        systemImage: WalkSymbol.steps
                    )
                    WalkMetricCard(
                        title: "Moving time",
                        value: WalkMetricFormatting.duration(detail.summary.movingDuration),
                        detail: "Excludes pauses",
                        systemImage: WalkSymbol.movingTime
                    )
                    WalkMetricCard(
                        title: displayPreferences.speedDisplay == .pace ? "Average pace" : "Average speed",
                        value: WalkMetricFormatting.speed(
                            detail.summary.averageSpeed,
                            configuration: displayPreferences.configuration
                        ),
                        detail: "Distance ÷ moving time",
                        systemImage: WalkSymbol.speed
                    )
                    WalkMetricCard(
                        title: "Elevation gain",
                        value: WalkMetricFormatting.altitude(
                            detail.elevationGain,
                            configuration: displayPreferences.configuration
                        ),
                        detail: detail.altitudeQuality.displayName,
                        systemImage: WalkSymbol.elevationGain
                    )
                    WalkMetricCard(
                        title: "Elapsed time",
                        value: WalkMetricFormatting.duration(detail.summary.elapsedDuration),
                        detail: "Paused \(WalkMetricFormatting.duration(detail.pausedDuration))",
                        systemImage: WalkSymbol.elapsedTime
                    )
                }

                HealthInsightSection(
                    detail: detail,
                    accessState: healthStore.accessState,
                    isRefreshing: healthStore.isWorking,
                    refresh: { refreshHealth?() }
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("Recording details")
                        .font(.sectionHeader)
                    LabeledContent("Started") {
                        Text(detail.summary.startDate.formatted(date: .complete, time: .shortened))
                    }
                    LabeledContent("Source") {
                        Text(detail.origin == .appleHealth
                            ? (detail.healthSourceName ?? "Apple Health")
                            : "papaSteps")
                    }
                    LabeledContent("Time zone") {
                        Text(detail.summary.timeZoneIdentifier)
                    }
                    LabeledContent("Route quality") {
                        Text(detail.summary.routeQuality.displayName)
                            .foregroundStyle(detail.summary.routeQuality.signalColor)
                    }
                    LabeledContent("GPS points") {
                        Text("\(detail.acceptedLocationCount) accepted · \(detail.rejectedLocationCount) rejected")
                    }
                    if let reason = detail.summary.routeQualityReason {
                        Label(reason.explanation, systemImage: WalkSymbol.information)
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .padding(Spacing.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding()
        }
        .accessibilityIdentifier("history.walk.detail")
    }

    private var distanceSourceLabel: String {
        detail.summary.distanceSource.displayName
    }

    private var stepSourceLabel: String {
        detail.summary.stepSource.displayName
    }
}
