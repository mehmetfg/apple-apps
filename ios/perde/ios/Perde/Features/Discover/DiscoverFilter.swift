import Foundation

struct DiscoverFilter: Hashable, Sendable {
    var query = DiscoverQuery(
        kind: .movie,
        category: .all,
        genreIds: [],
        minimumYear: nil,
        sort: .popular,
        origin: .any
    )
    /// 0 means no limit. Applied on the device, because TMDB does not know IMDb scores.
    var minimumIMDbScore = 0.0
    var minimumIMDbVotes = 1_000
    var hidesWatched = true

    var activeFilterCount: Int {
        var count = 0
        if !query.genreIds.isEmpty { count += 1 }
        if query.minimumYear != nil { count += 1 }
        if query.origin != .any { count += 1 }
        if minimumIMDbScore > 0 { count += 1 }
        if !hidesWatched { count += 1 }
        return count
    }
}
