// Görsel dil: sakin mavi zemin, kehribar vurgu (ikondaki nokta), İngilizce metin serif (New York).
import SwiftUI

enum Tema {
    static let vurgu = Color(red: 0.27, green: 0.38, blue: 0.93)
    static let vurguKoyu = Color(red: 0.17, green: 0.25, blue: 0.70)
    static let kehribar = Color(red: 1.0, green: 0.74, blue: 0.30)
    /// Beyaz zeminde yazı için koyu kehribar (okunurluk).
    static let kehribarYazi = Color(red: 0.78, green: 0.48, blue: 0.02)
    static let yesil = Color(red: 0.20, green: 0.66, blue: 0.45)
    static let sari = Color(red: 0.98, green: 0.80, blue: 0.25)

    static let egim = LinearGradient(colors: [Color(red: 0.34, green: 0.47, blue: 0.96), Color(red: 0.16, green: 0.24, blue: 0.70)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)

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
}

extension View {
    /// Kart zemini: açıkta beyaz, koyuda yükseltilmiş gri.
    func kart(_ ic: CGFloat = 16) -> some View {
        self.padding(ic)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }
}
