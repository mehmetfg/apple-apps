import Foundation

enum TitleOrigin: String, CaseIterable, Identifiable, Hashable, Sendable {
    case any
    case turkish
    case foreign

    var id: String { rawValue }

    var label: String {
        switch self {
        case .any: "Hepsi"
        case .turkish: "Yerli"
        case .foreign: "Yabancı"
        }
    }
}
