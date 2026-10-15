// Yalnız DEBUG: `-widgetPNG` argümanıyla açılınca widget görünümlerini gerçek veriyle PNG'ye çizer
// (Documents/onizleme/). Simülatörde ana ekranı elle sürmeden widget'ı görmek için.
#if DEBUG
import SwiftUI
import WidgetKit

enum Onizleme {
    @MainActor
    static func ciz() {
        guard ProcessInfo.processInfo.arguments.contains("-widgetPNG"), let a = Paylasim.oku() else { return }
        let l = a.kelimeler()
        guard let ilk = l.first(where: { !$0.pv }), let pv = l.first(where: { $0.pv }) else { return }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("onizleme")
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let boyutlar: [(String, WidgetFamily, CGSize)] = [
            ("kucuk", .systemSmall, CGSize(width: 170, height: 170)),
            ("orta", .systemMedium, CGSize(width: 364, height: 170)),
            ("buyuk", .systemLarge, CGSize(width: 364, height: 382)),
            ("kilit", .accessoryRectangular, CGSize(width: 172, height: 76)),
        ]
        let ornekler: [(String, WKelime, Bool)] = [("kelime", ilk, false), ("hatirla", ilk, true), ("pv", pv, false)]
        for sema in [ColorScheme.light, .dark] {
            let son = sema == .dark ? "koyu" : "acik"
            for (ad, aile, b) in boyutlar {
                for (tur, k, hatirla) in ornekler {
                    let g = Giris(date: Date(), kelime: k, sonrakiler: Array(l.filter { $0.i != k.i }.prefix(3)),
                                  anlik: a, acik: false, onceHatirla: hatirla)
                    yaz(KelimeGorunumu(g: g, zorla: aile),
                        arka: AnyView(KelimeZemini(c: k.c, pv: k.pv, harf: String(k.w.prefix(1)).uppercased())),
                        b, sema, dir.appendingPathComponent("\(ad)-\(tur)-\(son).png"))
                }
            }
            yaz(IlerlemeGorunumu(a: a, zorla: .systemSmall), arka: AnyView(IlerlemeZemini()),
                CGSize(width: 170, height: 170), sema, dir.appendingPathComponent("ilerleme-\(son).png"))
        }
    }

    @MainActor
    private static func yaz<V: View>(_ v: V, arka: AnyView, _ b: CGSize, _ sema: ColorScheme, _ u: URL) {
        let gorunum = v.padding(16)
            .frame(width: b.width, height: b.height)
            .background(arka)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(10)
            .background(sema == .dark ? Color.black : Color(white: 0.85))
            .environment(\.colorScheme, sema)
        let r = ImageRenderer(content: gorunum)
        r.scale = 3
        if let d = r.uiImage?.pngData() { try? d.write(to: u) }
    }
}
#endif
