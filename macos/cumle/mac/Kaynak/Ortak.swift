// Ortak görünüm parçaları: kart, çip, sayı kutusu, akış düzeni, fark (düzeltme metnin üstünde),
// yazma alanı (NSTextView: otomatik düzeltme ve tahmin KAPALI — yazdığın senin olsun), kelime kartı.
import SwiftUI
import AppKit

enum Renk {
    static let vurgu = Color.accentColor
    // koyu tema: derin lacivert-siyah zemin, bir kademe açık kart
    static let zemin = Color(red: 0.047, green: 0.055, blue: 0.075)
    static let kart = Color(red: 0.082, green: 0.094, blue: 0.122)
    static let kart2 = Color(red: 0.110, green: 0.125, blue: 0.158)
    static let cizgi = Color.white.opacity(0.07)
    static let yesil = Color(nsColor: .systemGreen)
    static let kirmizi = Color(nsColor: .systemRed)
    static let sari = Color(nsColor: .systemOrange)
    static let mor = Color(nsColor: .systemPurple)
    static let ht: [String: Color] = ["artikel": .blue, "edat": .teal, "zaman": .purple, "biçim": .red, "yazım": .orange, "kelime": .gray]
}

extension Font {
    static func serif(_ boyut: CGFloat, _ w: Font.Weight = .regular) -> Font { .system(size: boyut, weight: w, design: .serif) }
}

struct Kart<I: View>: View {
    var dolgu: CGFloat = 18
    @ViewBuilder var icerik: I
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { icerik }
            .padding(dolgu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Renk.kart))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Renk.cizgi))
    }
}

struct Baslik: View {
    var metin: String
    var alt: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(metin.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary).tracking(0.6)
            if let alt { Text(alt).font(.caption).foregroundStyle(.tertiary) }
        }
    }
}

struct Cip: View {
    var metin: String
    var renk: Color = .secondary
    var simge: String? = nil
    var body: some View {
        HStack(spacing: 4) {
            if let simge { Image(systemName: simge).font(.caption2) }
            Text(metin).lineLimit(1)
        }
        .font(.caption)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(renk.opacity(0.13)))
        .foregroundStyle(renk == .secondary ? Color.secondary : renk)
    }
}

struct Kutu: View {
    var k: String
    var v: String
    var renk: Color = .primary
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(.system(.title2, design: .rounded).weight(.semibold)).foregroundStyle(renk).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(k).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Renk.kart2))
    }
}

struct Akis: Layout {
    var aralik: CGFloat = 6
    var satir: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, h: CGFloat = 0
        for s in subviews {
            let b = s.sizeThatFits(ProposedViewSize(width: w, height: nil))
            if x + b.width > w, x > 0 { x = 0; y += h + satir; h = 0 }
            x += b.width + aralik; h = max(h, b.height)
        }
        return CGSize(width: w, height: y + h)
    }
    func placeSubviews(in r: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = r.minX, y = r.minY, h: CGFloat = 0
        for s in subviews {
            let p = ProposedViewSize(width: r.width, height: nil)
            let b = s.sizeThatFits(p)
            if x + b.width > r.maxX, x > r.minX { x = r.minX; y += h + satir; h = 0 }
            s.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: b.width, height: b.height))
            x += b.width + aralik; h = max(h, b.height)
        }
    }
}

/// Hata türü çubukları.
struct HtCubuk: View {
    var ht: [String: Int]
    var body: some View {
        let e = ht.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        let m = max(1, e.first?.value ?? 1)
        VStack(spacing: 6) {
            if e.isEmpty { Text("hata yok").font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
            ForEach(e, id: \.key) { k, v in
                HStack(spacing: 8) {
                    Text(Metin.htAd[k] ?? k).font(.callout).lineLimit(1).frame(width: 128, alignment: .leading)
                    GeometryReader { g in
                        Capsule().fill((Renk.ht[k] ?? .gray).gradient).frame(width: max(4, g.size.width * CGFloat(v) / CGFloat(m)))
                    }.frame(height: 8)
                    Text("\(v)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
                }
            }
        }
    }
}

struct HtSatir: View {
    var ht: [String: Int]
    var body: some View {
        if !ht.isEmpty {
            Akis {
                Text("hata türü").font(.caption).foregroundStyle(.tertiary)
                ForEach(ht.sorted { $0.value > $1.value }, id: \.key) { k, n in Cip(metin: "\(Metin.htAd[k] ?? k) ×\(n)", renk: Renk.ht[k] ?? .gray) }
            }
        }
    }
}

// MARK: - Fark: düzeltme senin cümlenin üstünde

struct FarkHucre: Hashable { var alt: String; var ust: String?; var tur: Tur
    enum Tur: Hashable { case ok, yanlis, fazla, eksik, eksikBlok } }

enum FarkDiz {
    /// Eksik ↔ fazla eşleştirmesi sırayla değil benzerlikle: aynı kök (go↔went) ya da harf farkı (hal↔hall).
    static func hucreler(_ f: Fark) -> [FarkHucre] {
        var h: [FarkHucre] = []
        let ops = f.ops
        var i = 0
        while i < ops.count {
            if ops[i].t == "ok" { h.append(.init(alt: ops[i].s, ust: nil, tur: .ok)); i += 1; continue }
            var blok: [Int] = []
            while i < ops.count && ops[i].t != "ok" { blok.append(i); i += 1 }
            let E = blok.filter { ops[$0].t == "eksik" }, F = blok.filter { ops[$0].t == "fazla" }
            var es: [Int: Int] = [:]
            func benzer(_ e: Int, _ f: Int) -> Int {
                let a = Metin.sadele(ops[e].s), b = Metin.sadele(ops[f].s)
                if !Metin.govdeKume(a).isDisjoint(with: Metin.govdeKume(b)) { return 3 }
                if a.count > 2 && Metin.mesafe(a, b, 2) <= (a.count <= 5 ? 1 : 2) { return 2 }
                return 0
            }
            for f in F {
                var en: Int?, puan = 0
                for e in E where es[e] == nil { let p = benzer(e, f); if p > puan { puan = p; en = e } }
                if let e = en { es[e] = f; es[f] = e }
            }
            let kE = E.filter { es[$0] == nil }, kF = F.filter { es[$0] == nil }
            if kE.count == kF.count { for (n, e) in kE.enumerated() { es[e] = kF[n]; es[kF[n]] = e } }
            let yalnizE = E.filter { es[$0] == nil }
            let blokEksik = yalnizE.count >= 4
            var yazildi = false
            for k in blok {
                let o = ops[k]
                if o.t == "fazla" {
                    if let e = es[k] { h.append(.init(alt: o.s, ust: ops[e].s, tur: .yanlis)) }
                    else { h.append(.init(alt: o.s, ust: "fazla", tur: .fazla)) }
                } else if es[k] == nil {
                    if blokEksik {
                        if !yazildi { h.append(.init(alt: yalnizE.map { ops[$0].s }.joined(separator: " "), ust: nil, tur: .eksikBlok)); yazildi = true }
                    } else { h.append(.init(alt: "‸", ust: o.s, tur: .eksik)) }
                }
            }
        }
        return h
    }
}

struct FarkGorunum: View {
    var fark: Fark
    var boyut: CGFloat = 19
    var body: some View {
        if fark.tam {
            HStack(alignment: .top, spacing: 12) {
                Text("🎉").font(.system(size: 30))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tam isabet — eksiksiz ve doğru").font(.headline)
                    Text(fark.metin).font(.serif(boyut))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Renk.yesil.opacity(0.1)))
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Akis(aralik: 5, satir: 4) {
                    ForEach(Array(FarkDiz.hucreler(fark).enumerated()), id: \.offset) { _, c in hucre(c) }
                }
                HStack(spacing: 14) {
                    Label { Text("olması gereken") } icon: { Circle().fill(Renk.yesil).frame(width: 7) }
                    Label { Text("değiştir / çıkar") } icon: { Circle().fill(Renk.kirmizi).frame(width: 7) }
                    Text("‸ burada kelime eksik")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    @ViewBuilder private func hucre(_ c: FarkHucre) -> some View {
        VStack(spacing: 0) {
            Text(c.ust ?? " ").font(.system(size: boyut * 0.62, weight: .semibold))
                .foregroundStyle(c.tur == .fazla ? Renk.kirmizi.opacity(0.8) : Renk.yesil)
            switch c.tur {
            case .ok: Text(c.alt).font(.serif(boyut))
            case .yanlis, .fazla: Text(c.alt).font(.serif(boyut)).strikethrough(color: Renk.kirmizi).foregroundStyle(Renk.kirmizi)
            case .eksik: Text(c.alt).font(.serif(boyut, .bold)).foregroundStyle(Renk.yesil)
            case .eksikBlok: Text(c.alt).font(.serif(boyut)).foregroundStyle(Renk.yesil)
                .padding(.horizontal, 4).background(RoundedRectangle(cornerRadius: 4).fill(Renk.yesil.opacity(0.12)))
                .help("yazılmamış kısım")
            }
        }
    }
}

struct SkorHalka: View {
    var yuzde: Int
    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 6)
            Circle().trim(from: 0, to: CGFloat(yuzde) / 100).stroke(yuzde >= 95 ? Renk.yesil : yuzde >= 80 ? Renk.vurgu : Renk.sari,
                                                                  style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
            Text("%\(yuzde)").font(.system(.callout, design: .rounded).weight(.bold)).monospacedDigit()
        }
        .frame(width: 54, height: 54)
    }
}

// MARK: - Yazma alanı

/// NSTextView: Enter = gönder, Shift+Enter = alt satır, ⌥H ipucu, ⌥E cümle, ⌥↑/↓ paragraf odağı.
/// Otomatik düzeltme, metin değiştirme ve satır içi tahmin KAPALI; yalnız yazım altı çizilir (sağ tık: öneri).
struct Editor: NSViewRepresentable {
    @Binding var metin: String
    var yerTutucu: String
    var boyut: CGFloat = 20
    var odak: UUID
    var gonder: (() -> Void)?
    var klavye: ((Kisayol) -> Bool)? = nil
    var degisti: ((String) -> Void)? = nil
    var duzenlenebilir = true

    enum Kisayol { case ipucu, cumle, yukari, asagi, oncekiCumle, sonrakiCumle }

    final class Alan: NSTextView {
        var gonder: (() -> Void)?
        var klavye: ((Kisayol) -> Bool)?
        var yerTutucu = ""
        override func keyDown(with e: NSEvent) {
            let m = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let k = e.charactersIgnoringModifiers?.lowercased() ?? ""
            if e.keyCode == 36 || e.keyCode == 76 {
                if m.contains(.shift) { super.keyDown(with: e); return }
                if !hasMarkedText() { gonder?(); return }
            }
            if m == .option, let kl = klavye {
                if k == "h" || e.keyCode == 4, kl(.ipucu) { return }
                if k == "e" || e.keyCode == 14, kl(.cumle) { return }
                if e.keyCode == 126, kl(.yukari) { return }
                if e.keyCode == 125, kl(.asagi) { return }
            }
            super.keyDown(with: e)
        }
        override func draw(_ r: NSRect) {
            super.draw(r)
            if string.isEmpty, !yerTutucu.isEmpty {
                let a: [NSAttributedString.Key: Any] = [.font: font ?? .systemFont(ofSize: 18), .foregroundColor: NSColor.placeholderTextColor]
                (yerTutucu as NSString).draw(at: NSPoint(x: textContainerInset.width + 5, y: textContainerInset.height), withAttributes: a)
            }
        }
    }

    final class Koordinator: NSObject, NSTextViewDelegate {
        var ust: Editor
        var sonOdak: UUID?
        init(_ u: Editor) { ust = u }
        func textDidChange(_ n: Notification) {
            guard let t = n.object as? NSTextView else { return }
            ust.metin = t.string
            ust.degisti?(t.string)
            t.needsDisplay = true
        }
    }

    func makeCoordinator() -> Koordinator { Koordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let sv = NSTextView.scrollableTextView()
        sv.drawsBackground = false
        sv.hasVerticalScroller = true
        let t = Alan(frame: .zero)
        t.isRichText = false
        t.allowsUndo = true
        t.drawsBackground = false
        t.font = NSFont(descriptor: NSFont.systemFont(ofSize: boyut).fontDescriptor.withDesign(.serif) ?? NSFont.systemFont(ofSize: boyut).fontDescriptor, size: boyut)
        t.textContainerInset = NSSize(width: 6, height: 10)
        t.isAutomaticSpellingCorrectionEnabled = false
        t.isAutomaticTextReplacementEnabled = false
        t.isAutomaticQuoteSubstitutionEnabled = false
        t.isAutomaticDashSubstitutionEnabled = false
        t.isAutomaticTextCompletionEnabled = false
        t.isGrammarCheckingEnabled = false
        t.isContinuousSpellCheckingEnabled = true
        if #available(macOS 14.0, *) { t.inlinePredictionType = .no }
        if #available(macOS 15.0, *) { t.writingToolsBehavior = .none }
        t.isVerticallyResizable = true
        t.autoresizingMask = [.width]
        t.textContainer?.widthTracksTextView = true
        t.delegate = context.coordinator
        t.string = metin
        sv.documentView = t
        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {
        guard let t = sv.documentView as? Alan else { return }
        context.coordinator.ust = self
        t.gonder = gonder
        t.klavye = klavye
        t.yerTutucu = yerTutucu
        t.isEditable = duzenlenebilir
        if t.string != metin { t.string = metin; t.needsDisplay = true }
        if context.coordinator.sonOdak != odak {
            context.coordinator.sonOdak = odak
            DispatchQueue.main.async { t.window?.makeFirstResponder(t); t.setSelectedRange(NSRange(location: (t.string as NSString).length, length: 0)) }
        }
    }
}

// MARK: - Kelime kartı (sözlük + Oxford sesi)

struct KelimeDugmesi: View {
    var kelime: String
    var renk: Color = Renk.vurgu
    @EnvironmentObject var t: Tezgah
    @State private var acik = false
    var body: some View {
        Button { acik = true; t.ses.kelime(kelime, sozluk: t.sozluk) } label: {
            HStack(spacing: 4) { Image(systemName: "speaker.wave.2").font(.caption2); Text(kelime) }
                .font(.callout)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(renk.opacity(0.13)))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $acik, arrowEdge: .bottom) { KelimeKarti(kelime: kelime).environmentObject(t) }
    }
}

struct KelimeKarti: View {
    var kelime: String
    @EnvironmentObject var t: Tezgah
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let s = t.sozluk.bul(kelime) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(s.w).font(.serif(22, .semibold))
                    Button { t.ses.kelime(s.w, sozluk: t.sozluk) } label: { Image(systemName: "speaker.wave.2.fill") }.buttonStyle(.borderless)
                    if !s.phon.isEmpty { Text(s.phon).foregroundStyle(.secondary) }
                    if !s.cefr.isEmpty { Cip(metin: s.cefr, renk: Renk.vurgu) }
                }
                Text(s.tr.isEmpty ? "—" : s.tr).font(.title3)
                if !s.pos.isEmpty { Text(s.pos).font(.caption).foregroundStyle(.secondary) }
                if !s.def.isEmpty { Text(s.def).font(.callout) }
                ForEach(s.ex.prefix(3), id: \.self) { e in Text(e).font(.serif(14)).foregroundStyle(.secondary) }
            } else {
                Text(kelime).font(.serif(22, .semibold))
                Text(t.sozlukHazir ? "Oxford 5000 listesinde yok." : "Sözlük yükleniyor…").foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
    }
}

/// Yan yana sığmazsa alt alta.
struct IkiliSira<A: View, B: View>: View {
    @ViewBuilder var a: A
    @ViewBuilder var b: B
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) { a.frame(minWidth: 320); b.frame(minWidth: 320) }
            VStack(spacing: 14) { a; b }
        }
    }
}
