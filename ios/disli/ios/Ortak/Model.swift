// Dişli veri modeli. Tek kaynak: konular.json (veri/uret.py üretir; elle düzenlenmez).
import Foundation

struct Veri: Codable {
    let surum: Int
    let yasalar: [Yasa]
    let bolgeler: [Bolge]
    let konular: [Konu]
    let yol: [String]
    let merdiven: [Merdiven]
    let termometre: [TermCumle]
}

struct Yasa: Codable, Identifiable, Hashable {
    let id, ad, imge, sembol, renk, ozet, aciklama: String
    let ornekler: [YasaOrnek]
    let konular: [String]
}

struct YasaOrnek: Codable, Hashable {
    let konu, en, tr: String
}

struct Bolge: Codable, Identifiable, Hashable {
    let id, ad, sembol, renk, ozet: String
}

struct Konu: Codable, Identifiable, Hashable {
    let id, ad, tr: String
    let faz: Int
    let yildiz: Bool
    let ne, formul: String
    let ornek: [[String]]
    let tuzak, kaynak, bolge, imge: String
    let yasalar: [KonuYasa]
    let tuzakAyrik: TuzakAyrik
    let kalip: Kalip
    let sorular: [Soru]

    static func == (a: Konu, b: Konu) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct KonuYasa: Codable, Hashable {
    let id: String
    let not: String
}

/// Formülün telefonda okunur hâli (veri/kalip.py üretir): bloklar → kalıplar → alt alta yuvalar.
struct Kalip: Codable, Hashable {
    let karsi: Bool          // iki blok yan yana kıyaslanır (↔)
    let bloklar: [KalipBlok]
}

struct KalipBlok: Codable, Hashable {
    let kaliplar: [KalipSatir]
    let liste: [String]      // kalıp değil kelime listesi (çip)
    let not: String
}

struct KalipSatir: Codable, Hashable {
    let etiket: String
    let parcalar: [KalipParca]
    let isaret: [String]     // birlikte gelen işaret kelimeleri
}

/// m: metin · t: tür (modal, perfect, surec, be, zaman, fiil, ozne, isim, bag, ayrac, ornek, diger) · a: kısa açıklama
struct KalipParca: Codable, Hashable {
    let m, t, a: String
}

struct TuzakAyrik: Codable, Hashable {
    let on, y, d, not: String
}

/// Soru türleri: b boşluk · h hata · s sırala · d dönüştür
struct Soru: Codable, Identifiable, Hashable {
    let id: String
    let t: String
    var s: String? = nil            // b: boşluklu cümle
    var cevaplar: [String]? = nil   // b, s, d
    var parcaSayisi: [Int]? = nil   // b: her boşluğun kelime sayısı
    var tas: [String]? = nil        // b, s, d: doğru taşlar
    var fazla: [String]? = nil      // b, d: yanıltıcı taşlar
    var secenek: [String]? = nil    // b: yanlış seçenekler (seçmeli kipte)
    var son: String? = nil          // s, d: cümle sonu noktalaması
    var yanlis: String? = nil       // h
    var dogru: String? = nil        // h
    var hataKelime: [Int]? = nil    // h: yanlış cümlede işaretlenecek kelime sıraları
    var kaynak: String? = nil       // d
    var talimat: String? = nil      // d

    enum Tur { case bosluk, hata, sirala, donustur }
    var tur: Tur {
        switch t {
        case "b": .bosluk
        case "h": .hata
        case "s": .sirala
        default: .donustur
        }
    }
}

struct Merdiven: Codable, Identifiable, Hashable {
    var id: String { tur + ad }
    let tur, ad: String
    let basamaklar: [String]
    let notlar: [String]
    let d: [String]
}

struct TermCumle: Codable, Identifiable, Hashable {
    var id: String { s }
    let s: String
    let deger: Int
    let aciklama: String
}

// MARK: - Metin yardımcıları

enum Metin {
    /// Karşılaştırma için: küçük harf, kesme işareti birliği, noktalama yok, kısaltmalar açık.
    static func norm(_ s: String) -> String {
        var x = s.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
        for (a, b) in [("won't", "will not"), ("can't", "can not"), ("cannot", "can not"), ("shan't", "shall not"),
                       ("n't", " not"), ("i'm", "i am"), ("'re", " are"), ("'ve", " have"), ("'ll", " will")] {
            x = x.replacingOccurrences(of: a, with: b)
        }
        let atla = CharacterSet(charactersIn: ".,!?;:“”\"·…—–()")
        x = String(x.unicodeScalars.map { atla.contains($0) ? " " : Character($0) })
        return x.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func esit(_ a: String, _ b: String) -> Bool { norm(a) == norm(b) }

    /// "If it [rains], we [will stay]" → yuvalar ve yuvasız parçalar
    static func yuvalar(_ s: String) -> (parcalar: [String], yuvalar: [String]) {
        var parcalar: [String] = [], yuvalar: [String] = []
        var kalan = Substring(s)
        while let a = kalan.firstIndex(of: "["), let b = kalan[a...].firstIndex(of: "]") {
            parcalar.append(String(kalan[..<a]))
            yuvalar.append(String(kalan[kalan.index(after: a)..<b]))
            kalan = kalan[kalan.index(after: b)...]
        }
        parcalar.append(String(kalan))
        return (parcalar, yuvalar)
    }

    static func koseliSil(_ s: String) -> String {
        s.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
    }
}
