// Siri, Shortcuts, Control Center and the Action Button (2026-11-06). The route waits in the shared defaults; the app
// reads it when it comes to the front. Compiled into the app and the widget extension.
import AppIntents
import Foundation

enum MemoriesScreen: String, AppEnum {
    case dinle, oku, kaydet
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Ekran"
    static let caseDisplayRepresentations: [MemoriesScreen: DisplayRepresentation] = [
        .dinle: "Bugünü dinle", .oku: "Cümleleri oku", .kaydet: "Metni kaydet",
    ]
}

struct OpenMemoriesIntent: AppIntent {
    static let title: LocalizedStringResource = "Memories'i aç"
    static let description = IntentDescription("Memories'i açar. Dinle seçilirse bugünün sesi başlar.")
    static let openAppWhenRun = true
    @Parameter(title: "Ekran", default: .dinle) var screen: MemoriesScreen
    init() {}
    init(_ s: MemoriesScreen) { screen = s }
    func perform() async throws -> some IntentResult {
        Paylasim.ayar.set(screen.rawValue, forKey: "w.rota")
        return .result()
    }
}
