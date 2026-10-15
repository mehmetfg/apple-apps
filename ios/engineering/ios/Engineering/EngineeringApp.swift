import SwiftUI

@main
struct EngineeringApp: App {
    @State private var ilerleme = Ilerleme()

    var body: some Scene {
        WindowGroup {
            KokEkran()
                .environment(ilerleme)
                .tint(Tema.vurgu)
        }
    }
}

struct KokEkran: View {
    @State private var sekme = UserDefaults.standard.integer(forKey: "sekme")
    /// Sınama: `-ders ALG-05-quick -adim 6` doğrudan o dersin o adımını açar.
    @State private var dogrudan: Ders? = UserDefaults.standard.string(forKey: "ders").flatMap { Kutuphane.shared.dersler[$0] }

    var body: some View {
        TabView(selection: $sekme) {
            YolEkrani()
                .terimSecimi()
                .tabItem { Label("Path", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                .tag(0)
            LabEkrani()
                .tabItem { Label("Lab", systemImage: "flask") }
                .tag(1)
            SozlukEkrani()
                .tabItem { Label("Words", systemImage: "character.book.closed") }
                .tag(2)
        }
        .fullScreenCover(item: $dogrudan) { DersEkrani(ders: $0, baslangic: UserDefaults.standard.integer(forKey: "adim")) }
    }
}
