import Foundation

/// Bir müzik dosyası. Kimliği dosya adıdır; aynı adla ikinci kopya alınmaz.
struct Parca: Identifiable, Hashable {
    let url: URL
    var id: String { url.lastPathComponent }
    var ad: String { url.deletingPathExtension().lastPathComponent }
}

/// Müzik uygulamanın kendi Belgeler klasöründe durur (Dosyalar › iPhone'umda › Fon).
/// Çalma her zaman bu yerel kopyadan yapılır: arka planda iCloud'a ya da izin süresine bağlı kalmaz.
/// Bağlanan klasör (ör. iCloud Drive/Fon) yalnız kaynaktır; eşitleme yeni dosyaları buraya kopyalar.
enum Depo {
    static let uzantilar: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac", "mp4", "m4b"]
    private static let yerImiAnahtari = "kaynakKlasorYerImi"
    static let klasorAdiAnahtari = "kaynakKlasorAdi"

    static var klasor: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    static func parcalar() -> [Parca] {
        let fm = FileManager.default
        let urller = (try? fm.contentsOfDirectory(at: klasor, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return urller
            .filter { uzantilar.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map(Parca.init)
    }

    /// Paylaş menüsünden gelen dosyalar Belgeler/Inbox'a düşer; onları ana klasöre alır.
    static func gelenKutusunuBosalt() {
        let fm = FileManager.default
        let kutu = klasor.appendingPathComponent("Inbox")
        guard let icerik = try? fm.contentsOfDirectory(at: kutu, includingPropertiesForKeys: nil) else { return }
        for url in icerik where uzantilar.contains(url.pathExtension.lowercased()) {
            let hedef = klasor.appendingPathComponent(url.lastPathComponent)
            if fm.fileExists(atPath: hedef.path) { try? fm.removeItem(at: url) } else { try? fm.moveItem(at: url, to: hedef) }
        }
        try? fm.removeItem(at: kutu)
    }

    /// Tek dosyayı içeri kopyalar. Aynı ad ve aynı boyutta dosya varsa dokunmaz.
    @discardableResult
    static func iceriAl(_ kaynak: URL) throws -> Bool {
        let fm = FileManager.default
        let hedef = klasor.appendingPathComponent(kaynak.lastPathComponent)
        if fm.fileExists(atPath: hedef.path) {
            if boyut(hedef) == boyut(kaynak) { return false }
            try fm.removeItem(at: hedef)
        }
        var hata: NSError?
        var icHata: Error?
        // Koordineli okuma, iCloud'da yalnız bulutta duran dosyayı önce indirir.
        NSFileCoordinator().coordinate(readingItemAt: kaynak, options: [], error: &hata) { okunur in
            do { try fm.copyItem(at: okunur, to: hedef) } catch { icHata = error }
        }
        if let hata { throw hata }
        if let icHata { throw icHata }
        return true
    }

    static func sil(_ parca: Parca) {
        try? FileManager.default.removeItem(at: parca.url)
    }

    private static func boyut(_ url: URL) -> Int? {
        try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    }

    // MARK: Kaynak klasör

    static func klasorBagla(_ url: URL) throws {
        let erisim = url.startAccessingSecurityScopedResource()
        defer { if erisim { url.stopAccessingSecurityScopedResource() } }
        let veri = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(veri, forKey: yerImiAnahtari)
        UserDefaults.standard.set(url.lastPathComponent, forKey: klasorAdiAnahtari)
    }

    static func klasorBaginiKaldir() {
        UserDefaults.standard.removeObject(forKey: yerImiAnahtari)
        UserDefaults.standard.removeObject(forKey: klasorAdiAnahtari)
    }

    static var bagliKlasorVar: Bool { UserDefaults.standard.data(forKey: yerImiAnahtari) != nil }

    struct EsitlemeSonucu {
        var yeni = 0
        var hatalar: [String] = []
    }

    /// Bağlı klasördeki (alt klasörler dahil) ses dosyalarından yerelde olmayanları kopyalar.
    /// Kaynaktan silinen dosya yerelden silinmez — telefondaki kopyayı yalnız kullanıcı siler.
    static func esitle() -> EsitlemeSonucu {
        var sonuc = EsitlemeSonucu()
        guard let veri = UserDefaults.standard.data(forKey: yerImiAnahtari) else { return sonuc }
        var eski = false
        guard let kok = try? URL(resolvingBookmarkData: veri, options: [], relativeTo: nil, bookmarkDataIsStale: &eski) else {
            sonuc.hatalar.append("Bağlı klasöre ulaşılamadı; klasörü yeniden bağla.")
            return sonuc
        }
        let erisim = kok.startAccessingSecurityScopedResource()
        defer { if erisim { kok.stopAccessingSecurityScopedResource() } }
        if eski { try? klasorBagla(kok) }

        let fm = FileManager.default
        guard let gezgin = fm.enumerator(at: kok, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsPackageDescendants]) else {
            sonuc.hatalar.append("Klasör okunamadı.")
            return sonuc
        }
        for case let url as URL in gezgin {
            var gercek = url
            let ad = url.lastPathComponent
            // Eski iCloud yer tutucusu: ".parca.mp3.icloud"
            if ad.hasPrefix("."), ad.hasSuffix(".icloud") {
                let asil = String(ad.dropFirst().dropLast(".icloud".count))
                gercek = url.deletingLastPathComponent().appendingPathComponent(asil)
                try? fm.startDownloadingUbiquitousItem(at: gercek)
            } else if ad.hasPrefix(".") {
                continue
            }
            guard uzantilar.contains(gercek.pathExtension.lowercased()) else { continue }
            do {
                if try iceriAl(gercek) { sonuc.yeni += 1 }
            } catch {
                sonuc.hatalar.append(gercek.lastPathComponent)
            }
        }
        return sonuc
    }
}
