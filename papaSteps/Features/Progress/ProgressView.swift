import Charts
import SwiftUI

struct ProgressDashboardView: View {
    @Environment(ProgressStore.self) private var progressStore
    @Environment(WalkDisplayPreferences.self) private var displayPreferences
    @Environment(WalkSessionStore.self) private var sessionStore

    var body: some View {
        Group {
            if let errorMessage = progressStore.errorMessage {
                ContentUnavailableView(
                    "Progress Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if progressStore.snapshot.eligibleWalkCount == 0 {
                ContentUnavailableView {
                    Label("No Eligible Walks Yet", systemImage: WalkSymbol.progress)
                } description: {
                    Text("Progress includes every completed walk with a usable route, no matter how short. Your recording history remains unchanged.")
                }
            } else {
                ProgressContent(
                    snapshot: progressStore.snapshot,
                    configuration: displayPreferences.configuration
                )
            }
        }
        .navigationTitle("Progress")
        .onAppear { progressStore.refresh() }
        .task(id: sessionStore.completedSummary?.id) { progressStore.refresh() }
        .accessibilityIdentifier("progress.dashboard")
    }
}

private struct ProgressContent: View {
    private static let visibleWeekCount = 8
    private static let chartWeekLimit = 52

    let snapshot: WalkAnalyticsSnapshot
    let configuration: WalkDisplayConfiguration
    let chartWeeks: [WeeklyWalkAggregate]

    /// The leading edge of the chart's initial scroll window, computed up
    /// front so the chart opens already showing the most recent weeks instead
    /// of flashing the oldest ones before jumping.
    @State private var chartScrollPosition: String

    init(snapshot: WalkAnalyticsSnapshot, configuration: WalkDisplayConfiguration) {
        self.snapshot = snapshot
        self.configuration = configuration
        let weeks = Array(snapshot.weeklyAggregates.prefix(Self.chartWeekLimit).reversed())
        chartWeeks = weeks
        let startIndex = max(0, weeks.count - Self.visibleWeekCount)
        let initialWeek = weeks.isEmpty ? snapshot.currentWeek.week : weeks[startIndex].week
        _chartScrollPosition = State(initialValue: Self.weekLabel(initialWeek))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.large) {
                currentWeekSection
                weeklyDistanceChart
                comparisonsSection
                goalsSection
                personalBestsSection
                achievementsSection
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(Spacing.screenMargin)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    // MARK: This week

    private var currentWeekSection: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("This week")
                        .font(.sectionHeader)
                    Text(currentWeekSubtitle)
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                streakChip
            }

            HeroMetric(
                title: "Distance",
                value: format(snapshot.currentWeek.totals.distanceMeters, metric: .distance),
                detail: weekWalkCountDetail
            )

            WalkMetricGrid {
                metricTile(.duration, value: snapshot.currentWeek.totals.movingDuration)
                metricTile(.steps, value: Double(snapshot.currentWeek.totals.steps))
                metricTile(.elevation, value: snapshot.currentWeek.totals.elevationGain)
            }
        }
    }

    private var streakChip: some View {
        Label("\(snapshot.currentStreak)-week streak", systemImage: WalkSymbol.streak)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(snapshot.currentStreak > 0 ? Color.signalCaution : Color.textSecondary)
            .padding(.horizontal, Spacing.small)
            .padding(.vertical, Spacing.xs)
            .background(
                (snapshot.currentStreak > 0 ? Color.signalCaution : Color.textSecondary).opacity(0.12),
                in: .capsule
            )
    }

    // MARK: Weekly distance chart

    private var weeklyDistanceChart: some View {
        SectionCard(title: "Weekly distance", systemImage: WalkSymbol.distance) {
            Chart(chartWeeks) { aggregate in
                BarMark(
                    x: .value("Week", Self.weekLabel(aggregate.week)),
                    y: .value("Distance", chartDistanceValue(aggregate.totals.distanceMeters))
                )
                .cornerRadius(6)
                .foregroundStyle(
                    Color.brandGreen.opacity(isCurrentWeek(aggregate.week) ? 1 : 0.45)
                )
                .accessibilityLabel(weekAccessibilityLabel(aggregate.week))
                .accessibilityValue(
                    WalkMetricFormatting.distance(
                        aggregate.totals.distanceMeters,
                        configuration: configuration
                    )
                )
            }
            .chartYScale(
                domain: 0...max(1, chartWeeks.map { chartDistanceValue($0.totals.distanceMeters) }.max() ?? 0)
            )
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let distance = value.as(Double.self) {
                            Text("\(Int(distance.rounded())) \(chartDistanceUnitSymbol)")
                        }
                    }
                }
            }
            .chartLegend(.hidden)
            .chartPlotStyle { plotArea in
                plotArea.background(Color.surfaceSunken, in: .rect(cornerRadius: Radius.control))
            }
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: Self.visibleWeekCount)
            .chartScrollPosition(x: $chartScrollPosition)
            .frame(minHeight: 200, maxHeight: 280)
            .accessibilityLabel("Weekly distance chart")
            .accessibilityIdentifier("progress.weeklyDistance.chart")
        }
    }

    // MARK: Comparisons

    private var comparisonsSection: some View {
        SectionCard(title: "Weekly comparisons", systemImage: WalkSymbol.progress) {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                ForEach(WalkProgressMetric.allCases) { metric in
                    let metricComparisons = snapshot.comparisons.filter { $0.metric == metric }
                    if !metricComparisons.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Label(metric.title, systemImage: icon(for: metric))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                            ForEach(metricComparisons) { comparison in
                                DeltaBadge(comparison: comparison)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Goals

    private var goalsSection: some View {
        SectionCard(title: "Weekly goals", systemImage: WalkSymbol.goal) {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                ForEach(snapshot.goals) { goal in
                    GoalRingRow(
                        goal: goal,
                        currentText: format(goal.current, metric: goal.metric),
                        targetText: format(goal.target, metric: goal.metric)
                    )
                }
            }
        }
    }

    // MARK: Personal bests

    private var personalBestsSection: some View {
        SectionCard(title: "Personal bests", systemImage: WalkSymbol.badge) {
            VStack(alignment: .leading, spacing: Spacing.small) {
                ForEach(snapshot.personalBests) { best in
                    HStack {
                        Label(best.metric.title, systemImage: icon(for: best.metric))
                            .font(.subheadline)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text(format(best.metric.value(in: totals(for: best.walk)), metric: best.metric))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.signalAward)
                    }
                }
            }
        }
    }

    // MARK: Achievements

    private var achievementsSection: some View {
        SectionCard(title: "Achievements", systemImage: WalkSymbol.badge) {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                AchievementGrid(earnedBadges: Set(snapshot.badges))

                if snapshot.ineligibleWalkCount > 0 {
                    Text("\(snapshot.ineligibleWalkCount) saved walk\(snapshot.ineligibleWalkCount == 1 ? " is" : "s are") not included under the current eligibility rules.")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                }
                Text("Eligibility rules version \(snapshot.rulesVersion)")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    // MARK: Helpers

    private func metricTile(_ metric: WalkProgressMetric, value: Double) -> some View {
        MetricTile(
            title: metric.title,
            value: format(value, metric: metric),
            detail: weekWalkCountDetail,
            systemImage: icon(for: metric)
        )
    }

    private var weekWalkCountDetail: String {
        "\(snapshot.currentWeek.walkCount) eligible walk\(snapshot.currentWeek.walkCount == 1 ? "" : "s")"
    }

    private func format(_ value: Double, metric: WalkProgressMetric) -> String {
        switch metric {
        case .distance:
            WalkMetricFormatting.distance(value, configuration: configuration)
        case .duration:
            WalkMetricFormatting.duration(value)
        case .steps:
            Int(value.rounded()).formatted()
        case .elevation:
            WalkMetricFormatting.altitude(value, configuration: configuration)
        }
    }

    private func totals(for walk: WalkSummary) -> WalkTotals {
        WalkTotals(
            distanceMeters: walk.displayDistance ?? 0,
            movingDuration: walk.movingDuration,
            steps: walk.displaySteps ?? 0,
            elevationGain: walk.elevationGain ?? 0
        )
    }

    private func icon(for metric: WalkProgressMetric) -> String {
        switch metric {
        case .distance: WalkSymbol.distance
        case .duration: WalkSymbol.movingTime
        case .steps: WalkSymbol.steps
        case .elevation: WalkSymbol.elevationGain
        }
    }

    private var currentWeekSubtitle: String {
        let start = snapshot.currentWeek.week.date(in: .current)
        return "Week of \(start.formatted(.dateTime.day().month(.wide)))"
    }

    private static func weekLabel(_ week: WalkWeek) -> String {
        week.date(in: .current).formatted(.dateTime.month(.abbreviated).day())
    }

    private func weekAccessibilityLabel(_ week: WalkWeek) -> String {
        let date = week.date(in: .current)
        return "Week of \(date.formatted(date: .abbreviated, time: .omitted))"
    }

    private func isCurrentWeek(_ week: WalkWeek) -> Bool {
        week == snapshot.currentWeek.week
    }

    private func chartDistanceValue(_ meters: Double) -> Double {
        let unit: UnitLength = configuration.distanceUnit == .metric ? .kilometers : .miles
        return Measurement(value: meters, unit: UnitLength.meters).converted(to: unit).value
    }

    private var chartDistanceUnitSymbol: String {
        configuration.distanceUnit == .metric ? "km" : "mi"
    }
}

// MARK: - Goal ring

/// A weekly goal shown as a fill ring rather than a linear bar, so "how close
/// am I" reads at a glance the same way the recording ring does on the live
/// walk screen.
private struct GoalRingRow: View {
    let goal: ProgressGoal
    let currentText: String
    let targetText: String

    var body: some View {
        HStack(spacing: Spacing.medium) {
            ZStack {
                Circle()
                    .stroke(Color.strokeHairline, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: goal.fractionComplete)
                    .stroke(
                        goal.isCompleted ? Color.signalGood : Color.brandGreen,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                if goal.isCompleted {
                    Image(systemName: WalkSymbol.good)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.signalGood)
                } else {
                    Text("\(Int((goal.fractionComplete * 100).rounded()))%")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.textPrimary)
                }
            }
            .frame(width: 52, height: 52)
            .animation(.easeInOut(duration: 0.4), value: goal.fractionComplete)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(goal.metric.title)
                    .font(.subheadline.weight(.semibold))
                Text("\(currentText) of \(targetText)")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(goal.metric.title) weekly goal")
        .accessibilityValue(
            goal.isCompleted
                ? "Completed, \(currentText) of \(targetText)"
                : "\(Int((goal.fractionComplete * 100).rounded())) percent complete, \(currentText) of \(targetText)"
        )
    }
}

// MARK: - Achievement grid

/// Every badge, earned or not. Locked badges stay visible and dimmed with
/// their unlock condition — a goal you can see motivates more than one that
/// only appears after you have already reached it.
private struct AchievementGrid: View {
    let earnedBadges: Set<ProgressBadge>

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        LazyVGrid(
            columns: dynamicTypeSize.isAccessibilitySize
                ? [GridItem(.flexible())]
                : [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: Spacing.small
        ) {
            ForEach(ProgressBadge.allCases) { badge in
                let isEarned = earnedBadges.contains(badge)
                VStack(spacing: Spacing.xxs) {
                    Image(systemName: isEarned ? WalkSymbol.badge : WalkSymbol.locked)
                        .font(.title2)
                        .foregroundStyle(isEarned ? Color.signalAward : Color.textTertiary)
                    Text(badge.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isEarned ? Color.textPrimary : Color.textTertiary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    Text(badge.detail)
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.small)
                .opacity(isEarned ? 1 : 0.5)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(badge.title)
                .accessibilityValue(isEarned ? "Earned. \(badge.detail)" : "Locked. \(badge.detail)")
            }
        }
    }
}
