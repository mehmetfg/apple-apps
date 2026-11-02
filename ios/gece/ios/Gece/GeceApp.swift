// Gece: a 3–5 minute night routine for the neck, the lower back and the knees, then sleep.
// It asks about pain before and after, reads the day from Apple Health and writes every night to the PDM bus.
import PDMBus
import SwiftUI
import UserNotifications

@main
struct GeceApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = Store.shared
    @StateObject private var health = Health.shared
    @StateObject private var router = Router.shared
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            HomeView(startNow: $router.startNow)
                .environmentObject(store)
                .environmentObject(health)
                .preferredColorScheme(.dark)
                .task { await firstRun() }
                .onOpenURL { if $0.host == "start" { router.startNow = true } }
                .onChange(of: phase) { _, p in
                    if p == .active { Task { await refresh() } }
                }
        }
    }

    private func firstRun() async {
        if !UserDefaults.standard.bool(forKey: "firstRun.done") {
            UserDefaults.standard.set(true, forKey: "firstRun.done")
            await store.requestNotifications()
            await health.requestAccess()
        } else {
            store.scheduleReminder()
        }
        await refresh()
    }

    private func refresh() async {
        store.bus.emitOpenedToday()
        await health.refreshToday()
        await store.emitHealthDays()
        await store.bus.sync()
    }
}

@MainActor
final class Router: ObservableObject {
    static let shared = Router()
    @Published var startNow = false
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        if let item = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem, item.type == "start" {
            Task { @MainActor in Router.shared.startNow = true }
        }
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting s: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let c = UISceneConfiguration(name: nil, sessionRole: s.role)
        c.delegateClass = SceneDelegate.self
        return c
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        switch response.actionIdentifier {
        case "later": await MainActor.run { Store.shared.snooze() }
        default: await MainActor.run { Router.shared.startNow = true }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        await MainActor.run { Router.shared.startNow = true }
        return true
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if connectionOptions.shortcutItem?.type == "start" {
            Task { @MainActor in Router.shared.startNow = true }
        }
    }
}
