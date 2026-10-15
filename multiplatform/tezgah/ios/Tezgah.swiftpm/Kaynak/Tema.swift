// Renkler İdrak iskeletinden (pano.py CSS'iyle aynı), ortak parçalar: kart, halka, çubuk, rozet, ısı haritası.
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

extension Color {
    static func hex(_ h: UInt32) -> Color {
        Color(.sRGB, red: Double((h >> 16) & 0xFF) / 255, green: Double((h >> 8) & 0xFF) / 255,
              blue: Double(h & 0xFF) / 255, opacity: 1)
    }

    /// Açık / koyu görünüme göre değişen renk.
    static func iki(_ acik: UInt32, _ koyu: UInt32) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { t in
            let h = t.userInterfaceStyle == .dark ? koyu : acik
            return UIColor(red: CGFloat((h >> 16) & 0xFF) / 255, green: CGFloat((h >> 8) & 0xFF) / 255,
                           blue: CGFloat(h & 0xFF) / 255, alpha: 1)
        })
        #else
        return Color(NSColor(name: nil) { g in
            let h = g.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? koyu : acik
            return NSColor(srgbRed: CGFloat((h >> 16) & 0xFF) / 255, green: CGFloat((h >> 8) & 0xFF) / 255,
                           blue: CGFloat(h & 0xFF) / 255, alpha: 1)
        })
        #endif
    }
}

enum T {
    static let zemin = Color.iki(0xF7F5F0, 0x080B12)
    static let yuzey = Color.iki(0xFFFFFF, 0x111726)
    static let tint = Color.iki(0xF1EDE4, 0x1A2133)
    static let murekkep = Color.iki(0x1D1D1F, 0xF2F2F4)
    static let yumusak = Color.iki(0x5F646B, 0xA3ACC2)
    static let soluk = Color.iki(0x8E9197, 0x6E7891)
    static let cizgi = Color.iki(0xE6E0D4, 0x232B3F)

    static let cumle = Color.iki(0xA1732F, 0xD8A660)
    static let muhendis = Color.iki(0x3D6E60, 0x6CBFA6)
    static let idrak = Color.iki(0xB0543C, 0xEC8A70)
    static let vault = Color.iki(0x4F5D95, 0x9AA8E0)
    static let yz = Color.iki(0xB9B3A6, 0x4A5470)
    static let dis = Color.iki(0xC9A27A, 0x8C6F52)

    static func renk(_ kod: String?) -> Color {
        switch kod {
        case "cumle": return cumle
        case "muhendis": return muhendis
        case "idrak": return idrak
        case "vault": return vault
        default: return yumusak
        }
    }

    static func koken(_ k: String?) -> Color {
        switch k {
        case "ben": return vault
        case "yz": return yz
        case "dis": return dis
        case "ortak": return muhendis
        default: return cizgi
        }
    }

    static func kokenAd(_ k: String?) -> String {
        switch k {
        case "ben": return "sen"
        case "yz": return "YZ"
        case "dis": return "dış"
        case "ortak": return "ortak"
        default: return "belirsiz"
        }
    }

    static let yay = Animation.spring(response: 0.55, dampingFraction: 0.82)
}

/// Mac'teki ön izleme betiği (ImageRenderer) animasyonları beklemeden son hâli çizsin diye.
private struct StatikAnahtar: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var statik: Bool {
        get { self[StatikAnahtar.self] }
        set { self[StatikAnahtar.self] = newValue }
    }
}

// MARK: - Biçimleme

enum Bicim {
    static let tr = Locale(identifier: "tr_TR")

    static func sayi(_ n: Int?) -> String {
        guard let n else { return "—" }
        let f = NumberFormatter()
        f.locale = tr
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    static func kisa(_ n: Int?) -> String {
        guard let n else { return "—" }
        if n >= 1_000_000 { return String(format: "%.1f Mn", Double(n) / 1_000_000).replacingOccurrences(of: ".", with: ",") }
        if n >= 10_000 { return "\(n / 1000) B" }
        return sayi(n)
    }

    private static let gunF: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func gun(_ s: String?) -> Date? {
        guard let s, s.count >= 10 else { return nil }
        return gunF.date(from: String(s.prefix(10)))
    }

    static func zaman(_ s: String?) -> Date? {
        guard let s else { return nil }
        for bicim in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = bicim
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    static func uzunTarih(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = tr
        f.dateFormat = "d MMMM yyyy, EEEE"
        return f.string(from: d)
    }

    static func kisaTarih(_ s: String?) -> String {
        guard let d = gun(s) else { return s ?? "" }
        let f = DateFormatter()
        f.locale = tr
        f.dateFormat = "d MMM"
        return f.string(from: d)
    }

    static func kisaTarih(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = tr
        f.dateFormat = "d MMM"
        return f.string(from: d)
    }

    static func once(_ s: String?) -> String {
        guard let d = zaman(s) else { return s ?? "" }
        let f = RelativeDateTimeFormatter()
        f.locale = tr
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }

    static func saat(_ s: String?) -> String {
        guard let d = zaman(s) else { return s ?? "—" }
        let f = DateFormatter()
        f.locale = tr
        f.dateFormat = Calendar.current.isDateInToday(d) ? "'bugün' HH:mm" : "d MMM HH:mm"
        return f.string(from: d)
    }
}

// MARK: - Parçalar

struct KartKutu<Icerik: View>: View {
    var renk: Color = T.cizgi
    var dolgu: CGFloat = 18
    @ViewBuilder var icerik: () -> Icerik

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { icerik() }
            .padding(dolgu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(T.yuzey, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(T.cizgi, lineWidth: 1))
            .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
    }
}

/// Kaydırırken hafifçe büyüyüp beliren kartlar.
struct BelirisEtkisi: ViewModifier {
    @Environment(\.statik) private var statik
    func body(content: Content) -> some View {
        if statik { content } else { canli(content) }
    }

    func canli(_ content: Content) -> some View {
        content.scrollTransition(.interactive, axis: .vertical) { c, faz in
            c.opacity(faz.isIdentity ? 1 : 0.35)
                .scaleEffect(faz.isIdentity ? 1 : 0.96)
                .offset(y: faz.value > 0 ? 14 : 0)
        }
    }
}

extension View {
    func belirerek() -> some View { modifier(BelirisEtkisi()) }
}

struct BolumBasligi: View {
    let baslik: String
    var alt: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(baslik).font(.system(.title3, design: .default).weight(.semibold))
            Spacer()
            if let alt { Text(alt).font(.footnote).foregroundStyle(T.soluk) }
        }
        .padding(.horizontal, 4)
        .padding(.top, 10)
    }
}

struct Rozet: View {
    let metin: String
    var renk: Color = T.yumusak
    var body: some View {
        Text(metin)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .foregroundStyle(renk)
            .background(renk.opacity(0.13), in: Capsule())
    }
}

struct DurumRozeti: View {
    let durum: String?
    var body: some View {
        switch durum {
        case "bitti": Rozet(metin: "bugün bitti", renk: T.muhendis)
        case "suruyor": Rozet(metin: "sürüyor", renk: T.cumle)
        default: Rozet(metin: "bekliyor", renk: T.soluk)
        }
    }
}

struct Cip: View {
    let metin: String
    var renk: Color = T.yumusak
    var body: some View {
        Text(metin)
            .font(.footnote)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(renk)
            .background(T.tint, in: Capsule())
    }
}

/// Satır satır akan çip dizilimi.
struct Akis: Layout {
    var bosluk: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 340
        var x: CGFloat = 0, y: CGFloat = 0, satir: CGFloat = 0
        for s in subviews {
            let b = s.sizeThatFits(.unspecified)
            if x + b.width > w, x > 0 { x = 0; y += satir + bosluk; satir = 0 }
            x += b.width + bosluk
            satir = max(satir, b.height)
        }
        return CGSize(width: w, height: y + satir)
    }

    func placeSubviews(in r: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = r.minX, y = r.minY, satir: CGFloat = 0
        for s in subviews {
            let b = s.sizeThatFits(.unspecified)
            if x + b.width > r.maxX, x > r.minX { x = r.minX; y += satir + bosluk; satir = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(b))
            x += b.width + bosluk
            satir = max(satir, b.height)
        }
    }
}

/// Görününce dolan ince çubuk.
struct Cubuk: View {
    let oran: Double
    var renk: Color
    var kalinlik: CGFloat = 6
    @State private var goster = false
    @Environment(\.statik) private var statik

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(T.tint)
                Capsule().fill(renk)
                    .frame(width: max(kalinlik / 2, g.size.width * (goster || statik ? oran : 0)))
            }
        }
        .frame(height: kalinlik)
        .onAppear { withAnimation(T.yay.delay(0.1)) { goster = true } }
    }
}

/// Apple Watch etkinlik halkası gibi, görününce dolar.
struct Halka: View {
    let oran: Double
    var renk: Color
    var kalinlik: CGFloat = 12
    @State private var goster = false
    @Environment(\.statik) private var statik

    var body: some View {
        ZStack {
            Circle().stroke(renk.opacity(0.16), lineWidth: kalinlik)
            Circle()
                .trim(from: 0, to: goster || statik ? max(0.004, oran) : 0)
                .stroke(renk, style: StrokeStyle(lineWidth: kalinlik, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .onAppear { withAnimation(.spring(response: 1.1, dampingFraction: 0.8).delay(0.15)) { goster = true } }
    }
}

/// Satır: ad · değer · altında çubuk.
struct OranSatiri: View {
    let ad: String
    let deger: String
    let oran: Double
    var renk: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(ad).font(.subheadline).lineLimit(1)
                Spacer(minLength: 8)
                Text(deger).font(.subheadline.monospacedDigit()).foregroundStyle(T.yumusak)
            }
            Cubuk(oran: oran, renk: renk, kalinlik: 4)
        }
        .padding(.vertical, 3)
    }
}

/// 28 günlük satır ısı haritası: kareler soldan sağa sırayla belirir.
struct IsiSatiri: View {
    let gunler: [Int]
    var renk: Color
    var bosluk: CGFloat = 3
    @State private var goster = false
    @Environment(\.statik) private var statik

    var body: some View {
        let goster = self.goster || statik
        let n = CGFloat(max(1, gunler.count))
        return GeometryReader { g in
            let k = max(2, (g.size.width - (n - 1) * bosluk) / n)
            let y = min(k * 1.6, 14)
            HStack(spacing: bosluk) {
                ForEach(Array(gunler.enumerated()), id: \.offset) { i, v in
                    RoundedRectangle(cornerRadius: k * 0.28, style: .continuous)
                        .fill(v == 0 ? T.tint : renk.opacity([0, 0.35, 0.65, 1][min(3, v)]))
                        .overlay(
                            RoundedRectangle(cornerRadius: k * 0.28, style: .continuous)
                                .strokeBorder(T.murekkep.opacity(i == gunler.count - 1 ? 0.7 : 0), lineWidth: 1.2)
                        )
                        .frame(width: k, height: y)
                        .scaleEffect(goster ? 1 : 0.2)
                        .opacity(goster ? 1 : 0)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(Double(i) * 0.018), value: goster)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 14)
        .onAppear { self.goster = true }
    }
}

/// Şeritteki kartın kayarken eğilip solması (ön izlemede kapalı).
struct SeritGecisi: ViewModifier {
    var olcek: CGFloat = 0.92
    var donus: Double = -8
    var solma: Double = 0.6
    @Environment(\.statik) private var statik
    func body(content: Content) -> some View {
        if statik { content } else {
            content.scrollTransition(.interactive, axis: .horizontal) { c, faz in
                c.scaleEffect(faz.isIdentity ? 1 : olcek)
                    .opacity(faz.isIdentity ? 1 : solma)
                    .rotation3DEffect(.degrees(faz.value * donus), axis: (0, 1, 0), perspective: 0.5)
            }
        }
    }
}

struct BosDurum: View {
    let simge: String
    let metin: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: simge).font(.largeTitle).foregroundStyle(T.soluk)
            Text(metin).font(.subheadline).foregroundStyle(T.yumusak).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(30)
    }
}

struct BolumHatasi: View {
    let ad: String
    let hata: String
    var body: some View {
        KartKutu {
            Label("\(ad) verisi okunamadı", systemImage: "exclamationmark.triangle")
                .font(.headline).foregroundStyle(T.idrak)
            Text(hata).font(.footnote).foregroundStyle(T.yumusak).padding(.top, 4)
        }
    }
}

/// Büyük sayı + küçük etiket; sayı değişince yuvarlanarak geçer.
struct BuyukSayi: View {
    let deger: String
    let etiket: String
    var renk: Color = T.murekkep
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(deger)
                .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(renk)
                .contentTransition(.numericText())
            Text(etiket).font(.caption).foregroundStyle(T.soluk).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EkranBasligi: View {
    let ust: String
    let baslik: String
    var alt: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ust.uppercased(with: Bicim.tr))
                .font(.caption.weight(.semibold)).tracking(0.6).foregroundStyle(T.soluk)
            Text(baslik).font(.system(size: 34, weight: .bold)).foregroundStyle(T.murekkep)
            if let alt { Text(alt).font(.callout).foregroundStyle(T.yumusak) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}


/// Yatay, sayfa sayfa oturan şerit. Ön izlemede (ImageRenderer kaydırmayı çizmez) düz satır.
struct Serit<Oge: Identifiable, Hucre: View>: View {
    let ogeler: [Oge]
    var bosluk: CGFloat = 12
    var kenar: CGFloat = 16
    @Binding var konum: Oge.ID?
    @ViewBuilder var hucre: (Oge) -> Hucre
    @Environment(\.statik) private var statik

    var body: some View {
        if statik {
            HStack(alignment: .top, spacing: bosluk) { ForEach(ogeler.prefix(3)) { hucre($0) } }
                .padding(.leading, kenar)
                .frame(width: 393, alignment: .leading)
                .clipped()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: bosluk) {
                    ForEach(ogeler) { hucre($0).id($0.id) }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $konum)
            .contentMargins(.horizontal, kenar, for: .scrollContent)
            .sensoryFeedback(.selection, trigger: konum)
        }
    }
}

/// Şerit içindeki tam genişlikli kart: telefonda ekran − 36 pt, ön izlemede 357 pt.
struct SeritGenisligi: ViewModifier {
    var eksi: CGFloat = 36
    @Environment(\.statik) private var statik
    func body(content: Content) -> some View {
        if statik { content.frame(width: 393 - eksi) } else {
            content.containerRelativeFrame(.horizontal) { w, _ in w - eksi }
        }
    }
}


/// Dikey kaydırma; ön izlemede (ImageRenderer kaydırma içini çizmez) düz içerik.
struct Kaydir<Icerik: View>: View {
    @ViewBuilder var icerik: () -> Icerik
    @Environment(\.statik) private var statik
    var body: some View {
        if statik { icerik() } else { ScrollView { icerik() } }
    }
}
