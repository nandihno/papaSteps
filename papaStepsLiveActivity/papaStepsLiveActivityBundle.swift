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
                .activityBackgroundTint(Color.surfaceBase.opacity(0.2))
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: WalkSymbol.motion)
                        .font(.title2)
                        .foregroundStyle(Color.brandGreen)
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
                Image(systemName: WalkSymbol.walk)
                    .foregroundStyle(Color.brandGreen)
            }
            .keylineTint(Color.brandGreen)
        }
    }

    private func metric(_ value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.textSecondary)
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
                Label("papaSteps", systemImage: WalkSymbol.motion)
                    .font(.headline)
                    .foregroundStyle(Color.brandGreenInk)
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
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                metric(context.state.steps.map(String.init) ?? "—", label: "steps")
                Spacer()
                metric(distanceText, label: "distance")
                Spacer()
                metric(durationText, label: "moving")
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
                .foregroundStyle(Color.textSecondary)
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
                .tint(Color.signalCaution)
                finishButton
            case .paused:
                Button(intent: ResumeWalkIntent(walkID: walkID)) {
                    Label("Resume", systemImage: "play.fill")
                }
                .tint(Color.brandGreen)
                .foregroundStyle(Color.onBrandGreen)
                finishButton
            case .finishCandidate:
                Button(intent: KeepWalkingIntent(walkID: walkID)) {
                    Label("Keep Walking", systemImage: WalkSymbol.walk)
                }
                .tint(Color.brandGreen)
                .foregroundStyle(Color.onBrandGreen)
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
        .tint(Color.signalAlertFill)
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
        case .active: WalkSymbol.walk
        case .paused: "pause.fill"
        case .finishCandidate: "questionmark"
        case .finalizing: "arrow.trianglehead.2.clockwise"
        case .completed: WalkSymbol.good
        case .interrupted: WalkSymbol.alert
        }
    }

    var tint: Color {
        switch self {
        case .active: .brandGreen
        case .paused: .signalCaution
        case .finishCandidate: .signalCaution
        case .finalizing: .textSecondary
        case .completed: .signalGood
        case .interrupted: .signalAlert
        }
    }
}
