// Visual language shared with Teoria (2026-11-04): warm paper in light, true black in dark, serif titles,
// Kıvılcım's ember as the accent. Theme choice: Sistem · Açık · Koyu (applies to every window and the menu panel).
import SwiftUI
import AppKit

extension Color {
    /// Light / dark pair, resolved by the window's appearance.
    static func pair(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { a in
            let v = a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                           blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        })
    }
}

enum Ink {
    static let paper = Color.pair(0xF6F4EF, 0x000000)
    static let surface = Color.pair(0xFFFFFF, 0x121214)
    static let surface2 = Color.pair(0xEEEBE4, 0x1C1C1F)
    static let line = Color.pair(0xE2DED5, 0x2A2A2E)
    static let text = Color.pair(0x1A1A1C, 0xF4F2EE)
    static let secondary = Color.pair(0x6B6A66, 0x9A9AA0)
    static let faint = Color.pair(0xA3A19B, 0x5C5C63)
    static let ember = Color.pair(0xE2552B, 0xFF7A50)
    static let gold = Color.pair(0xB4892F, 0xE6C063)
    static let journal = Color.pair(0x4B3FD6, 0x8F87FF)

    static func serif(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        .system(style, design: .serif).weight(weight)
    }

    /// Series colour from links.py (#hex); free topics get gold.
    static func topic(_ hex: String) -> Color { hex.isEmpty ? gold : Color(hex: hex) }
}

enum ThemeChoice: String, CaseIterable, Identifiable {
    case sistem, acik, koyu
    var id: String { rawValue }
    var name: String { switch self { case .sistem: "Sistem"; case .acik: "Açık"; case .koyu: "Koyu" } }
    var symbol: String { switch self { case .sistem: "circle.lefthalf.filled"; case .acik: "sun.max"; case .koyu: "moon" } }

    static var current: ThemeChoice { ThemeChoice(rawValue: UserDefaults.standard.string(forKey: "tema") ?? "") ?? .sistem }

    /// NSApp.appearance reaches the menu bar panel and the HUD too, not only SwiftUI windows.
    @MainActor static func apply(_ t: ThemeChoice = current) {
        NSApp.appearance = switch t {
        case .sistem: nil
        case .acik: NSAppearance(named: .aqua)
        case .koyu: NSAppearance(named: .darkAqua)
        }
    }
}

/// A card on paper: surface fill, hairline border.
struct Card<C: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: C
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Ink.line) }
    }
}
