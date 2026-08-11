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
                    Label("No Eligible Walks Yet", systemImage: "chart.line.uptrend.xyaxis")
                } description: {
                    Text("Progress includes completed walks of at least 5 minutes and 250 m with a usable route. Your recording history remains unchanged.")
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
    let snapshot: WalkAnalyticsSnapshot
    let configuration: WalkDisplayConfiguration

    private var chartWeeks: [WeeklyWalkAggregate] {
        Array(snapshot.weeklyAggregates.reversed().prefix(8))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                currentWeekSection
                weeklyDistanceChart
                comparisonsSection
                goalsSection
                personalBestsSection
                achievementsSection
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding()
        }
    }

    private var currentWeekSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("This week")
                        .font(.title2.bold())
                    Text("ISO week \(snapshot.currentWeek.week.number) · Rules v\(snapshot.rulesVersion)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label(
                    "\(snapshot.currentStreak)-week streak",
                    systemImage: "flame.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(snapshot.currentStreak > 0 ? .orange : .secondary)
            }

            WalkMetricGrid {
                metricCard(.distance, value: snapshot.currentWeek.totals.distanceMeters)
                metricCard(.duration, value: snapshot.currentWeek.totals.movingDuration)
                metricCard(.steps, value: Double(snapshot.currentWeek.totals.steps))
                metricCard(.elevation, value: snapshot.currentWeek.totals.elevationGain)
            }
        }
    }

    private var weeklyDistanceChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly distance")
                .font(.headline)

            Chart(chartWeeks) { aggregate in
                BarMark(
                    x: .value("Week", weekLabel(aggregate.week)),
                    y: .value("Distance", aggregate.totals.distanceMeters)
                )
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel(weekAccessibilityLabel(aggregate.week))
                .accessibilityValue(
                    WalkMetricFormatting.distance(
                        aggregate.totals.distanceMeters,
                        configuration: configuration
                    )
                )
            }
            .chartYScale(domain: 0...max(1, chartWeeks.map(\.totals.distanceMeters).max() ?? 0))
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartLegend(.hidden)
            .frame(minHeight: 200, maxHeight: 340)
            .accessibilityLabel("Weekly distance chart")
            .accessibilityIdentifier("progress.weeklyDistance.chart")
        }
        .padding()
        .background(.quaternary, in: .rect(cornerRadius: 16))
    }

    private var comparisonsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly comparisons")
                .font(.headline)
            ForEach(WalkProgressMetric.allCases) { metric in
                VStack(alignment: .leading, spacing: 8) {
                    Text(metric.title)
                        .font(.subheadline.weight(.semibold))
                    ForEach(snapshot.comparisons.filter { $0.metric == metric }) { comparison in
                        LabeledContent(comparison.kind.title) {
                            Text(comparisonText(comparison))
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
        }
        .padding()
        .background(.quaternary, in: .rect(cornerRadius: 16))
    }

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly goals")
                .font(.headline)
            ForEach(snapshot.goals) { goal in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(goal.metric.title)
                        Spacer()
                        Text("\(format(goal.current, metric: goal.metric)) / \(format(goal.target, metric: goal.metric))")
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: goal.fractionComplete)
                        .tint(goal.isCompleted ? .green : .accentColor)
                        .accessibilityLabel("\(goal.metric.title) weekly goal")
                        .accessibilityValue("\(Int((goal.fractionComplete * 100).rounded())) percent complete")
                }
            }
        }
        .padding()
        .background(.quaternary, in: .rect(cornerRadius: 16))
    }

    private var personalBestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Personal bests")
                .font(.headline)
            ForEach(snapshot.personalBests) { best in
                LabeledContent(best.metric.title) {
                    Text(format(best.metric.value(in: totals(for: best.walk)), metric: best.metric))
                }
            }
        }
        .padding()
        .background(.quaternary, in: .rect(cornerRadius: 16))
    }

    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Achievements")
                .font(.headline)
            if snapshot.badges.isEmpty {
                Text("Complete an eligible walk to begin earning achievements.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.badges) { badge in
                    Label {
                        VStack(alignment: .leading) {
                            Text(badge.title)
                            Text(badge.detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "medal.fill")
                            .foregroundStyle(.yellow)
                    }
                }
            }
            if snapshot.ineligibleWalkCount > 0 {
                Text("\(snapshot.ineligibleWalkCount) saved walk\(snapshot.ineligibleWalkCount == 1 ? " is" : "s are") not included under the current eligibility rules.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.quaternary, in: .rect(cornerRadius: 16))
    }

    private func metricCard(_ metric: WalkProgressMetric, value: Double) -> some View {
        WalkMetricCard(
            title: metric.title,
            value: format(value, metric: metric),
            detail: "\(snapshot.currentWeek.walkCount) eligible walk\(snapshot.currentWeek.walkCount == 1 ? "" : "s")",
            systemImage: icon(for: metric)
        )
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
        case .distance: "ruler"
        case .duration: "timer"
        case .steps: "shoeprints.fill"
        case .elevation: "arrow.up.right"
        }
    }

    private func weekLabel(_ week: WalkWeek) -> String {
        week.date(in: .current).formatted(.dateTime.month(.abbreviated).day())
    }

    private func weekAccessibilityLabel(_ week: WalkWeek) -> String {
        let date = week.date(in: .current)
        return "Week of \(date.formatted(date: .abbreviated, time: .omitted))"
    }

    private func comparisonText(_ comparison: ProgressComparison) -> String {
        guard let reference = comparison.referenceValue,
              let percentage = comparison.percentageChange else {
            return "Not enough history"
        }
        let direction = percentage > 0 ? "up" : percentage < 0 ? "down" : "even"
        return "\(abs(percentage).formatted(.percent.precision(.fractionLength(0)))) \(direction) · \(format(reference, metric: comparison.metric))"
    }
}
