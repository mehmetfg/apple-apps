import Foundation

/// The part of the filter the server applies. A change here means fetching again.
struct DiscoverQuery: Hashable, Sendable {
    var kind: MediaKind
    var category: TasteCategory
    var genreIds: Set<Int>
    var minimumYear: Int?
    var sort: DiscoverSort
    var origin: TitleOrigin

    var parameters: [String: String] {
        var result: [String: String] = [:]
        switch sort {
        case .popular, .personalMatch:
            result["sort_by"] = "popularity.desc"
        case .imdb:
            // TMDB's score only picks the candidates; IMDb decides the final order on the device.
            result["sort_by"] = "vote_average.desc"
            result["vote_count.gte"] = "50"
        case .newest:
            result["sort_by"] = kind == .movie ? "primary_release_date.desc" : "first_air_date.desc"
        }
        // A comma means "all of these" and a pipe means "any of these" in TMDB queries.
        let categoryGenres = category.genreIds(for: kind)
        var genreClauses: [String] = []
        if !categoryGenres.isEmpty {
            genreClauses.append(categoryGenres.map(String.init).joined(separator: "|"))
        }
        if !genreIds.isEmpty {
            genreClauses.append(genreIds.sorted().map(String.init).joined(separator: ","))
        }
        if !genreClauses.isEmpty {
            result["with_genres"] = genreClauses.joined(separator: ",")
        }
        if let minimumYear {
            let field = kind == .movie ? "primary_release_date.gte" : "first_air_date.gte"
            result[field] = "\(minimumYear)-01-01"
        }
        if origin == .turkish {
            result["with_original_language"] = "tr"
        }
        return result
    }
}
