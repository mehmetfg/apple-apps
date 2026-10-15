// Kıvılcım — Mac. Menü çubuğunda yaşar: tıkla ya da ⌃⌥K → konuş → bırak. Kayıt vault'a gider, yerel Whisper
// yazıya döker, başlık ve alan/amaç koyar. Arşiv penceresinde arama, süzme, dinleme, düzeltme.
import SwiftUI
import AppKit
import ServiceManagement
import Combine

@main
struct KivilcimApp: App {
    @NSApplicationDelegateAdaptor(Uygulama.self) var uygulama
    @StateObject private var depo = Depo.shared
    @StateObject private var kaydedici = Kaydedici.shared

    init() { MenuKonumu.sagaAl(zorla: false) }

    var body: some Scene {
        MenuBarExtra {
            MenuPaneli()
                .environmentObject(depo).environmentObject(kaydedici).environmentObject(Oynatici.shared)
        } label: {
            MenuEtiketi().environmentObject(kaydedici)
        }
        .menuBarExtraStyle(.window)

        Window("Kıvılcım", id: "arsiv") {
            ArsivPenceresi()
                .environmentObject(depo).environmentObject(kaydedici).environmentObject(Oynatici.shared)
                .frame(minWidth: 860, minHeight: 520)
        }
        .defaultSize(width: 1080, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(kaydedici.kayitta ? "Kaydı bitir" : "Yeni sesli fikir") { kaydedici.degistir() }
                    .keyboardShortcut("n")
            }
            CommandGroup(after: .newItem) {
                Button("Şimdi işle") { depo.isle() }.keyboardShortcut("r")
            }
        }

        Settings {
            AyarlarGorunumu().environmentObject(depo)
        }
    }
}

final class Uygulama: NSObject, NSApplicationDelegate {
    private var hud: HUDPaneli?
    private var gozlem: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["kalite": "dengeli", "dil": "tr", "claudeBaslik": true, "hud": true])
        if let o = Onizleme.klasor { MainActor.assumeIsolated { Onizleme.calistir(o) }; return }
        MainActor.assumeIsolated {
            Kisayol.shared.kur()
            Depo.shared.izle()
            hud = HUDPaneli()
            gozlem = Kaydedici.shared.$kayitta.removeDuplicates().receive(on: RunLoop.main).sink { [weak self] kayitta in
                MainActor.assumeIsolated {
                    Kisayol.shared.escAc(kayitta)
                    if kayitta, UserDefaults.standard.bool(forKey: "hud") { self?.hud?.goster() } else { self?.hud?.gizle() }
                }
            }
        }
        if UserDefaults.standard.object(forKey: "girisAyarlandi") == nil {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "girisAyarlandi")
        }
        // "kivilcim://kaydet" (Kestirmeler, Raycast, Stream Deck…)
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(adres(_:_:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    @objc func adres(_ olay: NSAppleEventDescriptor, _ cevap: NSAppleEventDescriptor) {
        guard let s = olay.paramDescriptor(forKeyword: keyDirectObject)?.stringValue, let u = URL(string: s) else { return }
        MainActor.assumeIsolated {
            switch u.host {
            case "kaydet", "baslat": if !Kaydedici.shared.kayitta { Kaydedici.shared.baslat() }
            case "bitir": Kaydedici.shared.bitir()
            default: Kaydedici.shared.degistir()
            }
        }
    }
}

/// Menü çubuğundaki simge: boşta dalga, kayıtta kor renkli nokta + süre.
struct MenuEtiketi: View {
    @EnvironmentObject var k: Kaydedici
    var body: some View {
        if k.kayitta {
            HStack(spacing: 3) {
                Image(systemName: "record.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.red, .primary)
                Text(Zaman.sure(k.sure)).monospacedDigit()
            }
        } else {
            Image(systemName: "waveform.badge.mic")
        }
    }
}

/// Kısayolla kayıtta ekranın üst ortasında duran küçük pano (odak çalmaz).
final class HUDPaneli {
    private let panel: NSPanel
    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 330, height: 64),
                        styleMask: [.nonactivatingPanel, .borderless, .hudWindow], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        let v = NSHostingView(rootView: MainActor.assumeIsolated { HUDGorunumu().environmentObject(Kaydedici.shared) })
        v.frame = panel.contentRect(forFrameRect: panel.frame)
        panel.contentView = v
    }
    func goster() {
        guard let e = NSScreen.main?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: e.midX - 165, y: e.maxY - 64 - 14))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }
    }
    func gizle() {
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; panel.animator().alphaValue = 0 }) { [panel] in panel.orderOut(nil) }
    }
}

struct HUDGorunumu: View {
    @EnvironmentObject var k: Kaydedici
    @State private var nabiz = false
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(Color.kivilcim).frame(width: 12, height: 12)
                .scaleEffect(nabiz ? 1.15 : 0.85).opacity(nabiz ? 1 : 0.6)
                .animation(.easeInOut(duration: 0.7).repeatForever(), value: nabiz)
            Text(Zaman.sure(k.sure)).font(.system(.title3, design: .rounded).monospacedDigit().weight(.semibold))
            DuzeyCubuklari(seviyeler: k.seviyeler, adet: 22).frame(height: 26)
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(KisayolSecenegi.secili.ad) bitir").font(.caption2.weight(.medium))
                Text("esc vazgeç").font(.caption2).foregroundStyle(.secondary)
            }
            Button { k.bitir() } label: {
                Image(systemName: "stop.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 26, height: 26).background(Circle().fill(Color.kivilcim))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 16).frame(width: 330, height: 64)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.08)))
        .onAppear { nabiz = true }
    }
}

/// Çentikli ekranda menü çubuğu dolunca macOS taşan simgeleri çentiğin arkasına saklar; en yeni eklenen (Kıvılcım)
/// en solda kalır ve görünmez. Simgeyi bir kez saatin/Denetim Merkezi'nin hemen soluna yerleştiririz.
/// Sonradan ⌘ basılı sürükleyerek taşıyabilirsin; o konum korunur.
enum MenuKonumu {
    static let anahtar = "NSStatusItem Preferred Position Item-0"
    static func sagaAl(zorla: Bool) {
        let d = UserDefaults.standard
        guard zorla || !d.bool(forKey: "menuKonumuAyarlandi") else { return }
        d.set(1.0, forKey: anahtar)
        d.set(true, forKey: "NSStatusItem Visible Item-0")
        d.set(true, forKey: "menuKonumuAyarlandi")
    }
    /// Ayarlar'daki düğme: konumu sıfırla ve uygulamayı yeniden aç.
    static func sifirlaVeYenidenAc() {
        sagaAl(zorla: true)
        let yol = Bundle.main.bundleURL
        let c = NSWorkspace.OpenConfiguration(); c.createsNewApplicationInstance = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSWorkspace.shared.openApplication(at: yol, configuration: c) { _, _ in }
            NSApp.terminate(nil)
        }
    }
}
