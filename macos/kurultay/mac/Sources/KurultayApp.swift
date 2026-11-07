import AppKit
import SwiftUI

@main
struct KurultayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Window("Kurultay", id: "main") {
            MainView()
                .environmentObject(delegate.council)
                .frame(minWidth: 980, minHeight: 640)
        }
        .defaultSize(width: 1320, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Yeni kurultay") { delegate.council.selectedSession = nil; NotificationCenter.default.post(name: .newSession, object: nil) }
                    .keyboardShortcut("n")
            }
        }
        Settings {
            SettingsView().environmentObject(delegate.council)
        }
    }
}

extension Notification.Name { static let newSession = Notification.Name("kurultay.newSession") }

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let council = Council()
    private var server: BridgeServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        server = BridgeServer(council: council)
        server?.start()
        council.writePending()
        AppUpdater.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
