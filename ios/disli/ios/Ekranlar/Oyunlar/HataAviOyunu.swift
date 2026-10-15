// HATA AVI — kart destesi. Sağa kaydır: doğru · sola kaydır: yanlış.
// Yanlış dediğin cümle gerçekten yanlışsa ikinci av başlar: hatalı kelimeye dokun.
import SwiftUI

struct AvKarti: Identifiable, Equatable {
    let id = UUID()
    let konu: Konu
    let cumle: String
    let dogrusu: String
    let yanlisMi: Bool
    let hataKelime: Set<Int>
}

struct HataAviOyunu: View {
    @Environment(Depo.self) private var depo
    @Environment(\.dismiss) private var kapat
    @State private var deste: [AvKarti] = []
    @State private var i = 0
    @State private var surukle: CGSize = .zero
    @State private var asama = 0          // 0 karar · 1 kelime avı · 2 sonuç
    @State private var dogruMu = false
    @State private var dokunulan: Int?
    @State private var puan = 0
    @State private var seri = 0
    @State private var bitti = false
    private let adet = 12

    var body: some View {
        if bitti {
            OyunSonu(oyun: .hata, buyuk: "\(puan)", aciklama: "puan · \(adet) cümle",
                     ders: "Hata avında göz önce anahtar kelimeye gider: yardımcı fiil, edat, biçim. Göz alıştıkça yazarken de aynı yere bakar.",
                     tekrar: { bitti = false; kur() }, kapat: { kapat() })
        } else {
            VStack(spacing: 16) {
                OyunUstu(baslik: "Hata Avı", alt: seri >= 2 ? "\(seri)× seri · \(puan) puan" : "\(puan) puan", renk: Oyun.hata.renk,
                         ilerleme: Double(i) / Double(adet)) { kapat() }
                Spacer(minLength: 0)
                if let k = deste[safe: i] {
                    kart(k)
                        .id(k.id)
                        .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .opacity))
                }
                Spacer(minLength: 0)
                altKisim
            }
            .background(Lekeler(renkler: [Oyun.hata.renk, Tema.renk("turuncu"), Tema.vurgu]))
            .onAppear { if deste.isEmpty { kur() } }
        }
    }

    private func kur() {
        var havuz: [AvKarti] = []
        for k in depo.oyunHavuzu(enAz: 8) {
            for s in k.sorular where s.tur == .hata {
                havuz.append(AvKarti(konu: k, cumle: s.yanlis ?? "", dogrusu: s.dogru ?? "", yanlisMi: true, hataKelime: Set(s.hataKelime ?? [])))
                havuz.append(AvKarti(konu: k, cumle: s.dogru ?? "", dogrusu: s.dogru ?? "", yanlisMi: false, hataKelime: []))
            }
        }
        // aynı cümlenin hem doğrusu hem yanlışı aynı destede olmasın
        var secilen: [AvKarti] = [], kullanilan = Set<String>()
        for a in havuz.shuffled() where secilen.count < adet {
            if kullanilan.insert(a.dogrusu).inserted { secilen.append(a) }
        }
        deste = secilen; i = 0; puan = 0; seri = 0; asama = 0; dokunulan = nil; surukle = .zero
    }

    // MARK: Kart

    private func kart(_ k: AvKarti) -> some View {
        let renk = depo.renk(k.konu)
        let kelimeler = k.cumle.split(separator: " ").map(String.init)
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                NoktaEtiket(metin: k.konu.tr, renk: depo.renk(k.konu))
                    .font(.caption.weight(.bold)).foregroundStyle(renk)
                Spacer()
                Button { Ses.konus(k.cumle) } label: { Image(systemName: "speaker.wave.2.fill").foregroundStyle(renk) }
            }
            if asama == 0 {
                Text(k.cumle).font(Tema.ingilizce(.title2, .medium)).fixedSize(horizontal: false, vertical: true)
            } else {
                Akis(aralik: 6, satirAraligi: 8) {
                    ForEach(Array(kelimeler.enumerated()), id: \.offset) { n, w in
                        Text(w).font(Tema.ingilizce(.title3, .medium))
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 9).fill(kelimeZemini(k, n)))
                            .onTapGesture { kelimeyeDokun(k, n) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if asama == 2 {
                VStack(alignment: .leading, spacing: 6) {
                    Label(dogruMu ? "Yakaladın" : "Kaçtı", systemImage: dogruMu ? "checkmark.seal.fill" : "arrow.uturn.backward.circle.fill")
                        .font(.headline).foregroundStyle(dogruMu ? Tema.dogru : Tema.renk("turuncu"))
                    if k.yanlisMi {
                        Text(k.dogrusu).font(Tema.ingilizce(.title3, .semibold))
                    } else {
                        Text("Bu cümle zaten doğruydu.").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Tema.yuzey))
        .overlay(alignment: .topLeading) { etiket("DOĞRU", Tema.dogru).opacity(Double(max(0, surukle.width / 120))) }
        .overlay(alignment: .topTrailing) { etiket("YANLIŞ", Tema.yanlis).opacity(Double(max(0, -surukle.width / 120))) }
        .shadow(color: .black.opacity(0.1), radius: 16, y: 8)
        .padding(.horizontal, 20)
        .offset(x: surukle.width, y: surukle.height * 0.2)
        .rotationEffect(.degrees(Double(surukle.width / 22)))
        .gesture(DragGesture()
            .onChanged { surukle = $0.translation }
            .onEnded { d in
                if d.translation.width > 110 { karar(k, yanlis: false) }
                else if d.translation.width < -110 { karar(k, yanlis: true) }
                else { withAnimation(.spring) { surukle = .zero } }
            }, including: asama == 0 ? .all : .subviews)
    }

    private func etiket(_ m: String, _ r: Color) -> some View {
        Text(m).font(.system(.title3, design: .rounded).weight(.black)).foregroundStyle(r)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(r, lineWidth: 3))
            .rotationEffect(.degrees(m == "DOĞRU" ? -12 : 12))
            .padding(28)
    }

    private func kelimeZemini(_ k: AvKarti, _ n: Int) -> Color {
        if asama == 2 && k.hataKelime.contains(n) { return Tema.yanlis.opacity(0.2) }
        if dokunulan == n { return dogruMu ? Tema.dogru.opacity(0.25) : Color(.tertiarySystemFill) }
        return Color(.tertiarySystemFill).opacity(asama == 1 ? 0.8 : 0.3)
    }

    @ViewBuilder
    private var altKisim: some View {
        if let k = deste[safe: i] {
            if asama == 0 {
                HStack(spacing: 40) {
                    Button { karar(k, yanlis: true) } label: { yuvarlak("xmark", Tema.yanlis) }
                    Button { karar(k, yanlis: false) } label: { yuvarlak("checkmark", Tema.dogru) }
                }
                .buttonStyle(BasinStil())
                .padding(.bottom, 24)
            } else if asama == 1 {
                Text("Hatalı kelimeye dokun").font(.headline).foregroundStyle(Oyun.hata.renk).padding(.bottom, 40)
            } else {
                Button { sonraki() } label: {
                    Text("Sonraki").font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 52)
                        .background(Capsule().fill(Oyun.hata.renk))
                }
                .buttonStyle(.plain).padding(.horizontal, 20).padding(.bottom, 20)
            }
        }
    }

    private func yuvarlak(_ s: String, _ r: Color) -> some View {
        Image(systemName: s).font(.title.weight(.bold)).foregroundStyle(.white)
            .frame(width: 72, height: 72).background(Circle().fill(r)).shadow(color: r.opacity(0.4), radius: 10, y: 5)
    }

    // MARK: Akış

    private func karar(_ k: AvKarti, yanlis: Bool) {
        withAnimation(.spring(response: 0.35)) { surukle = CGSize(width: yanlis ? -500 : 500, height: 0) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            surukle = .zero
            if yanlis == k.yanlisMi {
                if k.yanlisMi {
                    Dokunus.orta()
                    withAnimation { asama = 1 }   // ikinci av
                } else {
                    sonuc(k, true, puan: 10)
                }
            } else {
                sonuc(k, false, puan: 0)
            }
        }
    }

    private func kelimeyeDokun(_ k: AvKarti, _ n: Int) {
        guard asama == 1 else { return }
        dokunulan = n
        sonuc(k, k.hataKelime.contains(n), puan: 20)
    }

    private func sonuc(_ k: AvKarti, _ d: Bool, puan p: Int) {
        dogruMu = d
        if d { seri += 1; puan += p + (seri >= 3 ? 5 : 0); Dokunus.basari() } else { seri = 0; Dokunus.hata() }
        Ses.konus(k.dogrusu)
        withAnimation(.spring) { asama = 2 }
    }

    private func sonraki() {
        withAnimation(.snappy) {
            asama = 0; dokunulan = nil
            if i + 1 >= deste.count { bitti = true } else { i += 1 }
        }
    }
}
