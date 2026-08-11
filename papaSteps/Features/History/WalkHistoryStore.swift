import Foundation
import Observation

@MainActor
@Observable
final class WalkHistoryStore {
    private(set) var summaries: [WalkSummary] = []
    private(set) var errorMessage: String?

    private let repository: any WalkRepository

    init(repository: any WalkRepository) {
        self.repository = repository
    }

    func load() {
        do {
            summaries = try repository.fetchSummaries()
            errorMessage = nil
        } catch {
            errorMessage = "Walk history could not be loaded."
        }
    }

    func detail(id: UUID) -> WalkDetail? {
        do {
            errorMessage = nil
            return try repository.fetchDetail(id: id)
        } catch {
            errorMessage = "This walk could not be loaded."
            return nil
        }
    }

    func delete(id: UUID) {
        do {
            try repository.deleteWalk(id: id)
            summaries.removeAll { $0.id == id }
            errorMessage = nil
        } catch {
            errorMessage = "This walk could not be deleted."
        }
    }

    func deleteAll() {
        do {
            try repository.deleteAllWalks()
            summaries = []
            errorMessage = nil
        } catch {
            errorMessage = "Local walk data could not be deleted."
        }
    }
}
