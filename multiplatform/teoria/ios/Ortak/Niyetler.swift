// Widget ve Denetim Merkezi düğmeleri (App Intents). Widget hesap yapmaz:
// yalnız App Group'taki küçük durumu değiştirir ve olayı kutuya bırakır; uygulama açılınca günlüğe alır.
import AppIntents
import WidgetKit

struct SonrakiAforizma: AppIntent {
    static var title: LocalizedStringResource = "Sonraki aforizma"
    static var description = IntentDescription("Widget'taki aforizmayı bir sonrakine çevirir.")
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        let a = Paylasim.ayar
        a.set(a.integer(forKey: Paylasim.afoSira) + 1, forKey: Paylasim.afoSira)
        WidgetCenter.shared.reloadTimelines(ofKind: Paylasim.aforizmaTuru)
        return .result()
    }
}

struct AforizmaFavori: AppIntent {
    static var title: LocalizedStringResource = "Favorilere ekle"
    static var isDiscoverable = false

    @Parameter(title: "Kimlik") var kimlik: String

    init() {}
    init(kimlik: String) { self.kimlik = kimlik }

    func perform() async throws -> some IntentResult {
        guard var anlik = Paylasim.oku(), let i = anlik.aforizmalar.firstIndex(where: { $0.id == kimlik }) else {
            return .result()
        }
        anlik.aforizmalar[i].favori.toggle()
        Paylasim.kutuyaAt(Olay(tur: .favori, hedef: kimlik, deger: anlik.aforizmalar[i].favori))
        Paylasim.yaz(anlik)
        WidgetCenter.shared.reloadTimelines(ofKind: Paylasim.aforizmaTuru)
        return .result()
    }
}

struct CevabiGoster: AppIntent {
    static var title: LocalizedStringResource = "Cevabı göster"
    static var description = IntentDescription("Önce hatırlamaya çalış; sonra cevabı aç.")
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        let a = Paylasim.ayar
        a.set(!a.bool(forKey: Paylasim.hatAcik), forKey: Paylasim.hatAcik)
        WidgetCenter.shared.reloadTimelines(ofKind: Paylasim.hatirlaTuru)
        return .result()
    }
}

struct HatirlaCevap: AppIntent {
    static var title: LocalizedStringResource = "Hatırladım / Bilemedim"
    static var isDiscoverable = false

    @Parameter(title: "Kart") var kart: String
    @Parameter(title: "Hatırladı") var hatirladi: Bool

    init() {}
    init(kart: String, hatirladi: Bool) { self.kart = kart; self.hatirladi = hatirladi }

    func perform() async throws -> some IntentResult {
        Paylasim.kutuyaAt(Olay(tur: .cevap, hedef: kart, hat: .hatirla, puan: hatirladi ? 1 : 0,
                               not: hatirladi ? Not.iyi.rawValue : Not.unuttum.rawValue, rol: "widget"))
        let a = Paylasim.ayar
        a.set(a.integer(forKey: Paylasim.hatSira) + 1, forKey: Paylasim.hatSira)
        a.set(false, forKey: Paylasim.hatAcik)
        WidgetCenter.shared.reloadTimelines(ofKind: Paylasim.hatirlaTuru)
        WidgetCenter.shared.reloadTimelines(ofKind: Paylasim.kurTuru)
        return .result()
    }
}

/// Uygulamayı açıp bir ekrana götürür (Denetim Merkezi, Eylem düğmesi, Kestirmeler).
struct TeoriaAc: AppIntent {
    static var title: LocalizedStringResource = "Teoria'yı aç"
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Ekran", default: .kur) var ekran: TeoriaEkrani

    init() {}
    init(_ e: TeoriaEkrani) { ekran = e }

    func perform() async throws -> some IntentResult {
        Paylasim.ayar.set(ekran.rawValue, forKey: "w.ac")
        return .result()
    }
}

enum TeoriaEkrani: String, AppEnum {
    case kur, ses, akis, hatirla

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Ekran"
    static var caseDisplayRepresentations: [TeoriaEkrani: DisplayRepresentation] = [
        .kur: "Kür başlat", .ses: "Sesli not", .akis: "Akış", .hatirla: "Hatırla",
    ]
}
