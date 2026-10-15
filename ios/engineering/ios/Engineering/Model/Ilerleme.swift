import Foundation
import Observation

/// Telefonda kalan tek kayıt. Bilerek yok: seri, vade, borç, günlük hedef (vault kuralı).
/// Var: hangi ders bitti, quiz ve CPU sonucu, kendi cümlen, "biliyorum" dediğin terimler.
@Observable
final class Ilerleme {
    struct DersKaydi: Codable {
        var tarih: Date
        var quiz: Int
        var quizToplam: Int
        var cpu: Int?
        var cpuToplam: Int?
        var kez: Int = 1
    }

    private struct Dosya: Codable {
        var biten: [String: DersKaydi] = [:]
        var cumleler: [String: String] = [:]
        var bilinen: Set<String> = []
        var yanlislar: [String: Int] = [:]        // "dersId#soruNo" → kaç kez yanlış
    }

    private var dosya = Dosya()
    private let url: URL

    init() {
        let klasor = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
        url = klasor.appendingPathComponent("ilerleme.json")
        if let veri = try? Data(contentsOf: url), let d = try? JSONDecoder().decode(Dosya.self, from: veri) {
            dosya = d
        }
    }

    private func kaydet() {
        if let veri = try? JSONEncoder().encode(dosya) { try? veri.write(to: url, options: .atomic) }
    }

    // MARK: okuma

    func bitti(_ dersId: String) -> Bool { dosya.biten[dersId] != nil }
    func kayit(_ dersId: String) -> DersKaydi? { dosya.biten[dersId] }
    func cumle(_ dersId: String) -> String { dosya.cumleler[dersId] ?? "" }
    func biliyor(_ terim: Terim) -> Bool { dosya.bilinen.contains(terim.id) }
    var bitenSayisi: Int { dosya.biten.count }
    var bilinenSayisi: Int { dosya.bilinen.count }
    func yanlisSayisi(_ anahtar: String) -> Int { dosya.yanlislar[anahtar] ?? 0 }

    func bitenOran(_ mesele: Mesele) -> Double {
        guard !mesele.dersler.isEmpty else { return 0 }
        return Double(mesele.dersler.filter { bitti($0) }.count) / Double(mesele.dersler.count)
    }

    // MARK: yazma

    func bitir(_ dersId: String, quiz: Int, quizToplam: Int, cpu: Int?, cpuToplam: Int?) {
        var k = DersKaydi(tarih: .now, quiz: quiz, quizToplam: quizToplam, cpu: cpu, cpuToplam: cpuToplam)
        if let eski = dosya.biten[dersId] { k.kez = eski.kez + 1 }
        dosya.biten[dersId] = k
        kaydet()
    }

    func cumleYaz(_ dersId: String, _ metin: String) {
        let t = metin.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { dosya.cumleler[dersId] = nil } else { dosya.cumleler[dersId] = t }
        kaydet()
    }

    func bilinenDegistir(_ terim: Terim) {
        if dosya.bilinen.contains(terim.id) { dosya.bilinen.remove(terim.id) } else { dosya.bilinen.insert(terim.id) }
        kaydet()
    }

    func cevap(_ anahtar: String, dogru: Bool) {
        if dogru {
            if let n = dosya.yanlislar[anahtar] { dosya.yanlislar[anahtar] = n > 1 ? n - 1 : nil }
        } else {
            dosya.yanlislar[anahtar, default: 0] += 1
        }
        kaydet()
    }

    /// Karışık tur: bitmiş derslerin sorularından; önce yanlış yapılanlar, sonra rastgele. Vade yok.
    func karisikSorular(_ kutuphane: Kutuphane, adet: Int = 8) -> [(Ders, Int)] {
        let havuz = kutuphane.icerik.dersler.filter { bitti($0.id) }.flatMap { d in d.quiz.indices.map { (d, $0) } }
        let zayif = havuz.filter { yanlisSayisi("\($0.0.id)#\($0.1)") > 0 }.shuffled()
        let kalan = havuz.filter { yanlisSayisi("\($0.0.id)#\($0.1)") == 0 }.shuffled()
        return Array((zayif.prefix(adet / 2) + kalan).prefix(adet))
    }
}
