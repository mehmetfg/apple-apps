// SBS — personal health information system. Three tabs in the manner of the Health app:
// İçgörüler (Insights) · Uzun Ömür (Longevity) · Göz At (Browse).
// The data comes from two places: SBS/state/sbs.json in the vault (labs, episodes, conditions, the ledger)
// and Apple Health on this phone (sleep, movement, heart, weight).
import PDMBus
import SwiftUI

@main
struct SBSApp: App {
    @StateObject private var store = Store.shared
    @StateObject private var health = Health.shared
    @Environment(\.scenePhase) private var phase
    @State private var tab = ProcessInfo.processInfo.environment["SBS_TAB"] ?? "insights"

    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                Tab("İçgörüler", systemImage: "heart.fill", value: "insights") { InsightsView() }
                Tab("Uzun Ömür", systemImage: "camera.macro", value: "longevity") { LongevityView() }
                Tab("Göz At", systemImage: "square.grid.2x2.fill", value: "browse") { BrowseView() }
            }
            .environment(\.locale, Locale(identifier: "tr_TR"))
            .environmentObject(store)
            .environmentObject(health)
            .task { await start() }
            .onChange(of: phase) { _, p in if p == .active { Task { await refresh() } } }
        }
    }

    private func start() async {
        await store.load()
        if !UserDefaults.standard.bool(forKey: "health.asked") {
            UserDefaults.standard.set(true, forKey: "health.asked")
            await health.requestAccess()
        }
        await refresh()
    }

    private func refresh() async {
        store.bus.emitOpenedToday()
        await health.refresh()
        await store.load()
        if !ProcessInfo.processInfo.arguments.contains("-demoHealth") { await store.writeDays(health.days) }
        await store.flushInbox()
    }
}
