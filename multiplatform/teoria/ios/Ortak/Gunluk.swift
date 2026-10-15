// Olay günlüğü — JSON Lines. Her cihaz yalnız kendi dosyasına satır ekler (ilerleme/<cihaz>.jsonl).
// Okurken klasördeki bütün .jsonl dosyaları birleştirilir; aynı kimlikli olay bir kez sayılır.
// Böylece iCloud'un çakışma kopyaları ("iphone 2.jsonl") da kayıpsız okunur.
import Foundation

enum Gunluk {
    static let kodlayici: JSONEncoder = {
        let c = JSONEncoder()
        c.dateEncodingStrategy = .iso8601
        c.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return c
    }()

    static let cozucu: JSONDecoder = {
        let c = JSONDecoder()
        c.dateDecodingStrategy = .iso8601
        return c
    }()

    static func satir(_ o: Olay) -> Data {
        var v = (try? kodlayici.encode(o)) ?? Data()
        v.append(0x0A)
        return v
    }

    /// Bozuk ya da yarım satır atlanır, kalan okunur.
    static func coz(_ veri: Data) -> (olaylar: [Olay], bozuk: Int) {
        var sonuc: [Olay] = []
        var bozuk = 0
        for parca in veri.split(separator: 0x0A, omittingEmptySubsequences: true) {
            if let o = try? cozucu.decode(Olay.self, from: Data(parca)) { sonuc.append(o) } else { bozuk += 1 }
        }
        return (sonuc, bozuk)
    }

    static func oku(_ dosya: URL) -> (olaylar: [Olay], bozuk: Int) {
        guard let v = try? Data(contentsOf: dosya) else { return ([], 0) }
        return coz(v)
    }

    /// Klasördeki bütün günlükler (çakışma kopyaları dahil).
    static func klasoruOku(_ klasor: URL) -> (olaylar: [Olay], bozuk: Int, dosyalar: [String]) {
        let fm = FileManager.default
        guard let ad = try? fm.contentsOfDirectory(atPath: klasor.path) else { return ([], 0, []) }
        var tum: [Olay] = []
        var bozuk = 0
        var dosyalar: [String] = []
        for a in ad {
            // iCloud'dan inmemiş dosya: ".iphone.jsonl.icloud" — indirmeyi başlat, bu turda atla.
            if a.hasPrefix("."), a.hasSuffix(".icloud") {
                let gercek = String(a.dropFirst().dropLast(7))
                try? fm.startDownloadingUbiquitousItem(at: klasor.appendingPathComponent(gercek))
                continue
            }
            guard a.hasSuffix(".jsonl") else { continue }
            let r = oku(klasor.appendingPathComponent(a))
            tum += r.olaylar
            bozuk += r.bozuk
            dosyalar.append(a)
        }
        return (tum, bozuk, dosyalar)
    }

    static func tekille(_ o: [Olay]) -> [Olay] {
        var gorulen = Set<String>()
        return o.filter { gorulen.insert($0.id).inserted }
    }

    static func ekle(_ o: Olay, _ dosya: URL) {
        let v = satir(o)
        try? FileManager.default.createDirectory(at: dosya.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let h = try? FileHandle(forWritingTo: dosya) {
            h.seekToEndOfFile(); h.write(v); try? h.close()
        } else {
            try? v.write(to: dosya, options: .atomic)
        }
    }

    static func yaz(_ olaylar: [Olay], _ dosya: URL) throws {
        var v = Data()
        for o in olaylar.sorted(by: { $0.t < $1.t }) { v.append(satir(o)) }
        try FileManager.default.createDirectory(at: dosya.deletingLastPathComponent(), withIntermediateDirectories: true)
        try v.write(to: dosya, options: .atomic)
    }
}
