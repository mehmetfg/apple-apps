import Foundation

/// Applies the filters TMDB cannot and puts the results in their final order.
enum DiscoverRanker {
    struct Input {
        let titles: [CatalogTitle]
        let ratings: [String: IMDbRating]
        let watchedIds: Set<String>
        let filter: DiscoverFilter
        let matchPercent: (CatalogTitle) -> Int?
    }

    static func rank(_ input: Input) -> [CatalogTitle] {
        let kept = input.titles.filter { keeps($0, input: input) }
        switch input.filter.query.sort {
        case .popular:
            return kept.sorted { $0.popularity > $1.popularity }
        case .newest:
            return kept.sorted { ($0.releaseYear ?? 0) > ($1.releaseYear ?? 0) }
        case .imdb:
            return kept.sorted { imdbOrderValue($0, input) > imdbOrderValue($1, input) }
        case .personalMatch:
            return kept.sorted { first, second in
                let firstMatch = input.matchPercent(first) ?? 50
                let secondMatch = input.matchPercent(second) ?? 50
                if firstMatch != secondMatch { return firstMatch > secondMatch }
                return imdbOrderValue(first, input) > imdbOrderValue(second, input)
            }
        }
    }

    private static func keeps(_ title: CatalogTitle, input: DiscoverRanker.Input) -> Bool {
        let filter = input.filter
        if filter.hidesWatched && input.watchedIds.contains(title.id) { return false }
        if filter.query.origin == .foreign && title.originalLanguage == "tr" { return false }
        if filter.minimumIMDbScore > 0 {
            guard let rating = input.ratings[title.id] else { return false }
            if rating.score < filter.minimumIMDbScore { return false }
            if rating.votes < filter.minimumIMDbVotes { return false }
        }
        return true
    }

    private static func imdbOrderValue(_ title: CatalogTitle, _ input: Input) -> Double {
        input.ratings[title.id]?.weightedScore ?? -1
    }
}
