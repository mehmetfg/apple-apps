import Foundation

struct IMDbRating: Codable, Hashable, Sendable {
    let imdbId: String
    let score: Double
    let votes: Int
    let metascore: Int?
    let rottenTomatoes: String?
    let awards: String?

    /// A score that pulls titles with few votes toward the average, so 9.0 from 200 votes
    /// does not outrank 8.5 from 400,000. Used for ordering only; the raw score is what is shown.
    var weightedScore: Double {
        let confidenceVotes = 5_000.0
        let averageScore = 6.8
        let voteCount = Double(votes)
        return (voteCount * score + confidenceVotes * averageScore) / (voteCount + confidenceVotes)
    }
}
