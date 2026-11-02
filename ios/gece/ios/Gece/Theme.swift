// Night colours: deep blue, warm light, no bright blue before sleep.
import SwiftUI

enum Theme {
    static let night = Color(red: 0.055, green: 0.067, blue: 0.118)
    static let card = Color(red: 0.10, green: 0.115, blue: 0.18)
    static let line = Color.white.opacity(0.08)
    static let ink = Color(red: 0.95, green: 0.92, blue: 0.86)
    static let soft = Color(red: 0.95, green: 0.92, blue: 0.86).opacity(0.62)
    static let amber = Color(red: 0.957, green: 0.722, blue: 0.420)
    static let rose = Color(red: 0.92, green: 0.45, blue: 0.40)
    static let sage = Color(red: 0.55, green: 0.78, blue: 0.62)

    static func painColor(_ v: Int) -> Color {
        v <= 2 ? sage : v <= 5 ? amber : rose
    }
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.line))
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}

extension Int {
    var minutesText: String {
        let m = self / 60, s = self % 60
        return s == 0 ? "\(m) dk" : m == 0 ? "\(s) sn" : "\(m) dk \(s) sn"
    }
}
