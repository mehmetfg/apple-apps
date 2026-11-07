import Foundation
import Observation

@MainActor
@Observable
final class AppServices {
    let tmdb: TMDBClient
    let ratings: RatingService
    private(set) var genres = GenreCatalog()
    private(set) var hasTMDBKey = false
    private(set) var hasOMDbKey = false
    /// Changes whenever keys are saved, so screens can reload.
    private(set) var keyRevision = 0

    @ObservationIgnored private var providerIds: [String: Int] = [:]

    init() {
        let tmdb = TMDBClient()
        self.tmdb = tmdb
        ratings = RatingService(tmdb: tmdb, omdb: OMDbClient())
        refreshKeyState()
    }

    func refreshKeyState() {
        hasTMDBKey = APIKeyStore.value(for: .tmdb) != nil
        hasOMDbKey = APIKeyStore.value(for: .omdb) != nil
    }

    func save(tmdbKey: String, omdbKey: String) {
        APIKeyStore.set(tmdbKey, for: .tmdb)
        APIKeyStore.set(omdbKey, for: .omdb)
        providerIds.removeAll()
        genres = GenreCatalog()
        refreshKeyState()
        keyRevision += 1
    }

    func providerId(for platform: StreamingPlatform) async throws -> Int {
        if let known = providerIds[platform.id] { return known }
        let found = try await tmdb.providerId(for: platform)
        providerIds[platform.id] = found
        return found
    }

    func loadGenresIfNeeded() async throws {
        guard genres.movie.isEmpty else { return }
        genres = try await tmdb.genres()
    }
}
