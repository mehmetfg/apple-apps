// Memories — İngilizce Ön Çalışma. Veri modeli (uygulama ve widget ortak).
// Kaynak: vault'ta 01 - English Learning/oncalisma/paket/gun-NNN/paket.json (oncalisma.py yazar).
// Akış: ① mobilde çalış (dinle · oku · kendi sesinle oku) → ② Mac'te yaz (Cümle Tezgâhı) → ③ çözümle (ertesi sabah).
import Foundation

// MARK: - Paket (paket.json)

struct Paket: Codable, Hashable, Identifiable {
    var gun: Int
    var baslik: String?
    var surum: String?
    var uretildi: String?
    var sure_sn: Double?
    var kelime: Int?
    var tanidik: Double?
    var ses: String?
    var bolumler: [Bolum]?
    var satirlar: [Satir]?
    var metin: [Cumle]?
    var ozet: String?
    var tema: String?
    var sahne_konulari: [String]?
    var sozluk: [Sozcuk]?

    var id: Int { gun }
    var ad: String { baslik ?? "Gün \(gun)" }
    var sure: Double { sure_sn ?? 0 }
    var cumleler: [Cumle] { metin ?? [] }
    var klasorAdi: String { Paket.klasor(gun) }

    static func klasor(_ gun: Int) -> String { String(format: "gun-%03d", gun) }

    func bolum(_ t: Double) -> Bolum? {
        (bolumler ?? []).last { t + 0.05 >= $0.baslangic }
    }
    func satir(_ t: Double) -> Satir? {
        (satirlar ?? []).last { t + 0.05 >= $0.baslangic && t < $0.bitis + 0.9 }
    }
    func cumleZamani(_ i: Int) -> Satir? { (satirlar ?? []).first { $0.cumle == i } }
    func kelime(_ w: String) -> Sozcuk? {
        let k = w.lowercased()
        return (sozluk ?? []).first { s in
            let a = s.w.lowercased()
            return k == a || k == a + "s" || k == a + "es" || k == a + "ed" || k == a + "d" || k == a + "ing"
                || (a.hasSuffix("e") && k == String(a.dropLast()) + "ing") || k == a + "ly"
        }
    }
}

struct Bolum: Codable, Hashable, Identifiable {
    var ad: String
    var baslangic: Double
    var bitis: Double
    var id: String { ad }
    var etiket: String {
        switch ad {
        case "aciklama": "Açıklama"
        case "metin": "Metin"
        case "kelimeler": "Kelimeler ve yapılar"
        default: ad.capitalized
        }
    }
    var simge: String {
        switch ad {
        case "aciklama": "text.bubble"
        case "metin": "text.alignleft"
        case "kelimeler": "character.book.closed"
        default: "circle"
        }
    }
}

struct Satir: Codable, Hashable {
    var bolum: String?
    var s: String
    var t: String
    var baslangic: Double
    var bitis: Double
    var cumle: Int?
}

struct Cumle: Codable, Hashable, Identifiable {
    var i: Int
    var en: String?
    var tr: String?
    var konu: String?
    var id: Int { i }
}

struct Sozcuk: Codable, Hashable, Identifiable {
    var w: String
    var tur: String?
    var pos: String?
    var cefr: String?
    var ipa: String?
    var tanim: String?
    var tr: String?
    var ornek: String?
    var id: String { w }
    var turAdi: String {
        switch tur { case "yeni": "yeni"; case "yanki": "tekrar"; case "tanidik": "tanıdık"; default: "" }
    }
}

// MARK: - Çözüm (cozum.json, ertesi sabah Mac'te yazılır)

struct Cozum: Codable, Hashable {
    struct Yazim: Codable, Hashable {
        var ilk_yazim_ort: Int?
        var cumle: Int?
        var tam_isabet: Int?
        var kendinden: Int?
        var hata_turleri: [String: Int]?
        var sure_dk: Double?
    }
    struct Duzeltme: Codable, Hashable { var yazdigin: String?; var dogrusu: String?; var tr: String?; var yuzde: Int? }
    struct EnIyi: Codable, Hashable { var en: String?; var tr: String? }
    struct Fark: Codable, Hashable { var metin: String; var duyulan: String }
    struct Okuma: Codable, Hashable {
        var dosya: String
        var cihaz: String?
        var ortusme: Double?
        var atlanan: [String]?
        var farkli: [Fark]?
        var hata: String?
    }
    struct Rota: Codable, Hashable, Identifiable { var tur: String; var sayi: Int; var gun: Int?; var not: String?; var id: String { tur } }

    var gun: Int
    var baslik: String?
    var zaman: String?
    var yazim: Yazim?
    var duzeltme: Duzeltme?
    var en_iyi: EnIyi?
    var okumalar: [Okuma]?
    var yol_haritasi: [Rota]?
    var kaynak: String?             // "mac": aynı gün Cümle (Mac) yazdı (yazim.json); sabah cozum.json üstüne geçer
    var zorlar: [Duzeltme]?         // en çok zorlanılan en fazla 3 cümle
    var macten: Bool { kaynak == "mac" }
}

// MARK: - Olay günlüğü (ilerleme/<cihaz>.jsonl)

enum OlayTuru: String, Codable {
    case dinledi      // ses dosyasının ≥ %80'i gerçekten çalındı
    case okudu        // metin ekranda sonuna kadar okundu
    case kaydetti     // kendi sesinle okuma kaydı
    case hazirim      // ① bitti (kendiliğinden ya da elle)
    case takildi      // bir cümlede takıldın: yineledin, geri sardın, tek başına dinledin ya da Türkçesine baktın
    case basladi, bitti   // Mac'te Tezgâh (yalnız okunur)
    case atladi           // «Yaptım, geç»: gün sicile girmez, sıradaki gün açılır (iki cihaz da yazabilir)
}

struct Olay: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString.lowercased()
    var cihaz: String = Cihaz.ad
    var t: Date = Date()
    var gun: Int
    var surum: String?
    var tur: OlayTuru
    var oran: Double?
    var sure: Double?
    var dosya: String?
    var tanima: Double?
    var takilan: [String]?
    var rol: String?
    var cumle: Int?             // takildi: hangi cümle (0'dan) — Mac'te metin haritasında işaretlenir

    enum CodingKeys: String, CodingKey { case id, cihaz, t, gun, surum, tur, oran, sure, dosya, tanima, takilan, rol, cumle }

    init(gun: Int, surum: String?, tur: OlayTuru) { self.gun = gun; self.surum = surum; self.tur = tur }

    // Mac tarafının yazdığı bilinmeyen tür ya da eksik alan satırı düşürmesin.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        cihaz = (try? c.decode(String.self, forKey: .cihaz)) ?? "?"
        if let tarih = try? c.decode(Date.self, forKey: .t) { t = tarih }
        else if let s = try? c.decode(String.self, forKey: .t), let tarih = Tarih.coz(s) { t = tarih }
        gun = try c.decode(Int.self, forKey: .gun)
        surum = try? c.decode(String.self, forKey: .surum)
        guard let tr = OlayTuru(rawValue: (try? c.decode(String.self, forKey: .tur)) ?? "") else {
            throw DecodingError.dataCorruptedError(forKey: .tur, in: c, debugDescription: "bilinmeyen tür")
        }
        tur = tr
        oran = try? c.decode(Double.self, forKey: .oran)
        sure = try? c.decode(Double.self, forKey: .sure)
        dosya = try? c.decode(String.self, forKey: .dosya)
        tanima = try? c.decode(Double.self, forKey: .tanima)
        takilan = try? c.decode([String].self, forKey: .takilan)
        rol = try? c.decode(String.self, forKey: .rol)
        cumle = try? c.decode(Int.self, forKey: .cumle)
    }
}

/// Bir günün ① durumu — yalnız olaylardan hesaplanır.
struct Hazirlik: Hashable {
    var dinleme = 0
    var okuma = false
    var kayit = 0
    var hazir = false
    var yazildi = false        // Mac'te Tezgâh bitti
    var takilan: [String] = []

    var adim: Int { (dinleme > 0 ? 1 : 0) + (okuma ? 1 : 0) + (kayit > 0 ? 1 : 0) }
    var basladi: Bool { dinleme > 0 || okuma || kayit > 0 }

    static func kur(_ olaylar: [Olay], gun: Int) -> Hazirlik {
        var h = Hazirlik()
        for o in olaylar where o.gun == gun {
            switch o.tur {
            case .dinledi: h.dinleme += 1
            case .okudu: h.okuma = true
            case .kaydetti:
                h.kayit += 1
                for w in o.takilan ?? [] where !h.takilan.contains(w) { h.takilan.append(w) }
            case .hazirim: h.hazir = true
            case .bitti: h.yazildi = true
            case .basladi, .takildi, .atladi: break
            }
        }
        if h.dinleme > 0 && h.okuma { h.hazir = true }
        return h
    }
}

// MARK: - Yardımcılar

enum Cihaz {
    static let ad = "iphone"
}

enum Tarih {
    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    static let yerel: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()
    static func coz(_ s: String) -> Date? { iso.date(from: s) ?? yerel.date(from: s) }

    static func sure(_ s: Double) -> String {
        let n = max(0, Int(s.rounded()))
        return String(format: "%d:%02d", n / 60, n % 60)
    }
    static func dakika(_ s: Double) -> String {
        let d = s / 60
        return d < 10 ? String(format: "%.1f dk", d).replacingOccurrences(of: ".", with: ",") : "\(Int(d.rounded())) dk"
    }
    static func gorece(_ d: Date) -> String {
        if abs(d.timeIntervalSinceNow) < 60 { return "az önce" }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }
}

enum Metin {
    /// Kelime ayıklama — karşılaştırmada harf dışı her şey düşer, ’ → '.
    static func kelimeler(_ s: String) -> [String] {
        let k = s.lowercased().replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "-", with: " ")
        var sonuc: [String] = []
        var simdi = ""
        for c in k {
            if c.isLetter || (c == "'" && !simdi.isEmpty) { simdi.append(c) }
            else if !simdi.isEmpty { sonuc.append(simdi.trimmingCharacters(in: CharacterSet(charactersIn: "'"))); simdi = "" }
        }
        if !simdi.isEmpty { sonuc.append(simdi) }
        return sonuc
    }

    /// Okunan metinde tanınmayan kelimeler (en uzun ortak alt dizi). Özel isim ve tek harf sayılmaz.
    static func takilanlar(metin: String, duyulan: String) -> (oran: Double, takilan: [String], eslesen: Set<Int>) {
        let a = kelimeler(metin), b = kelimeler(duyulan)
        guard !a.isEmpty else { return (0, [], []) }
        var t = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                t[i][j] = a[i] == b[j] ? t[i + 1][j + 1] + 1 : max(t[i + 1][j], t[i][j + 1])
            }
        }
        var i = 0, j = 0
        var eslesen = Set<Int>()
        while i < a.count && j < b.count {
            if a[i] == b[j] { eslesen.insert(i); i += 1; j += 1 }
            else if t[i + 1][j] >= t[i][j + 1] { i += 1 } else { j += 1 }
        }
        // takılan = SON tanınan kelimeye kadar tanınmayanlar; yarıda bırakılan okumanın kuyruğu takılan sayılmaz
        let son = eslesen.max() ?? -1
        var takilan: [String] = []
        for (k, w) in a.enumerated() where k <= son && !eslesen.contains(k) && w.count > 1 && !takilan.contains(w) { takilan.append(w) }
        return (Double(eslesen.count) / Double(a.count), takilan, eslesen)
    }
}

// MARK: - Widget anlık görüntüsü

struct WidgetAnlik: Codable {
    struct Adim: Codable { var dinleme: Int; var okuma: Bool; var kayit: Int }
    var guncel: Date
    var gun: Int?
    var baslik: String?
    var ozet: String?
    var sure: Double?
    var adim: Adim?
    var anahtar: String?            // metinden bir cümle (EN)
    var anahtarTr: String?
    var dunGun: Int?
    var dunEn: String?              // dünün çözümünden: en iyi ya da düzeltilen cümle
    var dunTr: String?
    var rota: String?               // yol haritasının ilk satırı

    static let ornek = WidgetAnlik(
        guncel: Date(), gun: 22, baslik: "The Market",
        ozet: "Pazar günü semt pazarında küçük bir karışıklık.", sure: 384,
        adim: Adim(dinleme: 1, okuma: true, kayit: 0),
        anahtar: "On Saturday at ten, I visited my aunt after her knee surgery.",
        anahtarTr: "Cumartesi saat onda, diz ameliyatından sonra halamı ziyaret ettim.",
        dunGun: 21, dunEn: "My prime goal was an old edition of my father's favourite novel.",
        dunTr: "Asıl amacım babamın en sevdiği romanın eski bir baskısıydı.",
        rota: "artikel — a / an / the")
}

enum Paylasim {
    static let grup = "group.com.fatihgocgun.memories"

    static var kapsayici: URL {
        if let o = ProcessInfo.processInfo.environment["MEMORIES_KAPSAYICI"] {
            let u = URL(fileURLWithPath: o, isDirectory: true)
            try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
            return u
        }
        if let u = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: grup) { return u }
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Memories", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static var ayar: UserDefaults { UserDefaults(suiteName: grup) ?? .standard }
    static var anlikURL: URL { kapsayici.appendingPathComponent("widget.json") }
    static let dunAcik = "w.dun.acik"

    static func oku() -> WidgetAnlik? {
        guard let v = try? Data(contentsOf: anlikURL) else { return nil }
        let c = JSONDecoder(); c.dateDecodingStrategy = .iso8601
        return try? c.decode(WidgetAnlik.self, from: v)
    }
    static func yaz(_ a: WidgetAnlik) {
        let c = JSONEncoder(); c.dateEncodingStrategy = .iso8601
        if let v = try? c.encode(a) { try? v.write(to: anlikURL, options: .atomic) }
    }
}
