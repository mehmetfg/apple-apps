// Paylaş › Kenar: Kitaplar, Kindle, Safari ya da herhangi bir uygulamadan seçilen cümle Kenar'ın Kutu'suna düşer.
// Uzantı yalnız ortak dolaba bırakır; uygulama öne gelince alır. Ağ yok, başka yere gitmez.
import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class PaylasDenetleyici: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        Task { @MainActor in
            let (metin, adres) = await oku()
            let v = UIHostingController(rootView: PaylasGorunumu(metin: metin, adres: adres, kaynak: kaynakAdi(adres)) { [weak self] son in
                if let son { Depo.gelenBirak(Depo.Gelen(metin: son, adres: adres, kaynakUygulama: self?.kaynakAdi(adres), tarih: .now)) }
                self?.extensionContext?.completeRequest(returningItems: nil)
            })
            addChild(v); view.addSubview(v.view); v.view.frame = view.bounds
            v.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            v.didMove(toParent: self)
        }
    }

    private func kaynakAdi(_ adres: String?) -> String? {
        guard let h = adres.flatMap({ URL(string: $0)?.host() }) else { return nil }
        if h.contains("amazon") || h.contains("kindle") { return "Kindle" }
        if h.contains("books.apple") { return "Kitaplar" }
        return h.replacingOccurrences(of: "www.", with: "")
    }

    private func oku() async -> (String, String?) {
        var metin = "", adres: String?
        for oge in (extensionContext?.inputItems as? [NSExtensionItem]) ?? [] {
            if metin.isEmpty, let a = oge.attributedContentText?.string, !a.isEmpty { metin = a }
            for e in oge.attachments ?? [] {
                if metin.isEmpty, e.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let s = try? await e.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String { metin = s }
                if adres == nil, e.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let u = try? await e.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL { adres = u.absoluteString }
            }
        }
        // Kindle ve Kitaplar alıntının sonuna kaynak satırı ve bağlantı ekler; bağlantıyı metinden ayır
        if let a = adres { metin = metin.replacingOccurrences(of: a, with: "") }
        return (metin.trimmingCharacters(in: .whitespacesAndNewlines), adres)
    }
}

struct PaylasGorunumu: View {
    @State var metin: String
    let adres: String?
    let kaynak: String?
    let bitir: (String?) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(kaynak.map { "Kaynak: \($0)" } ?? "Kenar kutusuna").font(.caption.weight(.semibold)).foregroundStyle(Color.soluk)
                TextEditor(text: $metin)
                    .font(.serif(17))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.kart))
                Text("Kutu'ya düşer. Hangi bölüme gideceğine sonra karar verirsin.").font(.footnote).foregroundStyle(Color.soluk)
            }
            .padding()
            .background(Color.kagit)
            .navigationTitle("Kenar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { bitir(nil) } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ekle") { bitir(metin) }.disabled(metin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .tint(.kalem)
    }
}
