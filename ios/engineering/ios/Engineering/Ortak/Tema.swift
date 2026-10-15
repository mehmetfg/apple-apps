import SwiftUI
import UIKit

// Kâğıt zemin, mürekkep yazı, kehribar vurgu. Animasyon renkleri her ekranda aynı anlamı taşır:
// kehribar = karşılaştır · mercan = takas · mor = pivot · gök = yaz/anahtar · adaçayı = yerinde.

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    init(acik: UInt32, koyu: UInt32) {
        self.init(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: koyu) : UIColor(hex: acik) })
    }
}

enum Tema {
    static let zemin = Color(acik: 0xF6F4EF, koyu: 0x0F1114)
    static let kart = Color(acik: 0xFFFFFF, koyu: 0x1A1D22)
    static let kart2 = Color(acik: 0xEFECE4, koyu: 0x23272E)
    static let murekkep = Color(acik: 0x1B1E24, koyu: 0xECEDEF)
    static let soluk = Color(acik: 0x6B7079, koyu: 0x9AA0A9)
    static let cizgi = Color(acik: 0xE2DED4, koyu: 0x2C3038)
    static let vurgu = Color(acik: 0xD9862A, koyu: 0xF2A93B)
    static let kodZemin = Color(acik: 0x1E2128, koyu: 0x15171B)
    static let kodYazi = Color(acik: 0xE6E8EC, koyu: 0xDADDE2)

    static let cubuk = Color(acik: 0xB4BCCB, koyu: 0x535C6C)
    static let karsilastir = Color(acik: 0xF0B03C, koyu: 0xF2B544)
    static let takas = Color(acik: 0xE9604D, koyu: 0xF07462)
    static let sirali = Color(acik: 0x58B07F, koyu: 0x62C08C)
    static let pivot = Color(acik: 0x8070E8, koyu: 0x9A8CF2)
    static let yaz = Color(acik: 0x3E95D6, koyu: 0x5AAAE6)
    static let min = Color(acik: 0x22A595, koyu: 0x34BBA9)
    static let dogru = Color(acik: 0x3E9E68, koyu: 0x55B97E)
    static let yanlis = Color(acik: 0xD0574A, koyu: 0xE36E60)

    static func renk(_ i: Isaret) -> Color {
        switch i {
        case .karsilastir: karsilastir
        case .takas: takas
        case .pivot: pivot
        case .anahtar: yaz
        case .yaz: yaz
        case .min: min
        }
    }

    static func alan(_ ad: String) -> Color {
        switch ad {
        case "amber": Color(acik: 0xD9862A, koyu: 0xF2A93B)
        case "teal": Color(acik: 0x1F9C8F, koyu: 0x34BBA9)
        case "coral": Color(acik: 0xE0604E, koyu: 0xF07462)
        case "violet": Color(acik: 0x7A68E0, koyu: 0x9A8CF2)
        case "sky": Color(acik: 0x3889C8, koyu: 0x5AAAE6)
        case "olive": Color(acik: 0x87913A, koyu: 0xA7B155)
        case "sage": Color(acik: 0x58A07A, koyu: 0x6CC193)
        case "rust": Color(acik: 0xB35C2E, koyu: 0xD27A4A)
        case "rose": Color(acik: 0xC9577E, koyu: 0xE07A9C)
        case "indigo": Color(acik: 0x4B5BC4, koyu: 0x7484E6)
        case "plum": Color(acik: 0x9A4F9E, koyu: 0xBE75C2)
        default: Color(acik: 0x5E6878, koyu: 0x8D97A8)
        }
    }

    static func baslik(_ boyut: Font.TextStyle = .title2) -> Font { .system(boyut, design: .rounded, weight: .bold) }
    static let kod = Font.system(size: 13, design: .monospaced)
    static let kodKucuk = Font.system(size: 11.5, design: .monospaced)
}

// MARK: - Yüzeyler

struct KartYuzey: ViewModifier {
    var dolgu: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(dolgu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tema.kart, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Tema.cizgi, lineWidth: 0.5))
    }
}

extension View {
    func kartYuzey(_ dolgu: CGFloat = 16) -> some View { modifier(KartYuzey(dolgu: dolgu)) }
}

struct AnaDugme: ButtonStyle {
    var renk: Color = Tema.murekkep
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded))
            .foregroundStyle(Tema.zemin)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(renk, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

struct IkinciDugme: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(Tema.murekkep)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Tema.kart2, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

/// Seçenek düğmesi: nötr → doğru (yeşil) / yanlış (kırmızı) / soluk.
struct SecenekDugme: View {
    enum Durum { case notr, dogru, yanlis, soluk }
    let metin: String
    var kod = false
    var durum: Durum = .notr
    let eylem: () -> Void

    var body: some View {
        Button(action: eylem) {
            HStack(spacing: 10) {
                Text(metin)
                    .font(kod ? Tema.kod : .system(.body, design: .rounded))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if durum == .dogru { Image(systemName: "checkmark.circle.fill").foregroundStyle(Tema.dogru) }
                if durum == .yanlis { Image(systemName: "xmark.circle.fill").foregroundStyle(Tema.yanlis) }
            }
            .foregroundStyle(Tema.murekkep.opacity(durum == .soluk ? 0.45 : 1))
            .padding(.horizontal, 16).padding(.vertical, 13)
            .background(arka, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(kenar, lineWidth: durum == .notr ? 0.5 : 1.5))
        }
        .buttonStyle(.plain)
    }

    private var arka: Color {
        switch durum {
        case .dogru: Tema.dogru.opacity(0.12)
        case .yanlis: Tema.yanlis.opacity(0.12)
        default: Tema.kart
        }
    }
    private var kenar: Color {
        switch durum {
        case .dogru: Tema.dogru
        case .yanlis: Tema.yanlis
        default: Tema.cizgi
        }
    }
}

struct Etiket: View {
    let metin: String
    var renk: Color = Tema.soluk
    var body: some View {
        Text(metin)
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(renk)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(renk.opacity(0.12), in: Capsule())
    }
}

/// Türkçe destek: varsayılan kapalı; dokununca açılır.
struct TurkceDestek: View {
    let metin: String
    @State private var acik = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.snappy) { acik.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Text("TR").font(.system(.caption2, design: .rounded, weight: .heavy))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Tema.soluk.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                    Text(acik ? "Gizle" : "Türkçe destek").font(.caption)
                }
                .foregroundStyle(Tema.soluk)
            }
            .buttonStyle(.plain)
            if acik {
                Text(metin)
                    .font(.callout)
                    .foregroundStyle(Tema.soluk)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

enum Dokunma {
    static func basari() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func hata() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func hafif() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}
