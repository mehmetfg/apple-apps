// Uygulama ve widget'ın ortak modeli. Kelime verisi `veri.py`'nin yazdığı kelimeler.json'dan gelir.
import Foundation

/// Oxford veritabanından tek kelime. Kısa anahtarlar dosyayı küçük tutmak için.
struct Kelime: Codable, Identifiable, Hashable {
    let i: Int
    let w: String
    let p: String
    let c: String
    let t: String
    let ipa: String
    let tr: String
    let d: String
    let k: [String]
    let x: [String]
    let syn: [String]
    let ant: [String]
    let th: String
    let au: String
    /// d = depo (bilmediğim) · k = bilinen · e = elenmiş
    let s: String
    /// Depodaki sıra (yalnız s == "d")
    let o: Int?
    /// Örgü'de girdiği bölüm
    let g: Int?
    /// Deyimsel fiilde ayrılma: A ayrılabilir · Z ayrılmaz · N nesne almaz
    let sp: String?

    var id: Int { i }
    var kelime: String { w }
    var bant: String { c.isEmpty ? "—" : c }
    var turkce: String { tr }
    var ilkCumle: String? { x.first }

    var isPV: Bool { p == "phrasal verb" }
    /// "take off" → "take"
    var taban: String { String(w.split(separator: " ").first ?? Substring(w)) }
    /// İki sözcüklü deyimsel fiilin parçacığı ("take off" → "off"); üç sözcüklülerde nil
    var parcacik: String? {
        let t = w.split(separator: " ")
        return isPV && t.count == 2 ? String(t[1]) : nil
    }

    /// Ayrılma kuralı — örnekli, tek satır
    var ayrilmaNotu: (baslik: String, dogru: String, yanlis: String?)? {
        guard isPV, let sp else { return nil }
        let t = w.split(separator: " ").map(String.init)
        switch sp {
        case "A" where t.count == 2:
            return ("Ayrılabilir", "\(t[0]) it \(t[1])", "\(t[0]) \(t[1]) it")
        case "Z":
            return ("Ayrılmaz", "\(w) it", "\(t[0]) it \(t.dropFirst().joined(separator: " "))")
        case "N":
            return ("Nesne almaz", w, nil)
        default:
            return nil
        }
    }

    var turAdi: String {
        switch p {
        case "noun": return "isim"
        case "verb": return "fiil"
        case "adjective": return "sıfat"
        case "adverb": return "zarf"
        case "preposition": return "edat"
        case "conjunction": return "bağlaç"
        case "phrasal verb": return "deyimsel fiil"
        default: return p
        }
    }
}

struct Paket: Codable {
    let surum: String
    let uretildi: String
    let kelimeler: [Kelime]
}

/// Bir kelimenin öğrenme durumu (FSRS).
struct Kart: Codable, Hashable {
    var kararlilik: Double          // S — gün
    var zorluk: Double              // D — 1…10
    var son: Date                   // son tekrar
    var vade: Date                  // bir sonraki tekrar
    var tekrar: Int = 0
    var hata: Int = 0
    var ilk: Date                   // tanışma günü

    /// Bugün hatırlama olasılığı
    func hatirlama(_ an: Date = Date()) -> Double {
        FSRS.hatirlama(gun: max(0, an.timeIntervalSince(son) / 86_400), kararlilik: kararlilik)
    }

    var asama: Asama { Asama(kararlilik) }
}

/// Kelimenin kafandaki yeri. Kararlılığa göre — sayı değil, söz.
enum Asama: Int, CaseIterable, Codable {
    case tanisma, asina, oturmus, kalici

    init(_ s: Double) {
        switch s {
        case ..<4: self = .tanisma
        case ..<21: self = .asina
        case ..<90: self = .oturmus
        default: self = .kalici
        }
    }

    var ad: String {
        switch self {
        case .tanisma: return "Tanışma"
        case .asina: return "Aşina"
        case .oturmus: return "Oturmuş"
        case .kalici: return "Kalıcı"
        }
    }

    var aciklama: String {
        switch self {
        case .tanisma: return "Yeni gördün; birkaç gün içinde tekrar gelecek."
        case .asina: return "Görünce tanıyorsun; hafızada tutunuyor."
        case .oturmus: return "Haftalarca aklında kalıyor. Cümle Tezgâhı'na üretim için gider."
        case .kalici: return "Aylarca unutmuyorsun."
        }
    }
}

enum Karar: String, Codable {
    case biliyorum      // "zaten biliyorum" — depodan düşer, vault'a gider
    case ertele         // bugün değil, depoda sona at
}

/// Bir günün kaydı.
struct GunKaydi: Codable, Hashable {
    var yeni: Int = 0
    var tekrar: Int = 0
    var dogru: Int = 0
    var sure: Double = 0
    var bitti: Bool = false
}

extension Date {
    var gunAnahtari: String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: self)
    }

    var gunBasi: Date { Calendar.current.startOfDay(for: self) }
    var gunSonu: Date { Calendar.current.date(byAdding: .day, value: 1, to: gunBasi)!.addingTimeInterval(-1) }
    func gun(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: n, to: self)! }
}
