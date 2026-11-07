import SwiftData
import SwiftUI

@main
struct PerdeApp: App {
    @State private var services = AppServices()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(services)
        }
        .modelContainer(for: LibraryEntry.self)
    }
}
