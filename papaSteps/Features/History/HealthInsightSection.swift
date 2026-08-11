import SwiftUI

struct HealthInsightSection: View {
    let detail: WalkDetail
    let accessState: HealthAccessState
    let isRefreshing: Bool
    let refresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Apple Health", systemImage: WalkSymbol.healthDetail)
                    .font(.headline)
                    .foregroundStyle(Color.signalHealth)
                    .accessibilityIdentifier("health.insights")
                Spacer()
                enrichmentStatus
            }

            WalkMetricGrid {
                WalkMetricCard(
                    title: "Average heart rate",
                    value: heartRateValue,
                    detail: heartRateDetail,
                    systemImage: WalkSymbol.health
                )
                .accessibilityIdentifier("health.heartRate")

                WalkMetricCard(
                    title: "Walking asymmetry",
                    value: asymmetryValue,
                    detail: asymmetryDetail,
                    systemImage: WalkSymbol.motion
                )
                .accessibilityIdentifier("health.asymmetry")
            }

            if accessState == .requested {
                Button {
                    refresh()
                } label: {
                    Label("Refresh Health Insights", systemImage: WalkSymbol.refresh)
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshing)
                .accessibilityIdentifier("health.refresh")
            } else if accessState == .notRequested {
                Text("Connect Apple Health from the Walk screen settings to add optional post-walk insights.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if detail.healthWorkoutExportStatus != .disabled {
                Label(workoutStatusText, systemImage: detail.healthWorkoutExportStatus.symbolName)
                    .font(.footnote)
                    .foregroundStyle(detail.healthWorkoutExportStatus.signalColor)
            }
        }
        .padding(Spacing.cardPadding)
        .tintedSurface(.signalHealth)
    }

    private var enrichmentStatus: some View {
        Text(enrichmentStatusText)
            .font(.caption.weight(.semibold))
            .foregroundStyle(
                isRefreshing ? Color.signalNeutral : detail.healthEnrichmentStatus.signalColor
            )
    }

    private var enrichmentStatusText: String {
        if isRefreshing {
            return HealthEnrichmentStatus.pending.displayName
        }
        return detail.healthEnrichmentStatus.displayName
    }

    private var heartRateValue: String {
        detail.averageHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "Not available"
    }

    private var heartRateDetail: String {
        guard detail.averageHeartRate != nil else { return unavailableDetail }
        return coverageDetail(
            sampleCount: detail.heartRateSampleCount,
            coveredDuration: detail.heartRateCoveredDuration,
            sourceName: detail.heartRateSourceName
        )
    }

    private var asymmetryValue: String {
        guard let value = detail.walkingAsymmetryAverage else { return "Not available" }
        return value.formatted(.percent.precision(.fractionLength(1)))
    }

    private var asymmetryDetail: String {
        guard detail.walkingAsymmetryAverage != nil else { return unavailableDetail }
        return coverageDetail(
            sampleCount: detail.walkingAsymmetrySampleCount,
            coveredDuration: detail.walkingAsymmetryCoveredDuration,
            sourceName: detail.walkingAsymmetrySourceName
        )
    }

    private var unavailableDetail: String {
        switch detail.healthEnrichmentStatus {
        case .pending: "Checking Health…"
        case .completed: "No matching samples"
        case .failed: "Refresh to try again"
        case .unavailable: "Health unavailable"
        case .notRequested: "Optional insight"
        }
    }

    private func coverageDetail(
        sampleCount: Int,
        coveredDuration: TimeInterval?,
        sourceName: String?
    ) -> String {
        var parts = ["\(sampleCount) sample\(sampleCount == 1 ? "" : "s")"]
        if let coveredDuration, coveredDuration > 0 {
            parts.append("\(Int(coveredDuration / 60)) min coverage")
        }
        if let sourceName { parts.append(sourceName) }
        return parts.joined(separator: " · ")
    }

    private var workoutStatusText: String {
        if detail.healthWorkoutExportStatus == .failed,
           let error = detail.healthWorkoutExportError {
            return error
        }
        return detail.healthWorkoutExportStatus.displayName
    }
}
