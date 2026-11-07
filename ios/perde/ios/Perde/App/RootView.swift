import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Keşfet", systemImage: "sparkles.tv") {
                DiscoverView()
            }
            Tab("Listem", systemImage: "list.star") {
                LibraryView()
            }
            Tab("Tara", systemImage: "camera.viewfinder") {
                ScannerView()
            }
        }
    }
}
