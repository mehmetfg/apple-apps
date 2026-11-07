import Foundation

/// Finds IMDb ratings and caches them on disk, because the free OMDb key allows 1,000 requests a day.
actor RatingService {
    private struct CachedRating: Codable {
        let rating: IMDbRating?
        let fetchedAt: Date
    }

    private static let foundLifetime: TimeInterval = 7 * 24 * 3600
    private static let missingLifetime: TimeInterval = 24 * 3600

    private let tmdb: TMDBClient
    private let omdb: OMDbClient
    private let cacheURL: URL
    private var cache: [String: CachedRating]
    private var inFlight: [String: Task<RatingOutcome, Never>] = [:]
    private var pendingSave: Task<Void, Never>?

    init(tmdb: TMDBClient, omdb: OMDbClient) {
        self.tmdb = tmdb
        self.omdb = omdb
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheURL = directory.appending(path: "imdb-ratings.json")
        let stored = try? Data(contentsOf: cacheURL)
        cache = stored.flatMap { try? JSONDecoder().decode([String: CachedRating].self, from: $0) } ?? [:]
    }

    func rating(kind: MediaKind, tmdbId: Int) async -> RatingOutcome {
        let key = CatalogTitle.key(kind: kind, tmdbId: tmdbId)
        if let cached = cache[key], Self.isFresh(cached) {
            return cached.rating.map(RatingOutcome.found) ?? .unavailable
        }
        if let running = inFlight[key] {
            return await running.value
        }
        let task = Task { await self.fetch(kind: kind, tmdbId: tmdbId) }
        inFlight[key] = task
        let outcome = await task.value
        inFlight[key] = nil
        switch outcome {
        case .found(let rating): store(rating, for: key)
        case .unavailable: store(nil, for: key)
        case .failed: break
        }
        return outcome
    }

    private func fetch(kind: MediaKind, tmdbId: Int) async -> RatingOutcome {
        do {
            guard let imdbId = try await tmdb.imdbId(kind: kind, tmdbId: tmdbId) else { return .unavailable }
            guard let rating = try await omdb.rating(imdbId: imdbId) else { return .unavailable }
            return .found(rating)
        } catch let error as APIError {
            return .failed(error)
        } catch {
            return .failed(.network(error.localizedDescription))
        }
    }

    private func store(_ rating: IMDbRating?, for key: String) {
        cache[key] = CachedRating(rating: rating, fetchedAt: .now)
        pendingSave?.cancel()
        pendingSave = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self.persist()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    private static func isFresh(_ entry: CachedRating) -> Bool {
        let lifetime = entry.rating == nil ? missingLifetime : foundLifetime
        return Date.now.timeIntervalSince(entry.fetchedAt) < lifetime
    }
}
