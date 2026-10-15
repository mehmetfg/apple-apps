// Aşina'nın renkleri ve yazı biçimleri — uygulama ve widget ortak.
// Kâğıt + mürekkep zemini, tek sıcak vurgu (mercan). İngilizce kelimeler serif (New York),
// arayüz SF. Bantlar ayrı tonlarda: göz rengiyle seviyeyi tanısın.
import SwiftUI
import UIKit

extension Color {
    static func iki(_ acik: UInt32, _ koyu: UInt32) -> Color {
        Color(UIColor { t in
            let h = t.userInterfaceStyle == .dark ? koyu : acik
            return UIColor(red: CGFloat((h >> 16) & 0xFF) / 255, green: CGFloat((h >> 8) & 0xFF) / 255,
                           blue: CGFloat(h & 0xFF) / 255, alpha: 1)
        })
    }

    static func hex(_ h: UInt32) -> Color {
        Color(.sRGB, red: Double((h >> 16) & 0xFF) / 255, green: Double((h >> 8) & 0xFF) / 255,
              blue: Double(h & 0xFF) / 255, opacity: 1)
    }
}

enum R {
    static let zemin = Color.iki(0xF8F5EF, 0x0B0D12)
    static let yuzey = Color.iki(0xFFFFFF, 0x151821)
    static let yuzey2 = Color.iki(0xF1ECE3, 0x1D212C)
    static let murekkep = Color.iki(0x17181C, 0xF3F1EC)
    static let ikincil = Color.iki(0x5E6168, 0xA7ABB6)
    static let soluk = Color.iki(0x9A9CA2, 0x6B707C)
    static let cizgi = Color.iki(0xE7E1D6, 0x262A36)

    static let vurgu = Color.iki(0xE86B4A, 0xFF8F6B)
    static let dogru = Color.iki(0x2F8F6A, 0x5CCB9C)
    static let yanlis = Color.iki(0xC8453B, 0xFF7A6E)
    static let zor = Color.iki(0xC58A1E, 0xF2B84B)
    /// Deyimsel fiillerin rengi — kelimelerden bir bakışta ayrılsın diye gök mavisi
    static let pv = Color.iki(0x1F78D1, 0x5EB0FF)

    /// Bir kelimenin teması: deyimsel fiil ise gök mavisi, değilse CEFR bandı
    static func ton(_ c: String, pv: Bool) -> Color { pv ? Self.pv : bant(c) }

    /// Koyu widget zemininin derin tonu (Apple Hava Durumu/Müzik tarzı koyu gradyan)
    static func derin(_ c: String, pv: Bool) -> UInt32 {
        if pv { return 0x0B3166 }
        switch c {
        case "A1", "A2": return 0x0C3B3D
        case "B1": return 0x1B1F66
        case "B2": return 0x4D1B0B
        case "C1": return 0x35154F
        default: return 0x1A1C26
        }
    }

    static func bant(_ c: String) -> Color {
        switch c {
        case "A1", "A2": return Color.iki(0x2E8C86, 0x5CC8C0)
        case "B1": return Color.iki(0x4C5DB8, 0x8C9BFF)
        case "B2": return Color.iki(0xD0663F, 0xFF9670)
        case "C1": return Color.iki(0x8A4FA8, 0xC795E6)
        default: return ikincil
        }
    }

    static func asama(_ a: Asama?) -> Color {
        switch a {
        case .tanisma: return Color.iki(0xE0A13A, 0xF5C063)
        case .asina: return Color.iki(0x4C8DD0, 0x7DB4F0)
        case .oturmus: return Color.iki(0x2F9E73, 0x5CCB9C)
        case .kalici: return Color.iki(0x6E56C9, 0xA996F5)
        case nil: return soluk
        }
    }

    /// Bant rengiyle iki tonlu zemin (widget ve kartlar)
    static func bantZemin(_ c: String, pv: Bool = false) -> LinearGradient {
        let r = ton(c, pv: pv)
        return LinearGradient(colors: [r.opacity(0.22), r.opacity(0.06)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension Font {
    /// İngilizce kelime: New York serif
    static func kelime(_ boyut: CGFloat, _ agirlik: Font.Weight = .semibold) -> Font {
        .system(size: boyut, weight: agirlik, design: .serif)
    }
}

/// Örnek cümlede hedef kelimeyi (ve çekimli hâlini) vurgular.
enum Vurgu {
    static func aralik(_ cumle: String, _ kelime: String) -> Range<String.Index>? {
        let kok = kelime.count > 4 ? String(kelime.dropLast(kelime.hasSuffix("e") ? 1 : 2)) : kelime
        guard let bas = cumle.range(of: kok, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
        var son = bas.upperBound
        while son < cumle.endIndex, cumle[son].isLetter { son = cumle.index(after: son) }
        var ilk = bas.lowerBound
        while ilk > cumle.startIndex, cumle[cumle.index(before: ilk)].isLetter { ilk = cumle.index(before: ilk) }
        return ilk..<son
    }

    static func metin(_ cumle: String, _ kelime: String, renk: Color) -> AttributedString {
        var a = AttributedString(cumle)
        if let r = aralik(cumle, kelime), let ar = Range(r, in: a) {
            a[ar].foregroundColor = renk
            a[ar].inlinePresentationIntent = .stronglyEmphasized
        }
        return a
    }

    /// Boşluklu cümle: "We went for a _____ walk."
    static func bosluk(_ cumle: String, _ kelime: String) -> (String, String)? {
        guard let r = aralik(cumle, kelime) else { return nil }
        let cevap = String(cumle[r])
        var c = cumle
        c.replaceSubrange(r, with: String(repeating: "_", count: max(5, min(cevap.count, 9))))
        return (c, cevap)
    }
}
