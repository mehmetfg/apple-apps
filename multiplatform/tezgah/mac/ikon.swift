// Tezgâh ikonu v2: koyu mürekkep zemin, parlayan "T" (tabla + gövde) ve üstünde yükselen kıvılcım.
// T = Tezgâh; üç renkli şerit = Cümle · Mühendis · İdrak; kıvılcım = fikrin doğduğu an.
// Kullanım: swift ikon.swift <çıkış.png> [--tam]   (1024×1024)
import AppKit

let cikis = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "ikon.png"
let N: CGFloat = 1024
func renk(_ h: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((h >> 16) & 0xFF) / 255, green: CGFloat((h >> 8) & 0xFF) / 255,
            blue: CGFloat(h & 0xFF) / 255, alpha: a)
}
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(N), pixelsHigh: Int(N), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let tam = CommandLine.arguments.contains("--tam")
let kare = tam ? NSRect(x: 0, y: 0, width: N, height: N) : NSRect(x: 100, y: 100, width: 824, height: 824)
let yol = tam ? NSBezierPath(rect: kare) : NSBezierPath(roundedRect: kare, xRadius: 185, yRadius: 185)

let golge = NSShadow()
golge.shadowColor = NSColor.black.withAlphaComponent(0.4)
golge.shadowOffset = NSSize(width: 0, height: -14)
golge.shadowBlurRadius = 30
NSGraphicsContext.saveGraphicsState(); golge.set(); renk(0x14110E).setFill(); yol.fill()
NSGraphicsContext.restoreGraphicsState()

NSGradient(colors: [renk(0x2A2119), renk(0x0E0C0A)])!.draw(in: yol, angle: -90)

NSGraphicsContext.saveGraphicsState()
yol.addClip()
// kıvılcımın arkasında sıcak ışık
NSGradient(colors: [renk(0xF2B84B, 0.55), renk(0xF2B84B, 0)])!
    .draw(fromCenter: NSPoint(x: 512, y: 700), radius: 0, toCenter: NSPoint(x: 512, y: 700), radius: 420, options: [])
// alt köşelerde serin teal ve pas rengi yansıma
NSGradient(colors: [renk(0x3D6E60, 0.40), renk(0x3D6E60, 0)])!
    .draw(fromCenter: NSPoint(x: 150, y: 120), radius: 0, toCenter: NSPoint(x: 150, y: 120), radius: 380, options: [])
NSGradient(colors: [renk(0xB0543C, 0.35), renk(0xB0543C, 0)])!
    .draw(fromCenter: NSPoint(x: 880, y: 120), radius: 0, toCenter: NSPoint(x: 880, y: 120), radius: 360, options: [])

func kutu(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
}
// T: tabla (üç renkli şerit) + gövde
let govde = kutu(446, 214, 132, 330, 30)
NSGradient(colors: [renk(0xE9B556), renk(0xA1732F)])!.draw(in: govde, angle: -90)

let tabla = kutu(212, 500, 600, 112, 36)
NSGraphicsContext.saveGraphicsState()
tabla.addClip()
NSGradient(colors: [renk(0x4F8C7B), renk(0x3D6E60)])!.draw(in: NSRect(x: 212, y: 500, width: 200, height: 112), angle: -90)
NSGradient(colors: [renk(0xF4C766), renk(0xD9962F)])!.draw(in: NSRect(x: 412, y: 500, width: 200, height: 112), angle: -90)
NSGradient(colors: [renk(0xCC6A4D), renk(0xB0543C)])!.draw(in: NSRect(x: 612, y: 500, width: 200, height: 112), angle: -90)
NSColor.white.withAlphaComponent(0.28).setFill()
NSRect(x: 212, y: 584, width: 600, height: 10).fill()
NSGraphicsContext.restoreGraphicsState()

// kıvılcım: dört uçlu yıldız
func yildiz(_ c: NSPoint, _ R: CGFloat, _ r: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    for i in 0..<8 {
        let a = CGFloat(i) * .pi / 4 + .pi / 2
        let d = i % 2 == 0 ? R : r
        let pt = NSPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d)
        i == 0 ? p.move(to: pt) : p.line(to: pt)
    }
    p.close(); return p
}
let m = NSPoint(x: 512, y: 770)
NSGraphicsContext.saveGraphicsState()
let parla = NSShadow(); parla.shadowColor = renk(0xFFD27A, 0.9); parla.shadowBlurRadius = 60; parla.set()
NSGradient(colors: [renk(0xFFF6DC), renk(0xFFC85A)])!.draw(in: yildiz(m, 150, 28), angle: -90)
NSGraphicsContext.restoreGraphicsState()
// küçük yan kıvılcımlar
for (p, s) in [(NSPoint(x: 668, y: 850), 34.0), (NSPoint(x: 372, y: 836), 24.0)] {
    renk(0xFFE3A3).setFill(); yildiz(p, CGFloat(s), CGFloat(s) * 0.22).fill()
}
NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: cikis))
print("ikon: \(cikis)")
