import Foundation
import Observation

@MainActor
@Observable
final class WalkHistoryStore {
    private(set) var summaries: [WalkSummary] = []
    private(set) var errorMessage: String?
    /// Downsampled routes for list thumbnails, loaded per row as it appears and
    /// kept for the session. A failed load caches an empty route so the row
    /// does not retry on every scroll pass.
    private(set) var routePreviews: [UUID: [WalkCoordinate]] = [:]

    private static let previewPointLimit = 60

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

    /// Loads the thumbnail route for one walk, once.
    func loadRoutePreview(id: UUID) {
        guard routePreviews[id] == nil else { return }
        routePreviews[id] = (try? repository.fetchRoutePreview(
            id: id,
            maximumPoints: Self.previewPointLimit
        )) ?? []
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
            routePreviews[id] = nil
            errorMessage = nil
        } catch {
            errorMessage = "This walk could not be deleted."
        }
    }

    func deleteAll() {
        do {
            try repository.deleteAllWalks()
            summaries = []
            routePreviews = [:]
            errorMessage = nil
        } catch {
            errorMessage = "Local walk data could not be deleted."
        }
    }
}
