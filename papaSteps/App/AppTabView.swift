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
            Tab("Walk", systemImage: "figure.walk", value: .walk) {
                NavigationStack {
                    WalkView()
                }
            }

            Tab("History", systemImage: "clock.arrow.circlepath", value: .history) {
                NavigationStack {
                    HistoryView()
                }
            }

            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: .progress) {
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
