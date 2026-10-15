// Vault köprüsü. iPhone'da kullanıcı iCloud'daki vault klasörünü bir kez seçer (yer imi saklanır);
// Mac'te vault yolu sabittir. İkisinde de iş klasörü: 00 - Philosophy/_projects/teoria
import Foundation

@MainActor
final class Kasa: ObservableObject {
    @Published private(set) var bagli = false
    @Published private(set) var klasorAdi = ""
    @Published var hata: String?

    private let anahtar = "teoria.kasa.yerimi"
    private var kok: URL?

    #if os(macOS)
    static let macYolu = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Mobile Documents/iCloud~md~obsidian/Documents/Personel Data Management/00 - Philosophy/_projects/teoria")
    #endif

    init() {
        #if os(macOS)
        if let v = ProcessInfo.processInfo.environment["TEORIA_VAULT"] {
            kok = URL(fileURLWithPath: v); bagli = true; klasorAdi = "sınama"
        } else if ProcessInfo.processInfo.environment["TEORIA_KAPSAYICI"] == nil, FileManager.default.fileExists(atPath: Kasa.macYolu.path) {
            kok = Kasa.macYolu; bagli = true; klasorAdi = "teoria (vault)"
        }
        #else
        if let v = UserDefaults.standard.data(forKey: anahtar) {
            var eski = false
            if let u = try? URL(resolvingBookmarkData: v, options: [], relativeTo: nil, bookmarkDataIsStale: &eski) {
                kok = u; bagli = true; klasorAdi = u.lastPathComponent
                if eski { yerImi(u) }
            }
        }
        #endif
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

    /// Seçilen klasör vault kökü, 00 - Philosophy ya da doğrudan teoria olabilir.
    nonisolated static func teoria(_ kok: URL) -> URL {
        let fm = FileManager.default
        for yol in ["00 - Philosophy/_projects/teoria", "_projects/teoria", "teoria", ""] {
            let u = yol.isEmpty ? kok : kok.appendingPathComponent(yol)
            if fm.fileExists(atPath: u.appendingPathComponent("veri").path) { return u }
        }
        return kok.appendingPathComponent("00 - Philosophy/_projects/teoria")
    }

    /// Klasöre güvenli erişimle bir iş yaptırır (arka planda).
    func ile<T: Sendable>(_ is: @escaping @Sendable (URL) throws -> T) async -> T? {
        guard let kok else { return nil }
        let sonuc: Result<T, Error> = await Task.detached {
            let e = kok.startAccessingSecurityScopedResource()
            defer { if e { kok.stopAccessingSecurityScopedResource() } }
            do { return .success(try `is`(Kasa.teoria(kok))) } catch { return .failure(error) }
        }.value
        switch sonuc {
        case .success(let v): hata = nil; return v
        case .failure(let h): hata = h.localizedDescription; return nil
        }
    }

    /// iCloud'dan inmemiş dosyayı indirmeyi başlatır, en çok ~5 sn bekler.
    nonisolated static func indir(_ u: URL) {
        let fm = FileManager.default
        try? fm.startDownloadingUbiquitousItem(at: u)
        var i = 0
        while !fm.fileExists(atPath: u.path) && i < 20 { Thread.sleep(forTimeInterval: 0.25); i += 1 }
    }

    nonisolated static func koordineliOku(_ u: URL) -> Data? {
        var veri: Data?
        var h: NSError?
        NSFileCoordinator().coordinate(readingItemAt: u, options: [], error: &h) { x in veri = try? Data(contentsOf: x) }
        return veri
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
