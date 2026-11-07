import Foundation

struct TMDBClient: Sendable {
    private static let language = "tr-TR"
    private static let fallbackLanguage = "en-US"

    func providerId(for platform: StreamingPlatform) async throws -> Int {
        for kind in MediaKind.allCases {
            let list: TMDBPayload.ProviderList = try await get(
                "watch/providers/\(kind.rawValue)",
                query: ["watch_region": platform.region, "language": Self.language]
            )
            if let match = list.results.first(where: { platform.matches(providerName: $0.providerName) }) {
                return match.providerId
            }
        }
        throw APIError.platformNotListed(platform.displayName)
    }

    func genres() async throws -> GenreCatalog {
        var catalog = GenreCatalog()
        for kind in MediaKind.allCases {
            let list: TMDBPayload.GenreList = try await get("genre/\(kind.rawValue)/list", query: ["language": Self.language])
            let lookup = Dictionary(list.genres.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
            switch kind {
            case .movie: catalog.movie = lookup
            case .tv: catalog.tv = lookup
            }
        }
        return catalog
    }

    func discover(query: DiscoverQuery, providerId: Int, region: String, page: Int) async throws -> CatalogPage {
        var parameters = query.parameters
        parameters["with_watch_providers"] = String(providerId)
        parameters["watch_region"] = region
        parameters["language"] = Self.language
        parameters["include_adult"] = "false"
        parameters["page"] = String(page)
        let payload: TMDBPayload.Page = try await get("discover/\(query.kind.rawValue)", query: parameters)
        return CatalogPage(
            titles: payload.results.map { $0.catalogTitle(kind: query.kind) },
            page: payload.page,
            totalPages: payload.totalPages,
            totalResults: payload.totalResults
        )
    }

    func search(text: String) async throws -> [CatalogTitle] {
        let payload: TMDBPayload.Page = try await get(
            "search/multi",
            query: ["query": text, "language": Self.language, "include_adult": "false"]
        )
        return payload.results.compactMap { result in
            guard let kind = result.mediaType.flatMap(MediaKind.init(rawValue:)) else { return nil }
            return result.catalogTitle(kind: kind)
        }
    }

    func imdbId(kind: MediaKind, tmdbId: Int) async throws -> String? {
        let ids: TMDBPayload.ExternalIds = try await get("\(kind.rawValue)/\(tmdbId)/external_ids", query: [:])
        return ids.imdbId.flatMap { $0.isEmpty ? nil : $0 }
    }

    func details(kind: MediaKind, tmdbId: Int, region: String) async throws -> TitleDetails {
        let payload: TMDBPayload.Details = try await get(
            "\(kind.rawValue)/\(tmdbId)",
            query: [
                "language": Self.language,
                "append_to_response": "external_ids,keywords,credits,reviews,watch/providers",
            ]
        )
        var overview = payload.overview ?? ""
        var reviews = payload.reviews?.results ?? []
        // Turkish overviews and reviews are often missing; English is better than nothing.
        if overview.isEmpty || reviews.isEmpty {
            let fallback: TMDBPayload.Details = try await get(
                "\(kind.rawValue)/\(tmdbId)",
                query: ["language": Self.fallbackLanguage, "append_to_response": "reviews"]
            )
            if overview.isEmpty { overview = fallback.overview ?? "" }
            if reviews.isEmpty { reviews = fallback.reviews?.results ?? [] }
        }
        let regional = payload.watchProviders?.results?[region]
        let streaming = (regional?.flatrate ?? []) + (regional?.ads ?? []) + (regional?.free ?? [])
        let rental = (regional?.rent ?? []) + (regional?.buy ?? [])
        return TitleDetails(
            overview: overview,
            tagline: payload.tagline.flatMap { $0.isEmpty ? nil : $0 },
            runtimeMinutes: payload.runtime.flatMap { $0 > 0 ? $0 : nil },
            seasonCount: payload.numberOfSeasons,
            genreNames: payload.genres?.map(\.name) ?? [],
            keywords: payload.keywords?.all.map(\.name) ?? [],
            cast: Array((payload.credits?.cast ?? []).prefix(8).map(\.name)),
            imdbId: payload.externalIds?.imdbId,
            streamingProviders: Self.uniqueNames(streaming),
            rentalProviders: Self.uniqueNames(rental),
            reviews: reviews.map(Self.review)
        )
    }

    private static func uniqueNames(_ providers: [TMDBPayload.Provider]) -> [String] {
        var seen = Set<String>()
        return providers.map(\.providerName).filter { seen.insert($0).inserted }
    }

    private static func review(_ payload: TMDBPayload.Review) -> TitleReview {
        TitleReview(
            id: payload.id,
            author: payload.author,
            content: payload.content,
            authorScore: payload.authorDetails?.rating,
            createdAt: payload.createdAt.flatMap { try? Date($0, strategy: .iso8601.year().month().day()) }
        )
    }

    private func get<Response: Decodable>(_ path: String, query: [String: String]) async throws -> Response {
        guard let key = APIKeyStore.value(for: .tmdb) else { throw APIError.missingKey(service: "TMDB") }
        var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        items.append(URLQueryItem(name: "api_key", value: key))
        let url = ServiceEndpoints.tmdb.appending(path: path).appending(queryItems: items)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(from: url)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw APIError.network(error.localizedDescription)
        }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200..<300: break
        case 401: throw APIError.invalidKey(service: "TMDB")
        case 429: throw APIError.quotaReached(service: "TMDB")
        default: throw APIError.badResponse(service: "TMDB")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.badResponse(service: "TMDB")
        }
    }
}
