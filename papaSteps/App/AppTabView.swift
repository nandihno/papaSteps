import Observation
import SwiftData
import SwiftUI

enum AppTab: Hashable, Sendable {
    case walk
    case history
    case progress
}

/// Owns tab selection so a screen can send the user somewhere else — History's
/// empty state offering to start a walk, for instance.
@MainActor
@Observable
final class AppTabRouter {
    var selectedTab: AppTab = .walk

    func select(_ tab: AppTab) {
        selectedTab = tab
    }
}

struct AppTabView: View {
    @Environment(AppTabRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            Tab("Walk", systemImage: WalkSymbol.walk, value: .walk) {
                NavigationStack {
                    WalkView()
                }
            }

            Tab("History", systemImage: WalkSymbol.history, value: .history) {
                NavigationStack {
                    HistoryView()
                }
            }

            Tab("Progress", systemImage: WalkSymbol.progress, value: .progress) {
                NavigationStack {
                    ProgressDashboardView()
                }
            }
        }
    }
}

#Preview {
    let dependencies = try! AppDependencies.preview()
    AppRootView(dependencies: dependencies)
        .modelContainer(dependencies.modelContainer)
}
