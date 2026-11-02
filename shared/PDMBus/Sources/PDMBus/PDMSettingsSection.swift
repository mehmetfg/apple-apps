// The "PDM Ağı" section for a settings screen. Interface text is Turkish.
//   selectsVault: true  → the app has no vault folder of its own: the section shows "Vault klasörünü seç".
//   selectsVault: false → the app has its own folder row (VocuTeach, Vitrin): the section shows only the status.
#if canImport(SwiftUI) && os(iOS)
import SwiftUI
import UniformTypeIdentifiers

public struct PDMSettingsSection: View {
    let bus: PDMBus
    let selectsVault: Bool
    @State private var picking = false
    @State private var folder: String?
    @State private var lastText: String?
    @State private var lastDate: Date?
    @State private var pending = 0
    @State private var working = false

    public init(bus: PDMBus, selectsVault: Bool = true) {
        self.bus = bus
        self.selectsVault = selectsVault
    }

    public var body: some View {
        Section {
            if selectsVault {
                if let folder {
                    LabeledContent("Klasör", value: folder)
                } else {
                    Button { picking = true } label: { Label("Vault klasörünü seç", systemImage: "folder.badge.plus") }
                }
            }
            if let lastText {
                LabeledContent("Durum") { Text(lastText).multilineTextAlignment(.trailing) }
            }
            if let lastDate {
                LabeledContent("Son eşitleme", value: lastDate.formatted(.relative(presentation: .named)))
            }
            if pending > 0 { LabeledContent("Bekleyen olay", value: "\(pending)") }
            Button {
                Task { await syncNow() }
            } label: {
                Label(working ? "Eşitleniyor…" : "Şimdi eşitle", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(working)
            if selectsVault, folder != nil {
                Button("Bağlantıyı kaldır", role: .destructive) { PDMVault.forget(); reload() }
            }
        } header: {
            Text("PDM Ağı")
        } footer: {
            Text(selectsVault
                 ? "iCloud Drive › Obsidian › Personel Data Management'ı seç. Uygulama ilerlemeni `_bus/events/` altına olay olarak yazar; öteki uygulamalar oradan görür."
                 : "İlerlemen `_bus/events/` altına olay olarak gider; günün odak kelimeleri `_bus/state/`'ten gelir.")
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { r in
            if case .success(let u) = r {
                PDMVault.save(u)
                reload()
                Task { await syncNow() }
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        folder = PDMVault.simulatorOverride?.lastPathComponent ?? PDMVault.resolve()?.lastPathComponent
        let s = bus.lastSync
        lastText = s.text
        lastDate = s.date
        pending = bus.pendingCount
    }

    private func syncNow() async {
        working = true
        _ = await bus.sync()
        working = false
        reload()
    }
}
#endif
