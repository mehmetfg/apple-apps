import SwiftUI

/// Kasetli Walkman WM-GX serisinin (GX655 / GX688 dönemi) yüzü: fırçalanmış gümüş gövde, kaset penceresinde
/// gerçek ilerlemeye göre dolan/boşalan makaralar, yeşil LCD (dokununca turuncu arka ışık), Mega Bass anahtarı,
/// AVLS, ses tekerleği. Düğmeler gerçek gibi basılır ve titreşir.
struct WalkmanDeri: View {
    @EnvironmentObject var calar: Calar
    @EnvironmentObject var ses: Ses
    @EnvironmentObject var gezinti: Gezinti
    @AppStorage("walkmanIsik") private var isik = false
    @State private var tik = 0

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.16), Color(white: 0.05)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            GeometryReader { g in
                let w = min(g.size.width - 24, 420)
                VStack(spacing: 0) {
                    govde(w)
                    ustDugmeler.padding(.top, 14)
                }
                .frame(width: w)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.impact(weight: .medium), trigger: tik)
    }

    private func govde(_ w: CGFloat) -> some View {
        VStack(spacing: 12) {
            // Üst yazılar
            HStack(alignment: .firstTextBaseline) {
                Text("WALKMAN").font(.system(size: 26, weight: .black).italic()).tracking(-0.5)
                    .foregroundStyle(Color(white: 0.12))
                Text("WM-GX688").font(.system(size: 10, weight: .bold)).foregroundStyle(Color(white: 0.25))
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("MEGA BASS").font(.system(size: 10, weight: .heavy).italic()).foregroundStyle(Color(red: 0.75, green: 0.1, blue: 0.1))
                    Text("RADIO CASSETTE CORDER").font(.system(size: 7, weight: .semibold)).foregroundStyle(Color(white: 0.3))
                }
            }
            lcd
            KasetPenceresi()
                .frame(height: w * 0.52)
            HStack(alignment: .center, spacing: 14) {
                MegaBassAnahtari()
                Spacer()
                AVLSAnahtari()
                Spacer()
                SesTekerlegi(deger: $calar.ses)
            }
            HStack {
                Text("AUTO REVERSE").font(.system(size: 8, weight: .bold))
                Spacer()
                Text("DOLBY B NR").font(.system(size: 8, weight: .bold))
                Spacer()
                Text("DIGITAL TUNER").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(Color(white: 0.3))
        }
        .padding(18)
        .background(FircaliMetal().clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous)))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(LinearGradient(colors: [.white.opacity(0.9), .black.opacity(0.4)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.7), radius: 20, y: 12)
    }

    // MARK: LCD

    private var lcd: some View {
        let yazi = isik ? Color(red: 0.22, green: 0.10, blue: 0.0) : Color(red: 0.10, green: 0.14, blue: 0.08)
        return Button { isik.toggle(); tik += 1 } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    LCDIsaret("TAPE", true)
                    LCDIsaret(calar.caliyorMu ? "▶" : "■", true)
                    LCDIsaret("MEGA BASS", ses.ayar.bas == .megaBass)
                    LCDIsaret("GROOVE", ses.ayar.bas == .groove)
                    LCDIsaret("AVLS", calar.avls)
                    Spacer()
                    LCDIsaret("SHUF", calar.karisik)
                    LCDIsaret(calar.tekrar == .tek ? "REP 1" : "REP", calar.tekrar != .kapali)
                }
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                HStack(alignment: .lastTextBaseline) {
                    Text(String(format: "%02d", calar.sira + 1)).font(.system(size: 30, weight: .bold, design: .monospaced))
                    Text("TR").font(.system(size: 10, weight: .bold, design: .monospaced))
                    Spacer()
                    Text(sureYazi(calar.konum)).font(.system(size: 30, weight: .bold, design: .monospaced))
                }
                Text((calar.simdiki.map { "\($0.sanatci) · \($0.baslik)" } ?? "NO TAPE").uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .monospaced)).lineLimit(1)
                TepeGostergesi(renk: yazi).frame(height: 9).opacity(0.85)
            }
            .foregroundStyle(yazi)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(
                LinearGradient(colors: isik ? [Color(red: 1.0, green: 0.68, blue: 0.25), Color(red: 0.93, green: 0.55, blue: 0.15)]
                                            : [Color(red: 0.64, green: 0.69, blue: 0.56), Color(red: 0.55, green: 0.60, blue: 0.48)],
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.6), lineWidth: 3))
            .shadow(color: isik ? .orange.opacity(0.6) : .clear, radius: 10)
        }
        .buttonStyle(.plain)
    }

    // MARK: Düğmeler

    private var ustDugmeler: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                MetalDugme(simge: "backward.end.fill", yazi: "REW") { tik += 1; calar.onceki() }
                MetalDugme(simge: "stop.fill", yazi: "STOP") { tik += 1; calar.durdur() }
                MetalDugme(simge: calar.caliyorMu ? "pause.fill" : "play.fill", yazi: "PLAY", vurgu: true) { tik += 1; calar.acKapa() }
                MetalDugme(simge: "forward.end.fill", yazi: "FF") { tik += 1; calar.sonraki() }
            }
            HStack(spacing: 10) {
                KucukDugme(yazi: "DIR") { tik += 1; calar.karisik.toggle() }
                KucukDugme(yazi: "MODE") { tik += 1; calar.tekrar = calar.tekrar == .kapali ? .tum : (calar.tekrar == .tum ? .tek : .kapali) }
                KucukDugme(yazi: "TAPES") { gezinti.sayfa = .kutuphane }
                KucukDugme(yazi: "SOUND") { gezinti.sayfa = .sesLab }
                KucukDugme(yazi: "SET") { gezinti.sayfa = .ayarlar }
            }
        }
    }
}

private struct LCDIsaret: View {
    let yazi: String, acik: Bool
    init(_ y: String, _ a: Bool) { yazi = y; acik = a }
    var body: some View { Text(yazi).opacity(acik ? 1 : 0.12) }
}

// MARK: - Kaset

private struct KasetPenceresi: View {
    @EnvironmentObject var calar: Calar
    private final class Aci { var deger: Double = 0; var son: Date? }
    @State private var aci = Aci()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !calar.caliyorMu)) { zaman in
            let ilerleme = calar.sure > 0 ? min(1, calar.konum / calar.sure) : 0
            let a = aciHesapla(zaman.date)
            GeometryReader { g in
                let w = g.size.width, h = g.size.height
                let rMin = h * 0.12, rMax = h * 0.25
                let sol = rMin + (rMax - rMin) * (1 - ilerleme), sag = rMin + (rMax - rMin) * ilerleme
                ZStack {
                    // Kaset gövdesi
                    RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.1))
                    RoundedRectangle(cornerRadius: 6)
                        .fill(LinearGradient(colors: [Color(red: 0.95, green: 0.93, blue: 0.86), Color(red: 0.86, green: 0.83, blue: 0.75)], startPoint: .top, endPoint: .bottom))
                        .frame(width: w * 0.86, height: h * 0.26)
                        .overlay(alignment: .leading) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(calar.simdiki?.album ?? "Tını — boş kaset").font(.custom("Noteworthy-Bold", size: 14)).lineLimit(1)
                                Text(calar.simdiki?.baslik ?? "").font(.custom("Noteworthy-Light", size: 11)).lineLimit(1)
                            }
                            .foregroundStyle(Color(red: 0.1, green: 0.15, blue: 0.45))
                            .padding(.horizontal, 10)
                        }
                        .overlay(alignment: .topTrailing) {
                            Text(calar.simdiki?.kayipsiz == true ? "TYPE IV · METAL" : "TYPE I · NORMAL")
                                .font(.system(size: 7, weight: .heavy)).padding(4).foregroundStyle(.red.opacity(0.8))
                        }
                        .position(x: w / 2, y: h * 0.17)
                    // Pencere
                    RoundedRectangle(cornerRadius: h * 0.2)
                        .fill(Color(red: 0.25, green: 0.22, blue: 0.2).opacity(0.9))
                        .frame(width: w * 0.62, height: h * 0.42)
                        .position(x: w / 2, y: h * 0.62)
                    // Bant sargıları
                    Circle().fill(Color(red: 0.24, green: 0.15, blue: 0.1)).frame(width: sol * 2, height: sol * 2).position(x: w * 0.3, y: h * 0.62)
                    Circle().fill(Color(red: 0.24, green: 0.15, blue: 0.1)).frame(width: sag * 2, height: sag * 2).position(x: w * 0.7, y: h * 0.62)
                    // Makaralar: sargısı küçük olan daha hızlı döner (bant sabit hızla akar)
                    Makara(aci: a * Double(rMax / sol)).frame(width: h * 0.3, height: h * 0.3).position(x: w * 0.3, y: h * 0.62)
                    Makara(aci: a * Double(rMax / sag)).frame(width: h * 0.3, height: h * 0.3).position(x: w * 0.7, y: h * 0.62)
                    // Cam yansıması
                    LinearGradient(colors: [.white.opacity(0.22), .clear, .white.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .allowsHitTesting(false)
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.8), lineWidth: 4))
    }

    private func aciHesapla(_ simdi: Date) -> Double {
        if calar.caliyorMu, let s = aci.son { aci.deger += simdi.timeIntervalSince(s) * 70 }
        aci.son = calar.caliyorMu ? simdi : nil
        return aci.deger
    }
}

private struct Makara: View {
    let aci: Double
    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.92))
            Circle().fill(Color(white: 0.25)).padding(9)
            ForEach(0..<6) { i in
                Capsule().fill(Color(white: 0.92)).frame(width: 4, height: 9)
                    .offset(y: -8).rotationEffect(.degrees(Double(i) * 60))
            }
        }
        .rotationEffect(.degrees(-aci))
    }
}

// MARK: - Anahtarlar ve düğmeler

private struct MegaBassAnahtari: View {
    @EnvironmentObject var ses: Ses
    var body: some View {
        let konum: Int = ses.ayar.bas == .megaBass ? 1 : (ses.ayar.bas == .groove ? 2 : 0)
        VStack(alignment: .leading, spacing: 3) {
            Text("MEGA BASS").font(.system(size: 8, weight: .heavy).italic()).foregroundStyle(Color(red: 0.7, green: 0.1, blue: 0.1))
            ZStack(alignment: .leading) {
                Capsule().fill(Color(white: 0.15)).frame(width: 84, height: 18)
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(colors: [Color(white: 0.85), Color(white: 0.5)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 26, height: 16)
                    .offset(x: 2 + CGFloat(konum) * 27)
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: konum)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                let yeni = (konum + 1) % 3
                if ses.ayar.basSeviye < 3 { ses.ayar.basSeviye = 6 }
                ses.ayar.bas = [.kapali, .megaBass, .groove][yeni]
            }
            HStack(spacing: 0) {
                Text("OFF").frame(width: 28); Text("MEGA").frame(width: 28); Text("GROOVE").frame(width: 30)
            }
            .font(.system(size: 6.5, weight: .bold)).foregroundStyle(Color(white: 0.3))
        }
        .sensoryFeedback(.selection, trigger: konum)
    }
}

private struct AVLSAnahtari: View {
    @EnvironmentObject var calar: Calar
    var body: some View {
        VStack(spacing: 3) {
            Text("AVLS").font(.system(size: 8, weight: .heavy)).foregroundStyle(Color(white: 0.25))
            ZStack(alignment: calar.avls ? .trailing : .leading) {
                Capsule().fill(Color(white: 0.15)).frame(width: 46, height: 16)
                RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.75)).frame(width: 20, height: 14).padding(.horizontal, 1)
            }
            .animation(.spring(response: 0.25), value: calar.avls)
            .onTapGesture { calar.avls.toggle() }
            HStack(spacing: 6) { Text("NORM"); Text("LIMIT") }.font(.system(size: 6.5, weight: .bold)).foregroundStyle(Color(white: 0.3))
        }
        .sensoryFeedback(.selection, trigger: calar.avls)
    }
}

/// Yandan görünen tırtıklı ses tekerleği; yukarı-aşağı sürüklenir.
private struct SesTekerlegi: View {
    @Binding var deger: Float
    @State private var baslangic: Float?
    var body: some View {
        VStack(spacing: 3) {
            Text("VOL \(Int(deger * 30))").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundStyle(Color(white: 0.25))
            Canvas { c, b in
                let kayma = CGFloat(deger) * 60
                c.fill(Path(roundedRect: CGRect(origin: .zero, size: b), cornerRadius: 5),
                       with: .linearGradient(Gradient(colors: [Color(white: 0.2), Color(white: 0.55), Color(white: 0.2)]), startPoint: .zero, endPoint: CGPoint(x: b.width, y: 0)))
                var y = (kayma.truncatingRemainder(dividingBy: 5))
                while y < b.height {
                    c.fill(Path(CGRect(x: 2, y: y, width: b.width - 4, height: 1.5)), with: .color(.black.opacity(0.55)))
                    y += 5
                }
            }
            .frame(width: 34, height: 54)
            .gesture(DragGesture()
                .onChanged { d in
                    if baslangic == nil { baslangic = deger }
                    deger = min(1, max(0, (baslangic ?? 0) - Float(d.translation.height) / 220))
                }
                .onEnded { _ in baslangic = nil })
        }
        .sensoryFeedback(.selection, trigger: Int(deger * 30))
    }
}

private struct MetalDugme: View {
    let simge: String, yazi: String
    var vurgu = false
    let eylem: () -> Void
    var body: some View {
        Button(action: eylem) {
            VStack(spacing: 4) {
                Image(systemName: simge).font(.system(size: 18, weight: .bold))
                Text(yazi).font(.system(size: 8, weight: .heavy))
            }
            .foregroundStyle(vurgu ? Color(red: 0.1, green: 0.25, blue: 0.6) : Color(white: 0.12))
            .frame(maxWidth: .infinity).frame(height: 56)
        }
        .buttonStyle(MetalBasis())
    }
}

private struct KucukDugme: View {
    let yazi: String
    let eylem: () -> Void
    var body: some View {
        Button(action: eylem) {
            Text(yazi).font(.system(size: 9, weight: .heavy)).foregroundStyle(Color(white: 0.15))
                .frame(maxWidth: .infinity).frame(height: 30)
        }
        .buttonStyle(MetalBasis(kose: 8))
    }
}

private struct MetalBasis: ButtonStyle {
    var kose: CGFloat = 12
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: kose)
                    .fill(LinearGradient(colors: configuration.isPressed ? [Color(white: 0.6), Color(white: 0.78)] : [Color(white: 0.92), Color(white: 0.62)],
                                         startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(configuration.isPressed ? 0.2 : 0.6), radius: configuration.isPressed ? 1 : 4, y: configuration.isPressed ? 1 : 3))
            .overlay(RoundedRectangle(cornerRadius: kose).stroke(Color.white.opacity(0.7), lineWidth: 0.8))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// Fırçalanmış alüminyum: gümüş degrade + yatay ince çizgiler.
struct FircaliMetal: View {
    var body: some View {
        Canvas { c, b in
            c.fill(Path(CGRect(origin: .zero, size: b)), with: .linearGradient(
                Gradient(colors: [Color(red: 0.86, green: 0.87, blue: 0.9), Color(red: 0.70, green: 0.72, blue: 0.76), Color(red: 0.82, green: 0.83, blue: 0.86), Color(red: 0.62, green: 0.64, blue: 0.68)]),
                startPoint: .zero, endPoint: CGPoint(x: b.width, y: b.height)))
            var t: UInt64 = 0x9E3779B97F4A7C15
            var y: CGFloat = 0
            while y < b.height {
                t = t &* 6364136223846793005 &+ 1442695040888963407
                let o = Double(t >> 40) / Double(1 << 24)
                c.fill(Path(CGRect(x: 0, y: y, width: b.width, height: 0.6)), with: .color((o > 0.5 ? Color.white : .black).opacity(0.04 + o * 0.05)))
                y += 1.3
            }
        }
    }
}
