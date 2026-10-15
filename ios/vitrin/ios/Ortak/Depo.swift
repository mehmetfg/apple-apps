// Uygulama ile widget'ın ortak dolabı (App Group).
//   vitrin.json      öğrenme içeriği (vault'tan ya da uygulamaya gömülü kopyadan)
//   tasarimlar.json  duvar ve widget tasarımları, günlük liste, bilinen kelimeler
//   gorseller/       seçilen fotoğraflar (en çok 2796 px) ve özne maskeleri
import Foundation
import UIKit
import ImageIO

enum Depo {
    static let grup = "group.com.fatihgocgun.vitrin"
    static let widgetTuru = "VitrinWidget"

    static var klasor: URL {
        if let u = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: grup) { return u }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    static var ayar: UserDefaults { UserDefaults(suiteName: grup) ?? .standard }

    private static var veriURL: URL { klasor.appendingPathComponent("vitrin.json") }
    private static var tasarimURL: URL { klasor.appendingPathComponent("tasarimlar.json") }
    static var gorselKlasoru: URL {
        let u = klasor.appendingPathComponent("gorseller", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    // MARK: içerik
    static func veriOku() -> VitrinVeri? {
        guard let d = try? Data(contentsOf: veriURL) else { return nil }
        return try? JSONDecoder().decode(VitrinVeri.self, from: d)
    }

    @discardableResult
    static func veriYaz(_ d: Data) -> Bool {
        guard (try? JSONDecoder().decode(VitrinVeri.self, from: d)) != nil else { return false }
        return (try? d.write(to: veriURL, options: .atomic)) != nil
    }

    // MARK: tasarımlar
    static func tasarimOku() -> Tasarimlar? {
        guard let d = try? Data(contentsOf: tasarimURL) else { return nil }
        let c = JSONDecoder(); c.dateDecodingStrategy = .iso8601
        return try? c.decode(Tasarimlar.self, from: d)
    }

    static func tasarimYaz(_ t: Tasarimlar) {
        let c = JSONEncoder(); c.dateEncodingStrategy = .iso8601
        if let d = try? c.encode(t) { try? d.write(to: tasarimURL, options: .atomic) }
    }

    // MARK: görseller
    static func gorselURL(_ ad: String) -> URL { gorselKlasoru.appendingPathComponent(ad) }

    /// Fotoğrafı en uzun kenarı `boy` piksel olacak şekilde küçültüp kaydeder; dosya adını döner.
    static func gorselKaydet(_ veri: Data, boy: CGFloat = 2796) -> String? {
        guard let img = kucult(veri: veri, enUzun: boy) else { return nil }
        let ad = "foto-\(UUID().uuidString.prefix(8)).jpg"
        guard let jpg = UIImage(cgImage: img).jpegData(compressionQuality: 0.9) else { return nil }
        return (try? jpg.write(to: gorselURL(ad), options: .atomic)) != nil ? ad : nil
    }

    static func pngKaydet(_ img: UIImage, ad: String) {
        if let d = img.pngData() { try? d.write(to: gorselURL(ad), options: .atomic) }
    }

    /// Widget belleği dar (≈30 MB): görseli diskte küçültülmüş okur, tam boyu belleğe almaz.
    static func gorsel(_ ad: String?, enUzun: CGFloat) -> UIImage? {
        guard let ad, let d = try? Data(contentsOf: gorselURL(ad)) else { return nil }
        return kucult(veri: d, enUzun: enUzun).map { UIImage(cgImage: $0) }
    }

    static func kucult(veri: Data, enUzun: CGFloat) -> CGImage? {
        guard let kaynak = CGImageSourceCreateWithData(veri as CFData, nil) else { return nil }
        let s: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: enUzun,
        ]
        return CGImageSourceCreateThumbnailAtIndex(kaynak, 0, s as CFDictionary)
    }

    static func ozneAdi(_ foto: String) -> String { (foto as NSString).deletingPathExtension + "-ozne.png" }
    static func ozneVar(_ foto: String?) -> Bool {
        guard let foto else { return false }
        return FileManager.default.fileExists(atPath: gorselURL(ozneAdi(foto)).path)
    }

    // MARK: widget düğmelerinin durumu
    static func cevrik(_ id: UUID) -> Bool { ayar.bool(forKey: "cevrik.\(id.uuidString)") }
    static func ileri(_ id: UUID) -> Int {
        // "Sonraki" sayacı gün değişince sıfırlanır
        let gun = ayar.string(forKey: "ileriGun.\(id.uuidString)")
        return gun == Secici.gunAnahtari(.now) ? ayar.integer(forKey: "ileri.\(id.uuidString)") : 0
    }
}
