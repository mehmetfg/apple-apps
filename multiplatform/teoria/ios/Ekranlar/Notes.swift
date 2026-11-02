// Notes — what the reader writes or says about a book, as production (2026-10-21).
// A note is tied to a place (a marked sentence, a page, the sentence being heard) or to the whole book, and holds
// typed text and/or a voice recording (dictated into text on the device). One append-only log per device:
// library/notes/<device>.jsonl; the latest line of an id wins, deleting is a line with `deleted: true`.
// Voice files: library/notes-audio/<id>.m4a. Counts (notes · sentences · words · minutes spoken) are derived, never typed.
import Foundation
import AVFoundation

/// A place in a book a note can hang on (block address + UTF-16 range, like a mark).
struct NoteAnchor: Hashable {
    var ch: Int
    var b: Int
    var s: Int
    var e: Int
    var quote: String
    var chapterTitle: String?
}

struct TeoriaNote: Codable, Hashable, Identifiable {
    var id: String
    var book: String
    var bookTitle: String
    var text: String
    var audio: String?
    var seconds: Double?
    var ch: Int?
    var b: Int?
    var s: Int?
    var e: Int?
    var quote: String?
    var chapterTitle: String?
    var date: String
    var edited: String?
    var deleted: Bool?

    var created: Date { Tarih.coz(date) ?? .distantPast }
    var stamp: String { edited ?? date }
    var anchored: Bool { quote != nil }
    var words: Int { NoteText.words(text) }
    var sentences: Int { NoteText.sentences(text) }
    var hasVoice: Bool { audio != nil }
    var anchor: NoteAnchor? {
        guard let ch, let b, let s, let e, let quote else { return nil }
        return NoteAnchor(ch: ch, b: b, s: s, e: e, quote: quote, chapterTitle: chapterTitle)
    }
}

enum NoteText {
    static func words<S: StringProtocol>(_ t: S) -> Int {
        t.split(whereSeparator: { $0.isWhitespace }).filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }.count
    }

    /// A sentence ends at . ! ? … or a line break; a text without any ending still counts as one.
    static func sentences(_ t: String) -> Int {
        let enders: Set<Character> = [".", "!", "?", "…", "\n"]
        return t.split(whereSeparator: { enders.contains($0) }).filter { words($0) > 0 }.count
    }
}

struct NoteDay: Identifiable, Hashable {
    let day: Date
    let notes: Int
    let words: Int
    var id: Date { day }
}

/// Everything shown on the Notes screen, computed from the notes alone.
struct NoteStats {
    var notes = 0, voice = 0, anchored = 0, words = 0, sentences = 0
    var seconds = 0.0
    var books = 0
    var today = (notes: 0, words: 0)
    var week = (notes: 0, words: 0)
    var days: [NoteDay] = []
    var perBook: [(id: String, title: String, notes: Int)] = []

    init(_ all: [TeoriaNote], now: Date = Date()) {
        notes = all.count
        voice = all.filter(\.hasVoice).count
        anchored = all.filter(\.anchored).count
        words = all.reduce(0) { $0 + $1.words }
        sentences = all.reduce(0) { $0 + $1.sentences }
        seconds = all.reduce(0) { $0 + ($1.seconds ?? 0) }
        let cal = Tarih.takvim
        let start = now.gunBasi
        let weekStart = start.gun(-6)
        var byDay: [Date: (Int, Int)] = [:]
        for n in all {
            let d = n.created.gunBasi
            let v = byDay[d] ?? (0, 0)
            byDay[d] = (v.0 + 1, v.1 + n.words)
            if cal.isDate(n.created, inSameDayAs: now) { today.notes += 1; today.words += n.words }
            if d >= weekStart { week.notes += 1; week.words += n.words }
        }
        days = (0..<14).reversed().map { i in
            let d = start.gun(-i)
            return NoteDay(day: d, notes: byDay[d]?.0 ?? 0, words: byDay[d]?.1 ?? 0)
        }
        var books: [String: (String, Int)] = [:]
        for n in all { books[n.book] = (n.bookTitle, (books[n.book]?.1 ?? 0) + 1) }
        self.books = books.count
        perBook = books.map { (id: $0.key, title: $0.value.0, notes: $0.value.1) }.sorted { $0.notes > $1.notes }
    }
}

@MainActor
final class NotesStore: ObservableObject {
    static let shared = NotesStore()
    @Published private(set) var notes: [TeoriaNote] = []        // live notes, newest first

    private var local: URL { Paylasim.kapsayici.appendingPathComponent("bookshelf", isDirectory: true) }
    private var mine: URL { local.appendingPathComponent("notes/\(Cihaz.ad).jsonl") }
    private var others: URL { local.appendingPathComponent("notes-others", isDirectory: true) }
    var audioDir: URL { local.appendingPathComponent("notes-audio", isDirectory: true) }

    private var syncing = false
    private var syncAgain = false
    private var syncTask: Task<Void, Never>?

    init() { load() }

    var stats: NoteStats { NoteStats(notes) }
    func notes(of book: String) -> [TeoriaNote] { notes.filter { $0.book == book } }

    // MARK: log

    private func load() {
        var files = [mine]
        files += ((try? FileManager.default.contentsOfDirectory(at: others, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "jsonl" }
        let dec = JSONDecoder()
        var latest: [String: TeoriaNote] = [:]
        for f in files {
            guard let t = try? String(contentsOf: f, encoding: .utf8) else { continue }
            for l in t.split(separator: "\n") {
                guard let n = try? dec.decode(TeoriaNote.self, from: Data(l.utf8)) else { continue }
                if let old = latest[n.id], old.stamp > n.stamp { continue }
                latest[n.id] = n
            }
        }
        notes = latest.values.filter { $0.deleted != true }.sorted { $0.stamp > $1.stamp }
    }

    private func append(_ n: TeoriaNote) {
        try? FileManager.default.createDirectory(at: mine.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard var line = try? JSONEncoder().encode(n) else { return }
        line.append(0x0A)
        if let h = try? FileHandle(forWritingTo: mine) { h.seekToEndOfFile(); h.write(line); try? h.close() }
        else { try? line.write(to: mine, options: .atomic) }
    }

    // MARK: writing

    /// A new note. `recording` is a file the voice recorder made; it is moved into the notes' audio folder.
    @discardableResult
    func add(book: String, title: String, anchor: NoteAnchor?, text: String, recording: URL?) -> TeoriaNote {
        let id = "n-" + UUID().uuidString.prefix(12).lowercased()
        var n = TeoriaNote(id: id, book: book, bookTitle: title, text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                           date: Tarih.isoSaat(Date()))
        apply(anchor, to: &n)
        attach(recording, to: &n)
        append(n)
        load()
        return n
    }

    func update(_ old: TeoriaNote, anchor: NoteAnchor?, text: String, recording: URL?) {
        var n = old
        n.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        apply(anchor, to: &n)
        if recording != nil { attach(recording, to: &n) }
        n.edited = Tarih.isoSaat(Date())
        append(n)
        load()
    }

    func delete(_ old: TeoriaNote) {
        var n = old
        n.deleted = true
        n.edited = Tarih.isoSaat(Date())
        append(n)
        if let a = old.audio { try? FileManager.default.removeItem(at: audioDir.appendingPathComponent(a)) }
        load()
    }

    private func apply(_ a: NoteAnchor?, to n: inout TeoriaNote) {
        n.ch = a?.ch; n.b = a?.b; n.s = a?.s; n.e = a?.e
        n.quote = a?.quote; n.chapterTitle = a?.chapterTitle
    }

    private func attach(_ file: URL?, to n: inout TeoriaNote) {
        guard let file, FileManager.default.fileExists(atPath: file.path) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: audioDir, withIntermediateDirectories: true)
        let name = "\(n.id).m4a"
        let dst = audioDir.appendingPathComponent(name)
        try? fm.removeItem(at: dst)
        guard (try? fm.copyItem(at: file, to: dst)) != nil else { return }
        try? fm.removeItem(at: file)
        n.audio = name
        n.seconds = (try? AVAudioPlayer(contentsOf: dst))?.duration
    }

    /// The recording's file on this device, or nil while it has not arrived from the vault yet.
    func audioURL(_ n: TeoriaNote) -> URL? {
        guard let a = n.audio else { return nil }
        let u = audioDir.appendingPathComponent(a)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    // MARK: vault

    /// New notes go up a few seconds after the last one.
    func scheduleSync(_ kasa: Kasa) {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !Task.isCancelled else { return }
            await self.sync(kasa)
        }
    }

    func sync(_ kasa: Kasa) async {
        if syncing { syncAgain = true; return }
        syncing = true
        defer { syncing = false }
        repeat {
            syncAgain = false
            await syncOnce(kasa)
        } while syncAgain
    }

    private func syncOnce(_ kasa: Kasa) async {
        let target = local, device = Cihaz.ad, audio = audioDir
        let ok: Bool? = await kasa.ile { kok in
            let fm = FileManager.default
            let lib = kok.appendingPathComponent("library", isDirectory: true)
            let logs = lib.appendingPathComponent("notes", isDirectory: true)
            let sounds = lib.appendingPathComponent("notes-audio", isDirectory: true)
            for d in [logs, sounds, audio, target.appendingPathComponent("notes-others"), target.appendingPathComponent("notes")] {
                try fm.createDirectory(at: d, withIntermediateDirectories: true)
            }
            // my log: union with the vault's copy (a reinstalled phone starts with an empty local log), both sides get it
            let mineLocal = target.appendingPathComponent("notes/\(device).jsonl")
            let mineVault = logs.appendingPathComponent("\(device).jsonl")
            if !fm.fileExists(atPath: mineVault.path) { Kasa.indir(mineVault) }
            let a = (try? String(contentsOf: mineLocal, encoding: .utf8))?.split(separator: "\n").map(String.init) ?? []
            let b = Kasa.koordineliOku(mineVault).flatMap { String(data: $0, encoding: .utf8) }?.split(separator: "\n").map(String.init) ?? []
            let known = Set(a)
            let merged = a + b.filter { !known.contains($0) }
            if !merged.isEmpty {
                let data = Data((merged.joined(separator: "\n") + "\n").utf8)
                if merged.count != a.count { try data.write(to: mineLocal, options: .atomic) }
                if merged.count != b.count { try Kasa.koordineliYaz(data, mineVault) }
            }
            // the other devices' logs down
            for f in (try? fm.contentsOfDirectory(atPath: logs.path)) ?? [] {
                if f.hasPrefix("."), f.hasSuffix(".icloud") {
                    try? fm.startDownloadingUbiquitousItem(at: logs.appendingPathComponent(String(f.dropFirst().dropLast(7)))); continue
                }
                guard f.hasSuffix(".jsonl"), f != "\(device).jsonl" else { continue }
                if let v = Kasa.koordineliOku(logs.appendingPathComponent(f)) {
                    try? v.write(to: target.appendingPathComponent("notes-others/\(f)"), options: .atomic)
                }
            }
            // voice files: mine up, the others' down
            for f in (try? fm.contentsOfDirectory(atPath: audio.path)) ?? [] where f.hasSuffix(".m4a") {
                let dst = sounds.appendingPathComponent(f)
                if !fm.fileExists(atPath: dst.path), let v = try? Data(contentsOf: audio.appendingPathComponent(f)) { try? Kasa.koordineliYaz(v, dst) }
            }
            for f in (try? fm.contentsOfDirectory(atPath: sounds.path)) ?? [] {
                if f.hasPrefix("."), f.hasSuffix(".icloud") {
                    try? fm.startDownloadingUbiquitousItem(at: sounds.appendingPathComponent(String(f.dropFirst().dropLast(7)))); continue
                }
                guard f.hasSuffix(".m4a"), !fm.fileExists(atPath: audio.appendingPathComponent(f).path) else { continue }
                if let v = Kasa.koordineliOku(sounds.appendingPathComponent(f)) { try? v.write(to: audio.appendingPathComponent(f), options: .atomic) }
            }
            return true
        }
        if ok == true { load() }
    }
}
