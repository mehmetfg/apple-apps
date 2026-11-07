import CoreGraphics
import Foundation

/// One piece of text the camera currently sees, in the scanner view's coordinates.
struct ScannedText: Identifiable, Hashable, Sendable {
    let id: String
    let text: String
    let frame: CGRect
}
