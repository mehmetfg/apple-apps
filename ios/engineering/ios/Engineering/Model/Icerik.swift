import Foundation

// engineering.json'un Swift karşılığı. Dosyayı `veri/uret.py` basar; alan adları oradaki Python sözlükleriyle aynıdır.

struct Icerik: Decodable {
    let surum: Int
    let uretildi: String
    let alanlar: [Alan]
    let dersler: [Ders]
}

struct Alan: Decodable, Identifiable, Hashable {
    let kod: String
    let ad: String          // Türkçe (Tezgâh)
    let en: String          // İngilizce
    let renk: String
    let meseleler: [Mesele]
    var id: String { kod }
}

struct Mesele: Decodable, Identifiable, Hashable {
    let id: String
    let sira: Int
    let baslik: String      // Türkçe (Tezgâh)
    let soru: String        // Türkçe merkez soru (Tezgâh)
    let en: String
    let dersler: [String]
    var dolu: Bool { !dersler.isEmpty }
}

struct Ders: Decodable, Identifiable, Hashable {
    let id: String
    let mesele: String
    let sira: Int
    let baslik: String
    let baslik_tr: String
    let kanca: String
    let kanca_tr: String
    let kartlar: [Kart]
    let lab: Lab?
    let oyun: String?
    let dedektif: [DedektifTuru]?
    let kod: Kod
    let c: CPerdesi?
    let parsons: Parsons?
    let quiz: [Soru]
    let sozluk: [Terim]
    let cumle: Cumle
    let tuzak: Tuzak
    let ozet: String

    static func == (a: Ders, b: Ders) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct Kart: Decodable, Hashable {
    let baslik: String
    let metin: String
    let tr: String
    let gorsel: String?
}

struct Lab: Decodable, Hashable { let algoritma: String }

struct DedektifTuru: Decodable, Hashable {
    let kod: String
    let secenekler: [String]
    let dogru: Int
    let aciklama: String
}

struct Kod: Decodable, Hashable {
    let metin: String
    let notlar: [KodNotu]
    let etiketler: [String: Int]
    var satirlar: [String] { metin.components(separatedBy: "\n") }
}

struct KodNotu: Decodable, Hashable {
    let satir: Int
    let en: String
    let tr: String
}

struct CPerdesi: Decodable, Hashable {
    let metin: String
    let en: String
    let tr: String
}

struct Parsons: Decodable, Hashable {
    let satirlar: [String]
    let yanlis: [String]?
}

struct Soru: Decodable, Hashable {
    let soru: String
    let kod: String?
    let secenekler: [String]
    let dogru: Int
    let aciklama: String
    let aciklama_tr: String?
}

struct Terim: Decodable, Hashable, Identifiable {
    let terim: String
    let tr: String
    let kalip: String
    let ornek: String
    let ipa: String
    var id: String { terim.lowercased() }
}

struct Cumle: Decodable, Hashable { let en: String; let tr: String }
struct Tuzak: Decodable, Hashable { let yanlis: String; let dogru: String; let not: String }

// MARK: - Yükleyici

@MainActor
final class Kutuphane {
    static let shared = Kutuphane()

    let icerik: Icerik
    let dersler: [String: Ders]
    /// Bütün derslerin terimleri — bir derste geçen terim başka dersin metninde de dokunulabilir olur.
    let terimler: [Terim]
    let terimDersi: [String: String]

    private init() {
        guard let url = Bundle.main.url(forResource: "engineering", withExtension: "json"),
              let veri = try? Data(contentsOf: url),
              let icerik = try? JSONDecoder().decode(Icerik.self, from: veri) else {
            fatalError("engineering.json okunamadı — `python3 veri/uret.py` çalıştır.")
        }
        self.icerik = icerik
        dersler = Dictionary(uniqueKeysWithValues: icerik.dersler.map { ($0.id, $0) })
        var gorulen = Set<String>(), liste: [Terim] = [], kaynak: [String: String] = [:]
        for d in icerik.dersler {
            for t in d.sozluk where !gorulen.contains(t.id) {
                gorulen.insert(t.id); liste.append(t); kaynak[t.id] = d.id
            }
        }
        terimler = liste
        terimDersi = kaynak
    }

    /// Yol sırası: alan alan, mesele mesele, ders ders.
    var sira: [Ders] {
        icerik.alanlar.flatMap { $0.meseleler }.flatMap { $0.dersler }.compactMap { dersler[$0] }
    }

    func alan(ofMesele id: String) -> Alan? {
        icerik.alanlar.first { a in a.meseleler.contains { $0.id == id } }
    }

    func mesele(_ id: String) -> Mesele? {
        icerik.alanlar.flatMap { $0.meseleler }.first { $0.id == id }
    }

    func ders(algoritma: Algoritma) -> Ders? {
        icerik.dersler.first { $0.lab?.algoritma == algoritma.rawValue }
    }
}
