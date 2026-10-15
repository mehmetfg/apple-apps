// Kenar — okumayı tek metne bağlayan uygulama. Okuduğun her şey yazacağın metnin bir bölümüne gider ya da dışarıda kalır.
// Sekmeler: Metin · Kutu · Oku · Harita · Anlat. Adresler: kenar://metin · kutu · oku · oku/basla · kamera · anlat · harita · bolum/<id>
import CoreSpotlight
import SwiftUI
import UIKit
import UserNotifications

final class Rota: ObservableObject {
    static let shared = Rota()
    @Published var sekme = 0
    @Published var bolum: String?          // Metin sekmesinde açılacak bölüm
    @Published var kamera = false
    @Published var oturumAc = false
    @Published var anlatBolum: String?
    @Published var anlatKitap: String?
    @Published var haritaBolum: String?

    func git(_ adres: String) {
        guard let u = URL(string: adres), u.scheme == "kenar" else { return }
        let yol = u.pathComponents.filter { $0 != "/" }
        switch u.host() ?? "" {
        case "kutu": sekme = 1
        case "oku": sekme = 2; if yol.first == "basla" { oturumAc = true }
        case "kamera": sekme = 2; kamera = true
        case "harita": sekme = 3; haritaBolum = yol.first
        case "anlat": sekme = 4; anlatBolum = yol.first
        case "bolum": sekme = 0; bolum = yol.first
        default: sekme = 0
        }
    }
}

final class Temsilci: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Bildirimci.kategorileriKur(Depo.durumOku()?.metin)
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting s: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let k = options.shortcutItem { Kisayol.isle(k) }
        let c = UISceneConfiguration(name: nil, sessionRole: s.role)
        c.delegateClass = SahneTemsilcisi.self
        return c
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .list] }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let adres = await Bildirimci.cevap(response) { await MainActor.run { Rota.shared.git(adres) } }
    }
}

/// Uygulama simgesine basılı tutunca çıkan menü (Info.plist › UIApplicationShortcutItems).
final class SahneTemsilcisi: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        Kisayol.isle(shortcutItem); return true
    }
}

enum Kisayol {
    static func isle(_ k: UIApplicationShortcutItem) {
        let adres = ["oku": "kenar://oku/basla", "kamera": "kenar://kamera", "anlat": "kenar://anlat", "kutu": "kenar://kutu"][k.type] ?? "kenar://metin"
        DispatchQueue.main.async { Rota.shared.git(adres) }
    }
}

@main
struct KenarApp: App {
    @UIApplicationDelegateAdaptor(Temsilci.self) var temsilci
    @StateObject private var merkez = Merkez()
    @StateObject private var rota = Rota.shared
    @Environment(\.scenePhase) private var faz

    var body: some Scene {
        WindowGroup {
            AnaGorunum()
                .tint(.kalem)
                .environmentObject(merkez)
                .environmentObject(rota)
                .onOpenURL { rota.git($0.absoluteString) }
                .onContinueUserActivity(CSSearchableItemActionType) { a in
                    guard let id = a.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
                    if id.hasPrefix("bolum/") { rota.git("kenar://bolum/" + id.dropFirst(6)) } else { rota.git("kenar://kutu") }
                }
        }
        .onChange(of: faz) { _, yeni in
            guard yeni == .active else { return }
            if let r = Depo.rotaAl() { rota.git(r) }
            merkez.odakDegisti()
            Task { await merkez.esitle() }
        }
    }
}

struct AnaGorunum: View {
    @EnvironmentObject var merkez: Merkez
    @EnvironmentObject var rota: Rota

    var body: some View {
        Group {
            if merkez.d.metin == nil {
                KurulumEkrani()
            } else if merkez.odak {
                NavigationStack { OkuEkrani(odakKipi: true) }
            } else {
                TabView(selection: $rota.sekme) {
                    MetinEkrani().tabItem { Label("Metin", systemImage: "text.book.closed") }.tag(0)
                    KutuEkrani().tabItem { Label("Kutu", systemImage: "tray") }.badge(merkez.d.kutu.count).tag(1)
                    NavigationStack { OkuEkrani(odakKipi: false) }.tabItem { Label("Oku", systemImage: "book") }.tag(2)
                    HaritaEkrani().tabItem { Label("Harita", systemImage: "point.3.connected.trianglepath.dotted") }.tag(3)
                    AnlatEkrani().tabItem { Label("Anlat", systemImage: "waveform") }.tag(4)
                }
            }
        }
        .task {
            #if DEBUG
            Onizleme.baslat(merkez, rota)
            #endif
            if !CommandLine.arguments.contains("-sekme") {
                let ayarli = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus != .notDetermined
                if !ayarli, merkez.d.metin != nil { _ = await Bildirimci.izinIste() }
            }
        }
    }
}

struct KurulumEkrani: View {
    @EnvironmentObject var merkez: Merkez
    @State private var secici = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "text.book.closed").font(.system(size: 54, weight: .light)).foregroundStyle(Color.kalem)
            Text("Kenar").font(.serif(40, .semibold))
            Text("Okuduğun her şey tek bir metne hizmet eder.\nİlk metin: Kant'ın Kopernik Devrimi.")
                .font(.serif(17)).multilineTextAlignment(.center).foregroundStyle(Color.soluk).padding(.horizontal, 28)
            Button { secici = true } label: {
                Label("Vault klasörünü seç", systemImage: "folder").font(.system(size: 17, weight: .semibold))
                    .padding(.horizontal, 22).padding(.vertical, 13)
            }
            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
            Text("iCloud Drive › Obsidian › Personel Data Management").font(.footnote).foregroundStyle(.tertiary)
            if merkez.esitleniyor { ProgressView() }
            if let h = merkez.hata { Text(h).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center).padding(.horizontal) }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.kagit)
        .fileImporter(isPresented: $secici, allowedContentTypes: [.folder]) { sonuc in
            if case .success(let u) = sonuc { merkez.klasorSecildi(u) }
        }
    }
}
