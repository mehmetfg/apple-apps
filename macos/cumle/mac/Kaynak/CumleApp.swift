// Cümle — Cümle Tezgâhı'nın yerli Mac uygulaması. Mantık Tezgâh v7'ninki (sıra aynen); fark: tarayıcı ve yerel
// sunucu yok, vault'u doğrudan okur/yazar, telefondaki Memories ile ortak klasörden canlı konuşur.
import SwiftUI
import AppKit
import Combine

@main
struct CumleApp: App {
    @NSApplicationDelegateAdaptor(Temsilci.self) var temsilci
    @StateObject private var t = TezgahKok.t

    var body: some Scene {
        WindowGroup("Cümle", id: "ana") {
            Ana()
                .environmentObject(t)
                .frame(minWidth: 980, minHeight: 640)
                .background(Renk.zemin)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1320, height: 860)
        .windowToolbarStyle(.unified)
        .commands { Komutlar(t: t) }
    }
}

final class Temsilci: NSObject, NSApplicationDelegate {
    var izle: [AnyCancellable] = []
    var olay: Any?
    @MainActor func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        for p in NSApp.windows { p.backgroundColor = NSColor(red: 0.047, green: 0.055, blue: 0.075, alpha: 1) }
        NSApp.activate(ignoringOtherApps: true)
        let t = TezgahKok.t
        // alt nesnelerin değişimi ana görünümü de tazelesin
        for p in [t.ses.objectWillChange, t.calici.objectWillChange, t.kaydedici.objectWillChange] {
            izle.append(p.sink { [weak t] _ in t?.objectWillChange.send() })
        }
        // süre: dokunulan zaman (tuş ve tıklama)
        olay = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { e in
            Task { @MainActor in TezgahKok.t.dokun() }
            return e
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
    @MainActor func applicationWillTerminate(_ n: Notification) { TezgahKok.t.kaydet(hemen: true) }
}

struct Komutlar: Commands {
    @ObservedObject var t: Tezgah
    var body: some Commands {
        CommandMenu("Çalışma") {
            Button("Bugün") { t.gorunum = .bugun }.keyboardShortcut("1", modifiers: .command)
            Button("Geçmiş") { t.gorunum = .gecmis }.keyboardShortcut("2", modifiers: .command)
            Divider()
            Button("Gün JSON'u içe aktar…") { t.iceAktarPaneli() }.keyboardShortcut("i", modifiers: [.command, .shift])
            Button("Önceki gün") { t.oncekiGun() }.keyboardShortcut("[", modifiers: [.command, .shift])
            Button("Sonraki gün") { t.sonrakiGun() }.keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Bu günü yaptım, geç") { if let g = t.gunMasa { t.atla(g) } }.disabled(t.o != nil || t.gunMasa == nil)
            Divider()
            Button("İpucu") { t.ipucuTikla() }.keyboardShortcut("h", modifiers: .option).disabled(t.o?.adim != .cumle)
            Button("Cümleyi göster / gizle") { t.cumleTikla() }.keyboardShortcut("e", modifiers: .option).disabled(t.o?.adim != .cumle)
            Button("Önceki cümle") { if let o = t.o { t.cumleGit(o.i - 1) } }.disabled(t.o?.adim != .cumle)
            Button("Sıradaki cümle") { t.ileri() }.disabled(t.o?.adim != .cumle)
            Button("Doğrusunu dinle") { if let o = t.o { t.ses.soyle(o.cumle(o.i).en) } }.keyboardShortcut("d", modifiers: .option).disabled(t.o == nil)
            Divider()
            Button("Gramer sayfası") { t.gramerAc() }.keyboardShortcut("g", modifiers: .option)
            Button("Kuiz promptu") { t.kuizAcik = true }.keyboardShortcut("k", modifiers: .command)
            Button("Metin haritası") { t.haritaAcik.toggle() }.keyboardShortcut("0", modifiers: .command)
            Divider()
            Button("Sonucu yeniden kaydet") { t.sonucYaz(); t.kaydet() }.keyboardShortcut("s", modifiers: .command).disabled(t.o?.indi != true)
            Button("Telefonu ve metni tazele") { t.tazele(hepsi: true) }.keyboardShortcut("r", modifiers: .command)
            Button("Oturumu kapat") { t.birak() }.disabled(t.o == nil)
        }
    }
}
