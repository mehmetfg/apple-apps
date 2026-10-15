// iPhone entry point.
import SwiftUI

@main
struct AtriumApp: App {
    @StateObject private var store = VaultStore()
    @StateObject private var router = Router()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(router)
                .onAppear { applyLaunchArguments() }
        }
    }

    /// `-section apps` / `-open <path>` let screenshots and tests jump straight to a screen.
    private func applyLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-section"), i + 1 < args.count, let s = AppSection(rawValue: args[i + 1]) { router.section = s }
        if let i = args.firstIndex(of: "-open"), i + 1 < args.count {
            let p = args[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { router.open(p) }
        }
        if let i = args.firstIndex(of: "-day"), i + 1 < args.count {
            let d = args[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                var p = router.stacks[router.section] ?? NavigationPath()
                p.append(DayRoute(day: d))
                router.stacks[router.section] = p
            }
        }
    }
}

