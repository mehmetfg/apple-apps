// Teoria görsel dili. Açık: sıcak kâğıt beyazı. Koyu: saf siyah (OLED) — kullanıcı isteği.
// Yazı: arayüz SF Pro, alıntı ve kavram New York (serif). Renkler açık/koyu çiftli.
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Color {
    static func dinamik(_ acik: UInt32, _ koyu: UInt32) -> Color {
        #if canImport(UIKit)
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: koyu) : UIColor(hex: acik) })
        #else
        Color(NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .vibrantDark]) != nil ? NSColor(hex: koyu) : NSColor(hex: acik) })
        #endif
    }

    init(hex: UInt32, alfa: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alfa)
    }
}

#if canImport(UIKit)
extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
#else
extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
#endif

enum Tema {
    static let arka = Color.dinamik(0xF6F4EF, 0x000000)
    static let yuzey = Color.dinamik(0xFFFFFF, 0x111113)
    static let yuzey2 = Color.dinamik(0xEEEBE4, 0x1C1C1F)
    static let cizgi = Color.dinamik(0xE2DED5, 0x26262A)
    static let metin = Color.dinamik(0x1A1A1C, 0xF4F2EE)
    static let ikincil = Color.dinamik(0x6B6A66, 0x9A9AA0)
    static let soluk = Color.dinamik(0xA3A19B, 0x5C5C63)
    static let vurgu = Color.dinamik(0x1673E6, 0x3B9BFF)      // mavi merkez (ikonla aynı aile)
    static let altin = Color.dinamik(0xB4892F, 0xE6C063)
    static let basari = Color.dinamik(0x23915E, 0x39D98A)
    static let uyari = Color.dinamik(0xC9711B, 0xFFAD47)

    static func hat(_ h: Hat) -> Color {
        switch h {
        case .hatirla: Color.dinamik(0x2F6FEB, 0x5E9BFF)
        case .donustur: Color.dinamik(0xC9711B, 0xFFAD47)
        case .kur: Color.dinamik(0x23915E, 0x39D98A)
        }
    }

    static func renk(_ ad: String?) -> Color {
        switch ad ?? "" {
        case "mavi": Color.dinamik(0x2F6FEB, 0x5E9BFF)
        case "indigo": Color.dinamik(0x4B3FD6, 0x8F87FF)
        case "amber": Color.dinamik(0xB4892F, 0xE6C063)
        case "turuncu": Color.dinamik(0xC9711B, 0xFFAD47)
        case "yesil": Color.dinamik(0x23915E, 0x39D98A)
        case "gul": Color.dinamik(0xC2416B, 0xFF7A9C)
        case "camgobegi": Color.dinamik(0x1B8A9C, 0x4FD1E0)
        default: Color.dinamik(0x6B6A66, 0xB0B0B8)
        }
    }

    static let kitapRenkleri = ["mavi", "amber", "indigo", "turuncu", "yesil", "gul", "camgobegi"]

    /// Akıştaki kitaplara kimliğinden kalıcı bir renk.
    static func renkAdi(_ id: String) -> String {
        let h = id.unicodeScalars.reduce(UInt32(7)) { ($0 &* 31) &+ $1.value }
        return kitapRenkleri[Int(h % UInt32(kitapRenkleri.count))]
    }

    static func isaretRengi(_ r: Int) -> Color {
        switch r {
        case 1: renk("indigo")
        case 2: renk("yesil")
        case 3: renk("mavi")
        case 4: renk("turuncu")
        default: soluk
        }
    }

    static func serif(_ stil: Font.TextStyle, _ agirlik: Font.Weight = .regular) -> Font {
        .system(stil, design: .serif).weight(agirlik)
    }
}

// MARK: - Halka

struct Halka: View {
    var oran: Double
    var renk: Color = Tema.vurgu
    var kalinlik: CGFloat = 8
    var iz: Color = Tema.cizgi

    var body: some View {
        ZStack {
            Circle().stroke(iz.opacity(0.7), lineWidth: kalinlik)
            Circle()
                .trim(from: 0, to: min(max(oran, 0.0001), 1))
                .stroke(AngularGradient(colors: [renk.opacity(0.75), renk], center: .center,
                                        startAngle: .degrees(-90), endAngle: .degrees(270 * max(oran, 0.05))),
                        style: StrokeStyle(lineWidth: kalinlik, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Kademe çubuğu (6 basamak, evrelere göre gruplu)

struct KademeCubugu: View {
    var kademe: Int
    var renk: Color
    var yukseklik: CGFloat = 6

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...6, id: \.self) { i in
                Capsule()
                    .fill(i <= kademe ? renk : Tema.cizgi)
                    .frame(height: yukseklik)
                if i == 2 || i == 4 { Spacer().frame(width: 3) }
            }
        }
    }
}
