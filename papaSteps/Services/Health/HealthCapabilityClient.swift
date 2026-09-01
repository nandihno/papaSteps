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
    case backgroundDeliveryUnavailable

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
        case .backgroundDeliveryUnavailable:
            "Apple Health would not enable background updates for workouts. Automatic import stays off; you can still import walks manually."
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

/// One "walking workouts changed" notification from Apple Health.
///
/// HealthKit keeps the app awake — including after a background launch — only
/// until the notification is acknowledged, and re-delivers anything that was
/// never acknowledged. Consumers must therefore call ``acknowledge()`` exactly
/// once, on every path out of processing.
struct HealthWorkoutChange: Sendable {
    private let completion: @Sendable () -> Void

    init(completion: @escaping @Sendable () -> Void) {
        self.completion = completion
    }

    func acknowledge() {
        completion()
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
    func enableWalkingWorkoutBackgroundDelivery() async throws
    func disableWalkingWorkoutBackgroundDelivery() async
    /// Notifications that Apple Health's walking workouts changed.
    ///
    /// The stream stays open until its task is cancelled. Each element must be
    /// acknowledged; see ``HealthWorkoutChange``.
    func walkingWorkoutChanges() -> AsyncStream<HealthWorkoutChange>
}

@MainActor
protocol HealthPreferencesProviding: AnyObject {
    var insightsRequested: Bool { get set }
    var workoutExportEnabled: Bool { get set }
    var workoutAutoImportEnabled: Bool { get set }
    /// When auto-import was switched on. Auto-import never reaches back before
    /// this date, so enabling it does not silently backfill old history; the
    /// manual import screen stays the way to pull in anything older.
    var workoutAutoImportSince: Date? { get set }
}

@MainActor
final class LiveHealthPreferences: HealthPreferencesProviding {
    private enum Key {
        static let insightsRequested = "health.insights.requested"
        static let workoutExportEnabled = "health.workout.export.enabled"
        static let workoutAutoImportEnabled = "health.workout.autoImport.enabled"
        static let workoutAutoImportSince = "health.workout.autoImport.since"
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

    var workoutAutoImportEnabled: Bool {
        get { defaults.bool(forKey: Key.workoutAutoImportEnabled) }
        set { defaults.set(newValue, forKey: Key.workoutAutoImportEnabled) }
    }

    var workoutAutoImportSince: Date? {
        get { defaults.object(forKey: Key.workoutAutoImportSince) as? Date }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Key.workoutAutoImportSince)
            } else {
                defaults.removeObject(forKey: Key.workoutAutoImportSince)
            }
        }
    }
}

@MainActor
final class FakeHealthPreferences: HealthPreferencesProviding {
    var insightsRequested: Bool
    var workoutExportEnabled: Bool
    var workoutAutoImportEnabled: Bool
    var workoutAutoImportSince: Date?

    init(
        insightsRequested: Bool = false,
        workoutExportEnabled: Bool = false,
        workoutAutoImportEnabled: Bool = false,
        workoutAutoImportSince: Date? = nil
    ) {
        self.insightsRequested = insightsRequested
        self.workoutExportEnabled = workoutExportEnabled
        self.workoutAutoImportEnabled = workoutAutoImportEnabled
        self.workoutAutoImportSince = workoutAutoImportSince
    }
}

@MainActor
final class LiveHealthCapabilityClient: HealthDataProviding {
    private enum Metadata {
        static let localWalkID = "org.nando.papaSteps.localWalkID"
    }

    /// The gap that ends a route segment, borrowed from the live recorder so an
    /// imported walk breaks its line exactly where a recorded one would.
    private static let maximumRouteGap = TrackingConfiguration().maximumRouteGap

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
        var locations: [CLLocation] = []
        for route in routes {
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
                locations.append(location)
            }
        }
        // Segments are decided after ordering the whole walk, not per route:
        // a pause leaves a hole in one series rather than starting a new one,
        // and several routes can interleave in time.
        locations.sort { $0.timestamp < $1.timestamp }

        var points: [NewTrackPoint] = []
        var previousTimestamp: Date?
        for location in locations {
            let startsNewSegment = previousTimestamp.map {
                location.timestamp.timeIntervalSince($0) > Self.maximumRouteGap
            } ?? true
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
            previousTimestamp = location.timestamp
        }
        return HealthWalkingWorkoutImport(
            workout: healthWalkingWorkout(from: workout),
            routePoints: points
        )
    }

    func enableWalkingWorkoutBackgroundDelivery() async throws {
        guard isAvailable else { throw HealthDataError.unavailable }
        do {
            // Workouts are one of the few types that support `.immediate`, so a
            // finished Apple Watch walk wakes the app instead of waiting an hour.
            try await healthStore.enableBackgroundDelivery(
                for: HKObjectType.workoutType(),
                frequency: .immediate
            )
        } catch {
            throw HealthDataError.backgroundDeliveryUnavailable
        }

        // A watch walk's location series transfers separately from — and often
        // after — the workout itself, so the workout notification alone can
        // arrive while the route is still missing. Waking for the route too is
        // what lets the import fill it in. Best effort: losing this costs a
        // delayed route, not the walk, so it must not fail the whole opt-in.
        try? await healthStore.enableBackgroundDelivery(
            for: HKSeriesType.workoutRoute(),
            frequency: .immediate
        )
    }

    func disableWalkingWorkoutBackgroundDelivery() async {
        guard isAvailable else { return }
        try? await healthStore.disableBackgroundDelivery(
            for: HKObjectType.workoutType()
        )
        try? await healthStore.disableBackgroundDelivery(
            for: HKSeriesType.workoutRoute()
        )
    }

    func walkingWorkoutChanges() -> AsyncStream<HealthWorkoutChange> {
        guard isAvailable else { return AsyncStream { $0.finish() } }
        let healthStore = healthStore

        return AsyncStream { continuation in
            // Routes cannot be narrowed to walking workouts the way workouts
            // can, so that observer runs unpredicated; a pass it triggers for
            // some other activity's route simply finds nothing to do.
            let queries = [
                HKObserverQuery(
                    sampleType: HKObjectType.workoutType(),
                    predicate: HKQuery.predicateForWorkouts(with: .walking),
                    updateHandler: Self.changeHandler(for: continuation)
                ),
                HKObserverQuery(
                    sampleType: HKSeriesType.workoutRoute(),
                    predicate: nil,
                    updateHandler: Self.changeHandler(for: continuation)
                )
            ]

            nonisolated(unsafe) let observedQueries = queries
            continuation.onTermination = { _ in
                for query in observedQueries {
                    healthStore.stop(query)
                }
            }
            for query in queries {
                healthStore.execute(query)
            }
        }
    }

    private static func changeHandler(
        for continuation: AsyncStream<HealthWorkoutChange>.Continuation
    ) -> @Sendable (HKObserverQuery, @escaping HKObserverQueryCompletionHandler, (any Error)?) -> Void {
        { _, completionHandler, error in
            nonisolated(unsafe) let completionHandler = completionHandler
            guard error == nil else {
                // Acknowledge anyway; an unanswered notification stalls
                // every later delivery.
                completionHandler()
                return
            }
            // The handler travels downstream rather than firing here, so
            // HealthKit keeps the app alive until the import has finished.
            let change = HealthWorkoutChange(
                completion: { completionHandler() }
            )
            if case .enqueued = continuation.yield(change) {
                return
            }
            change.acknowledge()
        }
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
    private(set) var backgroundDeliveryEnableCount = 0
    private(set) var isBackgroundDeliveryEnabled = false
    var backgroundDeliveryError: (any Error)?
    private var workoutsByWalkID: [UUID: UUID] = [:]
    private var changeContinuation: AsyncStream<HealthWorkoutChange>.Continuation?

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

    func enableWalkingWorkoutBackgroundDelivery() async throws {
        backgroundDeliveryEnableCount += 1
        if let backgroundDeliveryError { throw backgroundDeliveryError }
        guard isAvailable else { throw HealthDataError.unavailable }
        isBackgroundDeliveryEnabled = true
    }

    func disableWalkingWorkoutBackgroundDelivery() async {
        isBackgroundDeliveryEnabled = false
    }

    func walkingWorkoutChanges() -> AsyncStream<HealthWorkoutChange> {
        AsyncStream { continuation in
            changeContinuation = continuation
        }
    }

    /// Simulates Apple Health reporting new walking workouts, and resolves once
    /// the consumer has acknowledged the notification.
    func emitWalkingWorkoutChange() async {
        guard let changeContinuation else { return }
        await withCheckedContinuation { (resume: CheckedContinuation<Void, Never>) in
            nonisolated(unsafe) let resume = resume
            changeContinuation.yield(
                HealthWorkoutChange(completion: { resume.resume() })
            )
        }
    }

    func externallyCreateWorkout(for walkID: UUID) -> UUID {
        if let existing = workoutsByWalkID[walkID] { return existing }
        let workoutID = UUID()
        workoutsByWalkID[walkID] = workoutID
        workoutCreationCount += 1
        return workoutID
    }
}
