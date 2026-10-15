// Akış — süreçlerin birbirini nasıl beslediği. Üst sıra sabah görevleri (boru hatları), altında her alan bir şerit.
// Kenarın rengi hedefin durumudur; tıkalı borudan çıkan kenar kesik kırmızı akar. Bir düğüme dokun → ayrıntı.
import SwiftUI

struct HaritaEkrani: View {
    @EnvironmentObject var merkez: Merkez
    @State private var secili: String?

    struct Dugum: Identifiable {
        var id: String
        var ad: String
        var durum: Durum
        var renk: Color
        var nokta: CGPoint
        var boru: Bool
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let d = merkez.durum {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Bir süreç aksarsa beslediği her şey yavaşlar. Kırmızı kesik çizgi: tıkalı boru hattı.")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                        GeometryReader { g in
                            let dugumler = yerlesim(d, genislik: g.size.width)
                            ZStack(alignment: .topLeading) {
                                seritler(d, g.size.width)
                                TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
                                    let faz = tl.date.timeIntervalSinceReferenceDate * 18
                                    Canvas { c, _ in kenarlar(c, d, dugumler, faz: faz) }
                                }
                                ForEach(dugumler) { n in dugum(n) }
                            }
                        }
                        .frame(height: CGFloat(satirlar(merkez.durum!).count) * 118 + 10)
                        lejant
                        if let s = secili { secim(d, s) }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 30)
                }
            }
            .background(Tema.zemin)
            .navigationTitle("Akış")
            .navigationDestination(for: String.self) { SurecDetay(id: $0) }
        }
    }

    func satirlar(_ d: Durumlar) -> [(String, String, [String])] {
        var out: [(String, String, [String])] = [("boru", "Sabah görevleri", d.veri.borular.map(\.id))]
        for a in d.veri.alanlar {
            let ids = d.hukumler.filter { $0.surec.alan == a.id }.map(\.id)
            if !ids.isEmpty { out.append((a.id, a.ad, ids)) }
        }
        return out
    }

    func yerlesim(_ d: Durumlar, genislik: CGFloat) -> [Dugum] {
        var out: [Dugum] = []
        for (i, satir) in satirlar(d).enumerated() {
            let y = CGFloat(i) * 118 + 58
            let n = satir.2.count
            for (j, id) in satir.2.enumerated() {
                let x = genislik * (CGFloat(j) + 0.5) / CGFloat(max(1, n))
                // aynı şeritteki düğümler hafif zikzak — etiketler çakışmasın
                let yy = y + (n > 3 ? (j % 2 == 0 ? -9 : 9) : 0)
                if satir.0 == "boru", let b = d.veri.boru(id) {
                    let dr: Durum = b.durum == "tikali" ? .tikali : b.durum == "tamam" ? .akiyor : .uykuda
                    out.append(Dugum(id: id, ad: b.ad, durum: dr, renk: .gray, nokta: CGPoint(x: x, y: yy), boru: true))
                } else if let h = d.hukum(id) {
                    out.append(Dugum(id: id, ad: h.surec.ad, durum: h.durum, renk: Tema.alan(h.surec.alan),
                                     nokta: CGPoint(x: x, y: yy), boru: false))
                }
            }
        }
        return out
    }

    func seritler(_ d: Durumlar, _ w: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(satirlar(d).enumerated()), id: \.offset) { i, s in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(s.0 == "boru" ? Color.primary.opacity(0.04) : Tema.alan(s.0).opacity(0.06))
                        .padding(.vertical, 3)
                    Label(s.1, systemImage: s.0 == "boru" ? "gearshape.2" : Tema.alanSimge(s.0))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(s.0 == "boru" ? Color.secondary : Tema.alan(s.0))
                        .padding(.leading, 10).padding(.top, 8)
                }
                .frame(height: 118)
            }
        }
        .frame(width: w)
    }

    func kenarlar(_ c: GraphicsContext, _ d: Durumlar, _ n: [Dugum], faz: Double) {
        let konum = Dictionary(uniqueKeysWithValues: n.map { ($0.id, $0) })
        for k in d.veri.kenarlar {
            guard let a = konum[k.a], let b = konum[k.b] else { continue }
            var p = Path()
            p.move(to: a.nokta)
            if abs(a.nokta.y - b.nokta.y) < 30 {
                let ust = min(a.nokta.y, b.nokta.y) - 46
                p.addCurve(to: b.nokta, control1: CGPoint(x: a.nokta.x, y: ust), control2: CGPoint(x: b.nokta.x, y: ust))
            } else {
                let orta = (a.nokta.y + b.nokta.y) / 2
                p.addCurve(to: b.nokta, control1: CGPoint(x: a.nokta.x, y: orta), control2: CGPoint(x: b.nokta.x, y: orta))
            }
            let tikali = a.durum == .tikali && a.boru
            let renk = tikali ? Tema.durum(.tikali) : Tema.durum(b.durum)
            let akiyor = b.durum == .akiyor || tikali
            c.stroke(p, with: .color(renk.opacity(0.22)), lineWidth: 5)
            c.stroke(p, with: .color(renk.opacity(akiyor ? 0.95 : 0.6)),
                     style: StrokeStyle(lineWidth: 1.8, lineCap: .round, dash: tikali ? [4, 5] : [7, 9],
                                        dashPhase: akiyor ? -faz : 0))
        }
    }

    func dugum(_ n: Dugum) -> some View {
        Button { withAnimation(.snappy) { secili = n.id } } label: {
            VStack(spacing: 3) {
                ZStack {
                    Circle().fill(Tema.kart)
                    Circle().fill(n.boru ? Color.gray.opacity(0.18) : n.renk.opacity(0.22))
                    Circle().stroke(Tema.durum(n.durum), style: StrokeStyle(lineWidth: secili == n.id ? 4 : 2.5,
                                                                          dash: n.durum == .gorunmuyor ? [3, 3] : []))
                    Image(systemName: n.boru ? "gearshape.fill" : Tema.durumSimge(n.durum))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(n.boru ? Tema.durum(n.durum) : n.renk)
                }
                .frame(width: 34, height: 34)
                Text(n.ad).font(.system(size: 9, weight: .semibold)).lineLimit(2).multilineTextAlignment(.center)
                    .frame(width: 70)
            }
        }
        .buttonStyle(.plain)
        .position(x: n.nokta.x, y: n.nokta.y + 14)
    }

    var lejant: some View {
        let durumlar: [Durum] = [.akiyor, .gecikti, .aksiyor, .tikali, .uykuda, .gorunmuyor]
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))], alignment: .leading, spacing: 6) {
            ForEach(durumlar, id: \.self) { s in
                HStack(spacing: 5) { DurumNoktasi(durum: s, boy: 9); Text(s.ad).font(.system(size: 11)) }
            }
        }
        .padding(12)
        .background(Tema.kart, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    func secim(_ d: Durumlar, _ id: String) -> some View {
        if let h = d.hukum(id) {
            NavigationLink(value: id) {
                SurecSatiri(h: h).padding(14).background(Tema.kart, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        } else if let b = d.veri.boru(id) {
            VStack(alignment: .leading, spacing: 4) {
                Text(b.ad).font(.system(size: 15, weight: .semibold))
                Text("\(b.saat) · \(b.durum)").font(.system(size: 12)).foregroundStyle(.secondary)
                Text(b.not).font(.system(size: 12))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14).background(Tema.kart, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}
