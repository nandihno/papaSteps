import Foundation

/// The papaSteps SF Symbol vocabulary.
///
/// One concept means one glyph everywhere. Adding a symbol literal to a view
/// instead of a case here is how a screen ends up using two different icons
/// for elevation gain.
enum WalkSymbol {
    // Metrics
    static let distance = "point.topleft.down.to.point.bottomright.curvepath"
    static let steps = "shoeprints.fill"
    static let movingTime = "timer"
    static let elapsedTime = "clock"
    static let speed = "speedometer"
    static let altitude = "mountain.2.fill"
    static let elevationGain = "arrow.up.forward.square.fill"
    static let direction = "location.north.fill"

    // Capabilities and state
    static let motion = "figure.walk.motion"
    static let location = "location.fill"
    static let locationOff = "location.slash.fill"
    static let precision = "scope"
    static let routeQuality = "dot.radiowaves.up.forward"
    static let health = "heart.fill"
    static let healthDetail = "heart.text.square.fill"
    static let recording = "record.circle"

    // Actions and navigation
    static let disclosure = "chevron.right"
    static let walk = "figure.walk"
    static let walkCircle = "figure.walk.circle.fill"
    static let start = "figure.walk.departure"
    static let finish = "flag.checkered"
    static let finishPrompt = "checkered.flag.circle.fill"
    static let history = "clock.arrow.circlepath"
    static let progress = "chart.line.uptrend.xyaxis"
    static let settings = "gearshape"
    static let diagnostics = "stethoscope"
    static let refresh = "arrow.clockwise"
    static let importWorkouts = "square.and.arrow.down"
    static let privacy = "hand.raised.fill"

    // Status
    static let good = "checkmark.circle.fill"
    static let caution = "exclamationmark.circle.fill"
    static let alert = "exclamationmark.triangle.fill"
    static let locked = "lock.circle.fill"
    static let unavailable = "xmark.circle.fill"
    static let checking = "ellipsis.circle.fill"
    static let information = "info.circle"

    // Progress
    static let streak = "flame.fill"
    static let badge = "medal.fill"
    static let goal = "target"
}
