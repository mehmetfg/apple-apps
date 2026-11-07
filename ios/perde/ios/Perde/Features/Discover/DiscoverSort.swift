import Foundation

enum DiscoverSort: String, CaseIterable, Identifiable, Hashable, Sendable {
    case popular
    case imdb
    case personalMatch
    case newest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .popular: "Popüler"
        case .imdb: "IMDb (oy sayısıyla)"
        case .personalMatch: "Bana uygun"
        case .newest: "En yeni"
        }
    }
}
