// Memories — İngilizce Ön Çalışma, iPhone (iOS 18+).
// Sekmeler: Bugün · Dinle · Oku · Metin (tek parça + Türkçesi + sesli oku ve kaydet) · Ayarlar.
// Akış: ① mobilde çalış → ② Mac'te yaz (Cümle Tezgâhı) → ③ çözümle (ertesi sabah). Paket bir gün önce hazır.
import SwiftUI
import UserNotifications
import BackgroundTasks

enum Sekme: String, Hashable { case bugun, dinle, oku, kaydet, ayarlar }

final class UygulamaTemsilcisi: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let gorev = "com.fatihgocgun.memories.esitle"
    @MainActor static weak var depo: Depo?
    @MainActor static var rota: ((String) -> Void)?
    @MainActor static var bekleyenRota: String?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.gorev, using: nil) { gorev in
            guard let g = gorev as? BGAppRefreshTask else { gorev.setTaskCompleted(success: false); return }
            Self.planla()
            let is_ = Task { @MainActor in
                guard let depo = UygulamaTemsilcisi.depo else { g.setTaskCompleted(success: false); return }
                let sonuc = await depo.esitleSimdi()
                if let gun = sonuc.yeniCozum, let c = depo.cozumler[gun] { await Bildirim.cozumGeldi(c) }
                g.setTaskCompleted(success: true)
            }
            g.expirationHandler = { is_.cancel() }
        }
        return true
    }

    /// Arka plan yenilemesi: sistem uygun gördüğünde (en erken 1 saat sonra). Yeni paket/çözüm gelince bildirim planlanır.
    static func planla() {
        let r = BGAppRefreshTaskRequest(identifier: gorev)
        r.earliestBeginDate = Date(timeIntervalSinceNow: 3600)
        try? BGTaskScheduler.shared.submit(r)
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse) async {
        let rota = r.notification.request.content.userInfo["rota"] as? String ?? "bugun"
        await MainActor.run {
            if let f = UygulamaTemsilcisi.rota { f(rota) } else { UygulamaTemsilcisi.bekleyenRota = rota }
        }
    }
}

@main
struct MemoriesApp: App {
    @UIApplicationDelegateAdaptor(UygulamaTemsilcisi.self) var temsilci
    @StateObject private var depo = Depo()
    @StateObject private var oynatici = Oynatici()
    @Environment(\.scenePhase) private var faz
    @State private var sekme: Sekme = .bugun
    @State private var cozumAcik = false
    @State private var okuHedef: Int?
    @State private var bant: String?

    var body: some Scene {
        WindowGroup {
            TabView(selection: $sekme) {
                BugunEkrani(sekme: $sekme).tabItem { Label("Bugün", systemImage: "sun.max") }.tag(Sekme.bugun)
                DinleEkrani().tabItem { Label("Dinle", systemImage: "headphones") }.tag(Sekme.dinle)
                OkuEkrani(hedef: $okuHedef).tabItem { Label("Oku", systemImage: "text.book.closed") }.tag(Sekme.oku)
                KayitEkrani().tabItem { Label("Metin", systemImage: "doc.text") }.tag(Sekme.kaydet)
                AyarlarEkrani().tabItem { Label("Ayarlar", systemImage: "gearshape") }.tag(Sekme.ayarlar)
            }
            .environmentObject(depo)
            .environmentObject(oynatici)
            .tint(Tema.vurgu)
            .environment(\.locale, Locale(identifier: "tr_TR"))
            .sheet(isPresented: $cozumAcik) {
                if let c = depo.sonCozum { CozumEkrani(cozum: c).environmentObject(depo) }
            }
            .overlay(alignment: .top) {
                if let bant {
                    Label(bant, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background { Capsule().fill(Tema.yesil.gradient) }
                        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                        .padding(.top, 6).padding(.horizontal, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: PasteboardCopy.copied)) { n in
                let yazi = n.object as? String ?? "Panoda"
                withAnimation(.spring(duration: 0.3)) { bant = yazi }
                Task {
                    try? await Task.sleep(for: .seconds(2.5))
                    if bant == yazi { withAnimation { bant = nil } }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: PasteboardCopy.openSentence)) { n in
                // Widget'ın YZ düğmesi: uygulama açıldı, istem panoda; o cümle Oku'da önde
                sekme = .oku
                okuHedef = n.object as? Int
            }
            .onOpenURL { git($0.host() ?? "") }
            .onAppear {
                oynatici.depo = depo
                UygulamaTemsilcisi.depo = depo
                UygulamaTemsilcisi.rota = { git($0) }
                if let r = UygulamaTemsilcisi.bekleyenRota { UygulamaTemsilcisi.bekleyenRota = nil; git(r) }
            }
            .task {
                await depo.esitleSimdi()
                await Bildirim.planla(depo)
            }
            .onChange(of: faz) { _, yeni in
                switch yeni {
                case .active:
                    let eski = Set(depo.cozumler.keys)
                    Task {
                        await depo.esitleSimdi()
                        if let g = Set(depo.cozumler.keys).subtracting(eski).max(), let c = depo.cozumler[g] { await Bildirim.cozumGeldi(c) }
                    }
                case .background:
                    UygulamaTemsilcisi.planla()
                    depo.widgetYaz()
                default: break
                }
            }
        }
    }

    private func git(_ rota: String) {
        switch rota {
        case "dinle":
            sekme = .dinle
            if let p = depo.guncel, !oynatici.caliyor { oynatici.cal(p) }
        case "oku": sekme = .oku
        case "kaydet": sekme = .kaydet
        case "cozum": sekme = .bugun; cozumAcik = depo.sonCozum != nil
        case "ayarlar": sekme = .ayarlar
        default: sekme = .bugun
        }
    }
}
