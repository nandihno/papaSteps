import Foundation
import Observation

@MainActor
@Observable
final class ProgressStore {
    private(set) var snapshot: WalkAnalyticsSnapshot = .empty
    private(set) var errorMessage: String?

    private let repository: any WalkRepository
    private let analytics: WalkAnalyticsService
    private let now: @Sendable () -> Date

    init(
        repository: any WalkRepository,
        analytics: WalkAnalyticsService = WalkAnalyticsService(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.repository = repository
        self.analytics = analytics
        self.now = now
    }

    func refresh() {
        do {
            snapshot = analytics.makeSnapshot(
                walks: try repository.fetchSummaries(),
                now: now()
            )
            errorMessage = nil
        } catch {
            errorMessage = "Progress could not be calculated from local walks."
        }
    }
}
