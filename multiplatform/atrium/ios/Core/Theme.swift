// Colors, type and the small building blocks every screen uses.
import SwiftUI

enum Palette {
    static let accent = Color(hex: "#6C5CE7")
    static let amber = Color(hex: "#F2A541")
    static let teal = Color(hex: "#2FA37C")
    static let rose = Color(hex: "#E2546B")
    static let sky = Color(hex: "#4C9BE8")
    static let calendarRed = Color(hex: "#D64545")

    static func origin(_ o: Origin) -> Color {
        switch o {
        case .me: return amber
        case .ai: return Color(hex: "#6C8CFF")
        case .shared: return Color(hex: "#B07CFF")
        case .external: return Color(hex: "#3FBFAE")
        case .unknown: return Color.gray.opacity(0.55)
        }
    }

    static func kind(_ k: NoteKind) -> Color {
        switch k {
        case .journal: return amber
        case .idea: return Color(hex: "#F5C542")
        case .essay: return rose
        case .article: return Color(hex: "#C9487A")
        case .poem: return Color(hex: "#B07CFF")
        case .book: return teal
        case .concept: return sky
        case .note: return Color.gray
        }
    }

    /// A stable, pleasant color for an area/folder name.
    static func area(_ name: String) -> Color {
        let colors = ["#7A5CFA", "#E0703A", "#2FA37C", "#4C9BE8", "#C9487A", "#D9A021", "#3FBFAE", "#8E6CCF", "#5B8C5A", "#C2542D"]
        var h: UInt64 = 1469598103934665603
        for b in name.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return Color(hex: colors[Int(h % UInt64(colors.count))])
    }

    static var card: Color {
        #if os(iOS)
        return Color(uiColor: .secondarySystemGroupedBackground)
        #else
        return Color(nsColor: .controlBackgroundColor)
        #endif
    }

    static var page: Color {
        #if os(iOS)
        return Color(uiColor: .systemGroupedBackground)
        #else
        return Color(nsColor: .windowBackgroundColor)
        #endif
    }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        let v = UInt64(s, radix: 16) ?? 0
        self.init(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

enum Format {
    static func number(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "tr_TR")
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    static func compact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1f M", Double(n) / 1_000_000).replacingOccurrences(of: ".", with: ",") }
        if n >= 10_000 { return "\(n / 1000) B" }
        return number(n)
    }

    static func time(_ d: Date) -> String { VaultStore.timeString(d) }
}

// MARK: - Building blocks

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }
}

struct SectionTitle: View {
    var title: String
    var detail: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.bold)).fontDesign(.rounded)
            Spacer()
            if let detail { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}

struct Pill: View {
    var text: String
    var color: Color
    var symbol: String? = nil
    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.caption2.weight(.bold)) }
            Text(text).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .foregroundStyle(color)
        .background(color.opacity(0.14), in: Capsule())
    }
}

struct Appear: ViewModifier {
    var delay: Double
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .onAppear { withAnimation(.spring(response: 0.55, dampingFraction: 0.85).delay(delay)) { shown = true } }
    }
}

extension View {
    func appear(_ delay: Double = 0) -> some View { modifier(Appear(delay: delay)) }
}
