import Foundation

@MainActor
protocol WalkReminderPreferences: AnyObject {
    var finishRemindersEnabled: Bool { get set }
}

@MainActor
final class LiveWalkReminderPreferences: WalkReminderPreferences {
    private enum Key {
        static let finishRemindersEnabled = "walk.finishRemindersEnabled"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var finishRemindersEnabled: Bool {
        get { defaults.bool(forKey: Key.finishRemindersEnabled) }
        set { defaults.set(newValue, forKey: Key.finishRemindersEnabled) }
    }
}

@MainActor
final class FakeWalkReminderPreferences: WalkReminderPreferences {
    var finishRemindersEnabled: Bool

    init(finishRemindersEnabled: Bool = false) {
        self.finishRemindersEnabled = finishRemindersEnabled
    }
}
