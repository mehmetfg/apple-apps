import Foundation

/// Mood shelves built from TMDB genre ids, which differ between films and series.
enum TasteCategory: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all
    case mindBending
    case deepDrama
    case tense
    case lightFun
    case trueStory
    case action
    case family

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "Hepsi"
        case .mindBending: "Zihin açan"
        case .deepDrama: "Derin dram"
        case .tense: "Gerilim"
        case .lightFun: "Hafif ve neşeli"
        case .trueStory: "Gerçek hikâye"
        case .action: "Aksiyon"
        case .family: "Aile"
        }
    }

    func genreIds(for kind: MediaKind) -> [Int] {
        switch (self, kind) {
        case (.all, _): []
        case (.mindBending, .movie): [878, 9648]
        case (.mindBending, .tv): [10765, 9648]
        case (.deepDrama, _): [18]
        case (.tense, .movie): [53, 80, 27]
        case (.tense, .tv): [80, 9648]
        case (.lightFun, .movie): [35, 10749]
        case (.lightFun, .tv): [35]
        case (.trueStory, .movie): [99, 36]
        case (.trueStory, .tv): [99]
        case (.action, .movie): [28, 12]
        case (.action, .tv): [10759]
        case (.family, .movie): [10751, 16]
        case (.family, .tv): [10751, 16, 10762]
        }
    }
}
