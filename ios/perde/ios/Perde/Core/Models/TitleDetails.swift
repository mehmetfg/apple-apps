import Foundation

struct TitleDetails: Sendable {
    let overview: String
    let tagline: String?
    let runtimeMinutes: Int?
    let seasonCount: Int?
    let genreNames: [String]
    let keywords: [String]
    let cast: [String]
    let imdbId: String?
    let streamingProviders: [String]
    let rentalProviders: [String]
    let reviews: [TitleReview]
}
