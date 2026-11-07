import Foundation
import SwiftData

/// A title the user has saved, prioritised or watched.
/// Rules: a priority title is always on the list, and watching a title takes it off both.
@Model
final class LibraryEntry {
    @Attribute(.unique) var key: String
    var kindRawValue: String
    var tmdbId: Int
    var title: String
    var originalTitle: String
    var overview: String
    var posterPath: String?
    var releaseYear: Int?
    var genreIds: [Int]
    var genreNames: [String]
    var originalLanguage: String?
    var tmdbScore: Double
    var tmdbVotes: Int
    var imdbScore: Double?
    var isListed: Bool
    var isPriority: Bool
    var priorityRank: Int
    var addedAt: Date
    var watchedAt: Date?
    var personalScore: Int?

    init(title source: CatalogTitle, genreNames: [String]) {
        key = source.id
        kindRawValue = source.kind.rawValue
        tmdbId = source.tmdbId
        title = source.title
        originalTitle = source.originalTitle
        overview = source.overview
        posterPath = source.posterPath
        releaseYear = source.releaseYear
        genreIds = source.genreIds
        self.genreNames = genreNames
        originalLanguage = source.originalLanguage
        tmdbScore = source.tmdbScore
        tmdbVotes = source.tmdbVotes
        isListed = false
        isPriority = false
        priorityRank = 0
        addedAt = .now
    }

    var kind: MediaKind { MediaKind(rawValue: kindRawValue) ?? .movie }
    var isWatched: Bool { watchedAt != nil }
    /// An entry with no state left carries no information and can be deleted.
    var isEmpty: Bool { !isListed && !isPriority && !isWatched }

    var catalogTitle: CatalogTitle {
        CatalogTitle(
            kind: kind,
            tmdbId: tmdbId,
            title: title,
            originalTitle: originalTitle,
            overview: overview,
            posterPath: posterPath,
            releaseYear: releaseYear,
            genreIds: genreIds,
            originalLanguage: originalLanguage,
            tmdbScore: tmdbScore,
            tmdbVotes: tmdbVotes,
            popularity: 0
        )
    }

    func setListed(_ listed: Bool) {
        isListed = listed
        if !listed { isPriority = false }
    }

    func setPriority(_ priority: Bool, rank: Int) {
        isPriority = priority
        if priority {
            isListed = true
            priorityRank = rank
        }
    }

    func markWatched(on date: Date = .now) {
        watchedAt = date
        isListed = false
        isPriority = false
    }

    func markUnwatched() {
        watchedAt = nil
        personalScore = nil
    }
}
