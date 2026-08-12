import SwiftUI
import UIKit

private enum WalkSheet: String, Equatable, Identifiable {
    case permissions
    case finish

    var id: String { rawValue }
}

/// A readiness capability the user tapped for an explanation.
private struct CapabilityExplanation: Equatable {
    let title: String
    let message: String
    let offersSettings: Bool
}

struct WalkView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(WalkSessionStore.self) private var sessionStore
    @Environment(WalkHealthStore.self) private var healthStore
    @Environment(WalkHistoryStore.self) private var historyStore
    @Environment(WalkDisplayPreferences.self) private var displayPreferences
    @State private var presentedSheet: WalkSheet?
    @State private var isConfirmingFailureDiscard = false
    @State private var explanation: CapabilityExplanation?
    @Namespace private var walkNamespace
    @ScaledMetric(relativeTo: .largeTitle) private var brandSymbolSize: CGFloat = 56
    @ScaledMetric(relativeTo: .largeTitle) private var savedSymbolSize: CGFloat = 44

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
                LiveWalkContent(store: sessionStore, namespace: walkNamespace)
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
        .animation(stateTransition, value: sessionStore.state)
        .navigationTitle(navigationTitle)
        .task(id: sessionStore.completedSummary?.id) {
            historyStore.load()
        }
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
                    Label("Walk Recording", systemImage: WalkSymbol.settings)
                }
                .accessibilityIdentifier("walk.recording.settings")
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    HealthSettingsView()
                } label: {
                    Label("Apple Health", systemImage: WalkSymbol.healthDetail)
                }
                .accessibilityIdentifier("walk.health.settings")
            }
#if DEBUG
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SensorDiagnosticsView()
                } label: {
                    Label("Sensor Diagnostics", systemImage: WalkSymbol.diagnostics)
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

    private var stateTransition: Animation? {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.85)
    }

    // MARK: - Start

    private var startContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                startHeader
                readinessSection
                if historyStore.summaries.isEmpty {
                    whatYouWillSeeCard
                } else {
                    lastWalkCard
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(Spacing.screenMargin)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .safeAreaInset(edge: .bottom) { startAction }
    }

    private var startHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Image(systemName: WalkSymbol.walkCircle)
                .font(.system(size: brandSymbolSize))
                .foregroundStyle(Color.brandGreenInk)
                .accessibilityHidden(true)

            Text("Your outdoor walking companion")
                .font(.largeTitle.bold())

            Text("Record live steps, moving time, speed, direction, altitude, and elevation gain using the sensors available on this iPhone.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private var readinessSection: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text("Readiness")
                .font(.sectionHeader)

            WrappingChips {
                Group {
                    StatusChip(
                        title: "Motion",
                        state: sessionStore.permissionSnapshot.motionAuthorization,
                        systemImage: WalkSymbol.motion
                    ) {
                        explain(
                            title: "Motion and fitness",
                            message: "Motion access provides live steps, pedometer distance, and the movement evidence that separates moving time from waiting time. Without it, papaSteps records what location can provide.",
                            state: sessionStore.permissionSnapshot.motionAuthorization
                        )
                    }
                    StatusChip(
                        title: "Location",
                        state: sessionStore.permissionSnapshot.locationAuthorization,
                        systemImage: WalkSymbol.location
                    ) {
                        explain(
                            title: "Location",
                            message: "Location provides the route map, route distance, GPS speed, and direction of travel. Without it, papaSteps records steps, moving time, pedometer distance, and elevation gain.",
                            state: sessionStore.permissionSnapshot.locationAuthorization
                        )
                    }
                    StatusChip(
                        title: "Accuracy",
                        state: sessionStore.permissionSnapshot.locationAccuracy,
                        systemImage: WalkSymbol.precision
                    ) {
                        explanation = CapabilityExplanation(
                            title: "Location accuracy",
                            message: sessionStore.permissionSnapshot.locationAccuracy == .full
                                ? "Precise Location is on, so route distance, GPS speed, direction, and the map are all available."
                                : "Approximate location is too coarse for a route. papaSteps asks for Precise Location when a walk starts, and continues without it if you decline.",
                            offersSettings: sessionStore.permissionSnapshot.locationAccuracy == .reduced
                        )
                    }
                    StatusChip(
                        title: "Health",
                        state: healthStore.accessState,
                        systemImage: WalkSymbol.healthDetail
                    ) {
                        explanation = CapabilityExplanation(
                            title: "Apple Health",
                            message: "Apple Health is optional. When connected, papaSteps looks for heart rate and walking asymmetry after a walk, and can save the walk as a workout. Walk recording works fully without it.",
                            offersSettings: false
                        )
                    }
                }
            }

            if let explanation {
                SectionCard(
                    title: explanation.title,
                    systemImage: WalkSymbol.information,
                    tint: .signalCaution
                ) {
                    VStack(alignment: .leading, spacing: Spacing.small) {
                        Text(explanation.message)
                            .font(.subheadline)
                            .foregroundStyle(Color.textPrimary)

                        HStack(spacing: Spacing.small) {
                            if explanation.offersSettings, sessionStore.canOpenSettings {
                                Button("Open Settings") { openSettings() }
                                    .buttonStyle(.bordered)
                            }
                            Button("Close") {
                                withAnimation(stateTransition) { self.explanation = nil }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
    }

    private func explain(title: String, message: String, state: some UserFacingState) {
        explanation = CapabilityExplanation(
            title: title,
            message: message,
            offersSettings: state.signalColor == Color.signalAlert
        )
    }

    @ViewBuilder
    private var lastWalkCard: some View {
        if let last = historyStore.summaries.first {
            NavigationLink {
                WalkDetailView(walkID: last.id)
            } label: {
                SectionCard(title: "Last walk", systemImage: WalkSymbol.history) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(last.startDate.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.textPrimary)

                        HStack(spacing: Spacing.medium) {
                            Label(
                                WalkMetricFormatting.distance(
                                    last.displayDistance,
                                    configuration: displayPreferences.configuration
                                ),
                                systemImage: WalkSymbol.distance
                            )
                            Label(
                                last.displaySteps.map(String.init) ?? "—",
                                systemImage: WalkSymbol.steps
                            )
                            Label(
                                WalkMetricFormatting.duration(last.movingDuration),
                                systemImage: WalkSymbol.movingTime
                            )
                        }
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("walk.lastWalk")
        }
    }

    private var startAction: some View {
        VStack(spacing: Spacing.xs) {
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
            .buttonStyle(.primaryWalk)
            .matchedGeometryEffect(id: "walk.primaryAction", in: walkNamespace)
            .accessibilityIdentifier("walk.start")

            Text("Permissions are requested only after you choose Start Walk. Apple Health remains optional.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 620)
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.top, Spacing.small)
        .padding(.bottom, Spacing.small)
        .background(.bar)
    }

    private var whatYouWillSeeCard: some View {
        SectionCard(
            title: "While you walk",
            systemImage: WalkSymbol.walk,
            footnote: "A metric that is unavailable says so rather than showing zero."
        ) {
            VStack(alignment: .leading, spacing: Spacing.small) {
                previewRow(WalkSymbol.speed, "Speed and direction of travel")
                previewRow(WalkSymbol.steps, "Live steps and moving time")
                previewRow(WalkSymbol.distance, "Distance and your route on a map")
                previewRow(WalkSymbol.elevationGain, "Altitude and elevation gained")
            }
        }
    }

    private func previewRow(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.textPrimary)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Color.brandGreenInk)
                .frame(width: 22)
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

    // MARK: - Completed

    private var completedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.large) {
                completedHeader

                if let summary = sessionStore.completedSummary {
                    if let detail = sessionStore.completedDetail {
                        WalkRouteMap(
                            segments: detail.routeSegments,
                            currentCoordinate: detail.routeCoordinates.last,
                            showsEndpointMarkers: true
                        )
                    }

                    HeroMetric(
                        title: "Distance",
                        value: WalkMetricFormatting.distance(
                            summary.displayDistance,
                            configuration: displayPreferences.configuration
                        ),
                        detail: summary.distanceSource.displayName
                    )

                    WalkMetricGrid {
                        MetricTile(
                            title: "Steps",
                            value: summary.displaySteps.map(String.init) ?? "—",
                            detail: summary.stepSource.displayName,
                            systemImage: WalkSymbol.steps
                        )
                        MetricTile(
                            title: "Moving time",
                            value: WalkMetricFormatting.duration(summary.movingDuration),
                            detail: "Excludes pauses",
                            systemImage: WalkSymbol.movingTime
                        )
                        MetricTile(
                            title: "Elapsed time",
                            value: WalkMetricFormatting.duration(summary.elapsedDuration),
                            detail: "Start to finish",
                            systemImage: WalkSymbol.elapsedTime
                        )
                        MetricTile(
                            title: displayPreferences.speedDisplay == .pace
                                ? "Average pace"
                                : "Average speed",
                            value: WalkMetricFormatting.speed(
                                summary.averageSpeed,
                                configuration: displayPreferences.configuration
                            ),
                            detail: "Distance ÷ moving time",
                            systemImage: WalkSymbol.speed
                        )
                        MetricTile(
                            title: "Elevation gain",
                            value: WalkMetricFormatting.altitude(
                                summary.elevationGain,
                                configuration: displayPreferences.configuration
                            ),
                            detail: "Accumulated ascent",
                            systemImage: WalkSymbol.elevationGain
                        )
                        MetricTile(
                            title: "Route quality",
                            value: summary.routeQuality.displayName,
                            detail: summary.routeQuality == .good
                                ? "Accepted GPS points"
                                : "Some metrics were limited",
                            systemImage: WalkSymbol.routeQuality,
                            accentsValue: summary.routeQuality == .good
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
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(Spacing.screenMargin)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .safeAreaInset(edge: .bottom) {
            Button("Done") {
                Task { await sessionStore.reset() }
            }
            .buttonStyle(.primaryWalk)
            .accessibilityIdentifier("walk.completed.done")
            .frame(maxWidth: 620)
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, Spacing.small)
            .padding(.bottom, Spacing.small)
            .background(.bar)
        }
    }

    private var completedHeader: some View {
        HStack(spacing: Spacing.small) {
            Image(systemName: WalkSymbol.good)
                .font(.system(size: savedSymbolSize))
                .foregroundStyle(Color.signalGood)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Walk saved")
                    .font(.title.bold())
                Text("Your local summary and accepted GPS route are saved on this iPhone.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func routeQualityExplanation(_ summary: WalkSummary) -> some View {
        if let reason = summary.routeQualityReason {
            Label(reason.explanation, systemImage: WalkSymbol.information)
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Recovery and failure

    private var failureContent: some View {
        Group {
            if sessionStore.recoveredCheckpoint != nil {
                ContentUnavailableView {
                    Label("Unfinished walk found", systemImage: "arrow.clockwise.heart")
                } description: {
                    Text(sessionStore.lastErrorMessage ?? "An unfinished walk can be recovered from its last checkpoint.")
                } actions: {
                    VStack(spacing: Spacing.small) {
                        Button("Resume Walk") {
                            Task { await sessionStore.resumeRecoveredWalk() }
                        }
                        .buttonStyle(.primaryWalk)
                        .accessibilityIdentifier("walk.recovery.resume")

                        Button("Finish at Last Checkpoint") {
                            Task { await sessionStore.finishRecoveredWalk() }
                        }
                        .buttonStyle(.secondaryWalk)
                        .accessibilityIdentifier("walk.recovery.finish")

                        Button("Discard Walk", role: .destructive) {
                            isConfirmingFailureDiscard = true
                        }
                        .accessibilityIdentifier("walk.recovery.discard")
                    }
                    .frame(maxWidth: 420)
                }
            } else {
                ContentUnavailableView {
                    Label("Walk needs attention", systemImage: WalkSymbol.alert)
                } description: {
                    Text(sessionStore.lastErrorMessage ?? "The walk could not continue.")
                } actions: {
                    VStack(spacing: Spacing.small) {
                        Button("Try Again") {
                            Task { await sessionStore.retry() }
                        }
                        .buttonStyle(.primaryWalk)

                        if sessionStore.canOpenSettings {
                            Button("Open Settings") {
                                openSettings()
                            }
                            .buttonStyle(.secondaryWalk)
                        }

                        Button("Discard Walk", role: .destructive) {
                            isConfirmingFailureDiscard = true
                        }
                    }
                    .frame(maxWidth: 420)
                }
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

// MARK: - Live walk

private struct LiveWalkContent: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(WalkDisplayPreferences.self) private var displayPreferences
    @AppStorage("walk.live.showsAllMetrics") private var showsAllMetrics = false

    let store: WalkSessionStore
    let namespace: Namespace.ID

    @ScaledMetric(relativeTo: .largeTitle) private var directionSymbolSize: CGFloat = 40

    private var metrics: WalkMetricsSnapshot { store.metrics }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.medium) {
                statusPill
                hero
                limitationBanner
                primaryMetrics
                secondaryMetrics
                WalkRouteMap(
                    segments: metrics.routeSegments,
                    currentCoordinate: metrics.currentCoordinate,
                    followsCurrentLocation: true
                )
            }
            .frame(maxWidth: 720)
            .padding(Spacing.screenMargin)
        }
        // The identifier must be applied before `safeAreaInset`: applied after,
        // it propagates into the inset and overrides the identifiers on the
        // Pause and Done buttons inside the control bar.
        .accessibilityIdentifier("walk.live")
        .scrollEdgeEffectStyle(.soft, for: .top)
        .safeAreaInset(edge: .bottom) { controls }
    }

    // MARK: Header

    private var statusPill: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: WalkSymbol.recording)
            Text(headerStatus)
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(ringState.tint)
        .padding(.horizontal, Spacing.small)
        .padding(.vertical, Spacing.xs)
        .background(ringState.tint.opacity(0.12), in: .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recording state")
        .accessibilityValue(headerStatus)
    }

    private var hero: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.large) {
                directionDial
                speedBlock
            }
            VStack(spacing: Spacing.medium) {
                directionDial
                speedBlock
            }
        }
    }

    private var directionDial: some View {
        VStack(spacing: Spacing.xs) {
            RecordingRing(state: ringState) {
                Image(systemName: WalkSymbol.direction)
                    .font(.system(size: directionSymbolSize, weight: .semibold))
                    .foregroundStyle(directionIsStale ? Color.textSecondary : Color.brandGreen)
                    .rotationEffect(.degrees(metrics.direction.value ?? 0))
                    .animation(.easeInOut(duration: 0.3), value: metrics.direction.value)
                    .frame(width: directionSymbolSize + 12, height: directionSymbolSize + 12)
            }

            Text(directionLabel)
                .font(.subheadline)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(directionIsStale ? Color.signalCaution : Color.textSecondary)
                // No line limit: "No heading yet" is clipped at large text sizes
                // when it cannot wrap. The audit caught this.
                .multilineTextAlignment(.center)
        }
        // `.accessibilityElement()` alone replaces the children with a synthetic
        // node, and the audit then cannot see that the text inside scales.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Direction of travel")
        .accessibilityValue(
            "\(WalkMetricFormatting.direction(metrics.direction.value)). \(WalkMetricFormatting.detail(for: metrics.direction.availability))"
        )
    }

    private var speedBlock: some View {
        HeroMetric(
            title: displayPreferences.speedDisplay == .pace ? "Pace" : "Speed",
            value: WalkMetricFormatting.speed(
                metrics.speed.value,
                configuration: displayPreferences.configuration
            ),
            detail: WalkMetricFormatting.detail(for: metrics.speed.availability),
            isStale: WalkMetricFormatting.isStale(metrics.speed.availability)
        )
    }

    // MARK: Metrics

    private var primaryMetrics: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: Spacing.gridGutter) { primaryTiles }
            } else {
                HStack(spacing: Spacing.gridGutter) { primaryTiles }
            }
        }
    }

    @ViewBuilder
    private var primaryTiles: some View {
        MetricTile(
            title: "Steps",
            value: metrics.steps.value.map(String.init) ?? "—",
            detail: WalkMetricFormatting.detail(for: metrics.steps.availability),
            systemImage: WalkSymbol.steps,
            size: .compact
        )
        MetricTile(
            title: "Moving",
            value: WalkMetricFormatting.duration(metrics.movingDuration),
            detail: metrics.isMoving ? "Moving" : "Waiting for movement",
            systemImage: WalkSymbol.movingTime,
            size: .compact
        )
        MetricTile(
            title: "Distance",
            value: WalkMetricFormatting.distance(
                metrics.distance.value,
                configuration: displayPreferences.configuration
            ),
            detail: distanceDetail,
            systemImage: WalkSymbol.distance,
            size: .compact
        )
    }

    private var secondaryMetrics: some View {
        DisclosureGroup(isExpanded: $showsAllMetrics) {
            WalkMetricGrid {
                MetricTile(
                    title: "Elapsed time",
                    value: WalkMetricFormatting.duration(metrics.elapsedDuration),
                    detail: store.state == .paused ? "Paused" : "Recording",
                    systemImage: WalkSymbol.elapsedTime
                )
                MetricTile(
                    title: "Altitude",
                    value: WalkMetricFormatting.altitude(
                        metrics.absoluteAltitude.value,
                        configuration: displayPreferences.configuration
                    ),
                    detail: WalkMetricFormatting.detail(for: metrics.absoluteAltitude.availability),
                    systemImage: WalkSymbol.altitude
                )
                MetricTile(
                    title: "Elevation gain",
                    value: WalkMetricFormatting.altitude(
                        metrics.elevationGain.value,
                        configuration: displayPreferences.configuration
                    ),
                    detail: WalkMetricFormatting.detail(for: metrics.elevationGain.availability),
                    systemImage: WalkSymbol.elevationGain
                )
                MetricTile(
                    title: "Direction",
                    value: WalkMetricFormatting.direction(metrics.direction.value),
                    detail: WalkMetricFormatting.detail(for: metrics.direction.availability),
                    systemImage: WalkSymbol.direction,
                    isStale: directionIsStale
                )
            }
            .padding(.top, Spacing.small)
        } label: {
            Text("More metrics")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
        }
        .tint(Color.brandGreenInk)
        .padding(Spacing.small)
        .cardSurface()
        .accessibilityIdentifier("walk.live.moreMetrics")
    }

    // MARK: Banners and controls

    @ViewBuilder
    private var limitationBanner: some View {
        if metrics.locationAccuracy == .reduced {
            SectionCard(
                title: "Precise Location is off",
                systemImage: WalkSymbol.locationOff,
                tint: .signalCaution
            ) {
                VStack(alignment: .leading, spacing: Spacing.small) {
                    Text("Route distance, GPS speed, direction, and map position are limited. Steps, moving time, pedometer distance, and relative elevation continue.")
                        .font(.subheadline)
                    Button("Request Precise Location") {
                        Task { await store.requestTemporaryFullAccuracy() }
                    }
                    .buttonStyle(.bordered)
                }
            }
        } else if metrics.routeLimitation == .permissionDenied
            || store.permissionSnapshot.locationAuthorization == .denied {
            SectionCard(
                title: "Location is turned off",
                systemImage: WalkSymbol.locationOff,
                tint: .signalCaution
            ) {
                VStack(alignment: .leading, spacing: Spacing.small) {
                    Text("The walk continues with the motion metrics that are available.")
                        .font(.subheadline)
                    Button("Open Settings") { openSettings() }
                        .buttonStyle(.bordered)
                }
            }
        } else if store.permissionSnapshot.motionAuthorization == .denied {
            SectionCard(
                title: "Motion access is turned off",
                systemImage: WalkSymbol.motion,
                tint: .signalCaution
            ) {
                VStack(alignment: .leading, spacing: Spacing.small) {
                    Text("The walk continues with the location metrics that are available.")
                        .font(.subheadline)
                    Button("Open Settings") { openSettings() }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private var controls: some View {
        GlassControlBar {
            Button(store.state == .paused ? "Resume" : "Pause") {
                Task {
                    if store.state == .paused {
                        await store.resume()
                    } else {
                        await store.pause()
                    }
                }
            }
            .buttonStyle(.primaryWalk)
            .matchedGeometryEffect(id: "walk.primaryAction", in: namespace)
            .accessibilityIdentifier(store.state == .paused ? "walk.resume" : "walk.pause")

            Button("Done") {
                store.requestFinish()
            }
            .buttonStyle(.secondaryWalk)
            .accessibilityIdentifier("walk.done")
        }
    }

    // MARK: Derived state

    private var ringState: RecordingRingState {
        if store.state == .paused { return .paused }
        return metrics.isMoving ? .recording : .waiting
    }

    private var directionIsStale: Bool {
        WalkMetricFormatting.isStale(metrics.direction.availability)
    }

    private var directionLabel: String {
        guard metrics.direction.value != nil else { return "No heading yet" }
        return WalkMetricFormatting.direction(metrics.direction.value)
    }

    private var headerStatus: String {
        if store.state == .paused { return "Paused" }
        return metrics.isMoving ? "Walking" : "Recording · start moving"
    }

    private var distanceDetail: String {
        switch metrics.distanceSource {
        case .unavailable:
            WalkMetricFormatting.detail(for: metrics.distance.availability)
        default:
            metrics.distanceSource.displayName
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}
