import SwiftUI

@main
struct DisliApp: App {
    @State private var depo = Depo()
    @Environment(\.scenePhase) private var faz

    var body: some Scene {
        WindowGroup {
            AnaGorunum()
                .environment(depo)
                .preferredColorScheme(depo.durum.ayar.gorunum == 1 ? .light : depo.durum.ayar.gorunum == 2 ? .dark : nil)
                .onChange(of: faz) { _, yeni in if yeni == .active { depo.gunuYenile() } }
                .task {
                    Ses.acik = depo.durum.ayar.ses
                    Ses.hiz = Float(depo.durum.ayar.sesHizi)
                    Dokunus.acik = depo.durum.ayar.haptik
                }
        }
    }
}

/// Sekme dışından açılan sayfalar (widget bağlantısı, Konular'dan konu, Bugün'den oyun)
enum Acilan: Identifiable, Hashable {
    case konu(String)
    case quiz([QuizOgesi], gunluk: Bool)
    case oyun(Oyun)
    case yasa(String)

    var id: String {
        switch self {
        case .konu(let k): "k-" + k
        case .quiz(let q, _): "q-" + (q.first?.id.uuidString ?? "")
        case .oyun(let o): "o-" + o.rawValue
        case .yasa(let y): "y-" + y
        }
    }
}

struct AnaGorunum: View {
    @Environment(Depo.self) private var depo
    @State private var sekme = 0
    @State private var acilan: Acilan?

    var body: some View {
        TabView(selection: $sekme) {
            BugunEkrani(ac: { acilan = $0 }, sekmeyeGit: { sekme = $0 })
                .tabItem { Label("Bugün", systemImage: "sun.horizon") }.tag(0)
            KonularEkrani(ac: { acilan = $0 })
                .tabItem { Label("Konular", systemImage: "list.bullet.rectangle") }.tag(1)
            OyunlarEkrani(ac: { acilan = $0 })
                .tabItem { Label("Oyunlar", systemImage: "square.grid.2x2") }.tag(2)
            YasalarEkrani(ac: { acilan = $0 })
                .tabItem { Label("Yasalar", systemImage: "link") }.tag(3)
        }
        .tint(Tema.vurgu)
        .fullScreenCover(item: $acilan) { a in
            switch a {
            case .konu(let id): KonuKarti(konuId: id)
            case .quiz(let q, let g): QuizEkrani(ogeler: q, gunluk: g)
            case .oyun(let o): o.ekran
            case .yasa(let y):
                NavigationStack {
                    YasaDetay(yasaId: y, ac: { acilan = $0 })
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { acilan = nil } } }
                }
            }
        }
        .onOpenURL { url in
            // disli://konu/<id> · disli://oyun/<ad>
            guard url.scheme == "disli", let ilk = url.host() else { return }
            let son = url.pathComponents.dropFirst().first ?? ""
            if ilk == "konu", depo.konu(son) != nil { acilan = .konu(son) }
            else if ilk == "oyun", let o = Oyun(rawValue: son) { acilan = .oyun(o) }
            else if ilk == "bugun", let k = depo.durum.gununKonusu { acilan = .konu(k) }
        }
    }
}
