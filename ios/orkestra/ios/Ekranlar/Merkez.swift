// Uygulamanın tek durumu: vault'tan oku → telefonun kendi izleriyle tazele → motoru çalıştır →
// widget dolabına yaz → bildirimleri kur. Ön plana gelişte, arka plan yenilemesinde ve dakikada bir (açıkken) koşar.
import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class Merkez: ObservableObject {
    @Published private(set) var veri: OrkestraVeri?
    @Published private(set) var durum: Durumlar?
    @Published private(set) var bagli = false
    @Published private(set) var klasorAdi = ""
    @Published private(set) var sonOkuma: Date?
    @Published var hata: String?
    @Published var yukleniyor = false

    private let anahtar = "orkestra.kasa.yerimi"
    private var kok: URL?

    static let yol = "_araçlar/orkestra/durum/orkestra.json"

    /// Şu an. DEBUG'da ORKESTRA_SIMDI ile başka bir ân taklit edilir (bildirim ve motor sınaması).
    nonisolated static var simdi: Date {
        #if DEBUG
        if let s = ProcessInfo.processInfo.environment["ORKESTRA_SIMDI"], let d = Tarih.coz(s) { return d }
        #endif
        return .now
    }

    init() {
        if let v = ProcessInfo.processInfo.environment["ORKESTRA_VAULT"] {
            kok = URL(fileURLWithPath: v); bagli = true; klasorAdi = "sınama"
        } else if let v = Depo.ayar.data(forKey: anahtar) {
            var eski = false
            if let u = try? URL(resolvingBookmarkData: v, options: [], relativeTo: nil, bookmarkDataIsStale: &eski) {
                kok = u; bagli = true; klasorAdi = u.lastPathComponent
                if eski { yerImi(u) }
            }
        }
        if let v = Depo.veriOku() { uygula(v) }
    }

    // MARK: vault klasörü
    func klasorSecildi(_ url: URL) {
        let e = url.startAccessingSecurityScopedResource()
        defer { if e { url.stopAccessingSecurityScopedResource() } }
        yerImi(url)
        kok = url; bagli = true; klasorAdi = url.lastPathComponent; hata = nil
        Task { await tazele() }
    }

    func unut() {
        Depo.ayar.removeObject(forKey: anahtar)
        kok = nil; bagli = false; klasorAdi = ""
    }

    private func yerImi(_ url: URL) {
        if let v = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            Depo.ayar.set(v, forKey: anahtar)
        }
    }

    // MARK: tazeleme
    func tazele(bildir: Bool = true) async {
        guard let kok else { hesapla(); return }
        yukleniyor = true
        defer { yukleniyor = false }
        let sonuc: Result<OrkestraVeri, Error> = await Task.detached {
            let e = kok.startAccessingSecurityScopedResource()
            defer { if e { kok.stopAccessingSecurityScopedResource() } }
            do { return .success(try Merkez.oku(kok)) } catch { return .failure(error) }
        }.value
        switch sonuc {
        case .success(let v):
            hata = nil
            sonOkuma = .now
            Depo.veriYaz(v)
            uygula(v)
        case .failure(let h):
            hata = "orkestra.json okunamadı: \(h.localizedDescription)"
            hesapla()
        }
        WidgetCenter.shared.reloadAllTimelines()
        if bildir, let d = durum { await Bildirimci.isle(d) }
    }

    /// Saat ilerledikçe hüküm değişir; dosyayı yeniden okumadan motoru yeniden çalıştırır.
    func hesapla() {
        guard let veri else { return }
        durum = Motor.hesapla(veri, simdi: Merkez.simdi, ertelenen: Depo.ertelenenler(Merkez.simdi))
    }

    private func uygula(_ v: OrkestraVeri) {
        veri = v
        hesapla()
    }

    func ertele(_ id: String) {
        Depo.ertele(id)
        hesapla()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: okuma (arka plan iş parçacığında)
    nonisolated static func kokBul(_ kok: URL) -> URL {
        let fm = FileManager.default
        var u = kok
        for _ in 0..<3 {   // seçilen klasör vault'un içi olabilir (ör. _araçlar/orkestra) — yukarı çık
            if fm.fileExists(atPath: u.appendingPathComponent("_araçlar").path) { return u }
            u = u.deletingLastPathComponent()
        }
        return kok
    }

    nonisolated static func oku(_ secilen: URL) throws -> OrkestraVeri {
        let kok = kokBul(secilen)
        let dosya = kok.appendingPathComponent(yol)
        _ = indir(dosya)
        guard let d = koordineliOku(dosya) else {
            throw NSError(domain: "Orkestra", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "\(yol) yok. Mac'te bir kez çalıştır: python3 _araçlar/orkestra/veri/orkestra.py"])
        }
        var v = try JSONDecoder().decode(OrkestraVeri.self, from: d)
        telefonIzleri(kok, &v)
        return v
    }

    /// Telefonun kendi yazdığı izler Mac'in son koşusundan yeni olabilir (Mac kapalı, iCloud eşitledi):
    /// Teoria ve Memories günlüklerinin son satırı süreçlerin "son dokunuş"unu ve bugünkü izini tazeler.
    nonisolated static func telefonIzleri(_ kok: URL, _ v: inout OrkestraVeri) {
        // Teoria'da yalnız çalışma olayları dokunuş sayılır (toplayıcıyla aynı ölçü); Memories'in her olayı bir eylemdir
        let kaynaklar: [(String, String, [String])] = [
            ("teoria", "00 - Philosophy/_projects/teoria/ilerleme", ["cevap", "kur", "sesNot", "kendiCumle"]),
            ("memories", "01 - English Learning/oncalisma/ilerleme", [])]
        let uretim = v.uretimZamani ?? .distantPast
        for (id, yol, turler) in kaynaklar {
            guard let i = v.surecler.firstIndex(where: { $0.id == id }) else { continue }
            let klasor = kok.appendingPathComponent(yol)
            guard let dosyalar = try? FileManager.default.contentsOfDirectory(at: klasor, includingPropertiesForKeys: nil)
            else { continue }
            var enYeni: Date?
            var bugunYeni = 0
            for f in dosyalar where f.pathExtension == "jsonl" {
                _ = indir(f, bekle: 2)
                guard let d = koordineliOku(f), let s = String(data: d, encoding: .utf8) else { continue }
                for satir in s.split(separator: "\n").suffix(80) {
                    if !turler.isEmpty, !turler.contains(where: { satir.contains("\"tur\":\"\($0)\"") }) { continue }
                    guard let r = satir.range(of: "\"t\":\"") else { continue }
                    let t = satir[r.upperBound...].prefix { $0 != "\"" }
                    guard let z = Tarih.coz(String(t)), z > uretim else { continue }
                    enYeni = max(enYeni ?? z, z)
                    if Tarih.gunFarki(z, simdi) == 0 { bugunYeni += 1 }
                }
            }
            if let z = enYeni, z > (v.surecler[i].sonDokunus ?? .distantPast) {
                v.surecler[i].son = Tarih.iso(z)
                if bugunYeni > 0, !v.surecler[i].iz.isEmpty, Tarih.gunFarki(uretim, simdi) == 0 {
                    v.surecler[i].iz[v.surecler[i].iz.count - 1] += bugunYeni
                }
            }
        }
    }

    nonisolated static func indir(_ u: URL, bekle: Double = 6) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: u.path), (try? u.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?
            .ubiquitousItemDownloadingStatus != .notDownloaded { return true }
        try? fm.startDownloadingUbiquitousItem(at: u)
        var i = 0.0
        while i < bekle {
            let d = (try? u.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?.ubiquitousItemDownloadingStatus
            if d == .current || (d == nil && fm.fileExists(atPath: u.path)) { return true }
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
}
