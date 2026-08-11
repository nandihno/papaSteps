@preconcurrency import UserNotifications
import Foundation

enum WalkNotificationAuthorizationState: String, Sendable {
    case notDetermined
    case denied
    case authorized
}

@MainActor
protocol WalkNotificationProviding: AnyObject {
    func authorizationState() async -> WalkNotificationAuthorizationState
    func requestAuthorization() async -> Bool
    func scheduleFinishPrompt(for walkID: UUID) async
    func cancelFinishPrompt(for walkID: UUID) async
}

@MainActor
final class LiveWalkNotificationClient: NSObject, WalkNotificationProviding,
    UNUserNotificationCenterDelegate {
    private enum Identifier {
        static let category = "PAPASTEPS_FINISH_CANDIDATE"
        static let finish = "PAPASTEPS_FINISH_WALK"
        static let keepWalking = "PAPASTEPS_KEEP_WALKING"
        static let requestPrefix = "papasteps.finish-candidate."
        static let walkIDKey = "walkID"
    }

    private let center: UNUserNotificationCenter
    private let actionHandler: WalkActivityActionHandler

    init(
        center: UNUserNotificationCenter = .current(),
        actionHandler: WalkActivityActionHandler
    ) {
        self.center = center
        self.actionHandler = actionHandler
        super.init()
        center.delegate = self
        registerCategory()
    }

    func authorizationState() async -> WalkNotificationAuthorizationState {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized, .provisional, .ephemeral:
            return .authorized
        @unknown default:
            return .denied
        }
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    func scheduleFinishPrompt(for walkID: UUID) async {
        guard await authorizationState() == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Have you finished your walk?"
        content.body = "Finish now or keep recording when you start moving again."
        content.sound = .default
        content.categoryIdentifier = Identifier.category
        content.userInfo = [Identifier.walkIDKey: walkID.uuidString]

        let request = UNNotificationRequest(
            identifier: requestIdentifier(for: walkID),
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    func cancelFinishPrompt(for walkID: UUID) async {
        let identifier = requestIdentifier(for: walkID)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        []
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let walkIDString = response.notification.request.content.userInfo[
            Identifier.walkIDKey
        ] as? String,
              let walkID = UUID(uuidString: walkIDString) else {
            return
        }

        let action: WalkActivityAction?
        switch response.actionIdentifier {
        case Identifier.finish:
            action = .finish
        case Identifier.keepWalking:
            action = .keepWalking
        default:
            action = nil
        }
        guard let action else { return }
        await actionHandler.perform(
            WalkActivityActionRequest(walkID: walkID, action: action)
        )
    }

    private func registerCategory() {
        let finish = UNNotificationAction(
            identifier: Identifier.finish,
            title: "Finish",
            options: [.foreground]
        )
        let keepWalking = UNNotificationAction(
            identifier: Identifier.keepWalking,
            title: "Keep Walking",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Identifier.category,
            actions: [finish, keepWalking],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    private func requestIdentifier(for walkID: UUID) -> String {
        Identifier.requestPrefix + walkID.uuidString
    }
}

@MainActor
final class FakeWalkNotificationClient: WalkNotificationProviding {
    var state: WalkNotificationAuthorizationState
    var requestResult: Bool
    private(set) var scheduledWalkIDs: [UUID] = []
    private(set) var cancelledWalkIDs: [UUID] = []

    init(
        state: WalkNotificationAuthorizationState = .authorized,
        requestResult: Bool = true
    ) {
        self.state = state
        self.requestResult = requestResult
    }

    func authorizationState() async -> WalkNotificationAuthorizationState {
        state
    }

    func requestAuthorization() async -> Bool {
        state = requestResult ? .authorized : .denied
        return requestResult
    }

    func scheduleFinishPrompt(for walkID: UUID) async {
        scheduledWalkIDs.append(walkID)
    }

    func cancelFinishPrompt(for walkID: UUID) async {
        cancelledWalkIDs.append(walkID)
    }
}
