// Vault köprüsü: iCloud'daki vault klasörüne bir kez izin alınır (Tezgâh'la aynı yol).
//   okur:  01 - English Learning/_projects/asina/veri/kelimeler.json   (Mac'te veri.py üretir)
//   yazar: 01 - English Learning/_projects/asina/telefon/ilerleme.json (Mac'te veri.py işler)
import Foundation

@MainActor
final class Kasa: ObservableObject {
    @Published private(set) var bagli = false
    @Published private(set) var sonEslesme: Date?
    @Published private(set) var hata: String?
    @Published private(set) var klasorAdi = ""

    private let anahtar = "kasa.yerimi"
    private var klasor: URL?

    init() {
        if let v = UserDefaults.standard.data(forKey: anahtar) {
            var eski = false
            if let u = try? URL(resolvingBookmarkData: v, options: [], relativeTo: nil, bookmarkDataIsStale: &eski) {
                klasor = u
                bagli = true
                klasorAdi = u.lastPathComponent
                if eski { yerImiYaz(u) }
            }
        }
        sonEslesme = UserDefaults.standard.object(forKey: "kasa.son") as? Date
    }

    func klasorSecildi(_ url: URL) {
        let e = url.startAccessingSecurityScopedResource()
        defer { if e { url.stopAccessingSecurityScopedResource() } }
        yerImiYaz(url)
        klasor = url
        bagli = true
        klasorAdi = url.lastPathComponent
        hata = nil
    }

    func unut() {
        UserDefaults.standard.removeObject(forKey: anahtar)
        klasor = nil
        bagli = false
        klasorAdi = ""
    }

    private func yerImiYaz(_ url: URL) {
        if let v = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(v, forKey: anahtar)
        }
    }

    /// Seçilen klasör vault kökü, English Learning ya da doğrudan asina klasörü olabilir.
    nonisolated private static func asinaKlasoru(_ kok: URL) -> URL {
        let fm = FileManager.default
        for yol in ["01 - English Learning/_projects/asina", "_projects/asina", ""] {
            let u = yol.isEmpty ? kok : kok.appendingPathComponent(yol)
            if fm.fileExists(atPath: u.appendingPathComponent("veri.py").path)
                || fm.fileExists(atPath: u.appendingPathComponent("veri").path) { return u }
        }
        return kok.appendingPathComponent("01 - English Learning/_projects/asina")
    }

    func paketAl(mevcut: String) async -> Paket? {
        guard let kok = klasor else { return nil }
        let sonuc: Result<Paket?, Error> = await Task.detached {
            let e = kok.startAccessingSecurityScopedResource()
            defer { if e { kok.stopAccessingSecurityScopedResource() } }
            let u = Self.asinaKlasoru(kok).appendingPathComponent("veri/kelimeler.json")
            let fm = FileManager.default
            try? fm.startDownloadingUbiquitousItem(at: u)
            for _ in 0..<20 where !fm.fileExists(atPath: u.path) {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            do {
                var veri = Data()
                var kh: NSError?
                var ih: Error?
                NSFileCoordinator().coordinate(readingItemAt: u, options: [], error: &kh) { x in
                    do { veri = try Data(contentsOf: x) } catch { ih = error }
                }
                if let h = kh ?? ih { throw h }
                let p = try JSONDecoder().decode(Paket.self, from: veri)
                return .success(p.surum > mevcut ? p : nil)
            } catch { return .failure(error) }
        }.value
        switch sonuc {
        case .success(let p): hata = nil; return p
        case .failure(let e): hata = "Kelime verisi okunamadı: \(e.localizedDescription)"; return nil
        }
    }

    func ilerlemeYaz(_ d: [String: Any]) async {
        guard let kok = klasor,
              let veri = try? JSONSerialization.data(withJSONObject: d, options: [.prettyPrinted, .sortedKeys]) else { return }
        let h: String? = await Task.detached {
            let e = kok.startAccessingSecurityScopedResource()
            defer { if e { kok.stopAccessingSecurityScopedResource() } }
            let dir = Self.asinaKlasoru(kok).appendingPathComponent("telefon")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let u = dir.appendingPathComponent("ilerleme.json")
            var kh: NSError?
            var ih: Error?
            NSFileCoordinator().coordinate(writingItemAt: u, options: .forReplacing, error: &kh) { x in
                do { try veri.write(to: x, options: .atomic) } catch { ih = error }
            }
            return (kh ?? ih)?.localizedDescription
        }.value
        if let h { hata = "İlerleme yazılamadı: \(h)" } else {
            sonEslesme = Date()
            UserDefaults.standard.set(sonEslesme, forKey: "kasa.son")
        }
    }
}
