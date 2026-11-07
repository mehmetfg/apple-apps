// General settings, from the gear at the top left of the library: one place that opens every settings panel
// (appearance, voice, sound and music) and shows where iCloud sync stands.
import SwiftUI
import PDMBus

struct GeneralSettingsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("readingCard") private var readingCard = true
    @State private var page: Page?
    @State private var syncStatus = ""
    @State private var syncing = false
    @State private var vaultPath: String?
    @State private var vaultError: String?
    @State private var pickingVault = false
    @State private var vaultStatus = UserDefaults.standard.string(forKey: "vault.status") ?? "seçilmedi"

    /// Each step of choosing the vault, shown here and written to Library/sync-status.txt for diagnosis from the Mac.
    private func note(_ text: String) {
        UserDefaults.standard.set(text, forKey: "vault.status")
        vaultStatus = text
        model.sync.noteVaultStatus()
    }

    enum Page: String, Identifiable {
        case visual, audio
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Okuma") {
                    row("Görsel ayarlar", detail: "Yazı tipi, renkler, konuşma imleci", symbol: "textformat.size") { page = .visual }
                    row("Ses ayarları", detail: "Hız, dil, ses, müzik · \(model.currentVoiceName)", symbol: "speaker.wave.2") { page = .audio }
                    Toggle(isOn: $readingCard) {
                        Text("Kilit ekranında okuma kartı")
                        Text("Oku, işaretle, sesli not. Okuma durduktan 10 dakika sonra kalkar.")
                    }
                    .onChange(of: readingCard) { _, on in
                        if on { ReadingCard.shared.sync(model) } else { ReadingCard.shared.end() }
                    }
                }
                Section {
                    LabeledContent("Durum", value: syncStatus)
                    Button {
                        syncing = true
                        Task {
                            await model.sync.sync()
                            syncStatus = model.sync.status
                            syncing = false
                        }
                    } label: {
                        HStack {
                            Label("Şimdi eşitle", systemImage: "arrow.triangle.2.circlepath")
                            if syncing { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(syncing)
                } header: { Text("iCloud") } footer: {
                    Text("Telefonda: Dosyalar › iCloud Drive › Voice Reader.")
                }
                Section {
                    if let vaultPath {
                        LabeledContent("Klasör", value: vaultPath)
                        Button("Başka klasör seç") { note("seçici açıldı"); pickingVault = true }
                        Button("Bağlantıyı kaldır", role: .destructive) {
                            Task { await VaultMirror.shared.forget(); self.vaultPath = nil }
                        }
                    } else {
                        Button { note("seçici açıldı"); pickingVault = true } label: { Label("Vault klasörünü seç", systemImage: "folder.badge.plus") }
                    }
                    if let vaultError { Text(vaultError).font(.footnote).foregroundStyle(.red) }
                    LabeledContent("Son durum", value: vaultStatus).font(.footnote)
                } header: { Text("PDM vault (Mac ve Claude)") } footer: {
                    Text("Kaldığın yer, işaretler, notlar ve yer imleri vault'ta _araçlar/voice-reader/durum klasörüne de yazılır; Mac'teki PDM Ağı ve Claude oradan okur. Dosyalar › iCloud Drive › Obsidian › Personel Data Management klasörünü seç.")
                }
                PDMSettingsSection(bus: model.bus, selectsVault: false)
                // the system file importer (a UIDocumentPicker wrapped in a sheet over this sheet never called back:
                // "seçici açıldı" and then nothing, 2026-10-20)
                .fileImporter(isPresented: $pickingVault, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
                    switch result {
                    case .failure(let e): note("seçici hatası: \(e.localizedDescription)")
                    case .success(let urls):
                        guard let url = urls.first else { note("seçici kapatıldı, klasör seçilmedi"); return }
                        note("seçildi: \(url.lastPathComponent)")
                        Task {
                            vaultError = await VaultMirror.shared.choose(url)
                            vaultPath = await VaultMirror.shared.path
                            await model.sync.mirrorLibrary()
                            model.sync.positionsChanged()
                            vaultStatus = UserDefaults.standard.string(forKey: "vault.status") ?? ""
                        }
                    }
                }
            }
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
            .onAppear { syncStatus = model.sync.status }
            .task { vaultPath = await VaultMirror.shared.path }
            .sheet(item: $page) { p in
                switch p {
                case .visual: VisualSettingsView()
                case .audio: AudioSettingsView()
                }
            }
        }
    }

    private func row(_ title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                        Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                } icon: { Image(systemName: symbol) }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .tint(.primary)
    }
}
