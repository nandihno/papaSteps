import SwiftUI

struct HistoryView: View {
    @Environment(WalkHistoryStore.self) private var historyStore
    @Environment(WalkSessionStore.self) private var sessionStore
    @Environment(WalkDisplayPreferences.self) private var displayPreferences
    @Environment(AppTabRouter.self) private var tabRouter
    @State private var walkPendingDeletion: WalkSummary?
    /// Explicit expand/collapse choices, keyed by `WalkWeek.id`. A week with no
    /// entry here falls back to its default (only the most recent week starts
    /// expanded) so newly recorded walks don't reset choices made on older weeks.
    @State private var weekExpansionOverrides: [String: Bool] = [:]

    private var weeks: [WalkHistoryWeek] {
        WalkHistoryWeek.group(historyStore.summaries)
    }

    var body: some View {
        Group {
            if historyStore.summaries.isEmpty {
                EmptyStateView(
                    title: "No walks yet",
                    message: "Finish a walk and its summary, route, and metrics are saved here on this iPhone.",
                    systemImage: WalkSymbol.history
                ) {
                    Button("Start Walk") {
                        tabRouter.select(.walk)
                    }
                    .buttonStyle(.primaryWalk)
                    .accessibilityIdentifier("history.empty.start")
                }
            } else {
                List {
                    ForEach(Array(weeks.enumerated()), id: \.element.id) { index, week in
                        Section {
                            if isExpanded(week, isMostRecent: index == 0) {
                                ForEach(week.walks) { summary in
                                    walkRow(summary)
                                }
                            }
                        } header: {
                            weekHeader(week, isMostRecent: index == 0)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollEdgeEffectStyle(.soft, for: .top)
            }
        }
        .navigationTitle("History")
        .task(id: sessionStore.completedSummary?.id) {
            historyStore.load()
        }
        .overlay(alignment: .bottom) {
            if let message = historyStore.errorMessage {
                Label(message, systemImage: WalkSymbol.alert)
                    .font(.footnote)
                    .foregroundStyle(Color.signalCaution)
                    .padding(Spacing.small)
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

    private func walkRow(_ summary: WalkSummary) -> some View {
        NavigationLink {
            WalkDetailView(walkID: summary.id)
        } label: {
            WalkHistoryRow(
                summary: summary,
                configuration: displayPreferences.configuration,
                routePreview: historyStore.routePreviews[summary.id] ?? []
            )
        }
        .task { historyStore.loadRoutePreview(id: summary.id) }
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) {
                walkPendingDeletion = summary
            }
        }
        .accessibilityIdentifier("history.walk.\(summary.id.uuidString)")
    }

    /// A week with no explicit override defaults to expanded only if it's the
    /// most recent one, so the list opens compact instead of one long scroll.
    private func isExpanded(_ week: WalkHistoryWeek, isMostRecent: Bool) -> Bool {
        weekExpansionOverrides[week.id] ?? isMostRecent
    }

    private func weekHeader(_ week: WalkHistoryWeek, isMostRecent: Bool) -> some View {
        let expanded = isExpanded(week, isMostRecent: isMostRecent)
        let title = week.title()
        return Button {
            withAnimation(.snappy) {
                weekExpansionOverrides[week.id] = !expanded
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Image(systemName: WalkSymbol.disclosure)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(
                    WalkMetricFormatting.distance(
                        week.totalDistance,
                        configuration: displayPreferences.configuration
                    )
                )
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .textCase(nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(
            "\(week.walks.count) walk\(week.walks.count == 1 ? "" : "s"), "
                + "\(WalkMetricFormatting.distance(week.totalDistance, configuration: displayPreferences.configuration)) in total, "
                + (expanded ? "expanded" : "collapsed")
        )
        .accessibilityAddTraits(.isButton)
    }
}

/// Walks bucketed by the Monday-to-Sunday ISO week they started in, using each
/// walk's own stored time zone so a trip does not shuffle rows between weeks.
struct WalkHistoryWeek: Identifiable {
    let id: String
    let week: WalkWeek
    let walks: [WalkSummary]

    var totalDistance: Double {
        walks.reduce(into: 0) { $0 += $1.displayDistance ?? 0 }
    }

    func title(now: Date = .now) -> String {
        let currentWeek = WalkWeek.current(at: now, timeZone: .current)
        if week == currentWeek { return "This week" }
        if week == currentWeek.previous(in: .current) { return "Last week" }
        return Self.dateRangeTitle(for: week, now: now)
    }

    static func group(_ summaries: [WalkSummary]) -> [WalkHistoryWeek] {
        var order: [String] = []
        var walksByKey: [String: [WalkSummary]] = [:]
        var weekByKey: [String: WalkWeek] = [:]

        for summary in summaries {
            let week = WalkWeek.from(summary.startDate, timeZoneIdentifier: summary.timeZoneIdentifier)
            let key = week.id

            if walksByKey[key] == nil {
                order.append(key)
                weekByKey[key] = week
            }
            walksByKey[key, default: []].append(summary)
        }

        return order.map { key in
            WalkHistoryWeek(
                id: key,
                week: weekByKey[key] ?? .current(at: .now, timeZone: .current),
                walks: walksByKey[key] ?? []
            )
        }
    }

    private static func dateRangeTitle(for week: WalkWeek, now: Date) -> String {
        let monday = week.date(in: .current)
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let sunday = calendar.date(byAdding: .day, value: 6, to: monday) ?? monday

        let showsYear = calendar.component(.year, from: sunday) != calendar.component(.year, from: now)
        let format: Date.FormatStyle = showsYear
            ? .dateTime.month(.abbreviated).day().year()
            : .dateTime.month(.abbreviated).day()
        return "\(monday.formatted(format)) – \(sunday.formatted(format))"
    }
}

private struct WalkHistoryRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let summary: WalkSummary
    let configuration: WalkDisplayConfiguration
    let routePreview: [WalkCoordinate]

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.small) {
            if !dynamicTypeSize.isAccessibilitySize {
                RouteThumbnail(coordinates: routePreview)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(summary.startDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.headline)
                    Spacer(minLength: Spacing.xs)
                    if summary.origin == .appleHealth {
                        Label("Health", systemImage: WalkSymbol.health)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.signalHealth)
                    }
                }

                metrics

                Text(summary.routeQuality.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(summary.routeQuality.signalColor)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 2)
                    .background(summary.routeQuality.signalColor.opacity(0.12), in: .capsule)
            }
        }
        .padding(.vertical, Spacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(summary.startDate.formatted(date: .abbreviated, time: .shortened))
        .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder
    private var metrics: some View {
        let distance = WalkMetricFormatting.distance(
            summary.displayDistance,
            configuration: configuration
        )
        let steps = summary.displaySteps.map(String.init) ?? "—"
        let moving = WalkMetricFormatting.duration(summary.movingDuration)

        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Label(distance, systemImage: WalkSymbol.distance)
                Label("\(steps) steps", systemImage: WalkSymbol.steps)
                Label(moving, systemImage: WalkSymbol.movingTime)
            }
            .font(.subheadline)
            .foregroundStyle(Color.textSecondary)
        } else {
            // Three icon-and-value pairs do not fit beside the thumbnail, and
            // truncating a distance to "0.8…" is worse than dropping the icons.
            Text("\(distance) · \(steps) steps · \(moving)")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var accessibilityValue: String {
        var parts = [
            WalkMetricFormatting.distance(summary.displayDistance, configuration: configuration),
            "\(summary.displaySteps.map(String.init) ?? "no") steps",
            "\(WalkMetricFormatting.duration(summary.movingDuration)) moving",
            summary.routeQuality.displayName
        ]
        if summary.origin == .appleHealth {
            parts.append("Imported from Apple Health")
        }
        return parts.joined(separator: ", ")
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
                EmptyStateView(
                    title: "Walk unavailable",
                    message: historyStore.errorMessage ?? "This walk could not be loaded.",
                    systemImage: WalkSymbol.alert
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
            VStack(alignment: .leading, spacing: Spacing.large) {
                WalkRouteMap(
                    segments: detail.routeSegments,
                    currentCoordinate: detail.routeCoordinates.last,
                    showsEndpointMarkers: true
                )

                HeroMetric(
                    title: "Distance",
                    value: WalkMetricFormatting.distance(
                        detail.summary.displayDistance,
                        configuration: displayPreferences.configuration
                    ),
                    detail: detail.summary.distanceSource.displayName
                )

                WalkMetricGrid {
                    MetricTile(
                        title: "Steps",
                        value: detail.summary.displaySteps.map(String.init) ?? "—",
                        detail: detail.summary.stepSource.displayName,
                        systemImage: WalkSymbol.steps
                    )
                    MetricTile(
                        title: "Moving time",
                        value: WalkMetricFormatting.duration(detail.summary.movingDuration),
                        detail: "Excludes pauses",
                        systemImage: WalkSymbol.movingTime
                    )
                    MetricTile(
                        title: displayPreferences.speedDisplay == .pace
                            ? "Average pace"
                            : "Average speed",
                        value: WalkMetricFormatting.speed(
                            detail.summary.averageSpeed,
                            configuration: displayPreferences.configuration
                        ),
                        detail: "Distance ÷ moving time",
                        systemImage: WalkSymbol.speed
                    )
                    MetricTile(
                        title: "Elevation gain",
                        value: WalkMetricFormatting.altitude(
                            detail.elevationGain,
                            configuration: displayPreferences.configuration
                        ),
                        detail: detail.altitudeQuality.displayName,
                        systemImage: WalkSymbol.elevationGain
                    )
                    MetricTile(
                        title: "Elapsed time",
                        value: WalkMetricFormatting.duration(detail.summary.elapsedDuration),
                        detail: "Paused \(WalkMetricFormatting.duration(detail.pausedDuration))",
                        systemImage: WalkSymbol.elapsedTime
                    )
                    MetricTile(
                        title: "Route quality",
                        value: detail.summary.routeQuality.displayName,
                        detail: "\(detail.acceptedLocationCount) points accepted",
                        systemImage: WalkSymbol.routeQuality,
                        accentsValue: detail.summary.routeQuality == .good
                    )
                }

                HealthInsightSection(
                    detail: detail,
                    accessState: healthStore.accessState,
                    isRefreshing: healthStore.isWorking,
                    refresh: { refreshHealth?() }
                )

                recordingDetails
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(Spacing.screenMargin)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .accessibilityIdentifier("history.walk.detail")
    }

    private var recordingDetails: some View {
        SectionCard(title: "Recording details", systemImage: WalkSymbol.information) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                LabeledContent("Started") {
                    Text(detail.summary.startDate.formatted(date: .complete, time: .shortened))
                        .multilineTextAlignment(.trailing)
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
                        .multilineTextAlignment(.trailing)
                }
                if let reason = detail.summary.routeQualityReason {
                    Label(reason.explanation, systemImage: WalkSymbol.information)
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.top, Spacing.xxs)
                }
            }
            .font(.subheadline)
        }
    }
}
