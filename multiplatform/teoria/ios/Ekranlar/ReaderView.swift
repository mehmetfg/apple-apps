// Reader — Apple Books style. Two ways in: the whole text, or only the pages that carry your highlights, one after
// another. A highlighted page always opens back into the whole text at the same place.
// Listen (the device's Turkish voices, speed, tone) with the sentence followed on the page; mark while reading
// (press and hold a sentence) or while listening (İşaretle). Search inside the book.
import SwiftUI
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

enum ReaderMode: String { case full, marked }

struct SearchHit: Identifiable, Hashable {
    let ch: Int; let b: Int; let range: NSRange; let before: String; let match: String; let after: String
    var id: String { "\(ch).\(b).\(range.location)" }
}

struct ReaderView: View {
    @EnvironmentObject var depo: Depo
    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var voice = ReaderVoice.shared
    @Environment(\.dismiss) private var dismiss
    let book: Book
    @State var mode: ReaderMode
    var jump: (ch: Int, b: Int)? = nil

    @AppStorage("teoria.reader.size") private var size: Double = 19
    @AppStorage("teoria.reader.theme") private var themeRaw = ReaderTheme.paper.rawValue
    @AppStorage("teoria.reader.scroll") private var scrollMode = false
    @AppStorage("teoria.reader.hideRepeats") private var hideRepeats = true
    @AppStorage("teoria.reader.justify") private var justify = false
    @AppStorage("teoria.reader.markColor") private var markColor = 1

    @State private var layout: BookLayout?
    @State private var visible: [Int] = []       // page indices shown in this mode (cached)
    @State private var current = 0              // index into `visible`
    @State private var chrome = true
    @State private var showTOC = false
    @State private var showSettings = false
    @State private var showVoice = false
    @State private var showSearch = false
    @State private var tapped: BookHighlight?
    @State private var recall: Isaret?
    @State private var redraw = 0                // bumps after an in-place mark so pages repaint
    @State private var toast: (String, TeoriaMark?)?
    @State private var query = ""
    @State private var hits: [SearchHit] = []
    @State private var hitIndex: Int?
    @State private var spreadStep = 1

    private var theme: ReaderTheme { ReaderTheme(rawValue: themeRaw) ?? .paper }
    private var style: ReaderStyle { ReaderStyle(size: CGFloat(size), theme: theme, justify: justify) }
    private var insight: BookInsight? { library.insights[book.id] }
    private var hidden: Set<String> { hideRepeats ? (insight?.dropped ?? []) : [] }
    private var positionKey: String { "teoria.reader.pos.\(book.id)" }
    private var listeningHere: Bool { voice.speaking && voice.bookID == book.id }

    #if os(macOS)
    private let margins = EdgeInsets(top: 112, leading: 56, bottom: 76, trailing: 56)
    #else
    private let margins = EdgeInsets(top: 152, leading: 28, bottom: 108, trailing: 28)
    #endif

    var body: some View {
        // The whole screen, safe areas included: hiding the status bar must not change the page size
        // (a new size re-typesets the whole book — that was what swallowed taps).
        GeometryReader { geo in
            let spread = spreadCount(geo.size)
            let pageSize = CGSize(width: floor((geo.size.width - CGFloat(spread - 1) * 64) / CGFloat(spread) - margins.leading - margins.trailing),
                                  height: floor(geo.size.height - margins.top - margins.bottom))
            ZStack {
                theme.background
                if let layout, !visible.isEmpty {
                    pages(layout, pageSize: pageSize, spread: spread)
                } else if layout != nil {
                    emptyMarked
                } else {
                    VStack(spacing: 10) {
                        ProgressView().tint(Color(theme.muted))
                        Text("Sayfalar diziliyor…").font(.caption).foregroundStyle(Color(theme.muted))
                    }
                }
                overlayChrome
            }
            .task(id: LayoutKey(size: pageSize, style: style, hidden: hidden)) { await relayout(pageSize) }
        }
        .ignoresSafeArea()
        #if os(iOS)
        .statusBarHidden(!chrome)
        .persistentSystemOverlays(chrome ? .automatic : .hidden)
        #endif
        .preferredColorScheme(theme.isDark ? .dark : (theme == .paper ? nil : .light))
        .sheet(isPresented: $showTOC) { toc }
        .sheet(isPresented: $showSearch) { searchSheet }
        .sheet(item: $tapped) { h in highlightSheet(h) }
        .sheet(item: $recall) { RecallSayfasi(isaret: $0).environmentObject(depo) }
        .onChange(of: mode) { _, _ in refreshVisible() }
        .onChange(of: voice.live?.range.location) { _, _ in followVoice() }
        .onDisappear { if listeningHere { voice.stop() }; save() }
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 620)
        .onKeyPress(.rightArrow) { turn(+1); return .handled }
        .onKeyPress(.leftArrow) { turn(-1); return .handled }
        .onKeyPress(.space) { if listeningHere { voice.toggle() } else { turn(+1) }; return .handled }
        .onKeyPress(.escape) { dismiss(); return .handled }
        .focusable()
        .focusEffectDisabled()
        #endif
    }

    private struct LayoutKey: Equatable { let size: CGSize; let style: ReaderStyle; let hidden: Set<String> }

    private func spreadCount(_ s: CGSize) -> Int {
        #if os(macOS)
        return scrollMode ? 1 : (s.width > 1080 ? 2 : 1)
        #else
        return s.width > 900 && !scrollMode ? 2 : 1
        #endif
    }

    // MARK: layout

    private func relayout(_ size: CGSize) async {
        guard size.width > 120, size.height > 160 else { return }
        let keepOffset: Int = {
            if let layout, let i = visible[safe: current], let pg = layout.pages[safe: i] { return pg.start }
            return UserDefaults.standard.integer(forKey: positionKey)
        }()
        let b = library.withMarks(book), st = style, hid = hidden
        let new = await LayoutCache.shared.layout(book: b, style: st, size: size, hidden: hid)
        guard !Task.isCancelled else { return }
        layout = new
        refreshVisible(keepPage: nil)
        var target = new.page(forOffset: keepOffset)
        if let j = jump, layout?.size == size, !jumped { target = new.page(chapter: j.ch, block: j.b); jumped = true }
        current = visible.firstIndex(where: { $0 >= target }) ?? max(0, visible.count - 1)
    }
    @State private var jumped = false

    private func refreshVisible(keepPage: Int? = -1) {
        guard let layout else { visible = []; return }
        let here = keepPage == -1 ? visible[safe: current] : keepPage
        visible = mode == .full ? Array(0..<layout.pageCount) : layout.pages.indices.filter { !layout.pages[$0].highlightIDs.isEmpty }
        if let here {
            current = mode == .full ? min(here, max(0, visible.count - 1)) : (visible.firstIndex(where: { $0 >= here }) ?? max(0, visible.count - 1))
        }
        current = min(current, max(0, visible.count - 1))
    }

    private func save() {
        guard mode == .full, let layout, let i = visible[safe: current], let pg = layout.pages[safe: i] else { return }
        UserDefaults.standard.set(pg.start, forKey: positionKey)
    }

    private func turn(_ d: Int) {
        let step = scrollMode ? 1 : spreadStep
        let n = max(0, min(visible.count - 1, current + d * step))
        guard n != current else { return }
        Dokunus.hafif(0.3)
        withAnimation(.easeInOut(duration: 0.25)) { current = n }
        save()
    }

    private func go(page p: Int) {
        if mode == .marked, !visible.contains(p) { mode = .full; refreshVisible(keepPage: p) }
        if let i = visible.firstIndex(of: p) { current = i } else { current = min(p, max(0, visible.count - 1)) }
        save()
    }

    /// Transient mark for the page: the sentence being read aloud wins over a search hit.
    private var live: LiveMark? {
        guard let layout else { return nil }
        if listeningHere, let s = voice.currentSentence(), let r = layout.range(chapter: s.ch, block: s.b, s: s.s, e: s.e) {
            var mark = LiveMark(chapter: s.ch, range: r, kind: .speech)
            if let l = voice.live, l.ch == s.ch, l.b == s.b {
                mark.word = layout.range(chapter: l.ch, block: l.b, s: l.range.location, e: NSMaxRange(l.range))
            }
            return mark
        }
        if let i = hitIndex, let h = hits[safe: i], let r = layout.range(chapter: h.ch, block: h.b, s: h.range.location, e: NSMaxRange(h.range)) {
            return LiveMark(chapter: h.ch, range: r, kind: .search)
        }
        return nil
    }

    private func findHighlight(_ id: String) -> BookHighlight? {
        book.highlights.first { $0.id == id } ?? library.mark(id)?.highlight
    }

    // MARK: pages

    @ViewBuilder
    private func pages(_ layout: BookLayout, pageSize: CGSize, spread: Int) -> some View {
        let vis = visible
        let lv = live
        if scrollMode {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(vis.enumerated()), id: \.element) { n, i in
                            page(layout, i, pageSize, live: lv)
                                .padding(.horizontal, margins.leading)
                                .padding(.vertical, 18)
                                .id(n)
                                .onAppear { current = n }
                            Rectangle().fill(Color(theme.muted).opacity(0.14)).frame(height: 0.5).padding(.horizontal, 40)
                        }
                    }
                    .padding(.top, margins.top).padding(.bottom, margins.bottom)
                }
                .onAppear { proxy.scrollTo(current, anchor: .top) }
                .onChange(of: current) { _, c in if listeningHere || hitIndex != nil { withAnimation { proxy.scrollTo(c, anchor: .top) } } }
            }
        } else {
            #if os(iOS)
            CurlPager(count: vis.count, current: $current, background: PColor(theme.background), revision: redraw, chromeVisible: chrome,
                      chromeTop: margins.top - 14, chromeBottom: margins.bottom - 20,
                      onTurn: { save(); Dokunus.hafif(0.25) },
                      tapCenter: { p in centerTap(layout, vis[safe: current], p) },
                      longPress: { p in markAt(layout, vis[safe: current], CGPoint(x: p.x - margins.leading, y: p.y - margins.top)) }) { n in
                if let i = vis[safe: n] {
                    AnyView(page(layout, i, pageSize, live: lv).padding(margins))
                } else {
                    AnyView(Color.clear)
                }
            }
            .onAppear { spreadStep = spread }
            #else
            HStack(spacing: 64) {
                ForEach(0..<spread, id: \.self) { k in
                    if let i = vis[safe: current + k] {
                        page(layout, i, pageSize, live: lv)
                            .contentShape(Rectangle())
                            .gesture(SpatialTapGesture(count: 2).onEnded { v in markAt(layout, i, v.location) })
                            .simultaneousGesture(SpatialTapGesture(count: 1).onEnded { v in
                                if let id = layout.highlight(at: v.location, page: i), let h = findHighlight(id) { tapped = h }
                                else { turn(k == 0 && spread == 2 ? -1 : +1) }
                            })
                    } else {
                        Color.clear.frame(width: pageSize.width, height: pageSize.height)
                    }
                }
            }
            .padding(margins)
            .id(current)
            .transition(.opacity)
            .onAppear { spreadStep = spread }
            .onChange(of: spread) { _, s in spreadStep = s }
            #endif
        }
    }

    private func page(_ layout: BookLayout, _ i: Int, _ size: CGSize, live: LiveMark?) -> some View {
        let pg = layout.pages[safe: i]
        return PageCanvas(layout: layout, index: i, inset: .zero, live: live, revision: redraw)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .overlay(alignment: .top) {
                if mode == .marked, let pg {
                    HStack(spacing: 6) {
                        Image(systemName: "highlighter")
                        Text(book.chapters[safe: pg.chapter]?.title ?? "").lineLimit(1)
                        Spacer()
                        Text("s. \(i + 1)").monospacedDigit()
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(theme.muted))
                    .offset(y: -28)
                }
            }
    }

    #if os(iOS)
    private func centerTap(_ layout: BookLayout, _ i: Int?, _ p: CGPoint) {
        let local = CGPoint(x: p.x - margins.leading, y: p.y - margins.top)
        if let i, let id = layout.highlight(at: local, page: i), let h = findHighlight(id) {
            Dokunus.secim(); tapped = h
        } else {
            withAnimation(.easeOut(duration: 0.15)) { chrome.toggle() }
        }
    }
    #endif

    // MARK: marking

    /// Press and hold (iPhone) / double-click (Mac) a sentence: it becomes a highlight in the current colour.
    private func markAt(_ layout: BookLayout, _ i: Int?, _ point: CGPoint) {
        guard let i, let spot = layout.spot(at: point, page: i), let blk = book.chapters[safe: spot.ch]?.blocks[safe: spot.b], !blk.isHeading else { return }
        let (a, z) = Self.sentence(blk.x, at: spot.off)
        addMark(layout, ch: spot.ch, b: spot.b, s: a, e: z, text: blk.x)
    }

    private func addMark(_ layout: BookLayout, ch: Int, b: Int, s: Int, e: Int, text: String) {
        let ns = text as NSString
        guard e > s, e <= ns.length else { return }
        let q = ns.substring(with: NSRange(location: s, length: e - s)).trimmingCharacters(in: .whitespaces)
        let m = library.addMark(book: book.id, ch: ch, b: b, s: s, e: e, quote: q, color: markColor)
        layout.apply(m.highlight)
        redraw += 1
        Dokunus.basari()
        withAnimation(.snappy) { toast = ("İşaretlendi", m) }
        Task { try? await Task.sleep(nanoseconds: 5_000_000_000); if toast?.1?.id == m.id { withAnimation { toast = nil } } }
        LibraryStore.shared.scheduleSync(depo.kasa)
    }

    private func undo(_ m: TeoriaMark) {
        library.deleteMark(m)
        layout?.remove(m.id)
        redraw += 1
        withAnimation { toast = nil }
        LibraryStore.shared.scheduleSync(depo.kasa)
    }

    static func sentence(_ text: String, at i: Int) -> (Int, Int) {
        let ns = text as NSString
        let enders: Set<unichar> = [46, 33, 63, 8230]
        var a = min(max(0, i), ns.length)
        while a > 0, !enders.contains(ns.character(at: a - 1)) { a -= 1 }
        while a < ns.length, ns.character(at: a) == 32 { a += 1 }
        var z = min(max(a, i), ns.length)
        while z < ns.length { let c = ns.character(at: z); z += 1; if enders.contains(c) { break } }
        return (a, z)
    }

    // MARK: listening

    private func listenFromHere() {
        guard let layout, let i = visible[safe: current], let pg = layout.pages[safe: i] else { return }
        if mode == .marked { mode = .full; refreshVisible(keepPage: i) }
        var blocks: [SpokenBlock] = []
        var startIndex = 0, startOff = 0
        for (ci, ch) in book.chapters.enumerated() {
            let starts = layout.blockStarts[safe: ci] ?? [:]
            for bi in starts.keys.sorted() {
                guard let blk = ch.blocks[safe: bi], let (st, len) = starts[bi] else { continue }
                if ci < pg.chapter || (ci == pg.chapter && st + len <= pg.range.location) { startIndex = blocks.count + 1 }
                if ci == pg.chapter, st < pg.range.location, st + len > pg.range.location {
                    startIndex = blocks.count; startOff = pg.range.location - st
                }
                blocks.append(SpokenBlock(ch: ci, b: bi, text: blk.x))
            }
        }
        let off = startOff > 0 ? Self.sentence(blocks[safe: startIndex]?.text ?? "", at: startOff).0 : 0
        voice.play(book: book.id, title: book.title, blocks: blocks, from: startIndex, offset: off)
    }

    private func followVoice() {
        guard listeningHere, let layout, let l = voice.live, let r = layout.range(chapter: l.ch, block: l.b, s: l.range.location, e: l.range.location) else { return }
        let p = layout.page(chapter: l.ch, local: r.location)
        if mode == .marked { mode = .full; refreshVisible(keepPage: p) }
        if visible[safe: current] != p, let i = visible.firstIndex(of: p) { current = i; save() }
    }

    private func markListening() {
        guard let layout, let s = voice.currentSentence() else { return }
        guard let text = book.chapters[safe: s.ch]?.blocks[safe: s.b]?.x else { return }
        addMark(layout, ch: s.ch, b: s.b, s: s.s, e: s.e, text: text)
    }

    // MARK: search

    private func runSearch(_ q: String) {
        let needle = q.trimmingCharacters(in: .whitespaces)
        guard needle.count >= 2 else { hits = []; return }
        var out: [SearchHit] = []
        outer: for (ci, ch) in book.chapters.enumerated() {
            for (bi, blk) in ch.blocks.enumerated() {
                let ns = blk.x as NSString
                var from = 0
                while from < ns.length {
                    let r = ns.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: NSRange(location: from, length: ns.length - from), locale: Dil.tr)
                    if r.location == NSNotFound { break }
                    let a = max(0, r.location - 50), z = min(ns.length, NSMaxRange(r) + 70)
                    out.append(SearchHit(ch: ci, b: bi, range: r,
                                         before: (a > 0 ? "…" : "") + ns.substring(with: NSRange(location: a, length: r.location - a)),
                                         match: ns.substring(with: r),
                                         after: ns.substring(with: NSRange(location: NSMaxRange(r), length: z - NSMaxRange(r))) + (z < ns.length ? "…" : "")))
                    if out.count >= 500 { break outer }
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

    private var searchSheet: some View {
        NavigationStack {
            List {
                if hits.isEmpty {
                    Text(query.count < 2 ? "En az iki harf yaz. Büyük/küçük harf ve şapka fark etmez." : "Bu kitapta bulunamadı.")
                        .foregroundStyle(.secondary)
                } else {
                    Section("\(hits.count >= 500 ? "500+" : "\(hits.count)") sonuç") {
                        ForEach(Array(hits.enumerated()), id: \.element.id) { n, h in
                            Button { openHit(n); showSearch = false } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(book.chapters[safe: h.ch]?.title ?? "").font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                                        Spacer()
                                        if let layout { Text("s. \(layout.page(chapter: h.ch, block: h.b, offset: h.range.location) + 1)").font(.caption).monospacedDigit().foregroundStyle(.secondary) }
                                    }
                                    (Text(h.before) + Text(h.match).bold().foregroundColor(Tema.uyari) + Text(h.after))
                                        .font(.system(.callout, design: .serif)).foregroundStyle(Tema.metin).lineLimit(3)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .searchable(text: $query, isPresented: $searchActive, placement: .automatic, prompt: "Kitapta ara")
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { searchActive = true } }
            .onSubmit(of: .search) { runSearch(query) }
            .onChange(of: query) { _, q in
                searchTask?.cancel()
                searchTask = Task { try? await Task.sleep(nanoseconds: 250_000_000); if !Task.isCancelled { runSearch(q) } }
            }
            .navigationTitle("Ara")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { showSearch = false } } }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #endif
    }
    @State private var searchTask: Task<Void, Never>?
    @State private var searchActive = false

    private var emptyMarked: some View {
        VStack(spacing: 12) {
            Image(systemName: "highlighter").font(.system(size: 34)).foregroundStyle(Color(theme.muted))
            Text("Bu kitapta işaret yok.").font(.system(.title3, design: .serif)).foregroundStyle(Color(theme.ink))
            Text("Bir cümleye basılı tutarak işaretleyebilirsin.").font(.footnote).foregroundStyle(Color(theme.muted))
            Button("Tam metni aç") { mode = .full }.buttonStyle(.borderedProminent)
        }
    }

    // MARK: chrome

    /// A 44-point target around every symbol: the whole square answers, not only the glyph.
    private func barButton(_ symbol: String, _ label: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: { Dokunus.secim(); action() }) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(active ? Color(theme.accent) : Color(theme.ink))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var overlayChrome: some View {
        let pg = layout.flatMap { l in visible[safe: current].flatMap { l.pages[safe: $0] } }
        return VStack(spacing: 0) {
            ZStack(alignment: .top) {
                VStack(spacing: 8) {
                    HStack(spacing: 2) {
                        barButton("xmark", "Kapat") { save(); dismiss() }
                        barButton("list.bullet", "İçindekiler") { showTOC = true }
                        Spacer(minLength: 0)
                        barButton("magnifyingglass", "Ara", active: hitIndex != nil) { showSearch = true }
                        barButton(listeningHere ? "headphones.circle.fill" : "headphones", "Dinle", active: listeningHere) {
                            if listeningHere { showVoice = true } else { listenFromHere() }
                        }
                        .popover(isPresented: $showVoice) { voiceSettings }
                        Button { Dokunus.secim(); showSettings = true } label: {
                            Text("Aa").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color(theme.ink))
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showSettings) { settings }
                    }
                    modePicker
                }
                .padding(.horizontal, 10)
                #if os(iOS)
                .padding(.top, 50)
                #else
                .padding(.top, 14)
                #endif
                .padding(.bottom, 8)
                .background(theme.background.opacity(0.94))
                // always laid out, only faded: a bar sliding in cannot catch taps, a faded-in one can
                .opacity(chrome ? 1 : 0)
                .allowsHitTesting(chrome)
                if !chrome, let pg {
                    Text(book.chapters[safe: pg.chapter]?.title ?? "").lineLimit(1).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(theme.muted)).padding(.horizontal, 60)
                        #if os(iOS)
                        .padding(.top, 62)
                        #else
                        .padding(.top, 20)
                        #endif
                        .allowsHitTesting(false)
                }
            }
            Spacer(minLength: 0)
            if let h = hitIndex, !showSearch, hits.count > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass").font(.caption)
                    Text("“\(query)” \(h + 1)/\(hits.count)").font(.caption.weight(.semibold)).lineLimit(1)
                    barButton("chevron.up", "Önceki") { openHit((h - 1 + hits.count) % hits.count) }
                    barButton("chevron.down", "Sonraki") { openHit((h + 1) % hits.count) }
                    barButton("xmark.circle.fill", "Aramayı kapat") { hitIndex = nil }
                }
                .padding(.leading, 12)
                .background(Capsule().fill(.ultraThinMaterial))
                .padding(.bottom, 8)
            }
            if let t = toast {
                HStack(spacing: 12) {
                    Image(systemName: "highlighter").foregroundStyle(Marker.swatch(markColor))
                    Text(t.0).font(.callout.weight(.semibold))
                    if let m = t.1 { Button("Geri al") { undo(m) }.font(.callout.weight(.semibold)) }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Capsule().fill(.regularMaterial))
                .padding(.bottom, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if listeningHere { playerBar } else { footer(pg) }
        }
    }

    @ViewBuilder
    private func footer(_ pg: BookPage?) -> some View {
        if let layout, let pg, let i = visible[safe: current] {
            VStack(spacing: 6) {
                if chrome && !scrollMode && visible.count > 1 {
                    Slider(value: Binding(get: { Double(current) }, set: { current = Int($0.rounded()) }),
                           in: 0...Double(max(visible.count - 1, 1)), onEditingChanged: { if !$0 { save() } })
                        .tint(Color(theme.accent)).frame(maxWidth: 520)
                }
                HStack {
                    if mode == .marked {
                        Text("İşaretli sayfa \(current + 1) / \(visible.count)")
                        Spacer()
                        Button { go(page: i); mode = .full; refreshVisible(keepPage: i) } label: {
                            Label("Sayfada aç", systemImage: "book.pages").padding(.vertical, 10).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).foregroundStyle(Color(theme.accent))
                    } else {
                        Text("\(i + 1) / \(layout.pageCount)")
                        Spacer()
                        let next = layout.chapterFirstPage[safe: pg.chapter + 1] ?? layout.pageCount
                        let left = next - i - 1
                        Text(left == 0 ? "bölümün son sayfası" : "bölümde \(left) sayfa kaldı")
                    }
                }
                .font(.system(size: 11.5, weight: .medium)).monospacedDigit()
                .foregroundStyle(Color(theme.muted))
                .frame(maxWidth: 560)
            }
            .padding(.horizontal, 26)
            #if os(iOS)
            .padding(.bottom, 30)
            #else
            .padding(.bottom, 16)
            #endif
        }
    }

    private var playerBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                barButton("backward.end.fill", "Önceki paragraf") { voice.skip(-1) }
                Button { Dokunus.secim(); voice.toggle() } label: {
                    Image(systemName: voice.paused ? "play.circle.fill" : "pause.circle.fill")
                        .font(.system(size: 40)).foregroundStyle(Color(theme.accent))
                        .frame(width: 56, height: 56).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel(voice.paused ? "Sürdür" : "Duraklat")
                barButton("forward.end.fill", "Sonraki paragraf") { voice.skip(1) }
                Menu {
                    Picker("Hız", selection: $voice.speed) {
                        ForEach(ReaderVoice.speeds, id: \.self) { m in Text(ReaderVoice.speedName(m)).tag(m) }
                    }
                } label: {
                    Text(ReaderVoice.speedName(voice.speed))
                        .font(.callout.weight(.bold)).monospacedDigit().fixedSize()
                        .foregroundStyle(Color(theme.ink))
                        .frame(minWidth: 48, minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Hız \(ReaderVoice.speedName(voice.speed))")
                Spacer(minLength: 4)
                Menu {
                    ForEach(IsaretRengi.allCases) { r in
                        Button { markColor = r.rawValue } label: { Label(r.ad, systemImage: markColor == r.rawValue ? "checkmark.circle.fill" : "circle") }
                    }
                } label: {
                    Circle().fill(Marker.swatch(markColor)).frame(width: 20, height: 20)
                        .frame(width: 32, height: 44).contentShape(Rectangle())
                }
                Button { markListening() } label: {
                    ViewThatFits(in: .horizontal) {
                        Label("İşaretle", systemImage: "highlighter").fixedSize().padding(.horizontal, 12)
                        Image(systemName: "highlighter").padding(.horizontal, 12)
                    }
                    .font(.callout.weight(.semibold)).frame(height: 40)
                    .background(Capsule().fill(Color(theme.accent).opacity(0.15)))
                    .foregroundStyle(Color(theme.accent)).contentShape(Capsule())
                }
                .accessibilityLabel("İşaretle")
                .buttonStyle(.plain)
                barButton("stop.fill", "Dinlemeyi bitir") { voice.stop() }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.regularMaterial))
        .padding(.horizontal, 10)
        #if os(iOS)
        .padding(.bottom, 26)
        #else
        .padding(.bottom, 12)
        #endif
    }

    private var voiceSettings: some View {
        let voices = ReaderVoice.voices
        return VStack(alignment: .leading, spacing: 16) {
            Text("Dinleme").font(.headline)
            if voices.isEmpty {
                Text("Bu cihazda Türkçe ses yok. Ayarlar › Erişilebilirlik › Seslendirilen İçerik › Sesler › Türkçe'den indir.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Picker("Ses", selection: $voice.voiceID) {
                    ForEach(voices, id: \.identifier) { v in Text("\(v.name) · \(ReaderVoice.qualityName(v))").tag(v.identifier) }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Hız"); Spacer()
                    Text(ReaderVoice.speedName(voice.speed)).font(.body.weight(.semibold)).monospacedDigit()
                }
                Slider(value: $voice.speed, in: 1...3.5, step: 0.25) {
                    Text("Hız")
                } minimumValueLabel: { Text("1×").font(.caption) } maximumValueLabel: { Text("3,5×").font(.caption) }
                HStack(spacing: 6) {
                    ForEach([1.0, 1.5, 2.0, 2.5, 3.0, 3.5], id: \.self) { m in
                        Button(ReaderVoice.speedName(m)) { voice.speed = m }
                            .font(.caption.weight(.medium)).monospacedDigit()
                            .buttonStyle(.bordered).controlSize(.small)
                            .tint(voice.speed == m ? .accentColor : .secondary)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack { Text("Ton"); Spacer(); Text(voice.pitch < 0.95 ? "kalın" : (voice.pitch > 1.05 ? "ince" : "doğal")).foregroundStyle(.secondary) }
                Slider(value: $voice.pitch, in: 0.6...1.4) {
                    Text("Ton")
                } minimumValueLabel: { Image(systemName: "speaker.wave.1") } maximumValueLabel: { Image(systemName: "speaker.wave.3") }
                Text("Sola çektikçe ses kalınlaşır.").font(.caption).foregroundStyle(.secondary)
            }
            Text("Daha doğal bir ses için Ayarlar › Erişilebilirlik › Seslendirilen İçerik › Sesler'den Türkçe Gelişmiş/Premium sesi indir.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 320)
        .presentationCompactAdaptation(.popover)
    }

    private var modePicker: some View {
        Picker("", selection: Binding(get: { mode }, set: { m in switchMode(m) })) {
            Label("Tam metin", systemImage: "book").tag(ReaderMode.full)
            Label("İşaretler", systemImage: "highlighter").tag(ReaderMode.marked)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 300)
    }

    private func switchMode(_ m: ReaderMode) {
        guard m != mode else { return }
        let here = visible[safe: current]
        mode = m
        refreshVisible(keepPage: here)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button { size = max(14, size - 1) } label: { Text("A").font(.system(size: 14)).frame(width: 44, height: 32) }
                Spacer()
                Text("\(Int(size)) pt").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Button { size = min(30, size + 1) } label: { Text("A").font(.system(size: 22)).frame(width: 44, height: 32) }
            }
            .buttonStyle(.bordered)
            HStack(spacing: 10) {
                ForEach(ReaderTheme.allCases) { t in
                    Button { themeRaw = t.rawValue } label: {
                        Text(t.name).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(t.ink))
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 10).fill(t.background))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(themeRaw == t.rawValue ? Color(t.accent) : .gray.opacity(0.3), lineWidth: themeRaw == t.rawValue ? 2 : 1))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            Toggle("Kaydırarak oku", isOn: $scrollMode)
            Toggle("İki yana yasla", isOn: $justify)
            if insight?.drop?.isEmpty == false {
                Toggle("Tekrarları gizle", isOn: $hideRepeats)
            }
            Picker("İşaret rengi", selection: $markColor) {
                ForEach(IsaretRengi.allCases) { r in Text(r.ad).tag(r.rawValue) }
            }
            Text(book.claude ? "Okuma baskısı: sayılar rakamla, okunuş notları ve sesli tekrarlar çıkarıldı." : "Özgün metin.")
                .font(.caption).foregroundStyle(.secondary)
            Text("İşaretlemek için bir cümleye basılı tut (Mac'te çift tıkla).").font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 310)
        .presentationCompactAdaptation(.popover)
    }

    // MARK: table of contents

    private var toc: some View {
        NavigationStack {
            List {
                let cur = layout.flatMap { l in visible[safe: current].flatMap { l.pages[safe: $0]?.chapter } }
                let all = library.withMarks(book).highlights
                ForEach(Array(book.chapters.enumerated()), id: \.offset) { ci, ch in
                    if let p = ch.part, ci == 0 || book.chapters[ci - 1].part != p {
                        Text(p.uppercased(with: Dil.tr)).font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary).listRowSeparator(.hidden)
                            .padding(.top, 6)
                    }
                    Button {
                        if let layout, let target = layout.chapterFirstPage[safe: ci] { go(page: target) }
                        showTOC = false
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ch.title).font(.system(.body, design: .serif).weight(cur == ci ? .bold : .regular))
                                    .foregroundStyle(cur == ci ? Tema.vurgu : Tema.metin)
                                if let s = insight?.summary(ci)?.key { Text(s).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                            }
                            Spacer()
                            let n = all.filter { $0.at.contains { $0.ch == ci } }.count
                            if n > 0 { Label("\(n)", systemImage: "highlighter").font(.caption2).foregroundStyle(Marker.swatch(1)) }
                            if let layout, let fp = layout.chapterFirstPage[safe: ci] { Text("\(fp + 1)").font(.caption).monospacedDigit().foregroundStyle(.secondary) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("İçindekiler")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { showTOC = false } } }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 560)
        #endif
    }

    // MARK: a highlight

    private func highlightSheet(_ h: BookHighlight) -> some View {
        let akis = matchingAkis(h)
        let own = library.mark(h.id)
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        Circle().fill(Marker.swatch(h.color)).frame(width: 10, height: 10)
                        Text(IsaretRengi(rawValue: h.color)?.ad ?? "işaret").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(own != nil ? "· Teoria'da" : "· Voice Dream").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if h.time != .distantPast { Text(Tarih.kisa(h.time)).font(.caption).foregroundStyle(.secondary) }
                    }
                    Text(h.quote).font(.system(.title3, design: .serif)).lineSpacing(4).textSelection(.enabled)
                    if let n = h.note { Label(n, systemImage: "note.text").font(.callout).foregroundStyle(.secondary) }
                    if let ch = h.at.first?.ch, let s = insight?.summary(ch) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("BÖLÜMÜN ÖZÜ").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                            Text(s.summary).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    Button {
                        let i = akis ?? Isaret(id: "kitap:\(book.id):\(h.id)", kitap: book.id, baslik: book.title, metin: h.quote,
                                               renk: h.color, tarih: h.date ?? Tarih.gun(Date()), kaynak: "kitap", baglam: nil)
                        tapped = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { recall = i }
                    } label: { Label("Kapat · hatırla · yeniden kur", systemImage: "brain.head.profile") }
                        .buttonStyle(.borderedProminent)
                    if let a = akis {
                        HStack {
                            Button { depo.favori(a.id) } label: {
                                Label("Favori", systemImage: depo.durum.favoriler.contains(a.id) ? "heart.fill" : "heart")
                            }
                            Button { depo.hatirlat(a.id) } label: {
                                Label("Tekrar havuzu", systemImage: depo.durum.hatirlatmalar.contains(a.id) ? "bell.fill" : "bell")
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    if let own {
                        Button(role: .destructive) { tapped = nil; undo(own) } label: { Label("İşareti sil", systemImage: "trash") }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(22)
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { tapped = nil } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func matchingAkis(_ h: BookHighlight) -> Isaret? {
        let q = String(Dil.normal(h.quote).prefix(50))
        return depo.akis.isaretler.first { $0.kitap == book.id && Dil.normal($0.metin).hasPrefix(q) }
            ?? depo.akis.isaretler.first { Dil.normal($0.metin).hasPrefix(q) }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// The last few typeset books, so reopening a book (or coming back from another screen) is instant.
actor LayoutCache {
    static let shared = LayoutCache()
    private struct Key: Hashable { let id: String; let w: Int; let h: Int; let size: Int; let theme: String; let justify: Bool; let hidden: Set<String>; let marks: Int }
    private var items: [(Key, BookLayout)] = []

    func layout(book: Book, style: ReaderStyle, size: CGSize, hidden: Set<String>) -> BookLayout {
        let k = Key(id: book.id, w: Int(size.width), h: Int(size.height), size: Int(style.size), theme: style.theme.rawValue,
                    justify: style.justify, hidden: hidden, marks: book.highlights.count)
        if let hit = items.first(where: { $0.0 == k }) { return hit.1 }
        let l = BookLayout(book: book, style: style, size: size, hidden: hidden)
        items.removeAll { $0.0.id == book.id && $0.0.marks != k.marks }   // stale highlight set
        items.append((k, l))
        if items.count > 3 { items.removeFirst() }
        return l
    }
}

// MARK: - iPhone page curl

#if os(iOS)
struct CurlPager: UIViewControllerRepresentable {
    let count: Int
    @Binding var current: Int
    let background: UIColor
    var revision: Int
    var chromeVisible: Bool
    var chromeTop: CGFloat
    var chromeBottom: CGFloat
    var onTurn: () -> Void
    var tapCenter: (CGPoint) -> Void
    var longPress: (CGPoint) -> Void
    let content: (Int) -> AnyView

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pv = UIPageViewController(transitionStyle: .pageCurl, navigationOrientation: .horizontal,
                                      options: [.spineLocation: UIPageViewController.SpineLocation.min.rawValue])
        pv.isDoubleSided = false
        pv.dataSource = context.coordinator
        pv.delegate = context.coordinator
        // the pager's own edge taps are replaced: edges turn, the middle shows the toolbar or opens a highlight
        for g in pv.gestureRecognizers where g is UITapGestureRecognizer { g.isEnabled = false }
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.delegate = context.coordinator
        pv.view.addGestureRecognizer(tap)
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.held(_:)))
        hold.minimumPressDuration = 0.45
        hold.delegate = context.coordinator
        pv.view.addGestureRecognizer(hold)
        pv.view.backgroundColor = background
        context.coordinator.lastCount = count
        pv.setViewControllers([context.coordinator.page(min(current, max(0, count - 1)))], direction: .forward, animated: false)
        return pv
    }

    func updateUIViewController(_ pv: UIPageViewController, context: Context) {
        let c = context.coordinator
        c.parent = self
        pv.view.backgroundColor = background
        let target = min(current, max(0, count - 1))
        let shown = (pv.viewControllers?.first as? Page)?.index
        let countChanged = c.lastCount != count
        c.lastCount = count
        if shown != target || countChanged {
            guard !c.turning else { return }          // a curl in flight finishes first; it reports its own page
            let dir: UIPageViewController.NavigationDirection = (shown ?? 0) <= target ? .forward : .reverse
            let animate = !countChanged && shown != nil && abs((shown ?? 0) - target) == 1
            pv.setViewControllers([c.page(target)], direction: dir, animated: animate)
        } else if let p = pv.viewControllers?.first as? Page {
            p.host.rootView = content(target); p.view.backgroundColor = background
        }
    }

    final class Page: UIViewController {
        let index: Int
        let host: UIHostingController<AnyView>
        init(index: Int, view v: AnyView, background: UIColor) {
            self.index = index
            host = UIHostingController(rootView: v)
            super.init(nibName: nil, bundle: nil)
            view.backgroundColor = background
            host.view.backgroundColor = .clear
            host.safeAreaRegions = []
            addChild(host)
            host.view.frame = view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(host.view)
            host.didMove(toParent: self)
        }
        required init?(coder: NSCoder) { fatalError() }
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIGestureRecognizerDelegate {
        var parent: CurlPager
        var lastCount = 0
        var turning = false
        init(_ p: CurlPager) { parent = p }

        func page(_ i: Int) -> Page { Page(index: i, view: parent.content(i), background: parent.background) }

        func pageViewController(_ pv: UIPageViewController, viewControllerBefore vc: UIViewController) -> UIViewController? {
            guard let i = (vc as? Page)?.index, i > 0, i - 1 < parent.count else { return nil }
            return page(i - 1)
        }
        func pageViewController(_ pv: UIPageViewController, viewControllerAfter vc: UIViewController) -> UIViewController? {
            guard let i = (vc as? Page)?.index, i + 1 < parent.count else { return nil }
            return page(i + 1)
        }
        func pageViewController(_ pv: UIPageViewController, willTransitionTo pending: [UIViewController]) { turning = true }
        func pageViewController(_ pv: UIPageViewController, didFinishAnimating f: Bool, previousViewControllers: [UIViewController], transitionCompleted ok: Bool) {
            turning = false
            guard ok, let i = (pv.viewControllers?.first as? Page)?.index else { return }
            parent.current = i
            parent.onTurn()
        }
        /// Touches in the toolbar and footer bands belong to the buttons there, never to the page.
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive t: UITouch) -> Bool {
            guard let v = g.view, parent.chromeVisible else { return true }
            let y = t.location(in: v).y
            return y > parent.chromeTop && y < v.bounds.height - parent.chromeBottom
        }
        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard let v = g.view else { return }
            let p = g.location(in: v)
            let w = v.bounds.width
            if p.x < w * 0.2, parent.current > 0 { parent.current -= 1; parent.onTurn() }
            else if p.x > w * 0.8, parent.current + 1 < parent.count { parent.current += 1; parent.onTurn() }
            else { parent.tapCenter(p) }
        }
        @objc func held(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let v = g.view else { return }
            parent.longPress(g.location(in: v))
        }
    }
}
#endif
