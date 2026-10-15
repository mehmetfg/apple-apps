// Saray'ın verisi: sözlük (pakette, veri/sozluk.py üretir) + oda oda etiketler (cihazda, ARKit dünya haritasıyla birlikte).
import Foundation
import simd

struct Oda: Codable, Identifiable, Hashable { var id: String; var ad: String; var en: String; var simge: String }

struct Kelime: Codable, Identifiable, Hashable {
    var en: String
    var tr: String
    var odalar: [String]
    var siniflar: [String]
    var kaynak: String          // oxford3000 · oxford5000 · ek
    var cefr: String
    var ses: String             // /telaffuz/
    var tanim: String
    var ornek: String
    var sesURL: String
    var id: String { en }

    var rozet: String { kaynak == "ek" ? "ek" : (kaynak == "oxford3000" ? "Ox 3000" : "Ox 5000") + (cefr.isEmpty ? "" : " · \(cefr)") }
}

struct Sozluk: Codable {
    var odalar: [Oda]
    var kelimeler: [Kelime]

    static let paket: Sozluk = {
        guard let u = Bundle.main.url(forResource: "sozluk", withExtension: "json"), let d = try? Data(contentsOf: u),
              let s = try? JSONDecoder().decode(Sozluk.self, from: d) else { return Sozluk(odalar: [], kelimeler: []) }
        return s
    }()

    func kelime(_ en: String) -> Kelime? { kelimeler.first { $0.en == en } }
    func odada(_ oda: String) -> [Kelime] { kelimeler.filter { $0.odalar.contains(oda) } }

    /// Modelin sınıfı → bu odaya en uygun kelime (önce bu odanın kelimesi, sonra Oxford önceliği).
    func esle(_ sinif: String, oda: String) -> Kelime? {
        let adaylar = kelimeler.filter { $0.siniflar.contains(sinif) }
        return adaylar.first { $0.odalar.contains(oda) } ?? adaylar.first
    }
}

/// Bir odada yerleşmiş bir etiket. Konumu ARKit çapasında (adı "saray:<id>") durur; dünya haritasıyla kaydedilir.
struct Etiket: Codable, Identifiable, Hashable {
    var id: String
    var en: String
    var oda: String
    var otomatik: Bool
    var tarih: Date
    var konum: [Float]          // son bilinen dünya konumu (x, y, z) — çapa yoksa yedek

    var nokta: SIMD3<Float> { konum.count == 3 ? SIMD3(konum[0], konum[1], konum[2]) : .zero }
}

/// Oda başına kayıt: Documents/odalar/<oda>/etiketler.json + dunya.map
enum Kasa {
    static func klasor(_ oda: String) -> URL {
        let u = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("odalar/\(oda)", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static func etiketler(_ oda: String) -> [Etiket] {
        guard let d = try? Data(contentsOf: klasor(oda).appendingPathComponent("etiketler.json")) else { return [] }
        let c = JSONDecoder(); c.dateDecodingStrategy = .iso8601
        return (try? c.decode([Etiket].self, from: d)) ?? []
    }

    static func yaz(_ e: [Etiket], _ oda: String) {
        let k = JSONEncoder(); k.dateEncodingStrategy = .iso8601
        if let d = try? k.encode(e) { try? d.write(to: klasor(oda).appendingPathComponent("etiketler.json"), options: .atomic) }
    }

    static func haritaURL(_ oda: String) -> URL { klasor(oda).appendingPathComponent("dunya.map") }

    /// Bilinen kelimeler (uzun bas › "biliyorum") — Sözlük'te soluk görünür, kamerada yine çıkar.
    static var bilinen: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "bilinen") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "bilinen") }
    }
}
