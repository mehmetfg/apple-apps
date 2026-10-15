// Mac entry point: one window with a sidebar, ⌘N for a new note, ⌘⇧J for today's journal.
import SwiftUI

@main
struct AtriumMac: App {
    @StateObject private var store = VaultStore()
    @StateObject private var router = Router()

    var body: some Scene {
        WindowGroup("Atrium") {
            RootView()
                .environmentObject(store)
                .environmentObject(router)
                .frame(minWidth: 980, minHeight: 680)
                .onAppear {
                    let args = ProcessInfo.processInfo.arguments
                    if let i = args.firstIndex(of: "-section"), i + 1 < args.count, let s = AppSection(rawValue: args[i + 1]) { router.section = s }
                }
        }
        .defaultSize(width: 1240, height: 840)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Yeni not") { router.composeKind = .note }.keyboardShortcut("n")
                Button("Yeni fikir") { router.composeKind = .idea }.keyboardShortcut("i", modifiers: [.command, .shift])
                Button("Bugünün günlüğü") {
                    Task { if let p = try? await store.ensureJournal() { router.open(p) } }
                }
                .keyboardShortcut("j", modifiers: [.command, .shift])
                Button("Ses kaydı") { router.showVoice = true }.keyboardShortcut("r", modifiers: [.command, .shift])
            }
            CommandGroup(after: .sidebar) {
                ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { i, s in
                    Button(s.label) { router.section = s }.keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
                }
            }
        }
        Settings { SettingsView().environmentObject(store) }
    }
}
