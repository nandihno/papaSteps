import SwiftData
import SwiftUI

@main
@MainActor
struct papaStepsApp: App {
    private enum BootstrapState {
        case ready(AppDependencies)
        case failed
    }

    private let bootstrapState: BootstrapState

    init() {
        do {
#if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--ui-testing") {
                bootstrapState = .ready(
                    try AppDependencies.uiTesting(
                        permissionNotDetermined: arguments.contains(
                            "--ui-testing-permissions-not-determined"
                        ),
                        recoverableDraft: arguments.contains(
                            "--ui-testing-recovery"
                        )
                    )
                )
            } else {
                bootstrapState = .ready(try AppDependencies.live())
            }
#else
            bootstrapState = .ready(try AppDependencies.live())
#endif
        } catch {
            bootstrapState = .failed
        }
    }

    var body: some Scene {
        WindowGroup {
            switch bootstrapState {
            case .ready(let dependencies):
                AppRootView(dependencies: dependencies)
                    .modelContainer(dependencies.modelContainer)
            case .failed:
                ContentUnavailableView(
                    "Unable to Start",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(
                        "papaSteps could not open its local walk data. Restart the app and try again."
                    )
                )
            }
        }
    }
}

@MainActor
struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase

    let dependencies: AppDependencies

    var body: some View {
        AppTabView()
            .environment(dependencies.walkSessionStore)
            .environment(dependencies.walkHistoryStore)
            .environment(dependencies.tabRouter)
            .environment(dependencies.progressStore)
            .environment(dependencies.walkHealthStore)
            .environment(dependencies.healthWorkoutImportStore)
            .environment(dependencies.healthWorkoutAutoImporter)
            .environment(dependencies.walkDisplayPreferences)
#if DEBUG
            .environment(dependencies.sensorDiagnosticsStore)
#endif
            .task {
                await dependencies.walkSessionStore.refreshExternalExperienceState()
            }
            .onChange(of: scenePhase) { _, newPhase in
                Task {
                    if newPhase == .active {
                        await dependencies.walkSessionStore.reconcileAfterForeground()
                        // Covers walks that landed in Health while the app was
                        // terminated and never got a background wake.
                        await dependencies.healthWorkoutAutoImporter.runCatchUpPass()
                    } else if newPhase == .inactive || newPhase == .background {
                        await dependencies.walkSessionStore.checkpointBeforeBackground()
                    }
                }
            }
    }
}
