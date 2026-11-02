// A copy of where you are and what you marked, written into the PDM vault (Obsidian's iCloud folder), so the Mac,
// the PDM hub and Claude see it without the app's own iCloud container (which macOS only shows when an app on the
// Mac uses it). Written, never read: the app's own sync stays the source.
//
//   <vault>/_araçlar/voice-reader/durum/
//     State/<device>.json        where each document was left (same shape as the iCloud State file)
//     Events/<device>.jsonl      highlights, notes, bookmarks… (same lines as the iCloud Events file)
//     Library/<id>.json          title, author, folder, length of each document
//     Texts/<id>.json            the readable text (content.json), for Teoria on the Mac; written once per document
//     Notes/<device>.jsonl       written and voice notes (NoteStore's log, copied whole)
//     NoteAudio/<id>.m4a         the voice notes' recordings
//
// The vault folder is picked once (Ayarlar › PDM vault); iOS keeps the permission as a security-scoped bookmark.
import Foundation

actor VaultMirror {
    static let shared = VaultMirror()
    private static let bookmarkKey = "vault.bookmark"
    nonisolated static let relative = "_araçlar/voice-reader/durum"

    private var vault: URL?
    private let fm = FileManager.default

    /// The vault root from the saved bookmark, with access started (kept for the app's lifetime).
    func connect() -> URL? {
        if let vault { return vault }
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        if stale, let fresh = try? url.bookmarkData() { UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey) }
        let root = UserDefaults.standard.string(forKey: "vault.inner").map { url.appending(path: $0) } ?? url
        vault = root
        return root
    }

    /// Save a folder the user picked: the vault root, or a folder that holds it (Obsidian's Documents). The root is
    /// known by its own files (_bus, _araçlar, CLAUDE.md), also when iCloud shows them only as placeholders
    /// (".name.icloud"). Returns an error text, or nil when saved. The outcome goes to Library/sync-status.txt too.
    func choose(_ picked: URL) -> String? {
        let ok = picked.startAccessingSecurityScopedResource()
        func names(_ u: URL) -> Set<String> {
            let items = (try? fm.contentsOfDirectory(atPath: u.path)) ?? []
            return Set(items.map { n in n.hasPrefix(".") && n.hasSuffix(".icloud") ? String(n.dropFirst().dropLast(7)) : n })
        }
        func isRoot(_ u: URL) -> Bool { !names(u).isDisjoint(with: ["_bus", "_araçlar", "CLAUDE.md", "00 - Philosophy"]) }
        var root: URL?
        if isRoot(picked) { root = picked }
        else {
            let inner = picked.appending(path: "Personel Data Management")
            if fm.fileExists(atPath: inner.path), isRoot(inner) || names(inner).isEmpty == false { root = inner }
        }
        guard let root else {
            let seen = names(picked).sorted().prefix(6).joined(separator: ", ")
            if ok { picked.stopAccessingSecurityScopedResource() }
            let msg = "“\(picked.lastPathComponent)” vault'un kökü değil (içinde: \(seen.isEmpty ? "boş ya da okunamadı" : seen)). Dosyalar › iCloud Drive › Obsidian › Personel Data Management klasörünü seç."
            UserDefaults.standard.set(msg, forKey: "vault.status")
            return msg
        }
        // the bookmark is made on the folder the user granted; the vault root is remembered as a path inside it
        guard let data = try? picked.bookmarkData() else {
            UserDefaults.standard.set("izin kaydedilemedi: \(picked.path)", forKey: "vault.status")
            return "Klasör izni kaydedilemedi."
        }
        UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        UserDefaults.standard.set(root == picked ? nil : "Personel Data Management", forKey: "vault.inner")
        UserDefaults.standard.removeObject(forKey: "vault.seeded")
        UserDefaults.standard.set("bağlı: \(root.lastPathComponent)", forKey: "vault.status")
        vault = root
        return nil
    }

    func forget() {
        vault?.stopAccessingSecurityScopedResource()
        vault = nil
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
    }

    var path: String? { connect().map { $0.lastPathComponent + "/" + Self.relative } }

    private func dir(_ sub: String) -> URL? {
        guard let v = connect() else { return nil }
        let d = v.appending(path: Self.relative).appending(path: sub)
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private func write(_ data: Data, to url: URL) {
        var err: NSError?
        var failure: String?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &err) { u in
            do { try data.write(to: u, options: .atomic) } catch { failure = error.localizedDescription }
        }
        if let f = failure ?? err?.localizedDescription {
            UserDefaults.standard.set("yazılamadı \(url.lastPathComponent): \(f)", forKey: "vault.status")
        } else {
            UserDefaults.standard.set("yazıldı \(Date.now.formatted(date: .omitted, time: .shortened))", forKey: "vault.status")
        }
    }

    // MARK: writing

    func writeState(_ s: DeviceState, device: String) {
        guard let d = dir("State"), let data = try? JSONEncoder().encode(s) else { return }
        write(data, to: d.appending(path: "\(device).json"))
    }

    func append(_ events: [SyncEvent], device: String) {
        guard !events.isEmpty, let d = dir("Events") else { return }
        let url = d.appending(path: "\(device).jsonl")
        var data = (try? Data(contentsOf: url)) ?? Data()
        let enc = JSONEncoder()
        for e in events { if let line = try? enc.encode(e) { data.append(line); data.append(0x0A) } }
        write(data, to: url)
    }

    struct Meta: Codable { var id: UUID; var title: String; var author: String?; var folder: String?; var length: Int; var language: String? }

    func writeMeta(_ docs: [Meta]) {
        guard let d = dir("Library") else { return }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        for m in docs {
            let url = d.appending(path: "\(m.id.uuidString).json")
            guard let data = try? enc.encode(m) else { continue }
            if (try? Data(contentsOf: url)) != data { write(data, to: url) }
        }
    }

    /// Documents whose text is not in the vault copy yet.
    func missingTexts(_ ids: [UUID]) -> [UUID] {
        guard let d = dir("Texts") else { return [] }
        return ids.filter { !fm.fileExists(atPath: d.appending(path: "\($0.uuidString).json").path) }
    }

    /// The listening log (Listening/<device>.json), for the Mac and the PDM hub.
    func writeListening(_ data: Data, device: String) {
        guard let d = dir("Listening") else { return }
        write(data, to: d.appending(path: "\(device).json"))
    }

    /// A ride or walk (Workouts/<id>.json): route, distance, climb, steps, calories.
    func writeWorkout(_ data: Data, id: UUID) {
        guard let d = dir("Workouts") else { return }
        write(data, to: d.appending(path: "\(id.uuidString).json"))
    }

    /// Teoria's insight for a book (core idea, key sentences with why they matter, chapter summaries), found by title
    /// in `00 - Philosophy/_projects/teoria/library/index.json`. Nil when the vault or the book is not there.
    func teoriaInsight(title: String) -> Data? {
        guard let v = connect() else { return nil }
        let lib = v.appending(path: "00 - Philosophy/_projects/teoria/library")
        guard let data = try? Data(contentsOf: lib.appending(path: "index.json")),
              let index = try? JSONDecoder().decode(TeoriaIndex.self, from: data) else { return nil }
        let want = Self.titleKey(title)
        guard want.count >= 6 else { return nil }
        let best = index.books.filter { $0.insight == true }
            .map { ($0, Self.commonPrefix(Self.titleKey($0.title), want)) }
            .max { $0.1 < $1.1 }
        guard let (book, n) = best, n >= min(14, want.count) else { return nil }
        return try? Data(contentsOf: lib.appending(path: "insights/\(book.id).json"))
    }

    private struct TeoriaIndex: Decodable {
        struct Book: Decodable { var id: String; var title: String; var insight: Bool? }
        var books: [Book]
    }

    /// Letters and digits only, lower case: "Felsefe 04 — Arkhe" and "Felsefe 04 · Arkhe" are the same book.
    static func titleKey(_ s: String) -> String {
        String(s.lowercased(with: Locale(identifier: "tr")).unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    static func commonPrefix(_ a: String, _ b: String) -> Int {
        zip(a, b).prefix { $0 == $1 }.count
    }

    func writeText(_ data: Data, id: UUID) {
        guard let d = dir("Texts") else { return }
        write(data, to: d.appending(path: "\(id.uuidString).json"))
    }

    func mirrorNotes(log: URL, audioDir: URL, device: String) {
        guard let d = dir("Notes"), let a = dir("NoteAudio") else { return }
        if let data = try? Data(contentsOf: log), (try? Data(contentsOf: d.appending(path: "\(device).jsonl"))) != data {
            write(data, to: d.appending(path: "\(device).jsonl"))
        }
        for f in (try? fm.contentsOfDirectory(atPath: audioDir.path)) ?? [] where f.hasSuffix(".m4a") {
            let dst = a.appending(path: f)
            if !fm.fileExists(atPath: dst.path), let data = try? Data(contentsOf: audioDir.appending(path: f)) { write(data, to: dst) }
        }
    }

    /// First time with this vault: every highlight and bookmark already in the library goes in as events, so the
    /// vault copy starts complete.
    func seedIfNeeded(_ docs: [DocumentRecord], device: String) {
        guard connect() != nil, !UserDefaults.standard.bool(forKey: "vault.seeded") else { return }
        var events: [SyncEvent] = []
        for d in docs {
            for h in d.highlights { events.append(SyncEvent(at: h.createdAt, kind: .highlightAdd, doc: d.id, highlight: h)) }
            for b in d.bookmarks { events.append(SyncEvent(at: b.createdAt, kind: .bookmarkAdd, doc: d.id, bookmark: b)) }
        }
        append(events, device: device)
        UserDefaults.standard.set(true, forKey: "vault.seeded")
    }
}
