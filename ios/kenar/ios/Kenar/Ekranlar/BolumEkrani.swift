// Bölüm: iddia · kanıtlar · ham notların (kopyalanmaz, yanında durur) · yazı. Yazmadan önce 60 sn anlatmak önerilir.
import SwiftUI

struct BolumEkrani: View {
    @EnvironmentObject var merkez: Merkez
    @EnvironmentObject var rota: Rota
    @Environment(\.openURL) private var ac
    let bolumId: String

    @State private var paragraf = ""
    @State private var iddia = ""
    @State private var hamAcik = false
    @State private var yuklendi = false
    @FocusState private var yaziyor: Bool

    private var b: Bolum? { merkez.d.metin?.bolumler.first { $0.id == bolumId } }

    var body: some View {
        ScrollView {
            if let b {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 10) {
                        BolumRozeti(no: b.no, boy: 34, dolu: b.bitti)
                        Text(b.baslik).font(.serif(26, .semibold)).foregroundStyle(Color.murekkep)
                    }
                    iddiaKutusu(b)
                    kanitlar(b)
                    hamNotlar(b)
                    yazi(b)
                    eylemler(b)
                    if let e = b.ingilizce { ingilizce(e) }
                }
                .padding(18)
            }
        }
        .kagitZemin()
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Text("\(paragraf.kelimeSayisi)/\(b?.hedef ?? 300)").font(.caption.monospacedDigit()).foregroundStyle(Color.soluk)
                Spacer()
                Button("Bitti") { yaziyor = false }
            }
        }
        .onAppear {
            guard !yuklendi, let b else { return }
            paragraf = b.paragraf; iddia = b.iddia; yuklendi = true
        }
        .task(id: paragraf + "§" + iddia) {
            guard yuklendi, var x = b, x.paragraf != paragraf || x.iddia != iddia else { return }
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            x.paragraf = paragraf; x.iddia = iddia
            merkez.bolumGuncelle(x)
        }
    }

    private func iddiaKutusu(_ b: Bolum) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("İDDİA").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Color.bolum(b.no))
            TextField("Bu bölüm tek cümleyle ne söylüyor?", text: $iddia, axis: .vertical)
                .font(.serif(18).italic()).foregroundStyle(Color.murekkep)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.bolum(b.no).opacity(0.08)))
    }

    private func kanitlar(_ b: Bolum) -> some View {
        let k = merkez.d.kanitlar(b.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Kanıtlar").font(.headline)
                Text("\(k.count)").font(.headline).foregroundStyle(Color.soluk)
                Spacer()
                if k.count >= 2 {
                    Button { rota.git("kenar://harita/\(b.id)") } label: { Label("Haritada", systemImage: "point.3.connected.trianglepath.dotted").font(.footnote.weight(.semibold)) }
                }
            }
            if k.isEmpty {
                Text("Kutu'dan buraya sürükle ya da okurken kamerayla işaretle. Bir bölüm en az iki kanıtla kurulur: biri iddiayı taşır, biri ona karşı çıkar.")
                    .font(.footnote).foregroundStyle(Color.soluk)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.cizgi, style: StrokeStyle(lineWidth: 1, dash: [5])))
            }
            ForEach(k) { x in
                IsaretKarti(x: x, satir: 5).contextMenu { IsaretMenusu(x: x) }
            }
        }
    }

    private func hamNotlar(_ b: Bolum) -> some View {
        Group {
            if !b.ham.isEmpty {
                DisclosureGroup(isExpanded: $hamAcik) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Temmuz'da sesle yazdırdığın notlar. Buradan kopyalanmaz: bak, kapat, kendi cümlenle yeniden kur.")
                            .font(.caption).foregroundStyle(Color.soluk)
                        ForEach(Array(b.ham.enumerated()), id: \.offset) { _, h in
                            Text(h).font(.serif(14)).foregroundStyle(Color.murekkep.opacity(0.8))
                                .padding(.leading, 10)
                                .overlay(alignment: .leading) { Rectangle().fill(Color.cizgi).frame(width: 2) }
                                .textSelection(.disabled)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Label("Ham notların · \(b.ham.joined(separator: " ").kelimeSayisi) kelime", systemImage: "waveform.and.mic").font(.subheadline.weight(.semibold))
                }
                .tint(Color.murekkep)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.kart))
            }
        }
    }

    private func yazi(_ b: Bolum) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Yaz").font(.headline)
                Spacer()
                Text("\(paragraf.kelimeSayisi) / \(b.hedef) kelime").font(.footnote.monospacedDigit())
                    .foregroundStyle(paragraf.kelimeSayisi >= b.hedef ? Color.bolum(b.no) : Color.soluk)
            }
            ZStack(alignment: .topLeading) {
                if paragraf.isEmpty {
                    Text("İddiayla başla. Sonra kanıtı kendi cümlenle anlat; alıntı en çok bir kez.")
                        .font(.serif(17)).foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 5)
                }
                TextEditor(text: $paragraf)
                    .font(.serif(17))
                    .lineSpacing(4)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 240)
                    .focused($yaziyor)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.kart))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(yaziyor ? Color.bolum(b.no) : Color.cizgi, lineWidth: yaziyor ? 1.4 : 0.6))
        }
    }

    private func eylemler(_ b: Bolum) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button { rota.git("kenar://anlat/\(b.id)") } label: {
                    Label("60 sn anlat", systemImage: "mic.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.large)
                Button { merkez.bolumBitti(b.id, !b.bitti) } label: {
                    Label(b.bitti ? "Bitti ✓" : "Bitti olarak işaretle", systemImage: b.bitti ? "checkmark.seal.fill" : "checkmark.seal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Color.bolum(b.no)).controlSize(.large)
                .disabled(!b.bitti && paragraf.kelimeSayisi < 40)
            }
            if b.bitti, b.ingilizce == nil {
                let aynaVar = UIApplication.shared.canOpenURL(URL(string: "ayna://")!)
                Button {
                    if let u = URL(string: "ayna://anlat?is=\(merkez.d.metin?.id ?? "")-\(b.id)") { ac(u) }
                } label: {
                    Label(aynaVar ? "Ayna'da İngilizce anlat" : "Ayna kurulunca bu bölüm onun kuyruğunda", systemImage: "globe")
                        .font(.footnote.weight(.semibold)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).disabled(!aynaVar)
            }
        }
    }

    private func ingilizce(_ e: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("English · Ayna'dan", systemImage: "globe").font(.caption.weight(.bold)).foregroundStyle(.blue)
            Text(e).font(.serif(16)).foregroundStyle(Color.murekkep)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.blue.opacity(0.07)))
    }
}
