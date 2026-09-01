@preconcurrency import CoreLocation
import Foundation

@MainActor
protocol LocationCapabilityProviding: AnyObject {
    var snapshot: LocationCapabilitySnapshot { get }

    func requestWhenInUseAuthorization() async
    func requestTemporaryFullAccuracy() async
    func refreshLocation() async
}

@MainActor
final class LiveLocationCapabilityClient: NSObject, LocationCapabilityProviding, WalkLocationProviding, CLLocationManagerDelegate {
    private let manager: CLLocationManager
    private var latestFix: LocationFix?
    private var authorizationContinuation: CheckedContinuation<Void, Never>?
    private var locationContinuation: CheckedContinuation<Void, Never>?
    private var walkContinuation: AsyncStream<WalkLocationEvent>.Continuation?
    private var backgroundActivitySession: CLBackgroundActivitySession?

    override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
    }

    var snapshot: LocationCapabilitySnapshot {
        LocationCapabilitySnapshot(
            authorization: authorizationState(for: manager.authorizationStatus),
            accuracy: accuracyState,
            latestFix: latestFix
        )
    }

    func requestWhenInUseAuthorization() async {
        guard manager.authorizationStatus == .notDetermined else { return }

        await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }

    }

    func requestTemporaryFullAccuracy() async {
        guard snapshot.authorization.permitsLocation,
              manager.accuracyAuthorization == .reducedAccuracy else {
            return
        }

        await withCheckedContinuation { continuation in
            manager.requestTemporaryFullAccuracyAuthorization(
                withPurposeKey: "RouteRecording"
            ) { @Sendable _ in
                continuation.resume()
            }
        }

    }

    func refreshLocation() async {
        guard snapshot.authorization.permitsLocation,
              locationContinuation == nil else {
            return
        }

        await withCheckedContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    func startWalkUpdates() -> AsyncStream<WalkLocationEvent> {
        stopWalkUpdates()

        return AsyncStream { continuation in
            walkContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.stopWalkUpdates()
                }
            }

            continuation.yield(
                .authorization(snapshot.authorization, snapshot.accuracy)
            )

            if snapshot.authorization.permitsLocation {
                beginBackgroundActivityIfNeeded()
                manager.startUpdatingLocation()
            }
        }
    }

    func stopWalkUpdates() {
        manager.stopUpdatingLocation()
        backgroundActivitySession?.invalidate()
        backgroundActivitySession = nil
        walkContinuation?.finish()
        walkContinuation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined else { return }
        authorizationContinuation?.resume()
        authorizationContinuation = nil
        walkContinuation?.yield(
            .authorization(snapshot.authorization, snapshot.accuracy)
        )
        if walkContinuation != nil {
            if snapshot.authorization.permitsLocation {
                beginBackgroundActivityIfNeeded()
                manager.startUpdatingLocation()
            } else {
                manager.stopUpdatingLocation()
                backgroundActivitySession?.invalidate()
                backgroundActivitySession = nil
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let samples = LocationSampleBatch.samples(
            from: locations,
            accuracyAuthorization: accuracyState
        )
        if let sample = samples.last {
            latestFix = LocationFix(
                latitude: sample.coordinate.latitude,
                longitude: sample.coordinate.longitude,
                horizontalAccuracy: sample.horizontalAccuracy,
                timestamp: sample.timestamp
            )
        }
        for sample in samples {
            walkContinuation?.yield(.location(sample))
        }
        resumeLocationRequest()
    }

    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        guard walkContinuation != nil, snapshot.authorization.permitsLocation else { return }
        manager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        if !LocationFailurePolicy.isTransient(error) {
            walkContinuation?.yield(.unavailable("Location is temporarily unavailable."))
        }
        resumeLocationRequest()
    }

    private var accuracyState: LocationAccuracyState {
        guard snapshotAuthorizationPermitsLocation else { return .unknown }

        return switch manager.accuracyAuthorization {
        case .fullAccuracy:
            .full
        case .reducedAccuracy:
            .reduced
        @unknown default:
            .unknown
        }
    }

    private var snapshotAuthorizationPermitsLocation: Bool {
        authorizationState(for: manager.authorizationStatus).permitsLocation
    }

    private func authorizationState(
        for status: CLAuthorizationStatus
    ) -> LocationAuthorizationState {
        switch status {
        case .notDetermined:
            .notDetermined
        case .authorizedWhenInUse:
            .whenInUse
        case .authorizedAlways:
            .always
        case .denied:
            .denied
        case .restricted:
            .restricted
        @unknown default:
            .restricted
        }
    }

    private func resumeLocationRequest() {
        locationContinuation?.resume()
        locationContinuation = nil
    }

    private func beginBackgroundActivityIfNeeded() {
        guard backgroundActivitySession == nil else { return }
        backgroundActivitySession = CLBackgroundActivitySession()
    }
}

enum LocationSampleBatch {
    static func samples(
        from locations: [CLLocation],
        accuracyAuthorization: LocationAccuracyState
    ) -> [WalkLocationSample] {
        locations.map { location in
            WalkLocationSample(
                coordinate: WalkCoordinate(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                ),
                timestamp: location.timestamp,
                altitude: location.altitude,
                horizontalAccuracy: location.horizontalAccuracy,
                verticalAccuracy: location.verticalAccuracy,
                speed: location.speed,
                speedAccuracy: location.speedAccuracy,
                course: location.course,
                courseAccuracy: location.courseAccuracy,
                accuracyAuthorization: accuracyAuthorization
            )
        }
    }
}

enum LocationFailurePolicy {
    static func isTransient(_ error: any Error) -> Bool {
        let error = error as NSError
        return error.domain == kCLErrorDomain
            && error.code == CLError.Code.locationUnknown.rawValue
    }
}

@MainActor
final class FakeLocationCapabilityClient: LocationCapabilityProviding, WalkLocationProviding {
    var snapshot: LocationCapabilitySnapshot
    var walkEvents: [WalkLocationEvent]
    private(set) var startWalkUpdatesCallCount = 0
    private(set) var stopWalkUpdatesCallCount = 0

    init(
        snapshot: LocationCapabilitySnapshot = LocationCapabilitySnapshot(
            authorization: .whenInUse,
            accuracy: .full,
            latestFix: LocationFix(
                latitude: -37.8136,
                longitude: 144.9631,
                horizontalAccuracy: 8,
                timestamp: Date()
            )
        ),
        walkEvents: [WalkLocationEvent] = []
    ) {
        self.snapshot = snapshot
        self.walkEvents = walkEvents
    }

    func requestWhenInUseAuthorization() async {
        snapshot = LocationCapabilitySnapshot(
            authorization: .whenInUse,
            accuracy: snapshot.accuracy == .unknown ? .full : snapshot.accuracy,
            latestFix: snapshot.latestFix
        )
    }

    func requestTemporaryFullAccuracy() async {
        snapshot = LocationCapabilitySnapshot(
            authorization: snapshot.authorization,
            accuracy: .full,
            latestFix: snapshot.latestFix
        )
    }

    func refreshLocation() async {}

    func startWalkUpdates() -> AsyncStream<WalkLocationEvent> {
        startWalkUpdatesCallCount += 1
        let snapshot = snapshot
        let events = walkEvents
        return AsyncStream { continuation in
            continuation.yield(
                .authorization(snapshot.authorization, snapshot.accuracy)
            )
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    func stopWalkUpdates() {
        stopWalkUpdatesCallCount += 1
    }
}
