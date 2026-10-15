// Teoria — iPhone uygulaması (iOS 17+, iOS 26 tasarımına uyumlu sekme çubuğu).
// Sekmeler: Bugün · Akış · Kitaplar · Müfredat · Ses. Ayarlar Bugün başlığındaki dişliden açılır. Kür tam ekran açılır; sesli not sayfa olarak.
import SwiftUI
import UserNotifications
import AppIntents

final class UygulamaTemsilcisi: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static var bekleyenRota: ((String) -> Void)?
    static var birikenRota: String?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Bildirim.kategorileriKaydet()
        return true
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse) async {
        guard let rota = Bildirim.eylem(r) else {
            await MainActor.run { NotificationCenter.default.post(name: .teoriaKutu, object: nil) }
            return
        }
        await MainActor.run {
            if let f = UygulamaTemsilcisi.bekleyenRota { f(rota) } else { UygulamaTemsilcisi.birikenRota = rota }
        }
    }
}

extension Notification.Name { static let teoriaKutu = Notification.Name("teoria.kutu") }

enum Sekme: Hashable { case bugun, akis, kitaplar, mufredat, ses }

struct SesHedefi: Identifiable { let id = UUID(); let hedef: String? }
struct OdaHedefi: Identifiable { let id: String }   // açılacak işaretin kimliği

@main
struct TeoriaApp: App {
    @UIApplicationDelegateAdaptor(UygulamaTemsilcisi.self) var temsilci
    @StateObject private var depo = Depo()
    @Environment(\.scenePhase) private var faz
    @State private var sekme: Sekme = .bugun
    @State private var kurDakika: Int?
    @State private var ses: SesHedefi?
    @State private var oda: OdaHedefi?
    @State private var recall: Isaret?
    @State private var kitap: LibraryEntry?

    var body: some Scene {
        WindowGroup {
            sekmeler
                .environmentObject(depo)
                .preferredColorScheme(depo.tema.sema)
                .tint(Tema.vurgu)
                .environment(\.locale, Dil.tr)
                .fullScreenCover(item: Binding(get: { kurDakika.map { KurAcilis(dakika: $0) } }, set: { kurDakika = $0?.dakika })) { k in
                    KurEkrani(dakika: k.dakika) {
                        kurDakika = nil
                        Task { await Bildirim.planla(depo) }
                    }
                    .environmentObject(depo)
                    .preferredColorScheme(depo.tema.sema)
                }
                .sheet(item: $ses) { s in
                    SesKayitSayfasi(hedef: s.hedef).environmentObject(depo)
                        .presentationDetents([.large])
                }
                .sheet(item: $oda) { o in
                    IsaretOdasi(kimlik: o.id, sesAc: { ses = SesHedefi(hedef: $0) }).environmentObject(depo)
                        .preferredColorScheme(depo.tema.sema)
                }
                .sheet(item: $recall) { i in
                    RecallSayfasi(isaret: i).environmentObject(depo).preferredColorScheme(depo.tema.sema)
                }
                .sheet(item: $kitap) { e in
                    NavigationStack { BookScreen(entry: e) }
                        .environmentObject(depo).preferredColorScheme(depo.tema.sema)
                }
                .onOpenURL { u in
                    // teoria://isaret/<id> → bir nota; öteki rotalar yalnız ana makine adı
                    let h = u.host() ?? ""
                    rota(h == "isaret" || h == "kitap" ? h + ":" + u.lastPathComponent : h)
                }
                .onReceive(NotificationCenter.default.publisher(for: .teoriaKutu)) { _ in depo.kutuyuAl() }
                .task { await Bildirim.planla(depo) }   // ilk açılışta izin burada sorulur
                .onAppear {
                    UygulamaTemsilcisi.bekleyenRota = { rota($0) }
                    if let r = UygulamaTemsilcisi.birikenRota { UygulamaTemsilcisi.birikenRota = nil; rota(r) }
                }
                .onChange(of: faz) { _, yeni in
                    guard yeni == .active else { return }
                    depo.kutuyuAl()
                    depo.yenidenHesapla()
                    depo.widgetYaz()
                    if let a = Paylasim.ayar.string(forKey: "w.ac") {
                        Paylasim.ayar.removeObject(forKey: "w.ac"); rota(a)
                    }
                    Task {
                        await depo.esitleSimdi()
                        await Bildirim.planla(depo)
                    }
                }
        }
    }

    private var sekmeler: some View {
        TabView(selection: $sekme) {
            BugunEkrani(kurBaslat: { kurDakika = $0 }, sesAc: { ses = SesHedefi(hedef: $0) })
                .tabItem { Label("Bugün", systemImage: "sun.max") }.tag(Sekme.bugun)
            AkisEkrani(sesAc: { ses = SesHedefi(hedef: $0) })
                .tabItem { Label("Akış", systemImage: "text.bubble") }.tag(Sekme.akis)
            KitaplarEkrani(sesAc: { ses = SesHedefi(hedef: $0) })
                .tabItem { Label("Kitaplar", systemImage: "books.vertical") }.tag(Sekme.kitaplar)
            MufredatEkrani()
                .tabItem { Label("Müfredat", systemImage: "map") }.tag(Sekme.mufredat)
            SesListesi(sesAc: { ses = SesHedefi(hedef: $0) })
                .tabItem { Label("Ses", systemImage: "waveform") }.tag(Sekme.ses)
        }
        .modifier(SekmeKucult())
        .bildirimSeridi()
        .dokun(.selection, sekme)
    }

    /// teoria://kur · teoria://ses · teoria://akis · teoria://mufredat · teoria://hatirla · teoria://isaret/<id> · bildirimden "ses:<id>", "isaret:<id>", "recall:<id>"
    private func rota(_ r: String) {
        switch r {
        case "kur", "hatirla": let d = depo.kurDakika; present { kurDakika = d }
        case "ses": present { ses = SesHedefi(hedef: nil) }
        case "akis": sekme = .akis
        case "kitaplar": sekme = .kitaplar
        case "mufredat": sekme = .mufredat
        case let x where x.hasPrefix("ses:"):
            let h = String(x.dropFirst(4)); present { ses = SesHedefi(hedef: h.isEmpty ? nil : h) }
        case let x where x.hasPrefix("recall:"):
            if let i = depo.isaret(String(x.dropFirst(7))) { present { recall = i } } else { sekme = .akis }
        case let x where x.hasPrefix("kitap:"):
            if let e = LibraryStore.shared.entry(String(x.dropFirst(6))) { present { kitap = e } } else { sekme = .kitaplar }
        case let x where x.hasPrefix("isaret:"):
            let id = String(x.dropFirst(7))
            if depo.isaret(id) != nil { present { oda = OdaHedefi(id: id) } } else { sekme = .akis }
        default: break
        }
    }

    /// A route from a notification, widget or link while another sheet is up: SwiftUI shows one sheet at a time and
    /// silently drops the second, so close what is open, let it animate away, then present.
    private func present(_ show: @escaping @MainActor () -> Void) {
        let open = kurDakika != nil || ses != nil || oda != nil || recall != nil || kitap != nil
        guard open else { show(); return }
        kurDakika = nil; ses = nil; oda = nil; recall = nil; kitap = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            show()
        }
    }
}

struct KurAcilis: Identifiable { let dakika: Int; var id: Int { dakika } }

/// iOS 26: aşağı kaydırınca sekme çubuğu küçülür (Liquid Glass). Önceki sürümlerde etkisiz.
struct SekmeKucult: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}

struct TeoriaKestirmeleri: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TeoriaAc(.kur), phrases: ["\(.applicationName) kürünü başlat", "\(.applicationName) ile çalış"],
                    shortTitle: "Kür başlat", systemImageName: "circle.dashed.inset.filled")
        AppShortcut(intent: TeoriaAc(.ses), phrases: ["\(.applicationName) sesli not"],
                    shortTitle: "Sesli not", systemImageName: "waveform")
    }
}
