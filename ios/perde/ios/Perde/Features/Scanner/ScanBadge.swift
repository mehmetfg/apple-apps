import CoreGraphics
import Foundation

/// A rating label pinned over a recognised title in the camera view.
struct ScanBadge: Identifiable, Sendable {
    let title: CatalogTitle
    let frame: CGRect
    let rating: IMDbRating?
    let isRatingResolved: Bool

    var id: String { title.id }
}
