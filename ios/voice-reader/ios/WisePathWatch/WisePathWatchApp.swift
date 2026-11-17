// Wise Path on the wrist (2026-11-17): what the phone is reading, its play/pause and skip keys, and today's
// listening. The voice stays on the phone; the watch is its remote.
import SwiftUI

@main
struct WisePathWatchApp: App {
    @State private var link = WristLink()

    var body: some Scene {
        WindowGroup {
            TabView {
                NowPlayingView(link: link)
                TodayView(link: link)
            }
            .tabViewStyle(.verticalPage)
            .onAppear { link.activate() }
        }
    }
}
