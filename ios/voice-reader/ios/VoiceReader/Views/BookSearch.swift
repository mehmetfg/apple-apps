// Search inside the books (2026-11-08): a sentence anywhere in the library, an expression inside one book.
//   Kütüphane  the search field finds titles and authors as before, and below them "Kitapların içinde": every book
//              where the phrase occurs, the most recently opened first, each with its first places
//   a book     "Kitapta ara" on its card (menu, or the book taken off the shelf) searches it without opening it
//   a place    opens the book showing that place; the reading place stays where it was (revealRequest)
// Matching ignores case, accents and the dotted/dotless i: "gazali" finds "Gazâlî", "ISIK" finds "ışık".
import SwiftUI

// MARK: - matcher

enum TextFold {
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

    static func needle(_ q: String, minimum: Int = 2) -> [UInt16]? {
        let t = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= minimum else { return nil }
        return table.withUnsafeBufferPointer { tb in t.utf16.map { tb[Int($0)] } }
    }
}

struct TextHit: Identifiable, Hashable, Sendable {
    let doc: UUID
    let offset: Int             // UTF-16 offset in the document's text
    let chapter: String
    let before: String
    let match: String
    let after: String
    var id: String { "\(doc.uuidString).\(offset)" }
}

enum TextSearch {
    struct Found: Sendable { var hits: [TextHit] = []; var total = 0 }

    /// Every place in a document's text, in order; `total` counts past the limit too.
    static func hits(doc: UUID, text: String, chapters: [Chapter], needle: [UInt16], limit: Int) -> Found {
        let orig = Array(text.utf16)
        var folded = [UInt16]()
        folded.reserveCapacity(orig.count)
        TextFold.table.withUnsafeBufferPointer { t in for u in orig { folded.append(t[Int(u)]) } }
        let ns = text as NSString
        let heads = chapters.sorted { $0.offset < $1.offset }
        var out = Found()
        let m = needle.count
        guard m > 0, folded.count >= m else { return out }
        folded.withUnsafeBufferPointer { h in
            needle.withUnsafeBufferPointer { nd in
                let first = nd[0], end = h.count - m
                var i = 0
                while i <= end {
                    if h[i] == first {
                        var k = 1
                        while k < m && h[i + k] == nd[k] { k += 1 }
                        if k == m {
                            out.total += 1
                            if out.hits.count < limit {
                                let ch = heads.last { $0.offset <= i }?.title ?? ""
                                out.hits.append(snippet(doc: doc, ns: ns, at: i, length: m, chapter: ch))
                            }
                            i += m
                            continue
                        }
                    }
                    i += 1
                }
            }
        }
        return out
    }

    /// The paragraph around a place, cut at word boundaries, never across a paragraph.
    static func snippet(doc: UUID, ns: NSString, at: Int, length: Int, chapter: String) -> TextHit {
        let para = ns.paragraphRange(for: NSRange(location: at, length: 0))
        var a = max(para.location, at - 60), z = min(NSMaxRange(para), at + length + 90)
        if a > para.location {
            let r = ns.range(of: " ", options: [], range: NSRange(location: a, length: at - a))
            if r.location != NSNotFound { a = r.location + 1 }
        }
        if z < NSMaxRange(para) {
            let r = ns.range(of: " ", options: .backwards, range: NSRange(location: at + length, length: max(0, z - at - length)))
            if r.location != NSNotFound { z = r.location }
        }
        let left = ns.rangeOfComposedCharacterSequences(for: NSRange(location: a, length: at - a))
        let right = ns.rangeOfComposedCharacterSequences(for: NSRange(location: at + length, length: max(0, z - at - length)))
        func clean(_ s: String) -> String { s.replacingOccurrences(of: "\n", with: " ") }
        return TextHit(doc: doc, offset: at, chapter: chapter,
                       before: (left.location > para.location ? "…" : "") + clean(ns.substring(with: left)),
                       match: ns.substring(with: NSRange(location: at, length: length)),
                       after: clean(ns.substring(with: right)) + (NSMaxRange(right) < NSMaxRange(para) - 1 ? "…" : ""))
    }

    static func search(doc: UUID, file: URL, needle: [UInt16], limit: Int) -> Found? {
        guard let data = try? Data(contentsOf: file), let c = try? JSONDecoder().decode(DocumentContent.self, from: data) else { return nil }
        return hits(doc: doc, text: c.text, chapters: c.chapters, needle: needle, limit: limit)
    }
}

// MARK: - the whole library

@MainActor
final class LibraryTextSearch: ObservableObject {
    struct Result: Identifiable {
        let doc: DocumentRecord
        let hits: [TextHit]
        let total: Int
        var id: UUID { doc.id }
    }

    static let minimum = 3
    static let perBook = 12
    static let cap = 300

    @Published private(set) var query = ""
    @Published private(set) var results: [Result] = []
    @Published private(set) var scanned = 0
    @Published private(set) var count = 0
    @Published private(set) var running = false
    @Published private(set) var capped = false
    private var task: Task<Void, Never>?

    var places: Int { results.reduce(0) { $0 + $1.total } }

    func search(_ q: String, in store: LibraryStore) {
        let t = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= Self.minimum else { cancel(); query = ""; results = []; scanned = 0; count = 0; capped = false; return }
        guard t != query else { return }
        task?.cancel()
        let docs = store.documents.sorted { ($0.lastOpenedAt ?? $0.addedAt) > ($1.lastOpenedAt ?? $1.addedAt) }
        let files = docs.map { store.contentURL($0.id) }
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(320))
            guard let self, !Task.isCancelled else { return }
            await self.run(t, docs, files)
        }
    }

    func cancel() { task?.cancel(); task = nil; running = false }

    private func run(_ q: String, _ docs: [DocumentRecord], _ files: [URL]) async {
        guard let needle = TextFold.needle(q, minimum: Self.minimum) else { return }
        query = q; results = []; scanned = 0; count = docs.count; capped = false; running = true
        var shown = 0
        for (n, d) in docs.enumerated() {
            if Task.isCancelled { return }
            let id = d.id, file = files[n], limit = min(Self.perBook, Self.cap - shown)
            let found = await Task.detached(priority: .userInitiated) { TextSearch.search(doc: id, file: file, needle: needle, limit: limit) }.value
            if Task.isCancelled { return }
            if let found, found.total > 0 {
                results.append(Result(doc: d, hits: found.hits, total: found.total))
                shown += found.hits.count
            }
            if n % 4 == 3 || n == docs.count - 1 { scanned = n + 1 }
            if shown >= Self.cap { capped = true; scanned = n + 1; break }
        }
        running = false
    }
}

// MARK: - views

struct TextHitRow: View {
    let hit: TextHit
    var showChapter = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showChapter, !hit.chapter.isEmpty {
                Text(hit.chapter).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
            }
            Text("\(Text(hit.before))\(Text(hit.match).bold().foregroundStyle(.orange))\(Text(hit.after))")
                .font(.system(.callout, design: .serif)).foregroundStyle(.primary).lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// "Kitapların içinde" under the library's search field.
struct LibrarySentenceResults: View {
    @Environment(AppModel.self) private var model
    let query: String
    let open: (TextHit) -> Void
    @StateObject private var search = LibraryTextSearch()
    @State private var expanded: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).count >= LibraryTextSearch.minimum {
                HStack(spacing: 8) {
                    Label("Kitapların içinde", systemImage: "text.magnifyingglass").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if !search.results.isEmpty {
                        Text("\(search.places) yer · \(search.results.count) kitap").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                ForEach(search.results) { r in book(r) }
                if search.running {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("\(search.scanned)/\(search.count) kitap tarandı").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                } else if !search.query.isEmpty, search.results.isEmpty {
                    Text("“\(search.query)” hiçbir kitabın içinde geçmiyor.").font(.subheadline).foregroundStyle(.secondary)
                }
                if search.capped {
                    Text("İlk \(LibraryTextSearch.cap) yer gösteriliyor; daha dar bir ifadeyle ara.").font(.caption).foregroundStyle(.secondary)
                }
            } else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("Kitapların içinde aramak için en az üç harf.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .onAppear { search.search(query, in: model.store) }
        .onChange(of: query) { _, q in search.search(q, in: model.store) }
        .onChange(of: search.query) { _, _ in expanded = [] }
        .onDisappear { search.cancel() }
    }

    private func book(_ r: LibraryTextSearch.Result) -> some View {
        let isOpen = expanded.contains(r.id)
        let list = isOpen ? r.hits : Array(r.hits.prefix(3))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(r.doc.title).font(.system(.subheadline, design: .serif).weight(.semibold)).lineLimit(2)
                    if let a = r.doc.author { Text(a).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 8)
                Text("\(r.total) yer").font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(.orange)
            }
            ForEach(list) { h in
                Button { open(h) } label: { TextHitRow(hit: h) }.buttonStyle(.plain)
            }
            if !isOpen, r.hits.count > 3 {
                Button { expanded.insert(r.id) } label: {
                    Label("\(r.hits.count - 3) yer daha", systemImage: "chevron.down").font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain).foregroundStyle(.orange)
            } else if r.total > r.hits.count {
                Button { model.bookSearchDoc = r.doc.id } label: {
                    Label("Bu kitaptaki \(r.total) yerin hepsi", systemImage: "list.bullet").font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain).foregroundStyle(.orange)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(GlassPanel(cornerRadius: 18))
    }
}

/// "Kitapta ara" from a book's card: the book's text searched without opening it; a place opens the book there.
struct BookSearchSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let doc: DocumentRecord
    let open: (TextHit) -> Void
    @State private var query = ""
    @State private var content: DocumentContent?
    @State private var found = TextSearch.Found()
    @State private var searched = ""

    var body: some View {
        NavigationStack {
            List {
                if content == nil {
                    HStack { ProgressView(); Text("Metin yükleniyor…").foregroundStyle(.secondary) }
                } else if searched.isEmpty {
                    Text("Bu kitabın içinde bir ifade ara. Büyük/küçük harf, şapka ve ı/i fark etmez.").foregroundStyle(.secondary)
                } else if found.hits.isEmpty {
                    ContentUnavailableView.search(text: searched)
                } else {
                    Section("\(found.total) yer · \(Set(found.hits.map(\.chapter)).count) bölümde") {
                        ForEach(found.hits) { h in
                            Button { dismiss(); open(h) } label: { TextHitRow(hit: h) }.tint(.primary)
                        }
                    }
                    if found.total > found.hits.count {
                        Text("İlk \(found.hits.count) yer gösteriliyor; kitabı açıp ⌕ ile hepsini gezebilirsin.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Bu kitapta ara")
            .navigationTitle(doc.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
            .task { content = await model.store.content(for: doc.id); run() }
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                run()
            }
        }
    }

    private func run() {
        guard let content, let needle = TextFold.needle(query) else { found = .init(); searched = ""; return }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines), id = doc.id
        Task {
            let r = await Task.detached(priority: .userInitiated) {
                TextSearch.hits(doc: id, text: content.text, chapters: content.chapters, needle: needle, limit: 300)
            }.value
            if q == query.trimmingCharacters(in: .whitespacesAndNewlines) { found = r; searched = q }
        }
    }
}
