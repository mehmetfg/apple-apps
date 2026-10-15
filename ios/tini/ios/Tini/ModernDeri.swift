import SwiftUI

struct ModernDeri: View {
    @EnvironmentObject var calar: Calar
    @EnvironmentObject var ses: Ses
    @EnvironmentObject var gezinti: Gezinti

    var body: some View {
        ZStack {
            arkaPlan
            VStack(spacing: 16) {
                ustCubuk
                Spacer(minLength: 0)
                KapakGorunumu(parca: calar.simdiki, kose: 14)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 330)
                    .shadow(color: .black.opacity(0.45), radius: 24, y: 14)
                    .scaleEffect(calar.caliyorMu ? 1 : 0.92)
                    .animation(.spring(response: 0.45, dampingFraction: 0.7), value: calar.caliyorMu)
                    .onTapGesture { gezinti.sayfa = .kutuphane }
                bilgi
                SpektrumCubuklari(bant: 40, renkler: [.white.opacity(0.95), .white.opacity(0.55), .white.opacity(0.15)], tepeRengi: .white)
                    .frame(height: 38)
                IlerlemeCubugu()
                denetimler
                SesSurgusuModern()
                efektSeridi
                altCubuk
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 6)
            .foregroundStyle(.white)
        }
        .preferredColorScheme(.dark)
    }

    private var arkaPlan: some View {
        // Kapak, yerleşimi genişletmesin diye yalnız katman olarak (overlay) çizilir.
        Color.black
            .overlay {
                if let r = calar.simdiki?.kapakResmi {
                    Image(uiImage: r).resizable().scaledToFill().blur(radius: 60).opacity(0.65).scaleEffect(1.3)
                } else {
                    LinearGradient(colors: [Color(red: 0.18, green: 0.12, blue: 0.32), .black], startPoint: .top, endPoint: .bottom)
                }
            }
            .overlay(LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
            .clipped()
            .ignoresSafeArea()
    }

    private var ustCubuk: some View {
        HStack {
            Button { gezinti.sayfa = .ayarlar } label: { Image(systemName: "rectangle.stack").font(.title3) }
            Spacer()
            VStack(spacing: 1) {
                Text("TINI").font(.caption.weight(.heavy)).tracking(4)
                Text(calar.kip.ad + (calar.konusmaAlgilandi == true ? " · konuşma" : ""))
                    .font(.caption2).opacity(0.6)
            }
            Spacer()
            Button { calar.kip = calar.kip == .kitapla ? .yalniz : .kitapla } label: {
                Image(systemName: calar.kip == .kitapla ? "book.and.wrench" : "headphones").font(.title3)
            }
            .accessibilityLabel("Kip: \(calar.kip.ad)")
        }
        .padding(.top, 6)
    }

    private var bilgi: some View {
        VStack(spacing: 5) {
            Text(calar.simdiki?.baslik ?? "Kitaplıktan bir parça seç")
                .font(.title3.weight(.semibold)).lineLimit(1)
            Text(calar.simdiki.map { "\($0.sanatci) — \($0.album)" } ?? " ")
                .font(.subheadline).opacity(0.7).lineLimit(1)
            if let p = calar.simdiki {
                HStack(spacing: 6) {
                    BicimRozeti(bicim: p.bicim)
                    if p.yuksekCozunurluk { BicimRozeti(bicim: "Hi-Res") }
                    if ses.ayar.atla { BicimRozeti(bicim: "B · HAM") }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var denetimler: some View {
        HStack {
            Button { calar.karisik.toggle() } label: {
                Image(systemName: "shuffle").opacity(calar.karisik ? 1 : 0.4)
            }
            Spacer()
            Button { calar.onceki() } label: { Image(systemName: "backward.fill").font(.title) }
            Spacer()
            Button { calar.acKapa() } label: {
                Image(systemName: calar.caliyorMu ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 66)).symbolRenderingMode(.hierarchical)
                    .contentTransition(.symbolEffect(.replace))
            }
            Spacer()
            Button { calar.sonraki() } label: { Image(systemName: "forward.fill").font(.title) }
            Spacer()
            Button {
                calar.tekrar = calar.tekrar == .kapali ? .tum : (calar.tekrar == .tum ? .tek : .kapali)
            } label: {
                Image(systemName: calar.tekrar == .tek ? "repeat.1" : "repeat").opacity(calar.tekrar == .kapali ? 0.4 : 1)
            }
        }
        .font(.title3)
        .buttonStyle(.plain)
    }

    private var efektSeridi: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(Hazir.Grup.allCases, id: \.self) { g in
                        Section(g.rawValue) {
                            ForEach(Hazir.hepsi.filter { $0.grup == g }) { h in Button(h.ad) { ses.uygula(h) } }
                        }
                    }
                } label: { Cip(ad: ses.ad, simge: "slider.horizontal.3", acik: true) }
                Button { ses.abDegistir() } label: { Cip(ad: ses.ayar.atla ? "B" : "A", simge: "ear", acik: !ses.ayar.atla) }
                Button { ses.ayar.eqAcik.toggle() } label: { Cip(ad: "EQ", simge: "slider.vertical.3", acik: ses.ayar.eqAcik) }
                Button { ses.ayar.maximizer.toggle(); if ses.ayar.maximizer && ses.ayar.maxNetlik == 0 { ses.ayar.maxBas = 5; ses.ayar.maxNetlik = 5 } } label: {
                    Cip(ad: "BBE", simge: "sparkles", acik: ses.ayar.maximizer)
                }
                Button { ses.ayar.bas = ses.ayar.bas == .kapali ? .megaBass : .kapali } label: {
                    Cip(ad: ses.ayar.bas == .kapali ? "Mega Bass" : ses.ayar.bas.ad, simge: "speaker.wave.3", acik: ses.ayar.bas != .kapali)
                }
                Button { ses.ayar.tiz = ses.ayar.tiz > 0 ? 0 : 5 } label: { Cip(ad: "Tiz onarımı", simge: "waveform.path.ecg", acik: ses.ayar.tiz > 0) }
                Button { ses.ayar.surround = ses.ayar.surround > 0 ? 0 : 5 } label: { Cip(ad: "3D", simge: "cube.transparent", acik: ses.ayar.surround > 0) }
                Button { ses.ayar.crossfeed = ses.ayar.crossfeed > 0 ? 0 : 5 } label: { Cip(ad: "Crossfeed", simge: "headphones", acik: ses.ayar.crossfeed > 0) }
                Menu {
                    ForEach(YankiOda.allCases) { o in Button(o.ad) { ses.ayar.yanki = o } }
                } label: { Cip(ad: ses.ayar.yanki == .kapali ? "VPT" : ses.ayar.yanki.ad, simge: "building.columns", acik: ses.ayar.yanki != .kapali) }
                Button { ses.ayar.dengeleyici.toggle() } label: { Cip(ad: "Dengeleyici", simge: "waveform.badge.minus", acik: ses.ayar.dengeleyici) }
            }
            .buttonStyle(.plain)
        }
    }

    private var altCubuk: some View {
        HStack {
            AltDugme(ad: "Kitaplık", simge: "music.note.list") { gezinti.sayfa = .kutuphane }
            AltDugme(ad: "Ses Lab", simge: "dial.medium") { gezinti.sayfa = .sesLab }
            AltDugme(ad: "Ayarlar", simge: "gearshape") { gezinti.sayfa = .ayarlar }
        }
    }
}

private struct Cip: View {
    let ad: String, simge: String
    let acik: Bool
    var body: some View {
        Label(ad, systemImage: simge)
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(acik ? Color.white.opacity(0.9) : Color.white.opacity(0.12), in: Capsule())
            .foregroundStyle(acik ? Color.black : Color.white)
    }
}

private struct AltDugme: View {
    let ad: String, simge: String
    let eylem: () -> Void
    var body: some View {
        Button(action: eylem) {
            VStack(spacing: 3) {
                Image(systemName: simge).font(.title3)
                Text(ad).font(.caption2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .opacity(0.85)
    }
}

struct IlerlemeCubugu: View {
    @EnvironmentObject var calar: Calar
    var renk: Color = .white
    @State private var surukleniyor: Double?

    var body: some View {
        let sure = max(calar.sure, 0.01)
        let k = surukleniyor ?? calar.konum
        VStack(spacing: 4) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(renk.opacity(0.2)).frame(height: surukleniyor == nil ? 5 : 9)
                    Capsule().fill(renk).frame(width: g.size.width * CGFloat(min(1, k / sure)), height: surukleniyor == nil ? 5 : 9)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { d in surukleniyor = Double(min(max(0, d.location.x / g.size.width), 1)) * sure }
                    .onEnded { _ in if let s = surukleniyor { calar.atla(s) }; surukleniyor = nil })
                .animation(.easeOut(duration: 0.15), value: surukleniyor == nil)
            }
            .frame(height: 16)
            HStack {
                Text(sureYazi(k))
                Spacer()
                Text("-" + sureYazi(max(0, sure - k)))
            }
            .font(.caption2.monospacedDigit()).opacity(0.65)
        }
    }
}

private struct SesSurgusuModern: View {
    @EnvironmentObject var calar: Calar
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill").font(.caption)
            Slider(value: $calar.ses, in: 0...1).tint(.white)
            Image(systemName: "speaker.wave.3.fill").font(.caption)
            if calar.avls { Text("AVLS").font(.caption2.weight(.bold)) }
        }
        .opacity(0.85)
    }
}
