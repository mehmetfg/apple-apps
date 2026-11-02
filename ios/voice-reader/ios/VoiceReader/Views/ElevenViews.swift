// ElevenLabs in the voice page: the voice row and its settings page (key, voice, model, quality, credits, cache).
import SwiftUI

/// Ses › ElevenLabs: choose it as the reading voice; its settings are one tap away.
struct ElevenVoiceSection: View {
    @Environment(AppModel.self) private var model
    let isSelected: Bool
    let choose: () -> Void
    private var eleven: ElevenLabs { .shared }

    var body: some View {
        Section {
            Button(action: choose) {
                HStack {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(eleven.voiceName.isEmpty ? "ElevenLabs" : eleven.voiceName).fontWeight(.semibold)
                        Text(eleven.ready ? "İnternetten · bir kez üretilir, sonra telefondan çalar" : "Önce anahtar ve ses gerekli")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .tint(.primary)
            .disabled(!eleven.ready)
            NavigationLink("ElevenLabs ayarları") { ElevenSettingsPage() }
            if isSelected, let p = model.player.elevenProblem {
                Label(p, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
            }
        } header: { Text("ElevenLabs") } footer: {
            Text("Kendi ElevenLabs hesabının sesi. Her paragraf bir kez üretilip telefonda saklanır; yeniden dinlemek kredi harcamaz. İnternet ya da kredi yoksa o paragrafı iPhone sesi okur.")
        }
    }
}

struct ElevenSettingsPage: View {
    @State private var keyText = ""
    @State private var sampleBusy = false
    private var eleven: ElevenLabs { .shared }

    var body: some View {
        @Bindable var e = ElevenLabs.shared
        Form {
            Section {
                if eleven.hasKey {
                    LabeledContent("Anahtar", value: "Keychain'de kayıtlı")
                    Button("Anahtarı sil", role: .destructive) { eleven.deleteKey() }
                } else {
                    SecureField("API anahtarı (xi-api-key)", text: $keyText)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Kaydet") { eleven.saveKey(keyText); keyText = ""; Task { await eleven.test() } }
                        .disabled(keyText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Button("Bağlantıyı dene") { Task { await eleven.test() } }.disabled(!eleven.hasKey)
                if let s = eleven.status { Text(s).font(.footnote).foregroundStyle(.secondary) }
            } header: { Text("Hesap") } footer: {
                Text("elevenlabs.io › Developers › API Keys. Anahtar yalnız bu telefonun Keychain'inde durur; koda, vault'a ya da iCloud'a yazılmaz. Kotayı görmek için anahtarda User okuma izni açık olmalı.")
            }

            if let a = eleven.subscription {
                Section("Kredi") {
                    LabeledContent("Paket", value: a.tier)
                    LabeledContent("Kalan", value: "\(a.left.formatted()) / \(a.limit.formatted()) karakter")
                    ProgressView(value: Double(a.used), total: Double(max(a.limit, 1)))
                    if let r = a.resets { LabeledContent("Yenilenme", value: r.formatted(date: .abbreviated, time: .omitted)) }
                }
            }

            Section("Ses") {
                if eleven.voices.isEmpty {
                    LabeledContent("Seçili", value: eleven.voiceName.isEmpty ? "—" : eleven.voiceName)
                    Text("Sesleri görmek için Bağlantıyı dene'ye bas.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Picker("Ses", selection: Binding(get: { eleven.voiceID }, set: { eleven.choose($0) })) {
                        ForEach(eleven.voices) { v in
                            Text(v.category.isEmpty ? v.name : "\(v.name) · \(v.category)").tag(v.id)
                        }
                    }
                }
                Button {
                    sampleBusy = true
                    Task {
                        defer { sampleBusy = false }
                        do {
                            let clip = try await eleven.synthesize("Merhaba. Kitaplarını bu sesle, istediğin hızda okuyabilirim.")
                            if let s = StudioPack.decode(clip.file) { SamplePlayer.shared.play(s) }
                        } catch { eleven.status = error.localizedDescription }
                    }
                } label: {
                    HStack { Text("Sesi dinle"); if sampleBusy { Spacer(); ProgressView() } }
                }
                .disabled(!eleven.ready || sampleBusy)
            }

            Section {
                Picker("Model", selection: $e.model) { ForEach(ElevenModel.allCases) { Text($0.name).tag($0) } }
                Picker("Kayıt kalitesi", selection: $e.quality) { ForEach(ElevenQuality.allCases) { Text($0.name).tag($0) } }
            } header: { Text("Üretim") } footer: {
                Text("Hız telefonda ayarlanır (ses perdesi korunur); bu yüzden bir paragraf her hız için yeniden üretilmez. Model ya da kalite değişince paragraflar yeniden üretilir.")
            }

            Section {
                Picker("Sınır", selection: $e.limitMB) {
                    ForEach([200, 500, 1000, 2000, 5000], id: \.self) { mb in
                        Text(mb >= 1000 ? "\(mb / 1000) GB" : "\(mb) MB").tag(mb)
                    }
                }
                if let s = eleven.stats {
                    LabeledContent("Saklanan", value: "\(s.paragraphs) paragraf · \(ByteCountFormatter.string(fromByteCount: s.bytes, countStyle: .file))")
                    LabeledContent("Süre", value: Duration.seconds(s.seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                }
                LabeledContent("Telefondan çalınan", value: "\(eleven.cachedCharacters.formatted()) karakter")
                LabeledContent("Krediyle üretilen", value: "\(eleven.networkCharacters.formatted()) karakter")
                Button("Saklananları sil", role: .destructive) { Task { await eleven.clearCache() } }
            } header: { Text("Telefonda saklanan") } footer: {
                Text("Sınır dolunca en uzun zamandır dinlenmeyen paragraflar silinir. Yedeğe girmez.")
            }
        }
        .navigationTitle("ElevenLabs")
        .navigationBarTitleDisplayMode(.inline)
        .task { await eleven.refreshStats(); if eleven.hasKey, eleven.voices.isEmpty { await eleven.test() } }
    }
}

/// Ses › Bulut sesi: Google, Azure or OpenAI as the reading voice (large free monthly allowances on the first two).
struct CloudVoiceSection: View {
    @Environment(AppModel.self) private var model
    let isSelected: Bool
    let choose: () -> Void
    private var cloud: CloudVoice { .shared }

    var body: some View {
        Section {
            Button(action: choose) {
                HStack {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cloud.ready ? cloud.displayName : "Bulut sesi").fontWeight(.semibold)
                        Text(cloud.ready ? usage : "Önce sağlayıcı, anahtar ve ses gerekli")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .tint(.primary)
            .disabled(!cloud.ready)
            NavigationLink("Bulut sesi ayarları") { CloudSettingsPage() }
            if isSelected, let p = model.player.elevenProblem {
                Label(p, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
            }
        } header: { Text("Bulut sesi · Google, Azure, OpenAI") } footer: {
            Text("Google'da ayda 1–4 milyon, Azure'da 500 bin karakter ücretsiz: yüksek hızda ayda onlarca saat. Her paragraf bir kez üretilip telefonda saklanır.")
        }
    }

    private var usage: String {
        let free = cloud.freeAllowance
        return free > 0 ? "Bu ay \(cloud.usedThisMonth.formatted()) / \(free.formatted()) ücretsiz karakter"
                        : "Bu ay \(cloud.usedThisMonth.formatted()) karakter"
    }
}

struct CloudSettingsPage: View {
    @State private var keyText = ""
    @State private var sampleBusy = false
    private var cloud: CloudVoice { .shared }

    var body: some View {
        @Bindable var c = CloudVoice.shared
        Form {
            Section {
                Picker("Sağlayıcı", selection: $c.provider) { ForEach(CloudProvider.allCases) { Text($0.name).tag($0) } }
            } footer: { Text(cloud.provider.keyHelp) }

            Section("Hesap") {
                if cloud.hasKey {
                    LabeledContent("Anahtar", value: "Keychain'de kayıtlı")
                    Button("Anahtarı sil", role: .destructive) { cloud.deleteKey() }
                } else {
                    SecureField("API anahtarı", text: $keyText).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Kaydet") { cloud.saveKey(keyText); keyText = ""; Task { await cloud.test() } }
                        .disabled(keyText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if cloud.provider == .azure {
                    TextField("Bölge (örn. westeurope)", text: $c.azureRegion).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Button("Bağlantıyı dene") { Task { await cloud.test() } }.disabled(!cloud.hasKey)
                if let s = cloud.status { Text(s).font(.footnote).foregroundStyle(.secondary) }
            }

            Section("Ses") {
                if cloud.voices.isEmpty {
                    LabeledContent("Seçili", value: cloud.voiceName.isEmpty ? "—" : cloud.voiceName)
                } else {
                    Picker("Ses", selection: Binding(get: { cloud.voiceID }, set: { cloud.choose($0) })) {
                        ForEach(cloud.voices) { v in Text("\(v.name) · \(v.detail)").tag(v.id) }
                    }
                    .pickerStyle(.navigationLink)
                }
                Button {
                    sampleBusy = true
                    Task {
                        defer { sampleBusy = false }
                        do {
                            let clip = try await cloud.synthesize("Merhaba. Kitaplarını bu sesle, istediğin hızda okuyabilirim.")
                            if let s = StudioPack.decode(clip.file) { SamplePlayer.shared.play(s) }
                        } catch { cloud.status = error.localizedDescription }
                    }
                } label: { HStack { Text("Sesi dinle"); if sampleBusy { Spacer(); ProgressView() } } }
                .disabled(!cloud.ready || sampleBusy)
            }

            Section {
                let free = cloud.freeAllowance
                LabeledContent("Bu ay", value: "\(cloud.usedThisMonth.formatted()) karakter")
                if free > 0 {
                    LabeledContent("Ücretsiz", value: "\(free.formatted()) karakter")
                    ProgressView(value: Double(min(cloud.usedThisMonth, free)), total: Double(free))
                    LabeledContent("Kalan dinleme", value: "≈ \(hours(max(0, free - cloud.usedThisMonth))) (330 kelime/dk)")
                }
                Toggle("Ücretsiz kotada kal", isOn: $c.stayFree)
            } header: { Text("Bu ayın kullanımı") } footer: {
                Text("Açıkken ücretsiz kota dolunca paragrafları iPhone sesi okur; hiçbir şey ücretlendirilmez. Sayaç bu telefonda gönderilen karakterleri sayar; asıl fatura sağlayıcının panelindedir. Telefonda saklanan paragraflar sayılmaz.")
            }
        }
        .navigationTitle("Bulut sesi")
        .navigationBarTitleDisplayMode(.inline)
        .task { if cloud.hasKey, cloud.voices.isEmpty { await cloud.test() } }
        .onChange(of: cloud.provider) { keyText = ""; Task { if cloud.hasKey { await cloud.test() } } }
    }

    /// Characters → listening time at 330 words a minute (≈ 7 characters a word with the space).
    private func hours(_ chars: Int) -> String {
        let minutes = Double(chars) / (330 * 7)
        return minutes >= 60 ? String(format: "%.0f saat", minutes / 60) : String(format: "%.0f dk", minutes)
    }
}
