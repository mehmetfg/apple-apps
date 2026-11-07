// Library — every listened book kept as a real book (veri/library.py writes library/ in the vault).
// The shelf index and Claude's insights are small and synced whole; a book's text is fetched only when opened
// and kept in the local container, so a book stays readable offline and after Voice Dream drops it.
import Foundation
import SwiftUI

struct LibraryEntry: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let claude: Bool
    let percent: Int
    let last: String?
    let added: String?
    let words: Int
    let chapters: Int
    let highlights: Int
    let inVD: Bool
    var inVR: Bool?                 // in Voice Reader (iPhone) now — library.py, 2026-10-20
    let insight: Bool

    var lastDate: Date { Tarih.coz(last ?? "") ?? Tarih.coz(added ?? "") ?? .distantPast }
    var finished: Bool { percent >= 90 }
    /// "Author - Title" → ("Title", "Author") for outside books.
    var titleParts: (title: String, author: String?) {
        if !claude, let r = title.range(of: " - ") {
            return (String(title[r.upperBound...]), String(title[..<r.lowerBound]))
        }
        return (title.kodsuz, nil)
    }
}

struct LibraryIndex: Codable { var version: String; var books: [LibraryEntry] }

struct BookBlock: Codable, Hashable {
    let k: String          // "p" paragraph · "h" heading
    let x: String
    var lv: Int?
    var st: String?        // "oz" chapter essence · "oz-head" · "tekrar" spoken repetition (hidden)
    var isHeading: Bool { k == "h" }
}

struct BookChapter: Codable, Hashable {
    let title: String
    var sub: String?
    var part: String?
    let blocks: [BookBlock]
}

struct BookHighlight: Codable, Hashable, Identifiable {
    struct Place: Codable, Hashable { let ch: Int; let b: Int; let s: Int; let e: Int }
    let id: String
    let color: Int
    let date: String?
    var note: String?
    let quote: String
    let at: [Place]
    var time: Date { Tarih.coz(date ?? "") ?? .distantPast }
}

struct Book: Codable, Hashable {
    let id: String
    let title: String
    let claude: Bool
    let edition: String
    let words: Int
    let chapters: [BookChapter]
    let highlights: [BookHighlight]
    var percent: Int?
}

extension Book {
    func adding(_ more: [BookHighlight]) -> Book {
        more.isEmpty ? self : Book(id: id, title: title, claude: claude, edition: edition, words: words, chapters: chapters,
                                   highlights: highlights + more, percent: percent)
    }
}

/// A highlight made in Teoria (while reading or listening). One append-only log per device:
/// library/marks/<device>.jsonl. Deleting is a new line with `deleted: true` — nothing is rewritten.
struct TeoriaMark: Codable, Hashable, Identifiable {
    var id: String
    var book: String
    var ch: Int
    var b: Int
    var s: Int
    var e: Int
    var quote: String
    var color: Int
    var date: String
    var deleted: Bool?

    var highlight: BookHighlight {
        BookHighlight(id: id, color: color, date: date, note: nil, quote: quote, at: [.init(ch: ch, b: b, s: s, e: e)])
    }
}

/// Claude's reading of a book: library/insights/<id>.json ("Teoria kitap işle").
struct BookInsight: Codable, Hashable {
    struct ChapterSummary: Codable, Hashable { let ch: Int; let summary: String; var key: String? }
    /// A carrying point the reader did not mark. Folded from İdrak (rooms.py) it may have no address.
    struct Missed: Codable, Hashable, Identifiable {
        var ch: Int?; var b: Int?; let quote: String; let why: String
        var id: String { "\(ch ?? -1).\(b ?? -1).\(quote.prefix(24))" }
    }
    /// İdrak's core: what the book is about, its claim, the idea to carry away.
    struct Core: Codable, Hashable { var theme: String?; var claim: String?; var idea: String? }
    struct Nuance: Codable, Hashable { let title: String; var text: String? }
    /// Can alıcı cümle: chosen by Claude from the text whether or not it was marked; weight 5 = carries the book.
    struct Key: Codable, Hashable, Identifiable {
        var ch: Int?; var b: Int?
        let quote: String
        var why: String
        var weight: Int
        var words: [String]?
        var id: String { "\(ch ?? -1).\(b ?? -1).\(quote.prefix(32))" }
    }
    struct Source: Codable, Hashable { let work: String; var author: String?; var year: Int?; var kind: String?; var why: String?
        var isReference: Bool { kind != "read" } }
    struct Link: Codable, Hashable { let to: String; var kind: String?; var note: String? }
    struct Node: Codable, Hashable, Identifiable { let id: String; let label: String; var note: String?; var ch: [Int]?; var weight: Int? }
    struct Edge: Codable, Hashable { let a: String; let b: String; var label: String? }
    struct ConceptMap: Codable, Hashable { var nodes: [Node]; var edges: [Edge] }
    struct Drop: Codable, Hashable { let ch: Int; let b: Int; var why: String? }

    var built: String?
    var thesis: String?
    var verdicts: [String]
    var chapters: [ChapterSummary]
    var missed: [Missed]?
    var concepts: ConceptMap?
    var drop: [Drop]?
    var by: String?
    var core: Core?
    var chain: [String]?
    var nuances: [Nuance]?
    var keys: [Key]?
    var sources: [Source]?
    var links: [Link]?

    func summary(_ ch: Int) -> ChapterSummary? { chapters.first { $0.ch == ch } }
    var dropped: Set<String> { Set((drop ?? []).map { "\($0.ch).\($0.b)" }) }
}

/// library/network.json (rooms.py): İdrak's clusters (each a question) and, for every book with a room,
/// its cluster and listening log — the data behind the Mac library's Ağ and İstatistik views.
struct LibraryNetwork: Codable, Hashable {
    struct Cluster: Codable, Hashable { let name: String; let question: String }
    struct Read: Codable, Hashable { let date: String; var percent: Int? }
    struct Member: Codable, Hashable { let cluster: String; var reads: [Read] }
    var clusters: [String: Cluster]
    var books: [String: Member]
    static let order = ["bilgi", "varolus", "sistem", "etik", "sermaye", "diger"]
    var clusterIds: [String] { Self.order.filter { clusters[$0] != nil } + clusters.keys.filter { !Self.order.contains($0) }.sorted() }
}

@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()
    @Published private(set) var index = LibraryIndex(version: "0", books: [])
    @Published private(set) var insights: [String: BookInsight] = [:]
    @Published private(set) var loading: Set<String> = []
    @Published var failed: String?
    @Published private(set) var marks: [String: [TeoriaMark]] = [:]     // book → live marks (deleted removed)
    @Published private(set) var network = LibraryNetwork(clusters: [:], books: [:])
    private var books: [String: Book] = [:]
    private var opening: [String: Task<Book?, Never>] = [:]   // one load per book, however many screens ask at once
    private var syncing = false
    private var syncAgain = false

    private var local: URL { Paylasim.kapsayici.appendingPathComponent("bookshelf", isDirectory: true) }

    init() { loadLocal(); loadMarks() }

    // MARK: marks made in Teoria

    private var myMarks: URL { local.appendingPathComponent("marks/\(Cihaz.ad).jsonl") }
    private var otherMarks: URL { local.appendingPathComponent("marks-others", isDirectory: true) }

    private func loadMarks() {
        var lines: [TeoriaMark] = []
        let dec = JSONDecoder()
        var files = [myMarks]
        files += ((try? FileManager.default.contentsOfDirectory(at: otherMarks, includingPropertiesForKeys: nil)) ?? [])
        for f in files {
            guard let t = try? String(contentsOf: f, encoding: .utf8) else { continue }
            for l in t.split(separator: "\n") { if let m = try? dec.decode(TeoriaMark.self, from: Data(l.utf8)) { lines.append(m) } }
        }
        var last: [String: TeoriaMark] = [:]
        for m in lines { last[m.id] = m }                       // later line wins (deletion)
        marks = Dictionary(grouping: last.values.filter { $0.deleted != true }, by: \.book)
    }

    private func append(_ m: TeoriaMark) {
        try? FileManager.default.createDirectory(at: myMarks.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard var line = try? JSONEncoder().encode(m) else { return }
        line.append(0x0A)
        if let h = try? FileHandle(forWritingTo: myMarks) { h.seekToEndOfFile(); h.write(line); try? h.close() }
        else { try? line.write(to: myMarks, options: .atomic) }
    }

    @discardableResult
    func addMark(book: String, ch: Int, b: Int, s: Int, e: Int, quote: String, color: Int) -> TeoriaMark {
        let m = TeoriaMark(id: "t-" + UUID().uuidString.prefix(12).lowercased(), book: book, ch: ch, b: b, s: s, e: e,
                           quote: quote, color: color, date: Tarih.isoSaat(Date()))
        append(m)
        marks[book, default: []].append(m)
        return m
    }

    func deleteMark(_ m: TeoriaMark) {
        var d = m; d.deleted = true; d.date = Tarih.isoSaat(Date())
        append(d)
        marks[m.book]?.removeAll { $0.id == m.id }
    }

    func mark(_ id: String) -> TeoriaMark? { marks.values.lazy.flatMap { $0 }.first { $0.id == id } }

    private var syncTask: Task<Void, Never>?
    /// New marks go up to the vault a few seconds after the last one (one write for a burst of marks).
    func scheduleSync(_ kasa: Kasa) {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, !Task.isCancelled else { return }
            await self.sync(kasa)
        }
    }

    /// The book with Voice Dream highlights and the ones made in Teoria.
    func withMarks(_ b: Book) -> Book { b.adding((marks[b.id] ?? []).map(\.highlight)) }

    func entry(_ id: String) -> LibraryEntry? { index.books.first { $0.id == id } }
    func cached(_ id: String) -> Book? { books[id] }

    private func loadLocal() {
        let dec = JSONDecoder()
        if let v = try? Data(contentsOf: local.appendingPathComponent("index.json")),
           let i = try? dec.decode(LibraryIndex.self, from: v) { index = i }
        if let v = try? Data(contentsOf: local.appendingPathComponent("network.json")),
           let n = try? dec.decode(LibraryNetwork.self, from: v) { network = n }
        let dir = local.appendingPathComponent("insights")
        var all: [String: BookInsight] = [:]
        for f in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where f.hasSuffix(".json") {
            if let v = try? Data(contentsOf: dir.appendingPathComponent(f)), let x = try? dec.decode(BookInsight.self, from: v) {
                all[String(f.dropLast(5))] = x
            }
        }
        insights = all
    }

    /// Shelf + insights from the vault into the local container (background, coordinated reads).
    func sync(_ kasa: Kasa) async {
        // two syncs at once (app returning to the foreground + a burst of new marks) would write the same files;
        // a request during a sync runs once more after it instead
        if syncing { syncAgain = true; return }
        syncing = true
        defer { syncing = false }
        repeat {
            syncAgain = false
            await syncOnce(kasa)
        } while syncAgain
    }

    private struct Pulled: Sendable {
        var changed = Set<String>()             // groups whose local copy was rewritten: index · network · sabah · marks · feedback
        var insights: [String] = []             // insight files that were rewritten
        var stamps: [String: FileStamp] = [:]
    }
    private var stamps: [String: FileStamp] = [:]   // vault files as last read in this run (unchanged → skipped)

    private func syncOnce(_ kasa: Kasa) async {
        let target = local
        let device = Cihaz.ad
        let seen = stamps
        let pulled: Pulled? = await kasa.ile { kok in
            var out = Pulled()
            let fm = FileManager.default
            let lib = kok.appendingPathComponent("library", isDirectory: true)
            try fm.createDirectory(at: target.appendingPathComponent("insights"), withIntermediateDirectories: true)
            /// Vault file → local copy, only when it changed: same size and date as last time is not read at all,
            /// same bytes as the local copy is not written (and nothing is reloaded for it).
            func pull(_ src: URL, _ dst: URL, _ group: String, wait: Bool = false) throws -> Bool {
                if wait { Kasa.indir(src) }
                let key = src.path
                let stamp = FileStamp.of(src)
                if let stamp, seen[key] == stamp { return false }
                guard let v = Kasa.koordineliOku(src) else { return false }
                if let stamp { out.stamps[key] = stamp }
                if (try? Data(contentsOf: dst)) == v { return false }
                try v.write(to: dst, options: .atomic)
                out.changed.insert(group)
                return true
            }
            _ = try pull(lib.appendingPathComponent("index.json"), target.appendingPathComponent("index.json"), "index", wait: true)
            // Sabah's plan (veri/sabah.py)
            _ = try pull(lib.appendingPathComponent("sabah.json"), target.appendingPathComponent("sabah.json"), "sabah", wait: true)
            // İkinci dikkat (veri/ikinci.py)
            _ = try pull(lib.appendingPathComponent("ikinci.json"), target.appendingPathComponent("ikinci.json"), "ikinci", wait: true)
            _ = try pull(lib.appendingPathComponent("network.json"), target.appendingPathComponent("network.json"), "network", wait: true)
            // marks: mine up, the other devices' down
            let mk = lib.appendingPathComponent("marks", isDirectory: true)
            try? fm.createDirectory(at: mk, withIntermediateDirectories: true)
            let mine = target.appendingPathComponent("marks/\(device).jsonl")
            if let v = try? Data(contentsOf: mine) {
                let dst = mk.appendingPathComponent("\(device).jsonl")
                if Kasa.koordineliOku(dst) != v { try? Kasa.koordineliYaz(v, dst) }
            }
            try? fm.createDirectory(at: target.appendingPathComponent("marks-others"), withIntermediateDirectories: true)
            for f in (try? fm.contentsOfDirectory(atPath: mk.path)) ?? [] where f.hasSuffix(".jsonl") && f != "\(device).jsonl" {
                _ = try? pull(mk.appendingPathComponent(f), target.appendingPathComponent("marks-others/\(f)"), "marks")
            }
            // feedback (ratings, expand switches): mine up, the other devices' down — same as marks
            let fbDir = lib.appendingPathComponent("feedback", isDirectory: true)
            try? fm.createDirectory(at: fbDir, withIntermediateDirectories: true)
            if let v = try? Data(contentsOf: target.appendingPathComponent("feedback/\(device).jsonl")) {
                let dst = fbDir.appendingPathComponent("\(device).jsonl")
                if Kasa.koordineliOku(dst) != v { try? Kasa.koordineliYaz(v, dst) }
            }
            try? fm.createDirectory(at: target.appendingPathComponent("feedback-others"), withIntermediateDirectories: true)
            for f in (try? fm.contentsOfDirectory(atPath: fbDir.path)) ?? [] where f.hasSuffix(".jsonl") && f != "\(device).jsonl" {
                _ = try? pull(fbDir.appendingPathComponent(f), target.appendingPathComponent("feedback-others/\(f)"), "feedback")
            }
            let ins = lib.appendingPathComponent("insights", isDirectory: true)
            for f in (try? fm.contentsOfDirectory(atPath: ins.path)) ?? [] {
                if f.hasPrefix("."), f.hasSuffix(".icloud") {
                    try? fm.startDownloadingUbiquitousItem(at: ins.appendingPathComponent(String(f.dropFirst().dropLast(7)))); continue
                }
                guard f.hasSuffix(".json") else { continue }
                if try pull(ins.appendingPathComponent(f), target.appendingPathComponent("insights/\(f)"), "insights") { out.insights.append(f) }
            }
            return out
        }
        guard let pulled else { return }
        stamps.merge(pulled.stamps) { _, new in new }
        // Only what changed is read again, and it is decoded off the main actor.
        if pulled.changed.contains("sabah") { await MorningStore.shared.reload() }
        if pulled.changed.contains("feedback") { FeedbackStore.shared.load() }
        if pulled.changed.contains("marks") { loadMarks() }
        let dir = local
        if pulled.changed.contains("network"),
           let n = await Task.detached(operation: { LibraryStore.decode(LibraryNetwork.self, dir.appendingPathComponent("network.json")) }).value {
            network = n
        }
        if !pulled.insights.isEmpty {
            let files = pulled.insights
            let fresh = await Task.detached { () -> [String: BookInsight] in
                var all: [String: BookInsight] = [:]
                for f in files {
                    if let x = LibraryStore.decode(BookInsight.self, dir.appendingPathComponent("insights/\(f)")) { all[String(f.dropLast(5))] = x }
                }
                return all
            }.value
            if !fresh.isEmpty { insights.merge(fresh) { _, new in new } }
        }
        if pulled.changed.contains("index"),
           let i = await Task.detached(operation: { LibraryStore.decode(LibraryIndex.self, dir.appendingPathComponent("index.json")) }).value {
            // a book whose edition changed in the vault is fetched again next time it opens
            let old = Dictionary(index.books.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            index = i
            for b in index.books where old[b.id].map({ $0.words != b.words || $0.highlights != b.highlights }) ?? false {
                books[b.id] = nil
                try? FileManager.default.removeItem(at: local.appendingPathComponent("books/\(b.id).json"))
            }
        }
    }

    nonisolated private static func decode<T: Decodable>(_ type: T.Type, _ file: URL) -> T? {
        guard let v = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(T.self, from: v)
    }

    /// The book's reading edition: memory → local copy → vault.
    func book(_ id: String, kasa: Kasa) async -> Book? {
        if let b = books[id] { return b }
        if let t = opening[id] { return await t.value }
        let t = Task { await load(id, kasa: kasa) }
        opening[id] = t
        let b = await t.value
        opening[id] = nil
        return b
    }

    private func load(_ id: String, kasa: Kasa) async -> Book? {
        let file = local.appendingPathComponent("books/\(id).json")
        // a book is up to a few MB of JSON: read and decode off the main thread so the screen never stalls
        if let b = await Task.detached(priority: .userInitiated, operation: { () -> Book? in
            guard let v = try? Data(contentsOf: file) else { return nil }
            return try? JSONDecoder().decode(Book.self, from: v)
        }).value {
            books[id] = b
            return b
        }
        loading.insert(id)
        defer { loading.remove(id) }
        let fetched: Data?? = await kasa.ile { kok -> Data? in
            let u = kok.appendingPathComponent("library/books/\(id).json")
            if !FileManager.default.fileExists(atPath: u.path) {
                try? FileManager.default.startDownloadingUbiquitousItem(at: u)
                var i = 0
                while !FileManager.default.fileExists(atPath: u.path) && i < 60 { Thread.sleep(forTimeInterval: 0.25); i += 1 }
            }
            return Kasa.koordineliOku(u)
        }
        let data = fetched ?? nil
        let decoded: Book? = await Task.detached(priority: .userInitiated) { data.flatMap { try? JSONDecoder().decode(Book.self, from: $0) } }.value
        guard let data, let b = decoded else {
            failed = kasa.bagli ? "Kitap henüz inmedi; birazdan yeniden dene." : "Vault klasörü bağlı değil (Ayarlar)."
            return nil
        }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        books[id] = b
        return b
    }

    /// Akış kitap kimliği → kütüphane kaydı (aynı kimlik ya da aynı başlık).
    func entry(forAkis k: OkumaKitabi) -> LibraryEntry? {
        entry(k.id) ?? index.books.first { Dil.normal($0.title) == Dil.normal(k.baslik) }
    }
}

// MARK: - Geri bildirim (2026-11-03): book ratings and "burayı genişlet" signals

/// One line of library/feedback/<device>.jsonl. The latest line per (kind, book, target) wins.
/// rating: value 1 = Orta, 2 = İyi, 0 = cleared · expand: every mark is "expand" until a line with value 0 switches it off.
/// veri/feedback.py turns all of it (with the marks and the Kür misses) into library/GERIBILDIRIM.md for Claude.
struct FeedbackEvent: Codable, Hashable {
    var id: String = UUID().uuidString
    var kind: String
    var book: String
    var target: String?
    var value: Int
    var reasons: [String]?
    var note: String?
    var quote: String?
    var ch: Int?
    var date: String = Tarih.isoSaat(Date())
}

@MainActor
final class FeedbackStore: ObservableObject {
    static let shared = FeedbackStore()
    @Published private(set) var ratings: [String: FeedbackEvent] = [:]
    @Published private(set) var closed: Set<String> = []

    private var dir: URL { Paylasim.kapsayici.appendingPathComponent("bookshelf", isDirectory: true) }
    private var mine: URL { dir.appendingPathComponent("feedback/\(Cihaz.ad).jsonl") }

    init() { load() }

    func load() {
        var lines: [FeedbackEvent] = []
        let dec = JSONDecoder()
        var files = [mine]
        files += ((try? FileManager.default.contentsOfDirectory(at: dir.appendingPathComponent("feedback-others"), includingPropertiesForKeys: nil)) ?? [])
        for f in files {
            guard let t = try? String(contentsOf: f, encoding: .utf8) else { continue }
            for l in t.split(separator: "\n") { if let e = try? dec.decode(FeedbackEvent.self, from: Data(l.utf8)) { lines.append(e) } }
        }
        var r: [String: FeedbackEvent] = [:], c = Set<String>()
        for e in lines.sorted(by: { $0.date < $1.date }) {
            if e.kind == "rating" { r[e.book] = e }
            if e.kind == "expand", let t = e.target { if e.value == 0 { c.insert(t) } else { c.remove(t) } }
        }
        ratings = r.filter { $0.value.value > 0 }
        closed = c
    }

    private func append(_ e: FeedbackEvent) {
        try? FileManager.default.createDirectory(at: mine.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard var line = try? JSONEncoder().encode(e) else { return }
        line.append(0x0A)
        if let h = try? FileHandle(forWritingTo: mine) { h.seekToEndOfFile(); h.write(line); try? h.close() }
        else { try? line.write(to: mine, options: .atomic) }
    }

    func rate(_ book: String, value: Int, reasons: [String], note: String?) {
        let e = FeedbackEvent(kind: "rating", book: book, value: value, reasons: reasons.isEmpty ? nil : reasons,
                              note: (note?.isEmpty ?? true) ? nil : note)
        append(e)
        if value > 0 { ratings[book] = e } else { ratings[book] = nil }
    }

    func expands(_ mark: String) -> Bool { !closed.contains(mark) }

    func setExpand(_ on: Bool, mark: String, book: String, quote: String, ch: Int?) {
        append(FeedbackEvent(kind: "expand", book: book, target: mark, value: on ? 1 : 0, quote: quote, ch: ch))
        if on { closed.remove(mark) } else { closed.insert(mark) }
    }
}

/// Book page: two levels, ★ Orta · ★★ İyi (tap again to clear). Unrated is not positive. The rating steers what the
/// next texts lean on.
struct BookRatingBar: View {
    @EnvironmentObject var depo: Depo
    @ObservedObject private var fb = FeedbackStore.shared
    let book: String
    @State private var note = ""

    private var current: FeedbackEvent? { fb.ratings[book] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Değerlendir").font(.caption.weight(.semibold)).foregroundStyle(Tema.ikincil)
                level(1, "★ Orta")
                level(2, "★★ İyi")
                Spacer(minLength: 0)
            }
            if let c = current {
                HStack(spacing: 8) {
                    reason("rich", "İçerik zengin", c)
                    reason("fit", "Amaca uygun", c)
                }
                TextField("Bir satır not (isteğe bağlı) ↩", text: $note)
                    .textFieldStyle(.roundedBorder).font(.callout)
                    .onSubmit { save(c.value, c.reasons ?? []) }
            }
            Text(current == nil ? "Puansız kitap olumlu sayılmaz. Puan, sıradaki metinlerin nereye ağırlık vereceğini yönlendirir."
                                : "Kaydedildi · sıradaki metin yazılırken okunur.")
                .font(.caption2).foregroundStyle(Tema.soluk).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Tema.yuzey))
        .onAppear { note = current?.note ?? "" }
    }

    private func level(_ v: Int, _ t: String) -> some View {
        let on = current?.value == v
        return Button { save(on ? 0 : v, current?.reasons ?? []) } label: {
            Text(t).font(.callout.weight(on ? .semibold : .regular))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(on ? Tema.altin.opacity(0.22) : Tema.yuzey2))
                .foregroundStyle(on ? Tema.metin : Tema.ikincil)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(on ? "\(t), seçili" : t)
    }

    private func reason(_ key: String, _ t: String, _ c: FeedbackEvent) -> some View {
        let on = c.reasons?.contains(key) ?? false
        return Button {
            var r = c.reasons ?? []
            if on { r.removeAll { $0 == key } } else { r.append(key) }
            save(c.value, r)
        } label: {
            Label(t, systemImage: on ? "checkmark.circle.fill" : "circle")
                .font(.caption).foregroundStyle(on ? Tema.basari : Tema.ikincil)
        }
        .buttonStyle(.plain)
    }

    private func save(_ v: Int, _ reasons: [String]) {
        fb.rate(book, value: v, reasons: v > 0 ? reasons : [], note: v > 0 ? note : nil)
        if v == 0 { note = "" }
        Dokunus.secim()
        LibraryStore.shared.scheduleSync(depo.kasa)
    }
}

/// A mark's second job: "burayı genişlet". On by default for every mark; switched off here.
struct ExpandToggle: View {
    @EnvironmentObject var depo: Depo
    @ObservedObject private var fb = FeedbackStore.shared
    let book: String
    let highlight: BookHighlight
    var compact = false

    var body: some View {
        let on = fb.expands(highlight.id)
        if compact {
            Button { set(!on) } label: {
                Image(systemName: on ? "arrow.up.left.and.arrow.down.right.circle.fill" : "arrow.up.left.and.arrow.down.right.circle")
                    .foregroundStyle(on ? Tema.vurgu : Tema.soluk)
            }
            .buttonStyle(.plain)
            .help(on ? "Genişlet açık: sonraki metinde bu yer açılır" : "Genişlet kapalı")
            .accessibilityLabel(on ? "Genişlet açık" : "Genişlet kapalı")
        } else {
            Toggle(isOn: Binding(get: { on }, set: { set($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Burayı genişlet", systemImage: "arrow.up.left.and.arrow.down.right")
                    Text("Sonraki metinde ve Dikkat Metni'nde bu yer açılır").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func set(_ v: Bool) {
        fb.setExpand(v, mark: highlight.id, book: book, quote: highlight.quote, ch: highlight.at.first?.ch)
        LibraryStore.shared.scheduleSync(depo.kasa)
    }
}
