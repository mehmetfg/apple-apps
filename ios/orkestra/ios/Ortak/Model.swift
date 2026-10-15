// Orkestra'nın veri modeli — Mac'teki toplayıcının (veri/orkestra.py) yazdığı orkestra.json'un birebir karşılığı.
// Toplayıcı yalnız olgu yazar; hüküm (durum, öncelik, hamle) Motor.swift'te verilir.
import Foundation

struct OrkestraVeri: Codable, Equatable {
    var surum: Int
    var uretildi: String
    var makine: String
    var bugun: String
    var gun_sayisi: Int
    var yon: Yon
    var alanlar: [Alan]
    var surecler: [Surec]
    var borular: [Boru]
    var kenarlar: [Kenar]
    var aksiyonlar: [Aksiyon]
    var kararlar: [Karar]
    var hacim: Hacim?           // okuma hacmi (veri/hacim.py) — eski orkestra.json'larda yok
    var uyarilar: [String]

    var uretimZamani: Date? { Tarih.coz(uretildi) }
    func surec(_ id: String) -> Surec? { surecler.first { $0.id == id } }
    func boru(_ id: String?) -> Boru? { guard let id else { return nil }; return borular.first { $0.id == id } }
}

struct Yon: Codable, Equatable {
    var ana: String
    var destek: [String]
    var hedef: String
    var sonraki_olcum: String
}

struct Alan: Codable, Equatable, Identifiable {
    var id: String
    var ad: String
    var kisa: String
}

struct Ilerleme: Codable, Equatable {
    var a: Int
    var b: Int
    var birim: String
    var oran: Double { b > 0 ? min(1, Double(a) / Double(b)) : 0 }
}

struct Basamak: Codable, Equatable, Identifiable {
    var ad: String
    var a: Int
    var b: Int
    var id: String { ad }
    var oran: Double { b > 0 ? min(1, Double(a) / Double(b)) : 0 }
}

struct Birikme: Codable, Equatable {
    var bekleyen: Int?
    var esik: Int
    var birim: String
    var not: String
    var asildi: Bool { (bekleyen ?? 0) > esik }
}

struct Vade: Codable, Equatable {
    var tarih: String
    var olcut: String
    var gun: Date? { Tarih.coz(tarih) }
}

struct Kayit: Codable, Equatable, Hashable {
    var e: String
    var d: String
}

struct Surec: Codable, Equatable, Identifiable {
    var id: String
    var ad: String
    var alt: String
    var alan: String
    var kademe: String          // ana · destek · hat · bakim
    var ritim: Int              // beklenen en uzun aralık (gün)
    var son: String?            // son dokunuş (yerel ISO)
    var iz: [Int]               // eskiden yeniye günlük iz, son eleman bugün
    var ilerleme: Ilerleme?
    var bicim: String           // halka · merdiven · depo · kitaplik · akis
    var basamaklar: [Basamak]
    var birikme: Birikme?
    var boru: String?
    var bugun: String
    var ayrinti: [Kayit]
    var acilis: String?
    var acilis_ad: String?
    var durdu: Bool
    var durdu_neden: String
    var vade: Vade?
    var kaynak: String          // mac · telefon · telefon+mac · yok
    var hata: String?
    var besler: [String]

    var sonDokunus: Date? { son.flatMap(Tarih.coz) }
}

struct Boru: Codable, Equatable, Identifiable {
    var id: String
    var ad: String
    var saat: String
    var son: String?
    var durum: String           // tamam · tikali · bekliyor · bilinmiyor
    var not: String
    var besler: [String]
}

struct Kenar: Codable, Equatable, Hashable {
    var a: String
    var b: String
    var etiket: String?
}

struct Aksiyon: Codable, Equatable, Identifiable, Hashable {
    var tarih: String
    var baslik: String
    var ozet: String
    var id: String { tarih + baslik }
}

struct Karar: Codable, Equatable, Identifiable, Hashable {
    var metin: String
    var ayrinti: String
    var kaynak: String
    var id: String { metin }
}

enum Tarih {
    static let takvim: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "tr_TR")
        c.timeZone = .current
        return c
    }()

    /// "2026-10-09" ya da "2026-10-09T17:19:32" (yerel) → Date
    private static let yerel: [(Int, DateFormatter)] = [(19, "yyyy-MM-dd'T'HH:mm:ss"), (16, "yyyy-MM-dd'T'HH:mm"),
                                                         (10, "yyyy-MM-dd")].map { n, b in
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = b
        return (n, f)
    }
    private static let utc: [ISO8601DateFormatter] = {
        let a = ISO8601DateFormatter()
        let b = ISO8601DateFormatter()
        b.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return [a, b]
    }()

    static func coz(_ s: String) -> Date? {
        if s.hasSuffix("Z") || s.contains("+") {
            for f in utc { if let d = f.date(from: s) { return d } }
        }
        for (n, f) in yerel where s.count >= n {
            if let d = f.date(from: String(s.prefix(n))) { return d }
        }
        return nil
    }

    static func iso(_ d: Date) -> String { yerel[0].1.string(from: d) }

    static func gunFarki(_ a: Date, _ b: Date) -> Int {
        takvim.dateComponents([.day], from: takvim.startOfDay(for: a), to: takvim.startOfDay(for: b)).day ?? 0
    }

    static func kisa(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMM"
        return f.string(from: d)
    }

    static func saat(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    static func gorece(_ d: Date, _ simdi: Date = .now) -> String {
        let g = gunFarki(d, simdi)
        switch g {
        case ..<0: return kisa(d)
        case 0:
            let dk = Int(simdi.timeIntervalSince(d) / 60)
            if dk < 1 { return "az önce" }
            if dk < 60 { return "\(dk) dk önce" }
            return "bugün \(saat(d))"
        case 1: return "dün"
        default: return "\(g) gün önce"
        }
    }
}

// MARK: okuma hacmi — Voice Dream'den: Claude'un ürettiği metinden dinlenen (temel), diğer kitaplar (ayrı), üretilen
struct HacimGunu: Codable, Equatable {
    var g: String       // gün
    var c: Int          // Claude metninden dinlenen kelime
    var o: Int          // diğer (yayımlanmış kitaplar) dinlenen kelime
    var u: Int          // o gün Voice Dream'e düşen Claude metni (kelime)
    var dk: Double      // dinleme dakikası (belgenin okuma hızıyla)
    var i: Int          // işaret
    var gun: Date? { Tarih.coz(g) }
}

struct Hacim: Codable, Equatable {
    var baslangic: String          // Claude metinlerinin başladığı gün
    var ilk_gun: String            // Voice Dream'de iz olan ilk gün
    var kesin_baslangic: String    // bu günden önce günlük dağılım tahmini
    var sayfa_kelime: Int
    var kitap_sayfa: Int
    var claude_metin: Int
    var claude_sindirilen: Int
    var arsiv_metin: Int?          // Voice Dream'den silinmiş, işaretleri vault'ta arşivli metinler
    var arsiv_kelime: Int?
    var beyan_metin: Int?          // işaretsiz silinmiş, kullanıcının "dinledim" beyanıyla eklenen
    var beyan_kelime: Int?
    var beyan_tahmini: Int?        // tam metni kalmadığı için ortalamayla sayılan kısım
    var seri: [HacimGunu]

    var kitapKelime: Double { Double(sayfa_kelime * kitap_sayfa) }
}
