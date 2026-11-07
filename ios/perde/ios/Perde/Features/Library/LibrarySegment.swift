import Foundation

enum LibrarySegment: String, CaseIterable, Identifiable {
    case priority
    case listed
    case watched

    var id: String { rawValue }

    var label: String {
        switch self {
        case .priority: "Öncelikli"
        case .listed: "Listem"
        case .watched: "İzlediklerim"
        }
    }
}
