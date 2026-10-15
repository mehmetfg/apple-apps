// Duvar kâğıdı: zemin + öğrenme katmanı (+ istenirse fotoğraftaki öznenin metnin önüne geçmesi).
// Ölçüler 430 pt genişliğe göre kurulur, her ekran boyuna oranla ölçeklenir.
import SwiftUI

struct DuvarGorunum: View {
    var duvar: Duvar
    var g: Gosterilen
    var tarih: Date = .now
    var faz: Double = 0
    var fotoBoyu: CGFloat = 2796

    var body: some View {
        GeometryReader { geo in
            let s = geo.size
            let u = s.width / 430
            ZStack {
                ZeminGorunum(zemin: duvar.zemin, faz: faz, fotoBoyu: fotoBoyu)
                if duvar.icerik != .yok {
                    IcerikKatmani(duvar: duvar, g: g, tarih: tarih, u: u)
                        .frame(width: s.width - 60 * u)
                        .position(x: s.width / 2, y: s.height * duvar.konum)
                }
                if duvar.derinlik, duvar.zemin.tur == .foto, let foto = duvar.zemin.foto,
                   let ozne = Depo.gorsel(Depo.ozneAdi(foto), enUzun: fotoBoyu) {
                    Image(uiImage: ozne)
                        .resizable()
                        .scaledToFill()
                        .frame(width: s.width, height: s.height)
                        .scaleEffect(1 + 0.08 * faz)
                        .clipped()
                        .allowsHitTesting(false)
                }
            }
            .frame(width: s.width, height: s.height)
            .clipped()
        }
    }
}

struct IcerikKatmani: View {
    var duvar: Duvar
    var g: Gosterilen
    var tarih: Date
    var u: CGFloat

    private var y: YaziStili { duvar.yazi }
    private var o: CGFloat { u * y.olcek }
    private var renk: Color { Color(hex: y.renk) }
    private var vurgu: Color { Color(hex: y.vurgu) }

    var body: some View {
        icerik
            .multilineTextAlignment(y.hiza.metin)
            .foregroundStyle(renk)
            .frame(maxWidth: .infinity, alignment: y.hiza.cerceve)
            .padding(.horizontal, duvar.kart == .yok ? 0 : 26 * u)
            .padding(.vertical, duvar.kart == .yok ? 0 : 24 * u)
            .background(kart)
            .shadow(color: .black.opacity(y.golge && duvar.kart != .duz ? 0.35 : 0), radius: 10 * u, y: 2 * u)
    }

    @ViewBuilder private var kart: some View {
        let sekil = RoundedRectangle(cornerRadius: 30 * u, style: .continuous)
        switch duvar.kart {
        case .yok: EmptyView()
        // ImageRenderer sistem malzemelerini (blur) çizemez; cam, zeminin rengiyle yarı saydam dolgu + ince kenar
        case .cam: sekil.fill(duvar.zemin.renk(0).opacity(0.38)).overlay(sekil.stroke(.white.opacity(0.22), lineWidth: 1 * u))
        case .duz: sekil.fill(duvar.zemin.renk(0).opacity(0.9))
        case .cizgi: sekil.stroke(renk.opacity(0.55), lineWidth: 1.5 * u)
        }
    }

    private func buyuk(_ s: String) -> String { y.buyukHarf ? s.uppercased(with: Locale(identifier: "tr")) : s }

    private var ustSatir: some View {
        Text(g.ust.uppercased(with: Locale(identifier: "tr")))
            .font(.system(size: 13 * o, weight: .semibold, design: .rounded))
            .tracking(2.4 * o)
            .foregroundStyle(vurgu)
    }

    @ViewBuilder private var icerik: some View {
        VStack(alignment: y.hiza.yatay, spacing: 10 * o) {
            switch duvar.icerik {
            case .kelime:
                ustSatir
                Text(buyuk(g.ana))
                    .font(y.aile.font(62 * o))
                    .lineLimit(1).minimumScaleFactor(0.4)
                if !g.ara.isEmpty {
                    Text(g.ara).font(.system(size: 19 * o, weight: .regular)).opacity(0.78)
                }
                Capsule().fill(vurgu).frame(width: 44 * o, height: 3 * o).padding(.vertical, 4 * o)
                Text(g.alt).font(y.aile.font(27 * o, ikincil: true))
                if !g.ornek.isEmpty {
                    Text(g.ornek).font(y.aile.font(17 * o, ikincil: true)).italic().opacity(0.8)
                        .lineLimit(3).padding(.top, 2 * o)
                }
            case .alinti:
                Text("“").font(.system(size: 70 * o, weight: .bold, design: .serif)).foregroundStyle(vurgu)
                    .frame(height: 34 * o, alignment: .top)
                Text(buyuk(g.ana))
                    .font(y.aile.font(g.ana.count > 120 ? 23 * o : 27 * o, ikincil: y.aile == .ince))
                    .lineSpacing(4 * o)
                    .minimumScaleFactor(0.6)
                if !g.alt.isEmpty {
                    Text("— " + g.alt).font(.system(size: 14 * o, weight: .medium)).opacity(0.75).lineLimit(1)
                }
            case .kavram:
                ustSatir
                Text(buyuk(g.ana)).font(y.aile.font(50 * o)).lineLimit(1).minimumScaleFactor(0.4)
                Capsule().fill(vurgu).frame(width: 44 * o, height: 3 * o).padding(.vertical, 2 * o)
                Text(g.alt).font(y.aile.font(21 * o, ikincil: true)).lineSpacing(3 * o)
                if !g.ornek.isEmpty {
                    Text(g.ornek).font(.system(size: 13 * o, weight: .medium)).opacity(0.7)
                }
            case .odak:
                Text(tarih.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "tr_TR"))).uppercased(with: Locale(identifier: "tr")))
                    .font(.system(size: 13 * o, weight: .semibold, design: .rounded)).tracking(2.4 * o).foregroundStyle(vurgu)
                Text(buyuk(g.ana)).font(y.aile.font(30 * o)).lineLimit(2).minimumScaleFactor(0.6)
                VStack(alignment: y.hiza.yatay, spacing: 6 * o) {
                    ForEach(g.satirlar, id: \.self) { s in
                        Text(s).font(.system(size: 15 * o, weight: .regular)).lineLimit(2).opacity(0.88)
                    }
                }
                if !g.alt.isEmpty {
                    Text(g.alt).font(.system(size: 13 * o, weight: .medium)).foregroundStyle(vurgu).padding(.top, 2 * o)
                }
            case .metin:
                Text(buyuk(g.ana)).font(y.aile.font(34 * o)).lineSpacing(4 * o).minimumScaleFactor(0.5)
            default:
                EmptyView()
            }
        }
    }
}
