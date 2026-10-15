// Saray — evini İngilizce gör. Kamerayı aç: eşyanın adı eşyanın üstünde, sesiyle. Etiketler odada kalır; döndüğünde yerindedir.
// Sekmeler: Kamera · Sözlük. Adresler: saray://kamera · saray://kamera/<oda> · saray://sozluk
import AppIntents
import SwiftUI

final class Rota: ObservableObject {
    static let shared = Rota()
    @Published var sekme = 0
    func git(_ adres: String) {
        guard let u = URL(string: adres), u.scheme == "saray" else { return }
        if u.host() == "sozluk" { sekme = 1; return }
        sekme = 0
        if let oda = u.pathComponents.filter({ $0 != "/" }).first { Task { @MainActor in Goz.shared.odaDegistir(oda) } }
    }
}

final class Temsilci: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting s: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let k = options.shortcutItem { DispatchQueue.main.async { Rota.shared.git("saray://kamera/\(k.type)") } }
        let c = UISceneConfiguration(name: nil, sessionRole: s.role)
        c.delegateClass = SahneTemsilcisi.self
        return c
    }
}

/// Simgeye basılı tut: Mutfak · Banyo · Salon · Yatak odası — kamera o odada açılır.
final class SahneTemsilcisi: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        Rota.shared.git("saray://kamera/\(shortcutItem.type)"); return true
    }
}

@main
struct SarayApp: App {
    @UIApplicationDelegateAdaptor(Temsilci.self) var temsilci
    @StateObject private var goz = Goz.shared
    @StateObject private var ses = Ses.shared
    @StateObject private var rota = Rota.shared
    @Environment(\.scenePhase) private var faz

    var body: some Scene {
        WindowGroup {
            TabView(selection: $rota.sekme) {
                KameraEkrani().tabItem { Label("Kamera", systemImage: "camera.viewfinder") }.tag(0)
                SozlukEkrani().tabItem { Label("Sözlük", systemImage: "list.bullet.rectangle") }.tag(1)
            }
            .tint(.saray)
            .environmentObject(goz)
            .environmentObject(ses)
            .onOpenURL { rota.git($0.absoluteString) }
            .task {
                #if DEBUG
                if let i = CommandLine.arguments.firstIndex(of: "-sekme"), i + 1 < CommandLine.arguments.count, let s = Int(CommandLine.arguments[i + 1]) { rota.sekme = s }
                #endif
            }
        }
        .onChange(of: faz) { _, yeni in
            if yeni == .background { goz.durdur() }
        }
    }
}

struct KamerayiAcNiyeti: AppIntent {
    static let title: LocalizedStringResource = "Saray kamerasını aç"
    static let description = IntentDescription("Kamerayı açar; eşyaların İngilizce adı üstlerinde görünür.")
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult { await MainActor.run { Rota.shared.sekme = 0 }; return .result() }
}

struct SarayKestirmeleri: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: KamerayiAcNiyeti(), phrases: ["\(.applicationName) kamerasını aç", "\(.applicationName) ile evimi göster"],
                    shortTitle: "Kamerayı aç", systemImageName: "camera.viewfinder")
    }
}

extension Color {
    static let saray = Color(red: 0.95, green: 0.70, blue: 0.20)      // altın: sarayın rengi
}
