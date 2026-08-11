import Foundation

enum WalkSensorError: LocalizedError, Equatable, Sendable {
    case unavailable(String)
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let metric):
            "\(metric) is unavailable on this device."
        case .queryFailed(let metric):
            "\(metric) could not be reconciled."
        }
    }
}

@MainActor
protocol WalkMotionProviding: AnyObject {
    var authorizationState: PermissionAuthorizationState { get }
    var stepCountingAvailable: Bool { get }
    var pedometerDistanceAvailable: Bool { get }
    var relativeAltitudeAvailable: Bool { get }
    var absoluteAltitudeAvailable: Bool { get }

    func requestAuthorization() async
    func startWalkUpdates(from startDate: Date) -> AsyncStream<WalkMotionEvent>
    func queryPedometer(from startDate: Date, to endDate: Date) async throws -> PedometerSample
    func stopWalkUpdates()
}

@MainActor
protocol WalkLocationProviding: AnyObject {
    var snapshot: LocationCapabilitySnapshot { get }

    func requestWhenInUseAuthorization() async
    func requestTemporaryFullAccuracy() async
    func startWalkUpdates() -> AsyncStream<WalkLocationEvent>
    func stopWalkUpdates()
}
