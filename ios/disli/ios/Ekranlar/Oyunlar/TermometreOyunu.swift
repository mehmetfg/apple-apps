// TERMOMETRE — "Her şey bir ölçekte" yasasının oyunu. Cümleyi oku, konuşan ne kadar emin? Cıvayı oraya çek.
import SwiftUI

struct TermometreOyunu: View {
    @Environment(Depo.self) private var depo
    @Environment(\.dismiss) private var kapat
    @State private var liste: [TermCumle] = []
    @State private var i = 0
    @State private var tahmin: Double = 50
    @State private var olculdu = false
    @State private var puan = 0
    @State private var isabet = 0
    @State private var sonTik = 5
    @State private var bitti = false
    private let adet = 10
    private let renk = Oyun.termometre.renk

    var body: some View {
        if bitti {
            OyunSonu(oyun: .termometre, buyuk: "\(isabet)/\(adet)", aciklama: "isabet · \(puan) puan",
                     ders: "Cetvel: will / be certain to (%100) · must / be bound to (%95) · should / likely (%75) · may / might / could (%40-50) · unlikely (%20) · can't (%0). Geçmiş için aynı cetvel + have + V3.",
                     tekrar: { bitti = false; kur() }, kapat: { kapat() })
        } else {
            VStack(spacing: 12) {
                OyunUstu(baslik: "Termometre", alt: "\(isabet) isabet", renk: renk, ilerleme: Double(i) / Double(adet)) { kapat() }
                if let t = liste[safe: i] {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Konuşan ne kadar emin?").font(.subheadline.weight(.semibold)).foregroundStyle(renk)
                            Text(vurgulu(t.s)).font(Tema.ingilizce(.title2)).fixedSize(horizontal: false, vertical: true)
                            Button { Ses.konus(t.s) } label: { Label("Dinle", systemImage: "speaker.wave.2.fill").font(.subheadline) }
                                .tint(renk)
                            Text("%\(Int(tahmin))").font(.system(size: 44, weight: .heavy, design: .rounded))
                                .foregroundStyle(renk).contentTransition(.numericText()).monospacedDigit()
                            if olculdu {
                                let fark = abs(Int(tahmin) - t.deger)
                                VStack(alignment: .leading, spacing: 6) {
                                    Label(fark <= 15 ? "İsabet" : "Gerçek değer %\(t.deger)", systemImage: fark <= 15 ? "scope" : "ruler")
                                        .font(.headline).foregroundStyle(fark <= 15 ? Tema.dogru : Tema.renk("turuncu"))
                                    Text(t.aciklama).font(.callout)
                                }
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            } else {
                                Text("Cıvayı parmağınla yukarı aşağı çek.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        termometre(t)
                    }
                    .padding(.horizontal)
                    Spacer(minLength: 0)
                    Button { olculdu ? sonraki() : olc(t) } label: {
                        Text(olculdu ? "Sonraki" : "Ölç").font(.headline).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 52).background(Capsule().fill(renk))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal).padding(.bottom, 12)
                }
            }
            .background(Lekeler(renkler: [renk, Tema.renk("mor"), Tema.renk("turuncu")]))
            .onAppear { if liste.isEmpty { kur() } }
        }
    }

    private func termometre(_ t: TermCumle) -> some View {
        let yuk: CGFloat = 400
        let etiketler: [(Int, String)] = [(100, "kesin"), (75, "büyük ihtimal"), (50, "belki"), (25, "zayıf"), (0, "imkânsız")]
        return HStack(alignment: .top, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                ForEach(etiketler, id: \.0) { d, ad in
                    Text(ad).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        .offset(y: yuk * (1 - CGFloat(d) / 100) - 7)
                }
            }
            .frame(width: 78, height: yuk, alignment: .topTrailing)
            ZStack(alignment: .bottom) {
                Capsule().fill(Color(.tertiarySystemFill)).frame(width: 34, height: yuk)
                Capsule()
                    .fill(LinearGradient(colors: [Tema.renk("mavi"), Tema.renk("mor"), renk], startPoint: .bottom, endPoint: .top))
                    .frame(width: 22, height: max(22, yuk * tahmin / 100))
                    .padding(.bottom, 6)
                if olculdu {
                    HStack(spacing: 2) {
                        Image(systemName: "arrowtriangle.right.fill").font(.caption)
                        Rectangle().frame(width: 34, height: 3)
                    }
                    .foregroundStyle(Tema.dogru)
                    .offset(x: -6, y: -yuk * CGFloat(t.deger) / 100 + 1.5)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 44, height: yuk)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                guard !olculdu else { return }
                let v = min(100, max(0, (1 - g.location.y / yuk) * 100))
                tahmin = v.rounded()
                let tik = Int(v / 10)
                if tik != sonTik { sonTik = tik; Dokunus.secim() }
            })
            .accessibilityElement()
            .accessibilityLabel("Kesinlik")
            .accessibilityValue("yüzde \(Int(tahmin))")
            .accessibilityAdjustableAction { y in tahmin = min(100, max(0, tahmin + (y == .increment ? 5 : -5))) }
        }
    }

    private func vurgulu(_ s: String) -> AttributedString {
        var a = AttributedString(s)
        let kelimeler = ["must have", "might have", "can't have", "must", "might not", "might", "may", "could", "can't", "couldn't", "should",
                         "ought to", "will probably", "will", "probably won't", "definitely won't", "bound to", "unlikely", "likely",
                         "certain to", "slight chance", "probably"]
        var kapli: [Range<AttributedString.Index>] = []
        for k in kelimeler {
            var ara = a.startIndex..<a.endIndex
            while let r = a[ara].range(of: k, options: .caseInsensitive) {
                if !kapli.contains(where: { $0.overlaps(r) }) {
                    a[r].foregroundColor = Tema.modal
                    a[r].font = Tema.ingilizce(.title2, .bold)
                    kapli.append(r)
                }
                ara = r.upperBound..<a.endIndex
            }
        }
        return a
    }

    private func kur() {
        liste = Array(depo.veri.termometre.shuffled().prefix(adet))
        i = 0; puan = 0; isabet = 0; tahmin = 50; olculdu = false
    }

    private func olc(_ t: TermCumle) {
        let fark = abs(Int(tahmin) - t.deger)
        puan += max(0, 100 - fark * 3)
        if fark <= 15 { isabet += 1; Dokunus.basari() } else { Dokunus.hata() }
        Ses.konus(t.s)
        withAnimation(.spring) { olculdu = true }
    }

    private func sonraki() {
        if i + 1 >= liste.count { bitti = true; return }
        withAnimation(.snappy) { i += 1; tahmin = 50; olculdu = false }
    }
}
