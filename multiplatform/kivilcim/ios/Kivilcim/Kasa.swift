// Vault köprüsü (Memories'in Kasa'sından). Kullanıcı iCloud'daki vault klasörünü bir kez seçer, yer imi saklanır.
// Seçilen klasör vault kökü ("Personel Data Management"), "Fikirler" ya da doğrudan "Kıvılcım" olabilir.
// Vault'a dokunan her iş arka planda yapılır; iCloud izni ana iş parçacığını bekletebilir.
import Foundation

@MainActor
final class Kasa: ObservableObject {
    static let shared = Kasa()
    @Published private(set) var bagli = false
    @Published private(set) var klasorAdi = ""
    @Published var hata: String?

    private let anahtar = "kivilcim.kasa.yerimi"
    private var kok: URL?

    init() {
        if let v = ProcessInfo.processInfo.environment["KIVILCIM_VAULT"] {
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

    /// Seçilen klasörden Kıvılcım veri klasörünü bulur.
    nonisolated static func veriKlasoru(_ sec: URL) -> URL {
        if sec.lastPathComponent == "Kıvılcım" { return sec }
        if sec.lastPathComponent == "Fikirler" { return sec.appendingPathComponent("Kıvılcım") }
        if sec.lastPathComponent == "05 - Notlar" { return sec.appendingPathComponent("Fikirler/Kıvılcım") }
        return sec.appendingPathComponent(veriKlasoruYolu)
    }

    /// Klasöre güvenli erişimle bir iş yaptırır (arka planda). Bağlı değilse nil.
    func ile<T: Sendable>(_ is: @escaping @Sendable (URL) throws -> T) async -> T? {
        guard let kok else { return nil }
        let sonuc: Result<T, Error> = await Task.detached {
            let e = kok.startAccessingSecurityScopedResource()
            defer { if e { kok.stopAccessingSecurityScopedResource() } }
            do { return .success(try `is`(Kasa.veriKlasoru(kok))) } catch { return .failure(error) }
        }.value
        switch sonuc {
        case .success(let v): hata = nil; return v
        case .failure(let h): hata = h.localizedDescription; return nil
        }
    }

    /// iCloud'dan inmemiş dosyanın indirilmesini başlatır, en çok `bekle` sn bekler.
    nonisolated static func indir(_ u: URL, bekle: Double = 8) -> Bool {
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
        NSFileCoordinator().coordinate(writingItemAt: hedef, options: .forReplacing, error: &h) { x in
            let g = x.deletingLastPathComponent().appendingPathComponent("." + x.lastPathComponent + ".yaziliyor")
            try? FileManager.default.removeItem(at: g)
            if (try? FileManager.default.copyItem(at: kaynak, to: g)) != nil {
                try? FileManager.default.removeItem(at: x)
                tamam = (try? FileManager.default.moveItem(at: g, to: x)) != nil
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
