// BAĞ AVI — iki konu, tek yasa. Uzak bölgelerden iki konu seçilir; onları bağlayan dişliyi (yasayı) bulursun.
// Amaç ezber değil: "bu ikisi aslında aynı hareket" fark edişi.
import SwiftUI

struct BagTuru: Identifiable {
    let id = UUID()
    let a: Konu
    let b: Konu
    let yasa: Yasa
    let secenekler: [Yasa]
}

struct BagAviOyunu: View {
    @Environment(Depo.self) private var depo
    @Environment(\.dismiss) private var kapat
    @State private var turlar: [BagTuru] = []
    @State private var i = 0
    @State private var secilen: String?
    @State private var dogrular = 0
    @State private var bitti = false
    @State private var nabiz = false
    private let adet = 8
    private let renk = Oyun.bag.renk

    var body: some View {
        if bitti {
            OyunSonu(oyun: .bag, buyuk: "\(dogrular)/\(adet)", aciklama: "bağ buldun",
                     ders: "Altmış konu ezberlenecek altmış ayrı şey değil; on yasa farklı yerlerde aynı işi yapıyor.",
                     tekrar: { bitti = false; kur() }, kapat: { kapat() })
        } else {
            VStack(spacing: 12) {
                OyunUstu(baslik: "Bağ Avı", alt: "\(dogrular) bağ", renk: renk, ilerleme: Double(i) / Double(adet)) { kapat() }
                if let t = turlar[safe: i] {
                    ScrollView {
                        VStack(spacing: 14) {
                            Text("Bu iki konuyu hangi yasa bağlıyor?").font(.headline).foregroundStyle(renk)
                            konuKarti(t.a, t)
                            baglanti(t)
                            konuKarti(t.b, t)
                            if secilen == nil {
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                    ForEach(t.secenekler) { y in
                                        Button { sec(y, t) } label: { secenek(y) }.buttonStyle(BasinStil())
                                    }
                                }
                            } else {
                                aciklama(t)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                    .id(t.id)
                    .transition(.opacity)
                }
            }
            .background(Lekeler(renkler: [renk, Tema.renk("turkuaz"), Tema.renk("gul")]))
            .onAppear { if turlar.isEmpty { kur() } }
        }
    }

    private func konuKarti(_ k: Konu, _ t: BagTuru) -> some View {
        let r = depo.renk(k)
        return VStack(alignment: .leading, spacing: 8) {
            NoktaEtiket(metin: depo.bolge(k.bolge)?.ad ?? "", renk: depo.renk(k))
                .font(.caption2.weight(.bold)).foregroundStyle(r)
            Text(k.tr).font(Tema.baslik(.title3))
            if let o = k.ornek.first?.first { Text(o).font(Tema.ingilizce(.callout)).foregroundStyle(.secondary) }
            if secilen != nil, let not = k.yasalar.first(where: { $0.id == t.yasa.id })?.not {
                Text(not).font(.callout.weight(.medium)).foregroundStyle(Tema.renk(t.yasa.renk))
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kart(16)
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(r.opacity(0.35), lineWidth: 1))
    }

    private func baglanti(_ t: BagTuru) -> some View {
        let acik = secilen != nil
        let yr = Tema.renk(t.yasa.renk)
        return ZStack {
            Rectangle().fill(acik ? yr : Color.secondary.opacity(0.3)).frame(width: 3, height: 54)
            Circle().fill(acik ? yr : Tema.yuzey).frame(width: 52, height: 52)
                .overlay(Circle().stroke(acik ? yr : Color.secondary.opacity(0.3), lineWidth: 2))
                .scaleEffect(nabiz ? 1.08 : 1)
            if acik {
                Cizim(ad: t.yasa.id, renk: .white, boy: 40, zemin: false).transition(.scale.combined(with: .opacity))
            } else {
                Image(systemName: "questionmark").font(.title3.weight(.bold)).foregroundStyle(.secondary)
            }
        }
        .frame(height: 54)
        .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever()) { nabiz = true } }
    }

    private func secenek(_ y: Yasa) -> some View {
        let r = Tema.renk(y.renk)
        return VStack(spacing: 6) {
            Cizim(ad: y.id, renk: r, boy: 40)
            Text(y.ad).font(.footnote.weight(.semibold)).multilineTextAlignment(.center).lineLimit(2)
            Text(y.imge).font(.caption2).opacity(0.75)
        }
        .foregroundStyle(r)
        .frame(maxWidth: .infinity, minHeight: 104)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(r.opacity(0.12)))
    }

    private func aciklama(_ t: BagTuru) -> some View {
        let d = secilen.map { s in t.a.yasalar.contains { $0.id == s } && t.b.yasalar.contains { $0.id == s } } ?? false
        return VStack(alignment: .leading, spacing: 10) {
            Label(d ? "Bağ bulundu" : "Bağlayan: \(t.yasa.ad)", systemImage: d ? "link.circle.fill" : "link")
                .font(.headline).foregroundStyle(d ? Tema.dogru : Tema.renk("turuncu"))
            Text(t.yasa.ozet).font(.callout)
            Button {
                withAnimation(.snappy) {
                    if i + 1 >= turlar.count { bitti = true } else { i += 1; secilen = nil }
                }
            } label: {
                Text("Sonraki").font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 50)
                    .background(Capsule().fill(renk))
            }
            .buttonStyle(.plain)
        }
        .kart(16)
    }

    private func sec(_ y: Yasa, _ t: BagTuru) {
        let d = t.a.yasalar.contains { $0.id == y.id } && t.b.yasalar.contains { $0.id == y.id }
        if d { dogrular += 1; Dokunus.basari() } else { Dokunus.hata() }
        withAnimation(.spring) { secilen = y.id }
    }

    private func kur() {
        let havuz = Set(depo.oyunHavuzu(enAz: 10).map(\.id))
        var yeni: [BagTuru] = []
        var deneme = 0
        while yeni.count < adet && deneme < 200 {
            deneme += 1
            guard let y = depo.veri.yasalar.randomElement() else { break }
            let uyelar = y.konular.compactMap { depo.konu($0) }
            let tercih = uyelar.filter { havuz.contains($0.id) }
            let aday = tercih.count >= 2 ? tercih : uyelar
            guard let a = aday.randomElement() else { continue }
            // mümkünse başka bölgeden: uzak iki konu
            let digerleri = aday.filter { $0.id != a.id }
            guard let b = digerleri.filter({ $0.bolge != a.bolge }).randomElement() ?? digerleri.randomElement() else { continue }
            if yeni.contains(where: { Set([$0.a.id, $0.b.id]) == Set([a.id, b.id]) }) { continue }
            let ortak = Set(a.yasalar.map(\.id)).intersection(b.yasalar.map(\.id))
            let yanlislar = depo.veri.yasalar.filter { !ortak.contains($0.id) }.shuffled().prefix(3)
            yeni.append(BagTuru(a: a, b: b, yasa: y, secenekler: ([y] + yanlislar).shuffled()))
        }
        turlar = yeni; i = 0; secilen = nil; dogrular = 0
    }
}
