// Ortak dolaplar:
//   group.com.fatihgocgun.ayna    → Ayna'nın kendi dolabı (durum, widget özeti, kapı seçimi ve sayaç, ses)
//   group.com.fatihgocgun.atolye  → Kenar ↔ Ayna: ayna-kuyrugu.json (Kenar yazar) · ayna-donus.json (Ayna yazar)
import Foundation

enum Depo {
    static let grup = "group.com.fatihgocgun.ayna"
    static let atolye = "group.com.fatihgocgun.atolye"

    static var klasor: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: grup) ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    static var ayar: UserDefaults { UserDefaults(suiteName: grup) ?? .standard }
    static var sesKlasoru: URL {
        let u = klasor.appendingPathComponent("ses", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static let kodlayici: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]; return e }()
    static let cozucu: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    private static var durumURL: URL { klasor.appendingPathComponent("ayna.json") }

    static func durumOku() -> AynaDurum {
        guard let d = try? Data(contentsOf: durumURL), let v = try? cozucu.decode(AynaDurum.self, from: d) else { return AynaDurum() }
        return v
    }

    static func durumYaz(_ v: AynaDurum) {
        if let d = try? kodlayici.encode(v) { try? d.write(to: durumURL, options: .atomic) }
        let hata = v.kayitlar.reversed().lazy.compactMap { $0.hatalar.first }.first
        let o = WidgetOzet(yanlis: hata?.yanlis ?? "", dogru: hata?.dogru ?? "", kural: hata?.kural ?? "",
                           bekleyen: v.kayitlar.filter { $0.duzeltme != nil && !$0.dinlendi }.count)
        if let d = try? kodlayici.encode(o) { ayar.set(d, forKey: "ozet") }
    }

    static var ozet: WidgetOzet? { ayar.data(forKey: "ozet").flatMap { try? cozucu.decode(WidgetOzet.self, from: $0) } }

    /// Kapı uzantısı "Söyle" deyince bir an bırakır; uygulama açılınca Bugün'de istem olarak görünür.
    static func kapiAniBirak() {
        var d = durumOku(); d.kapiIstemleri.append(.now); d.kapiIstemleri = Array(d.kapiIstemleri.suffix(10)); durumYaz(d)
    }

    static func rotaBirak(_ s: String) { ayar.set(s, forKey: "rota") }
    static func rotaAl() -> String? { let r = ayar.string(forKey: "rota"); ayar.removeObject(forKey: "rota"); return r }

    // MARK: Kenar
    static var atolyeKlasoru: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: atolye) }

    static func kenarKuyrugu() -> [KenarIsi] {
        guard let k = atolyeKlasoru, let d = try? Data(contentsOf: k.appendingPathComponent("ayna-kuyrugu.json")) else { return [] }
        return (try? cozucu.decode([KenarIsi].self, from: d)) ?? []
    }

    struct KenarDonus: Codable { var id: String; var ingilizce: String; var tarih: Date }

    static func kenaraDon(_ x: [KenarDonus]) {
        guard let k = atolyeKlasoru, let d = try? kodlayici.encode(x) else { return }
        try? d.write(to: k.appendingPathComponent("ayna-donus.json"), options: .atomic)
    }
}
