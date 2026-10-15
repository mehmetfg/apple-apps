// Teoria — veri modeli.
// İçerik (kartlar.json) ve akış (akis.json) Mac'te üretilir, salt okunur.
// İlerleme yalnız olaylardan (Olay) oluşur; durum her açılışta olayların yeniden oynatılmasıyla hesaplanır.
import Foundation

// MARK: - İçerik paketi

struct Paket: Codable {
    var surum: String
    var kitaplar: [Kitap]
    var kavramlar: [Kavram]
    var cumleler: [Cumle]
    var donusumler: [Donusum]
    var kavramsallar: [Kavramsal]
    var baglar: [Bag]
    var aforizmalar: [Aforizma]
    /// Optional so older packs without the key still decode.
    var questions: [ConceptQuestion]? = nil

    static let bos = Paket(surum: "0", kitaplar: [], kavramlar: [], cumleler: [], donusumler: [],
                           kavramsallar: [], baglar: [], aforizmalar: [])

    func kitap(_ id: String?) -> Kitap? { kitaplar.first { $0.id == id } }
    func kavram(_ id: String) -> Kavram? { kavramlar.first { $0.id == id } }
}

struct Kitap: Codable, Identifiable, Hashable {
    let id: String
    let baslik: String
    let yazar: String
    let seri: String
    let renk: String
    let sembol: String
    let oz: String
}

struct Ayirt: Codable, Hashable {
    let karsi: String
    let fark: String
}

struct Kavram: Codable, Identifiable, Hashable {
    let id: String
    let kitap: String
    let terim: String
    let tanim: String
    let anahtar: [String]
    let ipucu: String
    var ayirt: Ayirt?
}

struct Cumle: Codable, Identifiable, Hashable {
    let id: String
    let kitap: String
    let metin: String
    let anahtar: [String]
    let oz: String
    let yapi: String
    let taklit: String
    let kaynak: String
}

struct Donusum: Codable, Identifiable, Hashable {
    let id: String
    let kok: String
    let hedef: String
    let dogru: String
    let secenekler: [String]
    let aciklama: String
}

struct Kavramsal: Codable, Identifiable, Hashable {
    let id: String
    let kitap: String
    let gundelik: String
    let kavramsal: String
    let ipucu: String
}

struct Bag: Codable, Identifiable, Hashable {
    let id: String
    let a: String
    let b: String
    let soru: String
    let model: String
}

struct Aforizma: Codable, Identifiable, Hashable {
    let id: String
    let metin: String
    let kaynak: String
    var kitap: String?
}

// MARK: - Akış (bütün işaretler)

struct Akis: Codable {
    var surum: String
    var isaretler: [Isaret]
    var kitaplar: [OkumaKitabi]
    static let bos = Akis(surum: "0", isaretler: [], kitaplar: [])
}

struct Isaret: Codable, Identifiable, Hashable {
    let id: String
    let kitap: String
    let baslik: String
    let metin: String
    let renk: Int
    let tarih: String
    let kaynak: String
    var baglam: String?

    var zaman: Date { Tarih.coz(tarih) ?? .distantPast }
    var renkAdi: String { IsaretRengi(rawValue: renk)?.ad ?? "işaret" }
}

enum IsaretRengi: Int, CaseIterable, Identifiable {
    case cekirdek = 1, kanit, terim, itiraz
    var id: Int { rawValue }
    var ad: String {
        switch self {
        case .cekirdek: "çekirdek iddia"
        case .kanit: "katılıyorum"
        case .terim: "terim"
        case .itiraz: "itiraz"
        }
    }
    var sembol: String {
        switch self {
        case .cekirdek: "scope"
        case .kanit: "hand.thumbsup"
        case .terim: "textformat.abc"
        case .itiraz: "exclamationmark.bubble"
        }
    }
}

struct Okuma: Codable, Hashable {
    var tarih: String?
    var yuzde: Int?
    var yeni: Int?
}

struct OkumaKitabi: Codable, Identifiable, Hashable {
    let id: String
    let baslik: String
    let kategori: String
    let yuzde: Int
    let durum: String
    let kelime: Int
    let isaret: Int
    let ilk: String
    let son: String
    let okumalar: [Okuma]
    var kume: String?
    var disiplin: String?
    var tema: String?

    var okunmadi: Bool { durum == "okunmadi" }
    var suruyor: Bool { !okunmadi && (durum == "suruyor" || yuzde < 100) }
    var sonZaman: Date { Tarih.coz(son) ?? Tarih.coz(ilk) ?? .distantPast }
}

// MARK: - Hatlar ve kademeler

enum Hat: String, Codable, CaseIterable, Identifiable {
    case hatirla, donustur, kur
    var id: String { rawValue }
    var ad: String {
        switch self {
        case .hatirla: "Hatırla"
        case .donustur: "Dönüştür"
        case .kur: "Kur"
        }
    }
    var aciklama: String {
        switch self {
        case .hatirla: "Okuduğunu ipucu azaldıkça kendi zihninden çağır."
        case .donustur: "Kavramı işlet: örnekte tanı, komşusundan ayır, gündelikten kavramsala geç."
        case .kur: "Önemli cümleyi yeniden kur, sonra o yapıyla kendi cümleni yaz."
        }
    }
    var sembol: String {
        switch self {
        case .hatirla: "brain.head.profile"
        case .donustur: "arrow.triangle.2.circlepath"
        case .kur: "text.append"
        }
    }
}

enum Evre: String {
    case entegrasyon = "Entegrasyon", oryantasyon = "Oryantasyon", ileri = "İleri kavrayış"
    static func of(_ k: Int) -> Evre { k <= 2 ? .entegrasyon : (k <= 4 ? .oryantasyon : .ileri) }
}

enum Zorluk: String, Codable, CaseIterable, Identifiable {
    case hafif, dengeli, zorlu
    var id: String { rawValue }
    var ad: String { switch self { case .hafif: "Hafif"; case .dengeli: "Dengeli"; case .zorlu: "Zorlu" } }
    /// +1 için tutturulması gereken başarı oranı. Düşük hedef = daha hızlı tırmanış = daha çok zorluk.
    var hedef: Double { switch self { case .hafif: 0.90; case .dengeli: 0.85; case .zorlu: 0.75 } }
    var aciklama: String {
        switch self {
        case .hafif: "Bir kademe çıkmak için %90 başarı. Yavaş ve rahat."
        case .dengeli: "%85 başarı. Öğrenmenin en verimli bandı."
        case .zorlu: "%75 başarı yeter; merdiveni hızlı çıkarsın, daha çok terlersin."
        }
    }
}

// MARK: - Olay günlüğü

enum OlayTuru: String, Codable {
    case cevap          // bir alıştırmanın sonucu
    case kur            // bir kürün kapanışı
    case favori         // hedef: işaret/aforizma id, deger: açık/kapalı
    case yerIsareti
    case hatirlat       // işareti tekrar havuzuna al / çıkar
    case sesNot         // metin: dosya adı, hedef: ilgili öğe, sure
    case sesSil         // hedef: silinen olayın id'si — ses notu ya da kendi gönderin (yorum/alıntı/fikir)
    case kendiCumle     // bildirimden ya da akıştan yazılan kendi cümle (metin); rol: alinti · yorum · fikir
                        // deger: true = yazarken/konuşurken asıl metne bakıldı (hatırlama perdesi açıldı)
    case kademe         // elle kademe ayarı (hat, kademe)
}

struct Olay: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var t: Date = Date()
    var gun: String = Tarih.gun(Date())
    var cihaz: String = Cihaz.ad
    var tur: OlayTuru
    var hedef: String?
    var hat: Hat?
    var kademe: Int?
    var puan: Double?
    var guven: Int?
    var not: Int?
    var deger: Bool?
    var metin: String?
    var sure: Double?
    var kurId: String?
    var rol: String?        // "songun" · "tekrar" · "isinma" · "esneme" · "kapanis" · "alinti" · "yorum" · "atolye" · nil
}

enum Cihaz {
    static let anahtar = "teoria.cihaz"
    static var ad: String {
        if let a = UserDefaults.standard.string(forKey: anahtar), !a.isEmpty { return a }
        #if os(iOS)
        let a = "iphone"
        #else
        let h = (Host.current().localizedName ?? ProcessInfo.processInfo.hostName)
        let a = "mac-" + Dil.dosyaAdi(h)
        #endif
        UserDefaults.standard.set(a, forKey: anahtar)
        return a
    }
}

// MARK: - Tarih yardımcıları

enum Tarih {
    static let takvim: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "tr_TR")
        c.firstWeekday = 2
        return c
    }()

    private static let gunBicim: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let bicimler: [DateFormatter] = ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"].map {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = $0
        return f
    }

    static func gun(_ d: Date) -> String { gunBicim.string(from: d) }
    static func isoSaat(_ d: Date) -> String { bicimler[0].string(from: d) }

    static func coz(_ s: String?) -> Date? {
        guard var s, !s.isEmpty else { return nil }
        if let r = s.range(of: "+"), s.count > 19 { s = String(s[..<r.lowerBound]) }
        for f in bicimler { if let d = f.date(from: String(s.prefix(19))) { return d } }
        return ISO8601DateFormatter().date(from: s)
    }

    static func goreli(_ d: Date, simdi: Date = Date()) -> String {
        let t = takvim
        if t.isDate(d, inSameDayAs: simdi) || d > simdi { return "bugün" }
        if let dun = t.date(byAdding: .day, value: -1, to: simdi), t.isDate(d, inSameDayAs: dun) { return "dün" }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: simdi)
    }

    static func kisa(_ d: Date) -> String {
        d.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "tr_TR")))
    }
}

extension Date {
    var gunBasi: Date { Tarih.takvim.startOfDay(for: self) }
    func gun(_ n: Int) -> Date { Tarih.takvim.date(byAdding: .day, value: n, to: self) ?? self }
}
