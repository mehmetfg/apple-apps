// Sınama: simülatörde `-onizleme <klasör>` ile açılınca temaların duvarlarını, widget tasarımlarını her boyda
// ve bir hareketli zemin Live Photo'sunu dosyaya yazar, sonra çıkar. Ekran görüntüsü izni gerektirmez.
import SwiftUI
import WidgetKit
import Photos

@MainActor
enum Onizleme {
    static func calistirGerekirse(_ m: Merkez) {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-onizleme"), i + 1 < a.count else { return }
        let kok = URL(fileURLWithPath: a[i + 1])
        try? FileManager.default.createDirectory(at: kok, withIntermediateDirectories: true)
        Task {
            var rapor: [String] = []
            let boy = Cizer.ekran
            for t in Tema.hepsi {
                let d = t.duvar()
                if let img = Cizer.duvar(d, g: m.gosterilen(d), boy: boy, olcek: 1) {
                    yaz(img, kok.appendingPathComponent("duvar-\(dosya(t.ad)).png"))
                }
                for w in t.widgetlar() {
                    for aile in WidgetOlcu.ana + WidgetOlcu.kilit {
                        if let img = Cizer.widget(w, g: m.gosterilen(w), aile: aile, veri: m.veri, bilinen: m.bilinen, olcek: 2) {
                            yaz(img, kok.appendingPathComponent("widget-\(dosya(w.ad))-\(WidgetOlcu.ad(aile)).png"))
                        }
                    }
                }
            }
            if let (img, d) = Cizer.gununDuvari() {
                yaz(img, kok.appendingPathComponent("gunun-duvari.png"))
                rapor.append("günün duvarı: \(d.ad) \(Int(img.size.width * img.scale))×\(Int(img.size.height * img.scale))")
            }
            if a.contains("-canli"), let d = Tema.hepsi.first?.duvar() {
                do {
                    let (f, v) = try await CanliFoto.zeminden(d, g: m.gosterilen(d), sure: 2, fps: 12) { _ in }
                    try? FileManager.default.copyItem(at: f, to: kok.appendingPathComponent("canli.jpg"))
                    try? FileManager.default.copyItem(at: v, to: kok.appendingPathComponent("canli.mov"))
                    rapor.append("canlı: tamam")
                    if a.contains("-canliKaydet") {
                        let id = try await Fotograflar.canliKaydet(foto: f, video: v)
                        _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                        let son = PHAsset.fetchAssets(withLocalIdentifiers: [id ?? ""], options: nil).firstObject
                        let kaynaklar = son.map { PHAssetResource.assetResources(for: $0).map { "\($0.type.rawValue)" }.joined(separator: ",") } ?? "-"
                        rapor.append("öğe: \(id ?? "yok") · kaynak türleri: \(kaynaklar)")
                        rapor.append("Fotoğraflar'da Live Photo mu: \(son?.mediaSubtypes.contains(.photoLive) == true ? "EVET" : "HAYIR")")
                    }
                } catch { rapor.append("canlı HATA: \(error.localizedDescription)") }
            }
            rapor.append("kelime: \(m.veri.kelimeler.count) · bugün: \(Secici.kelime(m.veri, .now, bilinen: m.bilinen)?.w ?? "-")")
            try? rapor.joined(separator: "\n").write(to: kok.appendingPathComponent("rapor.txt"), atomically: true, encoding: .utf8)
            exit(0)
        }
    }

    private static func dosya(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            .replacingOccurrences(of: " · ", with: "-").replacingOccurrences(of: " ", with: "-")
    }

    private static func yaz(_ img: UIImage, _ u: URL) { try? img.pngData()?.write(to: u) }
}
