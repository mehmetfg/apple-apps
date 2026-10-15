// Ortak parçalar: ses, titreşim, konfeti, kademe halkası, renkli formül, taş düzeni.
import SwiftUI
import AVFoundation

// MARK: - Ses (cihazın İngiliz sesi)

@MainActor
enum Ses {
    static var acik = true
    static var hiz: Float = 0.46
    private static let s = AVSpeechSynthesizer()

    static func konus(_ metin: String) {
        guard acik else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        s.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: Metin.koseliSil(metin).replacingOccurrences(of: "____", with: "blank"))
        u.voice = AVSpeechSynthesisVoice(language: "en-GB")
        u.rate = hiz
        s.speak(u)
    }
}

// MARK: - Titreşim

@MainActor
enum Dokunus {
    static var acik = true
    static func hafif() { guard acik else { return }; UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func orta() { guard acik else { return }; UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func basari() { guard acik else { return }; UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func hata() { guard acik else { return }; UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func secim() { guard acik else { return }; UISelectionFeedbackGenerator().selectionChanged() }
}

// MARK: - Konfeti

struct Konfeti: View {
    @State private var baslangic = Date.now
    private let parcalar: [(x: Double, hiz: Double, boy: Double, renk: Color, don: Double)] = (0..<70).map { _ in
        (Double.random(in: 0...1), Double.random(in: 0.5...1.2), Double.random(in: 5...10),
         [Tema.vurgu, Tema.renk("kehribar"), Tema.renk("turkuaz"), Tema.renk("gul"), Tema.renk("yesil")].randomElement()!,
         Double.random(in: -6...6))
    }
    var body: some View {
        TimelineView(.animation) { t in
            Canvas { c, boyut in
                let gecen = t.date.timeIntervalSince(baslangic)
                for p in parcalar {
                    let y = -20 + gecen * p.hiz * boyut.height * 0.9
                    guard y < boyut.height + 20 else { continue }
                    let x = p.x * boyut.width + sin(gecen * 3 + p.don) * 18
                    var cc = c
                    cc.translateBy(x: x, y: y)
                    cc.rotate(by: .radians(gecen * p.don))
                    cc.fill(Path(roundedRect: CGRect(x: -p.boy / 2, y: -p.boy / 4, width: p.boy, height: p.boy / 2), cornerRadius: 1.5),
                            with: .color(p.renk))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

// MARK: - Kademe halkası (gördüm → taklit → üretim → özerk)

struct KademeHalkasi: View {
    let kademe: Int
    var renk: Color = Tema.vurgu
    var boy: CGFloat = 34
    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .trim(from: Double(i) / 4 + 0.015, to: Double(i + 1) / 4 - 0.015)
                    .stroke(i < kademe ? renk : renk.opacity(0.16), style: StrokeStyle(lineWidth: boy * 0.13, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            if kademe >= 4 {
                Image(systemName: "star.fill").font(.system(size: boy * 0.32)).foregroundStyle(renk)
            }
        }
        .frame(width: boy, height: boy)
        .accessibilityLabel("Aşinalık: \(Tema.kademeAdi(kademe))")
    }
}

// MARK: - Renkli formül: parçalar mekanizma rengini taşır

struct FormulMetni: View {
    let formul: String
    var font: Font = .system(.callout, design: .monospaced)

    var body: some View {
        Text(renkli).font(font).lineSpacing(5)
    }

    private var renkli: AttributedString {
        var sonuc = AttributedString()
        // kelimeleri ayırırken ayraçları da koru
        let desen = #/[A-Za-z0-9\-\/']+|[^A-Za-z0-9\-\/']+/#
        for m in formul.matches(of: desen) {
            let p = String(m.output)
            var a = AttributedString(p.replacingOccurrences(of: "-", with: "\u{2011}"))
            if let r = Self.renk(p) { a.foregroundColor = r; a.font = font.weight(.semibold) }
            else if p.contains("·") || p.contains("↔") || p.contains("+") { a.foregroundColor = .secondary }
            sonuc += a
        }
        return sonuc
    }

    static func renk(_ p: String) -> Color? {
        let k = p.lowercased()
        let modal = ["will", "would", "can", "could", "may", "might", "must", "should", "ought", "shall", "mustn't", "can't", "won't", "'ll"]
        if k.split(separator: "/").contains(where: { modal.contains(String($0)) }) { return Tema.modal }
        if ["v3", "had", "have", "has", "have/has", "having"].contains(k) { return Tema.perfect }
        if k.contains("-ing") || k == "being" || k == "v-ing" { return Tema.surec }
        if ["v2", "did", "was", "were", "was/were", "-ed"].contains(k) { return Tema.zaman }
        if ["am/is/are", "be", "is", "are", "am"].contains(k) { return Tema.edilgen.opacity(0.85) }
        return nil
    }
}

// MARK: - Yasa rozeti

/// Renkli nokta + yazı (bölge etiketi). Sistem simgesi yerine.
struct NoktaEtiket: View {
    let metin: String
    let renk: Color
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(renk).frame(width: 7, height: 7)
            Text(metin)
        }
    }
}

struct YasaRozeti: View {
    let yasa: Yasa
    var kucuk = false
    var body: some View {
        HStack(spacing: 4) {
            Cizim(ad: yasa.id, renk: Tema.renk(yasa.renk), boy: kucuk ? 16 : 20, zemin: false)
            Text(yasa.ad)
        }
            .font(kucuk ? .caption2.weight(.semibold) : .caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, kucuk ? 8 : 10).padding(.vertical, kucuk ? 4 : 6)
            .foregroundStyle(Tema.renk(yasa.renk))
            .background(Capsule().fill(Tema.renk(yasa.renk).opacity(0.13)))
    }
}

// MARK: - Akış düzeni (taşlar satır satır sarar)

struct Akis: Layout {
    var aralik: CGFloat = 8
    var satirAraligi: CGFloat = 8
    var ortala = true

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let gen = proposal.width ?? 340
        var x: CGFloat = 0, y: CGFloat = 0, satir: CGFloat = 0, enGenis: CGFloat = 0
        for v in subviews {
            let b = v.sizeThatFits(.unspecified)
            if x + b.width > gen, x > 0 { x = 0; y += satir + satirAraligi; satir = 0 }
            x += b.width + aralik; satir = max(satir, b.height); enGenis = max(enGenis, x - aralik)
        }
        return CGSize(width: proposal.width ?? enGenis, height: y + satir)
    }

    func placeSubviews(in r: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var satirlar: [[(LayoutSubview, CGSize)]] = [[]]
        var x: CGFloat = 0
        for v in subviews {
            let b = v.sizeThatFits(.unspecified)
            if x + b.width > r.width, x > 0 { satirlar.append([]); x = 0 }
            satirlar[satirlar.count - 1].append((v, b)); x += b.width + aralik
        }
        var y = r.minY
        for s in satirlar {
            let gen = s.reduce(0) { $0 + $1.1.width } + aralik * CGFloat(max(0, s.count - 1))
            var xx = ortala ? r.minX + (r.width - gen) / 2 : r.minX
            let yuk = s.map(\.1.height).max() ?? 0
            for (v, b) in s {
                v.place(at: CGPoint(x: xx, y: y + (yuk - b.height) / 2), proposal: ProposedViewSize(b))
                xx += b.width + aralik
            }
            y += yuk + satirAraligi
        }
    }
}

// MARK: - Taş

struct Tas: Identifiable, Hashable {
    let id = UUID()
    let metin: String
}

struct TasGorunum: View {
    let metin: String
    var renk: Color = Tema.vurgu
    var dolu = true
    var body: some View {
        Text(metin)
            .font(Tema.ingilizce(.body, .medium))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(dolu ? Tema.yuzey : renk.opacity(0.12))
                    .shadow(color: .black.opacity(dolu ? 0.08 : 0), radius: 2, y: 2)
            )
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(renk.opacity(0.35), lineWidth: 1))
    }
}

/// Taş tezgâhı: üstte kurulan dizi, altta taş bankası. Dokun → yer değiştir.
struct TasTezgahi: View {
    @Binding var dizi: [Tas]
    @Binding var banka: [Tas]
    var renk: Color = Tema.vurgu
    var kilitli = false
    @Namespace private var ns

    var body: some View {
        VStack(spacing: 18) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(renk.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                if dizi.isEmpty {
                    Text("Taşlara dokun, cümleyi kur")
                        .font(.footnote).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, minHeight: 64)
                }
                Akis {
                    ForEach(dizi) { t in
                        TasGorunum(metin: t.metin, renk: renk, dolu: false)
                            .matchedGeometryEffect(id: t.id, in: ns)
                            .onTapGesture { geriAl(t) }
                    }
                }
                .padding(12)
            }
            .frame(minHeight: 64)

            Akis {
                ForEach(banka) { t in
                    TasGorunum(metin: t.metin, renk: renk)
                        .matchedGeometryEffect(id: t.id, in: ns)
                        .onTapGesture { koy(t) }
                }
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: dizi)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: banka)
    }

    private func koy(_ t: Tas) {
        guard !kilitli else { return }
        Dokunus.hafif()
        banka.removeAll { $0.id == t.id }; dizi.append(t)
    }
    private func geriAl(_ t: Tas) {
        guard !kilitli else { return }
        Dokunus.secim()
        dizi.removeAll { $0.id == t.id }; banka.append(t)
    }
}

// MARK: - Sesli cümle satırı

struct SesliCumle: View {
    let en: String
    var tr: String? = nil
    var renk: Color = Tema.vurgu
    var body: some View {
        Button { Ses.konus(en) } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "speaker.wave.2.fill").font(.footnote).foregroundStyle(renk).padding(.top, 4)
                VStack(alignment: .leading, spacing: 4) {
                    Text(en).font(Tema.ingilizce(.body, .medium)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                    if let tr { Text(tr).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading) }
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Oyun ve quiz ekranlarının üst çubuğu: kapat · başlık · ilerleme
struct OyunUstu: View {
    let baslik: String
    var alt: String? = nil
    var renk: Color = Tema.vurgu
    var ilerleme: Double? = nil
    let kapat: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button(action: kapat) {
                    Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 36, height: 36)
                        .background(Circle().fill(Color(.tertiarySystemFill)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Kapat")
                Spacer()
                VStack(spacing: 1) {
                    Text(baslik).font(.headline)
                    if let alt { Text(alt).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Color.clear.frame(width: 36, height: 36)
            }
            if let ilerleme {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(renk.opacity(0.15))
                        Capsule().fill(renk).frame(width: max(8, g.size.width * ilerleme))
                    }
                }
                .frame(height: 6)
                .animation(.spring, value: ilerleme)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
}
