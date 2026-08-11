import Foundation

enum RuntimeEnvironment: String, Sendable {
    case device
    case simulator

    static var current: RuntimeEnvironment {
#if targetEnvironment(simulator)
        .simulator
#else
        .device
#endif
    }
}

enum CapabilityAvailability: String, CaseIterable, Sendable {
    case available
    case permissionRequired
    case limited
    case unavailable
    case checking
}

struct CapabilityStatus: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let availability: CapabilityAvailability
    let detail: String
}

enum PermissionAuthorizationState: String, CaseIterable, Codable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case unavailable
}

enum LocationAuthorizationState: String, CaseIterable, Codable, Sendable {
    case notDetermined
    case whenInUse
    case always
    case denied
    case restricted

    var permitsLocation: Bool {
        self == .whenInUse || self == .always
    }
}

enum LocationAccuracyState: String, CaseIterable, Codable, Sendable {
    case full
    case reduced
    case unknown
}

struct LocationFix: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let timestamp: Date
}

struct LocationCapabilitySnapshot: Equatable, Sendable {
    let authorization: LocationAuthorizationState
    let accuracy: LocationAccuracyState
    let latestFix: LocationFix?
}

struct SensorDiagnosticsSnapshot: Equatable, Sendable {
    let environment: RuntimeEnvironment
    let motion: [CapabilityStatus]
    let location: [CapabilityStatus]
    let health: [CapabilityStatus]

    static let checking = SensorDiagnosticsSnapshot(
        environment: .current,
        motion: [
            CapabilityStatus(
                id: "motion.checking",
                title: "Motion",
                availability: .checking,
                detail: "Checking capabilities…"
            )
        ],
        location: [
            CapabilityStatus(
                id: "location.checking",
                title: "Location",
                availability: .checking,
                detail: "Checking authorization…"
            )
        ],
        health: [
            CapabilityStatus(
                id: "health.checking",
                title: "Apple Health",
                availability: .checking,
                detail: "Checking availability…"
            )
        ]
    )
}
