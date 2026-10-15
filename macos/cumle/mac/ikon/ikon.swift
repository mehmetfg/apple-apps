// Cümle ikonu: mavi yüzey, beyaz serif "c" ve altında yazma imleci. swift ikon/ikon.swift → ikon/Cumle.iconset
import AppKit
let klasor = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Cumle.iconset"
try? FileManager.default.createDirectory(atPath: klasor, withIntermediateDirectories: true)
for (ad, px) in [("16x16",16),("16x16@2x",32),("32x32",32),("32x32@2x",64),("128x128",128),("128x128@2x",256),("256x256",256),("256x256@2x",512),("512x512",512),("512x512@2x",1024)] {
    let s = CGFloat(px)
    let r = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: r)
    let k = NSRect(x: s*0.1, y: s*0.1, width: s*0.8, height: s*0.8)
    let yol = NSBezierPath(roundedRect: k, xRadius: s*0.18, yRadius: s*0.18)
    NSGradient(starting: NSColor(red: 0.27, green: 0.45, blue: 0.98, alpha: 1), ending: NSColor(red: 0.12, green: 0.22, blue: 0.62, alpha: 1))!.draw(in: yol, angle: -90)
    let f = NSFont(descriptor: NSFont.systemFont(ofSize: s*0.5, weight: .semibold).fontDescriptor.withDesign(.serif)!, size: s*0.5)!
    let a: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: NSColor.white]
    let m = NSAttributedString(string: "c.", attributes: a); let b = m.size()
    m.draw(at: NSPoint(x: (s - b.width)/2, y: s*0.32))
    NSColor.white.withAlphaComponent(0.85).setFill()
    NSBezierPath(roundedRect: NSRect(x: s*0.3, y: s*0.24, width: s*0.4, height: s*0.035), xRadius: s*0.02, yRadius: s*0.02).fill()
    NSGraphicsContext.restoreGraphicsState()
    try! r.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(klasor)/icon_\(ad).png"))
}
