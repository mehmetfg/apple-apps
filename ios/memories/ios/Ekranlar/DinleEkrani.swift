// Dinle: tek ses dosyası, üç bölüm. Çalan cümle ekranda büyük durur (metin bölümünde cümle numarasıyla).
import SwiftUI

struct DinleEkrani: View {
    @EnvironmentObject var depo: Depo
    @EnvironmentObject var oynatici: Oynatici

    private var paket: Paket? { oynatici.paket ?? depo.guncel }

    var body: some View {
        NavigationStack {
            Group {
                if let p = paket {
                    icerik(p)
                } else {
                    BosDurum(simge: "headphones", baslik: "Dinlenecek paket yok", metin: "Paket telefona inince burada çalar.")
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Dinle")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func icerik(_ p: Paket) -> some View {
        let h = depo.hazirlik(p.gun)
        let sure = oynatici.paket?.gun == p.gun ? oynatici.sure : p.sure
        let zaman = oynatici.paket?.gun == p.gun ? oynatici.zaman : 0
        return VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 6) {
                        Text("Gün \(p.gun)").font(.caption.weight(.bold)).tracking(1.1).foregroundStyle(.secondary)
                        Text(p.ad).font(.system(.title, design: .serif).weight(.semibold))
                        HStack(spacing: 6) {
                            ForEach(0..<3) { i in
                                Image(systemName: i < h.dinleme ? "headphones.circle.fill" : "circle.dotted")
                                    .foregroundStyle(i < h.dinleme ? Tema.vurgu : Color.secondary.opacity(0.5))
                            }
                            Text(h.dinleme == 0 ? "henüz dinlenmedi" : "\(h.dinleme) kez dinlendi").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 10)

                    cumleKarti(p)

                    VStack(spacing: 10) {
                        ForEach(p.bolumler ?? []) { b in
                            Button { oynatici.yukle(p) ? oynatici.bolumeGit(b) : () } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: b.simge).font(.body.weight(.semibold)).foregroundStyle(Tema.bolumRengi(b.ad))
                                        .frame(width: 34, height: 34)
                                        .background(Circle().fill(Tema.bolumRengi(b.ad).opacity(0.14)))
                                    Text(b.etiket).font(.body.weight(oynatici.bolum == b ? .semibold : .regular)).foregroundStyle(.primary)
                                    Spacer()
                                    Text(Tarih.sure(b.bitis - b.baslangic)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    if oynatici.bolum == b && oynatici.caliyor {
                                        Image(systemName: "waveform").symbolEffect(.variableColor.iterative).foregroundStyle(Tema.bolumRengi(b.ad))
                                    }
                                }
                                .padding(.vertical, 6).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .kart()
                }
                .padding(.horizontal, 18).padding(.bottom, 20)
            }
            kontroller(p, zaman: zaman, sure: sure)
        }
        .alert("Ses", isPresented: Binding(get: { oynatici.hata != nil }, set: { if !$0 { oynatici.hata = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: { Text(oynatici.hata ?? "") }
    }

    /// Çalan satır: konuşan kişi + metin. Metin bölümünde cümle numarası ve Türkçesi (uzun bas).
    private func cumleKarti(_ p: Paket) -> some View {
        let s = oynatici.paket?.gun == p.gun ? oynatici.satir : nil
        let b = s?.bolum ?? "aciklama"
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Cip(metin: oynatici.bolum?.etiket ?? "Açıklama", renk: Tema.bolumRengi(b))
                if let i = s?.cumle { Cip(metin: "cümle \(i + 1)", renk: Tema.kehribarYazi, simge: "text.alignleft") }
                Spacer()
                if let k = s?.s { Text(k.capitalized).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
            }
            Text(s?.t ?? (p.ozet ?? "Dinlemeye başla. Çalan cümle burada görünür."))
                .font(Tema.ingilizce(.title2))
                .foregroundStyle(s == nil ? .secondary : .primary)
                .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
                .animation(.easeInOut(duration: 0.25), value: s?.t)
                .contentTransition(.opacity)
            if let i = s?.cumle, let tr = p.cumleler.first(where: { $0.i == i })?.tr {
                TurkceGoz(tr: tr)
            }
        }
        .kart(18)
    }

    private func kontroller(_ p: Paket, zaman: Double, sure: Double) -> some View {
        VStack(spacing: 14) {
            BolumCubugu(paket: p, zaman: zaman, sure: max(sure, 1)) { t in
                if oynatici.yukle(p) { oynatici.git(t) }
            }
            HStack {
                Text(Tarih.sure(zaman)).font(.caption.monospacedDigit())
                Spacer()
                Text("-" + Tarih.sure(max(0, sure - zaman))).font(.caption.monospacedDigit())
            }
            .foregroundStyle(.secondary)
            HStack(spacing: 0) {
                dugme("backward.end.alt", "Bir cümle geri") { if oynatici.yukle(p) { oynatici.oncekiCumle() } }
                dugme("gobackward.10", "10 sn geri") { if oynatici.yukle(p) { oynatici.atla(-10) } }
                Button {
                    if oynatici.paket?.gun == p.gun { oynatici.degistir() } else { oynatici.cal(p) }
                } label: {
                    Image(systemName: oynatici.caliyor && oynatici.paket?.gun == p.gun ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 66)).foregroundStyle(Tema.vurgu)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel(oynatici.caliyor ? "Duraklat" : "Çal")
                .dokun(depo, oynatici.caliyor)
                dugme("goforward.10", "10 sn ileri") { if oynatici.yukle(p) { oynatici.atla(10) } }
                dugme("repeat.1", "Cümleyi yinele") { oynatici.cumleyiYinele() }
            }
            HStack {
                Text("Hız").font(.caption).foregroundStyle(.secondary)
                Picker("Hız", selection: Binding(get: { depo.hiz }, set: { depo.hiz = $0; oynatici.hizDegisti() })) {
                    ForEach([0.8, 0.9, 1.0, 1.1, 1.2], id: \.self) { h in
                        Text(String(format: "%.1f×", h).replacingOccurrences(of: ".", with: ",")).tag(h)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 10)
        .background(.bar)
    }

    private func dugme(_ simge: String, _ ad: String, _ e: @escaping () -> Void) -> some View {
        Button(action: e) {
            Image(systemName: simge).font(.system(size: 22, weight: .medium)).frame(maxWidth: .infinity, minHeight: 44)
        }
        .foregroundStyle(.primary)
        .accessibilityLabel(ad)
    }
}

/// Türkçesi göz atma biçiminde: dokununca açılır, birkaç saniye sonra kendiliğinden kapanır.
struct TurkceGoz: View {
    var tr: String
    @State private var acik = false
    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { acik.toggle() }
        } label: {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: acik ? "eye.slash" : "eye").font(.caption)
                Text(acik ? tr : "Türkçesi").font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .onChange(of: tr) { _, _ in acik = false }
        .task(id: acik) {
            guard acik else { return }
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            withAnimation { acik = false }
        }
    }
}
