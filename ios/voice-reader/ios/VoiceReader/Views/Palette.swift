// The app's colours. One accent (navy by default, measured from Voice Dream: icons #003D61, slider #006FB4) that the
// user changes in Görsel Ayarlar › Renk Ayarları; everything else follows the light / dark appearance.
// The play button is always the same orange-red (#FF3601).
import SwiftUI
import UIKit

/// The accent: `ink` colours icons and text on the bars, `fill` the progress bar. In dark mode both are lightened so
/// a deep navy stays readable.
struct Accent: Equatable, Sendable {
    let hex: String

    struct Preset: Identifiable, Sendable {
        let name: String, ink: String, fill: String
        var id: String { ink }
    }

    static let presets: [Preset] = [
        Preset(name: "Lacivert", ink: "003D61", fill: "006FB4"),
        Preset(name: "Çivit", ink: "1B2A5C", fill: "3A5FC8"),
        Preset(name: "Yeşil", ink: "0B4F3A", fill: "1B9A6B"),
        Preset(name: "Bordo", ink: "6B1630", fill: "C03058"),
        Preset(name: "Mor", ink: "40307A", fill: "7C5CD0"),
        Preset(name: "Grafit", ink: "2A2E35", fill: "6B7482"),
    ]
    static let standard = presets[0]

    init(hex: String) { self.hex = hex.uppercased().replacingOccurrences(of: "#", with: "") }

    private var preset: Preset? { Self.presets.first { $0.ink == hex } }

    private static func rgb(_ hex: String) -> (CGFloat, CGFloat, CGFloat)? {
        guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return nil }
        return (CGFloat((v >> 16) & 255) / 255, CGFloat((v >> 8) & 255) / 255, CGFloat(v & 255) / 255)
    }

    static func base(hex: String) -> UIColor { color(hex.uppercased()) }

    /// "RRGGBB" of a colour the user picked.
    static func hex(of color: Color) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: nil)
        return String(format: "%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    private static func color(_ hex: String) -> UIColor {
        let c = rgb(hex) ?? rgb(standard.ink)!
        return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
    }

    private static func lighten(_ c: UIColor, by t: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: nil)
        return UIColor(red: r + (1 - r) * t, green: g + (1 - g) * t, blue: b + (1 - b) * t, alpha: 1)
    }

    /// The bright companion of a custom colour (a preset has its own): same hue, more saturated and lighter.
    private static func companion(_ c: UIColor) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: nil)
        return UIColor(hue: h, saturation: min(1, s * 0.95 + 0.05), brightness: min(1, b + 0.34), alpha: 1)
    }

    /// The accent's hue with its colour turned down: dark mode keeps only a whisper of it (2026-11-10, "koyu
    /// temalarda çok fazla mavi var, sadeleştir"): icons and labels a quiet silver, bars a muted grey-blue.
    private static func quiet(_ c: UIColor, saturation k: CGFloat, brightness v: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: nil)
        return UIColor(hue: h, saturation: s * k, brightness: v, alpha: 1)
    }

    var inkUI: UIColor {
        let base = Self.color(hex)
        let bright = preset.map { Self.color($0.fill) } ?? Self.companion(base)
        return UIColor { $0.userInterfaceStyle == .dark ? Self.quiet(bright, saturation: 0.16, brightness: 0.88) : base }
    }
    var fillUI: UIColor {
        let base = preset.map { Self.color($0.fill) } ?? Self.companion(Self.color(hex))
        return UIColor { $0.userInterfaceStyle == .dark ? Self.quiet(base, saturation: 0.32, brightness: 0.70) : base }
    }
    /// A solid ground for white marks (the voice-note key, the prominent buttons): the accent in light mode, a
    /// graphite with a trace of the accent in dark mode (the silver ink would not carry white).
    var solidUI: UIColor {
        let base = Self.color(hex)
        return UIColor { $0.userInterfaceStyle == .dark ? Self.quiet(base, saturation: 0.22, brightness: 0.30) : base }
    }
    var ink: Color { Color(uiColor: inkUI) }
    var fill: Color { Color(uiColor: fillUI) }
    var solid: Color { Color(uiColor: solidUI) }
    /// A faint wash of the accent, for the selected row and the playing tile.
    var wash: Color { Color(uiColor: UIColor { t in
        let c = Self.color(hex)
        return t.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.10) : Self.lighten(c, by: 0.55).withAlphaComponent(0.30)
    }) }
}

enum Palette {
    static let play = Color(red: 1.0, green: 0.212, blue: 0.004)            // #FF3601
    static var playFill: Color { play }

    /// Library backdrop and panels, following the appearance.
    static let ground = dyn((0.941, 0.941, 0.941), (0.058, 0.058, 0.062))       // dark: neutral, no blue cast
    static let groundDeep = dyn((0.918, 0.918, 0.922), (0.022, 0.022, 0.024))
    static let panel = dyn((1, 1, 1), (0.120, 0.120, 0.128))

    private static func dyn(_ light: (Double, Double, Double), _ dark: (Double, Double, Double)) -> Color {
        Color(UIColor { t in
            let c = t.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}

private struct AccentKey: EnvironmentKey { static let defaultValue = Accent(hex: Accent.standard.ink) }
extension EnvironmentValues {
    var accent: Accent {
        get { self[AccentKey.self] }
        set { self[AccentKey.self] = newValue }
    }
}
