// Renk ve biçim dili. Alan renkleri sabit (her süreç alanının rengini taşır), durum renkleri anlam taşır.
import SwiftUI

enum Tema {
    static func alan(_ id: String) -> Color {
        switch id {
        case "felsefe": Color(red: 0.49, green: 0.42, blue: 0.95)   // çivit
        case "ingilizce": Color(red: 0.13, green: 0.70, blue: 0.67) // deniz
        case "teknik": Color(red: 0.96, green: 0.55, blue: 0.20)    // bakır
        case "yazilim": Color(red: 0.24, green: 0.56, blue: 0.98)   // mavi
        case "vault": Color(red: 0.91, green: 0.36, blue: 0.53)     // gül
        default: .gray
        }
    }

    static func alanSimge(_ id: String) -> String {
        switch id {
        case "felsefe": "building.columns"
        case "ingilizce": "character.bubble"
        case "teknik": "gearshape.2"
        case "yazilim": "curlybraces"
        case "vault": "books.vertical"
        default: "circle"
        }
    }

    static func durum(_ d: Durum) -> Color {
        switch d {
        case .akiyor: Color(red: 0.20, green: 0.78, blue: 0.47)
        case .gecikti: Color(red: 0.98, green: 0.76, blue: 0.18)
        case .aksiyor: Color(red: 0.98, green: 0.50, blue: 0.16)
        case .tikali: Color(red: 0.94, green: 0.25, blue: 0.27)
        case .baslamadi: Color(red: 0.62, green: 0.55, blue: 0.80)
        case .uykuda: Color.gray.opacity(0.55)
        case .gorunmuyor: Color.gray.opacity(0.35)
        }
    }

    static func durumSimge(_ d: Durum) -> String {
        switch d {
        case .akiyor: "waveform.path"
        case .gecikti: "clock"
        case .aksiyor: "exclamationmark.triangle"
        case .tikali: "xmark.octagon"
        case .baslamadi: "circle.dotted"
        case .uykuda: "moon.zzz"
        case .gorunmuyor: "eye.slash"
        }
    }

    static func nabiz(_ n: Int) -> Color {
        n >= 75 ? durum(.akiyor) : n >= 50 ? durum(.gecikti) : n >= 30 ? durum(.aksiyor) : durum(.tikali)
    }

    static func bicimSimge(_ b: String) -> String {
        switch b {
        case "halka": "circle.circle"
        case "merdiven": "stairs"
        case "depo": "cylinder.split.1x2"
        case "kitaplik": "books.vertical"
        default: "waveform"
        }
    }

    // Orkestra her yerde koyu: siyaha yakın zemin, buzlu cam kartlar
    static let zemin = Color(red: 0.024, green: 0.027, blue: 0.035)
    static let kart = Color.white.opacity(0.055)
    static let cizgi = Color.white.opacity(0.09)
}

extension Font {
    static func yuvarlak(_ boy: CGFloat, _ agirlik: Font.Weight = .semibold) -> Font {
        .system(size: boy, weight: agirlik, design: .rounded)
    }
}
