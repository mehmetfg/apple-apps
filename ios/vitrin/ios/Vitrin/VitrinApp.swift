import SwiftUI

@main
struct VitrinApp: App {
    @StateObject private var m = Merkez()
    @Environment(\.scenePhase) private var faz

    var body: some Scene {
        WindowGroup {
            Kok()
                .environmentObject(m)
                .preferredColorScheme(.dark)
                .tint(Renkler.vurgu)
                .task { Onizleme.calistirGerekirse(m) }
                .onChange(of: faz) { _, yeni in
                    if yeni == .active { Task { await m.tazele(sessiz: true) } }
                }
        }
    }
}

enum Sekme: Int { case vitrin, duvar, widget, hareket }

struct Kok: View {
    @EnvironmentObject var m: Merkez
    @State private var sekme: Sekme = {
        Sekme(rawValue: UserDefaults.standard.integer(forKey: "sekme")) ?? .vitrin
    }()
    @State private var acilacakWidget: UUID?

    var body: some View {
        TabView(selection: $sekme) {
            Tab("Vitrin", systemImage: "sparkles.rectangle.stack", value: Sekme.vitrin) { VitrinEkrani(sekme: $sekme) }
            Tab("Duvar", systemImage: "iphone.gen3", value: Sekme.duvar) { DuvarlarEkrani() }
            Tab("Widget", systemImage: "square.grid.2x2", value: Sekme.widget) { WidgetlarEkrani(acilacak: $acilacakWidget) }
            Tab("Hareket", systemImage: "livephoto", value: Sekme.hareket) { HareketEkrani() }
        }
        .overlay(alignment: .top) {
            if let d = m.duyuru {
                Text(d)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.12)))
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onOpenURL { u in
            guard u.scheme == "vitrin" else { return }
            if u.host == "widget", let id = UUID(uuidString: u.lastPathComponent) {
                sekme = .widget; acilacakWidget = id
            } else if u.host == "duvar" { sekme = .duvar }
            else if u.host == "hareket" { sekme = .hareket }
        }
    }
}

enum Renkler {
    static let zemin = Color(hex: "#0A0A0C")
    static let kart = Color(hex: "#16161A")
    static let kart2 = Color(hex: "#1F1F25")
    static let cizgi = Color.white.opacity(0.08)
    static let vurgu = Color(hex: "#F4B466")
    static let ikincil = Color.white.opacity(0.6)
}
