// Ortak dolap (App Group). Uygulama, widget ve paylaşım uzantısı buradan konuşur.
//   group.com.fatihgocgun.kenar   → Kenar'ın kendi dolabı: kenar.json, widget özeti, paylaşılanlar (gelen/), ses/
//   group.com.fatihgocgun.atolye  → Kenar ↔ Ayna devir teslimi: ayna-kuyrugu.json (Kenar yazar), ayna-donus.json (Ayna yazar)
import Foundation

enum Depo {
    static let grup = "group.com.fatihgocgun.kenar"
    static let atolye = "group.com.fatihgocgun.atolye"

    static var klasor: URL {
        if let u = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: grup) { return u }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    static var ayar: UserDefaults { UserDefaults(suiteName: grup) ?? .standard }

    static var sesKlasoru: URL { alt("ses") }
    static var gelenKlasoru: URL { alt("gelen") }

    private static func alt(_ ad: String) -> URL {
        let u = klasor.appendingPathComponent(ad, isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    // MARK: durum
    private static var durumURL: URL { klasor.appendingPathComponent("kenar.json") }

    static let kodlayici: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]; return e
    }()
    static let cozucu: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    static func durumOku() -> KenarDurum? {
        guard let d = try? Data(contentsOf: durumURL) else { return nil }
        return try? cozucu.decode(KenarDurum.self, from: d)
    }

    static func durumYaz(_ v: KenarDurum) {
        if let d = try? kodlayici.encode(v) { try? d.write(to: durumURL, options: .atomic) }
        if let o = v.ozet, let d = try? kodlayici.encode(o) { ayar.set(d, forKey: "ozet") }
    }

    static var ozet: WidgetOzet? {
        guard let d = ayar.data(forKey: "ozet") else { return nil }
        return try? cozucu.decode(WidgetOzet.self, from: d)
    }

    // MARK: rota — niyetler ve denetimler uygulamayı açarken nereye gidileceğini buraya bırakır
    static func rotaBirak(_ adres: String) { ayar.set(adres, forKey: "rota") }
    static func rotaAl() -> String? {
        let r = ayar.string(forKey: "rota"); ayar.removeObject(forKey: "rota"); return r
    }

    // MARK: paylaşım uzantısının bıraktıkları
    struct Gelen: Codable { var metin: String; var adres: String?; var kaynakUygulama: String?; var tarih: Date }

    static func gelenBirak(_ g: Gelen) {
        let u = gelenKlasoru.appendingPathComponent(Kimlik.yeni() + ".json")
        if let d = try? kodlayici.encode(g) { try? d.write(to: u, options: .atomic) }
    }

    static func gelenleriAl() -> [Gelen] {
        let fm = FileManager.default
        guard let dosyalar = try? fm.contentsOfDirectory(at: gelenKlasoru, includingPropertiesForKeys: nil) else { return [] }
        var sonuc: [Gelen] = []
        for f in dosyalar where f.pathExtension == "json" {
            if let d = try? Data(contentsOf: f), let g = try? cozucu.decode(Gelen.self, from: d) { sonuc.append(g) }
            try? fm.removeItem(at: f)
        }
        return sonuc.sorted { $0.tarih < $1.tarih }
    }

    // MARK: Ayna ile devir teslim
    struct AynaIsi: Codable, Hashable { var id: String; var metin: String; var bolumNo: Int; var baslik: String; var iddia: String; var paragraf: String; var tarih: Date }
    struct AynaDonus: Codable, Hashable { var id: String; var ingilizce: String; var tarih: Date }

    static var atolyeKlasoru: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: atolye) }

    static func aynayaGonder(_ isler: [AynaIsi]) {
        guard let k = atolyeKlasoru, let d = try? kodlayici.encode(isler) else { return }
        try? d.write(to: k.appendingPathComponent("ayna-kuyrugu.json"), options: .atomic)
    }

    static func aynadanGelen() -> [AynaDonus] {
        guard let k = atolyeKlasoru, let d = try? Data(contentsOf: k.appendingPathComponent("ayna-donus.json")) else { return [] }
        return (try? cozucu.decode([AynaDonus].self, from: d)) ?? []
    }
}
