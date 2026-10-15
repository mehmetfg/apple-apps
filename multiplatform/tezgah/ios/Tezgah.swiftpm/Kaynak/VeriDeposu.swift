// Vault klasörünü bir kez seçtirir (iCloud Drive › Obsidian › Personel Data Management),
// yer imini saklar, tezgah.json'u ve kapakları oradan okur. Hiçbir dosyaya yazmaz.
import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

@MainActor
final class VeriDeposu: ObservableObject {
    enum Durum: Equatable {
        case kurulmadi
        case yukleniyor
        case hazir
        case hata(String)
    }

    @Published var veri: TezgahVeri?
    @Published var durum: Durum = .kurulmadi
    @Published var klasorAdi: String?
    @Published var sonOkuma: Date?

    private var klasor: URL?
    private var jsonKlasoru: URL?
    private var kapaklar: [String: Image] = [:]
    private let anahtar = "tezgah.klasor.yerimi"

    /// Seçilen klasöre göre tezgah.json'un olası yerleri (vault kökü, Artifacts, _ortak, ios ya da bir üstü).
    private let adaylar = [
        "Artifacts/_ortak/ios/tezgah.json",
        "_ortak/ios/tezgah.json",
        "ios/tezgah.json",
        "tezgah.json",
        "Personel Data Management/Artifacts/_ortak/ios/tezgah.json",
        "Documents/Personel Data Management/Artifacts/_ortak/ios/tezgah.json",
    ]

    init() {
        #if DEBUG
        // Simülatör sınaması: `simctl launch … -tezgahJSON /yol/tezgah.json` klasör seçmeden yükler.
        if let p = UserDefaults.standard.string(forKey: "tezgahJSON"),
           (try? dosyadanYukle(URL(fileURLWithPath: p))) != nil {
            klasorAdi = "sınama"
            return
        }
        #endif
        if let veri = UserDefaults.standard.data(forKey: anahtar) {
            var eski = false
            if let url = try? URL(resolvingBookmarkData: veri, options: Self.cozmeSecenek, relativeTo: nil,
                                  bookmarkDataIsStale: &eski) {
                klasor = url
                klasorAdi = url.lastPathComponent
                if eski { yerImiYaz(url) }
                durum = .yukleniyor
            }
        }
    }

    var kurulu: Bool { klasor != nil }

    // MARK: klasör

    func klasorSecildi(_ url: URL) {
        let erisim = url.startAccessingSecurityScopedResource()
        defer { if erisim { url.stopAccessingSecurityScopedResource() } }
        yerImiYaz(url)
        klasor = url
        klasorAdi = url.lastPathComponent
        kapaklar = [:]
        Task { await yukle() }
    }

    func klasoruUnut() {
        UserDefaults.standard.removeObject(forKey: anahtar)
        klasor = nil
        klasorAdi = nil
        veri = nil
        kapaklar = [:]
        durum = .kurulmadi
    }

    private func yerImiYaz(_ url: URL) {
        if let v = try? url.bookmarkData(options: Self.yerImiSecenek, includingResourceValuesForKeys: nil,
                                         relativeTo: nil) {
            UserDefaults.standard.set(v, forKey: anahtar)
        }
    }

    #if os(macOS)
    private static let yerImiSecenek: URL.BookmarkCreationOptions = [.withSecurityScope]
    private static let cozmeSecenek: URL.BookmarkResolutionOptions = [.withSecurityScope]
    #else
    private static let yerImiSecenek: URL.BookmarkCreationOptions = []
    private static let cozmeSecenek: URL.BookmarkResolutionOptions = []
    #endif

    // MARK: okuma

    func yukle() async {
        guard let klasor else { durum = .kurulmadi; return }
        if veri == nil { durum = .yukleniyor }
        let adaylar = self.adaylar
        let sonuc: Result<(TezgahVeri, URL), Error> = await Task.detached(priority: .userInitiated) {
            let erisim = klasor.startAccessingSecurityScopedResource()
            defer { if erisim { klasor.stopAccessingSecurityScopedResource() } }
            do {
                let yol = try await Self.bul(klasor, adaylar)
                let data = try Self.koordineliOku(yol)
                let v = try JSONDecoder().decode(TezgahVeri.self, from: data)
                return .success((v, yol.deletingLastPathComponent()))
            } catch {
                return .failure(error)
            }
        }.value
        switch sonuc {
        case .success(let (v, k)):
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                veri = v
                jsonKlasoru = k
                sonOkuma = Date()
                durum = .hazir
            }
        case .failure(let e):
            if veri == nil {
                durum = .hata(e.localizedDescription)
            }
        }
    }

    /// iCloud'da henüz inmemiş dosya `.tezgah.json.icloud` yer tutucusu olarak durur:
    /// indirmeyi başlatıp en çok ~20 sn bekler.
    nonisolated private static func bul(_ kok: URL, _ adaylar: [String]) async throws -> URL {
        let fm = FileManager.default
        for _ in 0..<40 {
            for a in adaylar {
                let url = kok.appendingPathComponent(a)
                let yerTutucu = url.deletingLastPathComponent()
                    .appendingPathComponent("." + url.lastPathComponent + ".icloud")
                if fm.fileExists(atPath: url.path) {
                    try? fm.startDownloadingUbiquitousItem(at: url)  // daha yeni sürüm varsa iner
                    return url
                }
                if fm.fileExists(atPath: yerTutucu.path) {
                    try? fm.startDownloadingUbiquitousItem(at: url)
                }
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw HataMesaji("tezgah.json bu klasörde bulunamadı. Vault'un kendisini (Personel Data Management) seçtiğinden emin ol; Mac'te pano bir kez çalışmış olmalı.")
    }

    nonisolated private static func koordineliOku(_ url: URL) throws -> Data {
        var hata: NSError?
        var sonuc: Result<Data, Error> = .failure(HataMesaji("okunamadı"))
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &hata) { u in
            sonuc = Result { try Data(contentsOf: u) }
        }
        if let hata { throw hata }
        return try sonuc.get()
    }

    // MARK: kapaklar

    func kapak(_ ad: String?) -> Image? {
        guard let ad, let k = jsonKlasoru, let klasor else { return nil }
        if let i = kapaklar[ad] { return i }
        let erisim = klasor.startAccessingSecurityScopedResource()
        defer { if erisim { klasor.stopAccessingSecurityScopedResource() } }
        let url = k.appendingPathComponent("kapak").appendingPathComponent(ad)
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        guard let d = try? Data(contentsOf: url) else { return nil }
        #if canImport(UIKit)
        guard let ui = UIImage(data: d) else { return nil }
        let i = Image(uiImage: ui)
        #else
        guard let ns = NSImage(data: d) else { return nil }
        let i = Image(nsImage: ns)
        #endif
        kapaklar[ad] = i
        return i
    }

    // MARK: önizleme / sınama

    /// Klasör seçmeden doğrudan bir dosyadan yükler (Mac'teki ön izleme betiği kullanır).
    func dosyadanYukle(_ json: URL) throws {
        let v = try JSONDecoder().decode(TezgahVeri.self, from: Data(contentsOf: json))
        veri = v
        jsonKlasoru = json.deletingLastPathComponent()
        klasor = json.deletingLastPathComponent()
        durum = .hazir
        sonOkuma = Date()
    }
}

struct HataMesaji: LocalizedError {
    let mesaj: String
    init(_ m: String) { mesaj = m }
    var errorDescription: String? { mesaj }
}
