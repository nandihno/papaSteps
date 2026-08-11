import CoreLocation
import Foundation
import HealthKit

enum HealthDataError: LocalizedError, Equatable {
    case unavailable
    case authorizationFailed
    case workoutSharingDenied
    case invalidWorkoutInterval
    case routeBuilderUnavailable
    case workoutNotCreated
    case workoutNotFound

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Apple Health is not available on this device."
        case .authorizationFailed:
            "Apple Health access could not be requested."
        case .workoutSharingDenied:
            "Apple Health is not allowing papaSteps to save workouts, walking distance, and workout routes. Review papaSteps write permissions in Apple Health, then try again."
        case .invalidWorkoutInterval:
            "The saved walk has an invalid time interval and cannot be exported to Apple Health."
        case .routeBuilderUnavailable:
            "Apple Health could not prepare the workout route."
        case .workoutNotCreated:
            "The Apple Health workout could not be created."
        case .workoutNotFound:
            "That walking workout is no longer available in Apple Health."
        }
    }
}

enum HealthWorkoutExportStage: String, Equatable, Sendable {
    case existingWorkoutLookup
    case beginCollection
    case addMetadata
    case addDistance
    case addRoute
    case endCollection
    case finishWorkout

    var displayName: String {
        switch self {
        case .existingWorkoutLookup: "existing-workout check"
        case .beginCollection: "workout start"
        case .addMetadata: "workout metadata"
        case .addDistance: "walking distance"
        case .addRoute: "workout route"
        case .endCollection: "workout end"
        case .finishWorkout: "workout save"
        }
    }
}

struct HealthWorkoutExportError: LocalizedError, Equatable, Sendable {
    let stage: HealthWorkoutExportStage
    let underlyingDomain: String
    let underlyingCode: Int

    var errorDescription: String? {
        "Apple Health rejected the \(stage.displayName) (\(underlyingDomain) \(underlyingCode)). The local walk is safe; try the export again."
    }
}

struct HealthWorkoutPayload: Equatable, Sendable {
    let distanceMeters: Double?
    let distanceStartDate: Date?
    let routePoints: [NewTrackPoint]

    init(input: HealthWalkInput) throws {
        let duration = input.endDate.timeIntervalSince(input.startDate)
        guard duration > 0, duration.isFinite else {
            throw HealthDataError.invalidWorkoutInterval
        }

        if let distance = input.displayDistance,
           distance > 0,
           distance.isFinite {
            // HKWorkoutBuilder requires added samples to begin after its own
            // start date. Keep the sample representative of the full walk
            // while satisfying that strict ordering contract.
            distanceMeters = distance
            distanceStartDate = input.startDate.addingTimeInterval(
                min(0.001, duration / 2)
            )
        } else {
            distanceMeters = nil
            distanceStartDate = nil
        }

        let validPoints = input.trackPoints
            .filter { point in
                point.isAccepted
                    && point.timestamp >= input.startDate
                    && point.timestamp <= input.endDate
                    && point.latitude.isFinite
                    && (-90...90).contains(point.latitude)
                    && point.longitude.isFinite
                    && (-180...180).contains(point.longitude)
                    && point.altitude.isFinite
                    && point.horizontalAccuracy.isFinite
                    && point.horizontalAccuracy >= 0
                    && point.verticalAccuracy.isFinite
            }
            .sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp < rhs.timestamp
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        routePoints = validPoints.reduce(into: []) { result, point in
            guard result.last?.timestamp != point.timestamp else { return }
            result.append(point)
        }
    }
}

@MainActor
protocol HealthCapabilityProviding: AnyObject {
    func capabilityStatuses() -> [CapabilityStatus]
}

@MainActor
protocol HealthDataProviding: HealthCapabilityProviding {
    var isAvailable: Bool { get }

    func requestAuthorization(includeWorkoutWrite: Bool) async throws
    func fetchEnrichment(
        for input: HealthWalkInput,
        at date: Date
    ) async throws -> WalkHealthEnrichment
    func ensureWorkout(for input: HealthWalkInput) async throws -> UUID
    func requestWalkingWorkoutReadAuthorization() async throws
    func walkingWorkouts(since startDate: Date, limit: Int) async throws
        -> [HealthWalkingWorkout]
    func walkingWorkoutImport(id: UUID) async throws
        -> HealthWalkingWorkoutImport
}

@MainActor
protocol HealthPreferencesProviding: AnyObject {
    var insightsRequested: Bool { get set }
    var workoutExportEnabled: Bool { get set }
}

@MainActor
final class LiveHealthPreferences: HealthPreferencesProviding {
    private enum Key {
        static let insightsRequested = "health.insights.requested"
        static let workoutExportEnabled = "health.workout.export.enabled"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var insightsRequested: Bool {
        get { defaults.bool(forKey: Key.insightsRequested) }
        set { defaults.set(newValue, forKey: Key.insightsRequested) }
    }

    var workoutExportEnabled: Bool {
        get { defaults.bool(forKey: Key.workoutExportEnabled) }
        set { defaults.set(newValue, forKey: Key.workoutExportEnabled) }
    }
}

@MainActor
final class FakeHealthPreferences: HealthPreferencesProviding {
    var insightsRequested: Bool
    var workoutExportEnabled: Bool

    init(
        insightsRequested: Bool = false,
        workoutExportEnabled: Bool = false
    ) {
        self.insightsRequested = insightsRequested
        self.workoutExportEnabled = workoutExportEnabled
    }
}

@MainActor
final class LiveHealthCapabilityClient: HealthDataProviding {
    private enum Metadata {
        static let localWalkID = "org.nando.papaSteps.localWalkID"
    }

    private let healthStore: HKHealthStore

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func capabilityStatuses() -> [CapabilityStatus] {
        if isAvailable {
            [
                CapabilityStatus(
                    id: "health.availability",
                    title: "Apple Health",
                    availability: .available,
                    detail: "Available for optional post-walk insights, walking-workout import, and workout export. Read access is privacy-preserving, so empty data cannot be distinguished from declined access."
                )
            ]
        } else {
            [
                CapabilityStatus(
                    id: "health.availability",
                    title: "Apple Health",
                    availability: .unavailable,
                    detail: "Apple Health is not available on this device or simulator."
                )
            ]
        }
    }

    func requestAuthorization(includeWorkoutWrite: Bool) async throws {
        guard isAvailable else { throw HealthDataError.unavailable }

        var readTypes: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.walkingAsymmetryPercentage),
            HKQuantityType(.stepCount),
            HKQuantityType(.distanceWalkingRunning)
        ]
        var shareTypes: Set<HKSampleType> = []

        if includeWorkoutWrite {
            let workoutType = HKObjectType.workoutType()
            let routeType = HKSeriesType.workoutRoute()
            let distanceType = HKQuantityType(.distanceWalkingRunning)
            readTypes.insert(workoutType)
            readTypes.insert(routeType)
            shareTypes.insert(workoutType)
            shareTypes.insert(routeType)
            shareTypes.insert(distanceType)
        }

        do {
            try await healthStore.requestAuthorization(
                toShare: shareTypes,
                read: readTypes
            )
        } catch {
            throw HealthDataError.authorizationFailed
        }

        if includeWorkoutWrite,
           shareTypes.contains(where: {
               healthStore.authorizationStatus(for: $0) != .sharingAuthorized
           }) {
            throw HealthDataError.workoutSharingDenied
        }
    }

    func requestWalkingWorkoutReadAuthorization() async throws {
        guard isAvailable else { throw HealthDataError.unavailable }
        do {
            try await healthStore.requestAuthorization(
                toShare: [],
                read: [
                    HKObjectType.workoutType(),
                    HKSeriesType.workoutRoute(),
                    HKQuantityType(.distanceWalkingRunning)
                ]
            )
        } catch {
            throw HealthDataError.authorizationFailed
        }
    }

    func walkingWorkouts(
        since startDate: Date,
        limit: Int
    ) async throws -> [HealthWalkingWorkout] {
        guard isAvailable else { throw HealthDataError.unavailable }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(with: .walking),
            HKQuery.predicateForSamples(withStart: startDate, end: nil)
        ])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: max(1, limit)
        )
        return try await descriptor.result(for: healthStore)
            .filter { $0.metadata?[Metadata.localWalkID] == nil }
            .map(healthWalkingWorkout(from:))
    }

    func walkingWorkoutImport(id: UUID) async throws
        -> HealthWalkingWorkoutImport {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObject(with: id),
            HKQuery.predicateForWorkouts(with: .walking)
        ])
        let workoutDescriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [],
            limit: 1
        )
        guard let workout = try await workoutDescriptor
            .result(for: healthStore).first else {
            throw HealthDataError.workoutNotFound
        }

        let routeDescriptor = HKSampleQueryDescriptor(
            predicates: [
                .workoutRoute(HKQuery.predicateForObjects(from: workout))
            ],
            sortDescriptors: [SortDescriptor(\.startDate)],
            limit: HKObjectQueryNoLimit
        )
        let routes = try await routeDescriptor.result(for: healthStore)
        var points: [NewTrackPoint] = []
        for route in routes {
            var startsNewSegment = true
            for try await location in HKWorkoutRouteQueryDescriptor(route)
                .results(for: healthStore) {
                guard location.coordinate.latitude.isFinite,
                      (-90...90).contains(location.coordinate.latitude),
                      location.coordinate.longitude.isFinite,
                      (-180...180).contains(location.coordinate.longitude),
                      location.altitude.isFinite,
                      location.horizontalAccuracy.isFinite,
                      location.horizontalAccuracy >= 0,
                      location.verticalAccuracy.isFinite,
                      location.timestamp >= workout.startDate,
                      location.timestamp <= workout.endDate else {
                    continue
                }
                points.append(
                    NewTrackPoint(
                        id: UUID(),
                        timestamp: location.timestamp,
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude,
                        altitude: location.altitude,
                        horizontalAccuracy: location.horizontalAccuracy,
                        verticalAccuracy: location.verticalAccuracy,
                        speed: location.speed >= 0 ? location.speed : nil,
                        speedAccuracy: location.speedAccuracy >= 0
                            ? location.speedAccuracy : nil,
                        course: location.course >= 0 ? location.course : nil,
                        courseAccuracy: location.courseAccuracy >= 0
                            ? location.courseAccuracy : nil,
                        isAccepted: true,
                        rejectionReason: nil,
                        startsNewSegment: startsNewSegment
                    )
                )
                startsNewSegment = false
            }
        }
        return HealthWalkingWorkoutImport(
            workout: healthWalkingWorkout(from: workout),
            routePoints: points.sorted { $0.timestamp < $1.timestamp }
        )
    }

    func fetchEnrichment(
        for input: HealthWalkInput,
        at date: Date
    ) async throws -> WalkHealthEnrichment {
        guard isAvailable else { throw HealthDataError.unavailable }

        async let heartRate = observations(
            type: HKQuantityType(.heartRate),
            unit: HKUnit.count().unitDivided(by: .minute()),
            input: input
        )
        async let asymmetry = observations(
            type: HKQuantityType(.walkingAsymmetryPercentage),
            unit: .percent(),
            input: input
        )
        async let steps = observations(
            type: HKQuantityType(.stepCount),
            unit: .count(),
            input: input
        )
        async let distance = observations(
            type: HKQuantityType(.distanceWalkingRunning),
            unit: .meter(),
            input: input
        )

        return try await HealthMetricsProcessor.enrichment(
            heartRate: heartRate,
            walkingAsymmetry: asymmetry,
            steps: steps,
            distance: distance,
            input: input,
            enrichedAt: date
        )
    }

    func ensureWorkout(for input: HealthWalkInput) async throws -> UUID {
        guard isAvailable else { throw HealthDataError.unavailable }
        if let existing = try await perform(.existingWorkoutLookup, operation: {
            try await existingWorkout(for: input.id)
        }) {
            return existing.uuid
        }

        let payload = try HealthWorkoutPayload(input: input)

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .walking
        configuration.locationType = .outdoor
        let builder = HKWorkoutBuilder(
            healthStore: healthStore,
            configuration: configuration,
            device: .local()
        )
        let routeBuilder: HKWorkoutRouteBuilder?
        if payload.routePoints.isEmpty {
            routeBuilder = nil
        } else {
            guard let builder = builder.seriesBuilder(
                for: HKSeriesType.workoutRoute()
            ) as? HKWorkoutRouteBuilder else {
                throw HealthDataError.routeBuilderUnavailable
            }
            routeBuilder = builder
        }
        let metadata: [String: Any] = [
            Metadata.localWalkID: input.id.uuidString,
            HKMetadataKeyIndoorWorkout: false
        ]

        try await perform(.beginCollection) {
            try await builder.beginCollection(at: input.startDate)
        }
        try await perform(.addMetadata) {
            try await builder.addMetadata(metadata)
        }
        if let distance = payload.distanceMeters,
           let distanceStartDate = payload.distanceStartDate {
            let sample = HKQuantitySample(
                type: HKQuantityType(.distanceWalkingRunning),
                quantity: HKQuantity(unit: .meter(), doubleValue: distance),
                start: distanceStartDate,
                end: input.endDate
            )
            try await perform(.addDistance) {
                try await builder.addSamples([sample])
            }
        }

        let routeLocations = payload.routePoints
            .map { point in
                CLLocation(
                    coordinate: CLLocationCoordinate2D(
                        latitude: point.latitude,
                        longitude: point.longitude
                    ),
                    altitude: point.altitude,
                    horizontalAccuracy: point.horizontalAccuracy,
                    verticalAccuracy: point.verticalAccuracy,
                    timestamp: point.timestamp
                )
            }
        if let routeBuilder {
            try await perform(.addRoute) {
                try await routeBuilder.insertRouteData(routeLocations)
            }
        }

        try await perform(.endCollection) {
            try await builder.endCollection(at: input.endDate)
        }
        guard let workout = try await perform(.finishWorkout, operation: {
            try await builder.finishWorkout()
        }) else {
            throw HealthDataError.workoutNotCreated
        }
        return workout.uuid
    }

    private func perform<Value>(
        _ stage: HealthWorkoutExportStage,
        operation: () async throws -> Value
    ) async throws -> Value {
        do {
            return try await operation()
        } catch let error as HealthDataError {
            throw error
        } catch let error as HealthWorkoutExportError {
            throw error
        } catch {
            let nsError = error as NSError
            throw HealthWorkoutExportError(
                stage: stage,
                underlyingDomain: nsError.domain,
                underlyingCode: nsError.code
            )
        }
    }

    private func observations(
        type: HKQuantityType,
        unit: HKUnit,
        input: HealthWalkInput
    ) async throws -> [HealthQuantityObservation] {
        let datePredicate = HKQuery.predicateForSamples(
            withStart: input.startDate,
            end: input.endDate
        )
        let sourceDescriptor = HKSourceQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: datePredicate)
        )
        let sources = try await sourceDescriptor.result(for: healthStore)
            .sorted { $0.bundleIdentifier < $1.bundleIdentifier }
        var observations: [HealthQuantityObservation] = []

        for source in sources {
            let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                datePredicate,
                HKQuery.predicateForObjects(from: source)
            ])
            let descriptor = HKSampleQueryDescriptor(
                predicates: [
                    .quantitySample(type: type, predicate: predicate)
                ],
                sortDescriptors: [SortDescriptor(\.startDate)],
                limit: HKObjectQueryNoLimit
            )
            let samples = try await descriptor.result(for: healthStore)
            observations.append(contentsOf: samples.map { sample in
                let revision = sample.sourceRevision
                let productType = revision.productType ?? "unknown-device"
                return HealthQuantityObservation(
                    sourceIdentifier: "\(revision.source.bundleIdentifier)|\(productType)",
                    sourceName: revision.source.name,
                    startDate: sample.startDate,
                    endDate: sample.endDate,
                    value: sample.quantity.doubleValue(for: unit)
                )
            })
        }
        return observations
    }

    private func existingWorkout(for walkID: UUID) async throws -> HKWorkout? {
        let metadataPredicate = HKQuery.predicateForObjects(
            withMetadataKey: Metadata.localWalkID,
            allowedValues: [walkID.uuidString]
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(metadataPredicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        return try await descriptor.result(for: healthStore).first
    }

    private func healthWalkingWorkout(from workout: HKWorkout)
        -> HealthWalkingWorkout {
        let distance = workout
            .statistics(for: HKQuantityType(.distanceWalkingRunning))?
            .sumQuantity()?
            .doubleValue(for: .meter())
        let timeZone = workout.metadata?[HKMetadataKeyTimeZone] as? String
        return HealthWalkingWorkout(
            id: workout.uuid,
            startDate: workout.startDate,
            endDate: workout.endDate,
            movingDuration: max(0, workout.duration),
            distanceMeters: distance.flatMap {
                $0.isFinite && $0 > 0 ? $0 : nil
            },
            sourceName: workout.sourceRevision.source.name,
            sourceBundleIdentifier: workout.sourceRevision.source.bundleIdentifier,
            timeZoneIdentifier: timeZone
        )
    }
}

@MainActor
final class FakeHealthCapabilityClient: HealthDataProviding {
    var isAvailable: Bool
    var heartRateObservations: [HealthQuantityObservation]
    var walkingAsymmetryObservations: [HealthQuantityObservation]
    var stepObservations: [HealthQuantityObservation]
    var distanceObservations: [HealthQuantityObservation]
    var authorizationError: (any Error)?
    var enrichmentError: (any Error)?
    var workoutError: (any Error)?
    var walkingWorkoutCandidates: [HealthWalkingWorkout] = []
    var walkingWorkoutImports: [UUID: HealthWalkingWorkoutImport] = [:]

    private(set) var authorizationRequestCount = 0
    private(set) var enrichmentRequestCount = 0
    private(set) var workoutCreationCount = 0
    private(set) var workoutEnsureCount = 0
    private(set) var walkingWorkoutReadAuthorizationCount = 0
    private var workoutsByWalkID: [UUID: UUID] = [:]

    init(
        isAvailable: Bool = true,
        heartRateObservations: [HealthQuantityObservation] = [],
        walkingAsymmetryObservations: [HealthQuantityObservation] = [],
        stepObservations: [HealthQuantityObservation] = [],
        distanceObservations: [HealthQuantityObservation] = []
    ) {
        self.isAvailable = isAvailable
        self.heartRateObservations = heartRateObservations
        self.walkingAsymmetryObservations = walkingAsymmetryObservations
        self.stepObservations = stepObservations
        self.distanceObservations = distanceObservations
    }

    func capabilityStatuses() -> [CapabilityStatus] {
        [
            CapabilityStatus(
                id: "health.fake",
                title: "Apple Health",
                availability: isAvailable ? .available : .unavailable,
                detail: isAvailable
                    ? "Provided by an in-memory fake."
                    : "The fake is configured as unavailable."
            )
        ]
    }

    func requestAuthorization(includeWorkoutWrite: Bool) async throws {
        authorizationRequestCount += 1
        if let authorizationError { throw authorizationError }
        guard isAvailable else { throw HealthDataError.unavailable }
    }

    func fetchEnrichment(
        for input: HealthWalkInput,
        at date: Date
    ) async throws -> WalkHealthEnrichment {
        enrichmentRequestCount += 1
        if let enrichmentError { throw enrichmentError }
        guard isAvailable else { throw HealthDataError.unavailable }
        return HealthMetricsProcessor.enrichment(
            heartRate: heartRateObservations,
            walkingAsymmetry: walkingAsymmetryObservations,
            steps: stepObservations,
            distance: distanceObservations,
            input: input,
            enrichedAt: date
        )
    }

    func ensureWorkout(for input: HealthWalkInput) async throws -> UUID {
        workoutEnsureCount += 1
        if let workoutError { throw workoutError }
        if let existing = workoutsByWalkID[input.id] { return existing }
        let workoutID = UUID()
        workoutsByWalkID[input.id] = workoutID
        workoutCreationCount += 1
        return workoutID
    }

    func requestWalkingWorkoutReadAuthorization() async throws {
        walkingWorkoutReadAuthorizationCount += 1
        if let authorizationError { throw authorizationError }
        guard isAvailable else { throw HealthDataError.unavailable }
    }

    func walkingWorkouts(since startDate: Date, limit: Int) async throws
        -> [HealthWalkingWorkout] {
        Array(
            walkingWorkoutCandidates
                .filter { $0.startDate >= startDate }
                .sorted { $0.startDate > $1.startDate }
                .prefix(max(1, limit))
        )
    }

    func walkingWorkoutImport(id: UUID) async throws
        -> HealthWalkingWorkoutImport {
        guard let imported = walkingWorkoutImports[id] else {
            throw HealthDataError.workoutNotFound
        }
        return imported
    }

    func externallyCreateWorkout(for walkID: UUID) -> UUID {
        if let existing = workoutsByWalkID[walkID] { return existing }
        let workoutID = UUID()
        workoutsByWalkID[walkID] = workoutID
        workoutCreationCount += 1
        return workoutID
    }
}
