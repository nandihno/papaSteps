import Foundation
import Observation

@MainActor
@Observable
final class SensorDiagnosticsStore {
    private(set) var snapshot: SensorDiagnosticsSnapshot = .checking
    private(set) var isWorking = false

    private let motionClient: any MotionCapabilityProviding
    private let locationClient: any LocationCapabilityProviding
    private let healthClient: any HealthCapabilityProviding

    init(
        motionClient: any MotionCapabilityProviding,
        locationClient: any LocationCapabilityProviding,
        healthClient: any HealthCapabilityProviding
    ) {
        self.motionClient = motionClient
        self.locationClient = locationClient
        self.healthClient = healthClient
    }

    var motionAuthorization: PermissionAuthorizationState {
        motionClient.authorizationState
    }

    var locationAuthorization: LocationAuthorizationState {
        locationClient.snapshot.authorization
    }

    var locationAccuracy: LocationAccuracyState {
        locationClient.snapshot.accuracy
    }

    func refresh(requestLocationFix: Bool = false) async {
        isWorking = true
        defer { isWorking = false }

        if requestLocationFix {
            await locationClient.refreshLocation()
        }

        rebuildSnapshot()
    }

    func requestMotionAuthorization() async {
        isWorking = true
        defer { isWorking = false }

        await motionClient.requestAuthorization()
        rebuildSnapshot()
    }

    func requestLocationAuthorization() async {
        isWorking = true
        defer { isWorking = false }

        await locationClient.requestWhenInUseAuthorization()
        await locationClient.refreshLocation()
        rebuildSnapshot()
    }

    func requestTemporaryFullAccuracy() async {
        isWorking = true
        defer { isWorking = false }

        await locationClient.requestTemporaryFullAccuracy()
        await locationClient.refreshLocation()
        rebuildSnapshot()
    }

    private func rebuildSnapshot() {
        let locationSnapshot = locationClient.snapshot

        snapshot = SensorDiagnosticsSnapshot(
            environment: .current,
            motion: motionClient.capabilityStatuses(
                locationAuthorization: locationSnapshot.authorization
            ),
            location: locationStatuses(from: locationSnapshot),
            health: healthClient.capabilityStatuses()
        )
    }

    private func locationStatuses(
        from location: LocationCapabilitySnapshot
    ) -> [CapabilityStatus] {
        [
            authorizationStatus(for: location.authorization),
            accuracyStatus(
                authorization: location.authorization,
                accuracy: location.accuracy
            ),
            fixStatus(
                authorization: location.authorization,
                fix: location.latestFix
            )
        ]
    }

    private func authorizationStatus(
        for authorization: LocationAuthorizationState
    ) -> CapabilityStatus {
        switch authorization {
        case .notDetermined:
            CapabilityStatus(
                id: "location.authorization",
                title: "Location access",
                availability: .permissionRequired,
                detail: "Not requested. Location is requested from this diagnostics screen or when starting a walk."
            )
        case .whenInUse:
            CapabilityStatus(
                id: "location.authorization",
                title: "Location access",
                availability: .available,
                detail: "When In Use access is authorized."
            )
        case .always:
            CapabilityStatus(
                id: "location.authorization",
                title: "Location access",
                availability: .available,
                detail: "Location is authorized. papaSteps does not require Always access for the MVP."
            )
        case .denied:
            CapabilityStatus(
                id: "location.authorization",
                title: "Location access",
                availability: .permissionRequired,
                detail: "Denied. Route, GPS speed, direction, and absolute altitude are affected."
            )
        case .restricted:
            CapabilityStatus(
                id: "location.authorization",
                title: "Location access",
                availability: .unavailable,
                detail: "Restricted on this device."
            )
        }
    }

    private func accuracyStatus(
        authorization: LocationAuthorizationState,
        accuracy: LocationAccuracyState
    ) -> CapabilityStatus {
        guard authorization.permitsLocation else {
            return CapabilityStatus(
                id: "location.accuracy",
                title: "Location accuracy",
                availability: .permissionRequired,
                detail: "Accuracy is reported separately after Location access is granted."
            )
        }

        switch accuracy {
        case .full:
            return CapabilityStatus(
                id: "location.accuracy",
                title: "Location accuracy",
                availability: .available,
                detail: "Precise Location is enabled."
            )
        case .reduced:
            return CapabilityStatus(
                id: "location.accuracy",
                title: "Location accuracy",
                availability: .limited,
                detail: "Reduced accuracy. Route, route distance, GPS speed, and direction need Precise Location."
            )
        case .unknown:
            return CapabilityStatus(
                id: "location.accuracy",
                title: "Location accuracy",
                availability: .checking,
                detail: "Accuracy authorization is not yet available."
            )
        }
    }

    private func fixStatus(
        authorization: LocationAuthorizationState,
        fix: LocationFix?
    ) -> CapabilityStatus {
        guard authorization.permitsLocation else {
            return CapabilityStatus(
                id: "location.fix",
                title: "Current location",
                availability: .permissionRequired,
                detail: "A location fix can be requested after authorization."
            )
        }

        guard let fix else {
            return CapabilityStatus(
                id: "location.fix",
                title: "Current location",
                availability: .checking,
                detail: "No location fix is available yet."
            )
        }

        let coordinate = String(
            format: "%.5f, %.5f",
            fix.latitude,
            fix.longitude
        )
        let accuracy = Measurement(value: fix.horizontalAccuracy, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))

        return CapabilityStatus(
            id: "location.fix",
            title: "Current location",
            availability: fix.horizontalAccuracy >= 0 ? .available : .limited,
            detail: "\(coordinate) · ±\(accuracy)"
        )
    }
}
