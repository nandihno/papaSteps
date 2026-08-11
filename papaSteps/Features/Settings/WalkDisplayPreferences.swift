import Foundation
import Observation

enum WalkDistanceUnit: String, CaseIterable, Codable, Equatable, Sendable {
    case metric
    case imperial

    var displayName: String {
        switch self {
        case .metric: "Metric"
        case .imperial: "Imperial"
        }
    }
}

enum WalkSpeedDisplay: String, CaseIterable, Codable, Equatable, Sendable {
    case speed
    case pace

    var displayName: String {
        switch self {
        case .speed: "Speed"
        case .pace: "Pace"
        }
    }
}

struct WalkDisplayConfiguration: Equatable, Sendable {
    var distanceUnit: WalkDistanceUnit
    var speedDisplay: WalkSpeedDisplay

    static let metricSpeed = WalkDisplayConfiguration(
        distanceUnit: .metric,
        speedDisplay: .speed
    )
}

@MainActor
@Observable
final class WalkDisplayPreferences {
    private enum Key {
        static let distanceUnit = "walkDisplay.distanceUnit"
        static let speedDisplay = "walkDisplay.speedDisplay"
    }

    private let defaults: UserDefaults

    var distanceUnit: WalkDistanceUnit {
        didSet { defaults.set(distanceUnit.rawValue, forKey: Key.distanceUnit) }
    }

    var speedDisplay: WalkSpeedDisplay {
        didSet { defaults.set(speedDisplay.rawValue, forKey: Key.speedDisplay) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        distanceUnit = WalkDistanceUnit(
            rawValue: defaults.string(forKey: Key.distanceUnit) ?? ""
        ) ?? .metric
        speedDisplay = WalkSpeedDisplay(
            rawValue: defaults.string(forKey: Key.speedDisplay) ?? ""
        ) ?? .speed
    }

    var configuration: WalkDisplayConfiguration {
        WalkDisplayConfiguration(
            distanceUnit: distanceUnit,
            speedDisplay: speedDisplay
        )
    }
}
