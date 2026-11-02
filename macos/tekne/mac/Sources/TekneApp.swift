import Carbon.HIToolbox
import SwiftUI

@main
struct TekneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppDelegate.model

    var body: some Scene {
        Window("Tekne", id: "main") {
            DashboardView()
                .environmentObject(model).environmentObject(model.store).environmentObject(model.tracker)
                .frame(minWidth: 980, minHeight: 640)
        }
        .defaultSize(width: 1240, height: 820)

        MenuBarExtra {
            MenuContent().environmentObject(model).environmentObject(model.store).environmentObject(model.tracker)
        } label: {
            MenuLabel().environmentObject(model).environmentObject(model.tracker)
        }

        Settings { SettingsView().environmentObject(model) }
    }
}

struct MenuLabel: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var tracker: Tracker

    var body: some View {
        let icon = tracker.manual != nil ? "record.circle" : (tracker.auto.map { $0.build ? "hammer" : "pencil.line" } ?? "sailboat")
        Label("%\(Int(model.percentOfDay.rounded())) · \(model.dueCount)", systemImage: icon)
            .labelStyle(.titleAndIcon)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let model = AppModel()
    private var hotKey: EventHotKeyRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.model.start()
        registerHotKey()
        AppUpdater.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// ⌃⌥T starts or stops the manual production timer from anywhere (same Carbon pattern as Uygulamalarım).
    private func registerHotKey() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { AppDelegate.model.toggleManual() } }
            return noErr
        }, 1, &type, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x544B4E45), id: 1)   // 'TKNE'
        RegisterEventHotKey(UInt32(kVK_ANSI_T), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKey)
    }
}
