// Alan renkleri ve küçük görsel parçalar — Mac ve iPhone ortak.
import SwiftUI

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        let v = UInt64(s, radix: 16) ?? 0x888888
        self.init(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
    static let kivilcim = Color(hex: "#FF6A3D")      // kayıt rengi: kor
    static let kivilcimKoyu = Color(hex: "#C9431E")
}

extension Alan { var color: Color { Color(hex: renk) } }

/// Alan rozetini (renkli nokta + ad) ve amaç simgesini birlikte gösterir.
struct SinifRozeti: View {
    let alan: Alan
    let amac: Amac
    var kucuk = false
    var body: some View {
        HStack(spacing: 6) {
            Label(alan.ad, systemImage: alan.simge)
                .labelStyle(.titleAndIcon)
                .foregroundStyle(alan.color)
            Text("·").foregroundStyle(.tertiary)
            Label(amac.ad, systemImage: amac.simge)
                .foregroundStyle(.secondary)
        }
        .font(kucuk ? .caption2.weight(.medium) : .caption.weight(.medium))
        .lineLimit(1)
    }
}

/// Ses düzeyi çubukları (kayıt sırasında).
struct DuzeyCubuklari: View {
    let seviyeler: [Float]
    var renk: Color = .kivilcim
    var adet = 28
    var body: some View {
        GeometryReader { g in
            let son = Array(seviyeler.suffix(adet))
            let dolu = Array(repeating: Float(0.04), count: max(0, adet - son.count)) + son
            HStack(alignment: .center, spacing: 2) {
                ForEach(dolu.indices, id: \.self) { i in
                    Capsule()
                        .fill(renk.opacity(0.35 + Double(dolu[i]) * 0.65))
                        .frame(width: max(1.5, (g.size.width - CGFloat(adet - 1) * 2) / CGFloat(adet)),
                               height: max(3, g.size.height * CGFloat(dolu[i])))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeOut(duration: 0.08), value: seviyeler.count)
        }
    }
}
