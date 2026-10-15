// Aşina — Oxford depomdaki bilmediğim kelimeleri her gün önüme getiren uygulama.
import SwiftUI
import UserNotifications
import BackgroundTasks

@main
struct AsinaApp: App {
    @UIApplicationDelegateAdaptor(UygulamaTemsilcisi.self) var temsilci
    @StateObject private var depo = Depo()
    @Environment(\.scenePhase) private var evre
    @AppStorage("gorunum") private var gorunum = 0

    var body: some Scene {
        WindowGroup {
            Kabuk()
                .environmentObject(depo)
                .environmentObject(depo.kasa)
                .preferredColorScheme(gorunum == 1 ? .light : gorunum == 2 ? .dark : nil)
                .task {
                    temsilci.depo = depo
                    await depo.yukle()
                    // İlk açılışta izin ister; sonrakilerde yalnız bildirim düğmelerini kaydeder.
                    _ = await Bildirim.izinIste()
                    depo.planla()
                    Self.arkaPlanIste()
                    #if DEBUG
                    Onizleme.ciz()
                    #endif
                }
                .onOpenURL { depo.ac($0) }
        }
        .onChange(of: evre) { _, yeni in
            if yeni == .active {
                Task { depo.planla(); await depo.eslestir() }
            } else if yeni == .background {
                depo.planla()
                Self.arkaPlanIste()
            }
        }
        .backgroundTask(.appRefresh(Self.tazeleKimligi)) {
            // Gece yarısından sonra widget'ın yeni günü ve bildirimler kurulsun.
            await MainActor.run { Self.arkaPlanIste() }
            let d = await Depo()
            await d.yukle()
        }
    }

    static let tazeleKimligi = "com.fatihgocgun.asina.tazele"

    static func arkaPlanIste() {
        let r = BGAppRefreshTaskRequest(identifier: tazeleKimligi)
        let yarin = Calendar.current.date(bySettingHour: 5, minute: 30, second: 0, of: Date().gun(1))
        r.earliestBeginDate = yarin
        try? BGTaskScheduler.shared.submit(r)
    }
}

final class UygulamaTemsilcisi: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var depo: Depo?

    func application(_ a: UIApplication, didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .list] }

    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse) async {
        let bilgi = r.notification.request.content.userInfo
        guard let id = bilgi["id"] as? Int else { return }
        let eylem = r.actionIdentifier
        if eylem == Bildirim.dinleEylemi {
            // Uygulama açılmadan seslendir; çalma bitene kadar bekle ki sistem süreci askıya almasın.
            let ad = bilgi["w"] as? String ?? "", url = bilgi["au"] as? String
            let oxford = (Paylasim.ayar.object(forKey: Paylasim.oxfordAnahtari) as? Bool) ?? true
            await MainActor.run { Ses.ortak.soyle(ad: ad, url: url, oxford: oxford) }
            await Ses.ortak.bekle()
            return
        }
        await MainActor.run {
            if let d = depo {
                d.bildirimEylemi(eylem, id: id)
            } else {
                // Uygulama kapalıyken gelen eylem: sonraki açılışta işlensin.
                var l = UserDefaults.standard.array(forKey: "bekleyenEylem") as? [String] ?? []
                l.append("\(eylem)|\(id)")
                UserDefaults.standard.set(l, forKey: "bekleyenEylem")
            }
        }
    }
}
