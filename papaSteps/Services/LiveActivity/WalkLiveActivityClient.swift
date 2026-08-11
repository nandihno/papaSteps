import ActivityKit
import Foundation

private final class WalkActivityHandle: @unchecked Sendable {
    let activity: Activity<WalkActivityAttributes>

    init(_ activity: Activity<WalkActivityAttributes>) {
        self.activity = activity
    }

    var walkID: UUID {
        activity.attributes.walkID
    }

    func update(
        _ content: ActivityContent<WalkActivityAttributes.ContentState>
    ) async {
        await activity.update(content)
    }

    func end(
        _ content: ActivityContent<WalkActivityAttributes.ContentState>?,
        dismissalPolicy: ActivityUIDismissalPolicy
    ) async {
        await activity.end(content, dismissalPolicy: dismissalPolicy)
    }
}

enum WalkLiveActivityEndReason: Sendable {
    case completed
    case discarded
}

@MainActor
protocol WalkLiveActivityProviding: AnyObject {
    func start(
        walkID: UUID,
        startDate: Date,
        state: WalkSessionState,
        metrics: WalkMetricsSnapshot
    ) async
    func update(
        walkID: UUID,
        state: WalkSessionState,
        metrics: WalkMetricsSnapshot,
        force: Bool
    ) async
    func end(
        walkID: UUID,
        metrics: WalkMetricsSnapshot,
        reason: WalkLiveActivityEndReason
    ) async
    func endOrphanedActivities(except walkID: UUID?) async
}

@MainActor
final class LiveWalkActivityClient: WalkLiveActivityProviding {
    private let minimumUpdateInterval: TimeInterval
    private var activity: WalkActivityHandle?
    private var lastUpdateDate: Date?
    private var lastStatus: WalkActivityStatus?

    init(minimumUpdateInterval: TimeInterval = 15) {
        self.minimumUpdateInterval = minimumUpdateInterval
    }

    func start(
        walkID: UUID,
        startDate: Date,
        state: WalkSessionState,
        metrics: WalkMetricsSnapshot
    ) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        await endOrphanedActivities(except: walkID)
        if let existing = Activity<WalkActivityAttributes>.activities.first(
            where: { $0.attributes.walkID == walkID }
        ) {
            activity = WalkActivityHandle(existing)
            await update(
                walkID: walkID,
                state: state,
                metrics: metrics,
                force: true
            )
            return
        }

        let status = activityStatus(for: state)
        let attributes = WalkActivityAttributes(
            walkID: walkID,
            startDate: startDate
        )
        let content = makeContent(status: status, metrics: metrics)

        do {
            activity = WalkActivityHandle(
                try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
            )
            lastUpdateDate = Date()
            lastStatus = status
        } catch {
            activity = nil
        }
    }

    func update(
        walkID: UUID,
        state: WalkSessionState,
        metrics: WalkMetricsSnapshot,
        force: Bool
    ) async {
        guard let activity = matchingActivity(for: walkID) else { return }
        let now = Date()
        let status = activityStatus(for: state)
        let statusChanged = status != lastStatus
        if !force, !statusChanged,
           let lastUpdateDate,
           now.timeIntervalSince(lastUpdateDate) < minimumUpdateInterval {
            return
        }

        await activity.update(makeContent(status: status, metrics: metrics, at: now))
        self.lastUpdateDate = now
        lastStatus = status
    }

    func end(
        walkID: UUID,
        metrics: WalkMetricsSnapshot,
        reason: WalkLiveActivityEndReason
    ) async {
        guard let activity = matchingActivity(for: walkID) else { return }
        let status: WalkActivityStatus
        switch reason {
        case .completed:
            status = .completed
        case .discarded:
            status = .interrupted
        }
        let content = makeContent(status: status, metrics: metrics)
        let policy: ActivityUIDismissalPolicy
        switch reason {
        case .completed:
            policy = .after(Date().addingTimeInterval(60))
        case .discarded:
            policy = .immediate
        }
        await activity.end(content, dismissalPolicy: policy)
        self.activity = nil
        lastUpdateDate = nil
        lastStatus = nil
    }

    func endOrphanedActivities(except walkID: UUID?) async {
        for existing in Activity<WalkActivityAttributes>.activities
        where existing.attributes.walkID != walkID {
            await WalkActivityHandle(existing).end(nil, dismissalPolicy: .immediate)
        }
    }

    private func matchingActivity(
        for walkID: UUID
    ) -> WalkActivityHandle? {
        if let activity, activity.walkID == walkID {
            return activity
        }
        let existing = Activity<WalkActivityAttributes>.activities.first {
            $0.attributes.walkID == walkID
        }
        let handle = existing.map(WalkActivityHandle.init)
        activity = handle
        return handle
    }

    private func makeContent(
        status: WalkActivityStatus,
        metrics: WalkMetricsSnapshot,
        at date: Date = Date()
    ) -> ActivityContent<WalkActivityAttributes.ContentState> {
        ActivityContent(
            state: WalkActivityAttributes.ContentState(
                status: status,
                updatedAt: date,
                elapsedDuration: metrics.elapsedDuration,
                movingDuration: metrics.movingDuration,
                steps: metrics.steps.value,
                distanceMeters: metrics.distance.value
            ),
            staleDate: date.addingTimeInterval(120),
            relevanceScore: status == .finishCandidate ? 100 : 80
        )
    }

    private func activityStatus(for state: WalkSessionState) -> WalkActivityStatus {
        switch state {
        case .paused:
            .paused
        case .finishCandidate:
            .finishCandidate
        case .finalizing:
            .finalizing
        case .completed:
            .completed
        case .recoverableFailure:
            .interrupted
        case .idle, .preparing, .active:
            .active
        }
    }
}

@MainActor
final class FakeWalkLiveActivityClient: WalkLiveActivityProviding {
    private(set) var startCallCount = 0
    private(set) var updateCallCount = 0
    private(set) var endCallCount = 0
    private(set) var lastWalkID: UUID?
    private(set) var lastState: WalkSessionState?

    func start(
        walkID: UUID,
        startDate: Date,
        state: WalkSessionState,
        metrics: WalkMetricsSnapshot
    ) async {
        startCallCount += 1
        lastWalkID = walkID
        lastState = state
    }

    func update(
        walkID: UUID,
        state: WalkSessionState,
        metrics: WalkMetricsSnapshot,
        force: Bool
    ) async {
        updateCallCount += 1
        lastWalkID = walkID
        lastState = state
    }

    func end(
        walkID: UUID,
        metrics: WalkMetricsSnapshot,
        reason: WalkLiveActivityEndReason
    ) async {
        endCallCount += 1
        lastWalkID = walkID
    }

    func endOrphanedActivities(except walkID: UUID?) async {}
}
