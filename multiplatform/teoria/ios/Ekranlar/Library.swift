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
    struct Missed: Codable, Hashable, Identifiable {
        let ch: Int; let b: Int; let quote: String; let why: String
        var id: String { "\(ch).\(b).\(quote.prefix(24))" }
    }
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

    func summary(_ ch: Int) -> ChapterSummary? { chapters.first { $0.ch == ch } }
    var dropped: Set<String> { Set((drop ?? []).map { "\($0.ch).\($0.b)" }) }
}

@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()
    @Published private(set) var index = LibraryIndex(version: "0", books: [])
    @Published private(set) var insights: [String: BookInsight] = [:]
    @Published private(set) var loading: Set<String> = []
    @Published var failed: String?
    @Published private(set) var marks: [String: [TeoriaMark]] = [:]     // book → live marks (deleted removed)
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
            try? await Task.sleep(nanoseconds: 4_000_000_000)
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

    private func syncOnce(_ kasa: Kasa) async {
        let target = local
        let device = Cihaz.ad
        let ok: Bool? = await kasa.ile { kok in
            let fm = FileManager.default
            let lib = kok.appendingPathComponent("library", isDirectory: true)
            try fm.createDirectory(at: target.appendingPathComponent("insights"), withIntermediateDirectories: true)
            let ix = lib.appendingPathComponent("index.json")
            Kasa.indir(ix)
            if let v = Kasa.koordineliOku(ix) { try v.write(to: target.appendingPathComponent("index.json"), options: .atomic) }
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
                if let v = Kasa.koordineliOku(mk.appendingPathComponent(f)) { try? v.write(to: target.appendingPathComponent("marks-others/\(f)"), options: .atomic) }
            }
            let ins = lib.appendingPathComponent("insights", isDirectory: true)
            for f in (try? fm.contentsOfDirectory(atPath: ins.path)) ?? [] {
                if f.hasPrefix("."), f.hasSuffix(".icloud") {
                    try? fm.startDownloadingUbiquitousItem(at: ins.appendingPathComponent(String(f.dropFirst().dropLast(7)))); continue
                }
                guard f.hasSuffix(".json"), let v = Kasa.koordineliOku(ins.appendingPathComponent(f)) else { continue }
                try v.write(to: target.appendingPathComponent("insights/\(f)"), options: .atomic)
            }
            return true
        }
        if ok == true {
            // a book whose edition changed in the vault is fetched again next time it opens
            let old = Dictionary(index.books.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            loadLocal()
            loadMarks()
            for b in index.books where old[b.id].map({ $0.words != b.words || $0.highlights != b.highlights }) ?? false {
                books[b.id] = nil
                try? FileManager.default.removeItem(at: local.appendingPathComponent("books/\(b.id).json"))
            }
        }
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
