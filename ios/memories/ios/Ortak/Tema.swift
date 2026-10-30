// Görsel dil (2026-10-30, Teoria'nın dilinden): açıkta sıcak kâğıt beyazı, koyuda saf siyah (OLED).
// Yazı nötr; renk yalnız vurguda. Memories'in rengi ikondaki kehribar: widget ve Bugün kartında köşede hafif kehribar ışıma.
// İngilizce metin serif (New York). Bütün renkler açık/koyu çiftli; uygulama ve widget aynı paleti kullanır.
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum Tema {
    static let arka = cift(0xF6F4EF, 0x000000)
    static let yuzey = cift(0xFFFFFF, 0x111113)
    static let yuzey2 = cift(0xEEEBE4, 0x1C1C1F)
    static let cizgi = cift(0xE2DED5, 0x26262A)
    static let metin = cift(0x1A1A1C, 0xF4F2EE)
    static let ikincil = cift(0x6B6A66, 0x9A9AA0)
    static let soluk = cift(0xA3A19B, 0x5C5C63)

    static let vurgu = cift(0x1673E6, 0x3B9BFF)
    /// Dolu düğme üstündeki yazı: vurgunun karşıtı.
    static let dolguYazi = cift(0xFFFFFF, 0x000000)
    /// Memories'in rengi (ikondaki nokta): ışıma ve dolu düğme.
    static let kehribar = cift(0xE39A2D, 0xFFB547)
    /// Zemin üstünde yazı için kehribar: açıkta koyu (okunurluk), koyuda parlak.
    static let kehribarYazi = cift(0xB8650F, 0xFFAD47)
    static let yesil = cift(0x23915E, 0x39D98A)
    static let sari = Color(red: 0.98, green: 0.80, blue: 0.25)
    /// Canlı Etkinlik zemini (kilit ekranı her zaman koyu).
    static let gece = Color(red: 0.07, green: 0.07, blue: 0.08)

    /// İngilizce metin: serif, okunaklı.
    static func ingilizce(_ stil: Font.TextStyle = .body) -> Font { .system(stil, design: .serif) }

    static func bolumRengi(_ ad: String) -> Color {
        switch ad {
        case "aciklama": vurgu
        case "metin": kehribarYazi
        case "kelimeler": yesil
        default: .secondary
        }
    }

    private static func cift(_ acik: UInt32, _ koyu: UInt32) -> Color {
        #if canImport(UIKit)
        Color(UIColor { $0.userInterfaceStyle == .dark ? renk(koyu) : renk(acik) })
        #else
        Color(red: Double((acik >> 16) & 0xFF) / 255, green: Double((acik >> 8) & 0xFF) / 255, blue: Double(acik & 0xFF) / 255)
        #endif
    }

    #if canImport(UIKit)
    private static func renk(_ h: UInt32) -> UIColor {
        UIColor(red: CGFloat((h >> 16) & 0xFF) / 255, green: CGFloat((h >> 8) & 0xFF) / 255, blue: CGFloat(h & 0xFF) / 255, alpha: 1)
    }
    #endif
}

/// Widget ve Bugün kartı zemini: kâğıt beyazı / saf siyah, sağ üst köşede kehribar ışıma (Teoria'daki WZemin gibi).
struct TemaZemin: View {
    @Environment(\.colorScheme) private var gorunum
    var body: some View {
        ZStack {
            gorunum == .dark ? Color.black : Color.white
            RadialGradient(colors: [Tema.kehribar.opacity(gorunum == .dark ? 0.20 : 0.14), .clear],
                           center: .topTrailing, startRadius: 2, endRadius: gorunum == .dark ? 180 : 250)
        }
    }
}

extension View {
    /// Kart zemini: açıkta beyaz, koyuda bir kademe açık siyah.
    func kart(_ ic: CGFloat = 16) -> some View {
        self.padding(ic)
            .background { RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Tema.yuzey) }
    }
}
