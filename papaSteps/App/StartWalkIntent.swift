import AppIntents

enum WalkStartOutcome: Sendable {
    case started
    case alreadyInProgress
    case needsPermissionSetup
}

/// Bridges the App Intents runtime — which can instantiate `StartWalkIntent`
/// before `AppDependencies` exists, the same way it can for a Live Activity
/// button — to the live `WalkSessionStore`. Mirrors `WalkActivityActionHandler`.
actor WalkStartActionHandler {
    typealias Handler = @MainActor @Sendable () async -> WalkStartOutcome

    private let handler: Handler

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func perform() async -> WalkStartOutcome {
        await handler()
    }
}

struct StartWalkIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Walk"
    static let description = IntentDescription("Begin recording a new outdoor walk in papaSteps.")

    @Dependency private var startHandler: WalkStartActionHandler

    func perform() async throws -> some IntentResult & ProvidesDialog {
        switch await startHandler.perform() {
        case .started:
            return .result(dialog: "Your walk has started.")
        case .alreadyInProgress:
            return .result(dialog: "You already have a walk in progress.")
        case .needsPermissionSetup:
            try await continueInForeground(
                "Open papaSteps to grant Motion and Location access before your first walk."
            )
            return .result(dialog: "Tap Start Walk to get set up.")
        }
    }
}

struct PapaStepsAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartWalkIntent(),
            phrases: [
                "Start a walk with \(.applicationName)",
                "Start walking with \(.applicationName)"
            ],
            shortTitle: "Start Walk",
            // Must be a literal — the App Intents metadata compiler rejects a
            // reference to WalkSymbol.walk here, even though it's the same value.
            systemImageName: "figure.walk"
        )
    }
}
