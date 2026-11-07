import Foundation

enum MediaKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case movie
    case tv

    var id: String { rawValue }

    var label: String {
        switch self {
        case .movie: "Film"
        case .tv: "Dizi"
        }
    }
}
