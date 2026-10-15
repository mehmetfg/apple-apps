// Kayıt: istem (fotoğraf, takvim, Kenar paragrafı) üstte, büyük düğme altta. 90 sn. Bitince telefon İngilizcesini hemen yazar.
import Photos
import SwiftUI

struct KayitEkrani: View {
    @EnvironmentObject var merkez: Merkez
    @Environment(\.dismiss) private var kapat
    let istek: KayitIstegi
    @StateObject private var kayitci = Kayitci()
    @State private var bitenId: String?
    @State private var onDokum: String?
    @State private var dokuluyor = false

    private var sinir: Double { istek.tur == .kapi ? 30 : 90 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Label(istek.tur.ad, systemImage: istek.tur.simge).font(.caption.weight(.bold)).foregroundStyle(Color.ayna)
                    Text(istek.istem).font(.title2.weight(.bold)).multilineTextAlignment(.center)
                    if let f = istek.foto, let a = PHAsset.fetchAssets(withLocalIdentifiers: [f], options: nil).firstObject {
                        Kucuk(asset: a).frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                    if let a = istek.aciklama {
                        Text(a).font(istek.tur == .metin ? .system(size: 16, design: .serif) : .callout)
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(istek.tur == .metin ? 14 : 0)
                            .background(istek.tur == .metin ? RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)) : nil)
                    }
                    if istek.tur == .metin {
                        Text("Türkçeyi oku, kapat, İngilizce anlat. Çeviri değil — aynı fikri kendi İngilizcenle kur.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    if bitenId == nil { dugme } else { sonuc }
                    if let h = kayitci.hata { Text(h).font(.footnote).foregroundStyle(.red) }
                }
                .padding(22)
            }
            .background(Color.black.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(bitenId == nil ? "Vazgeç" : "Kapat") { kayitci.bitir(); kapat() } } }
        }
        .interactiveDismissDisabled(kayitci.kayitta)
    }

    private var dugme: some View {
        Button {
            if kayitci.kayitta { kayitci.bitir(); return }
            let id = Kimlik.yeni()
            Task {
                await kayitci.baslat(id: id, sinir: sinir) { sure in
                    var k = Kayit(id: id, tarih: .now, tur: istek.tur, istem: istek.istem, sure: sure, kenarIs: istek.kenarIs, oncekiKayit: istek.onceki)
                    if istek.tur == .metin, let a = istek.aciklama { k.istem += " — " + String(a.prefix(80)) }
                    merkez.kayitEkle(k)
                    bitenId = id; dokuluyor = true
                    Haptik.basari()
                    Task {
                        let m = await Kayitci.dok(Depo.sesKlasoru.appendingPathComponent(id + ".m4a"))
                        dokuluyor = false; onDokum = m
                        if let m { merkez.onDokum(id, m) }
                    }
                }
            }
        } label: {
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 10).frame(width: 200, height: 200)
                Circle().trim(from: 0, to: kayitci.gecen / sinir).stroke(Color.ayna, style: StrokeStyle(lineWidth: 10, lineCap: .round)).rotationEffect(.degrees(-90)).frame(width: 200, height: 200)
                Circle().fill(kayitci.kayitta ? Color.ayna : Color.white.opacity(0.08)).frame(width: 160, height: 160)
                    .shadow(color: Color.ayna.opacity(0.5), radius: 10 + kayitci.seviye * 30)
                VStack(spacing: 4) {
                    Image(systemName: kayitci.kayitta ? "stop.fill" : "mic.fill").font(.system(size: 38, weight: .semibold))
                    Text(kayitci.kayitta ? "\(max(0, Int(sinir - kayitci.gecen)))" : "\(Int(sinir)) sn").font(.title3.weight(.semibold)).monospacedDigit()
                }
                .foregroundStyle(kayitci.kayitta ? .black : Color.ayna)
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .heavy), trigger: kayitci.kayitta)
    }

    private var sonuc: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Kaydedildi", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.headline)
            if dokuluyor { HStack { ProgressView(); Text("Telefon yazıya döküyor…").font(.footnote) } }
            if let o = onDokum {
                Text("Telefonun duyduğu").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                Text(o).font(.body).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
            } else if !dokuluyor {
                Text("Telefonda İngilizce döküm yok; Mac'te Whisper yazacak.").font(.footnote).foregroundStyle(.secondary)
            }
            Text("Gece Mac düzeltir. Sabah Dinle sekmesinde: kendi sesin → doğrusu → kendi hatalarından sorular.").font(.footnote).foregroundStyle(.secondary)
        }
    }
}
