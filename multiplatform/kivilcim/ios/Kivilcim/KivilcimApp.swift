// Kıvılcım — iPhone. Aklına geleni kilidi açmadan söyle: kilit ekranı denetimi → kayıt → Canlı Etkinlik → bitir.
// Kayıt vault'a gider; Mac'teki Kıvılcım yerel Whisper ile yazıya döker, başlık ve alan/amaç koyar, telefon geri çeker.
import PDMBus
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
    @State private var isaretSes: BekleyenIsaret?

    init() {
        UserDefaults.standard.register(defaults: ["kalite": "dengeli", "dil": "tr", "onDokum": true, "dokunsal": true, "sunucuDokum": false, "pruneAfterMac": true])
        KivilcimKisayollari.updateAppShortcutParameters()
        TelefonDeposu.preload()     // reads the stored list on a background thread while the app launches
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $sekme) {
                Tab("Kaydet", systemImage: "mic.fill", value: 0) { KayitEkrani(sekme: $sekme) }
                Tab("Merkez", systemImage: "square.grid.2x2.fill", value: 5) { MerkezEkrani() }
                Tab("İşler", systemImage: "checklist", value: 1) { IslerEkrani() }
                    .badge(depo.acik.filter { $0.priority == Priority.urgent.rawValue }.count)
                Tab("Günlük", systemImage: "book.pages.fill", value: 3) { GunlukEkrani() }
                Tab(value: 4, role: .search) { ArsivEkrani() }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
            .tint(.kivilcim)
            .environmentObject(merkez).environmentObject(depo).environmentObject(kasa).environmentObject(oy)
            .onOpenURL { adresAc($0) }
            // a Spotlight result: the record's id opens its quick editor
            .onContinueUserActivity(PDMSpotlight.activityType) { a in
                if let id = PDMSpotlight.identifier(from: a) { merkez.hizliDuzen = id }
            }
            .onChange(of: depo.ogeler) { _, ogeler in KivilcimSystem.indexSoon(ogeler) }
            .onChange(of: evre) { _, e in
                if e == .background { KivilcimSystem.scheduleSend() }
                if e == .active {
                    // the share sheet could not open the app: the waiting voice note opens here instead
                    if isaretSes == nil, let m = IsaretSesDeposu.sonBekleyen() { isaretSes = m }
                    Task { await depo.gonder(); await KivilcimBus.becameActive() }
                    Task.detached(priority: .utility) { Tani.kirp(); Tani.mirror() }
                    NewModelStore.shared.load()
                }
            }
            .sheet(item: $isaretSes) { m in IsaretSesEkrani(isaret: m).environmentObject(depo) }
            .onReceive(NotificationCenter.default.publisher(for: .kivilcimKisaYol)) { n in
                guard let tur = n.object as? String else { return }
                if tur.hasSuffix("kaydet") { sekme = 0; Task { await merkez.baslat(kaynak: "ikon") } } else { sekme = 1 }
            }
            .task {
                // a launch straight into the foreground (the lock-screen record path) never changes evre: copy here too
                Task.detached(priority: .utility) { Tani.mirror() }
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

    /// kivilcim://kaydet · bitir · surekli · arsiv · merkez/<sayfa> · duzen/<id> · isaret-ses/<id>
    private func adresAc(_ u: URL) {
        switch u.host {
        case "kaydet":
            // kivilcim://kaydet?topic=<Teoria book id or k:name>: another app starts a recording about a book
            let q = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func temiz(_ ad: String) -> String? {
                let v = q.first(where: { $0.name == ad })?.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return v.isEmpty || v.count > 200 ? nil : v
            }
            // ?app=<id>: a voice note from an app's page (Merkez › Uygulamalar)
            let konu = temiz("topic"), app = temiz("app")
            let kaynak = app != nil ? "adres+uygulama" : konu != nil ? "adres+konu" : "adres"
            sekme = 0; Task { await merkez.baslat(kaynak: kaynak, topic: konu, app: app) }
        case "bitir": Task { await merkez.bitir() }
        // kivilcim://surekli: all-day listening on/off (Shortcuts, Back Tap)
        case "surekli": sekme = 0; Task { await merkez.degistir(kaynak: "adres", tur: "continuous") }
        case "arsiv", "isler": sekme = 1
        case "merkez": sekme = 5; MerkezNav.shared.open(u.pathComponents.dropFirst().first)
        case "tatbik", "akis", "uygulamalar": sekme = 5; MerkezNav.shared.open(u.host)
        case "gunluk": sekme = 3
        case "duzen": if let id = u.pathComponents.dropFirst().first { merkez.hizliDuzen = id }
        case "isaret-ses":
            // Paylaş › Kıvılcım › "İşaretle ve sesli not ekle"
            if let id = u.pathComponents.dropFirst().first {
                let ay = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "ay" }?.value
                    ?? String(id.prefix(4)) + "-" + String(id.dropFirst(4).prefix(2))
                var m = BekleyenIsaret(id: id, ay: ay)
                m.baslik = IsaretSesDeposu.oku(m)?["baslik"] as? String ?? ""
                isaretSes = m
            }
        default: break
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
        AppShortcut(intent: StartJournalIntent(), phrases: ["\(.applicationName) ile günlük kaydet", "\(.applicationName) günlük"],
                    shortTitle: "Sesli günlük", systemImageName: "book.pages")
        AppShortcut(intent: StartContinuousIntent(), phrases: ["\(.applicationName) sürekli dinle", "\(.applicationName) ile gün boyu dinle"],
                    shortTitle: "Sürekli dinle", systemImageName: "ear.badge.waveform")
        AppShortcut(intent: ShowOpenSparksIntent(), phrases: ["\(.applicationName) açık işler", "\(.applicationName) neler açık"],
                    shortTitle: "Açık işler", systemImageName: "checklist")
        AppShortcut(intent: EditLastSparkIntent(), phrases: ["\(.applicationName) son kaydı düzenle"],
                    shortTitle: "Son kıvılcımı düzenle", systemImageName: "slider.horizontal.3")
        AppShortcut(intent: MarkDoneIntent(), phrases: ["\(.applicationName) yapıldı işaretle"],
                    shortTitle: "Yapıldı işaretle", systemImageName: "checkmark.circle")
        AppShortcut(intent: AddNoteIntent(), phrases: ["\(.applicationName) not ekle"],
                    shortTitle: "Not ekle", systemImageName: "square.and.pencil")
        AppShortcut(intent: SetPriorityIntent(), phrases: ["\(.applicationName) öncelik ver"],
                    shortTitle: "Öncelik ver", systemImageName: "flag")
        AppShortcut(intent: KaydiBitirNiyeti(), phrases: ["\(.applicationName) kaydını bitir"],
                    shortTitle: "Kaydı bitir", systemImageName: "stop.fill")
    }
}

// MARK: Ana ekran ikonuna uzun basınca çıkan menü (Fikir kaydet · Arşiv)

extension Notification.Name { static let kivilcimKisaYol = Notification.Name("kivilcimKisaYol") }

final class UygulamaTemsilcisi: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        KivilcimSystem.registerSend()
        // before any recording can start in this launch: a file left without its sidecar is saved, not lost
        KayitMerkezi.recoverOrphans()
        return true
    }

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
    /// Uygulama içi ada ayrı, saydam bir pencerede durur: TabView'ın üstündeki katman iOS 26'da tazelenmiyordu,
    /// ayrıca açık sayfaların (detay) da üstünde kalır. Bkz. Ada.swift.
    var adaPenceresi: AdaPenceresi?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let ws = scene as? UIWindowScene else { return }
        adaPenceresi = AdaPenceresi.kur(ws)
    }

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
