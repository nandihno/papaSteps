import SwiftUI

struct HealthInsightSection: View {
    let detail: WalkDetail
    let accessState: HealthAccessState
    let isRefreshing: Bool
    let refresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Apple Health", systemImage: "heart.text.square.fill")
                    .font(.headline)
                    .foregroundStyle(.pink)
                    .accessibilityIdentifier("health.insights")
                Spacer()
                enrichmentStatus
            }

            WalkMetricGrid {
                WalkMetricCard(
                    title: "Average heart rate",
                    value: heartRateValue,
                    detail: heartRateDetail,
                    systemImage: "heart.fill"
                )
                .accessibilityIdentifier("health.heartRate")

                WalkMetricCard(
                    title: "Walking asymmetry",
                    value: asymmetryValue,
                    detail: asymmetryDetail,
                    systemImage: "figure.walk.motion"
                )
                .accessibilityIdentifier("health.asymmetry")
            }

            if accessState == .requested {
                Button {
                    refresh()
                } label: {
                    Label("Refresh Health Insights", systemImage: "arrow.clockwise")
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
                Label(workoutStatusText, systemImage: workoutStatusImage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.pink.opacity(0.08), in: .rect(cornerRadius: 16))
    }

    private var enrichmentStatus: some View {
        Text(enrichmentStatusText)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var enrichmentStatusText: String {
        if isRefreshing || detail.healthEnrichmentStatus == .pending {
            return "Checking…"
        }
        return switch detail.healthEnrichmentStatus {
        case .notRequested: "Optional"
        case .pending: "Checking…"
        case .completed: "Refreshed"
        case .unavailable: "Unavailable"
        case .failed: "Needs retry"
        }
    }

    private var heartRateValue: String {
        detail.averageHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "Not Available"
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
        guard let value = detail.walkingAsymmetryAverage else { return "Not Available" }
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
        switch detail.healthWorkoutExportStatus {
        case .disabled: "Workout export is off"
        case .pending: "Saving workout to Apple Health…"
        case .completed: "Workout saved to Apple Health"
        case .failed: detail.healthWorkoutExportError ?? "Workout export needs a retry"
        }
    }

    private var workoutStatusImage: String {
        switch detail.healthWorkoutExportStatus {
        case .disabled: "heart.slash"
        case .pending: "arrow.trianglehead.2.clockwise"
        case .completed: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        }
    }
}
