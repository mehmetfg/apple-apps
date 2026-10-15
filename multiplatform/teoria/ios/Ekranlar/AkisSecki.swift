// Akış v7 — edebî defter (2026-10-11, kullanıcı: "estetik olarak hâlâ bir şey eksik, ilham verici olsun").
// Teşhis: her gönderi aynı ağırlıkta, aynı mor çizgi, her kartta tekrarlanan kitap adı, ekranı bölen eylem satırı.
// Bu dosya akışın yeni dilini taşır:
//  · Kitap rengi — her kitabın tonu kendi kapağından çıkar (doygun piksellerin dairesel ortalaması); kapak renksizse
//    kimliğinden kalıcı bir ton. Yan çizgi, halka, kart tülü, seçki zemini hep bu tondan.
//  · Günün cümlesi (Seçki) — akışın başında, kitabın renginde koyu bir sayfa: eski bir işaret geri döner
//    (önce favori ve çekirdek iddialar, en az üç gün önce işaretlenmiş olanlar). Günde bir, gün boyu aynı.
//  · Seri — aynı gün aynı kitaptan art arda gelen işaretler tek kartta toplanır; kitap adı bir kez yazılır.
//  · Gün başlığı — "Bugün" serif, yanında o günün sayısı.
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// MARK: - Kitap rengi

enum KitapRengi {
    private static let kilit = NSLock()
    nonisolated(unsafe) private static var tonlar: [String: Double] = [:]

    /// Kitabın tonu (0…1). Kapaktan bir kez çıkarılır, bellekte kalır.
    static func ton(_ id: String) -> Double {
        kilit.lock()
        if let t = tonlar[id] { kilit.unlock(); return t }
        kilit.unlock()
        let t = cikar(id) ?? yedek(id)
        kilit.lock(); tonlar[id] = t; kilit.unlock()
        return t
    }

    private static func yedek(_ id: String) -> Double {
        switch Tema.renkAdi(id) {
        case "mavi": 0.60
        case "amber": 0.11
        case "indigo": 0.68
        case "turuncu": 0.07
        case "yesil": 0.42
        case "gul": 0.95
        default: 0.52
        }
    }

    /// 12×18'e küçültülmüş kapakta doygun ve karanlık olmayan piksellerin dairesel ton ortalaması.
    /// Kapak neredeyse renksizse (siyah-beyaz) nil: yedek ton kullanılır.
    private static func cikar(_ id: String) -> Double? {
        guard let r = KapakDeposu.resim(id), let cg = r.cgResim else { return nil }
        let w = 12, h = 18
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let tamam: Bool = px.withUnsafeMutableBytes { tampon in
            guard let ctx = CGContext(data: tampon.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard tamam else { return nil }
        var x = 0.0, y = 0.0, top = 0.0
        for i in stride(from: 0, to: px.count, by: 4) {
            let r = Double(px[i]) / 255, g = Double(px[i + 1]) / 255, b = Double(px[i + 2]) / 255
            let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
            guard mx > 0.14, d > 0.07 else { continue }
            var t: Double
            if mx == r { t = (g - b) / d } else if mx == g { t = (b - r) / d + 2 } else { t = (r - g) / d + 4 }
            t /= 6
            if t < 0 { t += 1 }
            let s = d / mx
            let a = s * s * mx
            x += cos(t * 2 * .pi) * a; y += sin(t * 2 * .pi) * a; top += a
        }
        guard top > 0.12 else { return nil }
        var t = atan2(y, x) / (2 * .pi)
        if t < 0 { t += 1 }
        return t
    }
}

private extension Resim {
    var cgResim: CGImage? {
        #if canImport(UIKit)
        cgImage
        #else
        cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
    }
}

extension Color {
    /// Açık ve koyu görünümde ayrı HSB.
    static func dinamikHSB(_ acik: (Double, Double, Double), _ koyu: (Double, Double, Double)) -> Color {
        #if canImport(UIKit)
        Color(UIColor { tr in
            let c = tr.userInterfaceStyle == .dark ? koyu : acik
            return UIColor(hue: c.0, saturation: c.1, brightness: c.2, alpha: 1)
        })
        #else
        Color(NSColor(name: nil) { g in
            let c = g.bestMatch(from: [.darkAqua, .vibrantDark]) != nil ? koyu : acik
            return NSColor(hue: c.0, saturation: c.1, brightness: c.2, alpha: 1)
        })
        #endif
    }
}

extension Tema {
    /// Kitabın vurgu rengi: yan çizgi, halka, küçük yazılar.
    static func kitap(_ id: String) -> Color {
        let h = KitapRengi.ton(id)
        let sari = h > 0.08 && h < 0.2                     // sarı-amber koyulaşınca zeytine döner: biraz daha doygun
        return .dinamikHSB((h, sari ? 0.72 : 0.56, sari ? 0.66 : 0.62), (h, 0.46, 0.92))
    }

    /// Seçki sayfasının zemini: kitabın tonunda, her iki görünümde de koyu (kapak gibi).
    static func kitapDerin(_ id: String) -> [Color] {
        let h = KitapRengi.ton(id)
        return [Color(hue: h, saturation: 0.58, brightness: 0.36),
                Color(hue: (h + 0.035).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.12)]
    }

    /// Koyu zeminde ışık: tırnak, ince yazı.
    static func kitapIsik(_ id: String) -> Color {
        Color(hue: KitapRengi.ton(id), saturation: 0.32, brightness: 1)
    }
}

// MARK: - Günün cümlesi

extension Depo {
    /// Günde bir işaret geri döner. Havuz: 50–300 karakter, en az üç gün önce işaretlenmiş; içinden önce favoriler
    /// ve çekirdek iddialar. Seçim günün sırasına bağlı: gün boyu aynı, ertesi gün başka.
    func gununCumlesi(_ gun: Date = Date()) -> Isaret? {
        let hepsi = akis.isaretler
        guard !hepsi.isEmpty else { return nil }
        let esik = gun.gunBasi.gun(-3)
        let uygun = hepsi.filter { (50...300).contains($0.metin.count) }
        let eski = uygun.filter { $0.zaman < esik }
        let taban = eski.isEmpty ? (uygun.isEmpty ? hepsi : uygun) : eski
        let secme = taban.filter { durum.favoriler.contains($0.id) || $0.renk == IsaretRengi.cekirdek.rawValue }
        let havuz = (secme.count >= 3 ? secme : taban).sorted { $0.id < $1.id }
        let sira = Int(gun.gunBasi.timeIntervalSince1970 / 86_400)
        return havuz[(sira &* 7_919 % havuz.count + havuz.count) % havuz.count]
    }
}

/// Akışın başındaki sayfa: kitabın renginde koyu zemin, bulanık kapak, büyük serif cümle.
struct SeckiKarti: View {
    @EnvironmentObject var depo: Depo
    let isaret: Isaret
    var boy: Boy = .telefon
    var ac: (() -> Void)? = nil
    var yaz: (() -> Void)? = nil

    enum Boy { case telefon, dar, sahne }

    @State private var kapak: Resim?

    private var yaziBoyu: CGFloat { switch boy { case .telefon: 23; case .dar: 19; case .sahne: 34 } }
    private var yaricap: CGFloat { boy == .sahne ? 34 : 26 }

    var body: some View {
        let sekil = RoundedRectangle(cornerRadius: yaricap, style: .continuous)
        let isik = Tema.kitapIsik(isaret.kitap)
        VStack(alignment: .leading, spacing: boy == .sahne ? 26 : 16) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle").font(.system(size: 10, weight: .bold))
                Text("GÜNÜN CÜMLESİ").font(.system(size: 11, weight: .bold)).tracking(1.6)
                Spacer(minLength: 8)
                Text(geriDonus).font(.system(size: 12)).opacity(0.75).lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.72))

            VStack(alignment: .leading, spacing: 0) {
                Text("“")
                    .font(.system(size: yaziBoyu * 2.2, weight: .bold, design: .serif))
                    .foregroundStyle(isik.opacity(0.55))
                    .offset(y: -yaziBoyu * 0.42)
                    .frame(height: yaziBoyu * 1.15, alignment: .top)
                    .accessibilityHidden(true)
                Text(isaret.metin)
                    .font(.system(size: yaziBoyu, weight: .regular, design: .serif))
                    .foregroundStyle(.white)
                    .lineSpacing(yaziBoyu * 0.3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            HStack(alignment: .center, spacing: 12) {
                KitapKapagi(id: isaret.kitap, baslik: isaret.baslik, genislik: boy == .sahne ? 34 : 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isaret.kisaBaslik).font(.system(size: boy == .sahne ? 16 : 14, weight: .semibold))
                        .foregroundStyle(.white).lineLimit(1)
                    Text(isaret.renkAdi).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 8)
                if let yaz {
                    Button(action: yaz) {
                        Label("Üzerine yaz", systemImage: "pencil.line")
                            .font(.system(size: 13.5, weight: .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Capsule().fill(.white.opacity(0.16)))
                            .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.6))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .help("Bu cümleye kendi fikrini yaz")
                }
            }
        }
        .padding(boy == .sahne ? 44 : (boy == .dar ? 18 : 22))
        .background { zemin(sekil) }
        .clipShape(sekil)
        .overlay(sekil.strokeBorder(.white.opacity(0.08), lineWidth: 0.7))
        .shadow(color: Tema.kitapDerin(isaret.kitap)[0].opacity(0.35), radius: boy == .sahne ? 40 : 22, y: boy == .sahne ? 18 : 10)
        .contentShape(sekil)
        .onTapGesture { ac?() }
        .environment(\.colorScheme, .dark)
        .onAppear { if kapak == nil { kapak = KapakDeposu.resim(isaret.kitap) } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Günün cümlesi, \(isaret.kisaBaslik): \(isaret.metin)")
    }

    @ViewBuilder
    private func zemin(_ sekil: RoundedRectangle) -> some View {
        let d = Tema.kitapDerin(isaret.kitap)
        ZStack {
            LinearGradient(colors: d, startPoint: .topLeading, endPoint: .bottomTrailing)
            if let kapak {
                GeometryReader { g in
                    resim(kapak)
                        .frame(width: g.size.width * 1.1, height: g.size.height * 1.4)
                        .blur(radius: boy == .sahne ? 60 : 38)
                        .opacity(0.5)
                        .offset(x: g.size.width * 0.25, y: -g.size.height * 0.25)
                }
                .allowsHitTesting(false)
            }
            RadialGradient(colors: [Tema.kitapIsik(isaret.kitap).opacity(0.22), .clear],
                           center: .topLeading, startRadius: 0, endRadius: boy == .sahne ? 700 : 380)
            LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .center, endPoint: .bottom)
        }
    }

    @ViewBuilder
    private func resim(_ r: Resim) -> some View {
        #if canImport(UIKit)
        Image(uiImage: r).resizable().scaledToFill()
        #else
        Image(nsImage: r).resizable().scaledToFill()
        #endif
    }

    private var geriDonus: String {
        let g = Tarih.takvim.dateComponents([.day], from: isaret.zaman.gunBasi, to: Date().gunBasi).day ?? 0
        switch g {
        case ..<1: return "bugün işaretledin"
        case 1: return "dün işaretledin"
        case 2...13: return "\(g) gün önce işaretledin"
        case 14...59: return "\(g / 7) hafta önce işaretledin"
        default: return "\(g / 30) ay önce işaretledin"
        }
    }
}

// MARK: - Kitap tülü (sayfanın tepesinde)

/// Sayfanın üstüne kitabın renginde yumuşak bir ışık: akışta günün cümlesinin, Mac okuma odasında seçili kitabın tonu.
struct KitapTulu: View {
    let kitap: String
    var yukseklik: CGFloat = 460
    @Environment(\.colorScheme) private var sema

    var body: some View {
        let r = Tema.kitap(kitap)
        ZStack(alignment: .top) {
            LinearGradient(colors: [r.opacity(sema == .dark ? 0.20 : 0.13), r.opacity(0)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [r.opacity(sema == .dark ? 0.22 : 0.12), .clear], center: .topTrailing, startRadius: 0, endRadius: yukseklik)
        }
        .frame(height: yukseklik)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Bloklar: gün başlığı, seri, sen, ses

enum AkisBlogu: Identifiable {
    case gun(Date, isaret: Int, kitap: Int)
    case seri([Isaret])
    case tek(AkisOgesi)

    var id: String {
        switch self {
        case .gun(let d, _, _): "gun-\(Tarih.gun(d))"
        case .seri(let l): "seri-" + (l.first?.id ?? "")
        case .tek(let o): o.id
        }
    }

    /// Gün değişince başlık; aynı gün aynı kitaptan art arda gelen işaretler tek seride (en çok `tavan`).
    static func kur(_ l: [AkisOgesi], grupla: Bool, tavan: Int = 12) -> [AkisBlogu] {
        var b: [AkisBlogu] = []
        var seri: [Isaret] = []
        var gun: Date?
        func bosalt() { if !seri.isEmpty { b.append(.seri(seri)); seri = [] } }
        // gün başlıkları için sayılar
        var sayi: [String: (Int, Set<String>)] = [:]
        for o in l {
            let k = Tarih.gun(o.zaman)
            var s = sayi[k] ?? (0, [])
            if case .isaret(let i) = o { s.0 += 1; s.1.insert(i.kitap) }
            sayi[k] = s
        }
        for o in l {
            if gun == nil || !Tarih.takvim.isDate(gun!, inSameDayAs: o.zaman) {
                bosalt()
                gun = o.zaman
                let s = sayi[Tarih.gun(o.zaman)] ?? (0, [])
                b.append(.gun(o.zaman, isaret: s.0, kitap: s.1.count))
            }
            if grupla, case .isaret(let i) = o {
                if let son = seri.last, son.kitap != i.kitap || seri.count >= tavan { bosalt() }
                seri.append(i)
            } else {
                bosalt()
                if case .isaret(let i) = o { b.append(.seri([i])) } else { b.append(.tek(o)) }
            }
        }
        bosalt()
        return b
    }
}

/// Gün başlığı: "Bugün" serif, yanında "Pazar · 6 işaret, 2 kitap".
struct GunBasligi: View {
    let gun: Date
    var isaret = 0
    var kitap = 0
    var kucuk = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(ad).font(.system(size: kucuk ? 18 : 24, weight: .semibold, design: .serif)).foregroundStyle(Tema.metin)
                .fixedSize()
            Text(alt).font(.system(size: kucuk ? 11.5 : 12.5)).foregroundStyle(Tema.soluk).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, kucuk ? 16 : 20).padding(.top, kucuk ? 16 : 26).padding(.bottom, kucuk ? 8 : 12)
        .accessibilityAddTraits(.isHeader)
    }

    private var ad: String {
        let t = Tarih.takvim
        if t.isDateInToday(gun) { return "Bugün" }
        if t.isDateInYesterday(gun) { return "Dün" }
        return gun.formatted(.dateTime.day().month(.wide).locale(Dil.tr))
    }

    private var alt: String {
        var p: [String] = []
        let t = Tarih.takvim
        if t.isDateInToday(gun) || t.isDateInYesterday(gun) {
            p.append(gun.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Dil.tr)))
        } else {
            p.append(gun.formatted(.dateTime.weekday(.wide).locale(Dil.tr)))
        }
        if isaret > 0 { p.append(kitap > 1 ? "\(isaret) işaret, \(kitap) kitap" : "\(isaret) işaret") }
        return p.joined(separator: " · ")
    }
}

/// Bir kitabın art arda gelen işaretleri tek kartta: kitap bir kez yazılır, işaretler ince çizgiyle ayrılır.
/// Kartın tepesinde kitabın renginde hafif bir tül, her işaretin solunda kitabın renginde çizgi.
struct SeriKarti<Parca: View>: View {
    let isaretler: [Isaret]
    var kucuk = false
    @ViewBuilder var parca: (Isaret, Int) -> Parca

    var body: some View {
        let ilk = isaretler[0]
        let r = Tema.kitap(ilk.kitap)
        let sekil = RoundedRectangle(cornerRadius: kucuk ? 18 : 24, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: kucuk ? 9 : 12) {
                KitapKapagi(id: ilk.kitap, baslik: ilk.baslik, genislik: kucuk ? 18 : 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(ilk.kisaBaslik).font(.system(size: kucuk ? 13 : 15, weight: .semibold)).foregroundStyle(Tema.metin).lineLimit(1)
                    Text(ust).font(.system(size: kucuk ? 11.5 : 12.5)).foregroundStyle(Tema.soluk).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, kucuk ? 13 : 18).padding(.top, kucuk ? 11 : 16).padding(.bottom, kucuk ? 4 : 6)
            ForEach(Array(isaretler.enumerated()), id: \.element.id) { n, i in
                if n > 0 {
                    Rectangle().fill(Tema.cizgi.opacity(0.8)).frame(height: 0.5)
                        .padding(.leading, kucuk ? 26 : 34).padding(.trailing, kucuk ? 13 : 18)
                }
                parca(i, n)
            }
        }
        .padding(.bottom, kucuk ? 4 : 6)
        .background {
            sekil.fill(Tema.yuzey)
                .overlay(alignment: .top) {
                    LinearGradient(colors: [r.opacity(0.09), r.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 120).clipShape(sekil)
                }
                .shadow(color: .black.opacity(0.05), radius: 14, y: 6)
        }
        .overlay(sekil.strokeBorder(Tema.cizgi.opacity(0.75), lineWidth: 0.6))
    }

    private var ust: String {
        let n = isaretler.count
        let saat = isaretler[0].zaman.formatted(.dateTime.hour().minute().locale(Dil.tr))
        return n > 1 ? "\(n) işaret · \(saat)" : saat
    }
}
