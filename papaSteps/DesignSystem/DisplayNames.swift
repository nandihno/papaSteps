import SwiftUI

/// Plain-English labels for every enum that reaches the interface.
///
/// Views must never show a `rawValue`. Raw values are storage identifiers in
/// camelCase; users read sentences. Each type also declares the semantic color
/// its state carries, so a screen never has to decide what "denied" looks like.
///
/// Covered by `DisplayNameTests`, which fails if any label still looks like a
/// case name.
protocol UserFacingState {
    /// Sentence-case label shown to the user.
    var displayName: String { get }
    /// Two-or-three word variant for chips and other tight spaces. Defaults to
    /// `displayName`; override only where the full label is a sentence.
    var shortDisplayName: String { get }
    /// The semantic color for this state.
    var signalColor: Color { get }
}

extension UserFacingState {
    var shortDisplayName: String { displayName }
}

// MARK: - Permissions

extension PermissionAuthorizationState: UserFacingState {
    var displayName: String {
        switch self {
        case .notDetermined: "Not requested yet"
        case .authorized: "Allowed"
        case .denied: "Turned off"
        case .restricted: "Not allowed on this iPhone"
        case .unavailable: "Not available"
        }
    }

    var shortDisplayName: String {
        switch self {
        case .notDetermined: "Not requested"
        case .authorized: "Allowed"
        case .denied: "Turned off"
        case .restricted: "Not allowed"
        case .unavailable: "Not available"
        }
    }

    var signalColor: Color {
        switch self {
        case .authorized: .signalGood
        case .denied: .signalAlert
        case .notDetermined, .restricted, .unavailable: .signalNeutral
        }
    }
}

extension LocationAuthorizationState: UserFacingState {
    var displayName: String {
        switch self {
        case .notDetermined: "Not requested yet"
        case .whenInUse: "Allowed while using the app"
        case .always: "Always allowed"
        case .denied: "Turned off"
        case .restricted: "Not allowed on this iPhone"
        }
    }

    var shortDisplayName: String {
        switch self {
        case .notDetermined: "Not requested"
        case .whenInUse: "While using"
        case .always: "Always"
        case .denied: "Turned off"
        case .restricted: "Not allowed"
        }
    }

    var signalColor: Color {
        switch self {
        case .whenInUse, .always: .signalGood
        case .denied: .signalAlert
        case .notDetermined, .restricted: .signalNeutral
        }
    }
}

extension LocationAccuracyState: UserFacingState {
    var displayName: String {
        switch self {
        case .full: "Precise"
        case .reduced: "Approximate only"
        case .unknown: "Checking"
        }
    }

    var signalColor: Color {
        switch self {
        case .full: .signalGood
        case .reduced: .signalCaution
        case .unknown: .signalNeutral
        }
    }
}

extension CapabilityAvailability: UserFacingState {
    var displayName: String {
        switch self {
        case .available: "Available"
        case .permissionRequired: "Needs permission"
        case .limited: "Limited"
        case .unavailable: "Not available"
        case .checking: "Checking"
        }
    }

    var signalColor: Color {
        switch self {
        case .available: .signalGood
        case .permissionRequired: .brandGreenInk
        case .limited: .signalCaution
        case .unavailable, .checking: .signalNeutral
        }
    }

    var symbolName: String {
        switch self {
        case .available: WalkSymbol.good
        case .permissionRequired: WalkSymbol.locked
        case .limited: WalkSymbol.caution
        case .unavailable: WalkSymbol.unavailable
        case .checking: WalkSymbol.checking
        }
    }
}

// MARK: - Data quality and provenance

extension RouteQuality: UserFacingState {
    var displayName: String {
        switch self {
        case .good: "Good route"
        case .degraded: "Partial route"
        case .unavailable: "No route"
        }
    }

    var signalColor: Color {
        switch self {
        case .good: .signalGood
        case .degraded: .signalCaution
        case .unavailable: .signalNeutral
        }
    }
}

extension MetricQuality: UserFacingState {
    var displayName: String {
        switch self {
        case .good: "Good"
        case .degraded: "Approximate"
        case .unavailable: "Not recorded"
        }
    }

    var signalColor: Color {
        switch self {
        case .good: .signalGood
        case .degraded: .signalCaution
        case .unavailable: .signalNeutral
        }
    }
}

extension AltitudeSource: UserFacingState {
    var displayName: String {
        switch self {
        case .barometer: "Barometer"
        case .location: "Estimated from GPS"
        case .unavailable: "Not recorded"
        }
    }

    var signalColor: Color {
        switch self {
        case .barometer: .signalGood
        case .location: .signalCaution
        case .unavailable: .signalNeutral
        }
    }
}

extension DistanceSource: UserFacingState {
    var displayName: String {
        switch self {
        case .route: "GPS route"
        case .pedometer: "Pedometer estimate"
        case .health: "Apple Health"
        case .unavailable: "Not available"
        }
    }

    var signalColor: Color {
        switch self {
        case .route: .signalGood
        case .pedometer, .health: .signalNeutral
        case .unavailable: .signalNeutral
        }
    }
}

extension StepSource: UserFacingState {
    var displayName: String {
        switch self {
        case .motion: "Step counter"
        case .health: "Apple Health"
        case .unavailable: "Not available"
        }
    }

    var signalColor: Color {
        switch self {
        case .motion: .signalGood
        case .health, .unavailable: .signalNeutral
        }
    }
}

// MARK: - Apple Health

extension HealthAccessState: UserFacingState {
    var displayName: String {
        switch self {
        case .unavailable: "Not available"
        case .notRequested: "Not connected"
        case .requested: "Connected"
        }
    }

    var signalColor: Color {
        switch self {
        case .requested: .signalHealth
        case .notRequested, .unavailable: .signalNeutral
        }
    }
}

extension HealthEnrichmentStatus: UserFacingState {
    var displayName: String {
        switch self {
        case .notRequested: "Optional"
        case .pending: "Checking…"
        case .completed: "Refreshed"
        case .unavailable: "Unavailable"
        case .failed: "Needs retry"
        }
    }

    var signalColor: Color {
        switch self {
        case .completed: .signalGood
        case .pending, .notRequested, .unavailable: .signalNeutral
        case .failed: .signalCaution
        }
    }
}

extension HealthWorkoutExportStatus: UserFacingState {
    var displayName: String {
        switch self {
        case .disabled: "Workout export is off"
        case .pending: "Saving workout to Apple Health…"
        case .completed: "Workout saved to Apple Health"
        case .failed: "Workout export needs a retry"
        }
    }

    var signalColor: Color {
        switch self {
        case .completed: .signalGood
        case .pending, .disabled: .signalNeutral
        case .failed: .signalCaution
        }
    }

    var symbolName: String {
        switch self {
        case .disabled: "heart.slash"
        case .pending: "arrow.trianglehead.2.clockwise"
        case .completed: WalkSymbol.good
        case .failed: WalkSymbol.alert
        }
    }
}
