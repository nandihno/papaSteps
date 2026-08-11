import SwiftData
import SwiftUI

enum AppTab: Hashable, Sendable {
    case walk
    case history
    case progress
}

struct AppTabView: View {
    @State private var selectedTab: AppTab = .walk

    var body: some View {
        TabView(selection: $selectedTab) {
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
