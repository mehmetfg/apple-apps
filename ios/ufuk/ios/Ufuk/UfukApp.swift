// Ufuk: reads the outside world for the bike commute — rain windows, what to wear, the light, lunch and
// evening outdoors — and relates the weather to the person's own days.
import BackgroundTasks
import PDMBus
import SwiftUI
import UserNotifications

@main
struct UfukApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = Store.shared
    @Environment(\.scenePhase) private var phase
    static let refreshTask = "com.fatihgocgun.ufuk.refresh"

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .task {
                    Notifier.registerCategories()
                    await Notifier.requestAuthorization()
                    Location.shared.request()
                    store.bus.emitOpenedToday()
                    await store.refresh()
                    #if DEBUG
                    if CommandLine.arguments.contains("-dumpNotifications") { await Notifier.dump() }
                    #endif
                }
                .onOpenURL { url in
                    if url.host == "ride" { RideActivity.start(store, kind: url.lastPathComponent == "morning" ? .morning : .evening) }
                }
        }
        .onChange(of: phase) { _, p in
            if p == .active { Task { if (store.forecast?.fetched.timeIntervalSinceNow ?? -9999) < -600 { await store.refresh() } } }
            if p == .background { Self.scheduleRefresh() }
        }
        .backgroundTask(.appRefresh(Self.refreshTask)) {
            Self.scheduleRefresh()
            await Store.shared.refresh(background: true)
        }
    }

    /// Every 30 minutes at most; iOS decides when, usually more often before the usual opening times.
    static func scheduleRefresh() {
        let r = BGAppRefreshTaskRequest(identifier: refreshTask)
        r.earliestBeginDate = .now.addingTimeInterval(30 * 60)
        try? BGTaskScheduler.shared.submit(r)
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Bugün", systemImage: "bicycle") { TodayView() }
            Tab("Gökyüzü", systemImage: "sun.horizon.fill") { SkyView() }
            Tab("Dışarı", systemImage: "figure.walk") { OutsideView() }
            Tab("Ben ve hava", systemImage: "waveform.path.ecg") { InsightView() }
        }
        .tint(.white)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// The three feeling buttons work from the lock screen without opening the app.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let leg = LegKind(rawValue: info["leg"] as? String ?? "") ?? .morning
        let id = response.actionIdentifier
        await MainActor.run {
            if id.hasPrefix("feel."), let f = Feel(rawValue: String(id.dropFirst(5))) {
                Store.shared.addFeedback(f, leg: leg, baseLayer: nil, date: response.notification.date)
            } else if id == "ride.start" {
                RideActivity.start(Store.shared, kind: leg)
            }
        }
    }
}
