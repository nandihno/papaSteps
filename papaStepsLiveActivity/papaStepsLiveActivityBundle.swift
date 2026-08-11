import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct papaStepsLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        WalkLiveActivityWidget()
    }
}

struct WalkLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WalkActivityAttributes.self) { context in
            WalkLockScreenView(context: context)
                .activityBackgroundTint(.black.opacity(0.08))
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "figure.walk.motion")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    elapsedTime(context: context)
                        .font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.status.title)
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        HStack {
                            metric(
                                context.state.steps.map(String.init) ?? "—",
                                label: "steps"
                            )
                            Spacer()
                            metric(
                                distance(context.state.distanceMeters),
                                label: "distance"
                            )
                            Spacer()
                            metric(
                                duration(context.state.movingDuration),
                                label: "moving"
                            )
                        }
                        WalkActivityActionButtons(
                            walkID: context.attributes.walkID,
                            status: context.state.status
                        )
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.status.systemImage)
                    .foregroundStyle(context.state.status.tint)
            } compactTrailing: {
                elapsedTime(context: context)
                    .frame(width: 46)
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "figure.walk")
                    .foregroundStyle(.blue)
            }
            .keylineTint(.blue)
        }
    }

    private func metric(_ value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func distance(_ meters: Double?) -> String {
        guard let meters else { return "—" }
        if meters >= 1_000 {
            return String(format: "%.2f km", meters / 1_000)
        }
        return "\(Int(meters.rounded())) m"
    }

    private func duration(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct WalkLockScreenView: View {
    let context: ActivityViewContext<WalkActivityAttributes>

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label("papaSteps", systemImage: "figure.walk.motion")
                    .font(.headline)
                    .foregroundStyle(.blue)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(context.state.status.title)
                        .font(.subheadline.bold())
                    elapsedTime
                        .font(.title3.monospacedDigit().bold())
                }
            }

            if context.isStale {
                Label("Metrics will refresh when papaSteps can run", systemImage: "clock.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                metric(context.state.steps.map(String.init) ?? "—", label: "Steps")
                Spacer()
                metric(distanceText, label: "Distance")
                Spacer()
                metric(durationText, label: "Moving")
            }

            WalkActivityActionButtons(
                walkID: context.attributes.walkID,
                status: context.state.status
            )
        }
        .padding()
    }

    private var distanceText: String {
        guard let meters = context.state.distanceMeters else { return "—" }
        if meters >= 1_000 {
            return String(format: "%.2f km", meters / 1_000)
        }
        return "\(Int(meters.rounded())) m"
    }

    private var durationText: String {
        let seconds = max(0, Int(context.state.movingDuration.rounded()))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    @ViewBuilder
    private var elapsedTime: some View {
        if context.state.status == .completed {
            Text(Self.duration(context.state.elapsedDuration))
        } else if context.state.status == .interrupted {
            Text("Open app")
        } else {
            Text(context.attributes.startDate, style: .timer)
        }
    }

    private static func duration(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func metric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

@ViewBuilder
private func elapsedTime(
    context: ActivityViewContext<WalkActivityAttributes>
) -> some View {
    if context.state.status == .completed {
        let seconds = max(0, Int(context.state.elapsedDuration.rounded()))
        Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
    } else if context.state.status == .interrupted {
        Text("Open")
    } else {
        Text(context.attributes.startDate, style: .timer)
    }
}

private struct WalkActivityActionButtons: View {
    let walkID: UUID
    let status: WalkActivityStatus

    var body: some View {
        HStack(spacing: 12) {
            switch status {
            case .active:
                Button(intent: PauseWalkIntent(walkID: walkID)) {
                    Label("Pause", systemImage: "pause.fill")
                }
                .tint(.orange)
                finishButton
            case .paused:
                Button(intent: ResumeWalkIntent(walkID: walkID)) {
                    Label("Resume", systemImage: "play.fill")
                }
                .tint(.green)
                finishButton
            case .finishCandidate:
                Button(intent: KeepWalkingIntent(walkID: walkID)) {
                    Label("Keep Walking", systemImage: "figure.walk")
                }
                .tint(.blue)
                finishButton
            case .finalizing, .completed, .interrupted:
                EmptyView()
            }
        }
        .buttonStyle(.borderedProminent)
        .font(.caption.bold())
    }

    private var finishButton: some View {
        Button(intent: FinishWalkIntent(walkID: walkID)) {
            Label("Finish", systemImage: "stop.fill")
        }
        .tint(.red)
    }
}

private extension WalkActivityStatus {
    var title: String {
        switch self {
        case .active: "Walking"
        case .paused: "Paused"
        case .finishCandidate: "Finished?"
        case .finalizing: "Saving"
        case .completed: "Walk saved"
        case .interrupted: "Needs attention"
        }
    }

    var systemImage: String {
        switch self {
        case .active: "figure.walk"
        case .paused: "pause.fill"
        case .finishCandidate: "questionmark"
        case .finalizing: "arrow.trianglehead.2.clockwise"
        case .completed: "checkmark"
        case .interrupted: "exclamationmark"
        }
    }

    var tint: Color {
        switch self {
        case .active: .blue
        case .paused: .orange
        case .finishCandidate: .yellow
        case .finalizing: .secondary
        case .completed: .green
        case .interrupted: .red
        }
    }
}
