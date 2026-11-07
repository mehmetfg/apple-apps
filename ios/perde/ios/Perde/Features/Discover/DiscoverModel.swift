import Foundation
import Observation

@MainActor
@Observable
final class DiscoverModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// How many extra pages to fetch on one pass when device-side filters leave too little to show.
    private static let autoFillPageLimit = 4
    private static let enoughVisibleTitles = 12

    var filter = DiscoverFilter()
    private(set) var phase = Phase.idle
    private(set) var titles: [CatalogTitle] = []
    private(set) var ratings: [String: IMDbRating] = [:]
    private(set) var resolvedIds: Set<String> = []
    private(set) var ratingIssue: String?
    private(set) var totalResults = 0
    private(set) var isLoadingMore = false

    private var page = 0
    private var totalPages = 1
    private var providerId: Int?

    var canLoadMore: Bool { page < totalPages }

    func reload(services: AppServices) async {
        phase = .loading
        titles = []
        page = 0
        totalPages = 1
        totalResults = 0
        ratingIssue = nil
        do {
            try await services.loadGenresIfNeeded()
            let provider = try await services.providerId(for: .turkcellTVPlus)
            providerId = provider
            try await fetchNextPage(services: services, providerId: provider)
            phase = .loaded
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func loadMore(services: AppServices) async {
        guard canLoadMore, !isLoadingMore, let providerId else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        try? await fetchNextPage(services: services, providerId: providerId)
    }

    /// Keeps fetching when the device-side filters (IMDb score, for example) empty the screen.
    func fillIfNeeded(visibleCount: Int, services: AppServices) async {
        var attempts = 0
        var visible = visibleCount
        while visible < Self.enoughVisibleTitles, canLoadMore, attempts < Self.autoFillPageLimit, !Task.isCancelled {
            await loadMore(services: services)
            attempts += 1
            visible = DiscoverRanker.rank(rankerInput(watchedIds: [], matchPercent: { _ in nil })).count
        }
    }

    func rankerInput(watchedIds: Set<String>, matchPercent: @escaping (CatalogTitle) -> Int?) -> DiscoverRanker.Input {
        DiscoverRanker.Input(
            titles: titles,
            ratings: ratings,
            watchedIds: watchedIds,
            filter: filter,
            matchPercent: matchPercent
        )
    }

    func loadRatings(for newTitles: [CatalogTitle], services: AppServices) async {
        await withTaskGroup(of: (String, RatingOutcome).self) { group in
            var running = 0
            for title in newTitles where !resolvedIds.contains(title.id) {
                if running == 4 {
                    if let result = await group.next() { apply(result) }
                    running -= 1
                }
                group.addTask {
                    (title.id, await services.ratings.rating(kind: title.kind, tmdbId: title.tmdbId))
                }
                running += 1
            }
            for await result in group { apply(result) }
        }
    }

    private func apply(_ result: (String, RatingOutcome)) {
        let (id, outcome) = result
        resolvedIds.insert(id)
        switch outcome {
        case .found(let rating): ratings[id] = rating
        case .unavailable: break
        case .failed(let error): ratingIssue = error.localizedDescription
        }
    }

    private func fetchNextPage(services: AppServices, providerId: Int) async throws {
        let next = try await services.tmdb.discover(
            query: filter.query,
            providerId: providerId,
            region: StreamingPlatform.turkcellTVPlus.region,
            page: page + 1
        )
        page = next.page
        totalPages = next.totalPages
        totalResults = next.totalResults
        let known = Set(titles.map(\.id))
        let fresh = next.titles.filter { !known.contains($0.id) }
        titles.append(contentsOf: fresh)
        await loadRatings(for: fresh, services: services)
    }
}
