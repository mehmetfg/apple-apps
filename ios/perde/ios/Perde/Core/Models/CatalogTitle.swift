import Foundation

/// A film or series as returned by a catalog query.
struct CatalogTitle: Identifiable, Hashable, Sendable {
    let kind: MediaKind
    let tmdbId: Int
    let title: String
    let originalTitle: String
    let overview: String
    let posterPath: String?
    let releaseYear: Int?
    let genreIds: [Int]
    let originalLanguage: String?
    let tmdbScore: Double
    let tmdbVotes: Int
    let popularity: Double

    var id: String { Self.key(kind: kind, tmdbId: tmdbId) }

    static func key(kind: MediaKind, tmdbId: Int) -> String {
        "\(kind.rawValue)-\(tmdbId)"
    }
}
