// The library, the app's first page and its point (2026-10-28: books first). On top the book to go on with, then
// every book: as a bookcase of spines (Kitaplık), a shop window, a grid or a list, by shelf (süren, okunacak,
// bitenler) or folder; a thin line with today's listening and the automation; the folders. Statistics, the moving
// modes and the notes are keys at the top. Adding from Files or the clipboard; a mini player while reading.
import PDMBus
import SwiftUI
import UniformTypeIdentifiers

enum FolderScope: Hashable {
    case all, unfiled, named(String)
    var title: String {
        switch self {
        case .all: "Tüm belgeler"
        case .unfiled: "Klasörsüz"
        case .named(let n): n
        }
    }
    var folderName: String? { if case .named(let n) = self { n } else { nil } }

    var symbol: String {
        switch self {
        case .all: "books.vertical.fill"
        case .unfiled: "tray.fill"
        case .named(let n):
            switch n {
            case "Felsefe": "building.columns.fill"
            case "Bilimler": "atom"
            case "Mühendislik": "gearshape.2.fill"
            case "Edebiyat": "text.book.closed.fill"
            default: "folder.fill"
            }
        }
    }

    var tint: Color {
        switch folderName {
        case "Felsefe": Color(red: 0.62, green: 0.52, blue: 1.0)
        case "Bilimler": Color(red: 0.35, green: 0.78, blue: 0.95)
        case "Mühendislik": Color(red: 1.0, green: 0.62, blue: 0.30)
        case "Edebiyat": Color(red: 1.0, green: 0.45, blue: 0.56)
        default: Color(white: 0.75)
        }
    }
}

enum Route: Hashable {
    case folder(FolderScope)
    case reader(UUID)
    case notes
}

struct LibraryScreen: View {
    @Environment(AppModel.self) private var model
    @State private var path: [Route] = []
    @State private var importerShown = false
    @State private var promptShown = false
    @State private var elevenShown = false
    @State private var cursorShown = false       // test hook -cursortest: the Konuşma İmleci page
    @State private var cloudShown = false
    @State private var newFolderShown = false
    @State private var newFolderName = ""
    @State private var statsTab: StatsTab?
    @State private var settingsShown = false
    @State private var automationShown = false
    @State private var scanShown = false
    @State private var photosShown = false
    @State private var expandTest: ExpandSource?

    static let importTypes: [UTType] = [
        .pdf, .epub, .plainText, .text, .html, .rtf, .rtfd,
        UTType("org.openxmlformats.wordprocessingml.document") ?? .data,
        UTType("net.daringfireball.markdown") ?? .plainText,
        UTType("com.microsoft.word.doc") ?? .data,
        UTType("org.oasis-open.opendocument.text") ?? .data,
        UTType("com.amazon.mobi") ?? .data, UTType("com.amazon.azw3") ?? .data, UTType("com.amazon.azw") ?? .data,
        UTType("org.fictionbook.fb2") ?? .xml,
    ]

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $path) {
            ZStack {
                InkBackground()
                ScrollView {
                    if model.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                        home
                    } else {
                        VStack(alignment: .leading, spacing: 18) {
                            DocumentCollection(docs: model.documents(in: .all, applyFilter: false), style: .list, onOpen: open)
                            // the same field also finds sentences inside the books (BookSearch.swift)
                            LibrarySentenceResults(query: model.searchText) { h in show(h) }
                        }
                        .padding(.top, 8)
                    }
                }
                .scrollIndicators(.hidden)
                .softScrollEdges()
            }
            .navigationTitle("Kütüphane")
            .searchable(text: $model.searchText, prompt: "Kitap, yazar ya da cümle ara")
            .toolbar { settingsButton; statsButton; roadMenu; addMenu }
            .sheet(isPresented: $settingsShown) { GeneralSettingsSheet() }
            .sheet(isPresented: $automationShown) { AutomationSheet() }
            .sheet(item: $statsTab) { StatsScreen(tab: $0) }
            .sheet(isPresented: Binding(get: { model.marksSheetDoc != nil }, set: { if !$0 { model.marksSheetDoc = nil } })) {
                if let id = model.marksSheetDoc {
                    MarksSheet(documentID: id) { doc, offset in
                        model.revealRequest = (doc, offset)
                        open(doc)
                    }
                    .presentationDetents([.medium, .large])
                }
            }
            .sheet(isPresented: Binding(get: { model.bookSearchDoc != nil }, set: { if !$0 { model.bookSearchDoc = nil } })) {
                if let id = model.bookSearchDoc, let d = model.store.document(id) {
                    BookSearchSheet(doc: d) { h in show(h) }
                        .presentationDetents([.medium, .large])
                }
            }
            .navigationDestination(for: Route.self) { r in
                switch r {
                case .folder(let f): FolderScreen(scope: f, onOpen: open)
                case .reader(let id): ReaderScreen(documentID: id)
                case .notes: NotesScreen { id, offset in
                    model.revealRequest = (id, offset)
                    open(id)
                }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let id = model.player.documentID, path.last != .reader(id) {
                    MiniPlayer { open(id) }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .overlay { if model.importing { ProgressView("Ekleniyor…").padding().modifier(GlassPanel(cornerRadius: 16)) } }
        }
        .sheet(isPresented: $promptShown) { PromptBuilderView() }
        .modifier(ScanImportModifier(scan: $scanShown, photos: $photosShown, folder: nil))
        .sheet(item: $expandTest) { ExpandPromptView(source: $0) }
        .sheet(isPresented: $elevenShown) { NavigationStack { ElevenSettingsPage() } }
        .sheet(isPresented: $cursorShown) { NavigationStack { CursorSettingsPage() } }
        .sheet(isPresented: $cloudShown) { NavigationStack { CloudSettingsPage() } }
        .fileImporter(isPresented: $importerShown, allowedContentTypes: Self.importTypes, allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { Task { await model.importFiles(urls) } }
        }
        .alert("Yeni klasör", isPresented: $newFolderShown) {
            TextField("Klasör adı", text: $newFolderName)
            Button("Oluştur") { model.addFolder(newFolderName); newFolderName = "" }
            Button("Vazgeç", role: .cancel) { newFolderName = "" }
        }
        .alert("Ekleme", isPresented: Binding(get: { model.importMessage != nil }, set: { if !$0 { model.importMessage = nil } })) {
            Button("Tamam") { model.importMessage = nil }
        } message: { Text(model.importMessage ?? "") }
        .modifier(FinishedAlerts())
        .fullScreenCover(isPresented: Binding(get: { model.musicModeShown }, set: { model.musicModeShown = $0 })) {
            MusicModeView().environment(model)
        }
        // an active wait or a music break: the music screen (rhythm only) for its length, then back to reading
        .onChange(of: model.player.breakEnds != nil) { _, waiting in
            if waiting, model.settings.musicOnPause, !model.musicModeShown {
                model.musicFromBreak = true
                model.musicModeShown = true
            } else if !waiting, model.musicFromBreak {
                model.musicModeShown = false
            }
        }
        .task {                                   // test hook: -musictest opens the music mode on the last book
            let args = CommandLine.arguments
            guard args.contains("-musictest") || args.contains("-cursortest") || args.contains("-statstest") || args.contains("-markssheet") || args.contains("-prompttest")
                    || args.contains("-eleventest") || args.contains("-cloudtest") || args.contains("-expandtest") else { return }
            try? await Task.sleep(for: .seconds(2))
            if args.contains("-musictest") { model.musicModeShown = true }
            if args.contains("-statstest") { statsTab = args.contains("road") ? .road : .reading }
            if args.contains("-prompttest") { promptShown = true }
            if args.contains("-eleventest") { elevenShown = true }
            if args.contains("-cursortest") { cursorShown = true }
            if args.contains("-cloudtest") { cloudShown = true }
            if args.contains("-expandtest"), let d = model.store.documents.first(where: { !$0.highlights.isEmpty }), let h = d.highlights.first {
                expandTest = args.contains("marks") ? .marks(doc: d.id) : .passage(doc: d.id, range: h.range, text: h.text)
            }
            if args.contains("-markssheet") { model.marksSheetDoc = model.store.documents.first { !$0.highlights.isEmpty }?.id }
        }
        .task {                                   // test hook: -openreader shows the last book's reader
            guard CommandLine.arguments.contains("-openreader") else { return }
            try? await Task.sleep(for: .seconds(1.5))
            if let id = model.player.documentID ?? model.store.documents.first?.id { path = [.reader(id)] }
        }
        .onOpenURL { url in
            if url.scheme == "wisepath" {
                // book/<id>?at=<offset>: that place is shown, the reading place stays
                let at = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "at" }?.value.flatMap(Int.init)
                perform(([url.host ?? ""] + url.pathComponents.filter { $0 != "/" }).joined(separator: "/"), at: at)
                return
            }
            Task { await model.handleOpen(url); if let id = model.openDocumentID { path = [.reader(id)] } }
        }
        // a quick action from the app icon (also at a cold start, once the library is there)
        .onChange(of: QuickActions.shared.pending, initial: true) { _, a in
            guard let a else { return }
            QuickActions.shared.pending = nil
            Task { try? await Task.sleep(for: .milliseconds(400)); perform(a) }
        }
        .onChange(of: model.player.isPlaying) { _, _ in WidgetFeed.publish(model); model.publishLive() }
        .onChange(of: model.store.documents.count) { _, _ in WidgetFeed.publish(model); model.indexForSpotlight() }
        // a Spotlight result: book/<id> or book/<id>?at=<offset>. The place is shown, the reading place stays.
        .onContinueUserActivity(PDMSpotlight.activityType) { activity in
            guard let id = PDMSpotlight.identifier(from: activity) else { return }
            let parts = id.split(separator: "?at=", maxSplits: 1).map(String.init)
            perform(parts[0], at: parts.count > 1 ? Int(parts[1]) : nil)
        }
        .task { await model.store.backfillCovers() }
    }

    private func open(_ id: UUID) {
        if path.last == .reader(id) { return }
        path.append(.reader(id))
    }

    /// A found place: the book opens showing it; the reading place stays where it was.
    private func show(_ h: TextHit) {
        model.revealRequest = (h.doc, h.offset)
        if path.last == .reader(h.doc) { model.revealTick += 1 } else { open(h.doc) }
    }

    /// A quick action or a wisepath:// link: resume · book/<id> · bike · walk · music · stats · road.
    private func perform(_ action: String, at offset: Int? = nil) {
        let parts = action.split(separator: "/").map(String.init)
        let book = continueBook
        switch parts.first ?? "" {
        case "resume":
            guard let d = book else { return }
            path = [.reader(d.id)]
            Task {
                // read on as soon as the reader has the book (it opens it itself)
                for _ in 0..<40 {
                    if model.player.documentID == d.id, model.store.document(d.id) != nil { model.player.play(); return }
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        case "book":
            guard parts.count > 1 else { return }
            // the app's own id, or Teoria's name for the book (vr-<first eight hex digits of the id>)
            var id = UUID(uuidString: parts[1])
            if id == nil, parts[1].lowercased().hasPrefix("vr-") {
                let head = parts[1].dropFirst(3).lowercased()
                if head.count >= 8 { id = model.store.documents.first { $0.id.uuidString.lowercased().hasPrefix(head) }?.id }
            }
            guard let id, model.store.document(id) != nil else { return }
            if let offset { model.revealRequest = (id, max(0, offset)) }
            if path.last == .reader(id) { if offset != nil { model.revealTick += 1 } } else { path = [.reader(id)] }
        case "bike", "walk":
            guard let d = book else { return }
            path = [.reader(d.id)]
            model.startMove(parts[0] == "bike" ? .bike : .walk)
        case "music":
            if let d = book { path = [.reader(d.id)] }
            model.musicModeShown = true
        case "stats": statsTab = .reading
        case "road": statsTab = .road
        default: break
        }
    }

    // MARK: home

    /// The book to go on with: the one in the player, else the last one opened and not finished.
    private var continueBook: DocumentRecord? {
        if let id = model.player.documentID, let d = model.store.document(id) { return d }
        return model.store.documents.filter { $0.lastOpenedAt != nil && !$0.isFinished }
            .max { ($0.lastOpenedAt ?? .distantPast) < ($1.lastOpenedAt ?? .distantPast) }
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 22) {
            // the books rule the home (2026-11-10: "merkezde kitap hâkimiyeti"): the last three on top, then the
            // library in the chosen view; the day's numbers come after them, the library's counts are in İstatistik
            RecentBooks(open: open)
            if !model.store.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        sectionTitle("Kitaplarım")
                        Spacer()
                        Menu {
                            Picker("Görünüm", selection: Binding(get: { model.settings.homeStyle }, set: { model.settings.homeStyle = $0 })) {
                                ForEach(LibraryStyle.allCases) { Label($0.name, systemImage: $0.symbol).tag($0) }
                            }
                        } label: {
                            Label(model.settings.homeStyle.name, systemImage: model.settings.homeStyle.symbol)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12).frame(height: 32)
                                .modifier(GlassCapsule())
                        }
                        .padding(.trailing, 20)
                        .accessibilityLabel("Görünüm: \(model.settings.homeStyle.name)")
                    }
                    ShelfChips(selection: Binding(get: { model.settings.homeShelf }, set: { model.settings.homeShelf = $0 }))
                    homeBooks
                }
            }
            if !model.store.isEmpty { TodayCard(onStats: { statsTab = .reading }) }
            DayStrip(onStats: { statsTab = .reading }, onAutomations: { automationShown = true })
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    sectionTitle("Klasörler")
                    Spacer()
                    Button { newFolderShown = true } label: { Image(systemName: "folder.badge.plus").font(.title3) }
                        .accessibilityLabel("Yeni klasör")
                        .padding(.trailing, 20)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(model.folderScopes(), id: \.self) { f in
                        NavigationLink(value: Route.folder(f)) { FolderTile(scope: f) }
                            .buttonStyle(.plain)
                            .contextMenu { folderMenu(f) }
                    }
                }
                .padding(.horizontal, 20)
            }
            if model.store.isEmpty {
                ContentUnavailableView {
                    Label("Kütüphane boş", systemImage: "books.vertical")
                } description: {
                    Text("Sağ üstteki + ile Dosyalar'dan ya da panodan belge ekle.")
                } actions: {
                    Button("Dosyalardan ekle") { importerShown = true }.glassAction()
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 24)
    }

    /// The books of the chosen shelf, in the chosen view. "Tümü" in the bookcase stands as three shelves, the
    /// finished ones last, as the archive.
    @ViewBuilder private var homeBooks: some View {
        let sections = Self.shelves(model.store.documents, shelf: model.settings.homeShelf, grouped: model.settings.homeStyle == .spines)
        if sections.allSatisfy({ $0.docs.isEmpty }) {
            Text("Bu rafta kitap yok.").font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 20)
        } else if model.settings.homeStyle == .spines {
            BookshelfView(sections: sections, onOpen: open)
        } else if model.settings.homeStyle == .flow {
            CoverFlowView(docs: sections.flatMap(\.docs), onOpen: open)
        } else {
            DocumentCollection(docs: sections.flatMap(\.docs), style: model.settings.homeStyle, onOpen: open)
        }
    }

    static func shelves(_ all: [DocumentRecord], shelf: String, grouped: Bool) -> [BookshelfSection] {
        let byOpened: (DocumentRecord, DocumentRecord) -> Bool = { ($0.lastOpenedAt ?? $0.addedAt) > ($1.lastOpenedAt ?? $1.addedAt) }
        let reading = all.filter { !$0.isUnread && !$0.isFinished }.sorted(by: byOpened)
        let unread = all.filter(\.isUnread).sorted { $0.addedAt > $1.addedAt }
        let finished = all.filter(\.isFinished).sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
        switch shelf {
        case "reading": return [BookshelfSection(title: "Süren", docs: reading)]
        case "unread": return [BookshelfSection(title: "Okunacak", docs: unread)]
        case "finished": return [BookshelfSection(title: "Bitenler · arşiv", docs: finished)]
        case "all":
            return grouped
                ? [BookshelfSection(title: "Süren", docs: reading), BookshelfSection(title: "Okunacak", docs: unread),
                   BookshelfSection(title: "Bitenler · arşiv", docs: finished)]
                : [BookshelfSection(title: "Tümü", docs: all.sorted(by: byOpened))]
        default:
            return [BookshelfSection(title: shelf, docs: all.filter { $0.folder == shelf }.sorted(by: byOpened))]
        }
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(.title2.weight(.bold)).padding(.horizontal, 20)
    }

    @ViewBuilder private func folderMenu(_ f: FolderScope) -> some View {
        if let name = f.folderName {
            Button(role: .destructive) { model.removeFolder(name) } label: {
                Label("Klasörü kaldır (belgeler kalır)", systemImage: "folder.badge.minus")
            }
        }
    }

    /// The gear: Ayarlar, and under it Otomasyon (the list of automations and their editor). While an automation
    /// plays, a small dot on the gear says so.
    @ToolbarContentBuilder private var settingsButton: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Button { settingsShown = true } label: { Label("Ayarlar", systemImage: "gearshape") }
                Button { automationShown = true } label: {
                    Label(model.automationRun.map { "Otomasyon · \($0.automation.name)" } ?? "Otomasyon", systemImage: "list.bullet.rectangle")
                }
                Button { path.append(.notes) } label: { Label("Notlarım · \(model.notes.notes.count)", systemImage: "waveform") }
            } label: {
                Image(systemName: "gearshape")
                    .overlay(alignment: .topTrailing) {
                        if model.automationRun != nil { Circle().fill(.orange).frame(width: 7, height: 7).offset(x: 3, y: -2) }
                    }
            }
            .accessibilityLabel(model.automationRun != nil ? "Ayarlar ve Otomasyon, otomasyon çalışıyor" : "Ayarlar ve Otomasyon")
        }
        // Notlarım is in the gear's menu only (2026-11-10: its own key beside the gear was taken away)
    }

    /// The moving modes and the way's record, one key at the top (2026-10-28: the card left the home page, the books
    /// come first). The modes open on the book in the player, else the last one opened.
    @ToolbarContentBuilder private var roadMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            let book = model.player.documentID.flatMap { model.store.document($0) }
                ?? model.store.documents.filter { $0.lastOpenedAt != nil && !$0.isFinished }.max { $0.lastOpenedAt! < $1.lastOpenedAt! }
            Menu {
                Section(book.map { "Kitap: \($0.title)" } ?? "Önce bir kitap aç") {
                    Button { if let b = book { open(b.id); model.startMove(.bike) } } label: { Label("Bisiklet", systemImage: "bicycle") }
                    Button { if let b = book { open(b.id); model.startMove(.walk) } } label: { Label("Yürüyüş", systemImage: "figure.walk") }
                    Button { if let b = book { open(b.id); model.musicModeShown = true } } label: { Label("Müzik", systemImage: "music.note") }
                }
                .disabled(book == nil)
                Button { statsTab = .road } label: { Label("Yollarım: gün, hafta, ay", systemImage: "map") }
            } label: {
                Image(systemName: model.settings.bikeMode ? model.settings.moveKind.symbol : "map")
                    .foregroundStyle(model.settings.bikeMode ? Color.orange : Color.accentColor)
            }
            .accessibilityLabel("Yolda: bisiklet, yürüyüş, müzik ve Yollarım")
        }
    }

    @ToolbarContentBuilder private var statsButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { statsTab = .reading } label: { Image(systemName: "chart.bar.xaxis") }
                .accessibilityLabel("İstatistik: okuma ve yol")
        }
    }

    @ToolbarContentBuilder private var addMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { model.folder = nil; importerShown = true } label: { Label("Dosyalardan ekle", systemImage: "folder") }
                Button { model.folder = nil; model.importClipboard() } label: { Label("Panodan ekle", systemImage: "doc.on.clipboard") }
                Button { model.folder = nil; promptShown = true } label: { Label("İstem oluşturucu", systemImage: "wand.and.sparkles") }
                Section("Kâğıttan") {
                    Button { scanShown = true } label: { Label("Tara (kamera)", systemImage: "doc.viewfinder") }
                        .disabled(!DocumentScanner.isAvailable)
                    Button { photosShown = true } label: { Label("Fotoğraftan metin", systemImage: "text.viewfinder") }
                }
                Divider()
                Button { newFolderShown = true } label: { Label("Yeni klasör", systemImage: "folder.badge.plus") }
            } label: { Image(systemName: "plus") }
            .accessibilityLabel("Ekle")
        }
    }
}

// MARK: - home pieces

/// The book to go on with: its cover, where you are, and a key that reads on (or opens it).
struct ContinueCard: View {
    @Environment(AppModel.self) private var model
    let doc: DocumentRecord
    var open: () -> Void

    private var inPlayer: Bool { model.player.documentID == doc.id }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Button(action: open) {
                HStack(alignment: .center, spacing: 16) {
                    CoverView(doc: doc, width: 78)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Okumaya devam").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                        Text(doc.title).font(.system(size: 17, weight: .semibold, design: .serif)).lineLimit(2)
                        if let a = doc.author { Text(a).font(.footnote).foregroundStyle(.secondary).lineLimit(1) }
                        StateLabel(doc: doc).padding(.top, 2)
                        Text(model.statusText(doc)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { if inPlayer { model.player.toggle() } else { open() } } label: {
                Image(systemName: inPlayer && model.player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Palette.play, in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(inPlayer && model.player.isPlaying ? "Duraklat" : "Oku")
        }
        .padding(14)
        .modifier(GlassPanel(cornerRadius: 22))
        .padding(.horizontal, 14)
        .accessibilityElement(children: .contain)
    }
}

/// The shelves to choose from: Tümü, Süren, Okunacak, Bitenler, then the folders.
struct ShelfChips: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: String

    var body: some View {
        let fixed: [(String, String)] = [("all", "Tümü"), ("reading", "Süren"), ("unread", "Okunacak"), ("finished", "Bitenler")]
        let folders = model.folderScopes().compactMap(\.folderName)
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(fixed, id: \.0) { chip($0.0, $0.1, tint: nil) }
                ForEach(folders, id: \.self) { chip($0, $0, tint: FolderScope.named($0).tint) }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()               // glass inside a clipping scroll view drew a pale band across the screen
    }

    private func chip(_ key: String, _ title: String, tint: Color?) -> some View {
        let on = selection == key
        return Button { withAnimation(.smooth(duration: 0.25)) { selection = key } } label: {
            HStack(spacing: 5) {
                if let tint { Circle().fill(tint).frame(width: 7, height: 7) }
                Text(title)
            }
            .font(.subheadline.weight(on ? .semibold : .regular))
            .padding(.horizontal, 13).frame(height: 32)
            .modifier(GlassCapsule(tint: on ? Color.accentColor.opacity(0.28) : nil,
                                   fallback: on ? Color.primary.opacity(0.14) : Color.primary.opacity(0.05)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// One thin line: today's listening (a tap: İstatistik) and the automation (start, go on, stop; or the list).
struct DayStrip: View {
    @Environment(AppModel.self) private var model
    var onStats: () -> Void
    var onAutomations: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            automation
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder private var automation: some View {
        let store = model.automations
        Menu {
            if let run = model.automationRun {
                Button(role: .destructive) { model.stopAutomation() } label: { Label("Durdur · \(run.automation.name)", systemImage: "stop.fill") }
            } else if let a = store.featured {
                if store.resumePoint(for: a) != nil {
                    Button { model.startAutomation(a, resume: true) } label: { Label("Kaldığı yerden · \(a.name)", systemImage: "play.fill") }
                    Button { model.startAutomation(a, resume: false) } label: { Label("Baştan", systemImage: "arrow.counterclockwise") }
                } else {
                    Button { model.startAutomation(a, resume: false) } label: { Label("Başlat · \(a.name)", systemImage: "play.fill") }
                }
            }
            Button(action: onAutomations) { Label("Bütün otomasyonlar", systemImage: "list.bullet.rectangle") }
        } label: {
            Label(model.automationRun?.automation.name ?? store.featured?.name ?? "Otomasyon",
                  systemImage: model.automationRun != nil ? "dot.radiowaves.left.and.right" : "list.bullet.rectangle")
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 12).frame(height: 36)
                .foregroundStyle(model.automationRun != nil ? Color.orange : Color.primary)
                .modifier(GlassCapsule(tint: model.automationRun != nil ? Color.orange.opacity(0.18) : nil))
        }
        .accessibilityLabel("Otomasyon")
    }
}

struct FolderTile: View {
    @Environment(AppModel.self) private var model
    let scope: FolderScope

    var body: some View {
        let docs = model.documents(in: scope, applyFilter: false)
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                ForEach(Array(docs.prefix(3).enumerated().reversed()), id: \.element.id) { i, d in
                    CoverView(doc: d, width: 46, showsPlaying: false)
                        .rotationEffect(.degrees(Double(i) * -7))
                        .offset(x: CGFloat(i) * 26)
                }
                if docs.isEmpty {
                    Image(systemName: scope.symbol).font(.system(size: 34, weight: .medium))
                        .foregroundStyle(scope.tint.gradient)
                        .frame(height: 69)
                }
            }
            .frame(height: 74, alignment: .bottomLeading)
            .padding(.leading, 4)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Label(scope.title, systemImage: scope.symbol).font(.subheadline.weight(.semibold)).lineLimit(1)
                        .labelStyle(TintedLabel(tint: scope.tint))
                    Text("\(docs.count) belge").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(GlassPanel(cornerRadius: 22))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(scope.title), \(docs.count) belge")
    }
}

struct ProgressBar: View {
    var value: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.14))       // white was invisible on the light panels
                Capsule().fill(value >= 0.99 ? Color.green : Color.accentColor).frame(width: g.size.width * min(1, max(0, value)))
            }
        }
    }
}

// MARK: - folder

struct FolderScreen: View {
    @Environment(AppModel.self) private var model
    let scope: FolderScope
    var onOpen: (UUID) -> Void
    @State private var importerShown = false
    @State private var promptShown = false
    @State private var renameShown = false
    @State private var renameText = ""
    @State private var scanShown = false
    @State private var photosShown = false

    var body: some View {
        let docs = model.documents(in: scope, applyFilter: true)
        ZStack {
            InkBackground()
            ScrollView {
                if docs.isEmpty {
                    ContentUnavailableView("Belge yok", systemImage: "books.vertical",
                                           description: Text(scope == .all ? "Sağ üstteki + ile belge ekle." : "Bu klasörde belge yok. Bir belgeyi basılı tutup “Klasöre taşı”yı seç."))
                        .padding(.top, 60)
                } else {
                    DocumentCollection(docs: docs, style: model.settings.style, onOpen: onOpen)
                        .padding(.top, 8)
                }
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(scope.title)
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("Görünüm", selection: Binding(get: { model.settings.style }, set: { model.settings.style = $0 })) {
                ForEach(LibraryStyle.allCases) { s in Label(s.name, systemImage: s.symbol).tag(s) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker("Sırala", selection: Binding(get: { model.settings.sortOrder }, set: { model.settings.sortOrder = $0 })) {
                        ForEach(SortOrder.allCases) { Text($0.name).tag($0) }
                    }
                    Picker("Süz", selection: Binding(get: { model.settings.filter }, set: { model.settings.filter = $0 })) {
                        ForEach(LibraryFilter.allCases) { Text($0.name).tag($0) }
                    }
                } label: { Image(systemName: "line.3.horizontal.decrease") }
                .accessibilityLabel("Sırala ve süz")
                Menu {
                    Button { model.folder = scope.folderName; importerShown = true } label: { Label("Dosyalardan ekle", systemImage: "folder") }
                    Button { model.folder = scope.folderName; model.importClipboard() } label: { Label("Panodan ekle", systemImage: "doc.on.clipboard") }
                    Button { model.folder = scope.folderName; promptShown = true } label: { Label("İstem oluşturucu", systemImage: "wand.and.sparkles") }
                    Button { scanShown = true } label: { Label("Tara (kamera)", systemImage: "doc.viewfinder") }
                        .disabled(!DocumentScanner.isAvailable)
                    Button { photosShown = true } label: { Label("Fotoğraftan metin", systemImage: "text.viewfinder") }
                    if let name = scope.folderName {
                        Divider()
                        Button { renameText = name; renameShown = true } label: { Label("Klasörü yeniden adlandır", systemImage: "pencil") }
                    }
                } label: { Image(systemName: "plus") }
                .accessibilityLabel("Ekle")
            }
        }
        .sheet(isPresented: $promptShown) { PromptBuilderView() }
        .modifier(ScanImportModifier(scan: $scanShown, photos: $photosShown, folder: scope.folderName))
        .fileImporter(isPresented: $importerShown, allowedContentTypes: LibraryScreen.importTypes, allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { Task { await model.importFiles(urls) } }
        }
        .alert("Klasörü yeniden adlandır", isPresented: $renameShown) {
            TextField("Ad", text: $renameText)
            Button("Kaydet") { if let n = scope.folderName { model.renameFolder(n, to: renameText) } }
            Button("Vazgeç", role: .cancel) {}
        }
    }
}

/// The same documents as a shelf, a grid or a list, with the same context menu everywhere.
struct DocumentCollection: View {
    @Environment(AppModel.self) private var model
    let docs: [DocumentRecord]
    let style: LibraryStyle
    var onOpen: (UUID) -> Void
    @State private var renaming: DocumentRecord?
    @State private var renameText = ""
    @State private var deleting: DocumentRecord?
    @State private var rewinding: DocumentRecord?

    var body: some View {
        Group {
            switch style {
            case .spines: BookshelfView(sections: [BookshelfSection(title: "", docs: docs)], onOpen: onOpen)
            case .flow: CoverFlowView(docs: docs, onOpen: onOpen)
            case .shelf: shelf
            case .grid: grid
            case .list: list
            case .compact: compact
            case .wall: wall
            case .cards: cards
            case .folders: folderRows
            case .remaining: remaining
            }
        }
        .alert("Yeniden adlandır", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Başlık", text: $renameText)
            Button("Kaydet") {
                if let r = renaming, !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    model.rename(r.id, to: renameText.trimmingCharacters(in: .whitespaces))
                }
                renaming = nil
            }
            Button("Vazgeç", role: .cancel) { renaming = nil }
        }
        .confirmationDialog(rewinding?.isFinished == true ? "“\(rewinding?.title ?? "")” yeniden okunsun mu?" : "“\(rewinding?.title ?? "")” başa sarılsın mı?",
                            isPresented: Binding(get: { rewinding != nil }, set: { if !$0 { rewinding = nil } }), titleVisibility: .visible) {
            Button(rewinding?.isFinished == true ? "Baştan başla · \((rewinding?.finishes.count ?? 0) + 1). okuma" : "Başa sar") {
                if let d = rewinding { model.rewindToBeginning(d.id) }; rewinding = nil
            }
            Button("Vazgeç", role: .cancel) { rewinding = nil }
        } message: { Text(rewinding?.isFinished == true ? "Bitirdiğin okuma kayıtlı kalır." : "Kaldığın yer başa döner.") }
        .confirmationDialog("“\(deleting?.title ?? "")” silinsin mi?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Sil", role: .destructive) { if let d = deleting { model.delete([d.id]) }; deleting = nil }
        } message: { Text("İşaretler, notlar ve yer imleri de silinir.") }
    }

    /// A glass shelf: three books standing on each board.
    private var shelf: some View {
        let rows = stride(from: 0, to: docs.count, by: 3).map { Array(docs[$0..<min($0 + 3, docs.count)]) }
        return VStack(spacing: 26) {
            ForEach(rows.indices, id: \.self) { r in
                VStack(spacing: 0) {
                    HStack(alignment: .bottom, spacing: 18) {
                        ForEach(rows[r]) { d in
                            Button { onOpen(d.id) } label: { CoverView(doc: d, width: 96) }
                                .buttonStyle(.plain)
                                .contextMenu { menu(d) }
                                .accessibilityLabel("\(d.title), \(model.statusText(d))")
                        }
                        ForEach(0..<(3 - rows[r].count), id: \.self) { _ in Color.clear.frame(width: 96, height: 1) }
                    }
                    .padding(.bottom, -2)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom))
                        .frame(height: 12)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.18), lineWidth: 0.6))
                        .shadow(color: .black.opacity(0.6), radius: 10, y: 8)
                        .padding(.horizontal, 12)
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(rows[r]) { d in
                            VStack(spacing: 3) {
                                Text(d.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                StateLabel(doc: d, compact: true)
                            }
                            .frame(width: 96)
                        }
                        ForEach(0..<(3 - rows[r].count), id: \.self) { _ in Color.clear.frame(width: 96, height: 1) }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 130), spacing: 14, alignment: .top)], spacing: 20) {
            ForEach(docs) { d in
                Button { onOpen(d.id) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        CoverView(doc: d, width: 100)
                        Text(d.title).font(.caption.weight(.semibold)).lineLimit(2).frame(width: 100, alignment: .leading)
                        StateLabel(doc: d).frame(width: 100, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                .contextMenu { menu(d) }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }

    private var list: some View {
        LazyVStack(spacing: 10) {
            ForEach(docs) { d in
                Button { onOpen(d.id) } label: { LibraryRow(doc: d) }
                    .buttonStyle(.plain)
                    .contextMenu { menu(d) }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 24)
    }

    /// Every book on one line: about three times as many on a screen as the list.
    private var compact: some View {
        LazyVStack(spacing: 0) {
            ForEach(docs) { d in
                Button { onOpen(d.id) } label: { CompactRow(doc: d) }
                    .buttonStyle(.plain)
                    .contextMenu { menu(d) }
                if d.id != docs.last?.id { Divider().padding(.leading, 40) }
            }
        }
        .modifier(GlassPanel(cornerRadius: 16))
        .padding(.horizontal, 14)
        .padding(.bottom, 24)
    }

    /// Kapak duvarı: nothing but covers, four across, a hairline of progress under each. The most books on a screen.
    private var wall: some View {
        GeometryReader { g in
            let w = (g.size.width - 32 - 30) / 4
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(w), spacing: 10), count: 4), spacing: 12) {
                ForEach(docs) { d in
                    Button { onOpen(d.id) } label: {
                        VStack(spacing: 4) {
                            CoverView(doc: d, width: w)
                            if d.isFinished { Capsule().fill(Color.green).frame(height: 3) }
                            else if d.isUnread { Capsule().fill(Color.accentColor.opacity(0.35)).frame(height: 3) }
                            else { ProgressBar(value: d.progress).frame(height: 3) }
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu { menu(d) }
                    .accessibilityLabel("\(d.title), \(model.statusText(d))")
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: Self.wallHeight(count: docs.count))
        .padding(.bottom, 24)
    }

    private static func wallHeight(count: Int) -> CGFloat {
        let w = (UIScreen.main.bounds.width - 32 - 30) / 4
        return CGFloat((count + 3) / 4) * (w * 1.5 + 7 + 12)
    }

    /// Kartlar: one book a card, turned like pages: the cover large, what is left, and a key that reads on.
    private var cards: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 14) {
                ForEach(docs) { d in
                    BookCard(doc: d, open: { onOpen(d.id) })
                        .contextMenu { menu(d) }
                        .containerRelativeFrame(.horizontal, count: 1, span: 1, spacing: 14)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 28, for: .scrollContent)
        .padding(.bottom, 24)
    }

    /// Klasör rafları: a row of covers for each folder, pushed sideways.
    private var folderRows: some View {
        let groups = Dictionary(grouping: docs) { $0.folder ?? "Klasörsüz" }
        let names = groups.keys.sorted { a, b in a == "Klasörsüz" ? false : b == "Klasörsüz" ? true : a.localizedCompare(b) == .orderedAscending }
        return VStack(alignment: .leading, spacing: 20) {
            ForEach(names, id: \.self) { name in
                let books = groups[name] ?? []
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Circle().fill(FolderScope.named(name).tint).frame(width: 8, height: 8)
                        Text(name).font(.headline)
                        Text("\(books.count)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(books) { d in
                                Button { onOpen(d.id) } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        CoverView(doc: d, width: 92)
                                        Text(d.title).font(.caption.weight(.semibold)).lineLimit(2).frame(width: 92, alignment: .leading)
                                        StateLabel(doc: d)
                                    }
                                }
                                .buttonStyle(.plain)
                                .contextMenu { menu(d) }
                                .accessibilityElement(children: .combine)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .padding(.bottom, 24)
    }

    /// Kalan süre: the books in the order they can be finished, the nearest first; each line is as long as the
    /// book's listening, its heard part filled. The finished ones stand last.
    private var remaining: some View {
        let left: (DocumentRecord) -> TimeInterval = { model.duration(characters: max(0, $0.length - $0.position), speed: $0.speed) }
        let whole: (DocumentRecord) -> TimeInterval = { model.duration(characters: $0.length, speed: $0.speed) }
        let open = docs.filter { !$0.isFinished }.sorted { left($0) < left($1) }
        let done = docs.filter(\.isFinished)
        let longest = max(1, docs.map(whole).max() ?? 1)
        return LazyVStack(spacing: 0) {
            ForEach(open + done) { d in
                Button { onOpen(d.id) } label: {
                    HStack(spacing: 12) {
                        CoverView(doc: d, width: 30, showsPlaying: false)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(d.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            GeometryReader { g in
                                let w = max(14, g.size.width * whole(d) / longest)
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.primary.opacity(0.12)).frame(width: w)
                                    Capsule().fill(d.isFinished ? Color.green : Color.accentColor).frame(width: max(d.progress > 0 ? 5 : 0, w * d.progress))
                                }
                            }
                            .frame(height: 6)
                        }
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(d.isFinished ? "bitti" : Format.duration(left(d)))
                                .font(.subheadline.weight(.bold).monospacedDigit())
                                .foregroundStyle(d.isFinished ? Color.green : Color.primary)
                            if !d.isFinished { Text(d.isUnread ? "yeni" : "%\(Int(d.progress * 100))").font(.caption2).foregroundStyle(.secondary) }
                        }
                        .frame(minWidth: 70, alignment: .trailing)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu { menu(d) }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(d.title), \(model.statusText(d))")
                if d.id != (open + done).last?.id { Divider().padding(.leading, 54) }
            }
        }
        .modifier(GlassPanel(cornerRadius: 18))
        .padding(.horizontal, 14)
        .padding(.bottom, 24)
    }

    @ViewBuilder private func menu(_ d: DocumentRecord) -> some View {
        Button { renameText = d.title; renaming = d } label: { Label("Yeniden adlandır", systemImage: "pencil") }
        Menu {
            Button("Klasörsüz") { model.setFolder(d.id, nil) }
            ForEach(model.store.folders, id: \.self) { f in
                Button { model.setFolder(d.id, f) } label: { Label(f, systemImage: d.folder == f ? "checkmark" : "folder") }
            }
        } label: { Label("Klasöre taşı", systemImage: "folder") }
        Menu {
            ForEach(HighlightColor.allCases, id: \.self) { c in
                Button { model.setFlag(d.id, c) } label: { Label(c.name, systemImage: d.flag == c ? "checkmark.circle.fill" : "circle.fill") }
            }
            if d.flag != nil { Button("Etiketi kaldır") { model.setFlag(d.id, nil) } }
        } label: { Label("Etiket", systemImage: "flag") }
        Button { model.bookSearchDoc = d.id } label: { Label("Kitapta ara", systemImage: "text.magnifyingglass") }
        if !d.highlights.isEmpty {
            Button { model.marksSheetDoc = d.id } label: { Label("İşaretlere bak (\(d.highlights.count))", systemImage: "highlighter") }
        }
        Button { rewinding = d } label: {
            Label(d.isFinished ? "Yeniden oku" : "Başa sar", systemImage: d.isFinished ? "arrow.counterclockwise" : "backward.end")
        }
        Divider()
        Button(role: .destructive) { deleting = d } label: { Label("Sil", systemImage: "trash") }
    }
}

struct LibraryRow: View {
    @Environment(AppModel.self) private var model
    let doc: DocumentRecord

    private var playing: Bool { model.player.documentID == doc.id && model.player.isPlaying }

    var body: some View {
        HStack(spacing: 14) {
            CoverView(doc: doc, width: 44, showsPlaying: false)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let f = doc.flag { Circle().fill(f.color).frame(width: 8, height: 8) }
                    Text(doc.title).font(.body.weight(.medium)).lineLimit(1)
                }
                Text([doc.author, doc.folder ?? doc.format.badge].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 8) {
                    StateLabel(doc: doc)
                    if !doc.isFinished {
                        Text(Format.duration(model.duration(characters: doc.length - doc.position, speed: doc.speed)) + (doc.isUnread ? "" : " kaldı"))
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            Spacer(minLength: 0)
            MarksChip(doc: doc)
            if playing { PlayingBars(height: 18) }
        }
        .padding(12)
        .background {
            if playing {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(model.settings.accent.wash)
            }
        }
        .modifier(GlassPanel(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(doc.title), \(model.statusText(doc))\(playing ? ", okunuyor" : "")")
    }
}

/// Kartlar görünümünün kartı: the cover, the book's name, a ring of how far it is, the time left, and "Devam et".
struct BookCard: View {
    @Environment(AppModel.self) private var model
    let doc: DocumentRecord
    var open: () -> Void

    private var inPlayer: Bool { model.player.documentID == doc.id }

    var body: some View {
        let left = model.duration(characters: max(0, doc.length - doc.position), speed: doc.speed)
        HStack(alignment: .top, spacing: 16) {
            Button(action: open) { CoverView(doc: doc, width: 118) }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 8) {
                Text(doc.title).font(.system(size: 19, weight: .bold, design: .serif)).lineLimit(3)
                if let a = doc.author { Text(a).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    ZStack {
                        Circle().stroke(Color.primary.opacity(0.12), lineWidth: 5)
                        Circle().trim(from: 0, to: max(0.003, doc.progress))
                            .stroke(doc.isFinished ? Color.green : Palette.play, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text(doc.isFinished ? "✓" : "\(Int(doc.progress * 100))").font(.system(size: 13, weight: .bold, design: .rounded)).monospacedDigit()
                    }
                    .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(doc.isFinished ? "Bitti" : doc.isUnread ? "Yeni" : "\(Format.duration(left)) kaldı")
                            .font(.subheadline.weight(.semibold))
                        Text("\(StatFormat.pages(doc.wordCount)) sayfa").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button {
                    if inPlayer { model.player.toggle() } else { open() }
                } label: {
                    Label(inPlayer && model.player.isPlaying ? "Duraklat" : doc.isUnread ? "Başla" : doc.isFinished ? "Aç" : "Devam et",
                          systemImage: inPlayer && model.player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .glassAction()
                .tint(Palette.play)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(height: 118 * 1.5 + 32)
        .modifier(GlassPanel(cornerRadius: 24))
        .accessibilityElement(children: .contain)
    }
}

/// One line: a small cover, the title (author after it, faint), the percentage; a hairline of progress below.
struct CompactRow: View {
    @Environment(AppModel.self) private var model
    let doc: DocumentRecord

    private var playing: Bool { model.player.documentID == doc.id && model.player.isPlaying }

    var body: some View {
        HStack(spacing: 10) {
            CoverView(doc: doc, width: 20, showsPlaying: false)
            HStack(spacing: 6) {
                if let f = doc.flag { Circle().fill(f.color).frame(width: 6, height: 6) }
                Text(doc.title).font(.subheadline.weight(.medium)).lineLimit(1).layoutPriority(1)
                if let a = doc.author { Text(a).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 0)
            if playing { PlayingBars(height: 12) }
            StateLabel(doc: doc, compact: true).frame(minWidth: 34, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .background(playing ? model.settings.accent.wash : .clear)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(doc.title), \(model.statusText(doc))\(playing ? ", okunuyor" : "")")
    }
}

struct TintedLabel: LabelStyle {
    var tint: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.caption).foregroundStyle(tint)
            configuration.title
        }
    }
}
