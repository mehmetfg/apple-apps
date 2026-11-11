// Search (2026-11-08): a sentence anywhere in the library, an expression inside one book.
//
//   Mac     veri/search_corpus.py (run by library.py) writes library/search/<id>.z: each book's text as raw-DEFLATE
//           lines, "#" + the chapter titles joined with U+001F, then "<chapter>\t<block>\t<text>" per paragraph
//   iPhone  the library sync copies the files to bookshelf/search/ (by size and date, apart from the main sync)
//   both    LibrarySearch scans them off the main thread, the books read most recently first, and shows each book's
//           places as they are found; a book whose file has not arrived is searched in its downloaded text instead.
//           The reader, the book page and the Mac's reading room search one book with the same matcher.
//
// Matching ignores case, accents and the dotted/dotless i (Fold): "gazali" finds "Gazâlî", "ISIK" finds "ışık".
// Measured on the Mac (210 books, 55 MB of text): about one second for the whole library, most of it unpacking.
import SwiftUI

// MARK: - Matcher

enum Fold {
    /// Every UTF-16 unit mapped to exactly one folded unit, so an offset in the folded text is the offset in the original.
    static let table: [UInt16] = {
        var t = (0..<65536).map { UInt16($0) }
        func fold(_ r: ClosedRange<Int>) {
            for i in r {
                guard let s = Unicode.Scalar(UInt32(i)) else { continue }
                let f = Array(String(Character(s)).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil).utf16)
                if f.count == 1 { t[i] = f[0] }
            }
        }
        fold(0x41...0x5A); fold(0xC0...0x24F); fold(0x370...0x52F); fold(0x1E00...0x1FFF)
        for (a, b) in [("İ", "i"), ("I", "i"), ("ı", "i"), ("’", "'"), ("‘", "'"), ("ʼ", "'"), ("“", "\""), ("”", "\""), ("\u{00A0}", " ")] {
            t[Int(a.utf16.first!)] = b.utf16.first!
        }
        return t
    }()

    static func units(_ s: String) -> [UInt16] { table.withUnsafeBufferPointer { t in s.utf16.map { t[Int($0)] } } }

    static func fold(_ s: String, into buf: inout [UInt16]) {
        buf.removeAll(keepingCapacity: true)
        table.withUnsafeBufferPointer { t in for u in s.utf16 { buf.append(t[Int(u)]) } }
    }

    /// Each place the needle starts in the folded text, in order, without overlaps; `each` returns false to stop.
    static func scan(_ needle: [UInt16], _ hay: UnsafeBufferPointer<UInt16>, _ each: (Int) -> Bool) {
        let m = needle.count
        guard m > 0, hay.count >= m else { return }
        needle.withUnsafeBufferPointer { nd in
            let first = nd[0], end = hay.count - m
            var i = 0
            while i <= end {
                if hay[i] == first {
                    var k = 1
                    while k < m && hay[i + k] == nd[k] { k += 1 }
                    if k == m {
                        if !each(i) { return }
                        i += m
                        continue
                    }
                }
                i += 1
            }
        }
    }
}

struct TextHit: Identifiable, Hashable, Sendable {
    let book: String
    let ch: Int
    let b: Int
    let at: Int             // UTF-16 offset of the match in the paragraph
    let length: Int
    let chapter: String
    let before: String
    let match: String
    let after: String
    var id: String { "\(book).\(ch).\(b).\(at)" }
    var searchHit: SearchHit { SearchHit(ch: ch, b: b, range: NSRange(location: at, length: length), before: before, match: match, after: after) }
}

enum TextSearch {
    struct Found: Sendable {
        var hits: [TextHit] = []
        var total = 0           // every place, also past the limit
    }

    static let minimum = 2

    static func needle(_ q: String) -> [UInt16]? {
        let t = q.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count >= minimum ? Fold.units(t) : nil
    }

    /// The paragraph around a match, cut at word boundaries.
    static func hit(book: String, ch: Int, b: Int, chapter: String, text ns: NSString, at: Int, length: Int) -> TextHit {
        var a = max(0, at - 60), z = min(ns.length, at + length + 90)
        if a > 0 {
            let r = ns.range(of: " ", options: [], range: NSRange(location: a, length: at - a))
            if r.location != NSNotFound { a = r.location + 1 }
        }
        if z < ns.length {
            let r = ns.range(of: " ", options: .backwards, range: NSRange(location: at + length, length: z - at - length))
            if r.location != NSNotFound { z = r.location }
        }
        let left = ns.rangeOfComposedCharacterSequences(for: NSRange(location: a, length: at - a))
        let right = ns.rangeOfComposedCharacterSequences(for: NSRange(location: at + length, length: z - at - length))
        let m = NSRange(location: at, length: min(length, ns.length - at))
        return TextHit(book: book, ch: ch, b: b, at: at, length: m.length, chapter: chapter,
                       before: (left.location > 0 ? "…" : "") + ns.substring(with: left),
                       match: ns.substring(with: m),
                       after: ns.substring(with: right) + (NSMaxRange(right) < ns.length ? "…" : ""))
    }

    /// Every match in a book's paragraphs, in reading order (reader, book page, Mac reading room).
    static func hits(in book: Book, _ query: String, limit: Int = 500) -> Found {
        guard let n = needle(query) else { return Found() }
        return hits(in: book, needle: n, limit: limit)
    }

    static func hits(in book: Book, needle: [UInt16], limit: Int) -> Found {
        var out = Found()
        var buf: [UInt16] = []
        for (ci, c) in book.chapters.enumerated() {
            for (bi, blk) in c.blocks.enumerated() {
                Fold.fold(blk.x, into: &buf)
                guard buf.count >= needle.count else { continue }
                var ns: NSString?
                buf.withUnsafeBufferPointer { h in
                    Fold.scan(needle, h) { i in
                        out.total += 1
                        if out.hits.count < limit {
                            let s = ns ?? (blk.x as NSString)
                            ns = s
                            out.hits.append(hit(book: book.id, ch: ci, b: bi, chapter: c.title, text: s, at: i, length: needle.count))
                        }
                        return true
                    }
                }
            }
        }
        return out
    }

    /// One book's search file (veri/search_corpus.py); nil when it cannot be read.
    static func scan(corpus data: Data, book: String, needle: [UInt16], limit: Int) -> Found? {
        guard let raw = try? (data as NSData).decompressed(using: .zlib) as Data else { return nil }
        let orig = Array(String(decoding: raw, as: UTF8.self).utf16)
        guard orig.first == 35 else { return nil }                       // "#" + chapter titles
        var folded = [UInt16]()
        folded.reserveCapacity(orig.count)
        Fold.table.withUnsafeBufferPointer { t in for u in orig { folded.append(t[Int(u)]) } }
        let headEnd = orig.firstIndex(of: 10) ?? orig.count
        let titles = String(decoding: orig[1..<headEnd], as: UTF16.self).components(separatedBy: "\u{1F}")
        var out = Found()
        folded.withUnsafeBufferPointer { h in
            Fold.scan(needle, h) { i in
                guard i > headEnd else { return true }
                var ls = i
                while ls > 0 && h[ls - 1] != 10 { ls -= 1 }
                var le = i
                while le < h.count && h[le] != 10 { le += 1 }
                // "<chapter>\t<block>\t"
                var p = ls, ch = 0, b = 0
                while p < le, h[p] >= 48, h[p] <= 57 { ch = ch * 10 + Int(h[p] - 48); p += 1 }
                guard p < le, h[p] == 9 else { return true }
                p += 1
                while p < le, h[p] >= 48, h[p] <= 57 { b = b * 10 + Int(h[p] - 48); p += 1 }
                guard p < le, h[p] == 9 else { return true }
                p += 1
                guard i >= p, i + needle.count <= le else { return true }
                out.total += 1
                if out.hits.count < limit {
                    let text = String(decoding: orig[p..<le], as: UTF16.self) as NSString
                    out.hits.append(hit(book: book, ch: ch, b: b, chapter: titles[safe: ch] ?? "", text: text, at: i - p, length: needle.count))
                }
                return true
            }
        }
        return out
    }

    /// A book's places: its search file if one has arrived, else its downloaded text; nil when neither is here.
    static func search(book id: String, needle: [UInt16], corpora: [URL], books: [URL], limit: Int) -> Found? {
        for d in corpora {
            if let data = try? Data(contentsOf: d.appendingPathComponent("\(id).z"), options: .mappedIfSafe),
               let r = scan(corpus: data, book: id, needle: needle, limit: limit) { return r }
        }
        for d in books {
            if let data = try? Data(contentsOf: d.appendingPathComponent("\(id).json")),
               let b = try? JSONDecoder().decode(Book.self, from: data) { return hits(in: b, needle: needle, limit: limit) }
        }
        return nil
    }
}

// MARK: - The whole library

@MainActor
final class LibrarySearch: ObservableObject {
    struct Result: Identifiable {
        let entry: LibraryEntry
        let hits: [TextHit]
        let total: Int
        var id: String { entry.id }
    }

    static let minimum = 3
    static let perBook = 12
    static let cap = 300                // places shown in all; past it the search stops and asks for a narrower phrase

    @Published private(set) var query = ""          // what the results below are for
    @Published private(set) var results: [Result] = []
    @Published private(set) var scanned = 0
    @Published private(set) var count = 0
    @Published private(set) var running = false
    @Published private(set) var absent = 0          // books whose text is not on this device yet
    @Published private(set) var capped = false
    private var task: Task<Void, Never>?

    var places: Int { results.reduce(0) { $0 + $1.total } }

    func search(_ q: String) {
        let t = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= Self.minimum else { cancel(); query = ""; results = []; scanned = 0; count = 0; absent = 0; capped = false; return }
        guard t != query else { return }
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(320))
            guard let self, !Task.isCancelled else { return }
            await self.run(t)
        }
    }

    func cancel() { task?.cancel(); task = nil; running = false }

    static var corpora: [URL] {
        var d = [Paylasim.kapsayici.appendingPathComponent("bookshelf/search", isDirectory: true)]
        #if os(macOS)
        d.insert(Kasa.macYolu.appendingPathComponent("library/search", isDirectory: true), at: 0)
        #endif
        return d
    }

    static var bookFiles: [URL] {
        var d = [Paylasim.kapsayici.appendingPathComponent("bookshelf/books", isDirectory: true)]
        #if os(macOS)
        d.append(Kasa.macYolu.appendingPathComponent("library/books", isDirectory: true))
        #endif
        return d
    }

    private func run(_ q: String) async {
        guard let needle = TextSearch.needle(q) else { return }
        let entries = LibraryStore.shared.index.books.sorted { $0.lastDate > $1.lastDate }
        let corpora = Self.corpora, books = Self.bookFiles
        query = q; results = []; scanned = 0; count = entries.count; absent = 0; capped = false; running = true
        var shown = 0
        for (n, e) in entries.enumerated() {
            if Task.isCancelled { return }
            let id = e.id, limit = min(Self.perBook, Self.cap - shown)
            let found = await Task.detached(priority: .userInitiated) {
                TextSearch.search(book: id, needle: needle, corpora: corpora, books: books, limit: limit)
            }.value
            if Task.isCancelled { return }
            if let found {
                if found.total > 0 {
                    results.append(Result(entry: e, hits: found.hits, total: found.total))
                    shown += found.hits.count
                }
            } else {
                absent += 1
            }
            if n % 6 == 5 || n == entries.count - 1 { scanned = n + 1 }
            if shown >= Self.cap { capped = true; scanned = n + 1; break }
        }
        running = false
    }
}

// MARK: - Views

/// A found place: the chapter, then the paragraph around the match with the match marked.
struct TextHitRow: View {
    let hit: TextHit
    var showChapter = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showChapter, !hit.chapter.isEmpty {
                Text(hit.chapter).font(.caption.weight(.semibold)).foregroundStyle(Tema.ikincil).lineLimit(1)
            }
            Text("\(Text(hit.before))\(Text(hit.match).bold().foregroundStyle(Tema.uyari))\(Text(hit.after))")
                .font(Tema.serif(.callout)).foregroundStyle(Tema.metin).lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// "Kitapların içinde": the books where the phrase occurs, the most recently read first, each with its first places.
struct SentenceResults: View {
    @ObservedObject var search: LibrarySearch
    var shown = 3
    let open: (TextHit) -> Void
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label("Kitapların içinde", systemImage: "text.magnifyingglass")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.ikincil)
                Spacer()
                if !search.results.isEmpty {
                    Text("\(search.places) yer · \(search.results.count) kitap").font(.caption).monospacedDigit().foregroundStyle(Tema.soluk)
                }
            }
            ForEach(search.results) { r in book(r) }
            status
        }
        .onChange(of: search.query) { _, _ in expanded = [] }
    }

    private func book(_ r: LibrarySearch.Result) -> some View {
        let open = expanded.contains(r.id)
        let list = open ? r.hits : Array(r.hits.prefix(shown))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(r.entry.titleParts.title).font(Tema.serif(.subheadline, .semibold)).foregroundStyle(Tema.metin).lineLimit(2)
                Spacer(minLength: 8)
                Text("\(r.total) yer").font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(Tema.kitap(r.entry.id))
            }
            ForEach(list) { h in
                Button { self.open(h) } label: { TextHitRow(hit: h) }.buttonStyle(.plain)
            }
            if !open, r.hits.count > shown {
                Button { expanded.insert(r.id) } label: {
                    Label("\(r.hits.count - shown) yer daha", systemImage: "chevron.down").font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain).foregroundStyle(Tema.kitap(r.entry.id))
            } else if r.total > r.hits.count, let last = r.hits.last {
                Button { self.open(last) } label: {
                    Label("Kalan \(r.total - r.hits.count) yeri kitapta gez", systemImage: "book").font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain).foregroundStyle(Tema.kitap(r.entry.id))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Tema.yuzey) }
    }

    @ViewBuilder
    private var status: some View {
        VStack(alignment: .leading, spacing: 6) {
            if search.running {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("\(search.scanned)/\(search.count) kitap tarandı").font(.caption).monospacedDigit().foregroundStyle(Tema.ikincil)
                }
            } else if !search.query.isEmpty, search.results.isEmpty {
                Text("“\(search.query)” hiçbir kitapta geçmiyor.").font(.subheadline).foregroundStyle(Tema.ikincil)
            }
            if search.capped {
                Text("İlk \(LibrarySearch.cap) yer gösteriliyor; daha dar bir ifadeyle ara.").font(.caption).foregroundStyle(Tema.soluk)
            }
            if search.absent > 0, !search.running {
                Text("\(search.absent) kitabın metni bu cihaza henüz inmedi; eşitlemeden sonra onlarda da aranır.")
                    .font(.caption).foregroundStyle(Tema.soluk)
            }
        }
    }
}

/// Kitaplar · Kütüphane: one field for a book's title and for a sentence inside any book.
struct LibrarySearchSheet: View {
    @EnvironmentObject var depo: Depo
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var library = LibraryStore.shared
    @StateObject private var search = LibrarySearch()
    let openBook: (String) -> Void
    @State private var text = ""
    @State private var place: BookPlace?
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var titled: [LibraryEntry] {
        let q = Dil.normal(text)
        guard q.count >= 2 else { return [] }
        return library.index.books.filter { Dil.normal($0.title).contains(q) }.sorted { $0.lastDate > $1.lastDate }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    field
                    if trimmed.count < 2 {
                        Text("Bir kitabın adını ya da kitapların içinde geçen bir ifadeyi yaz. Büyük/küçük harf, şapka ve ı/i fark etmez.")
                            .font(.subheadline).foregroundStyle(Tema.ikincil)
                    }
                    let t = titled
                    if !t.isEmpty { titles(t) }
                    if trimmed.count >= LibrarySearch.minimum {
                        SentenceResults(search: search) { h in place = BookPlace(book: h.book, ch: h.ch, b: h.b, find: search.query) }
                    } else if trimmed.count == 2 {
                        Text("Cümle aramak için en az üç harf.").font(.caption).foregroundStyle(Tema.soluk)
                    }
                }
                .padding(18)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Tema.arka.ignoresSafeArea())
            .navigationTitle("Ara")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
        }
        .onChange(of: text) { _, q in search.search(q) }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true } }
        .onDisappear { search.cancel() }
        .bookPlaceOpener($place)
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 660)
        #endif
    }

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Tema.ikincil)
            TextField("Kitap ya da cümle ara", text: $text).textFieldStyle(.plain).autocorrectionDisabled()
                .focused($focused)
                #if os(iOS)
                .submitLabel(.search)
                #endif
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(Tema.soluk).accessibilityLabel("Temizle")
            }
        }
        .font(.system(size: 16))
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background { Capsule().fill(Tema.yuzey2) }
    }

    private func titles(_ list: [LibraryEntry]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Kitaplar · \(list.count)", systemImage: "books.vertical").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.ikincil)
            ForEach(list.prefix(8)) { e in
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { openBook(e.id) }
                } label: {
                    HStack(spacing: 12) {
                        KitapKapagi(id: e.id, baslik: e.titleParts.title, genislik: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.titleParts.title).font(Tema.serif(.callout, .semibold)).foregroundStyle(Tema.metin).lineLimit(2)
                            if let a = e.titleParts.author { Text(a).font(.caption).foregroundStyle(Tema.ikincil).lineLimit(1) }
                            Text("%\(e.percent) · \(e.chapters) bölüm").font(.caption2).monospacedDigit().foregroundStyle(Tema.soluk)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Tema.soluk)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if list.count > 8 {
                Text("ve \(list.count - 8) kitap daha; adı biraz daha yaz.").font(.caption).foregroundStyle(Tema.soluk)
            }
        }
    }
}

/// "Bu kitapta ara" on the book page: the places inline, each opening the reader on it with the phrase marked.
struct BookTextSearch: View {
    let book: Book?
    let tint: Color
    let open: (TextHit, String) -> Void
    @State private var text = ""
    @State private var found = TextSearch.Found()
    @State private var searched = ""
    @State private var all = false
    @State private var task: Task<Void, Never>?

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "text.magnifyingglass").foregroundStyle(Tema.ikincil)
                TextField("Bu kitapta ara", text: $text).textFieldStyle(.plain).autocorrectionDisabled()
                    #if os(iOS)
                    .submitLabel(.search)
                    #endif
                if !text.isEmpty {
                    Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Tema.soluk).accessibilityLabel("Temizle")
                }
            }
            .font(.system(size: 15))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background { Capsule().fill(Tema.yuzey2) }
            if trimmed.count >= TextSearch.minimum, searched == trimmed {
                if found.hits.isEmpty {
                    Text("“\(searched)” bu kitapta geçmiyor.").font(.subheadline).foregroundStyle(Tema.ikincil)
                } else {
                    let chapters = Set(found.hits.map(\.ch)).count
                    Text("\(found.total) yer · \(chapters) bölümde").font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(tint)
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(all ? found.hits : Array(found.hits.prefix(5))) { h in
                            Button { open(h, searched) } label: { TextHitRow(hit: h) }.buttonStyle(.plain)
                        }
                    }
                    if !all, found.hits.count > 5 {
                        Button { all = true } label: {
                            Label(found.total > found.hits.count ? "İlk \(found.hits.count) yeri göster" : "Hepsini göster (\(found.hits.count))",
                                  systemImage: "chevron.down").font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain).foregroundStyle(tint)
                    }
                }
            }
        }
        .disabled(book == nil)
        .onChange(of: text) { _, q in run(q) }
        .onChange(of: book?.id) { _, _ in run(text) }
    }

    private func run(_ q: String) {
        task?.cancel()
        let t = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= TextSearch.minimum, let book else { found = TextSearch.Found(); searched = ""; return }
        task = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let r = await Task.detached(priority: .userInitiated) { TextSearch.hits(in: book, t, limit: 80) }.value
            guard !Task.isCancelled else { return }
            found = r
            searched = t
            all = false
        }
    }
}

/// The search field on the Kitaplar / Kütüphane screen; it opens LibrarySearchSheet.
struct LibrarySearchButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                Text("Kitap ya da cümle ara").lineLimit(1)
                Spacer(minLength: 0)
                #if os(macOS)
                Text("⇧⌘F").font(.caption).foregroundStyle(Tema.soluk)
                #endif
            }
            .font(.system(size: 15)).foregroundStyle(Tema.ikincil)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background { Capsule().fill(Tema.yuzey2) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("f", modifiers: [.command, .shift])
        .accessibilityLabel("Kitap ya da cümle ara")
    }
}
