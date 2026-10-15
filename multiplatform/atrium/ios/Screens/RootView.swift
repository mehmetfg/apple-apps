// Top-level layout: tab bar on iPhone, sidebar on Mac. Also the first-run vault picker and settings.
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject var store: VaultStore
    @EnvironmentObject var router: Router
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if store.hasVault {
                layout
            } else {
                SetupView()
            }
        }
        .tint(Palette.accent)
        .sheet(item: $router.composeKind) { ComposeSheet(kind: $0) }
        .sheet(isPresented: $router.showVoice) { VoiceSheet() }
        .sheet(isPresented: $router.showSettings) { SettingsView() }
        .overlay(alignment: .top) { Toast() }
        .task { if store.hasVault { await store.refresh() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, store.hasVault { Task { await store.refresh() } }
        }
    }

    @ViewBuilder
    private var layout: some View {
        #if os(iOS)
        TabView(selection: $router.section) {
            ForEach(AppSection.allCases) { s in
                Tab(s.label, systemImage: s.symbol, value: s, role: s == .search ? .search : nil) {
                    NavigationStack(path: router.path(s)) {
                        screen(s)
                            .navigationTitle(s == .today ? "" : s.label)
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Menu {
                                        Button { router.composeKind = .idea } label: { Label("Fikir", systemImage: "lightbulb") }
                                        Button { router.composeKind = .journal } label: { Label("Günlüğe yaz", systemImage: "book.closed") }
                                        Button { router.composeKind = .note } label: { Label("Not", systemImage: "square.and.pencil") }
                                        Button { router.showVoice = true } label: { Label("Ses kaydı", systemImage: "mic") }
                                        Divider()
                                        Button { router.showSettings = true } label: { Label("Ayarlar", systemImage: "gearshape") }
                                    } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                                }
                            }
                            .atriumDestinations()
                            .noteLinks()
                    }
                }
            }
        }
        #else
        NavigationSplitView {
            List(selection: Binding(get: { router.section }, set: { if let s = $0 { router.section = s } })) {
                Section("Atrium") {
                    ForEach(AppSection.allCases) { s in Label(s.label, systemImage: s.symbol).tag(s) }
                }
                Section("Yakala") {
                    Button { router.composeKind = .idea } label: { Label("Fikir", systemImage: "lightbulb") }
                    Button { Task { if let p = try? await store.ensureJournal() { router.open(p) } } } label: { Label("Bugünün günlüğü", systemImage: "book.closed") }
                    Button { router.composeKind = .note } label: { Label("Not", systemImage: "square.and.pencil") }
                    Button { router.showVoice = true } label: { Label("Ses kaydı", systemImage: "mic") }
                }
                .buttonStyle(.plain)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            NavigationStack(path: router.path(router.section)) {
                screen(router.section)
                    .navigationTitle(router.section.label)
                    .atriumDestinations()
                    .noteLinks()
            }
            .id(router.section)
        }
        .toolbar {
            ToolbarItem {
                Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .keyboardShortcut("r")
            }
        }
        #endif
    }

    @ViewBuilder
    private func screen(_ s: AppSection) -> some View {
        switch s {
        case .today: TodayScreen()
        case .timeline: TimelineScreen()
        case .library: LibraryScreen()
        case .apps: AppsScreen()
        case .search: SearchScreen()
        }
    }
}

struct Toast: View {
    @EnvironmentObject var store: VaultStore
    var body: some View {
        if let m = store.message {
            Text(m)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(radius: 8, y: 3)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: m) {
                    try? await Task.sleep(nanoseconds: 2_800_000_000)
                    withAnimation { store.message = nil }
                }
                .onTapGesture { store.message = nil }
        }
    }
}

struct SetupView: View {
    @EnvironmentObject var store: VaultStore
    @State private var picking = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            CalendarPage(date: Date(), size: 1.3)
            Text("Atrium").font(.system(size: 44, weight: .bold, design: .serif))
            Text("Vault'unun evi. Gelişmeleri gör, oku, düzenle; günlük ve fikir yaz.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 32)
            Button { picking = true } label: {
                Label("Vault klasörünü seç", systemImage: "folder.badge.plus").font(.headline).padding(.horizontal, 20).padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            Text("iCloud Drive › Obsidian › Personel Data Management").font(.footnote).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.page)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { store.chooseVault(url) }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: VaultStore
    @Environment(\.dismiss) private var dismiss
    @State private var picking = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Vault") {
                    LabeledContent("Klasör", value: store.root?.lastPathComponent ?? "—")
                    LabeledContent("Not", value: Format.number(store.records.count))
                    LabeledContent("Kelime", value: Format.number(store.totalWords))
                    LabeledContent("İnmeyi bekleyen", value: "\(store.pendingDownloads)")
                    if let s = store.lastScan { LabeledContent("Son tarama", value: "\(TurkishCalendar.journalTitle(s)) \(Format.time(s))") }
                    Button("Yeniden tara") { Task { await store.refresh() } }
                    Button("Başka klasör seç") { picking = true }
                }
                Section("Nasıl çalışır") {
                    Text("Atrium vault dosyalarını doğrudan okur ve yazar; Mac'e ya da bir sunucuya bağlı değildir. Değişiklikler iCloud ile Obsidian'a ve öteki cihaza gider. Ses kayıtları Kıvılcım'ın klasörüne düşer; yazıya dökme Mac'te yerel Whisper ile olur.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ayarlar")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Tamam") { dismiss() } } }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { store.chooseVault(url) }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 420)
        #endif
    }
}
