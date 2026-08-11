import ActivityKit
import AppIntents
import Foundation

struct WalkActivityAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        let status: WalkActivityStatus
        let updatedAt: Date
        let elapsedDuration: TimeInterval
        let movingDuration: TimeInterval
        let steps: Int?
        let distanceMeters: Double?
    }

    let walkID: UUID
    let startDate: Date
}

enum WalkActivityStatus: String, Codable, Hashable, Sendable {
    case active
    case paused
    case finishCandidate
    case finalizing
    case completed
    case interrupted
}

enum WalkActivityAction: String, Codable, Hashable, Sendable {
    case pause
    case resume
    case finish
    case keepWalking
}

struct WalkActivityActionRequest: Codable, Hashable, Sendable {
    let walkID: UUID
    let action: WalkActivityAction
}

actor WalkActivityActionHandler {
    typealias Handler = @MainActor @Sendable (WalkActivityActionRequest) async -> Void

    private let handler: Handler

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func perform(_ request: WalkActivityActionRequest) async {
        await handler(request)
    }
}

struct PauseWalkIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause Walk"
    static let isDiscoverable = false
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Walk ID") var walkID: String
    @Dependency private var actionHandler: WalkActivityActionHandler

    init(walkID: UUID) {
        self.walkID = walkID.uuidString
    }

    init() {}

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: walkID) {
            await actionHandler.perform(
                WalkActivityActionRequest(walkID: id, action: .pause)
            )
        }
        return .result()
    }
}

struct ResumeWalkIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Resume Walk"
    static let isDiscoverable = false
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Walk ID") var walkID: String
    @Dependency private var actionHandler: WalkActivityActionHandler

    init(walkID: UUID) {
        self.walkID = walkID.uuidString
    }

    init() {}

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: walkID) {
            await actionHandler.perform(
                WalkActivityActionRequest(walkID: id, action: .resume)
            )
        }
        return .result()
    }
}

struct FinishWalkIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Finish Walk"
    static let isDiscoverable = false
    static var supportedModes: IntentModes { .foreground(.dynamic) }

    @Parameter(title: "Walk ID") var walkID: String
    @Dependency private var actionHandler: WalkActivityActionHandler

    init(walkID: UUID) {
        self.walkID = walkID.uuidString
    }

    init() {}

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: walkID) {
            await actionHandler.perform(
                WalkActivityActionRequest(walkID: id, action: .finish)
            )
        }
        return .result()
    }
}

struct KeepWalkingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Keep Walking"
    static let isDiscoverable = false
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Walk ID") var walkID: String
    @Dependency private var actionHandler: WalkActivityActionHandler

    init(walkID: UUID) {
        self.walkID = walkID.uuidString
    }

    init() {}

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: walkID) {
            await actionHandler.perform(
                WalkActivityActionRequest(walkID: id, action: .keepWalking)
            )
        }
        return .result()
    }
}
