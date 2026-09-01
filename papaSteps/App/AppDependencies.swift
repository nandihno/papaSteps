import AppIntents
import Foundation
import SwiftData

@MainActor
private final class WalkSessionStoreReference {
    weak var store: WalkSessionStore?
}

@MainActor
final class AppDependencies {
    let modelContainer: ModelContainer
    let walkRepository: any WalkRepository
    let walkSessionStore: WalkSessionStore
    let walkHistoryStore: WalkHistoryStore
    let tabRouter: AppTabRouter
    let progressStore: ProgressStore
    let walkHealthStore: WalkHealthStore
    let healthWorkoutImportStore: HealthWorkoutImportStore
    let healthWorkoutAutoImporter: HealthWorkoutAutoImporter
    let walkDisplayPreferences: WalkDisplayPreferences
    let activityActionHandler: WalkActivityActionHandler?
    let startWalkActionHandler: WalkStartActionHandler?
#if DEBUG
    let sensorDiagnosticsStore: SensorDiagnosticsStore
#endif

    private init(
        modelContainer: ModelContainer,
        walkRepository: any WalkRepository,
        walkSessionStore: WalkSessionStore,
        walkHealthStore: WalkHealthStore,
        healthWorkoutImportStore: HealthWorkoutImportStore,
        healthWorkoutAutoImporter: HealthWorkoutAutoImporter,
        tabRouter: AppTabRouter = AppTabRouter(),
        walkDisplayPreferences: WalkDisplayPreferences = WalkDisplayPreferences(),
        activityActionHandler: WalkActivityActionHandler? = nil,
        startWalkActionHandler: WalkStartActionHandler? = nil,
        sensorDiagnosticsStore: SensorDiagnosticsStore? = nil
    ) {
        self.modelContainer = modelContainer
        self.walkRepository = walkRepository
        self.walkSessionStore = walkSessionStore
        self.walkHealthStore = walkHealthStore
        self.healthWorkoutImportStore = healthWorkoutImportStore
        self.healthWorkoutAutoImporter = healthWorkoutAutoImporter
        self.tabRouter = tabRouter
        self.walkDisplayPreferences = walkDisplayPreferences
        self.activityActionHandler = activityActionHandler
        self.startWalkActionHandler = startWalkActionHandler
        let historyStore = WalkHistoryStore(repository: walkRepository)
        let progressStore = ProgressStore(repository: walkRepository)
        walkHistoryStore = historyStore
        self.progressStore = progressStore
        // A background auto-import can land while History is already on screen,
        // so refresh the derived stores rather than waiting for a scene change.
        healthWorkoutAutoImporter.onWalksImported = { [weak historyStore, weak progressStore] in
            historyStore?.load()
            progressStore?.refresh()
        }
#if DEBUG
        guard let sensorDiagnosticsStore else {
            preconditionFailure("Debug builds require sensor diagnostics dependencies.")
        }
        self.sensorDiagnosticsStore = sensorDiagnosticsStore
#endif
    }

    static func live() throws -> AppDependencies {
        let modelContainer = try PersistenceContainer.make()
        let repository = SwiftDataWalkRepository(modelContainer: modelContainer)
        let healthClient = LiveHealthCapabilityClient()
        let healthPreferences = LiveHealthPreferences()
        let walkHealthStore = WalkHealthStore(
            client: healthClient,
            preferences: healthPreferences,
            repository: repository
        )
        let autoImporter = HealthWorkoutAutoImporter(
            client: healthClient,
            repository: repository,
            healthStore: walkHealthStore,
            preferences: healthPreferences
        )
        let motionClient = LiveMotionCapabilityClient()
        let locationClient = LiveLocationCapabilityClient()
        let walkCoordinator = LiveWalkSessionCoordinator(
            motionClient: motionClient,
            locationClient: locationClient
        )
        let storeReference = WalkSessionStoreReference()
        let actionHandler = WalkActivityActionHandler { request in
            await storeReference.store?.performExternalAction(request)
        }
        let notificationClient = LiveWalkNotificationClient(
            actionHandler: actionHandler
        )
        let walkSessionStore = WalkSessionStore(
            coordinator: walkCoordinator,
            repository: repository,
            healthStore: walkHealthStore,
            liveActivityClient: LiveWalkActivityClient(),
            notificationClient: notificationClient,
            reminderPreferences: LiveWalkReminderPreferences()
        )
        storeReference.store = walkSessionStore
        AppDependencyManager.shared.add(dependency: actionHandler)

        let tabRouter = AppTabRouter()
        let startHandler = WalkStartActionHandler {
            guard walkSessionStore.state == .idle else { return .alreadyInProgress }
            guard !walkSessionStore.needsPermissionExplanation else { return .needsPermissionSetup }
            tabRouter.select(.walk)
            await walkSessionStore.start(requestPermissions: false)
            return .started
        }
        AppDependencyManager.shared.add(dependency: startHandler)
#if DEBUG
        let sensorDiagnosticsStore = SensorDiagnosticsStore(
            motionClient: motionClient,
            locationClient: locationClient,
            healthClient: healthClient
        )
#else
        let sensorDiagnosticsStore: SensorDiagnosticsStore? = nil
#endif

        let dependencies = AppDependencies(
            modelContainer: modelContainer,
            walkRepository: repository,
            walkSessionStore: walkSessionStore,
            walkHealthStore: walkHealthStore,
            healthWorkoutImportStore: HealthWorkoutImportStore(
                client: healthClient,
                repository: repository,
                healthStore: walkHealthStore
            ),
            healthWorkoutAutoImporter: autoImporter,
            tabRouter: tabRouter,
            activityActionHandler: actionHandler,
            startWalkActionHandler: startHandler,
            sensorDiagnosticsStore: sensorDiagnosticsStore
        )
        // Registered here rather than from a view: a HealthKit background launch
        // wakes the app without necessarily rendering a scene.
        autoImporter.activate()
        return dependencies
    }

    static func preview() throws -> AppDependencies {
        let modelContainer = try PersistenceContainer.make(isStoredInMemoryOnly: true)
        let repository = SwiftDataWalkRepository(modelContainer: modelContainer)
        let healthClient = FakeHealthCapabilityClient()
        let healthWorkoutStart = Date().addingTimeInterval(-24 * 60 * 60)
        let healthWorkout = HealthWalkingWorkout(
            id: UUID(uuidString: "6670A2A3-54DF-4A61-A64B-8584540EF1B5")!,
            startDate: healthWorkoutStart,
            endDate: healthWorkoutStart.addingTimeInterval(1_200),
            movingDuration: 1_080,
            distanceMeters: 1_450,
            sourceName: "Apple Watch",
            sourceBundleIdentifier: "com.apple.health",
            timeZoneIdentifier: "Australia/Melbourne"
        )
        healthClient.walkingWorkoutCandidates = [healthWorkout]
        healthClient.walkingWorkoutImports[healthWorkout.id] =
            HealthWalkingWorkoutImport(workout: healthWorkout, routePoints: [])
        let healthPreferences = FakeHealthPreferences()
        let walkHealthStore = WalkHealthStore(
            client: healthClient,
            preferences: healthPreferences,
            repository: repository
        )
        let motionClient = FakeMotionCapabilityClient()
        let locationClient = FakeLocationCapabilityClient()
        let walkCoordinator = LiveWalkSessionCoordinator(
            motionClient: motionClient,
            locationClient: locationClient
        )
#if DEBUG
        let sensorDiagnosticsStore = SensorDiagnosticsStore(
            motionClient: motionClient,
            locationClient: locationClient,
            healthClient: healthClient
        )
#else
        let sensorDiagnosticsStore: SensorDiagnosticsStore? = nil
#endif

        return AppDependencies(
            modelContainer: modelContainer,
            walkRepository: repository,
            walkSessionStore: WalkSessionStore(
                coordinator: walkCoordinator,
                repository: repository,
                healthStore: walkHealthStore
            ),
            walkHealthStore: walkHealthStore,
            healthWorkoutImportStore: HealthWorkoutImportStore(
                client: healthClient,
                repository: repository,
                healthStore: walkHealthStore
            ),
            healthWorkoutAutoImporter: HealthWorkoutAutoImporter(
                client: healthClient,
                repository: repository,
                healthStore: walkHealthStore,
                preferences: healthPreferences
            ),
            sensorDiagnosticsStore: sensorDiagnosticsStore
        )
    }

#if DEBUG
    static func uiTesting(
        permissionNotDetermined: Bool,
        recoverableDraft: Bool = false
    ) throws -> AppDependencies {
        let modelContainer = try PersistenceContainer.make(isStoredInMemoryOnly: true)
        let repository = SwiftDataWalkRepository(modelContainer: modelContainer)
        let healthClient = FakeHealthCapabilityClient()
        let healthWorkoutStart = Date().addingTimeInterval(-24 * 60 * 60)
        let healthWorkout = HealthWalkingWorkout(
            id: UUID(uuidString: "6670A2A3-54DF-4A61-A64B-8584540EF1B5")!,
            startDate: healthWorkoutStart,
            endDate: healthWorkoutStart.addingTimeInterval(1_200),
            movingDuration: 1_080,
            distanceMeters: 1_450,
            sourceName: "Apple Watch",
            sourceBundleIdentifier: "com.apple.health",
            timeZoneIdentifier: "Australia/Melbourne"
        )
        healthClient.walkingWorkoutCandidates = [healthWorkout]
        healthClient.walkingWorkoutImports[healthWorkout.id] =
            HealthWalkingWorkoutImport(workout: healthWorkout, routePoints: [])
        let healthPreferences = FakeHealthPreferences()
        let walkHealthStore = WalkHealthStore(
            client: healthClient,
            preferences: healthPreferences,
            repository: repository
        )
        if recoverableDraft {
            try repository.saveDraft(
                .sample(
                    id: UUID(),
                    startDate: Date(timeIntervalSince1970: 1_800_000_000)
                )
            )
        }
        let permissionSnapshot = WalkPermissionSnapshot(
            motionAuthorization: permissionNotDetermined ? .notDetermined : .authorized,
            locationAuthorization: permissionNotDetermined ? .notDetermined : .whenInUse,
            locationAccuracy: permissionNotDetermined ? .unknown : .full,
            stepCountingAvailable: true,
            pedometerDistanceAvailable: true,
            relativeAltitudeAvailable: true,
            absoluteAltitudeAvailable: true
        )
#if DEBUG
        let sensorDiagnosticsStore = SensorDiagnosticsStore(
            motionClient: FakeMotionCapabilityClient(),
            locationClient: FakeLocationCapabilityClient(),
            healthClient: healthClient
        )
#else
        let sensorDiagnosticsStore: SensorDiagnosticsStore? = nil
#endif

        return AppDependencies(
            modelContainer: modelContainer,
            walkRepository: repository,
            walkSessionStore: WalkSessionStore(
                coordinator: FakeWalkSessionCoordinator(
                    permissionSnapshot: permissionSnapshot
                ),
                repository: repository,
                healthStore: walkHealthStore
            ),
            walkHealthStore: walkHealthStore,
            healthWorkoutImportStore: HealthWorkoutImportStore(
                client: healthClient,
                repository: repository,
                healthStore: walkHealthStore
            ),
            healthWorkoutAutoImporter: HealthWorkoutAutoImporter(
                client: healthClient,
                repository: repository,
                healthStore: walkHealthStore,
                preferences: healthPreferences
            ),
            sensorDiagnosticsStore: sensorDiagnosticsStore
        )
    }
#endif
}
