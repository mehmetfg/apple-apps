import SwiftUI

@main
struct TiniApp: App {
    @StateObject private var calar = Calar.shared
    @StateObject private var ses = Ses.shared
    @StateObject private var gezinti = Gezinti()
    @Environment(\.scenePhase) private var evre

    var body: some Scene {
        WindowGroup {
            KokEkran()
                .environmentObject(calar)
                .environmentObject(ses)
                .environmentObject(gezinti)
                .onOpenURL { url in
                    // Paylaş › Tını ile gelen tek dosya.
                    let erisim = url.startAccessingSecurityScopedResource()
                    defer { if erisim { url.stopAccessingSecurityScopedResource() } }
                    if Depo.uzantilar.contains(url.pathExtension.lowercased()) { try? Depo.iceriAl(url) }
                    calar.yenile()
                }
        }
        .onChange(of: evre) { _, yeni in
            if yeni == .active {
                if Depo.bagliKlasorVar {
                    Task.detached { _ = Depo.esitle(); await MainActor.run { Calar.shared.yenile() } }
                } else {
                    calar.yenile()
                }
            }
        }
    }
}

struct KokEkran: View {
    @EnvironmentObject var calar: Calar
    @EnvironmentObject var gezinti: Gezinti
    @AppStorage("deri") private var deri: Deri = .modern

    var body: some View {
        Group {
            switch deri {
            case .modern: ModernDeri()
            case .walkman: WalkmanDeri()
            case .cowon: CowonDeri()
            }
        }
        .sheet(item: $gezinti.sayfa) { s in
            switch s {
            case .kutuphane: KutuphaneEkrani()
            case .sesLab: SesLab().presentationDetents([.medium, .large])
            case .ayarlar, .deriler: AyarlarEkrani()
            }
        }
    }
}
