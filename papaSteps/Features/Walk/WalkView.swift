import SwiftUI
import UIKit

private enum WalkSheet: String, Equatable, Identifiable {
    case permissions
    case finish

    var id: String { rawValue }
}

struct WalkView: View {
    @Environment(\.openURL) private var openURL
    @Environment(WalkSessionStore.self) private var sessionStore
    @Environment(WalkHealthStore.self) private var healthStore
    @Environment(WalkDisplayPreferences.self) private var displayPreferences
    @State private var presentedSheet: WalkSheet?
    @State private var isConfirmingFailureDiscard = false

    var body: some View {
        Group {
            switch sessionStore.state {
            case .idle:
                startContent
            case .preparing:
                workingContent(
                    title: "Preparing your walk",
                    detail: "Checking permissions and starting available sensors."
                )
            case .active, .paused, .finishCandidate:
                LiveWalkContent(store: sessionStore)
            case .finalizing:
                workingContent(
                    title: "Saving your walk",
                    detail: "Reconciling pedometer data and creating one local summary."
                )
            case .completed:
                completedContent
            case .recoverableFailure:
                failureContent
            }
        }
        .navigationTitle(navigationTitle)
        .onChange(of: sessionStore.state) { _, newState in
            if newState == .finishCandidate {
                presentedSheet = .finish
            } else if presentedSheet == .finish {
                presentedSheet = nil
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .permissions:
                WalkPermissionSheet(store: sessionStore)
            case .finish:
                WalkFinishSheet(store: sessionStore)
            }
        }
        .confirmationDialog(
            "Discard this walk permanently?",
            isPresented: $isConfirmingFailureDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard Permanently", role: .destructive) {
                Task { await sessionStore.discard() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current walk and its measurements will not be saved. This cannot be undone.")
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    WalkRecordingSettingsView()
                } label: {
                    Label("Walk Recording", systemImage: "gearshape")
                }
                .accessibilityIdentifier("walk.recording.settings")
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    HealthSettingsView()
                } label: {
                    Label("Apple Health", systemImage: "heart.text.square")
                }
                .accessibilityIdentifier("walk.health.settings")
            }
#if DEBUG
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SensorDiagnosticsView()
                } label: {
                    Label("Sensor Diagnostics", systemImage: "stethoscope")
                }
                .accessibilityIdentifier("walk.diagnostics")
            }
#endif
        }
    }

    private var navigationTitle: String {
        switch sessionStore.state {
        case .active, .paused, .finishCandidate:
            "Live Walk"
        default:
            "Walk"
        }
    }

    private var startContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "figure.walk.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)

                    Text("Your outdoor walking companion")
                        .font(.title2.bold())

                    Text("Record live steps, moving time, speed, direction, altitude, and elevation gain using the sensors available on this iPhone.")
                        .foregroundStyle(.secondary)
                }

                readinessPanel

                Button("Start Walk") {
                    sessionStore.refreshPermissionSnapshot()
                    if sessionStore.needsPermissionExplanation {
                        presentedSheet = .permissions
                    } else {
                        Task {
                            await sessionStore.start(requestPermissions: false)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("walk.start")

                Text("Permissions are requested only after you choose Start Walk. Apple Health remains optional.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding()
        }
    }

    private var readinessPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Readiness")
                .font(.headline)

            readinessRow(
                title: "Motion & Fitness",
                state: sessionStore.permissionSnapshot.motionAuthorization.rawValue,
                systemImage: "figure.walk.motion"
            )
            readinessRow(
                title: "Location",
                state: sessionStore.permissionSnapshot.locationAuthorization.rawValue,
                systemImage: "location"
            )
            readinessRow(
                title: "Location accuracy",
                state: sessionStore.permissionSnapshot.locationAccuracy.rawValue,
                systemImage: "scope"
            )
            readinessRow(
                title: "Apple Health",
                state: healthStore.accessState.displayName,
                systemImage: "heart.text.square"
            )
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: .rect(cornerRadius: 16))
    }

    private func readinessRow(
        title: String,
        state: String,
        systemImage: String
    ) -> some View {
        LabeledContent {
            Text(state.replacingOccurrences(of: "notDetermined", with: "Not requested"))
                .foregroundStyle(.secondary)
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    private func workingContent(title: String, detail: String) -> some View {
        ContentUnavailableView {
            ProgressView()
                .controlSize(.large)
            Text(title)
                .font(.title2.bold())
        } description: {
            Text(detail)
        }
    }

    private var completedContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text("Walk saved")
                        .font(.largeTitle.bold())
                    Text("Your local summary and accepted GPS route are saved on this iPhone.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let summary = sessionStore.completedSummary {
                    if let detail = sessionStore.completedDetail {
                        WalkRouteMap(
                            segments: detail.routeSegments,
                            currentCoordinate: detail.routeCoordinates.last,
                            showsEndpointMarkers: true
                        )
                    }
                    WalkMetricGrid {
                        WalkMetricCard(
                            title: "Distance",
                            value: WalkMetricFormatting.distance(
                                summary.displayDistance,
                                configuration: displayPreferences.configuration
                            ),
                            detail: "Saved locally",
                            systemImage: "ruler"
                        )
                        WalkMetricCard(
                            title: "Steps",
                            value: summary.displaySteps.map(String.init) ?? "—",
                            detail: "Saved locally",
                            systemImage: "shoeprints.fill"
                        )
                        WalkMetricCard(
                            title: "Moving time",
                            value: WalkMetricFormatting.duration(summary.movingDuration),
                            detail: "Excludes pauses",
                            systemImage: "timer"
                        )
                        WalkMetricCard(
                            title: "Elapsed time",
                            value: WalkMetricFormatting.duration(summary.elapsedDuration),
                            detail: "Start to finish",
                            systemImage: "clock"
                        )
                        WalkMetricCard(
                            title: displayPreferences.speedDisplay == .pace
                                ? "Average pace"
                                : "Average speed",
                            value: WalkMetricFormatting.speed(
                                summary.averageSpeed,
                                configuration: displayPreferences.configuration
                            ),
                            detail: "Distance ÷ moving time",
                            systemImage: "speedometer"
                        )
                        WalkMetricCard(
                            title: "Elevation gain",
                            value: WalkMetricFormatting.altitude(
                                summary.elevationGain,
                                configuration: displayPreferences.configuration
                            ),
                            detail: "Accumulated ascent",
                            systemImage: "arrow.up.right"
                        )
                    }

                    if let detail = sessionStore.completedDetail {
                        HealthInsightSection(
                            detail: detail,
                            accessState: healthStore.accessState,
                            isRefreshing: healthStore.isWorking,
                            refresh: {
                                Task { await sessionStore.refreshCompletedHealth() }
                            }
                        )
                    }

                    routeQualityExplanation(summary)
                }

                Button("Done") {
                    Task { await sessionStore.reset() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("walk.completed.done")
            }
            .frame(maxWidth: 620)
            .padding()
        }
    }

    @ViewBuilder
    private func routeQualityExplanation(_ summary: WalkSummary) -> some View {
        if let reason = summary.routeQualityReason {
            Label(reason.explanation, systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var failureContent: some View {
        Group {
            if sessionStore.recoveredCheckpoint != nil {
                ContentUnavailableView {
                    Label("Unfinished walk found", systemImage: "arrow.clockwise.heart")
                } description: {
                    Text(sessionStore.lastErrorMessage ?? "An unfinished walk can be recovered from its last checkpoint.")
                } actions: {
                    Button("Resume Walk") {
                        Task { await sessionStore.resumeRecoveredWalk() }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("walk.recovery.resume")

                    Button("Finish at Last Checkpoint") {
                        Task { await sessionStore.finishRecoveredWalk() }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("walk.recovery.finish")

                    Button("Discard Walk", role: .destructive) {
                        isConfirmingFailureDiscard = true
                    }
                    .accessibilityIdentifier("walk.recovery.discard")
                }
            } else {
                ContentUnavailableView {
                    Label("Walk needs attention", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(sessionStore.lastErrorMessage ?? "The walk could not continue.")
                } actions: {
                    Button("Try Again") {
                        Task { await sessionStore.retry() }
                    }
                    .buttonStyle(.borderedProminent)

                    if sessionStore.canOpenSettings {
                        Button("Open Settings") {
                            openSettings()
                        }
                    }

                    Button("Discard Walk", role: .destructive) {
                        isConfirmingFailureDiscard = true
                    }
                }
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

private struct LiveWalkContent: View {
    @Environment(\.openURL) private var openURL
    @Environment(WalkDisplayPreferences.self) private var displayPreferences

    let store: WalkSessionStore

    private var metrics: WalkMetricsSnapshot { store.metrics }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                recordingHeader
                limitationBanner
                metricGrid
                WalkRouteMap(
                    segments: metrics.routeSegments,
                    currentCoordinate: metrics.currentCoordinate,
                    followsCurrentLocation: true
                )
                controls
            }
            .frame(maxWidth: 720)
            .padding()
        }
        .accessibilityIdentifier("walk.live")
    }

    private var recordingHeader: some View {
        VStack(spacing: 8) {
            Image(systemName: "location.north.fill")
                .font(.system(size: 70, weight: .semibold))
                .foregroundStyle(directionIsStale ? Color.secondary : Color.blue)
                .rotationEffect(.degrees(metrics.direction.value ?? 0))
                .animation(.easeInOut(duration: 0.3), value: metrics.direction.value)
                .accessibilityHidden(true)

            Text(WalkMetricFormatting.direction(metrics.direction.value))
                .font(.largeTitle.monospacedDigit().bold())

            Text(headerStatus)
                .font(.headline)
                .foregroundStyle(store.state == .paused ? .orange : .secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Direction \(WalkMetricFormatting.direction(metrics.direction.value)), \(headerStatus)")
    }

    @ViewBuilder
    private var limitationBanner: some View {
        if metrics.locationAccuracy == .reduced {
            VStack(alignment: .leading, spacing: 10) {
                Label("Precise Location is off", systemImage: "location.slash.circle.fill")
                    .font(.headline)
                Text("Route distance, GPS speed, direction, and map position are limited. Steps, moving time, pedometer distance, and relative elevation continue.")
                    .font(.subheadline)
                Button("Request Precise Location") {
                    Task { await store.requestTemporaryFullAccuracy() }
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.14), in: .rect(cornerRadius: 16))
        } else if metrics.routeLimitation == .permissionDenied
            || store.permissionSnapshot.locationAuthorization == .denied {
            VStack(alignment: .leading, spacing: 10) {
                Label(
                    "Location is denied. The walk continues with available Motion metrics.",
                    systemImage: "location.slash"
                )
                Button("Open Settings") {
                    openSettings()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.14), in: .rect(cornerRadius: 16))
        } else if store.permissionSnapshot.motionAuthorization == .denied {
            VStack(alignment: .leading, spacing: 10) {
                Label(
                    "Motion access is denied. The walk continues with available Location metrics.",
                    systemImage: "figure.walk.motion"
                )
                Button("Open Settings") {
                    openSettings()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.14), in: .rect(cornerRadius: 16))
        }
    }

    private var metricGrid: some View {
        WalkMetricGrid {
            WalkMetricCard(
                title: displayPreferences.speedDisplay == .pace ? "Pace" : "Speed",
                value: WalkMetricFormatting.speed(
                    metrics.speed.value,
                    configuration: displayPreferences.configuration
                ),
                detail: WalkMetricFormatting.detail(for: metrics.speed.availability),
                systemImage: "speedometer",
                isStale: WalkMetricFormatting.isStale(metrics.speed.availability)
            )
            WalkMetricCard(
                title: "Steps",
                value: metrics.steps.value.map(String.init) ?? "—",
                detail: WalkMetricFormatting.detail(for: metrics.steps.availability),
                systemImage: "shoeprints.fill"
            )
            WalkMetricCard(
                title: "Moving time",
                value: WalkMetricFormatting.duration(metrics.movingDuration),
                detail: metrics.isMoving ? "Moving" : "Waiting for movement",
                systemImage: "timer"
            )
            WalkMetricCard(
                title: "Elapsed time",
                value: WalkMetricFormatting.duration(metrics.elapsedDuration),
                detail: store.state == .paused ? "Paused" : "Recording",
                systemImage: "clock"
            )
            WalkMetricCard(
                title: "Distance",
                value: WalkMetricFormatting.distance(
                    metrics.distance.value,
                    configuration: displayPreferences.configuration
                ),
                detail: distanceDetail,
                systemImage: "ruler"
            )
            WalkMetricCard(
                title: "Altitude",
                value: WalkMetricFormatting.altitude(
                    metrics.absoluteAltitude.value,
                    configuration: displayPreferences.configuration
                ),
                detail: WalkMetricFormatting.detail(for: metrics.absoluteAltitude.availability),
                systemImage: "mountain.2"
            )
            WalkMetricCard(
                title: "Elevation gain",
                value: WalkMetricFormatting.altitude(
                    metrics.elevationGain.value,
                    configuration: displayPreferences.configuration
                ),
                detail: WalkMetricFormatting.detail(for: metrics.elevationGain.availability),
                systemImage: "arrow.up.right"
            )
            WalkMetricCard(
                title: "Direction",
                value: WalkMetricFormatting.direction(metrics.direction.value),
                detail: WalkMetricFormatting.detail(for: metrics.direction.availability),
                systemImage: "location.north",
                isStale: directionIsStale
            )
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button(store.state == .paused ? "Resume" : "Pause") {
                Task {
                    if store.state == .paused {
                        await store.resume()
                    } else {
                        await store.pause()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier(store.state == .paused ? "walk.resume" : "walk.pause")

            Button("Done") {
                store.requestFinish()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("walk.done")
        }
    }

    private var directionIsStale: Bool {
        WalkMetricFormatting.isStale(metrics.direction.availability)
    }

    private var headerStatus: String {
        if store.state == .paused { return "Paused" }
        return metrics.isMoving ? "Walking" : "Recording · start moving"
    }

    private var distanceDetail: String {
        switch metrics.distanceSource {
        case .route:
            "GPS route"
        case .pedometer:
            "Pedometer estimate"
        case .health:
            "Apple Health"
        case .unavailable:
            WalkMetricFormatting.detail(for: metrics.distance.availability)
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}
