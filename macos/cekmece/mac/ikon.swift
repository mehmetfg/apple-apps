// Uygulamalarım ikonunu çizer: koyu zemin üstünde dört renkli kare (dört alan). swift ikon.swift <çıktı.png>
import AppKit
let boy: CGFloat = 1024
let img = NSImage(size: NSSize(width: boy, height: boy))
img.lockFocus()
let zemin = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
NSGradient(starting: NSColor(red: 0.16, green: 0.17, blue: 0.22, alpha: 1), ending: NSColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 1))!.draw(in: zemin, angle: -90)
let renkler: [NSColor] = [
    NSColor(red: 0.48, green: 0.36, blue: 0.98, alpha: 1), NSColor(red: 0.76, green: 0.33, blue: 0.18, alpha: 1),
    NSColor(red: 0.23, green: 0.51, blue: 0.77, alpha: 1), NSColor(red: 0.88, green: 0.64, blue: 0.12, alpha: 1)]
let k: CGFloat = 270, ara: CGFloat = 54, bas = (boy - 2 * k - ara) / 2
for (i, r) in renkler.enumerated() {
    let x = bas + CGFloat(i % 2) * (k + ara), y = bas + CGFloat(1 - i / 2) * (k + ara)
    r.setFill(); NSBezierPath(roundedRect: NSRect(x: x, y: y, width: k, height: k), xRadius: 64, yRadius: 64).fill()
}
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
