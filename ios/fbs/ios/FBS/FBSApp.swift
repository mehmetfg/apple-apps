// FBS — personal finance information system. Three tabs: Özet · Takvim · Göz At.
// Data: FBS/state/fbs.json in the vault (documents processed on the Mac) + what is entered on this phone.
import PDMBus
import SwiftUI

enum AddMode: String, Identifiable, CaseIterable {
    case expense, income, contract, product, document
    var id: String { rawValue }
    var name: String {
        switch self {
        case .expense: return "Gider"
        case .income: return "Gelir"
        case .contract: return "Sözleşme"
        case .product: return "Garanti"
        case .document: return "Belge"
        }
    }
    var symbol: String {
        switch self {
        case .expense: return "minus.circle.fill"
        case .income: return "plus.circle.fill"
        case .contract: return "doc.text.fill"
        case .product: return "checkmark.shield.fill"
        case .document: return "doc.viewfinder.fill"
        }
    }
}

@MainActor
final class Router: ObservableObject {
    static let shared = Router()
    @Published var add: AddMode?
}

@main
struct FBSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = Store.shared
    @StateObject private var router = Router.shared
    @Environment(\.scenePhase) private var phase
    @State private var tab = ProcessInfo.processInfo.environment["FBS_TAB"] ?? "overview"

    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                Tab("Özet", systemImage: "chart.pie.fill", value: "overview") { OverviewView() }
                Tab("Takvim", systemImage: "calendar", value: "calendar") { CalendarView() }
                Tab("Göz At", systemImage: "square.grid.2x2.fill", value: "browse") { BrowseView() }
            }
            .environment(\.locale, Day.tr)
            .environmentObject(store)
            .environmentObject(router)
            .sheet(item: $router.add) { mode in AddSheet(mode: mode).environmentObject(store) }
            .task { await start() }
            .onOpenURL { url in if let m = AddMode(rawValue: url.host ?? "") { router.add = m } }
            .onChange(of: phase) { _, p in if p == .active { Task { await refresh() } } }
        }
    }

    private func start() async {
        if !UserDefaults.standard.bool(forKey: "firstRun.done") {
            UserDefaults.standard.set(true, forKey: "firstRun.done")
            await store.requestNotifications()
        }
        await refresh()
    }

    private func refresh() async {
        store.bus.emitOpenedToday()
        await store.load()
        await store.pushEntries()
        await store.flushInbox()
        await store.scheduleReminders()
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        true
    }

    func application(_ application: UIApplication, configurationForConnecting s: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem { route(item.type) }
        let c = UISceneConfiguration(name: nil, sessionRole: s.role)
        c.delegateClass = SceneDelegate.self
        return c
    }

    func route(_ type: String) {
        Task { @MainActor in Router.shared.add = type == "contract" ? .contract : .expense }
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor item: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        let type = item.type
        Task { @MainActor in Router.shared.add = type == "contract" ? .contract : .expense }
        completionHandler(true)
    }
}

/// The header of a tab: large title on the left, a glass "+" menu on the right.
struct TabHeader: View {
    var title: String
    var subtitle: String?
    @EnvironmentObject private var router: Router

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.largeTitle.bold())
                if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
            }
            Spacer()
            Menu {
                ForEach(AddMode.allCases) { m in
                    Button { router.add = m } label: { Label(m.name + " ekle", systemImage: m.symbol) }
                }
            } label: {
                Image(systemName: "plus").font(.title3.weight(.semibold)).frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Kayıt ekle")
        }
        .padding(.top, 6)
    }
}
