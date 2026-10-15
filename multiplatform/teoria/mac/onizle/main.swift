// Teoria önizleyici — widget'ları ve ekranları iPhone 6.9" ölçüsünde PNG'ye çizer (Xcode gerekmez).
// Kullanım: zsh mac/onizle.sh  →  onizleme/*.png
import SwiftUI
import WidgetKit
import AppKit

@MainActor
func ciz<V: View>(_ v: V, _ boyut: CGSize, _ sema: ColorScheme, _ ad: String, zemin: Color, kose: CGFloat = 24, ic: CGFloat = 16) {
    let gorunum = v.padding(ic)
        .frame(width: boyut.width, height: boyut.height)
        .background(WZemin(renk: zemin))
        .clipShape(RoundedRectangle(cornerRadius: kose, style: .continuous))
        .padding(12)
        .background(sema == .dark ? Color(white: 0.11) : Color(white: 0.86))
        .environment(\.colorScheme, sema)
    let r = ImageRenderer(content: gorunum)
    r.scale = 3
    NSAppearance.current = NSAppearance(named: sema == .dark ? .darkAqua : .aqua)
    guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { print("çizilemedi:", ad); return }
    let u = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(ad + ".png")
    try? png.write(to: u)
}

@MainActor
func calis() {
    var a = WidgetAnlik.ornek
    if CommandLine.arguments.count > 2, let v = try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])) {
        let c = JSONDecoder(); c.dateDecodingStrategy = .iso8601
        if let x = try? c.decode(WidgetAnlik.self, from: v) { a = x }
    }
    let boy: [(String, WidgetFamily, CGSize)] = [
        ("kucuk", .systemSmall, CGSize(width: 170, height: 170)),
        ("orta", .systemMedium, CGSize(width: 364, height: 170)),
        ("buyuk", .systemLarge, CGSize(width: 364, height: 382)),
    ]
    for sema in [ColorScheme.light, .dark] {
        let s = sema == .dark ? "koyu" : "acik"
        for (ad, aile, b) in boy {
            ciz(AforizmaWidgetGorunum(anlik: a, sira: 0, zorla: aile), b, sema, "w-aforizma-\(ad)-\(s)", zemin: AforizmaWidgetGorunum.renk(a, 0))
            ciz(HatirlaWidgetGorunum(anlik: a, sira: 0, acik: false, zorla: aile), b, sema, "w-hatirla-\(ad)-\(s)", zemin: Tema.hat(.hatirla))
            ciz(HatirlaWidgetGorunum(anlik: a, sira: 0, acik: true, zorla: aile), b, sema, "w-hatirla-acik-\(ad)-\(s)", zemin: Tema.hat(.hatirla))
            ciz(OkumaWidgetGorunum(anlik: a, zorla: aile), b, sema, "w-okuma-\(ad)-\(s)", zemin: OkumaWidgetGorunum.renk(a))
            ciz(KurWidgetGorunum(anlik: a, zorla: aile), b, sema, "w-kur-\(ad)-\(s)", zemin: Tema.vurgu)
        }
    }
    print("tamam")
}

MainActor.assumeIsolated { calis() }
