// Ortak görsel parçalar: kart, halka, bant rozeti, basma efekti, ses düğmesi.
import SwiftUI

struct KartStili: ViewModifier {
    var dolgu: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .padding(dolgu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(R.yuzey, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(R.cizgi.opacity(0.7), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
    }
}

extension View {
    func kart(_ dolgu: CGFloat = 18) -> some View { modifier(KartStili(dolgu: dolgu)) }
}

struct Bas: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        c.label
            .scaleEffect(c.isPressed ? 0.96 : 1)
            .opacity(c.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: c.isPressed)
    }
}

struct AnaDugme: View {
    let baslik: String
    var simge: String? = nil
    var renk: Color = R.vurgu
    let eylem: () -> Void

    var body: some View {
        Button(action: eylem) {
            HStack(spacing: 8) {
                if let simge { Image(systemName: simge) }
                Text(baslik)
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(renk, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(Bas())
    }
}

struct Halka: View {
    let oran: Double
    var kalinlik: CGFloat = 12
    var renk: Color = R.vurgu
    @State private var gorunen = 0.0

    var body: some View {
        ZStack {
            Circle().stroke(renk.opacity(0.15), lineWidth: kalinlik)
            Circle()
                .trim(from: 0, to: gorunen)
                .stroke(renk, style: StrokeStyle(lineWidth: kalinlik, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .onAppear { withAnimation(.spring(response: 1.1, dampingFraction: 0.85).delay(0.15)) { gorunen = min(1, oran) } }
        .onChange(of: oran) { _, y in withAnimation(.spring(response: 0.8)) { gorunen = min(1, y) } }
    }
}

struct BantRozeti: View {
    let bant: String
    var body: some View {
        Text(bant.isEmpty ? "—" : bant)
            .font(.caption2.weight(.bold))
            .foregroundStyle(R.bant(bant))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(R.bant(bant).opacity(0.14), in: Capsule())
    }
}

/// Kelimede CEFR bandı, deyimsel fiilde gök mavisi "DEYİMSEL" rozeti.
struct RozetKelime: View {
    let k: Kelime
    var body: some View {
        if k.isPV {
            Text("DEYİMSEL")
                .font(.system(size: 10, weight: .heavy)).tracking(0.5)
                .foregroundStyle(R.pv)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(R.pv.opacity(0.14), in: Capsule())
        } else {
            BantRozeti(bant: k.c)
        }
    }
}

struct AsamaRozeti: View {
    let asama: Asama?
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(R.asama(asama)).frame(width: 6, height: 6)
            Text(asama?.ad ?? "Depoda").font(.caption2.weight(.semibold))
        }
        .foregroundStyle(R.asama(asama))
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(R.asama(asama).opacity(0.12), in: Capsule())
    }
}

struct SesDugmesi: View {
    let kelime: Kelime
    var boyut: CGFloat = 40
    @EnvironmentObject var depo: Depo
    @ObservedObject private var ses = Ses.ortak

    var body: some View {
        Button {
            ses.soyle(kelime, oxford: depo.ayar.oxfordSesi)
        } label: {
            Image(systemName: ses.caliyor ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                .font(.system(size: boyut * 0.42, weight: .semibold))
                .symbolEffect(.variableColor.iterative, isActive: ses.caliyor)
                .foregroundStyle(R.vurgu)
                .frame(width: boyut, height: boyut)
                .background(R.vurgu.opacity(0.12), in: Circle())
        }
        .buttonStyle(Bas())
        .sensoryFeedback(.selection, trigger: ses.caliyor)
    }
}

/// Akış düzeni (kalıp çipleri için)
struct Akis: Layout {
    var aralik: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let gen = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, satir: CGFloat = 0
        for s in subviews {
            let b = s.sizeThatFits(.unspecified)
            if x + b.width > gen, x > 0 { x = 0; y += satir + aralik; satir = 0 }
            x += b.width + aralik
            satir = max(satir, b.height)
        }
        return CGSize(width: gen, height: y + satir)
    }

    func placeSubviews(in r: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = r.minX, y = r.minY, satir: CGFloat = 0
        for s in subviews {
            let b = s.sizeThatFits(.unspecified)
            if x + b.width > r.maxX, x > r.minX { x = r.minX; y += satir + aralik; satir = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(b))
            x += b.width + aralik
            satir = max(satir, b.height)
        }
    }
}

struct Cip: View {
    let metin: String
    var renk: Color = R.ikincil
    var body: some View {
        Text(metin)
            .font(.footnote)
            .foregroundStyle(renk)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(R.yuzey2, in: Capsule())
    }
}

extension Date {
    var uzunGun: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMMM EEEE"
        return f.string(from: self)
    }
}
