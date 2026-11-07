import SwiftUI
import VisionKit

struct ScannerView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = ScanModel()
    @State private var isOnScreen = false
    @State private var failure: String?
    @State private var selectedTitle: CatalogTitle?

    var body: some View {
        content
            .onAppear {
                model.attach(services: services)
                isOnScreen = true
            }
            .onDisappear { isOnScreen = false }
            .sheet(item: $selectedTitle) { title in
                NavigationStack {
                    TitleDetailView(title: title)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Kapat") { selectedTitle = nil }
                            }
                        }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if !DataScannerViewController.isSupported {
            ContentUnavailableView(
                "Canlı tarama bu cihazda yok",
                systemImage: "camera.metering.unknown",
                description: Text("Canlı metin tarama gerçek bir iPhone'da çalışır. Bir yapımı Keşfet'teki aramayla bulabilirsin.")
            )
        } else if !services.hasTMDBKey {
            ContentUnavailableView(
                "Anahtarlar gerekli",
                systemImage: "key",
                description: Text("Tarama için önce Keşfet › Ayarlar'dan TMDB ve OMDb anahtarlarını gir.")
            )
        } else if !DataScannerViewController.isAvailable {
            ContentUnavailableView {
                Label("Kamera izni gerekli", systemImage: "camera")
            } description: {
                Text("Ayarlar › Perde bölümünden kamera iznini aç.")
            } actions: {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("Ayarları aç", destination: url)
                }
            }
        } else {
            scanner
        }
    }

    private var scanner: some View {
        ZStack(alignment: .bottom) {
            ZStack(alignment: .topLeading) {
                LiveTextScanner(
                    isActive: isOnScreen && scenePhase == .active && selectedTitle == nil,
                    onItemsChanged: { model.receive(items: $0) },
                    onFailure: { failure = $0 }
                )
                ForEach(model.badges) { badge in
                    Button {
                        selectedTitle = badge.title
                    } label: {
                        ScanBadgeLabel(badge: badge)
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .offset(x: max(8, badge.frame.minX), y: max(60, badge.frame.minY - 44))
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 8) {
                if let message = failure ?? model.issue {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .padding(8)
                        .background(.regularMaterial, in: .rect(cornerRadius: 8))
                }
                if model.foundTitles.isEmpty {
                    Text("Kamerayı film ya da dizi adının göründüğü ekrana tut")
                        .font(.footnote)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: .capsule)
                } else {
                    ScanTray(titles: model.foundTitles, ratings: model.ratings) { selectedTitle = $0 }
                }
            }
            .padding(.bottom, 8)
        }
    }
}
