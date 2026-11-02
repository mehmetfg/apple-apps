import AppKit
import SwiftUI

extension Color {
    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { a in
            let v = a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                           blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        })
    }
}

enum Theme {
    static let paper = Color.dyn(0xF7F3EC, 0x1C1B19)
    static let card = Color.dyn(0xFFFFFF, 0x272522)
    static let ink = Color.dyn(0x2B2722, 0xEDE8E0)
    static let muted = Color.dyn(0x7D756B, 0x9C958B)
    static let line = Color.dyn(0xE6DFD3, 0x3A3733)
    static let track = Color.dyn(0xEFE9DF, 0x302E2A)

    static func status(_ s: Status?) -> Color {
        switch s {
        case .done: Color.dyn(0x3E8E5E, 0x5DB37D)
        case .due: Color.dyn(0xD9822B, 0xE89A48)
        case .late: Color.dyn(0xC8463D, 0xE0665C)
        case .idle: Color.dyn(0xB9B1A5, 0x5E5953)
        case nil: Color.dyn(0xF1ECE4, 0x2C2A27)
        }
    }

    /// Colour and shape together, so the state is readable without colour.
    static func symbol(_ s: Status) -> String {
        switch s {
        case .done: "checkmark.circle.fill"
        case .due: "circle.fill"
        case .late: "exclamationmark.triangle.fill"
        case .idle: "circle"
        }
    }

    static func area(_ a: AreaID) -> Color {
        switch a {
        case .body: Color.dyn(0x2A9D8F, 0x4CC3B4)
        case .english: Color.dyn(0x3D6FB6, 0x6E9BE0)
        case .reading: Color.dyn(0x7A5BA6, 0xA88AD6)
        case .technical: Color.dyn(0xA0702A, 0xD3A050)
        case .general: Color.dyn(0x8A8378, 0xA49D93)
        }
    }

    static func areaSymbol(_ a: AreaID) -> String {
        switch a {
        case .body: "figure.strengthtraining.traditional"
        case .english: "character.bubble"
        case .reading: "book"
        case .technical: "gearshape.2"
        case .general: "pencil.line"
        }
    }

    static func serif(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}
