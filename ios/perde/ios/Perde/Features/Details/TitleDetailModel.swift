import Foundation
import Observation

@MainActor
@Observable
final class TitleDetailModel {
    private(set) var details: TitleDetails?
    private(set) var rating: IMDbRating?
    private(set) var isRatingResolved = false
    private(set) var errorMessage: String?

    func load(title: CatalogTitle, services: AppServices) async {
        async let fetchedDetails = services.tmdb.details(
            kind: title.kind,
            tmdbId: title.tmdbId,
            region: StreamingPlatform.turkcellTVPlus.region
        )
        async let outcome = services.ratings.rating(kind: title.kind, tmdbId: title.tmdbId)
        do {
            details = try await fetchedDetails
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        if case .found(let found) = await outcome { rating = found }
        isRatingResolved = true
    }
}
