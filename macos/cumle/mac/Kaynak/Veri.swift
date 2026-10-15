// Cümle — veri katmanı. Kaynaklar vault'tan, olduğu gibi okunur (tek kaynak, dönüştürme yok):
//   Artifacts/_data/gun.json          günün metni (sabah 07:10 görevi basar)
//   Artifacts/_data/tezgah-gramer.js  41 gramer kartı (elle düzenlenir)
//   Artifacts/_data/tezgah-arsiv.js   geçmiş günler + sicil (tezgah_arsiv.py türetir)
//   Artifacts/_data/tezgah-sozluk.js  Oxford sözlüğü + yazım listesi
// .js dosyaları JavaScriptCore ile okunur — tarayıcıdaki Tezgâh'la aynı dosyalar, ikinci kopya yok.
// Sınama: CUMLE_VAULT (vault kökü), CUMLE_INDIR (sonuç klasörü) ortam değişkenleri gerçek vault'a yazdırmaz.
import Foundation
import JavaScriptCore

enum Yol {
    static let env = ProcessInfo.processInfo.environment
    static var vault: URL {
        if let v = env["CUMLE_VAULT"] { return URL(fileURLWithPath: v, isDirectory: true) }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/iCloud~md~obsidian/Documents/Personel Data Management", isDirectory: true)
    }
    static var lob: URL { vault.appendingPathComponent("01 - English Learning", isDirectory: true) }
    static var veri: URL { lob.appendingPathComponent("Artifacts/_data", isDirectory: true) }
    static var oncalisma: URL { lob.appendingPathComponent("oncalisma", isDirectory: true) }
    static var ilerleme: URL { oncalisma.appendingPathComponent("ilerleme", isDirectory: true) }
    static var paket: URL { oncalisma.appendingPathComponent("paket", isDirectory: true) }
    static var sonuclar: URL { lob.appendingPathComponent("hatlar/EN-01-orgu/sonuclar", isDirectory: true) }
    /// Oturum, hatırlatma geçmişi, yerel özetler — iCloud'da durur: öteki Mac kaldığın yerden açar.
    static var durum: URL { lob.appendingPathComponent("_projects/cumle/durum", isDirectory: true) }
    /// Sonuç JSON'u buraya iner; sabah görevi Downloads'tan alıp sicile işler (değişmedi).
    static var indir: URL {
        if let v = env["CUMLE_INDIR"] { return URL(fileURLWithPath: v, isDirectory: true) }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }
    static func paketKlasoru(_ gun: Int) -> URL { paket.appendingPathComponent(String(format: "gun-%03d", gun), isDirectory: true) }
}

/// Olay ve kayıt adı için makine kısaltması — Tezgâh sunucusunun mac_cihaz() kuralı: mac-mehmet-macbook-pro.
enum Makine {
    static let ad: String = {
        var a = (Host.current().localizedName ?? ProcessInfo.processInfo.hostName).lowercased()
        for (x, y) in zip("çğıöşü", "cgiosu") { a = a.replacingOccurrences(of: String(x), with: String(y)) }
        let parca = a.split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }.joined(separator: "-")
        return "mac-" + (parca.isEmpty ? "mac" : String(parca.prefix(24)))
    }()
}

// MARK: - JS dosyalarını oku

enum JS {
    /// `window.X = …` dosyasını çalıştırır, istenen değişkenleri JSON nesnesi olarak döndürür.
    static func oku(_ u: URL, _ adlar: [String]) -> [String: Any] {
        guard let kaynak = try? String(contentsOf: u, encoding: .utf8), let c = JSContext() else { return [:] }
        c.evaluateScript("var window = {};")
        c.evaluateScript(kaynak)
        var sonuc: [String: Any] = [:]
        for ad in adlar {
            guard let v = c.evaluateScript("JSON.stringify(window.\(ad) === undefined ? null : window.\(ad))")?.toString(),
                  let d = v.data(using: .utf8),
                  let o = try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed]), !(o is NSNull) else { continue }
            sonuc[ad] = o
        }
        return sonuc
    }
}

// MARK: - Günün metni

struct GunCumle: Codable, Hashable {
    var en: String
    var tr: String?
    var konu: String?
    init(en: String, tr: String? = nil, konu: String? = nil) { self.en = en; self.tr = tr; self.konu = konu }
    init(from d: Decoder) throws {
        if let s = try? d.singleValueContainer().decode(String.self) { en = s; return }
        let c = try d.container(keyedBy: CodingKeys.self)
        en = (try? c.decode(String.self, forKey: .en)) ?? ""
        tr = try? c.decode(String.self, forKey: .tr)
        konu = try? c.decode(String.self, forKey: .konu)
        if konu?.isEmpty == true { konu = nil }
    }
}

struct GunVeri: Codable, Hashable {
    var gun: Int?
    var mod: String?
    var faz: Int?
    var baslik: String?
    var tema: String?
    var ozet: String?
    var sahne_konulari: [String]?
    var cumleler: [GunCumle]
    var yeni: [String]?
    var yanki: [String]?
    var tanidik: [String]?

    var no: Int { gun ?? 0 }
    var sahne: [String] { sahne_konulari ?? [] }
    var ad: String { baslik ?? "Modül" }
    var kurmaKipi: Bool { mod == "kurma" || (yeni ?? []).isEmpty }

    static func yukle() -> GunVeri? {
        let u = Yol.veri.appendingPathComponent("gun.json")
        guard let d = try? Data(contentsOf: u), let g = try? JSONDecoder().decode(GunVeri.self, from: d),
              !g.cumleler.isEmpty else { return nil }
        return g
    }
    static var degisti: Date? {
        (try? Yol.veri.appendingPathComponent("gun.json").resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}

// MARK: - Gramer kartları

struct GramerKart: Hashable, Identifiable {
    var ad: String
    var faz: Int
    var yildiz: Bool
    var tr: String
    var ne: String
    var formul: String
    var ornek: [[String]]
    var tuzak: String
    var yoklaS: String
    var yoklaC: String
    var desen: String
    var id: String { ad }
    var kisaAd: String { Gramer.kisa(ad) }
}

enum Gramer {
    static func yukle() -> [GramerKart] {
        let o = JS.oku(Yol.veri.appendingPathComponent("tezgah-gramer.js"), ["TEZGAH_GRAMER"])
        return (o["TEZGAH_GRAMER"] as? [[String: Any]] ?? []).map { g in
            let y = g["yokla"] as? [String: Any] ?? [:]
            return GramerKart(ad: g.s("ad"), faz: g.i("faz") ?? 1, yildiz: g["yildiz"] as? Bool ?? false,
                              tr: g.s("tr"), ne: g.s("ne"), formul: g.s("formul"),
                              ornek: g["ornek"] as? [[String]] ?? [], tuzak: g.s("tuzak"),
                              yoklaS: y.s("s"), yoklaC: y.s("c"), desen: g.s("desen"))
        }
    }
    static func kisa(_ k: String) -> String {
        var s = k.components(separatedBy: " — ")[0].components(separatedBy: " & ")[0]
        if let r = s.range(of: " vs ") { s = String(s[..<r.lowerBound]) }
        return s
    }
}

// MARK: - Arşiv (tezgah_arsiv.py'nin ürettiği geçmiş + sicil)

struct ArsivCumle: Hashable {
    var no: Int; var en: String; var tr: String; var konu: String
    var yazim: String; var yuzde: Int?; var baktim: Bool; var ipucu: Int; var ht: [String: Int]
}
struct ArsivSoru: Hashable { var bosluk: String; var cevap: String; var verilen: [String]; var sonuc: String?; var tip: String }

struct ArsivGun: Hashable, Identifiable {
    var gun: Int
    var tarih: String
    var baslik: String
    var tema: String
    var ozet: String
    var mod: String
    var faz: Int?
    var sahne: [String]
    var yeni: [String]
    var yanki: [String]
    var tanidik: [String]
    var sureDk: Int?
    var tutma: Int?
    var paragrafMetin: String?
    var paragrafYuzde: Int?
    var recallYuzde: Int?
    var sorular: [ArsivSoru]
    var zor: [String]
    var cumleler: [ArsivCumle]
    var hataTurleri: [String: Int]
    var hatirlatma: [String]
    var kendi: [(konu: String, metin: String)]
    var ipucu: [String: Int]?
    var yerel = false
    var id: String { "\(gun)|\(tarih)" }

    static func == (a: ArsivGun, b: ArsivGun) -> Bool { a.id == b.id && a.yerel == b.yerel }
    func hash(into h: inout Hasher) { h.combine(id) }

    init(_ g: [String: Any], yerel: Bool = false) {
        gun = g.i("gun") ?? 0; tarih = g.s("tarih"); baslik = g.s("baslik"); tema = g.s("tema"); ozet = g.s("ozet")
        mod = g.s("mod"); faz = g.i("faz")
        sahne = g.l("sahne"); yeni = g.l("yeni"); yanki = g.l("yanki"); tanidik = g.l("tanidik")
        sureDk = g.i("sure_dk"); tutma = g.i("tutma")
        let p = g["paragraf"] as? [String: Any]
        paragrafMetin = p?["metin"] as? String; paragrafYuzde = p?.i("yuzde")
        let r = g["recall"] as? [String: Any]
        recallYuzde = (r?["ozet"] as? [String: Any])?.i("yuzde")
        sorular = (r?["sorular"] as? [[String: Any]] ?? []).map {
            ArsivSoru(bosluk: $0.s("bosluk"), cevap: $0.s("cevap"), verilen: $0.l("verilen"), sonuc: $0["sonuc"] as? String, tip: $0.s("tip"))
        }
        zor = g.l("zor")
        cumleler = (g["cumleler"] as? [[String: Any]] ?? []).map {
            ArsivCumle(no: $0.i("no") ?? 0, en: $0.s("en"), tr: $0.s("tr"), konu: $0.s("konu"), yazim: $0.s("yazim"),
                       yuzde: $0.i("yuzde"), baktim: $0["baktim"] as? Bool ?? false, ipucu: $0.i("ipucu") ?? 0,
                       ht: ($0["ht"] as? [String: Any] ?? [:]).compactMapValues { ($0 as? NSNumber)?.intValue })
        }
        hataTurleri = (g["hata_turleri"] as? [String: Any] ?? [:]).compactMapValues { ($0 as? NSNumber)?.intValue }
        hatirlatma = g.l("hatirlatma")
        kendi = (g["kendi"] as? [[String: Any]] ?? []).map { ($0.s("konu"), $0.s("metin")) }
        ipucu = (g["ipucu"] as? [String: Any])?.compactMapValues { ($0 as? NSNumber)?.intValue }
        self.yerel = yerel
    }
}

struct KurmaYapi { var gun: Int; var skor: Int? }

struct Arsiv {
    var gunler: [ArsivGun] = []
    var kurmaYapilar: [String: [KurmaYapi]] = [:]

    static func yukle() -> Arsiv {
        let o = JS.oku(Yol.veri.appendingPathComponent("tezgah-arsiv.js"), ["TEZGAH_ARSIV"])
        guard let a = o["TEZGAH_ARSIV"] as? [String: Any] else { return Arsiv() }
        var s = Arsiv()
        s.gunler = (a["gunler"] as? [[String: Any]] ?? []).map { ArsivGun($0) }
        let ky = (a["sicil"] as? [String: Any])?["kurma_yapilar"] as? [String: Any] ?? [:]
        for (ad, v) in ky {
            let g = (v as? [String: Any])?["gunler"] as? [[String: Any]] ?? []
            s.kurmaYapilar[ad] = g.map { KurmaYapi(gun: $0.i("gun") ?? 0, skor: $0.i("skor") ?? $0.i("ilk")) }
        }
        return s
    }
}

// MARK: - Sözlük + yazım listesi

struct Sozcuk: Hashable {
    var w: String; var tr: String; var cefr: String; var pos: String; var phon: String; var def: String; var ex: [String]; var ses: String
}

final class Sozluk: @unchecked Sendable {
    static let ox = "https://www.oxfordlearnersdictionaries.com/media/english/"
    private(set) var kayit: [String: Sozcuk] = [:]
    private(set) var yazim: Set<String> = []
    private(set) var hazir = false

    func yukle() {
        let o = JS.oku(Yol.veri.appendingPathComponent("tezgah-sozluk.js"), ["TEZGAH_SOZLUK", "TEZGAH_YAZIM"])
        var k: [String: Sozcuk] = [:]
        for satir in (o["TEZGAH_SOZLUK"] as? String ?? "").split(separator: "\n") {
            let p = satir.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard p.count >= 5 else { continue }
            let al = { (i: Int) in i < p.count ? p[i] : "" }
            k[p[0]] = Sozcuk(w: p[0], tr: al(1), cefr: al(2), pos: al(3), phon: al(4), def: al(5),
                             ex: al(6).isEmpty ? [] : al(6).components(separatedBy: "|"), ses: al(7))
        }
        var y = Set<String>()
        var onceki = ""
        for satir in (o["TEZGAH_YAZIM"] as? String ?? "").split(separator: "\n") {
            guard let ilk = satir.unicodeScalars.first else { continue }
            let n = max(0, Int(ilk.value) - 65)
            let w = String(onceki.prefix(n)) + String(satir.dropFirst())
            y.insert(w); onceki = w
        }
        kayit = k; yazim = y; hazir = true
    }

    /// Kelimenin sözlük kaydı: kendisi yoksa gövdesi.
    func bul(_ kelime: String) -> Sozcuk? {
        var w = kelime.lowercased()
        if let r = w.firstIndex(where: { $0 == "'" || $0 == "’" }) { w = String(w[..<r]) }
        if let s = kayit[w] { return s }
        for g in Metin.govdeler(w) { if let s = kayit[g] { return s } }
        return nil
    }

    private static let kisaltma: Set<String> = ["t", "s", "re", "ve", "ll", "d", "m"]
    func dogruMu(_ kelime: String) -> Bool {
        let w = kelime.lowercased()
        if w.isEmpty || w.contains(where: \.isNumber) || !hazir { return true }
        if w.contains("'") || w.contains("’") {
            let p = w.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "'" || $0 == "’" }).map(String.init)
            let kok = p[0], son = p.dropFirst().joined()
            if son == "nt" && kok.hasSuffix("n") { return dogruMu(String(kok.dropLast())) || yazim.contains(kok) }
            if Sozluk.kisaltma.contains(son) { return dogruMu(kok) }
            return dogruMu(kok) && son.isEmpty
        }
        if yazim.contains(w) { return true }
        return Metin.govdeler(w).contains { yazim.contains($0) }
    }
}

// MARK: - Sözlük erişim yardımcıları

extension Dictionary where Key == String, Value == Any {
    func s(_ k: String) -> String { self[k] as? String ?? (self[k] as? NSNumber)?.stringValue ?? "" }
    func i(_ k: String) -> Int? { (self[k] as? NSNumber)?.intValue ?? (self[k] as? String).flatMap { Int($0) } }
    func d(_ k: String) -> Double? { (self[k] as? NSNumber)?.doubleValue }
    func l(_ k: String) -> [String] { (self[k] as? [Any] ?? []).compactMap { $0 as? String } }
}

enum Gun {
    static let isoGun: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    /// Tarayıcıdaki Tezgâh'la aynı: toISOString().slice(0,10) — UTC günü.
    static var bugun: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
    static func trKisa(_ t: String) -> String {
        guard let d = isoGun.date(from: t) else { return t.isEmpty ? "—" : t }
        let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR"); f.dateFormat = "d MMM"
        return f.string(from: d)
    }
    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    static let isoSaniye: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
}
