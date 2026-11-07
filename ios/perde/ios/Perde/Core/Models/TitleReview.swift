import Foundation

struct TitleReview: Identifiable, Hashable, Sendable {
    let id: String
    let author: String
    let content: String
    let authorScore: Double?
    let createdAt: Date?
}
