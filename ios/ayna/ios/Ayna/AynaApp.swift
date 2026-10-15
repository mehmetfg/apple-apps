// Ayna — kendi gününü İngilizce söyle. Akşam anlat → gece Mac düzeltir → sabah yürürken kendi sesini ve doğrusunu dinle,
// kendi hatalarından soruları kulaklık tuşuyla cevapla → yeniden söyle.
// Sekmeler: Bugün · Dinle · Kenar · Ayarlar. Adresler: ayna://bugun · dinle · kenar · kaydet/<tür> · anlat?is=<kenar işi>
import AppIntents
import SwiftUI
import UserNotifications

final class Rota: ObservableObject {
    static let shared = Rota()
    @Published var sekme = 0
    @Published var kayit: KayitIstegi?

    func git(_ adres: String) {
        guard let u = URL(string: adres), u.scheme == "ayna" else { return }
        switch u.host() ?? "" {
        case "dinle": sekme = 1
        case "kenar": sekme = 2
        case "anlat":
            sekme = 2
            if let is_ = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "is" })?.value,
               let x = Depo.kenarKuyrugu().first(where: { $0.id == is_ }) {
                kayit = KayitIstegi(tur: .metin, istem: "§\(x.bolumNo) \(x.baslik)", aciklama: x.paragraf, kenarIs: x.id)
            }
        case "kaydet":
            sekme = 0
            let tur = Tur(rawValue: u.pathComponents.filter { $0 != "/" }.first ?? "gun") ?? .gun
            kayit = KayitIstegi(tur: tur, istem: tur == .kapi ? Kapi.istem : "Gününü anlat", aciklama: nil)
        default: sekme = 0
        }
    }
}

struct KayitIstegi: Identifiable, Hashable {
    var id = UUID()
    var tur: Tur
    var istem: String
    var aciklama: String?
    var kenarIs: String? = nil
    var onceki: String? = nil
    var foto: String? = nil
}

final class Temsilci: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        _ = Yuruyus.shared
        return true
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .list] }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let r = response.notification.request.content.userInfo["rota"] as? String { await MainActor.run { Rota.shared.git(r) } }
    }
}

@main
struct AynaApp: App {
    @UIApplicationDelegateAdaptor(Temsilci.self) var temsilci
    @StateObject private var merkez = Merkez()
    @StateObject private var rota = Rota.shared
    @Environment(\.scenePhase) private var faz

    var body: some Scene {
        WindowGroup {
            TabView(selection: $rota.sekme) {
                BugunEkrani().tabItem { Label("Bugün", systemImage: "sun.horizon") }.tag(0)
                DinleEkrani().tabItem { Label("Dinle", systemImage: "headphones") }.badge(merkez.d.kayitlar.filter { $0.duzeltme != nil && !$0.dinlendi }.count).tag(1)
                KenarIsleriEkrani().tabItem { Label("Kenar", systemImage: "text.book.closed") }.badge(merkez.bekleyenKenar.count).tag(2)
                AyarlarEkrani().tabItem { Label("Ayarlar", systemImage: "gearshape") }.tag(3)
            }
            .tint(.ayna)
            .preferredColorScheme(.dark)
            .environmentObject(merkez)
            .environmentObject(rota)
            .sheet(item: $rota.kayit) { KayitEkrani(istek: $0) }
            .onOpenURL { rota.git($0.absoluteString) }
            .task {
                #if DEBUG
                if let i = CommandLine.arguments.firstIndex(of: "-sekme"), i + 1 < CommandLine.arguments.count, let s = Int(CommandLine.arguments[i + 1]) { rota.sekme = s }
                if CommandLine.arguments.contains("-ornek") { Onizleme.doldur(merkez) }
                #endif
                if !CommandLine.arguments.contains("-sekme") {
                    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                }
            }
        }
        .onChange(of: faz) { _, yeni in
            guard yeni == .active else { return }
            if let r = Depo.rotaAl() { rota.git(r) }
            Task { await merkez.esitle() }
        }
    }
}

struct GununAniNiyeti: AppIntent {
    static let title: LocalizedStringResource = "Gününü İngilizce anlat"
    static let description = IntentDescription("Ayna'da 90 saniyelik kaydı açar.")
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult { Depo.rotaBirak("ayna://kaydet/gun"); return .result() }
}

struct YuruyusNiyeti: AppIntent {
    static let title: LocalizedStringResource = "Sabah yürüyüşünü başlat"
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult { Depo.rotaBirak("ayna://dinle"); return .result() }
}

struct AynaKestirmeleri: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: GununAniNiyeti(), phrases: ["\(.applicationName) ile gününü anlat", "\(.applicationName) kayıt"], shortTitle: "Gününü anlat", systemImageName: "mic")
        AppShortcut(intent: YuruyusNiyeti(), phrases: ["\(.applicationName) sabah yürüyüşü"], shortTitle: "Sabah yürüyüşü", systemImageName: "figure.walk")
    }
}

#if DEBUG
enum Onizleme {
    @MainActor static func doldur(_ m: Merkez) {
        guard m.d.kayitlar.isEmpty else { return }
        var k = Kayit(id: "ornek1", tarih: .now.addingTimeInterval(-50000), tur: .gun, istem: "Gününü anlat", sure: 72)
        k.dokum = "Today I go to the office early and I have a meeting with my boss about the new project. After that I eat lunch with my colleague and we talk about the weekend."
        k.duzeltme = "Today I went to the office early and had a meeting with my boss about the new project. After that, I had lunch with a colleague, and we talked about the weekend."
        k.hatalar = [Hata(yanlis: "Today I go to the office", dogru: "Today I went to the office", kural: "Finished actions today → past simple"),
                     Hata(yanlis: "I eat lunch", dogru: "I had lunch", kural: "'have lunch' is the natural collocation")]
        k.sorular = [Soru(cumle: "Yesterday I go to the office early", dogru: false, aciklama: "Yesterday needs went."),
                     Soru(cumle: "After that, I had lunch with a colleague", dogru: true, aciklama: "Have lunch, past: had lunch.")]
        m.d.kayitlar = [k]
        m.d.kapiIstemleri = [.now.addingTimeInterval(-1200)]
        m.kaydet()
    }
}
#endif
