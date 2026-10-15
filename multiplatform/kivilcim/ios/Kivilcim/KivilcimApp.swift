// Kıvılcım — iPhone. Aklına geleni kilidi açmadan söyle: kilit ekranı denetimi → kayıt → Canlı Etkinlik → bitir.
// Kayıt vault'a gider; Mac'teki Kıvılcım yerel Whisper ile yazıya döker, başlık ve alan/amaç koyar, telefon geri çeker.
import SwiftUI
import AppIntents
import AVFoundation
import UIKit

@main
struct KivilcimApp: App {
    @UIApplicationDelegateAdaptor(UygulamaTemsilcisi.self) private var temsilci
    @StateObject private var merkez = KayitMerkezi.shared
    @StateObject private var depo = TelefonDeposu.shared
    @StateObject private var kasa = Kasa.shared
    @StateObject private var oy = TelefonOynatici.shared
    @Environment(\.scenePhase) private var evre
    @State private var sekme = 0

    init() {
        UserDefaults.standard.register(defaults: ["kalite": "dengeli", "dil": "tr", "onDokum": true, "dokunsal": true, "sunucuDokum": false])
        KivilcimKisayollari.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $sekme) {
                Tab("Kaydet", systemImage: "mic.fill", value: 0) { KayitEkrani(sekme: $sekme) }
                Tab("Arşiv", systemImage: "square.stack.3d.up.fill", value: 1) { ArsivEkrani() }
                Tab("Ayarlar", systemImage: "gearshape.fill", value: 2) { AyarlarEkrani() }
            }
            .tint(.kivilcim)
            .environmentObject(merkez).environmentObject(depo).environmentObject(kasa).environmentObject(oy)
            .onOpenURL { u in
                // kivilcim://kaydet · kivilcim://bitir · kivilcim://arsiv
                switch u.host {
                case "kaydet": sekme = 0; Task { await merkez.baslat(kaynak: "adres") }
                case "bitir": Task { await merkez.bitir() }
                case "arsiv": sekme = 1
                default: break
                }
            }
            .onChange(of: evre) { _, e in if e == .active { Task { await depo.gonder() } } }
            .onReceive(NotificationCenter.default.publisher(for: .kivilcimKisaYol)) { n in
                guard let tur = n.object as? String else { return }
                if tur.hasSuffix("kaydet") { sekme = 0; Task { await merkez.baslat(kaynak: "ikon") } } else { sekme = 1 }
            }
            .task {
                if let o = ProcessInfo.processInfo.environment["KIVILCIM_ONIZLEME"] { sekme = Int(o) ?? 0 }
                // kilit ekranından kayıt için izinler önceden alınmalı (orada soru gösterilemez)
                if AVAudioApplication.shared.recordPermission == .undetermined { _ = await AVAudioApplication.requestRecordPermission() }
                await depo.gonder()
                // sınama: KIVILCIM_SINAMA_KAYIT=<sn> → açılınca o kadar kaydedip bitirir
                if let s = ProcessInfo.processInfo.environment["KIVILCIM_SINAMA_KAYIT"], let sn = Double(s) {
                    await merkez.baslat(kaynak: "sinama")
                    try? await Task.sleep(for: .seconds(sn))
                    await merkez.bitir()
                }
            }
        }
    }
}

/// Siri ve Kestirmeler: "Kıvılcım ile fikir kaydet". Eylem Düğmesi ya da Arkaya Dokunma bunlara bağlanabilir.
struct KivilcimKisayollari: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: KaydiDegistirNiyeti(), phrases: [
            "\(.applicationName) ile fikir kaydet", "\(.applicationName) kaydet", "Record an idea with \(.applicationName)",
        ], shortTitle: "Fikir kaydet", systemImageName: "mic.fill")
        AppShortcut(intent: AcVeKaydetNiyeti(), phrases: ["\(.applicationName) aç ve kaydet"],
                    shortTitle: "Aç ve kaydet", systemImageName: "mic.circle")
        AppShortcut(intent: KaydiBitirNiyeti(), phrases: ["\(.applicationName) kaydını bitir"],
                    shortTitle: "Kaydı bitir", systemImageName: "stop.fill")
    }
}

// MARK: Ana ekran ikonuna uzun basınca çıkan menü (Fikir kaydet · Arşiv)

extension Notification.Name { static let kivilcimKisaYol = Notification.Name("kivilcimKisaYol") }

final class UygulamaTemsilcisi: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting s: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let c = UISceneConfiguration(name: nil, sessionRole: s.role)
        c.delegateClass = SahneTemsilcisi.self
        // soğuk açılış: kısa yol seçeneklerin içinde gelir
        if let k = options.shortcutItem { SahneTemsilcisi.bekleyen = k.type }
        return c
    }
}

final class SahneTemsilcisi: NSObject, UIWindowSceneDelegate {
    static var bekleyen: String?
    func sceneDidBecomeActive(_ scene: UIScene) {
        if let t = SahneTemsilcisi.bekleyen {
            SahneTemsilcisi.bekleyen = nil
            Tani.yaz("ikon menüsü: \(t) (soğuk açılış)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NotificationCenter.default.post(name: .kivilcimKisaYol, object: t) }
        }
    }
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        Tani.yaz("ikon menüsü: \(shortcutItem.type)")
        NotificationCenter.default.post(name: .kivilcimKisaYol, object: shortcutItem.type)
        completionHandler(true)
    }
}
