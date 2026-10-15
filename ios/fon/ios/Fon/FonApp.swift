import SwiftUI

@main
struct FonApp: App {
    @StateObject private var calar = Calar.shared
    @Environment(\.scenePhase) private var evre

    var body: some Scene {
        WindowGroup {
            AnaEkran()
                .environmentObject(calar)
                .onOpenURL { url in
                    // Paylaş › Fon ile gelen tek dosya.
                    let erisim = url.startAccessingSecurityScopedResource()
                    defer { if erisim { url.stopAccessingSecurityScopedResource() } }
                    if Depo.uzantilar.contains(url.pathExtension.lowercased()) { try? Depo.iceriAl(url) }
                    calar.yenile()
                }
        }
        .onChange(of: evre) { _, yeni in
            if yeni == .active { calar.yenile() }
        }
    }
}
