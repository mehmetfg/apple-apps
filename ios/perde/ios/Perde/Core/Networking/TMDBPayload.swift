import Foundation

/// Wire formats for the TMDB API. Decoded with `.convertFromSnakeCase`.
enum TMDBPayload {
    struct Page: Decodable {
        let page: Int
        let results: [Title]
        let totalPages: Int
        let totalResults: Int
    }

    struct Title: Decodable {
        let id: Int
        let mediaType: String?
        let title: String?
        let name: String?
        let originalTitle: String?
        let originalName: String?
        let overview: String?
        let posterPath: String?
        let releaseDate: String?
        let firstAirDate: String?
        let genreIds: [Int]?
        let originalLanguage: String?
        let voteAverage: Double?
        let voteCount: Int?
        let popularity: Double?

        func catalogTitle(kind: MediaKind) -> CatalogTitle {
            let displayTitle = title ?? name ?? ""
            let date = releaseDate ?? firstAirDate ?? ""
            return CatalogTitle(
                kind: kind,
                tmdbId: id,
                title: displayTitle,
                originalTitle: originalTitle ?? originalName ?? displayTitle,
                overview: overview ?? "",
                posterPath: posterPath,
                releaseYear: Int(date.prefix(4)),
                genreIds: genreIds ?? [],
                originalLanguage: originalLanguage,
                tmdbScore: voteAverage ?? 0,
                tmdbVotes: voteCount ?? 0,
                popularity: popularity ?? 0
            )
        }
    }

    struct ProviderList: Decodable {
        let results: [Provider]
    }

    struct Provider: Decodable {
        let providerId: Int
        let providerName: String
    }

    struct GenreList: Decodable {
        let genres: [Genre]
    }

    struct Genre: Decodable {
        let id: Int
        let name: String
    }

    struct ExternalIds: Decodable {
        let imdbId: String?
    }

    struct ReviewPage: Decodable {
        let results: [Review]
    }

    struct Review: Decodable {
        let id: String
        let author: String
        let content: String
        let authorDetails: AuthorDetails?
        let createdAt: String?
    }

    struct AuthorDetails: Decodable {
        let rating: Double?
    }

    struct Details: Decodable {
        let overview: String?
        let tagline: String?
        let runtime: Int?
        let numberOfSeasons: Int?
        let genres: [Genre]?
        let externalIds: ExternalIds?
        let keywords: Keywords?
        let credits: Credits?
        let reviews: ReviewPage?
        let watchProviders: WatchProviders?

        enum CodingKeys: String, CodingKey {
            case overview, tagline, runtime, numberOfSeasons, genres, externalIds, keywords, credits, reviews
            case watchProviders = "watch/providers"
        }
    }

    /// Movies use `keywords`, series use `results`.
    struct Keywords: Decodable {
        let keywords: [Genre]?
        let results: [Genre]?

        var all: [Genre] { keywords ?? results ?? [] }
    }

    struct Credits: Decodable {
        let cast: [CastMember]?
    }

    struct CastMember: Decodable {
        let name: String
    }

    struct WatchProviders: Decodable {
        let results: [String: RegionProviders]?
    }

    struct RegionProviders: Decodable {
        let flatrate: [Provider]?
        let ads: [Provider]?
        let free: [Provider]?
        let rent: [Provider]?
        let buy: [Provider]?
    }
}
