// Tezgâh iPhone ikonu — mavi/siyah: gece laciverti zemin, mavi ışık, tezgâh (tabla + iki ayak) ve üç mavi blok.
// iOS kendi köşe maskesini uygular; çizim köşesiz tam kare (1024×1024).
// Kullanım: ikon.swift → derlenip çalıştırılır (onizleme/calistir.sh'daki swiftc ayarlarıyla)
//   <ikili> Tezgah.swiftpm/Assets.xcassets/AppIcon.appiconset/ikon-1024.png
import AppKit

let cikis = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "ikon-1024.png"
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
let kare = NSRect(x: 0, y: 0, width: N, height: N)

// zemin: siyahtan gece laciverdine
NSGradient(colors: [renk(0x05070D), renk(0x0B1630), renk(0x10244F)])!.draw(in: kare, angle: 70)

// mavi ışık lekeleri
NSGradient(colors: [renk(0x3B82F6, 0.55), renk(0x3B82F6, 0)])!
    .draw(fromCenter: NSPoint(x: 700, y: 760), radius: 0, toCenter: NSPoint(x: 700, y: 760), radius: 470, options: [])
NSGradient(colors: [renk(0x22D3EE, 0.22), renk(0x22D3EE, 0)])!
    .draw(fromCenter: NSPoint(x: 230, y: 220), radius: 0, toCenter: NSPoint(x: 230, y: 220), radius: 380, options: [])

func kutu(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat, _ ust: NSColor, _ alt: NSColor) {
    let yol = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
    NSGradient(colors: [alt, ust])!.draw(in: yol, angle: 90)
}

// yumuşak gölge altlık
NSGraphicsContext.saveGraphicsState()
let golge = NSShadow()
golge.shadowColor = NSColor.black.withAlphaComponent(0.55)
golge.shadowOffset = NSSize(width: 0, height: -18)
golge.shadowBlurRadius = 40
golge.set()

// ayaklar
kutu(262, 236, 58, 250, 14, renk(0x1E3A8A), renk(0x172554))
kutu(704, 236, 58, 250, 14, renk(0x1E3A8A), renk(0x172554))
// tabla
kutu(212, 470, 600, 78, 26, renk(0x3B82F6), renk(0x1D4ED8))
// üç blok: Mühendis · Cümle · İdrak — üç ton mavi
kutu(262, 560, 132, 196, 26, renk(0x7DD3FC), renk(0x38BDF8))
kutu(446, 560, 132, 284, 26, renk(0x60A5FA), renk(0x2563EB))
kutu(630, 560, 132, 236, 26, renk(0xBFDBFE), renk(0x93C5FD))
NSGraphicsContext.restoreGraphicsState()

// tablanın üst parıltısı
kutu(212, 524, 600, 24, 12, renk(0x93C5FD, 0.55), renk(0x60A5FA, 0.25))

NSGraphicsContext.restoreGraphicsState()
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: cikis))
print(cikis)
