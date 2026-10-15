// Teoria simgesi v2 — Tezgâh ailesi: mavi merkezli, geometrik θ (theōria — seyretmek).
// Üç sürüm (iOS 18): açık (açık mavi zemin) · koyu (gece laciverdinden siyaha) · renkli (gri tonlu, şeffaf; sistem boyar).
// Kullanım: <ikili> <çıkış.png> [acik|koyu|renkli]   (Mac .icns için koyu kullanılır)
import SwiftUI
import AppKit

enum Kip: String { case acik, koyu, renkli }

struct Ikon: View {
    let kip: Kip

    var body: some View {
        ZStack {
            zemin
            teta
        }
        .frame(width: 1024, height: 1024)
    }

    @ViewBuilder private var zemin: some View {
        switch kip {
        case .koyu:
            ZStack {
                LinearGradient(colors: [Color(hex: 0x10244F), Color(hex: 0x0B1630), Color(hex: 0x05070D)],
                               startPoint: .topTrailing, endPoint: .bottomLeading)
                RadialGradient(colors: [Color(hex: 0x3B82F6).opacity(0.55), .clear], center: .init(x: 0.68, y: 0.26), startRadius: 0, endRadius: 470)
                RadialGradient(colors: [Color(hex: 0x22D3EE).opacity(0.22), .clear], center: .init(x: 0.22, y: 0.80), startRadius: 0, endRadius: 380)
            }
        case .acik:
            ZStack {
                LinearGradient(colors: [Color(hex: 0xF4F8FF), Color(hex: 0xDCE9FF), Color(hex: 0xBCD4FF)],
                               startPoint: .topTrailing, endPoint: .bottomLeading)
                RadialGradient(colors: [Color.white.opacity(0.9), .clear], center: .init(x: 0.68, y: 0.24), startRadius: 0, endRadius: 420)
                RadialGradient(colors: [Color(hex: 0x38BDF8).opacity(0.22), .clear], center: .init(x: 0.22, y: 0.82), startRadius: 0, endRadius: 380)
            }
        case .renkli:
            Color.clear
        }
    }

    private func dolgu(_ ust: UInt32, _ alt: UInt32) -> LinearGradient {
        if kip == .renkli {
            return LinearGradient(colors: [Color(white: 1), Color(white: 0.72)], startPoint: .top, endPoint: .bottom)
        }
        return LinearGradient(colors: [Color(hex: ust), Color(hex: alt)], startPoint: .top, endPoint: .bottom)
    }

    /// θ: kalın, dikey oval halka + ortasında yatay çubuk. Tezgâh'taki bloklar gibi düz, yumuşak köşeli.
    private var teta: some View {
        ZStack {
            Ellipse()
                .strokeBorder(dolgu(0x7DD3FC, 0x2563EB), lineWidth: 92)
                .frame(width: 470, height: 640)
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(dolgu(kip == .acik ? 0x1D4ED8 : 0xBFDBFE, kip == .acik ? 0x1E40AF : 0x93C5FD))
                .frame(width: 430, height: 82)
            // halkanın üst parıltısı
            if kip != .renkli {
                Ellipse()
                    .trim(from: 0.58, to: 0.92)
                    .stroke(Color.white.opacity(kip == .acik ? 0.55 : 0.35), style: StrokeStyle(lineWidth: 20, lineCap: .round))
                    .frame(width: 408, height: 578)
            }
        }
        .shadow(color: kip == .renkli ? .clear : Color.black.opacity(kip == .koyu ? 0.55 : 0.18), radius: 40, y: 18)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

MainActor.assumeIsolated {
    let a = CommandLine.arguments
    let kip = Kip(rawValue: a.count > 2 ? a[2] : "koyu") ?? .koyu
    let r = ImageRenderer(content: Ikon(kip: kip))
    r.scale = 1
    r.isOpaque = kip != .renkli
    let rep = NSBitmapImageRep(data: r.nsImage!.tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[1]))
    print("ikon yazıldı:", kip.rawValue)
}
