// Colours, tones and the small shared pieces (card, glass chip, section title).
import SwiftUI

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { t in
            let v = t.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        })
    }

    static let ground = Color(light: 0xF2F1F8, dark: 0x0D0D13)
    static let card = Color(light: 0xFFFFFF, dark: 0x1A1A22)
    static let track = Color(light: 0xDDDCE6, dark: 0x2C2C38)
    static let good = Color(light: 0x1FB48C, dark: 0x35D0A6)
    static let watch = Color(light: 0xF09A28, dark: 0xFFB44A)
    static let attention = Color(light: 0xF0525A, dark: 0xFF6B72)
    static let calm = Color(light: 0x2F6BFF, dark: 0x5C8DFF)
    static let sleep = Color(light: 0x5856E0, dark: 0x7D7BFF)
    static let move = Color(light: 0xFF5A3C, dark: 0xFF7A5E)
    static let heart = Color(light: 0xFF2D55, dark: 0xFF5C7C)
    static let food = Color(light: 0x34A853, dark: 0x58C877)
    static let mind = Color(light: 0x9B51E0, dark: 0xB57BFF)
}

enum Tone: String {
    case good, watch, attention, unknown

    init(status: String) {
        switch status {
        case "in", "good": self = .good
        case "watch": self = .watch
        case "attention", "alert": self = .attention
        default: self = .unknown
        }
    }

    var color: Color {
        switch self {
        case .good: return .good
        case .watch: return .watch
        case .attention: return .attention
        case .unknown: return .secondary
        }
    }

    var label: String {
        switch self {
        case .good: return "Aralıkta"
        case .watch: return "Sınırda"
        case .attention: return "Aralık dışında"
        case .unknown: return "Bilgi"
        }
    }

    var areaLabel: String {
        switch self {
        case .good: return "İyi yerde"
        case .watch: return "Tekrar bakılacak"
        case .attention: return "Bakman gerekiyor"
        case .unknown: return "Veri yok"
        }
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct SectionTitle: View {
    var text: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).font(.headline)
            Spacer()
            if let trailing { Text(trailing).font(.subheadline).foregroundStyle(.secondary) }
        }
        .padding(.top, 6)
    }
}

struct ToneDot: View {
    var tone: Tone
    var size: CGFloat = 9
    var body: some View { Circle().fill(tone.color).frame(width: size, height: size) }
}

/// A category tile icon in the style of the Health app: a white symbol on a coloured rounded square.
struct TileIcon: View {
    var symbol: String
    var color: Color
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

struct Bullet: View {
    var text: String
    var color: Color = .secondary
    var symbol = "circle.fill"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).font(.system(size: symbol == "circle.fill" ? 6 : 13)).foregroundStyle(color)
                .frame(width: 14)
            Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension View {
    /// The page ground behind every screen.
    func sbsGround() -> some View { background(Color.ground.ignoresSafeArea()) }
}
