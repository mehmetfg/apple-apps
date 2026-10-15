// Önizleme kipi: ekranları PNG'ye çizer ve çıkar (ekran kaydı izni gerekmez).
//   KIVILCIM_KOK=<sınama klasörü> Kivilcim --onizleme <çıkış klasörü> [--koyu]
import SwiftUI
import AppKit

enum Onizleme {
    static var klasor: URL? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "--onizleme"), i + 1 < a.count else { return nil }
        return URL(fileURLWithPath: a[i + 1])
    }

    @MainActor
    static func calistir(_ cikis: URL) {
        try? FileManager.default.createDirectory(at: cikis, withIntermediateDirectories: true)
        let koyu = CommandLine.arguments.contains("--koyu")
        NSApp.appearance = NSAppearance(named: koyu ? .darkAqua : .aqua)
        let ek = koyu ? "-koyu" : ""
        let depo = Depo.shared
        depo.secili = depo.ogeler.first(where: { $0.metin.contains("Kant") })?.id ?? depo.ogeler.first?.id
        ciz(AnyView(MenuPaneli().background(.background)), NSSize(width: 370, height: 560), cikis.appendingPathComponent("menu\(ek).png"))
        ciz(AnyView(ArsivPenceresi()), NSSize(width: 1180, height: 720), cikis.appendingPathComponent("arsiv\(ek).png"))
        ciz(AnyView(HUDGorunumu().padding(20)), NSSize(width: 370, height: 104), cikis.appendingPathComponent("hud\(ek).png"))
        ciz(AnyView(AyarlarGorunumu()), NSSize(width: 520, height: 640), cikis.appendingPathComponent("ayarlar\(ek).png"))
        exit(0)
    }

    @MainActor
    static func ciz(_ v: AnyView, _ boy: NSSize, _ u: URL) {
        let kok = v.environmentObject(Depo.shared).environmentObject(Kaydedici.shared).environmentObject(Oynatici.shared)
        let p = NSWindow(contentRect: NSRect(origin: .zero, size: boy), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        let h = NSHostingView(rootView: kok)
        h.frame = NSRect(origin: .zero, size: boy)
        p.contentView = h
        p.setFrameOrigin(NSPoint(x: -5000, y: -5000))
        p.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        h.layoutSubtreeIfNeeded()
        guard let r = h.bitmapImageRepForCachingDisplay(in: h.bounds) else { return }
        h.cacheDisplay(in: h.bounds, to: r)
        try? r.representation(using: .png, properties: [:])?.write(to: u)
        p.orderOut(nil)
    }
}
