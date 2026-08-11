@preconcurrency import CoreMotion
import Foundation

@MainActor
protocol MotionCapabilityProviding: AnyObject {
    var authorizationState: PermissionAuthorizationState { get }

    func capabilityStatuses(
        locationAuthorization: LocationAuthorizationState
    ) -> [CapabilityStatus]
    func requestAuthorization() async
}

@MainActor
final class LiveMotionCapabilityClient: MotionCapabilityProviding, WalkMotionProviding {
    private let pedometer = CMPedometer()
    private let activityManager = CMMotionActivityManager()
    private let altimeter = CMAltimeter()
    private var walkContinuation: AsyncStream<WalkMotionEvent>.Continuation?

    var authorizationState: PermissionAuthorizationState {
        switch CMMotionActivityManager.authorizationStatus() {
        case .notDetermined:
            .notDetermined
        case .authorized:
            .authorized
        case .denied:
            .denied
        case .restricted:
            .restricted
        @unknown default:
            .unavailable
        }
    }

    var stepCountingAvailable: Bool {
        CMPedometer.isStepCountingAvailable()
    }

    var pedometerDistanceAvailable: Bool {
        CMPedometer.isDistanceAvailable()
    }

    var relativeAltitudeAvailable: Bool {
        CMAltimeter.isRelativeAltitudeAvailable()
    }

    var absoluteAltitudeAvailable: Bool {
        CMAltimeter.isAbsoluteAltitudeAvailable()
    }

    func capabilityStatuses(
        locationAuthorization: LocationAuthorizationState
    ) -> [CapabilityStatus] {
        let authorization = authorizationState

        return [
            authorizationStatus(authorization),
            hardwareStatus(
                id: "motion.activity",
                title: "Motion activity",
                hardwareAvailable: CMMotionActivityManager.isActivityAvailable(),
                authorization: authorization
            ),
            hardwareStatus(
                id: "motion.steps",
                title: "Step counting",
                hardwareAvailable: CMPedometer.isStepCountingAvailable(),
                authorization: authorization
            ),
            hardwareStatus(
                id: "motion.distance",
                title: "Pedometer distance",
                hardwareAvailable: CMPedometer.isDistanceAvailable(),
                authorization: authorization
            ),
            hardwareStatus(
                id: "motion.pace",
                title: "Pedometer pace",
                hardwareAvailable: CMPedometer.isPaceAvailable(),
                authorization: authorization
            ),
            hardwareStatus(
                id: "motion.cadence",
                title: "Pedometer cadence",
                hardwareAvailable: CMPedometer.isCadenceAvailable(),
                authorization: authorization
            ),
            hardwareStatus(
                id: "motion.floors",
                title: "Floor counting",
                hardwareAvailable: CMPedometer.isFloorCountingAvailable(),
                authorization: authorization
            ),
            hardwareStatus(
                id: "motion.relativeAltitude",
                title: "Relative altitude",
                hardwareAvailable: CMAltimeter.isRelativeAltitudeAvailable(),
                authorization: authorization
            ),
            absoluteAltitudeStatus(
                authorization: authorization,
                locationAuthorization: locationAuthorization
            )
        ]
    }

    func requestAuthorization() async {
        guard authorizationState == .notDetermined else { return }

        let now = Date()
        if CMPedometer.isStepCountingAvailable() {
            await withCheckedContinuation { continuation in
                pedometer.queryPedometerData(
                    from: now.addingTimeInterval(-1),
                    to: now
                ) { @Sendable _, _ in
                    continuation.resume()
                }
            }
        } else if CMMotionActivityManager.isActivityAvailable() {
            await withCheckedContinuation { continuation in
                activityManager.queryActivityStarting(
                    from: now.addingTimeInterval(-1),
                    to: now,
                    to: .main
                ) { @Sendable _, _ in
                    continuation.resume()
                }
            }
        }
    }

    func startWalkUpdates(from startDate: Date) -> AsyncStream<WalkMotionEvent> {
        stopWalkUpdates()
        let relativeStreamID = UUID()

        return AsyncStream { continuation in
            walkContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.stopWalkUpdates()
                }
            }

            if stepCountingAvailable {
                // CMPedometer invokes handlers on its own serial background queue.
                // Explicit @Sendable inference keeps this closure nonisolated instead
                // of inheriting LiveMotionCapabilityClient's MainActor executor.
                pedometer.startUpdates(from: startDate) { @Sendable data, error in
                    if let data {
                        let sample = PedometerSample(
                            startDate: data.startDate,
                            endDate: data.endDate,
                            cumulativeSteps: data.numberOfSteps.intValue,
                            cumulativeDistance: data.distance?.doubleValue,
                            currentPace: data.currentPace?.doubleValue,
                            currentCadence: data.currentCadence?.doubleValue
                        )
                        continuation.yield(.pedometer(sample))
                    } else if error != nil {
                        continuation.yield(
                            .unavailable(.pedometer, "Live pedometer data is unavailable.")
                        )
                    }
                }
            } else {
                continuation.yield(
                    .unavailable(.pedometer, "Step counting is not supported on this device.")
                )
            }

            if relativeAltitudeAvailable {
                altimeter.startRelativeAltitudeUpdates(to: .main) { @Sendable data, error in
                    if let data {
                        continuation.yield(
                            .relativeAltitude(
                                RelativeAltitudeSample(
                                    streamID: relativeStreamID,
                                    timestamp: Date(),
                                    relativeAltitude: data.relativeAltitude.doubleValue
                                )
                            )
                        )
                    } else if error != nil {
                        continuation.yield(
                            .unavailable(.relativeAltitude, "Relative altitude is unavailable.")
                        )
                    }
                }
            } else {
                continuation.yield(
                    .unavailable(
                        .relativeAltitude,
                        "Relative altitude is not supported on this device."
                    )
                )
            }

            if absoluteAltitudeAvailable {
                altimeter.startAbsoluteAltitudeUpdates(to: .main) { @Sendable data, error in
                    if let data {
                        continuation.yield(
                            .absoluteAltitude(
                                AbsoluteAltitudeSample(
                                    timestamp: Date(),
                                    altitude: data.altitude,
                                    accuracy: data.accuracy
                                )
                            )
                        )
                    } else if error != nil {
                        continuation.yield(
                            .unavailable(.absoluteAltitude, "Absolute altitude is unavailable.")
                        )
                    }
                }
            } else {
                continuation.yield(
                    .unavailable(
                        .absoluteAltitude,
                        "Absolute altitude is not supported on this device."
                    )
                )
            }

            if CMMotionActivityManager.isActivityAvailable() {
                activityManager.startActivityUpdates(to: .main) { @Sendable activity in
                    guard let activity else { return }
                    continuation.yield(
                        .activity(
                            WalkMotionActivitySample(
                                timestamp: Date(),
                                activity: Self.classification(for: activity),
                                confidence: Self.confidence(for: activity.confidence)
                            )
                        )
                    )
                }
            }
        }
    }

    func queryPedometer(
        from startDate: Date,
        to endDate: Date
    ) async throws -> PedometerSample {
        guard stepCountingAvailable else {
            throw WalkSensorError.unavailable("Pedometer")
        }

        return try await withCheckedThrowingContinuation { continuation in
            pedometer.queryPedometerData(
                from: startDate,
                to: endDate
            ) { @Sendable data, error in
                if let data {
                    continuation.resume(
                        returning: PedometerSample(
                            startDate: data.startDate,
                            endDate: data.endDate,
                            cumulativeSteps: data.numberOfSteps.intValue,
                            cumulativeDistance: data.distance?.doubleValue,
                            currentPace: data.currentPace?.doubleValue,
                            currentCadence: data.currentCadence?.doubleValue
                        )
                    )
                } else {
                    continuation.resume(
                        throwing: error ?? WalkSensorError.queryFailed("Pedometer")
                    )
                }
            }
        }
    }

    func stopWalkUpdates() {
        pedometer.stopUpdates()
        activityManager.stopActivityUpdates()
        altimeter.stopRelativeAltitudeUpdates()
        altimeter.stopAbsoluteAltitudeUpdates()
        walkContinuation?.finish()
        walkContinuation = nil
    }

    nonisolated private static func classification(
        for activity: CMMotionActivity
    ) -> WalkMotionActivity {
        if activity.stationary { return .stationary }
        if activity.walking { return .walking }
        if activity.running { return .running }
        if activity.cycling { return .cycling }
        if activity.automotive { return .automotive }
        return .unknown
    }

    nonisolated private static func confidence(
        for confidence: CMMotionActivityConfidence
    ) -> WalkMotionConfidence {
        switch confidence {
        case .low:
            .low
        case .medium:
            .medium
        case .high:
            .high
        @unknown default:
            .low
        }
    }

    private func authorizationStatus(
        _ authorization: PermissionAuthorizationState
    ) -> CapabilityStatus {
        switch authorization {
        case .authorized:
            CapabilityStatus(
                id: "motion.authorization",
                title: "Motion access",
                availability: .available,
                detail: "Authorized"
            )
        case .notDetermined:
            CapabilityStatus(
                id: "motion.authorization",
                title: "Motion access",
                availability: .permissionRequired,
                detail: "Not requested. Access is requested from this diagnostics screen or when starting a walk."
            )
        case .denied:
            CapabilityStatus(
                id: "motion.authorization",
                title: "Motion access",
                availability: .permissionRequired,
                detail: "Denied. Enable Motion & Fitness access in Settings to use step and motion metrics."
            )
        case .restricted:
            CapabilityStatus(
                id: "motion.authorization",
                title: "Motion access",
                availability: .unavailable,
                detail: "Restricted on this device."
            )
        case .unavailable:
            CapabilityStatus(
                id: "motion.authorization",
                title: "Motion access",
                availability: .unavailable,
                detail: "The authorization state is unavailable."
            )
        }
    }

    private func hardwareStatus(
        id: String,
        title: String,
        hardwareAvailable: Bool,
        authorization: PermissionAuthorizationState
    ) -> CapabilityStatus {
        guard hardwareAvailable else {
            return CapabilityStatus(
                id: id,
                title: title,
                availability: .unavailable,
                detail: "Not supported by this device or simulator."
            )
        }

        switch authorization {
        case .authorized:
            return CapabilityStatus(
                id: id,
                title: title,
                availability: .available,
                detail: "Supported and ready."
            )
        case .notDetermined:
            return CapabilityStatus(
                id: id,
                title: title,
                availability: .permissionRequired,
                detail: "Hardware is supported; Motion access has not been requested."
            )
        case .denied:
            return CapabilityStatus(
                id: id,
                title: title,
                availability: .permissionRequired,
                detail: "Hardware is supported; Motion access is denied."
            )
        case .restricted:
            return CapabilityStatus(
                id: id,
                title: title,
                availability: .unavailable,
                detail: "Hardware is supported, but Motion access is restricted."
            )
        case .unavailable:
            return CapabilityStatus(
                id: id,
                title: title,
                availability: .unavailable,
                detail: "Capability could not be determined."
            )
        }
    }

    private func absoluteAltitudeStatus(
        authorization: PermissionAuthorizationState,
        locationAuthorization: LocationAuthorizationState
    ) -> CapabilityStatus {
        guard locationAuthorization.permitsLocation else {
            return CapabilityStatus(
                id: "motion.absoluteAltitude",
                title: "Absolute altitude",
                availability: .permissionRequired,
                detail: "Location access is required before absolute-altitude hardware support can be assessed."
            )
        }

        return hardwareStatus(
            id: "motion.absoluteAltitude",
            title: "Absolute altitude",
            hardwareAvailable: CMAltimeter.isAbsoluteAltitudeAvailable(),
            authorization: authorization
        )
    }
}

@MainActor
final class FakeMotionCapabilityClient: MotionCapabilityProviding, WalkMotionProviding {
    var authorizationState: PermissionAuthorizationState
    var statuses: [CapabilityStatus]
    var walkEvents: [WalkMotionEvent]
    var reconciliationSample: PedometerSample?
    private(set) var startWalkUpdatesCallCount = 0
    private(set) var stopWalkUpdatesCallCount = 0

    init(
        authorizationState: PermissionAuthorizationState = .authorized,
        statuses: [CapabilityStatus] = [
            CapabilityStatus(
                id: "motion.fake",
                title: "Motion sensors",
                availability: .available,
                detail: "Provided by an in-memory fake."
            )
        ],
        walkEvents: [WalkMotionEvent] = [],
        reconciliationSample: PedometerSample? = nil
    ) {
        self.authorizationState = authorizationState
        self.statuses = statuses
        self.walkEvents = walkEvents
        self.reconciliationSample = reconciliationSample
    }

    var stepCountingAvailable: Bool { true }
    var pedometerDistanceAvailable: Bool { true }
    var relativeAltitudeAvailable: Bool { true }
    var absoluteAltitudeAvailable: Bool { true }

    func capabilityStatuses(
        locationAuthorization: LocationAuthorizationState
    ) -> [CapabilityStatus] {
        statuses
    }

    func requestAuthorization() async {
        authorizationState = .authorized
    }

    func startWalkUpdates(from startDate: Date) -> AsyncStream<WalkMotionEvent> {
        startWalkUpdatesCallCount += 1
        let events = walkEvents
        return AsyncStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    func queryPedometer(
        from startDate: Date,
        to endDate: Date
    ) async throws -> PedometerSample {
        if let reconciliationSample {
            return reconciliationSample
        }
        return PedometerSample(
            startDate: startDate,
            endDate: endDate,
            cumulativeSteps: 0,
            cumulativeDistance: 0,
            currentPace: nil,
            currentCadence: nil
        )
    }

    func stopWalkUpdates() {
        stopWalkUpdatesCallCount += 1
    }
}
