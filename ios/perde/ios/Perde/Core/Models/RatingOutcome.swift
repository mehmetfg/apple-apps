import Foundation

enum RatingOutcome: Sendable {
    case found(IMDbRating)
    /// IMDb has no rating for this title.
    case unavailable
    case failed(APIError)
}
