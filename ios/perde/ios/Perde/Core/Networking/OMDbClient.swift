import Foundation

struct OMDbClient: Sendable {
    func rating(imdbId: String) async throws -> IMDbRating? {
        guard let key = APIKeyStore.value(for: .omdb) else { throw APIError.missingKey(service: "OMDb") }
        let url = ServiceEndpoints.omdb.appending(queryItems: [
            URLQueryItem(name: "i", value: imdbId),
            URLQueryItem(name: "apikey", value: key),
        ])
        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(from: url)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw APIError.network(error.localizedDescription)
        }
        return try Self.parse(data: data, imdbId: imdbId)
    }

    /// OMDb reports failures in the body, with `Response: "False"`, as well as through status codes.
    static func parse(data: Data, imdbId: String) throws -> IMDbRating? {
        struct Source: Decodable {
            let Source: String
            let Value: String
        }
        struct Payload: Decodable {
            let Response: String?
            let Error: String?
            let imdbRating: String?
            let imdbVotes: String?
            let Metascore: String?
            let Awards: String?
            let Ratings: [Source]?
        }

        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw APIError.badResponse(service: "OMDb")
        }
        if payload.Response == "False" {
            let message = payload.Error?.lowercased() ?? ""
            if message.contains("limit") { throw APIError.quotaReached(service: "OMDb") }
            if message.contains("api key") { throw APIError.invalidKey(service: "OMDb") }
            return nil
        }
        guard let score = payload.imdbRating.flatMap(Double.init) else { return nil }
        return IMDbRating(
            imdbId: imdbId,
            score: score,
            votes: Int(payload.imdbVotes?.replacingOccurrences(of: ",", with: "") ?? "") ?? 0,
            metascore: payload.Metascore.flatMap(Int.init),
            rottenTomatoes: payload.Ratings?.first { $0.Source == "Rotten Tomatoes" }?.Value,
            awards: payload.Awards.flatMap { $0 == "N/A" ? nil : $0 }
        )
    }
}
