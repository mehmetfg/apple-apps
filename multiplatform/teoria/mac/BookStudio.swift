// Book studio — the Mac reading room (2026-10-20). The whole window is the book: typeset pages side by side, turned
// like a printed book, with the contents on the left and the whole book's map on the right (both can be hidden).
// No voice here: listening happens in Voice Reader / Voice Dream; the yellow line on the page is where you left off.
// Marking: double-click a sentence, or drag across words. Marks go to library/marks (never to the listening apps).
// Data: library.py (Voice Dream + Voice Reader + archive) → LibraryStore; Claude's reading → BookInsight.
import SwiftUI

enum StudioTab: String, CaseIterable, Identifiable {
    case overview, keys, chain, chapters, map, links, sources, marks, notes, search
    var id: String { rawValue }
    var name: String {
        switch self {
        case .overview: "Genel"; case .keys: "Can alıcı"; case .chain: "İddia zinciri"; case .chapters: "Bölüm haritası"
        case .map: "Kavram haritası"; case .links: "Çapraz bağlar"; case .sources: "Kaynakça"; case .marks: "İşaretler"
        case .notes: "Notlarım"; case .search: "Arama"
        }
    }
    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.33percent"; case .keys: "key.horizontal"; case .chain: "link"
        case .chapters: "list.bullet.rectangle"; case .map: "point.3.connected.trianglepath.dotted"
        case .links: "arrow.triangle.branch"; case .sources: "books.vertical"; case .marks: "highlighter"
        case .notes: "square.and.pencil"; case .search: "magnifyingglass"
        }
    }
}

struct BookStudio: View {
    @EnvironmentObject var depo: Depo
    @ObservedObject private var library = LibraryStore.shared
    let entry: LibraryEntry

    @AppStorage("teoria.studio.size") private var size: Double = 19
    @AppStorage("teoria.studio.theme") private var themeRaw = ReaderTheme.paper.rawValue
    @AppStorage("teoria.studio.justify") private var justify = false
    @AppStorage("teoria.studio.markColor") private var markColor = 1
    @AppStorage("teoria.studio.contents") private var showContents = true
    @AppStorage("teoria.studio.panel") private var showPanel = true
    @AppStorage("teoria.studio.panelFocus") private var panelFocus = false   // the book map fills the whole window
    @AppStorage("teoria.studio.focusScale") private var focusScale = 1.4
    @AppStorage("teoria.studio.panelScale") private var panelScale = 1.1
    @AppStorage("teoria.studio.tab") private var tabRaw = StudioTab.overview.rawValue

    @State private var book: Book?
    @State private var layout: BookLayout?
    @State private var current = 0              // first page shown (left page of the spread)
    @State private var spread = 2
    @State private var redraw = 0
    @State private var tapped: BookHighlight?
    @State private var recall: Isaret?
    @ObservedObject private var notesStore = NotesStore.shared
    @StateObject private var notePlayer = SesKayit()
    @State private var noteRequest: NoteRequest?
    @State private var lastMark: TeoriaMark?
    @State private var editingNote: TeoriaNote?
    @State private var toast: (String, TeoriaMark?)?
    @State private var query = ""
    @State private var hits: [SearchHit] = []
    @State private var hitIndex: Int?
    @State private var flash: LiveMark?        // a jump target (key sentence, chapter) shown for a moment
    @State private var dragMark: (page: Int, from: CGPoint, to: CGPoint)?
    @State private var pageField = ""
    @State private var node: BookInsight.Node?
    @State private var scrub: Double?
    @State private var refreshing = false
    @State private var lastRefresh: Date?
    @FocusState private var searchFocused: Bool
    @FocusState private var pageFocused: Bool

    private var live: LibraryEntry { library.entry(entry.id) ?? entry }
    private var theme: ReaderTheme { ReaderTheme(rawValue: themeRaw) ?? .paper }
    private var style: ReaderStyle { ReaderStyle(size: CGFloat(size), theme: theme, justify: justify) }
    private var insight: BookInsight? { library.insights[entry.id] }
    private var tint: Color { Tema.kitap(entry.id) }
    private var tab: StudioTab { StudioTab(rawValue: tabRaw) ?? .overview }
    private var positionKey: String { "teoria.studio.pos.\(entry.id)" }
    private var desk: Color {
        switch theme { case .paper: Color(hex: 0xE9E5DC); case .sepia: Color(hex: 0xE2D5BA); case .night: Color(hex: 0x050505) }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                if panelFocus {
                    panel
                } else {
                    if showContents {
                        contents.frame(width: 268)
                        Divider()
                    }
                    readingDesk
                    if showPanel {
                        Divider()
                        panel.frame(width: 410 * min(panelScale, 1.3))
                    }
                }
            }
            Divider()
            scrubber
        }
        .background(Tema.arka)
        .navigationTitle(live.titleParts.title)
        .task { await loadBook() }
        .onChange(of: live.highlights) { _, _ in Task { await loadBook(reload: true) } }
        .onChange(of: live.words) { _, _ in Task { await loadBook(reload: true) } }
        .sheet(item: $tapped) { h in highlightSheet(h) }
        .sheet(item: $recall) { RecallSayfasi(isaret: $0).environmentObject(depo) }
        .sheet(item: $noteRequest) { r in
            NoteEditor(bookID: entry.id, bookTitle: entry.title, options: r.options).environmentObject(depo)
        }
        .overlay(alignment: .bottom) { toastView.padding(.bottom, 70) }
        .onKeyPress(.rightArrow) { guard !typing else { return .ignored }; turn(+1); return .handled }
        .onKeyPress(.leftArrow) { guard !typing else { return .ignored }; turn(-1); return .handled }
        .onKeyPress(.space) { guard !typing else { return .ignored }; turn(+1); return .handled }
        .onKeyPress(.pageDown) { guard !typing else { return .ignored }; turn(+1); return .handled }
        .onKeyPress(.pageUp) { guard !typing else { return .ignored }; turn(-1); return .handled }
        .focusable()
        .focusEffectDisabled()
        .background {
            // ⌘F search, ⌘L go to page, ⌘[ ⌘] contents / panel
            Group {
                Button("") { searchFocused = true; tabRaw = StudioTab.search.rawValue; showPanel = true }.keyboardShortcut("f", modifiers: .command)
                Button("") { pageFocused = true }.keyboardShortcut("l", modifiers: .command)
                Button("") { newNote() }.keyboardShortcut("n", modifiers: [.command, .option])
                Button("") { withAnimation { showContents.toggle() } }.keyboardShortcut("[", modifiers: .command)
                Button("") { withAnimation { showPanel.toggle() } }.keyboardShortcut("]", modifiers: .command)
                Button("") { toggleFocus() }.keyboardShortcut("]", modifiers: [.command, .shift])
                Button("") { if panelFocus { toggleFocus() } }.keyboardShortcut(.escape, modifiers: [])
                Button("") { zoomStep(0.1) }.keyboardShortcut("+", modifiers: [.command, .option])
                Button("") { zoomStep(-0.1) }.keyboardShortcut("-", modifiers: [.command, .option])
            }
            .opacity(0).allowsHitTesting(false)
        }
    }

    private var typing: Bool { searchFocused || pageFocused || noteRequest != nil || editingNote != nil || tapped != nil || recall != nil }

    // MARK: data

    private func loadBook(reload: Bool = false) async {
        if let b = await library.book(entry.id, kasa: depo.kasa) {
            if reload || book == nil || book?.highlights.count != b.highlights.count || book?.words != b.words { book = b }
        }
    }

    private func refresh() async {
        refreshing = true
        await depo.guncelle()
        await loadBook(reload: true)
        lastRefresh = Date()
        refreshing = false
    }

    // MARK: top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            toggle("sidebar.left", "İçindekiler (⌘[)", on: showContents) { withAnimation { showContents.toggle() } }
            VStack(alignment: .leading, spacing: 1) {
                Text(live.titleParts.title).font(Tema.serif(.headline, .semibold)).foregroundStyle(Tema.metin).lineLimit(1)
                HStack(spacing: 6) {
                    if let a = live.titleParts.author { Text(a).font(.caption).foregroundStyle(Tema.ikincil).lineLimit(1) }
                    badges
                }
            }
            .frame(minWidth: 160, alignment: .leading)
            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Image(systemName: "number").font(.caption).foregroundStyle(Tema.soluk)
                TextField("sayfa", text: $pageField)
                    .textFieldStyle(.plain).frame(width: 44).focused($pageFocused)
                    .onSubmit { if let n = Int(pageField), let layout { go(page: min(max(1, n), layout.pageCount) - 1) }; pageField = ""; pageFocused = false }
                Text("/ \(layout?.pageCount ?? 0)").font(.caption.monospacedDigit()).foregroundStyle(Tema.soluk)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background { RoundedRectangle(cornerRadius: 8).fill(Tema.yuzey2) }
            .help("Sayfaya git (⌘L)")

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(Tema.soluk)
                TextField("Kitapta ara", text: $query)
                    .textFieldStyle(.plain).frame(width: 170).focused($searchFocused)
                    .onSubmit { runSearch(query); tabRaw = StudioTab.search.rawValue; showPanel = true; if !hits.isEmpty { openHit(0) } }
                if !hits.isEmpty {
                    Text("\((hitIndex ?? 0) + 1)/\(hits.count)").font(.caption.monospacedDigit()).foregroundStyle(Tema.ikincil)
                    Button { openHit(((hitIndex ?? 0) - 1 + hits.count) % hits.count) } label: { Image(systemName: "chevron.up") }.buttonStyle(.plain)
                    Button { openHit(((hitIndex ?? -1) + 1) % hits.count) } label: { Image(systemName: "chevron.down") }.buttonStyle(.plain)
                    Button { query = ""; hits = []; hitIndex = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Tema.soluk) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background { RoundedRectangle(cornerRadius: 8).fill(Tema.yuzey2) }
            .help("Kitapta ara (⌘F)")

            HStack(spacing: 4) {
                ForEach(1...4, id: \.self) { c in
                    Button { markColor = c } label: {
                        Circle().fill(Marker.swatch(c)).frame(width: 14, height: 14)
                            .overlay { Circle().strokeBorder(Tema.metin.opacity(markColor == c ? 0.7 : 0), lineWidth: 2) }
                    }
                    .buttonStyle(.plain).help("İşaret rengi: \(IsaretRengi(rawValue: c)?.ad ?? "")")
                }
            }
            .padding(.horizontal, 6)

            Button { newNote() } label: { Label("Not", systemImage: "square.and.pencil").font(.callout.weight(.medium)) }
                .buttonStyle(.bordered).help("Not yaz ya da sesle anlat (⌥⌘N) — işaretlediğin cümleye, sayfaya ya da kitaba bağlı")

            Menu {
                Picker("Görünüm", selection: $themeRaw) { ForEach(ReaderTheme.allCases) { Text($0.name).tag($0.rawValue) } }
                Toggle("İki yana yasla", isOn: $justify)
                Divider()
                Button("Yazı büyüt") { size = min(30, size + 1) }.keyboardShortcut("+", modifiers: .command)
                Button("Yazı küçült") { size = max(13, size - 1) }.keyboardShortcut("-", modifiers: .command)
            } label: { Image(systemName: "textformat.size") }
                .menuStyle(.borderlessButton).frame(width: 34).help("Yazı ve görünüm")

            Button { Task { await refresh() } } label: {
                HStack(spacing: 5) {
                    if refreshing { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                    Text("Güncelle").font(.callout.weight(.medium))
                }
            }
            .buttonStyle(.bordered).disabled(refreshing)
            .help(lastRefresh.map { "Son güncelleme \($0.formatted(date: .omitted, time: .shortened)) · Voice Reader ve Voice Dream 10 dakikada bir kendiliğinden okunur" }
                  ?? "Voice Reader, Voice Dream ve kütüphaneyi şimdi oku (10 dakikada bir kendiliğinden de okunur)")

            toggle("arrow.up.left.and.arrow.down.right", "Tam ekran (⌃⌘F)", on: false) { NSApp.keyWindow?.toggleFullScreen(nil) }
            toggle("sidebar.right", "Kitabın haritası (⌘])", on: showPanel && !panelFocus) { withAnimation { panelFocus = false; showPanel.toggle() } }
            toggle("rectangle.expand.vertical", panelFocus ? "Kitaba dön (esc)" : "Haritayı bütün alana aç, büyük yazıyla (⇧⌘])", on: panelFocus) { toggleFocus() }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Tema.yuzey)
    }

    private func toggle(_ symbol: String, _ help: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium))
                .foregroundStyle(on ? Tema.vurgu : Tema.ikincil).frame(width: 30, height: 26)
        }
        .buttonStyle(.plain).help(help)
    }

    private var badges: some View {
        HStack(spacing: 4) {
            if live.inVR == true { badge("Voice Reader", Tema.vurgu) }
            if live.inVD { badge("Voice Dream", Tema.uyari) }
            if live.inVR != true && !live.inVD { badge("Arşiv", Tema.soluk) }
            if live.claude { badge("Claude metni", Tema.basari) }
        }
    }

    private func badge(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 10, weight: .semibold)).foregroundStyle(c)
            .padding(.horizontal, 6).padding(.vertical, 2).background { Capsule().fill(c.opacity(0.13)) }
    }

    // MARK: reading desk — the pages

    private let pad = EdgeInsets(top: 54, leading: 58, bottom: 46, trailing: 58)   // inside the paper

    private var readingDesk: some View {
        GeometryReader { geo in
            let n = geo.size.width > 980 ? 2 : 1
            let gap: CGFloat = n == 2 ? 0 : 0
            let outer: CGFloat = 26
            let paperW = min(760, floor((geo.size.width - outer * 2 - gap) / CGFloat(n)))
            let paperH = floor(geo.size.height - outer * 2)
            let text = CGSize(width: paperW - pad.leading - pad.trailing, height: paperH - pad.top - pad.bottom)
            ZStack {
                desk
                if let layout, layout.size == text, let book {
                    HStack(spacing: gap) {
                        ForEach(0..<n, id: \.self) { k in
                            paper(layout, book, current + k, side: n == 2 ? (k == 0 ? .left : .right) : .single, size: CGSize(width: paperW, height: paperH))
                        }
                    }
                    .shadow(color: .black.opacity(theme.isDark ? 0.6 : 0.16), radius: 18, y: 6)
                    .id("\(current).\(redraw)")
                    .transition(.opacity)
                } else {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text(book == nil ? (library.loading.contains(entry.id) ? "Kitap iniyor…" : "Kitap açılıyor…") : "Sayfalar diziliyor…")
                            .font(.caption).foregroundStyle(Tema.ikincil)
                        if let f = library.failed, book == nil { Text(f).font(.caption).foregroundStyle(Tema.uyari) }
                    }
                }
            }
            .onAppear { spread = n }
            .onChange(of: n) { _, v in spread = v; current = align(current) }
            .task(id: StudioLayoutKey(size: text, style: style, marks: book.map { library.withMarks($0).highlights.count } ?? -1, hidden: hidden)) {
                await relayout(text)
            }
        }
    }

    private struct StudioLayoutKey: Equatable { let size: CGSize; let style: ReaderStyle; let marks: Int; let hidden: Set<String> }
    private var hidden: Set<String> { insight?.dropped ?? [] }
    private enum Side { case left, right, single }

    private func paper(_ layout: BookLayout, _ book: Book, _ i: Int, side: Side, size: CGSize) -> some View {
        let pg = layout.pages[safe: i]
        return ZStack(alignment: .topLeading) {
            theme.background
            if side == .left {
                LinearGradient(colors: [.clear, .black.opacity(theme.isDark ? 0.35 : 0.07)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 34).frame(maxWidth: .infinity, alignment: .trailing)
            } else if side == .right {
                LinearGradient(colors: [.black.opacity(theme.isDark ? 0.35 : 0.08), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 34)
            }
            if let pg {
                // running head: book on the left page, chapter on the right
                Text(side == .left ? live.titleParts.title : (book.chapters[safe: pg.chapter]?.title ?? ""))
                    .font(.system(size: 10.5, weight: .semibold)).tracking(0.6).foregroundStyle(Color(theme.muted)).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: side == .left ? .leading : .trailing)
                    .padding(.horizontal, pad.leading).padding(.top, 24)
                PageCanvas(layout: layout, index: i, inset: .zero, live: liveMark(page: i), revision: redraw)
                    .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 6, coordinateSpace: .local)
                        .onChanged { v in dragMark = (i, v.startLocation, v.location) }
                        .onEnded { v in markRange(layout, book, page: i, from: v.startLocation, to: v.location); dragMark = nil })
                    .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { v in markSentence(layout, book, page: i, at: v.location) })
                    .simultaneousGesture(SpatialTapGesture(count: 1).onEnded { v in
                        if let id = layout.highlight(at: v.location, page: i), let h = findHighlight(id) { tapped = h }
                    })
                    .padding(.top, pad.top).padding(.leading, pad.leading)
                Text("\(i + 1)").font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(Color(theme.muted))
                    .frame(maxWidth: .infinity, alignment: side == .left ? .leading : (side == .right ? .trailing : .center))
                    .padding(.horizontal, pad.leading)
                    .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 18)
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: side == .right || side == .single ? .trailing : .leading) {
            // the outer edge of each page turns it, like a printed book
            Color.clear.frame(width: 44).contentShape(Rectangle())
                .onTapGesture { turn(side == .left ? -1 : +1) }
                .onHover { inside in if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
        }
        .overlay(alignment: .leading) {
            if side == .single { Color.clear.frame(width: 44).contentShape(Rectangle()).onTapGesture { turn(-1) } }
        }
    }

    // MARK: layout and navigation

    private func relayout(_ text: CGSize) async {
        guard text.width > 160, text.height > 200, let book else { return }
        let keep: Int = {
            if let layout, let pg = layout.pages[safe: current] { return pg.start }
            return UserDefaults.standard.integer(forKey: positionKey)
        }()
        let b = library.withMarks(book), st = style, hid = hidden
        let new = await LayoutCache.shared.layout(book: b, style: st, size: text, hidden: hid)
        guard !Task.isCancelled else { return }
        layout = new
        current = align(new.page(forOffset: keep))
    }

    private func align(_ p: Int) -> Int {
        let last = max(0, (layout?.pageCount ?? 1) - 1)
        let q = min(max(0, p), last)
        return spread == 2 ? q - q % 2 : q
    }

    private func turn(_ d: Int) {
        guard let layout else { return }
        let n = align(current + d * spread)
        guard n != current, n < layout.pageCount else { return }
        withAnimation(.easeInOut(duration: 0.22)) { current = n }
        save()
    }

    private func go(page p: Int) {
        withAnimation(.easeInOut(duration: 0.18)) { current = align(p) }
        save()
    }

    private func go(ch: Int, b: Int?, quote: String? = nil) {
        guard let layout, let book else { return }
        let bi = b ?? 0
        var r: NSRange?
        if let blk = book.chapters[safe: ch]?.blocks[safe: bi] {
            let ns = blk.x as NSString
            let q = quote.map { String($0.prefix(60)) } ?? ""
            let f = q.isEmpty ? NSRange(location: NSNotFound, length: 0) : ns.range(of: q, options: [.caseInsensitive, .diacriticInsensitive])
            let s = f.location == NSNotFound ? 0 : f.location
            let e = f.location == NSNotFound ? ns.length : min(ns.length, s + (quote.map { ($0 as NSString).length } ?? ns.length))
            r = layout.range(chapter: ch, block: bi, s: s, e: e)
            go(page: layout.page(chapter: ch, block: bi, offset: s))
        } else {
            go(page: layout.chapterFirstPage[safe: ch] ?? 0)
        }
        if let r {
            flash = LiveMark(chapter: ch, range: r, kind: .search)
            Task { try? await Task.sleep(for: .seconds(4)); flash = nil }
        }
    }

    private func save() {
        guard let layout, let pg = layout.pages[safe: current] else { return }
        UserDefaults.standard.set(pg.start, forKey: positionKey)
    }

    // MARK: where you left off listening (Voice Reader / Voice Dream percent → a block)

    private var listenSpot: (ch: Int, b: Int)? {
        guard let book, live.percent > 0, live.percent < 100 else { return nil }
        let words = book.chapters.map { $0.blocks.map { $0.isHeading ? 0 : $0.x.split(separator: " ").count } }
        let total = words.joined().reduce(0, +)
        guard total > 0 else { return nil }
        var left = Int(Double(total) * Double(live.percent) / 100)
        for (ci, ch) in words.enumerated() {
            for (bi, w) in ch.enumerated() {
                if left < w || (w > 0 && left == 0) { return (ci, bi) }
                left -= w
            }
        }
        return nil
    }

    private var listenPage: Int? {
        guard let layout, let s = listenSpot else { return nil }
        return layout.page(chapter: s.ch, block: s.b)
    }

    private func liveMark(page i: Int) -> LiveMark? {
        guard let layout, let pg = layout.pages[safe: i] else { return nil }
        if let d = dragMark, d.page == i, let a = layout.spot(at: d.from, page: i), let z = layout.spot(at: d.to, page: i),
           a.ch == z.ch, a.b == z.b, let r = layout.range(chapter: a.ch, block: a.b, s: min(a.off, z.off), e: max(a.off, z.off)) {
            return LiveMark(chapter: a.ch, range: r, kind: .search)
        }
        if let h = hitIndex, let hit = hits[safe: h], hit.ch == pg.chapter,
           let r = layout.range(chapter: hit.ch, block: hit.b, s: hit.range.location, e: NSMaxRange(hit.range)) {
            return LiveMark(chapter: hit.ch, range: r, kind: .search)
        }
        if let f = flash, f.chapter == pg.chapter { return f }
        if let s = listenSpot, s.ch == pg.chapter, let len = book?.chapters[safe: s.ch]?.blocks[safe: s.b].map({ ($0.x as NSString).length }),
           let r = layout.range(chapter: s.ch, block: s.b, s: 0, e: len) {
            return LiveMark(chapter: s.ch, range: r, kind: .cursor)
        }
        return nil
    }

    // MARK: marking

    private func markSentence(_ layout: BookLayout, _ book: Book, page i: Int, at p: CGPoint) {
        guard let spot = layout.spot(at: p, page: i), let blk = book.chapters[safe: spot.ch]?.blocks[safe: spot.b], !blk.isHeading else { return }
        let (a, z) = ReaderView.sentence(blk.x, at: spot.off)
        addMark(layout, ch: spot.ch, b: spot.b, s: a, e: z, text: blk.x)
    }

    /// Drag across words: the dragged span becomes a mark (snapped to whole words); across paragraphs, one mark per paragraph.
    private func markRange(_ layout: BookLayout, _ book: Book, page i: Int, from: CGPoint, to: CGPoint) {
        guard var a = layout.spot(at: from, page: i), var z = layout.spot(at: to, page: i) else { return }
        if (z.ch, z.b, z.off) < (a.ch, a.b, a.off) { swap(&a, &z) }
        guard a.ch == z.ch, let chapter = book.chapters[safe: a.ch] else { return }
        var made = 0
        for bi in a.b...z.b {
            guard let blk = chapter.blocks[safe: bi], !blk.isHeading else { continue }
            let ns = blk.x as NSString
            var s = bi == a.b ? a.off : 0, e = bi == z.b ? z.off + 1 : ns.length
            s = min(max(0, s), ns.length); e = min(max(s, e), ns.length)
            let letters = CharacterSet.alphanumerics
            func isWord(_ k: Int) -> Bool { guard k >= 0, k < ns.length, let u = UnicodeScalar(ns.character(at: k)) else { return false }; return letters.contains(u) }
            while s > 0, isWord(s - 1) { s -= 1 }
            while e < ns.length, isWord(e) { e += 1 }
            guard e - s >= 3 else { continue }
            addMark(layout, ch: a.ch, b: bi, s: s, e: e, text: blk.x, quiet: made > 0)
            made += 1
        }
    }

    private func addMark(_ layout: BookLayout, ch: Int, b: Int, s: Int, e: Int, text: String, quiet: Bool = false) {
        let ns = text as NSString
        guard e > s, e <= ns.length else { return }
        let q = ns.substring(with: NSRange(location: s, length: e - s)).trimmingCharacters(in: .whitespaces)
        let m = library.addMark(book: entry.id, ch: ch, b: b, s: s, e: e, quote: q, color: markColor)
        lastMark = m
        layout.apply(m.highlight)
        redraw += 1
        if !quiet {
            withAnimation(.snappy) { toast = ("İşaretlendi", m) }
            Task { try? await Task.sleep(for: .seconds(5)); if toast?.1?.id == m.id { withAnimation { toast = nil } } }
        }
        LibraryStore.shared.scheduleSync(depo.kasa)
    }

    private func undo(_ m: TeoriaMark) {
        library.deleteMark(m)
        layout?.remove(m.id)
        redraw += 1
        withAnimation { toast = nil }
        LibraryStore.shared.scheduleSync(depo.kasa)
    }

    private func findHighlight(_ id: String) -> BookHighlight? {
        book?.highlights.first { $0.id == id } ?? library.mark(id)?.highlight
    }

    @ViewBuilder
    private var toastView: some View {
        if let t = toast {
            HStack(spacing: 12) {
                Image(systemName: "highlighter").foregroundStyle(Marker.swatch(markColor))
                Text(t.0).font(.callout.weight(.semibold))
                if let m = t.1 {
                    Button("Geri al") { undo(m) }.buttonStyle(.borderless)
                    Button("Not ekle") { withAnimation { toast = nil }; newNote() }.buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background { Capsule().fill(.regularMaterial) }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: notes

    private func makeAnchor(ch: Int, b: Int, s: Int, e: Int) -> NoteAnchor? {
        guard let blk = book?.chapters[safe: ch]?.blocks[safe: b] else { return nil }
        let ns = blk.x as NSString
        guard s >= 0, e > s, e <= ns.length else { return nil }
        let q = ns.substring(with: NSRange(location: s, length: e - s)).trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty ? nil : NoteAnchor(ch: ch, b: b, s: s, e: e, quote: q, chapterTitle: book?.chapters[safe: ch]?.title)
    }

    private func pageAnchor() -> NoteAnchor? {
        guard let layout, let pg = layout.pages[safe: current] else { return nil }
        let starts = layout.blockStarts[safe: pg.chapter] ?? [:]
        for bi in starts.keys.sorted() {
            guard let (st, len) = starts[bi], st + len > pg.range.location,
                  let blk = book?.chapters[safe: pg.chapter]?.blocks[safe: bi], !blk.isHeading else { continue }
            let (a, z) = ReaderView.sentence(blk.x, at: max(0, pg.range.location - st))
            return makeAnchor(ch: pg.chapter, b: bi, s: a, e: z)
        }
        return nil
    }

    /// Places a note can hang on: the sentence just marked, the line where you left off listening, this page.
    private func noteOptions() -> [(label: String, anchor: NoteAnchor)] {
        var out: [(label: String, anchor: NoteAnchor)] = []
        func add(_ label: String, _ a: NoteAnchor?) { if let a, !out.contains(where: { $0.anchor == a }) { out.append((label, a)) } }
        if let m = lastMark, library.mark(m.id) != nil, Date().timeIntervalSince(Tarih.coz(m.date) ?? .distantPast) < 900 {
            add("İşaretlediğin cümle", makeAnchor(ch: m.ch, b: m.b, s: m.s, e: m.e))
        }
        add("Bu sayfa", pageAnchor())
        return out
    }

    private func newNote(_ extra: NoteAnchor? = nil) {
        var o = noteOptions()
        if let extra { o.removeAll { $0.anchor == extra }; o.insert(("İşaretlediğin yer", extra), at: 0) }
        noteRequest = NoteRequest(options: o)
    }

    private var notesTab: some View {
        let mine = notesStore.notes(of: entry.id)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(mine.count) not · \(mine.reduce(0) { $0 + $1.sentences }) cümle · \(mine.reduce(0) { $0 + $1.words }) kelime")
                    .font(.caption.weight(.semibold)).foregroundStyle(Tema.ikincil).monospacedDigit()
                Spacer()
                Button { newNote() } label: { Label("Yeni not", systemImage: "plus") }.controlSize(.small)
            }
            if mine.isEmpty {
                Text("Bu kitapta henüz notun yok. Bir cümleyi işaretleyip “Not ekle”ye bas, sayfaya ya da kitabın tamamına yaz; istersen sesinle anlat.")
                    .font(.callout).foregroundStyle(Tema.ikincil)
            }
            ForEach(mine) { n in
                NoteRow(player: notePlayer, note: n, onEdit: { editingNote = n },
                        onJump: n.anchor.map { a in { if let layout { go(page: layout.page(chapter: a.ch, block: a.b, offset: a.s)) } } })
            }
        }
        .sheet(item: $editingNote) { n in
            NoteEditor(bookID: entry.id, bookTitle: entry.title, options: noteOptions(), existing: n).environmentObject(depo)
        }
    }

    // MARK: search

    private func runSearch(_ q: String) {
        guard let book else { return }
        let needle = q.trimmingCharacters(in: .whitespaces)
        guard needle.count >= 2 else { hits = []; hitIndex = nil; return }
        var out: [SearchHit] = []
        outer: for (ci, ch) in book.chapters.enumerated() {
            for (bi, blk) in ch.blocks.enumerated() {
                let ns = blk.x as NSString
                var from = 0
                while from < ns.length {
                    let r = ns.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: NSRange(location: from, length: ns.length - from), locale: Dil.tr)
                    if r.location == NSNotFound { break }
                    let a = max(0, r.location - 60), z = min(ns.length, NSMaxRange(r) + 80)
                    out.append(SearchHit(ch: ci, b: bi, range: r,
                                         before: (a > 0 ? "…" : "") + ns.substring(with: NSRange(location: a, length: r.location - a)),
                                         match: ns.substring(with: r),
                                         after: ns.substring(with: NSRange(location: NSMaxRange(r), length: z - NSMaxRange(r))) + (z < ns.length ? "…" : "")))
                    if out.count >= 800 { break outer }
                    from = NSMaxRange(r)
                }
            }
        }
        hits = out
        hitIndex = nil
    }

    private func openHit(_ i: Int) {
        guard let layout, let h = hits[safe: i] else { return }
        hitIndex = i
        go(page: layout.page(chapter: h.ch, block: h.b, offset: h.range.location))
    }

    // MARK: contents (left)

    private var currentChapter: Int { layout?.pages[safe: current]?.chapter ?? 0 }

    private var contents: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    Text("İÇİNDEKİLER").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(Tema.soluk)
                        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 6)
                    if let book {
                        let marked = Dictionary(grouping: library.withMarks(book).highlights.compactMap { $0.at.first?.ch }, by: { $0 }).mapValues(\.count)
                        let keyed = Dictionary(grouping: (insight?.keys ?? []).compactMap(\.ch), by: { $0 }).mapValues(\.count)
                        let listenCh = listenSpot?.ch
                        ForEach(Array(book.chapters.enumerated()), id: \.offset) { ci, ch in
                            if let part = ch.part, part != book.chapters[safe: ci - 1]?.part {
                                Text(part.uppercased(with: Dil.tr)).font(.system(size: 9.5, weight: .bold)).tracking(0.8)
                                    .foregroundStyle(tint).padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 2)
                            }
                            Button { go(page: layout?.chapterFirstPage[safe: ci] ?? 0) } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Circle()
                                        .fill(listenCh.map { ci < $0 ? Tema.basari : (ci == $0 ? Color(hex: 0xE8B20E) : Tema.cizgi) } ?? (live.percent >= 90 ? Tema.basari : Tema.cizgi))
                                        .frame(width: 7, height: 7).padding(.top, 5)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ch.title).font(.system(size: 12.5, weight: ci == currentChapter ? .semibold : .regular))
                                            .foregroundStyle(ci == currentChapter ? Tema.metin : Tema.ikincil)
                                            .multilineTextAlignment(.leading).lineLimit(3)
                                        HStack(spacing: 8) {
                                            if let p = layout?.chapterFirstPage[safe: ci] { Text("s. \(p + 1)").monospacedDigit() }
                                            if let m = marked[ci] { Label("\(m)", systemImage: "highlighter") }
                                            if let k = keyed[ci] { Label("\(k)", systemImage: "key.horizontal") }
                                        }
                                        .font(.system(size: 10)).foregroundStyle(Tema.soluk).labelStyle(.titleAndIcon)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background { RoundedRectangle(cornerRadius: 8).fill(ci == currentChapter ? tint.opacity(0.12) : .clear) }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(insight?.summary(ci)?.summary ?? ch.title)
                            .id(ci)
                        }
                    }
                }
                .padding(.horizontal, 6).padding(.bottom, 20)
            }
            .onChange(of: currentChapter) { _, c in withAnimation { proxy.scrollTo(c, anchor: .center) } }
        }
        .background(Tema.yuzey)
    }

    // MARK: scrubber (bottom)

    private var scrubber: some View {
        HStack(spacing: 14) {
            Button { turn(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain).disabled(current == 0)
            let count = max(1, (layout?.pageCount ?? 1) - 1)
            ZStack(alignment: .leading) {
                Slider(value: Binding(get: { scrub ?? Double(current) }, set: { scrub = $0 }), in: 0...Double(count)) { editing in
                    if !editing, let s = scrub { go(page: Int(s.rounded())); scrub = nil }
                }
                .controlSize(.small)
                if let lp = listenPage {
                    GeometryReader { g in
                        Capsule().fill(Color(hex: 0xE8B20E)).frame(width: 3, height: 14)
                            .offset(x: 8 + (g.size.width - 16) * CGFloat(lp) / CGFloat(count) - 1.5, y: g.size.height / 2 - 7)
                    }
                    .allowsHitTesting(false)
                }
            }
            .frame(height: 22)
            Text(pageLabel).font(.caption.monospacedDigit()).foregroundStyle(Tema.ikincil).frame(minWidth: 210, alignment: .trailing)
            if let lp = listenPage {
                Button { go(page: lp) } label: {
                    Label("Dinlediğin yer · %\(live.percent)", systemImage: "headphones").font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered).tint(Color(hex: 0xC99500))
                .help("Voice Reader / Voice Dream'de kaldığın yer (sarı satır, yaklaşık)")
            }
            Button { turn(+1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Tema.yuzey)
    }

    private var pageLabel: String {
        guard let layout, layout.pageCount > 0 else { return "" }
        let p = Int((scrub ?? Double(current)).rounded())
        let last = min(layout.pageCount, p + spread)
        let ch = book?.chapters[safe: layout.pages[safe: p]?.chapter ?? 0]?.title ?? ""
        let pct = Int((Double(p + 1) / Double(layout.pageCount) * 100).rounded())
        return "\(String(ch.prefix(26))) · s. \(p + 1)\(last > p + 1 ? "–\(last)" : "") / \(layout.pageCount) · %\(pct)"
    }


    // MARK: panel type scale — macOS text styles are tiny (caption = 10 pt), so the whole book map uses explicit sizes × zoom
    private var zoom: CGFloat { panelFocus ? focusScale : panelScale }
    private func S(_ n: CGFloat) -> CGFloat { ((n < 12 ? n + 1.5 : n + 0.5) * zoom).rounded() }
    private func F(_ style: Font.TextStyle, _ weight: Font.Weight = .regular, serif: Bool = false) -> Font {
        let base: CGFloat
        switch style {
        case .caption2: base = 11.5
        case .caption: base = 12.5
        case .footnote: base = 13
        case .callout: base = 14.5
        case .subheadline: base = 14.5
        case .body: base = 15.5
        case .headline: base = 15.5
        case .title3: base = 19
        case .title2: base = 23
        default: base = 14.5
        }
        let w: Font.Weight = style == .headline && weight == .regular ? .semibold : weight
        return .system(size: (base * zoom).rounded(), weight: w, design: serif ? .serif : .default)
    }

    private func zoomStep(_ d: CGFloat) {
        if panelFocus { focusScale = min(2.2, max(1.0, ((focusScale + d) * 20).rounded() / 20)) }
        else { panelScale = min(1.8, max(0.9, ((panelScale + d) * 20).rounded() / 20)) }
    }

    private func toggleFocus() { withAnimation(.easeInOut(duration: 0.2)) { panelFocus.toggle(); if panelFocus { showPanel = true } } }

    // MARK: panel (right) — the whole book

    private var panel: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(StudioTab.allCases.filter { $0 != .search || !hits.isEmpty || !query.isEmpty }) { t in
                        Button { tabRaw = t.rawValue } label: {
                            Image(systemName: t.symbol).font(.system(size: S(13), weight: .semibold))
                                .foregroundStyle(tab == t ? Tema.vurgu : Tema.ikincil)
                                .frame(width: 36, height: 28)
                                .background { RoundedRectangle(cornerRadius: 7).fill(tab == t ? Tema.vurgu.opacity(0.12) : .clear) }
                        }
                        .buttonStyle(.plain).help(t.name)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
            }
            HStack(spacing: 6) {
                Text(tab.name.uppercased(with: Dil.tr)).font(.system(size: S(10.5), weight: .bold)).tracking(1).foregroundStyle(Tema.soluk)
                Spacer()
                Button { zoomStep(-0.1) } label: { Image(systemName: "textformat.size.smaller") }
                    .buttonStyle(.borderless).help("Yazıyı küçült (⌥⌘−)").accessibilityLabel("Yazıyı küçült")
                Text("%\(Int((zoom * 100).rounded()))").font(.caption.monospacedDigit()).foregroundStyle(Tema.soluk)
                Button { zoomStep(0.1) } label: { Image(systemName: "textformat.size.larger") }
                    .buttonStyle(.borderless).help("Yazıyı büyüt (⌥⌘+)").accessibilityLabel("Yazıyı büyüt")
                Button { toggleFocus() } label: {
                    Image(systemName: panelFocus ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.borderless).help(panelFocus ? "Kitaba dön (esc)" : "Bütün alana aç (⇧⌘])")
                .accessibilityLabel(panelFocus ? "Kitaba dön" : "Bütün alana aç")
            }
            .padding(.horizontal, 16).padding(.bottom, 4)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch tab {
                    case .overview: overview
                    case .keys: keysTab
                    case .chain: chainTab
                    case .chapters: chaptersTab
                    case .map: mapTab
                    case .links: linksTab
                    case .sources: sourcesTab
                    case .marks: marksTab
                    case .notes: notesTab
                    case .search: searchTab
                    }
                }
                .padding(panelFocus ? 32 : 16)
                .frame(maxWidth: panelFocus ? 1000 : .infinity, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: panelFocus ? .center : .leading)
            }
        }
        .background(Tema.arka)
    }

    private func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        c().padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Tema.yuzey) }
    }

    private func pending(_ title: String) -> some View {
        card {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: "hourglass").font(F(.callout, .semibold)).foregroundStyle(Tema.ikincil)
                Text("Kitap kütüphaneye girdiği anda Claude'un sırasına alındı (dinleme yüzdesi beklenmez). Sabah görevi her gün altı kitap yazar; şu an dinlediklerin önce gelir. Hemen istersen: \"Teoria kitap işle\".")
                    .font(F(.caption)).foregroundStyle(Tema.soluk).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // Genel — numbers, status, core

    private var status: (String, Color) {
        if live.percent >= 90 { return ("Bitti", Tema.basari) }
        if live.percent > 0 { return ("Sürüyor", Color(hex: 0xC99500)) }
        return ("Başlanmadı", Tema.soluk)
    }

    @ViewBuilder
    private var overview: some View {
        let marks = book.map { library.withMarks($0).highlights.count } ?? live.highlights
        let own = library.marks[entry.id]?.count ?? 0
        HStack(alignment: .top, spacing: 14) {
            KitapKapagi(id: entry.id, baslik: live.titleParts.title, genislik: 92)
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    Circle().stroke(Tema.cizgi, lineWidth: 7)
                    Circle().trim(from: 0, to: CGFloat(live.percent) / 100).stroke(status.1, style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("%\(live.percent)").font(.system(size: S(19), weight: .bold, design: .rounded)).foregroundStyle(Tema.metin)
                        Text("dinlendi").font(.system(size: S(9))).foregroundStyle(Tema.soluk)
                    }
                }
                .frame(width: 84, height: 84)
                Text(status.0).font(F(.caption, .bold)).foregroundStyle(status.1)
                    .padding(.horizontal, 8).padding(.vertical, 3).background { Capsule().fill(status.1.opacity(0.13)) }
            }
            Spacer(minLength: 0)
        }
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            stat("Kelime", live.words.formatted(.number.locale(Dil.tr)), "text.word.spacing")
            stat("Sayfa", "≈ \(max(1, live.words / 225)) basılı", "doc.plaintext", sub: layout.map { "\($0.pageCount) ekran sayfası" })
            stat("Bölüm", "\(book?.chapters.count ?? live.chapters)", "list.number")
            stat("İşaret", "\(marks)", "highlighter", sub: own > 0 ? "\(marks - own) dinlerken · \(own) Teoria'da" : "dinlerken yapılan")
            stat("Son dinleme", Tarih.coz(live.last ?? "").map(Tarih.kisa) ?? "—", "headphones",
                 sub: live.inVR == true ? "Voice Reader" : (live.inVD ? "Voice Dream" : "arşiv"))
            stat("Burada", layout.map { "s. \(current + 1) / \($0.pageCount)" } ?? "—", "book",
                 sub: layout.map { "%\(Int((Double(current + 1) / Double(max(1, $0.pageCount)) * 100).rounded())) okuma konumu" })
        }
        BookRatingBar(book: entry.id)
        if let i = insight {
            if let c = i.core, c.theme != nil || c.claim != nil || c.idea != nil {
                card {
                    VStack(alignment: .leading, spacing: 10) {
                        if let t = c.theme { coreRow("ANA TEMA", t, tint) }
                        if let t = c.claim { coreRow("TEMEL İDDİA", t, Tema.vurgu) }
                        if let t = c.idea { coreRow("ANA FİKİR", t, Tema.basari) }
                    }
                }
            }
            if let t = i.thesis, !t.isEmpty {
                card { coreRow("TEZ", t, Tema.metin) }
            }
            if !i.verdicts.isEmpty {
                card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("YARGILAR").font(.system(size: S(10), weight: .bold)).tracking(0.8).foregroundStyle(Tema.soluk)
                        ForEach(Array(i.verdicts.enumerated()), id: \.offset) { _, v in
                            HStack(alignment: .top, spacing: 8) {
                                Text("◆").font(F(.caption2)).foregroundStyle(tint).padding(.top, 3)
                                Text(v).font(F(.callout, .regular, serif: true)).foregroundStyle(Tema.metin).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            if let m = library.network.books[entry.id], let c = library.network.clusters[m.cluster] {
                card {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("OKUMA AĞINDAKİ YERİ · \(c.name.uppercased(with: Dil.tr))").font(.system(size: S(10), weight: .bold)).tracking(0.8).foregroundStyle(Tema.soluk)
                        Text(c.question).font(F(.callout, .regular, serif: true)).foregroundStyle(Tema.metin).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } else {
            pending("Ana fikir ve harita henüz yazılmadı")
        }
    }

    private func stat(_ k: String, _ v: String, _ symbol: String, sub: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(k, systemImage: symbol).font(.system(size: S(10.5), weight: .semibold)).foregroundStyle(Tema.soluk)
            Text(v).font(.system(size: S(15), weight: .semibold, design: .rounded)).foregroundStyle(Tema.metin).lineLimit(1).minimumScaleFactor(0.7)
            if let sub { Text(sub).font(.system(size: S(10))).foregroundStyle(Tema.soluk).lineLimit(1) }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Tema.yuzey) }
    }

    private func coreRow(_ k: String, _ v: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(k).font(.system(size: S(10), weight: .bold)).tracking(0.8).foregroundStyle(c)
            Text(v).font(F(.body, .regular, serif: true)).foregroundStyle(Tema.metin).lineSpacing(2).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
    }

    private func chapterName(_ ch: Int?) -> String {
        guard let ch, let t = book?.chapters[safe: ch]?.title else { return "" }
        return t
    }

    // Can alıcı — key sentences (marked or not) and what you missed

    @ViewBuilder
    private var keysTab: some View {
        let keys = (insight?.keys ?? []).sorted { $0.weight > $1.weight }
        let missed = insight?.missed ?? []
        if keys.isEmpty && missed.isEmpty {
            pending("Can alıcı cümleler henüz seçilmedi")
        } else {
            ForEach(keys) { k in
                Button { if let ch = k.ch { go(ch: ch, b: k.b, quote: k.quote) } } label: {
                    card {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 3) {
                                ForEach(0..<5, id: \.self) { n in Circle().fill(n < k.weight ? tint : Tema.cizgi).frame(width: 5, height: 5) }
                                Text(chapterName(k.ch)).font(.system(size: S(10), weight: .semibold)).foregroundStyle(Tema.soluk).lineLimit(1).padding(.leading, 6)
                                Spacer()
                                if k.ch != nil { Image(systemName: "arrow.right.circle").font(F(.caption)).foregroundStyle(Tema.soluk) }
                            }
                            Text("“\(k.quote)”").font(F(.callout, .regular, serif: true)).foregroundStyle(Tema.metin).lineSpacing(2)
                                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            Text(k.why).font(F(.caption)).foregroundStyle(Tema.ikincil).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            if !missed.isEmpty {
                Bolumbasi(metin: "İşaretlemediğin taşıyıcı yerler", sembol: "eye.slash").padding(.top, 6)
                ForEach(missed) { m in
                    Button { if let ch = m.ch { go(ch: ch, b: m.b, quote: m.quote) } } label: {
                        card {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("“\(m.quote)”").font(F(.callout, .regular, serif: true)).foregroundStyle(Tema.metin).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                Text(m.why).font(F(.caption)).foregroundStyle(Tema.ikincil).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // İddia zinciri

    @ViewBuilder
    private var chainTab: some View {
        let chain = insight?.chain ?? []
        let nuances = insight?.nuances ?? []
        if chain.isEmpty && nuances.isEmpty {
            pending("İddia zinciri henüz yazılmadı")
        } else {
            if !chain.isEmpty {
                card {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(chain.enumerated()), id: \.offset) { i, z in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(spacing: 0) {
                                    Text("\(i + 1)").font(.system(size: S(11), weight: .bold, design: .rounded)).foregroundStyle(.white)
                                        .frame(width: 22, height: 22).background { Circle().fill(tint) }
                                    if i < chain.count - 1 { Rectangle().fill(tint.opacity(0.25)).frame(width: 2).frame(maxHeight: .infinity) }
                                }
                                Text(z).font(F(.callout, .regular, serif: true)).foregroundStyle(Tema.metin).lineSpacing(2)
                                    .fixedSize(horizontal: false, vertical: true).padding(.bottom, 14).padding(.top, 2)
                            }
                        }
                    }
                }
            }
            if !nuances.isEmpty {
                Bolumbasi(metin: "İnce ayrımlar", sembol: "scissors").padding(.top, 4)
                ForEach(Array(nuances.enumerated()), id: \.offset) { _, n in
                    card {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(n.title).font(F(.headline, .regular, serif: true)).foregroundStyle(Tema.metin).fixedSize(horizontal: false, vertical: true)
                            if let t = n.text { Text(t).font(F(.caption)).foregroundStyle(Tema.ikincil).fixedSize(horizontal: false, vertical: true) }
                        }
                    }
                }
            }
        }
    }

    // Bölüm haritası — every chapter with its essence and its place in your listening

    @ViewBuilder
    private var chaptersTab: some View {
        if let book {
            let listenCh = listenSpot?.ch
            ForEach(Array(book.chapters.enumerated()), id: \.offset) { ci, ch in
                Button { go(page: layout?.chapterFirstPage[safe: ci] ?? 0) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(ci + 1)").font(.system(size: S(11), weight: .bold, design: .rounded))
                            .foregroundStyle(ci == currentChapter ? .white : Tema.ikincil)
                            .frame(width: 24, height: 24)
                            .background { Circle().fill(ci == currentChapter ? tint : Tema.yuzey2) }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(ch.title).font(.system(size: S(13), weight: .semibold)).foregroundStyle(Tema.metin).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                if let l = listenCh {
                                    Text(ci < l ? "dinlendi" : (ci == l ? "burada" : "")).font(.system(size: S(9.5), weight: .bold))
                                        .foregroundStyle(ci < l ? Tema.basari : Color(hex: 0xC99500))
                                } else if live.percent >= 90 {
                                    Text("dinlendi").font(.system(size: S(9.5), weight: .bold)).foregroundStyle(Tema.basari)
                                }
                            }
                            if let s = insight?.summary(ci) {
                                Text(s.summary).font(F(.caption)).foregroundStyle(Tema.ikincil).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                if let k = s.key { Text("“\(k)”").font(F(.caption, .regular, serif: true)).foregroundStyle(Tema.metin.opacity(0.8)).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true) }
                            } else if let sub = ch.sub {
                                Text(sub).font(F(.caption)).foregroundStyle(Tema.soluk)
                            }
                        }
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(ci == currentChapter ? tint.opacity(0.08) : Tema.yuzey) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if insight == nil || insight?.chapters.isEmpty == true {
                Text("Bölümlerin özü Claude kitabı işleyince burada belirir.").font(F(.caption)).foregroundStyle(Tema.soluk)
            }
        }
    }

    // Kavram haritası

    @ViewBuilder
    private var mapTab: some View {
        if let c = insight?.concepts, !c.nodes.isEmpty {
            ConceptMapView(map: c, tint: tint, selected: $node)
                .frame(height: max(380, CGFloat(min(c.nodes.count, 16)) * 32))
                .background { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Tema.yuzey) }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            if let n = node {
                card {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(n.label).font(F(.title3, .semibold, serif: true)).foregroundStyle(Tema.metin)
                        if let note = n.note { Text(note).font(F(.callout)).foregroundStyle(Tema.ikincil).fixedSize(horizontal: false, vertical: true) }
                        ForEach(Array(c.edges.filter { $0.a == n.id || $0.b == n.id }.enumerated()), id: \.offset) { _, e in
                            let other = c.nodes.first { $0.id == (e.a == n.id ? e.b : e.a) }?.label ?? ""
                            Text("\(e.a == n.id ? "→" : "←") \(e.label ?? "bağlı") · \(other)").font(F(.caption)).foregroundStyle(Tema.ikincil)
                        }
                        if let chs = n.ch, !chs.isEmpty {
                            AkanYerlesim(aralik: 6) {
                                ForEach(chs, id: \.self) { ci in
                                    Button { go(page: layout?.chapterFirstPage[safe: ci] ?? 0) } label: {
                                        Text(chapterName(ci).isEmpty ? "Bölüm \(ci + 1)" : chapterName(ci)).font(F(.caption, .semibold)).lineLimit(1)
                                            .padding(.horizontal, 9).padding(.vertical, 5)
                                            .background { Capsule().fill(tint.opacity(0.14)) }.foregroundStyle(tint)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            } else {
                Text("Bir kavrama tıkla: tanımı, bağları ve geçtiği bölümler açılır.").font(F(.caption)).foregroundStyle(Tema.soluk)
            }
        } else {
            pending("Kavram haritası henüz kurulmadı")
        }
    }

    // Çapraz bağlar — the shelf books this one talks to, and its neighbours in the reading network

    @ViewBuilder
    private var linksTab: some View {
        let links = insight?.links ?? []
        let cluster = library.network.books[entry.id]?.cluster
        let mates = cluster.map { c in library.network.books.filter { $0.value.cluster == c && $0.key != entry.id }.keys.compactMap(library.entry) } ?? []
        if links.isEmpty && mates.isEmpty {
            pending("Öbür kitaplarla bağlar henüz kurulmadı")
        } else {
            ForEach(Array(links.enumerated()), id: \.offset) { _, l in
                if let e = library.entry(l.to) { shelfLink(e, kind: l.kind ?? "bağlı", note: l.note) }
            }
            if !mates.isEmpty, let c = cluster.flatMap({ library.network.clusters[$0] }) {
                Bolumbasi(metin: "Aynı soruyu soranlar · \(c.name)", sembol: "circle.hexagongrid").padding(.top, 6)
                ForEach(mates.filter { m in !links.contains { $0.to == m.id } }) { e in shelfLink(e, kind: nil, note: nil) }
            }
        }
    }

    private func shelfLink(_ e: LibraryEntry, kind: String?, note: String?) -> some View {
        NavigationLink(value: e.id) {
            HStack(spacing: 10) {
                KitapKapagi(id: e.id, baslik: e.titleParts.title, genislik: 34)
                VStack(alignment: .leading, spacing: 2) {
                    if let kind { Text(kind.uppercased(with: Dil.tr)).font(.system(size: S(9.5), weight: .bold)).foregroundStyle(Tema.basari) }
                    Text(e.titleParts.title).font(F(.callout, .semibold, serif: true)).foregroundStyle(Tema.metin).lineLimit(2)
                    if let note { Text(note).font(F(.caption)).foregroundStyle(Tema.ikincil).fixedSize(horizontal: false, vertical: true) }
                    Text("%\(e.percent) · \(e.highlights) işaret").font(.system(size: S(10))).foregroundStyle(Tema.soluk)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(F(.caption)).foregroundStyle(Tema.soluk)
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Tema.yuzey) }
        }
        .buttonStyle(.plain)
    }

    // Kaynakça

    @ViewBuilder
    private var sourcesTab: some View {
        let src = insight?.sources ?? []
        if src.isEmpty {
            pending("Kaynakça henüz yazılmadı")
        } else {
            ForEach([("Başvuru · metnin dayandığı", true), ("Öneri · sonra okunacak", false)], id: \.1) { title, ref in
                let l = src.filter { $0.isReference == ref }
                if !l.isEmpty {
                    Bolumbasi(metin: title, sembol: ref ? "text.book.closed" : "sparkles")
                    ForEach(Array(l.enumerated()), id: \.offset) { _, s in
                        card {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(s.work).font(F(.callout, .semibold, serif: true)).foregroundStyle(Tema.metin).fixedSize(horizontal: false, vertical: true)
                                Text([s.author, s.year.map(String.init)].compactMap { $0 }.joined(separator: " · ")).font(F(.caption)).foregroundStyle(Tema.soluk)
                                if let w = s.why { Text(w).font(F(.caption)).foregroundStyle(Tema.ikincil).fixedSize(horizontal: false, vertical: true) }
                            }
                        }
                    }
                }
            }
        }
    }

    // İşaretler — every mark in book order

    @ViewBuilder
    private var marksTab: some View {
        if let book = book.map(library.withMarks) {
            let hs = book.highlights.sorted { Self.order($0) < Self.order($1) }
            if hs.isEmpty {
                card { Text("Bu kitapta işaret yok. Sayfada bir cümleye çift tıkla ya da kelimelerin üstünden sürükle: işaretlenir.").font(F(.caption)).foregroundStyle(Tema.ikincil) }
            } else {
                Text("\(hs.count) işaret").font(F(.caption)).foregroundStyle(Tema.soluk)
                ForEach(hs) { h in
                    HStack(alignment: .top, spacing: 6) {
                    Button { if let p = h.at.first { go(ch: p.ch, b: p.b, quote: h.quote) } } label: {
                        HStack(alignment: .top, spacing: 10) {
                            RoundedRectangle(cornerRadius: 2).fill(Marker.swatch(h.color)).frame(width: 4)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(chapterName(h.at.first?.ch)).font(.system(size: S(10), weight: .semibold)).foregroundStyle(Tema.soluk).lineLimit(1)
                                    Spacer()
                                    if library.mark(h.id) != nil { Text("Teoria").font(.system(size: S(9.5), weight: .bold)).foregroundStyle(Tema.vurgu) }
                                }
                                Text(h.quote).font(F(.callout, .regular, serif: true)).foregroundStyle(Tema.metin).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                if let n = h.note { Label(n, systemImage: "note.text").font(F(.caption)).foregroundStyle(Tema.ikincil) }
                            }
                        }
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Tema.yuzey) }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    ExpandToggle(book: entry.id, highlight: h, compact: true).padding(.top, 10)
                    }
                }
            }
        }
    }

    private static func order(_ h: BookHighlight) -> Int {
        guard let p = h.at.first else { return 0 }
        return p.ch * 100_000_000 + p.b * 100_000 + p.s
    }

    // Arama sonuçları

    @ViewBuilder
    private var searchTab: some View {
        if hits.isEmpty {
            Text(query.count < 2 ? "Üstteki kutuya en az iki harf yaz, ↩ ile ara." : "“\(query)” bu kitapta geçmiyor.").font(F(.caption)).foregroundStyle(Tema.soluk)
        } else {
            Text("\(hits.count) yer\(hits.count >= 800 ? " (ilk 800)" : "")").font(F(.caption)).foregroundStyle(Tema.soluk)
            ForEach(Array(hits.enumerated()), id: \.element.id) { i, h in
                Button { openHit(i) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(chapterName(h.ch)).font(.system(size: S(10), weight: .semibold)).foregroundStyle(Tema.soluk).lineLimit(1)
                        (Text(h.before).foregroundStyle(Tema.ikincil) + Text(h.match).bold().foregroundStyle(Tema.metin) + Text(h.after).foregroundStyle(Tema.ikincil))
                            .font(F(.caption)).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(9).frame(maxWidth: .infinity, alignment: .leading)
                    .background { RoundedRectangle(cornerRadius: 10).fill(i == hitIndex ? Tema.uyari.opacity(0.14) : Tema.yuzey) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: a tapped highlight

    private func highlightSheet(_ h: BookHighlight) -> some View {
        let own = library.mark(h.id)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(Marker.swatch(h.color)).frame(width: 10, height: 10)
                Text(IsaretRengi(rawValue: h.color)?.ad ?? "işaret").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(own != nil ? "· Teoria'da" : "· dinlerken").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if h.time != .distantPast { Text(Tarih.kisa(h.time)).font(.caption).foregroundStyle(.secondary) }
            }
            Text(h.quote).font(.system(.title3, design: .serif)).lineSpacing(4).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            if let n = h.note { Label(n, systemImage: "note.text").font(.callout).foregroundStyle(.secondary) }
            if let ch = h.at.first?.ch, let s = insight?.summary(ch) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("BÖLÜMÜN ÖZÜ").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                    Text(s.summary).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider()
            HStack {
                Button {
                    let i = Isaret(id: "kitap:\(entry.id):\(h.id)", kitap: entry.id, baslik: entry.title, metin: h.quote,
                                   renk: h.color, tarih: h.date ?? Tarih.gun(Date()), kaynak: "kitap", baglam: nil)
                    tapped = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { recall = i }
                } label: { Label("Kapat · hatırla · yeniden kur", systemImage: "brain.head.profile") }
                    .buttonStyle(.borderedProminent)
                Button {
                    let place = h.at.first.flatMap { makeAnchor(ch: $0.ch, b: $0.b, s: $0.s, e: $0.e) }
                    tapped = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { newNote(place) }
                } label: { Label("Not yaz", systemImage: "square.and.pencil") }
                    .buttonStyle(.bordered)
                if let own {
                    Button(role: .destructive) { tapped = nil; undo(own) } label: { Label("İşareti sil", systemImage: "trash") }
                        .buttonStyle(.bordered)
                }
                Spacer()
                Button("Kapat") { tapped = nil }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}
