import Foundation

/// Müzik uygulamanın kendi Belgeler klasöründe durur (Dosyalar › iPhone'umda › Tını). Fon'dan devralınan klasördür:
/// Fon'a konmuş dosyalar olduğu gibi kalır. Alt klasörler korunur (albüm klasörleri).
/// Bağlanan klasör (ör. iCloud Drive/Fon) yalnız kaynaktır; eşitleme yeni dosyaları alt yollarıyla buraya kopyalar.
enum Depo {
    static let uzantilar: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac", "mp4", "m4b", "alac"]
    static let resimler: Set<String> = ["jpg", "jpeg", "png"]
    private static let yerImiAnahtari = "kaynakKlasorYerImi"
    static let klasorAdiAnahtari = "kaynakKlasorAdi"

    static var klasor: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    /// (göreli yol, boyut, değişim zamanı)
    static func dosyalar() -> [(String, Int, Double)] {
        let fm = FileManager.default
        let anahtarlar: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let gezgin = fm.enumerator(at: klasor, includingPropertiesForKeys: anahtarlar, options: [.skipsHiddenFiles]) else { return [] }
        let kok = klasor.resolvingSymlinksInPath().path
        var sonuc: [(String, Int, Double)] = []
        for case let url as URL in gezgin {
            let ad = url.lastPathComponent
            if ad == "Inbox" || ad == ".Trash" { gezgin.skipDescendants(); continue }
            guard uzantilar.contains(url.pathExtension.lowercased()),
                  let d = try? url.resourceValues(forKeys: Set(anahtarlar)), d.isRegularFile == true else { continue }
            var yol = url.resolvingSymlinksInPath().path
            if yol.hasPrefix(kok) { yol.removeFirst(kok.count) }
            while yol.hasPrefix("/") { yol.removeFirst() }
            sonuc.append((yol, d.fileSize ?? 0, d.contentModificationDate?.timeIntervalSince1970 ?? 0))
        }
        return sonuc
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

    /// Tek dosyayı `altYol` altına kopyalar. Aynı ad ve aynı boyutta dosya varsa dokunmaz.
    @discardableResult
    static func iceriAl(_ kaynak: URL, altYol: String = "") throws -> Bool {
        let fm = FileManager.default
        let hedefKlasor = altYol.isEmpty ? klasor : klasor.appendingPathComponent(altYol, isDirectory: true)
        try fm.createDirectory(at: hedefKlasor, withIntermediateDirectories: true)
        let hedef = hedefKlasor.appendingPathComponent(kaynak.lastPathComponent)
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
        // Boş kalan albüm klasörünü de kaldır.
        let ust = parca.url.deletingLastPathComponent()
        if ust.standardizedFileURL != klasor.standardizedFileURL,
           let kalan = try? FileManager.default.contentsOfDirectory(atPath: ust.path),
           !kalan.contains(where: { uzantilar.contains(($0 as NSString).pathExtension.lowercased()) }) {
            try? FileManager.default.removeItem(at: ust)
        }
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
    static var bagliKlasorAdi: String? { UserDefaults.standard.string(forKey: klasorAdiAnahtari) }

    struct EsitlemeSonucu {
        var yeni = 0
        var hatalar: [String] = []
    }

    /// Bağlı klasördeki (alt klasörler dahil) ses dosyalarından yerelde olmayanları alt yollarıyla kopyalar;
    /// albüm klasöründeki kapak resimlerini de alır. Kaynaktan silinen dosya yerelden silinmez.
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
        let kokYol = kok.resolvingSymlinksInPath().path
        for case let url as URL in gezgin {
            var gercek = url
            let ad = url.lastPathComponent
            // Eski iCloud yer tutucusu: ".parca.flac.icloud"
            if ad.hasPrefix("."), ad.hasSuffix(".icloud") {
                let asil = String(ad.dropFirst().dropLast(".icloud".count))
                gercek = url.deletingLastPathComponent().appendingPathComponent(asil)
                try? fm.startDownloadingUbiquitousItem(at: gercek)
            } else if ad.hasPrefix(".") {
                continue
            }
            let uz = gercek.pathExtension.lowercased()
            guard uzantilar.contains(uz) || resimler.contains(uz) else { continue }
            var alt = gercek.deletingLastPathComponent().resolvingSymlinksInPath().path
            if alt.hasPrefix(kokYol) { alt.removeFirst(kokYol.count) }
            while alt.hasPrefix("/") { alt.removeFirst() }
            // Kök klasördeki tekil resimler alınmaz; yalnız albüm klasöründeki kapaklar.
            if resimler.contains(uz) && alt.isEmpty { continue }
            do {
                if try iceriAl(gercek, altYol: alt), uzantilar.contains(uz) { sonuc.yeni += 1 }
            } catch {
                sonuc.hatalar.append(gercek.lastPathComponent)
            }
        }
        return sonuc
    }
}
