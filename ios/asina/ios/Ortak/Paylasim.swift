// Uygulama ↔ widget arasında paylaşılan küçük anlık görüntü (App Group kapsayıcısı).
// Uygulama her değişiklikte yazar; widget yalnız okur. Widget kendi başına FSRS hesaplamaz.
import Foundation

enum Paylasim {
    static let grup = "group.com.fatihgocgun.asina"
    static let widgetTuru = "AsinaKelime"
    static let ilerlemeTuru = "AsinaIlerleme"

    static var kapsayici: URL {
        if let u = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: grup) {
            return u
        }
        // App Group imzalanamadıysa (ör. imzasız simülatör derlemesi) uygulama kendi klasörüne düşer.
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var ayar: UserDefaults { UserDefaults(suiteName: grup) ?? .standard }

    static var anlikURL: URL { kapsayici.appendingPathComponent("widget.json") }

    static func oku() -> Anlik? {
        guard let v = try? Data(contentsOf: anlikURL) else { return nil }
        return try? JSONDecoder().decode(Anlik.self, from: v)
    }

    static func yaz(_ a: Anlik) {
        if let v = try? JSONEncoder().encode(a) {
            try? v.write(to: anlikURL, options: .atomic)
        }
    }

    // Widget düğmelerinin durumu
    static let siraAnahtari = "widget.sira"
    static let acikAnahtari = "widget.acik"
    static let hatirlaAnahtari = "widget.oncehatirla"
    static let oxfordAnahtari = "ayar.oxfordsesi"
}

/// Widget'ta gösterilecek tek kelime — tam kayıt değil, gereken kadarı.
struct WKelime: Codable, Hashable, Identifiable {
    let i: Int
    let w: String
    let ipa: String
    let tr: String
    let d: String
    let x: String?
    let c: String
    let p: String
    let asama: Int          // -1 = bugün yeni
    var au: String? = nil
    var pv: Bool { p == "deyimsel fiil" }

    var id: Int { i }
}

struct Anlik: Codable {
    var guncel: Date
    /// "yyyy-MM-dd" → o günün kelimeleri (bugün + önümüzdeki iki gün; uygulama açılmasa da widget yürür)
    var gunler: [String: [WKelime]]
    var bugunHedef: Int
    var bugunYapilan: Int
    var seri: Int
    var asina: Int
    var oturmus: Int
    var depoKalan: Int
    /// Son 7 günün yapılan sayıları (eskiden yeniye)
    var hafta: [Int]

    func kelimeler(_ gun: Date = Date()) -> [WKelime] {
        if let k = gunler[gun.gunAnahtari], !k.isEmpty { return k }
        // Uygulama günlerce açılmadıysa en son günün listesini yürüt.
        return gunler.keys.sorted().last.flatMap { gunler[$0] } ?? []
    }

    static let ornek = Anlik(
        guncel: Date(),
        gunler: [Date().gunAnahtari: [
            WKelime(i: 1, w: "acquire", ipa: "/əˈkwaɪə(r)/", tr: "edinmek",
                    d: "to gain something by your own efforts", x: "She has acquired a good knowledge of English.",
                    c: "B2", p: "verb", asama: -1),
            WKelime(i: 2, w: "brisk", ipa: "/brɪsk/", tr: "canlı, hızlı",
                    d: "quick; busy", x: "We went for a brisk walk.", c: "C1", p: "adjective", asama: 0),
        ]],
        bugunHedef: 30, bugunYapilan: 12, seri: 4, asina: 140, oturmus: 38, depoKalan: 2410,
        hafta: [18, 25, 0, 30, 22, 27, 12])
}
