// Tasarımı gerçek piksele çevirir (ekranın kendi çözünürlüğünde), Fotoğraflar'a kaydeder,
// fotoğraftan palet çıkarır, fotoğraftaki özneyi ayırır (metni öznenin arkasına koymak için).
import SwiftUI
import Photos
import Vision
import CoreImage
import WidgetKit

@MainActor
enum Cizer {
    /// Duvar kâğıdı boyu: bu telefonun ekranı (nokta) ve ölçeği → 13 Pro Max'te 1284×2778
    static var ekran: CGSize { UIScreen.main.bounds.size }
    static var olcek: CGFloat { UIScreen.main.scale }

    static func duvar(_ d: Duvar, g: Gosterilen, tarih: Date = .now, faz: Double = 0,
                      boy: CGSize? = nil, olcek o: CGFloat? = nil) -> UIImage? {
        let s = boy ?? ekran
        let r = ImageRenderer(content: DuvarGorunum(duvar: d, g: g, tarih: tarih, faz: faz).frame(width: s.width, height: s.height))
        r.scale = o ?? olcek
        r.isOpaque = true
        return r.uiImage
    }

    static func gununDuvari(tarih: Date = .now) -> (UIImage, Duvar)? {
        let k = Depo.tasarimOku() ?? Varsayilan.tasarimlar()
        let v = Depo.veriOku() ?? .bos
        guard let d = GunlukSecim.duvar(k, tarih) else { return nil }
        let g = Gosterilen.hesapla(d.icerik, veri: v, tarih: tarih, adim: 0, bilinen: Set(k.bilinen), metin: d.metin)
        guard let img = duvar(d, g: g, tarih: tarih) else { return nil }
        return (img, d)
    }

    static func widget(_ t: WidgetTasarim, g: Gosterilen, aile: WidgetFamily, veri: VitrinVeri, bilinen: Set<String>,
                       tarih: Date = .now, olcek o: CGFloat = 3) -> UIImage? {
        let s = WidgetOlcu.boy(aile)
        let r = ImageRenderer(content: WidgetOnizleme(t: t, g: g, aile: aile, tarih: tarih, veri: veri, bilinen: bilinen)
            .frame(width: s.width, height: s.height))
        r.scale = o
        return r.uiImage
    }
}

enum Fotograflar {
    enum Hata: LocalizedError {
        case izin
        var errorDescription: String? { "Fotoğraflar'a ekleme izni yok — Ayarlar › Vitrin › Fotoğraflar" }
    }

    static func izin() async throws {
        let d = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard d == .authorized || d == .limited else { throw Hata.izin }
    }

    static func kaydet(_ img: UIImage) async throws {
        try await izin()
        guard let veri = img.pngData() else { return }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: veri, options: nil)
        }
    }

    @discardableResult
    static func canliKaydet(foto: URL, video: URL) async throws -> String? {
        try await izin()
        var kimlik: String?
        try await PHPhotoLibrary.shared().performChanges {
            let r = PHAssetCreationRequest.forAsset()
            r.addResource(with: .photo, fileURL: foto, options: nil)
            r.addResource(with: .pairedVideo, fileURL: video, options: nil)
            kimlik = r.placeholderForCreatedAsset?.localIdentifier
        }
        return kimlik
    }
}

enum PaletCikar {
    /// 48×48'e küçültüp k-ortalama (k=6); en kalabalık dört küme, koyudan açığa
    static func renkler(_ img: UIImage) -> [String] {
        guard let cg = img.cgImage else { return Palet.hepsi[0].renkler }
        let n = 48
        var px = [UInt8](repeating: 0, count: n * n * 4)
        guard let ctx = CGContext(data: &px, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return Palet.hepsi[0].renkler }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
        var noktalar: [SIMD3<Double>] = []
        for i in 0..<(n * n) {
            noktalar.append(SIMD3(Double(px[i * 4]), Double(px[i * 4 + 1]), Double(px[i * 4 + 2])) / 255)
        }
        let k = 6
        var r = Tohum(7)
        var merkez = (0..<k).map { _ in noktalar[Int(r.oran() * Double(noktalar.count))] }
        var atama = [Int](repeating: 0, count: noktalar.count)
        for _ in 0..<12 {
            for (i, p) in noktalar.enumerated() {
                var en = 0; var enD = Double.infinity
                for (j, m) in merkez.enumerated() {
                    let d = p - m; let dd = (d * d).sum()
                    if dd < enD { enD = dd; en = j }
                }
                atama[i] = en
            }
            for j in 0..<k {
                let uye = noktalar.indices.filter { atama[$0] == j }
                if !uye.isEmpty { merkez[j] = uye.map { noktalar[$0] }.reduce(SIMD3<Double>(), +) / Double(uye.count) }
            }
        }
        let sayim = (0..<k).map { j in (j, atama.filter { $0 == j }.count) }.sorted { $0.1 > $1.1 }
        let sec = sayim.prefix(4).map { merkez[$0.0] }
        let hex = sec.map { String(format: "#%02X%02X%02X", Int($0.x * 255), Int($0.y * 255), Int($0.z * 255)) }
        return hex.sorted { RenkHesap.parlaklik($0) < RenkHesap.parlaklik($1) }
    }
}

enum OzneAyir {
    /// Vision ile ön plandaki özneyi (insan, hayvan, nesne) saydam arka planlı PNG olarak kaydeder.
    static func ayir(foto: String) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            guard let d = try? Data(contentsOf: Depo.gorselURL(foto)),
                  let cg = Depo.kucult(veri: d, enUzun: 2796) else { return false }
            let istek = VNGenerateForegroundInstanceMaskRequest()
            let el = VNImageRequestHandler(cgImage: cg, orientation: .up)
            do {
                try el.perform([istek])
                guard let s = istek.results?.first else { return false }
                let tampon = try s.generateMaskedImage(ofInstances: s.allInstances, from: el, croppedToInstancesExtent: false)
                let ci = CIImage(cvPixelBuffer: tampon)
                guard let cikti = CIContext().createCGImage(ci, from: ci.extent) else { return false }
                Depo.pngKaydet(UIImage(cgImage: cikti), ad: Depo.ozneAdi(foto))
                return true
            } catch {
                return false
            }
        }.value
    }
}
