// KULE — kelime taşlarını diz; her doğru cümle kuleye bir kat ekler (katın rengi konunun bölgesi).
// Soru sırası, devrik yapı, zarf yeri, kelime sırası: "anahtar nereye gider?" sorusunun oyunu.
import SwiftUI

struct KuleOyunu: View {
    @Environment(Depo.self) private var depo
    @Environment(\.dismiss) private var kapat
    @State private var liste: [(Konu, Soru)] = []
    @State private var i = 0
    @State private var dizi: [Tas] = []
    @State private var banka: [Tas] = []
    @State private var sonuc: Bool?
    @State private var katlar: [Color] = []
    @State private var ipucuSayisi = 0
    @State private var bitti = false
    private let adet = 8

    var body: some View {
        if bitti {
            OyunSonu(oyun: .kule, buyuk: "\(katlar.count) kat", aciklama: "\(adet) cümleden \(katlar.count) tanesi ilk denemede oturdu",
                     ders: "İngilizce cümle bir trendir: özne, hemen arkasında fiil, sonra nesne; yer ve zaman en sonda. Soruda anahtar (yardımcı fiil) öne geçer.",
                     tekrar: { bitti = false; kur() }, kapat: { kapat() })
        } else {
            VStack(spacing: 14) {
                OyunUstu(baslik: "Kule", alt: "\(katlar.count) kat", renk: Oyun.kule.renk, ilerleme: Double(i) / Double(adet)) { kapat() }
                kule
                if let ks = liste[safe: i] {
                    let k = ks.0, s = ks.1
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            NoktaEtiket(metin: k.tr, renk: depo.renk(k))
                                .font(.caption.weight(.bold)).foregroundStyle(depo.renk(k))
                            if s.tur == .donustur, let kay = s.kaynak {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(s.talimat ?? "").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    Text(kay).font(Tema.ingilizce(.body)).foregroundStyle(.secondary)
                                }
                            }
                            TasTezgahi(dizi: $dizi, banka: $banka, renk: depo.renk(k), kilitli: sonuc != nil)
                            if let sonuc {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label(sonuc ? "Kat çıktı!" : "Doğru dizilim", systemImage: sonuc ? "building.columns.fill" : "arrow.triangle.2.circlepath")
                                        .font(.headline).foregroundStyle(sonuc ? Tema.dogru : Tema.renk("turuncu"))
                                    Text(dogruCumle(s)).font(Tema.ingilizce(.title3, .semibold))
                                    Button { sonraki() } label: {
                                        Text("Sonraki").font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 50)
                                            .background(Capsule().fill(Oyun.kule.renk))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .kart(16)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            } else {
                                HStack {
                                    Button("İpucu: ilk taş") { ipucu(s) }.disabled(!dizi.isEmpty)
                                    Spacer()
                                    Button("Temizle") { withAnimation { banka += dizi; dizi = [] } }.disabled(dizi.isEmpty)
                                }
                                .font(.subheadline)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .onChange(of: dizi) { _, d in if sonuc == nil, d.count == (s.tas?.count ?? 0) { denetle(s, k) } }
                }
            }
            .background(Lekeler(renkler: [Oyun.kule.renk, Tema.vurgu, Tema.renk("sari")]))
            .onAppear { if liste.isEmpty { kur() } }
        }
    }

    private var kule: some View {
        VStack(spacing: 3) {
            ForEach(Array(katlar.enumerated().reversed()), id: \.offset) { n, r in
                RoundedRectangle(cornerRadius: 4).fill(r)
                    .frame(width: 150 - CGFloat(n) * 8, height: 11)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Capsule().fill(Color.secondary.opacity(0.35)).frame(width: 190, height: 4)
        }
        .frame(height: 8 * 14 + 4, alignment: .bottom)
        .animation(.spring(response: 0.5, dampingFraction: 0.6), value: katlar.count)
    }

    private func kur() {
        var l: [(Konu, Soru)] = []
        for k in depo.oyunHavuzu() {
            for s in k.sorular where s.tur == .sirala || (s.tur == .donustur && (s.tas?.count ?? 0) <= 10) { l.append((k, s)) }
        }
        liste = Array(l.shuffled().prefix(adet)); i = 0; katlar = []
        hazirla()
    }

    private func hazirla() {
        guard let s = liste[safe: i]?.1 else { return }
        let taslar = (s.tas ?? []) + (s.tur == .donustur ? Array((s.fazla ?? []).prefix(2)) : [])
        var k = taslar.map { Tas(metin: $0) }.shuffled()
        if k.map(\.metin) == (s.tas ?? []) && k.count > 1 { k.swapAt(0, k.count - 1) }
        banka = k; dizi = []; sonuc = nil
    }

    private func ipucu(_ s: Soru) {
        guard let ilk = s.tas?.first, let t = banka.first(where: { $0.metin == ilk }) else { return }
        ipucuSayisi += 1
        withAnimation { banka.removeAll { $0.id == t.id }; dizi.append(t) }
    }

    private func denetle(_ s: Soru, _ k: Konu) {
        let kurulan = dizi.map(\.metin).joined(separator: " ")
        let d = (s.cevaplar ?? []).contains { Metin.esit($0, kurulan) }
        if d { Dokunus.basari(); withAnimation { katlar.append(depo.renk(k)) } } else { Dokunus.hata() }
        Ses.konus(dogruCumle(s))
        withAnimation(.spring) { sonuc = d }
    }

    private func dogruCumle(_ s: Soru) -> String {
        guard let c = s.cevaplar?.first else { return "" }
        let x = c.prefix(1).uppercased() + c.dropFirst()
        return x.last.map { ".?!".contains($0) } == true ? x : x + (s.son ?? "")
    }

    private func sonraki() {
        if i + 1 >= liste.count { bitti = true; return }
        withAnimation(.snappy) { i += 1; hazirla() }
    }
}
