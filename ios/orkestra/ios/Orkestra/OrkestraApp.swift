// Orkestra — bütün süreçlerin ilerlemesini tek yerden gösteren, aksayanı bulan ve sıradaki hamleyi söyleyen
// koordinasyon uygulaması. Salt okur: hiçbir sürece veri yazmaz; elle veri girişi yoktur.
import BackgroundTasks
import SwiftUI
import UserNotifications

final class Rota: ObservableObject {
    static let shared = Rota()
    @Published var sekme = 0
    @Published var surec: String?
    @Published var hacim = false
}

final class Temsilci: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Bildirimci.kur()
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound, .list] }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let bilgi = response.notification.request.content.userInfo
        let id = bilgi["surec"] as? String ?? ""
        let acilis = bilgi["acilis"] as? String ?? ""
        switch response.actionIdentifier {
        case "ertele":
            if !id.isEmpty { Depo.ertele(id) }
        case "ac":
            if let u = URL(string: acilis), !acilis.isEmpty {
                await UIApplication.shared.open(u)
            } else {
                await MainActor.run { Rota.shared.sekme = 0; Rota.shared.surec = id.isEmpty ? nil : id }
            }
        default:
            await MainActor.run { Rota.shared.sekme = 0; Rota.shared.surec = id.isEmpty ? nil : id }
        }
    }
}

@main
struct OrkestraApp: App {
    @UIApplicationDelegateAdaptor(Temsilci.self) var temsilci
    @StateObject private var merkez = Merkez()
    @StateObject private var rota = Rota.shared
    @Environment(\.scenePhase) private var faz
    static let gorev = "com.fatihgocgun.orkestra.tazele"

    var body: some Scene {
        WindowGroup {
            AnaGorunum()
                .preferredColorScheme(.dark)
                .tint(Color(red: 0.62, green: 0.56, blue: 1.0))
                .environmentObject(merkez)
                .environmentObject(rota)
                .onOpenURL { url in
                    // orkestra://surec/<id> · orkestra://bugun · orkestra://harita · orkestra://hacim
                    let parca = url.host() ?? ""
                    switch parca {
                    case "surec": rota.sekme = 1; rota.surec = url.pathComponents.dropFirst().first
                    case "harita": rota.sekme = 2
                    case "zaman": rota.sekme = 3
                    case "hacim": rota.sekme = 3; rota.hacim = true
                    default: rota.sekme = 0
                    }
                }
        }
        .onChange(of: faz) { _, yeni in
            if yeni == .active { Task { await merkez.tazele() } }
            if yeni == .background { OrkestraApp.arkaPlaniKur() }
        }
        .backgroundTask(.appRefresh(OrkestraApp.gorev)) {
            OrkestraApp.arkaPlaniKur()
            let m = await Merkez()
            await m.tazele()
        }
    }

    static func arkaPlaniKur() {
        let r = BGAppRefreshTaskRequest(identifier: gorev)
        r.earliestBeginDate = .now.addingTimeInterval(45 * 60)
        try? BGTaskScheduler.shared.submit(r)
    }
}

struct AnaGorunum: View {
    @EnvironmentObject var merkez: Merkez
    @EnvironmentObject var rota: Rota

    var body: some View {
        Group {
            if merkez.veri == nil && !merkez.bagli {
                KurulumEkrani()
            } else {
                TabView(selection: $rota.sekme) {
                    BugunEkrani().tabItem { Label("Bugün", systemImage: "music.note.list") }.tag(0)
                    SureclerEkrani().tabItem { Label("Süreçler", systemImage: "square.stack.3d.up") }.tag(1)
                    HaritaEkrani().tabItem { Label("Akış", systemImage: "point.3.connected.trianglepath.dotted") }.tag(2)
                    ZamanEkrani().tabItem { Label("Partisyon", systemImage: "calendar.day.timeline.left") }.tag(3)
                    KilavuzEkrani().tabItem { Label("Kılavuz", systemImage: "book.closed") }.tag(4)
                }
            }
        }
        .task {
            #if DEBUG
            await Onizleme.baslat(merkez, rota)
            #endif
            if await !Bildirimci.izinVar(), !CommandLine.arguments.contains("-sekme") { _ = await Bildirimci.izinIste() }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                merkez.hesapla()
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
            Image(systemName: "music.note.list").font(.system(size: 56, weight: .light)).foregroundStyle(.tint)
            Text("Orkestra").font(.yuvarlak(34, .bold))
            Text("Bütün süreçlerin tek partisyonu. Vault klasörünü bir kez seç; gerisini Orkestra okur — elle veri girişi yok.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 30)
            Button { secici = true } label: {
                Label("Vault klasörünü seç", systemImage: "folder").font(.system(size: 17, weight: .semibold))
                    .padding(.horizontal, 22).padding(.vertical, 13)
            }
            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
            Text("iCloud Drive › Obsidian › Personel Data Management").font(.footnote).foregroundStyle(.tertiary)
            if let h = merkez.hata { Text(h).font(.footnote).foregroundStyle(.red).padding(.horizontal) }
            Spacer()
        }
        .fileImporter(isPresented: $secici, allowedContentTypes: [.folder]) { sonuc in
            if case .success(let u) = sonuc { merkez.klasorSecildi(u) }
        }
    }
}
