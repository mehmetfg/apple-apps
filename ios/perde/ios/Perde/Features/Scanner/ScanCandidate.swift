import CoreGraphics
import Foundation

/// A piece of on-screen text that may be a title, ready to look up.
struct ScanCandidate: Hashable, Sendable {
    let query: String
    let frame: CGRect
}
