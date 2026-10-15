// Zemin çizimi: düz · gradyan · mesh · desen · fotoğraf, üstüne karartma · vinyet · tane.
// `faz` (0…1) hareket içindir: mesh akar, desen kayar, fotoğraf yavaşça yakınlaşır. Duruk görüntüde 0.
import SwiftUI

struct Tohum: RandomNumberGenerator {
    private var s: UInt64
    init(_ t: Int) { s = UInt64(bitPattern: Int64(t)) &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        s &+= 0x9E3779B97F4A7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func oran() -> Double { Double(next() >> 11) / Double(1 << 53) }
}

struct ZeminGorunum: View {
    var zemin: Zemin
    var faz: Double = 0
    var fotoBoyu: CGFloat = 1600     // widget'ta küçük, duvarda büyük okunur

    var body: some View {
        GeometryReader { g in
            ZStack {
                taban(g.size)
                if zemin.karartma > 0 {
                    Color.black.opacity(zemin.karartma)
                } else if zemin.karartma < 0 {
                    Color.white.opacity(-zemin.karartma)
                }
                if zemin.vinyet > 0 {
                    RadialGradient(colors: [.clear, .black.opacity(0.75 * zemin.vinyet)], center: .center,
                                   startRadius: min(g.size.width, g.size.height) * 0.25,
                                   endRadius: max(g.size.width, g.size.height) * 0.75)
                }
                if zemin.tane > 0 {
                    Image(uiImage: Gren.doku)
                        .resizable(resizingMode: .tile)
                        .blendMode(.overlay)
                        .opacity(0.55 * zemin.tane)
                }
            }
            .frame(width: g.size.width, height: g.size.height)
            .clipped()
        }
    }

    @ViewBuilder private func taban(_ s: CGSize) -> some View {
        switch zemin.tur {
        case .duz:
            zemin.renk(0)
        case .gradyan:
            let a = zemin.aci * .pi / 180
            let dx = cos(a) / 2, dy = sin(a) / 2
            LinearGradient(colors: Array(zemin.renkler.prefix(3)).map { Color(hex: $0) },
                           startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy),
                           endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy))
                .hueRotation(.degrees(faz * 12))
        case .mesh:
            Mesh(zemin: zemin, faz: faz)
        case .desen:
            ZStack {
                LinearGradient(colors: [zemin.renk(0), zemin.renk(zemin.desen == .yildizlar ? 1 : 0).opacity(zemin.desen == .yildizlar ? 1 : 0.92)],
                               startPoint: .top, endPoint: .bottom)
                Canvas { c, boy in Desen.ciz(&c, boy: boy, zemin: zemin, faz: faz) }
            }
        case .foto:
            if let img = Depo.gorsel(zemin.foto, enUzun: fotoBoyu) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: s.width, height: s.height)
                    .scaleEffect(1 + 0.08 * faz)
                    .blur(radius: zemin.bulanik * min(s.width, s.height) / 430)
                    .clipped()
            } else {
                ZStack {
                    zemin.renk(0)
                    Image(systemName: "photo").font(.system(size: min(s.width, s.height) * 0.2)).foregroundStyle(.white.opacity(0.3))
                }
            }
        }
    }
}

/// 3×3 mesh: köşeler sabit, kenar ortaları kendi kenarı üzerinde, merkez serbest kayar.
struct Mesh: View {
    var zemin: Zemin
    var faz: Double

    var body: some View {
        var r = Tohum(zemin.tohum &* 7919 &+ 13)
        let sapma: [(Double, Double)] = (0..<9).map { _ in (r.oran() * 2 - 1, r.oran() * 2 - 1) }
        let evre: [Double] = (0..<9).map { _ in r.oran() }
        func nokta(_ i: Int) -> SIMD2<Float> {
            let x0 = Double(i % 3) / 2, y0 = Double(i / 3) / 2
            let tit = 0.09 * sin(2 * .pi * (faz + evre[i]))
            var x = x0, y = y0
            let kenarX = (i % 3 == 0 || i % 3 == 2), kenarY = (i / 3 == 0 || i / 3 == 2)
            if !kenarX { x += 0.22 * sapma[i].0 + tit }
            if !kenarY { y += 0.22 * sapma[i].1 + 0.7 * tit }
            return SIMD2(Float(min(1, max(0, x))), Float(min(1, max(0, y))))
        }
        var sira = [0, 1, 0, 1, 2, 0, 2, 3, 1]
        sira.shuffle(using: &r)
        let renkler = sira.map { zemin.renk($0) }
        return MeshGradient(width: 3, height: 3, points: (0..<9).map(nokta), colors: renkler, smoothsColors: true)
    }
}

enum Desen {
    static func ciz(_ c: inout GraphicsContext, boy s: CGSize, zemin z: Zemin, faz f: Double) {
        var r = Tohum(z.tohum &* 31 &+ 101)
        let a = z.renk(2), b = z.renk(3)
        let birim = s.width / 14
        switch z.desen {
        case .noktalar:
            let ara = birim
            var y = -ara + (f * ara).truncatingRemainder(dividingBy: ara)
            var satir = 0
            while y < s.height + ara {
                var x = (satir % 2 == 0 ? 0 : ara / 2)
                while x < s.width + ara {
                    let rr = ara * 0.085
                    c.fill(Path(ellipseIn: CGRect(x: x - rr, y: y - rr, width: rr * 2, height: rr * 2)), with: .color(b.opacity(0.32)))
                    x += ara
                }
                y += ara * 0.866; satir += 1
            }
        case .cizgiler:
            let ara = s.width / 16
            var p = Path()
            var x = -s.height + (f * ara * 2).truncatingRemainder(dividingBy: ara)
            while x < s.width {
                p.move(to: CGPoint(x: x, y: s.height)); p.addLine(to: CGPoint(x: x + s.height, y: 0)); x += ara
            }
            c.stroke(p, with: .color(b.opacity(0.18)), lineWidth: max(0.8, s.width / 360))
        case .izgara:
            let ara = s.width / 12
            var ince = Path(), kalin = Path()
            var i = 0
            var x: CGFloat = (f * ara).truncatingRemainder(dividingBy: ara)
            while x < s.width {
                let a0 = CGPoint(x: x, y: 0), a1 = CGPoint(x: x, y: s.height)
                if i % 4 == 0 { kalin.move(to: a0); kalin.addLine(to: a1) } else { ince.move(to: a0); ince.addLine(to: a1) }
                x += ara; i += 1
            }
            i = 0
            var y: CGFloat = 0
            while y < s.height {
                let a0 = CGPoint(x: 0, y: y), a1 = CGPoint(x: s.width, y: y)
                if i % 4 == 0 { kalin.move(to: a0); kalin.addLine(to: a1) } else { ince.move(to: a0); ince.addLine(to: a1) }
                y += ara; i += 1
            }
            c.stroke(ince, with: .color(b.opacity(0.10)), lineWidth: max(0.5, s.width / 600))
            c.stroke(kalin, with: .color(b.opacity(0.22)), lineWidth: max(1, s.width / 300))
        case .dalga:
            let n = 26
            for k in 0..<n {
                let y0 = s.height * (Double(k) + 0.5) / Double(n)
                let gen = s.height / Double(n) * 0.9
                var p = Path()
                var x: CGFloat = 0
                p.move(to: CGPoint(x: 0, y: y0))
                while x <= s.width {
                    let t = x / s.width
                    let y = y0 + gen * sin(2 * .pi * (t * 1.6 + Double(k) * 0.07 + f)) * (0.6 + 0.4 * sin(Double(k) * 0.5))
                    p.addLine(to: CGPoint(x: x, y: y)); x += s.width / 90
                }
                c.stroke(p, with: .color((k % 2 == 0 ? a : b).opacity(0.30)), lineWidth: max(0.8, s.width / 320))
            }
        case .topografya:
            let merkezler = (0..<3).map { _ in CGPoint(x: r.oran() * s.width, y: r.oran() * s.height) }
            let tohumlar = (0..<3).map { _ in r.oran() * 6 }
            let adim = s.width / 22
            for (m, mz) in merkezler.enumerated() {
                for k in 1...14 {
                    let r0 = Double(k) * adim
                    var p = Path()
                    for i in 0...120 {
                        let t = Double(i) / 120 * 2 * .pi
                        let rr = r0 * (1 + 0.10 * sin(3 * t + tohumlar[m] + f * 2 * .pi) + 0.06 * sin(5 * t + Double(k) * 0.3))
                        let pt = CGPoint(x: mz.x + rr * cos(t), y: mz.y + rr * sin(t))
                        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                    }
                    p.closeSubpath()
                    c.stroke(p, with: .color((k % 5 == 0 ? b : a).opacity(k % 5 == 0 ? 0.42 : 0.24)), lineWidth: max(0.7, s.width / (k % 5 == 0 ? 220 : 400)))
                }
            }
        case .yildizlar:
            let n = Int(s.width * s.height / 2200)
            for _ in 0..<min(n, 900) {
                let x = r.oran() * s.width, y = r.oran() * s.height
                let boy = (r.oran() * r.oran()) * s.width / 170 + s.width / 1400
                let ev = r.oran()
                let parla = 0.35 + 0.65 * (0.5 + 0.5 * sin(2 * .pi * (f * 2 + ev)))
                c.fill(Path(ellipseIn: CGRect(x: x, y: y, width: boy, height: boy)), with: .color(Color.white.opacity(parla * (0.4 + 0.6 * ev))))
            }
            for _ in 0..<5 {
                let x = r.oran() * s.width, y = r.oran() * s.height * 0.7
                let boy = s.width / 22
                c.fill(Path(ellipseIn: CGRect(x: x - boy, y: y - boy, width: boy * 2, height: boy * 2)),
                       with: .radialGradient(Gradient(colors: [b.opacity(0.55), .clear]), center: CGPoint(x: x, y: y), startRadius: 0, endRadius: boy))
            }
        case .bauhaus:
            let renkler = [z.renk(1), z.renk(2), z.renk(3)]
            let kay = 0.04 * sin(2 * .pi * f)
            for i in 0..<6 {
                let x = r.oran() * s.width, y = r.oran() * s.height
                let boy = (0.25 + r.oran() * 0.45) * s.width
                let renk = renkler[i % 3].opacity(0.88)
                let mx = x + kay * s.width * (i % 2 == 0 ? 1 : -1)
                switch i % 3 {
                case 0:
                    c.fill(Path(ellipseIn: CGRect(x: mx - boy / 2, y: y - boy / 2, width: boy, height: boy)), with: .color(renk))
                case 1:
                    var p = Path()
                    p.addArc(center: CGPoint(x: mx, y: y), radius: boy / 2, startAngle: .degrees(Double(i) * 45), endAngle: .degrees(Double(i) * 45 + 180), clockwise: false)
                    p.closeSubpath()
                    c.fill(p, with: .color(renk))
                default:
                    c.fill(Path(CGRect(x: mx - boy * 0.3, y: y - boy * 0.12, width: boy * 0.6, height: boy * 0.24)), with: .color(renk))
                }
            }
        }
    }
}

/// Film tanesi: 128 px'lik sabit gürültü karosu, bir kez üretilir.
enum Gren {
    static let doku: UIImage = {
        let n = 128
        var r = Tohum(42)
        var px = [UInt8](repeating: 0, count: n * n * 4)
        for i in 0..<(n * n) {
            let v = UInt8(min(255, max(0, 128 + (r.oran() - 0.5) * 200)))
            px[i * 4] = v; px[i * 4 + 1] = v; px[i * 4 + 2] = v; px[i * 4 + 3] = 255
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: &px, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let cg = ctx?.makeImage() else { return UIImage() }
        return UIImage(cgImage: cg, scale: 2, orientation: .up)
    }()
}
