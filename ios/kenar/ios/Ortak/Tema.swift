// Görsel dil: kâğıt ve mürekkep. Kenar, bir kitabın kenar boşluğudur — sıcak kâğıt, koyu mürekkep, tek vurgu rengi (kurşun kalem kırmızısı).
import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
    static let kalem = Color(hex: 0xC2452D)        // vurgu: kırmızı kurşun kalem
    static let murekkep = Color(light: 0x1F1B16, dark: 0xEFE8DC)
    static let kagit = Color(light: 0xF6F1E7, dark: 0x16130F)
    static let kart = Color(light: 0xFFFDF8, dark: 0x221E18)
    static let cizgi = Color(light: 0xE3DACB, dark: 0x3A342B)
    static let soluk = Color(light: 0x7A6F60, dark: 0xA39886)

    /// Bölüm renkleri: beş bölüm, beş sakin ton.
    static func bolum(_ no: Int) -> Color {
        [Color(hex: 0x7A5CFA), Color(hex: 0xC2452D), Color(hex: 0x2F8F7E), Color(hex: 0xD08A2E), Color(hex: 0x3B6FB6)][max(0, min(4, no - 1))]
    }

    init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light)) })
        #else
        self.init(hex: light)
        #endif
    }
}

extension Font {
    static func serif(_ boy: CGFloat, _ agirlik: Font.Weight = .regular) -> Font { .system(size: boy, weight: agirlik, design: .serif) }
}
