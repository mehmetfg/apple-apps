// Çizimler: yasaların ve oyunların küçük resimleri. Sistem simgesi değil; her resim yasanın hareketini gösterir
// (talep: zincir · mesafe: uzaklaşan halkalar · merdiven: bir basamak iniş · ayna: zamanda geriye bakış …).
// 100×100'lük bir tuvalde çizilir, istenen boya ölçeklenir. Zemin: tonun açık hâli; çizgi: tonun kendisi.
import SwiftUI

struct Cizim: View {
    /// Yasa kimliği (talep, mesafe, …) ya da "oyun-<ad>"
    let ad: String
    var renk: Color = Tema.vurgu
    var boy: CGFloat = 56
    var zemin = true

    var body: some View {
        Canvas { c, b in
            let o = min(b.width, b.height) / 100
            c.translateBy(x: (b.width - 100 * o) / 2, y: (b.height - 100 * o) / 2)
            c.scaleBy(x: o, y: o)
            Self.ciz(ad, &c, renk)
        }
        .frame(width: boy, height: boy)
        .background {
            if zemin {
                RoundedRectangle(cornerRadius: boy * 0.3, style: .continuous).fill(renk.opacity(0.13))
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Çizim yardımcıları

    private static func cizgi(_ c: inout GraphicsContext, _ p: Path, _ r: Color, _ w: CGFloat = 4.5, kesik: Bool = false) {
        c.stroke(p, with: .color(r), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round, dash: kesik ? [5, 6] : []))
    }
    private static func dolu(_ c: inout GraphicsContext, _ p: Path, _ r: Color) { c.fill(p, with: .color(r)) }
    private static func hap(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: h / 2)
    }
    private static func nokta(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }
    /// Uçta küçük ok başı olan eğri
    private static func ok(_ c: inout GraphicsContext, _ a: CGPoint, _ b: CGPoint, _ k: CGPoint, _ r: Color, w: CGFloat = 4) {
        var p = Path(); p.move(to: a); p.addQuadCurve(to: b, control: k)
        cizgi(&c, p, r, w)
        let aci = atan2(b.y - k.y, b.x - k.x), u: CGFloat = 7
        var bas = Path()
        bas.move(to: CGPoint(x: b.x - u * cos(aci - 0.5), y: b.y - u * sin(aci - 0.5)))
        bas.addLine(to: b)
        bas.addLine(to: CGPoint(x: b.x - u * cos(aci + 0.5), y: b.y - u * sin(aci + 0.5)))
        cizgi(&c, bas, r, w)
    }

    static func ciz(_ ad: String, _ c: inout GraphicsContext, _ r: Color) {
        let acik = r.opacity(0.35)
        switch ad {
        case "talep", "oyun-motor":
            // üç parça zincir: her biri sonrakinin biçimini ister; zaman yalnız ilkine biner (dolu)
            dolu(&c, hap(8, 56, 24, 16), r)
            cizgi(&c, hap(38, 56, 24, 16), r, 4)
            cizgi(&c, hap(68, 56, 24, 16), r, 4)
            ok(&c, CGPoint(x: 22, y: 50), CGPoint(x: 46, y: 50), CGPoint(x: 34, y: 30), r)
            ok(&c, CGPoint(x: 52, y: 50), CGPoint(x: 76, y: 50), CGPoint(x: 64, y: 30), r)
        case "mesafe":
            dolu(&c, nokta(22, 50, 8), r)
            for (i, rr) in [CGFloat(20), 34, 48].enumerated() {
                var p = Path()
                p.addArc(center: CGPoint(x: 22, y: 50), radius: rr, startAngle: .degrees(-42), endAngle: .degrees(42), clockwise: false)
                cizgi(&c, p, r.opacity(1 - Double(i) * 0.28), 4.5)
            }
        case "merdiven", "oyun-merdiven":
            var p = Path()
            p.move(to: CGPoint(x: 12, y: 30)); p.addLine(to: CGPoint(x: 38, y: 30)); p.addLine(to: CGPoint(x: 38, y: 52))
            p.addLine(to: CGPoint(x: 62, y: 52)); p.addLine(to: CGPoint(x: 62, y: 74)); p.addLine(to: CGPoint(x: 88, y: 74))
            cizgi(&c, p, acik, 5)
            dolu(&c, nokta(25, 21, 6), r)
            ok(&c, CGPoint(x: 33, y: 18), CGPoint(x: 52, y: 42), CGPoint(x: 50, y: 18), r)
            dolu(&c, nokta(75, 65, 5), r.opacity(0.55))
        case "ayna":
            var t = Path(); t.move(to: CGPoint(x: 10, y: 66)); t.addLine(to: CGPoint(x: 90, y: 66))
            cizgi(&c, t, acik, 4)
            dolu(&c, nokta(70, 66, 7), r)
            cizgi(&c, nokta(30, 66, 6), r, 3.5)
            ok(&c, CGPoint(x: 70, y: 54), CGPoint(x: 32, y: 52), CGPoint(x: 51, y: 22), r)
        case "kuyruk":
            cizgi(&c, hap(10, 42, 32, 18), r.opacity(0.5), 3.5, kesik: true)
            dolu(&c, hap(50, 42, 40, 18), r)
            var k = Path(); k.move(to: CGPoint(x: 16, y: 36)); k.addLine(to: CGPoint(x: 36, y: 66))
            cizgi(&c, k, r.opacity(0.6), 3.5)
        case "isik", "oyun-hata":
            if ad == "isik" {
                dolu(&c, nokta(24, 58, 9), acik)
                ok(&c, CGPoint(x: 38, y: 58), CGPoint(x: 52, y: 58), CGPoint(x: 45, y: 58), r.opacity(0.7), w: 3.5)
                dolu(&c, nokta(72, 58, 13), r)
                for i in 0..<7 {
                    let a = Double(i) / 7 * 2 * .pi - .pi / 2
                    var p = Path()
                    p.move(to: CGPoint(x: 72 + cos(a) * 19, y: 58 + sin(a) * 19))
                    p.addLine(to: CGPoint(x: 72 + cos(a) * 25, y: 58 + sin(a) * 25))
                    cizgi(&c, p, r, 3.5)
                }
            } else {
                // cümle satırı, bir kelime halkaya alınmış
                for (x, w) in [(CGFloat(10), CGFloat(18)), (32, 22), (58, 14), (76, 14)] {
                    dolu(&c, hap(x, 46, w, 10), x == 32 ? r : acik)
                }
                cizgi(&c, Path(ellipseIn: CGRect(x: 25, y: 33, width: 36, height: 36)), r, 3.5)
                var s = Path(); s.move(to: CGPoint(x: 55, y: 64)); s.addLine(to: CGPoint(x: 66, y: 76))
                cizgi(&c, s, r, 5)
            }
        case "anahtar":
            dolu(&c, hap(10, 26, 38, 16), r)
            cizgi(&c, hap(52, 58, 38, 16), r, 4)
            ok(&c, CGPoint(x: 50, y: 34), CGPoint(x: 70, y: 52), CGPoint(x: 70, y: 34), r, w: 3.5)
            ok(&c, CGPoint(x: 50, y: 66), CGPoint(x: 30, y: 48), CGPoint(x: 30, y: 66), r.opacity(0.6), w: 3.5)
        case "kapsul":
            cizgi(&c, hap(12, 34, 76, 32), r, 4.5)
            var y = Path(); y.addRoundedRect(in: CGRect(x: 12, y: 34, width: 38, height: 32), cornerSize: CGSize(width: 16, height: 16))
            dolu(&c, y, acik)
            ok(&c, CGPoint(x: 36, y: 50), CGPoint(x: 68, y: 50), CGPoint(x: 52, y: 50), r, w: 4)
        case "olcek":
            var cz = Path(); cz.move(to: CGPoint(x: 10, y: 62)); cz.addLine(to: CGPoint(x: 90, y: 62))
            cizgi(&c, cz, r, 4.5)
            for i in 0...8 {
                let x = 10 + CGFloat(i) * 10
                var t = Path(); t.move(to: CGPoint(x: x, y: 62)); t.addLine(to: CGPoint(x: x, y: i % 4 == 0 ? 48 : 55))
                cizgi(&c, t, acik, 3)
            }
            var u = Path()
            u.move(to: CGPoint(x: 68, y: 40)); u.addLine(to: CGPoint(x: 61, y: 28)); u.addLine(to: CGPoint(x: 75, y: 28)); u.closeSubpath()
            dolu(&c, u, r)
        case "konum":
            // at: nokta · on: yüzeyde · in: kabın içinde
            dolu(&c, nokta(18, 50, 6), r)
            var y = Path(); y.move(to: CGPoint(x: 36, y: 60)); y.addLine(to: CGPoint(x: 60, y: 60))
            cizgi(&c, y, acik, 4)
            dolu(&c, nokta(48, 52, 6), r)
            cizgi(&c, Path(roundedRect: CGRect(x: 68, y: 36, width: 24, height: 28), cornerRadius: 5), acik, 4)
            dolu(&c, nokta(80, 52, 6), r)
        case "oyun-hafiza":
            for (i, (x, y)) in [(CGFloat(18), CGFloat(18)), (52, 18), (18, 52), (52, 52)].enumerated() {
                let p = Path(roundedRect: CGRect(x: x, y: y, width: 30, height: 30), cornerRadius: 8)
                if i == 1 { dolu(&c, p, r) } else { cizgi(&c, p, i == 2 ? r : acik, 4) }
            }
        case "oyun-kule":
            for (i, (x, w)) in [(CGFloat(18), CGFloat(64)), (24, 52), (30, 40), (38, 26)].enumerated() {
                let p = Path(roundedRect: CGRect(x: x, y: 74 - CGFloat(i) * 16, width: w, height: 12), cornerRadius: 4)
                if i == 3 { dolu(&c, p, r) } else { dolu(&c, p, r.opacity(0.3 + 0.12 * Double(i))) }
            }
        case "oyun-termometre":
            cizgi(&c, hap(42, 12, 16, 60), acik, 4)
            dolu(&c, nokta(50, 78, 11), r)
            dolu(&c, hap(46, 38, 8, 40), r)
            for i in 0..<4 {
                var t = Path(); t.move(to: CGPoint(x: 64, y: 20 + CGFloat(i) * 14)); t.addLine(to: CGPoint(x: 74, y: 20 + CGFloat(i) * 14))
                cizgi(&c, t, acik, 3)
            }
        case "oyun-bag":
            let a = CGPoint(x: 20, y: 68), b = CGPoint(x: 80, y: 68), m = CGPoint(x: 50, y: 30)
            var p = Path(); p.move(to: a); p.addLine(to: m); p.addLine(to: b)
            cizgi(&c, p, acik, 4)
            dolu(&c, nokta(a.x, a.y, 9), r.opacity(0.6))
            dolu(&c, nokta(b.x, b.y, 9), r.opacity(0.6))
            dolu(&c, nokta(m.x, m.y, 12), r)
        case "adim-kart":
            var a = Path(); a.addRoundedRect(in: CGRect(x: 30, y: 16, width: 46, height: 60), cornerSize: CGSize(width: 9, height: 9))
            cizgi(&c, a.applying(CGAffineTransform(rotationAngle: 0.16).concatenating(.init(translationX: 6, y: -6))), acik, 4)
            dolu(&c, Path(roundedRect: CGRect(x: 22, y: 26, width: 46, height: 60), cornerRadius: 9), r)
            for (y, w) in [(CGFloat(42), CGFloat(28)), (54, 20), (66, 24)] {
                dolu(&c, hap(30, y, w, 6), Color.white.opacity(0.85))
            }
        case "adim-quiz":
            for i in 0..<3 {
                let y = 24 + CGFloat(i) * 22
                let kutu = Path(roundedRect: CGRect(x: 16, y: y, width: 16, height: 16), cornerRadius: 4)
                if i == 0 { dolu(&c, kutu, r) } else { cizgi(&c, kutu, acik, 3.5) }
                dolu(&c, hap(40, y + 5, i == 1 ? 32 : 44, 6), i == 0 ? r : acik)
            }
        default:
            dolu(&c, nokta(50, 50, 12), r)
        }
    }
}
