// Vault köprüsü. Kullanıcı iCloud'daki vault klasörünü bir kez seçer (yer imi saklanır).
// Seçilen klasör vault kökü, "01 - English Learning" ya da doğrudan "oncalisma" olabilir.
// Vault'a dokunan her iş arka planda yapılır — iCloud izni ana iş parçacığını bekletebilir (Teoria'da bulundu).
import Foundation

@MainActor
final class Kasa: ObservableObject {
    @Published private(set) var bagli = false
    @Published private(set) var klasorAdi = ""
    @Published var hata: String?

    private let anahtar = "memories.kasa.yerimi"
    private var kok: URL?

    init() {
        if let v = ProcessInfo.processInfo.environment["MEMORIES_VAULT"] {
            kok = URL(fileURLWithPath: v); bagli = true; klasorAdi = "sınama"; return
        }
        if let v = UserDefaults.standard.data(forKey: anahtar) {
            var eski = false
            if let u = try? URL(resolvingBookmarkData: v, options: [], relativeTo: nil, bookmarkDataIsStale: &eski) {
                kok = u; bagli = true; klasorAdi = u.lastPathComponent
                if eski { yerImi(u) }
            }
        }
    }

    func klasorSecildi(_ url: URL) {
        let e = url.startAccessingSecurityScopedResource()
        defer { if e { url.stopAccessingSecurityScopedResource() } }
        yerImi(url)
        kok = url; bagli = true; klasorAdi = url.lastPathComponent; hata = nil
    }

    func unut() {
        UserDefaults.standard.removeObject(forKey: anahtar)
        kok = nil; bagli = false; klasorAdi = ""
    }

    private func yerImi(_ url: URL) {
        if let v = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(v, forKey: anahtar)
        }
    }

    nonisolated static func oncalisma(_ kok: URL) -> URL {
        let fm = FileManager.default
        for yol in ["01 - English Learning/oncalisma", "oncalisma", ""] {
            let u = yol.isEmpty ? kok : kok.appendingPathComponent(yol)
            if fm.fileExists(atPath: u.appendingPathComponent("paket").path) { return u }
        }
        return kok.appendingPathComponent("01 - English Learning/oncalisma")
    }

    /// Klasöre güvenli erişimle bir iş yaptırır (arka planda).
    func ile<T: Sendable>(_ is: @escaping @Sendable (URL) throws -> T) async -> T? {
        guard let kok else { return nil }
        let sonuc: Result<T, Error> = await Task.detached {
            let e = kok.startAccessingSecurityScopedResource()
            defer { if e { kok.stopAccessingSecurityScopedResource() } }
            do { return .success(try `is`(Kasa.oncalisma(kok))) } catch { return .failure(error) }
        }.value
        switch sonuc {
        case .success(let v): hata = nil; return v
        case .failure(let h): hata = h.localizedDescription; return nil
        }
    }

    /// iCloud'dan inmemiş dosyanın indirilmesini başlatır, en çok `bekle` sn bekler.
    nonisolated static func indir(_ u: URL, bekle: Double = 5) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: u.path), (try? u.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?
            .ubiquitousItemDownloadingStatus != .notDownloaded { return true }
        try? fm.startDownloadingUbiquitousItem(at: u)
        var i = 0.0
        while i < bekle {
            let durum = (try? u.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?.ubiquitousItemDownloadingStatus
            if durum == .current || (durum == nil && fm.fileExists(atPath: u.path)) { return true }
            Thread.sleep(forTimeInterval: 0.25); i += 0.25
        }
        return false
    }

    nonisolated static func koordineliOku(_ u: URL) -> Data? {
        var veri: Data?
        var h: NSError?
        NSFileCoordinator().coordinate(readingItemAt: u, options: [], error: &h) { x in veri = try? Data(contentsOf: x) }
        return veri
    }

    nonisolated static func koordineliKopyala(_ kaynak: URL, _ hedef: URL) -> Bool {
        var tamam = false
        var h: NSError?
        try? FileManager.default.createDirectory(at: hedef.deletingLastPathComponent(), withIntermediateDirectories: true)
        NSFileCoordinator().coordinate(readingItemAt: kaynak, options: [], error: &h) { x in
            let g = hedef.appendingPathExtension("iniyor")
            try? FileManager.default.removeItem(at: g)
            if (try? FileManager.default.copyItem(at: x, to: g)) != nil {
                try? FileManager.default.removeItem(at: hedef)
                tamam = (try? FileManager.default.moveItem(at: g, to: hedef)) != nil
            }
        }
        return tamam
    }

    nonisolated static func koordineliYaz(_ v: Data, _ u: URL) throws {
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        var h: NSError?
        var ic: Error?
        NSFileCoordinator().coordinate(writingItemAt: u, options: .forReplacing, error: &h) { x in
            do { try v.write(to: x, options: .atomic) } catch { ic = error }
        }
        if let e = h ?? ic { throw e }
    }
}

// Olay günlüğü — JSON Lines. Her cihaz yalnız kendi dosyasına satır ekler (ilerleme/<cihaz>.jsonl).
// Okurken bütün .jsonl dosyaları birleşir; aynı kimlik bir kez sayılır (iCloud çakışma kopyaları kayıpsız okunur).
enum Gunluk {
    static let kodlayici: JSONEncoder = {
        let c = JSONEncoder()
        c.dateEncodingStrategy = .iso8601
        c.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return c
    }()
    static let cozucu: JSONDecoder = {
        let c = JSONDecoder(); c.dateDecodingStrategy = .iso8601; return c
    }()

    static func satir(_ o: Olay) -> Data {
        var v = (try? kodlayici.encode(o)) ?? Data()
        v.append(0x0A)
        return v
    }

    static func coz(_ veri: Data) -> (olaylar: [Olay], bozuk: Int) {
        var sonuc: [Olay] = []
        var bozuk = 0
        for parca in veri.split(separator: 0x0A, omittingEmptySubsequences: true) {
            if let o = try? cozucu.decode(Olay.self, from: Data(parca)) { sonuc.append(o) } else { bozuk += 1 }
        }
        return (sonuc, bozuk)
    }

    static func oku(_ dosya: URL) -> [Olay] {
        guard let v = try? Data(contentsOf: dosya) else { return [] }
        return coz(v).olaylar
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

    static func veri(_ olaylar: [Olay]) -> Data {
        var v = Data()
        for o in olaylar.sorted(by: { $0.t < $1.t }) { v.append(satir(o)) }
        return v
    }
}
