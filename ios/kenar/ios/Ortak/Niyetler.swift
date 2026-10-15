// Niyetler (App Intents): Siri, Kestirmeler, NFC otomasyonu, Denetim Merkezi, kilit ekranı, Canlı Etkinlik düğmeleri.
// Bu dosya uygulamada ve widget uzantısında derlenir (WIDGET bayrağı uzantıda). Uygulamayı açan niyetler rotayı
// ortak dolaba bırakır; uygulama öne gelince oraya gider.
import Foundation
import AppIntents
import ActivityKit

/// Okuma oturumu Canlı Etkinliği: kilit ekranında kitap, taşıdığın soru, süre ve işaret sayısı.
struct OkumaEtkinligi: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var baslangic: Date
        var isaret: Int
    }
    var kitapAdi: String
    var soru: String
}

struct OkumayaBaslaNiyeti: AppIntent {
    static let title: LocalizedStringResource = "Okumaya başla"
    static let description = IntentDescription("Kenar'da okuma oturumunu açar: önce soru, sonra okuma.")
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult { Depo.rotaBirak("kenar://oku/basla"); return .result() }
}

struct KamerayaIsaretNiyeti: AppIntent {
    static let title: LocalizedStringResource = "Kamerayla işaretle"
    static let description = IntentDescription("Kâğıt kitaptaki cümleyi kamerayla seçip işaret yapar.")
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult { Depo.rotaBirak("kenar://kamera"); return .result() }
}

struct AnlatNiyeti: AppIntent {
    static let title: LocalizedStringResource = "Feynman dakikası"
    static let description = IntentDescription("Kitabı kapat, 60 saniye sesli anlat.")
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult { Depo.rotaBirak("kenar://anlat"); return .result() }
}

struct KutuyuAcNiyeti: AppIntent {
    static let title: LocalizedStringResource = "Kenar kutusunu aç"
    static let description = IntentDescription("Bölüme atanmayı bekleyen işaretler.")
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult { Depo.rotaBirak("kenar://kutu"); return .result() }
}

/// Canlı Etkinlikteki "Bitir": uygulamayı açmadan oturumu kapatır.
struct OturumuBitirNiyeti: LiveActivityIntent {
    static let title: LocalizedStringResource = "Okuma oturumunu bitir"
    static let openAppWhenRun = false
    func perform() async throws -> some IntentResult {
        #if !WIDGET
        await Merkez.paylasilan?.oturumuBitir()
        #endif
        for a in Activity<OkumaEtkinligi>.activities { await a.end(nil, dismissalPolicy: .immediate) }
        return .result()
    }
}

#if !WIDGET
struct KenarKestirmeleri: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OkumayaBaslaNiyeti(), phrases: ["\(.applicationName) ile okumaya başla", "\(.applicationName) okuma oturumu"],
                    shortTitle: "Okumaya başla", systemImageName: "book")
        AppShortcut(intent: KamerayaIsaretNiyeti(), phrases: ["\(.applicationName) ile kamerayla işaretle"],
                    shortTitle: "Kamerayla işaretle", systemImageName: "camera.viewfinder")
        AppShortcut(intent: AnlatNiyeti(), phrases: ["\(.applicationName) ile anlat", "\(.applicationName) Feynman dakikası"],
                    shortTitle: "Feynman dakikası", systemImageName: "mic")
        AppShortcut(intent: KutuyuAcNiyeti(), phrases: ["\(.applicationName) kutusunu aç"],
                    shortTitle: "Kenar kutusu", systemImageName: "tray")
    }
}

/// Okuma Odağı süzgeci: Ayarlar › Odak › (bir odak) › Odak Süzgeçleri › Kenar. Odak açıkken Kenar doğrudan Oku'da açılır,
/// öteki sekmeler gizlenir; kapanınca her şey geri gelir.
struct OkumaOdagiSuzgeci: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Okuma Odağı"
    static let description: IntentDescription? = IntentDescription("Odak açıkken Kenar yalnız okuma ekranını gösterir.")
    @Parameter(title: "Yalnız okuma ekranı", default: true) var yalnizOku: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: yalnizOku ? "Yalnız okuma ekranı" : "Kenar normal")
    }

    func perform() async throws -> some IntentResult {
        Depo.ayar.set(yalnizOku, forKey: "odak")
        await MainActor.run { Merkez.paylasilan?.odakDegisti() }
        return .result()
    }
}
#endif
