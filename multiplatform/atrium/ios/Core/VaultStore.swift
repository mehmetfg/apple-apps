// The single source of app state: where the vault is, what the index says, and every read/write.
import Foundation
import SwiftUI

enum VaultError: LocalizedError {
    case noVault
    case conflict(current: String, modified: Date)
    case unreadable(String)
    case outsideVault

    var errorDescription: String? {
        switch self {
        case .noVault: return "Vault klasörü seçilmedi."
        case .conflict: return "Dosya bu arada başka yerde değişti."
        case .unreadable(let p): return "Okunamadı: \(p)"
        case .outsideVault: return "Vault dışına yazılmaz."
        }
    }
}

struct LoadedNote {
    var text: String
    var modified: Date
}

struct AreaSummary: Identifiable {
    var id: String { name }
    var name: String
    var notes: Int
    var words: Int
    var lastTouched: Date
    var origins: [Origin: Int]
    var touchedThisWeek: Int
}

@MainActor
final class VaultStore: ObservableObject {
    @Published private(set) var root: URL?
    @Published private(set) var records: [NoteRecord] = []
    @Published private(set) var ledger: [String: DayLedger] = [:]
    @Published private(set) var isScanning = false
    @Published private(set) var scanCount = 0
    @Published private(set) var pendingDownloads = 0
    @Published private(set) var lastScan: Date?
    @Published private(set) var sinceLastVisit: [NoteRecord] = []
    @Published private(set) var sparks: [SparkItem] = []
    @Published var catalog: AppCatalog?
    @Published var catalogError: String?
    @Published var message: String?

    private var byPath: [String: NoteRecord] = [:]
    private var byName: [String: [String]] = [:]
    private var backlinkIndex: [String: [String]] = [:]
    private var cache = IndexCache()
    private let previousVisit: Date

    static let catalogPath = "_araçlar/atrium/catalog/apps.json"
    static let sparkFolder = "05 - Notlar/Fikirler/Kıvılcım"
    static let ideasFolder = "05 - Notlar/Fikirler"
    static let journalTemplate = "Templates/Günlük.md"

    init() {
        let defaults = UserDefaults.standard
        previousVisit = (defaults.object(forKey: "lastVisit") as? Date) ?? Date().addingTimeInterval(-86_400)
        defaults.set(Date(), forKey: "lastVisit")
        loadCache()
        root = Self.resolveRoot()
    }

    var hasVault: Bool { root != nil }
    var lastVisit: Date { previousVisit }

    // MARK: - Vault location

    private static func resolveRoot() -> URL? {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-vaultPath"), i + 1 < args.count {
            return URL(fileURLWithPath: args[i + 1], isDirectory: true)
        }
        #if os(macOS)
        if let p = UserDefaults.standard.string(forKey: "vaultPath"), FileManager.default.fileExists(atPath: p) {
            return URL(fileURLWithPath: p, isDirectory: true)
        }
        let guess = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/iCloud~md~obsidian/Documents/Personel Data Management")
        return FileManager.default.fileExists(atPath: guess.path) ? guess : nil
        #else
        guard let data = UserDefaults.standard.data(forKey: "vaultBookmark") else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: "vaultBookmark")
        }
        return url
        #endif
    }

    func chooseVault(_ url: URL) {
        #if os(macOS)
        UserDefaults.standard.set(url.path, forKey: "vaultPath")
        #else
        _ = url.startAccessingSecurityScopedResource()
        if let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: "vaultBookmark")
        }
        #endif
        if root?.path != url.path { cache = IndexCache(); apply(cache) }
        root = url
        Task { await refresh() }
    }

    // MARK: - Index

    private var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Atrium", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("index.json")
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL), let c = try? JSONDecoder().decode(IndexCache.self, from: data), c.version == IndexCache().version else { return }
        cache = c
        apply(c)
    }

    private func apply(_ c: IndexCache) {
        records = c.records.values.sorted { $0.modified > $1.modified }
        byPath = c.records
        var names: [String: [String]] = [:]
        var back: [String: [String]] = [:]
        for r in records {
            names[TextTools.key(r.name), default: []].append(r.path)
            for l in r.links { back[l, default: []].append(r.path) }
        }
        byName = names
        backlinkIndex = back
        ledger = c.ledger
        lastScan = c.lastScan
        sinceLastVisit = records.filter { $0.modified > previousVisit }
    }

    func refresh() async {
        guard let root, !isScanning else { return }
        isScanning = true
        scanCount = 0
        let previous = cache
        let firstRun = previous.records.isEmpty
        let result = await Task.detached(priority: .userInitiated) { () -> ScanResult in
            VaultScanner.scan(root: root, previous: previous, firstRun: firstRun) { n in
                Task { @MainActor in self.scanCount = n }
            }
        }.value
        cache = result.cache
        apply(cache)
        pendingDownloads = result.pendingDownloads
        isScanning = false
        let snapshot = cache
        let url = cacheURL
        Task.detached(priority: .background) {
            if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: url, options: .atomic) }
        }
        loadSparks()
        loadCatalog()
        if pendingDownloads > 0 && !firstRun {
            message = "\(pendingDownloads) not iCloud'dan iniyor; birazdan yenile."
        }
    }

    // MARK: - Lookup

    func record(_ path: String) -> NoteRecord? { byPath[path] }

    func resolve(link: String, from source: String? = nil) -> String? {
        var target = link
        if let hash = target.firstIndex(where: { $0 == "#" || $0 == "|" || $0 == "^" }) { target = String(target[..<hash]) }
        target = TextTools.nfc(target.trimmingCharacters(in: .whitespaces))
        if target.lowercased().hasSuffix(".md") { target = String(target.dropLast(3)) }
        if target.contains("/"), byPath[target + ".md"] != nil { return target + ".md" }
        let name = target.split(separator: "/").last.map(String.init) ?? target
        guard let candidates = byName[TextTools.key(name)], !candidates.isEmpty else { return nil }
        if candidates.count == 1 { return candidates[0] }
        if let source {
            let folder = (source as NSString).deletingLastPathComponent
            if let near = candidates.first(where: { $0.hasPrefix(folder) }) { return near }
        }
        return candidates.sorted { $0.count < $1.count }.first
    }

    func backlinks(to path: String) -> [NoteRecord] {
        guard let r = byPath[path] else { return [] }
        return (backlinkIndex[TextTools.key(r.name)] ?? []).compactMap { byPath[$0] }.filter { $0.path != path }
            .sorted { $0.modified > $1.modified }
    }

    func children(of folder: String) -> (folders: [AreaSummary], notes: [NoteRecord]) {
        let prefix = folder.isEmpty ? "" : folder + "/"
        var groups: [String: [NoteRecord]] = [:]
        var notes: [NoteRecord] = []
        for r in records where r.path.hasPrefix(prefix) {
            let rest = r.path.dropFirst(prefix.count)
            if let slash = rest.firstIndex(of: "/") {
                groups[String(rest[..<slash]), default: []].append(r)
            } else {
                notes.append(r)
            }
        }
        let folders = groups.map { summary(name: $0.key, notes: $0.value) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return (folders, notes)
    }

    func areas() -> [AreaSummary] { children(of: "").folders }

    private func summary(name: String, notes: [NoteRecord]) -> AreaSummary {
        var origins: [Origin: Int] = [:]
        for n in notes { origins[n.origin, default: 0] += 1 }
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        return AreaSummary(name: name, notes: notes.count, words: notes.reduce(0) { $0 + ($1.words ?? 0) },
                           lastTouched: notes.map(\.modified).max() ?? .distantPast, origins: origins,
                           touchedThisWeek: notes.filter { $0.modified > weekAgo }.count)
    }

    func search(_ query: String) -> [NoteRecord] {
        let q = TextTools.key(query)
        guard !q.isEmpty else { return [] }
        return records.filter { TextTools.key($0.name).contains(q) || TextTools.key($0.folder).contains(q) }.prefix(200).map { $0 }
    }

    /// Full-text search over downloaded notes; runs off the main thread.
    func searchContents(_ query: String) async -> [(NoteRecord, String)] {
        guard let root else { return [] }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 3 else { return [] }
        let candidates = records.filter { $0.words != nil }
        return await Task.detached(priority: .userInitiated) {
            var out: [(NoteRecord, String)] = []
            for r in candidates {
                guard let text = try? String(contentsOf: root.appendingPathComponent(r.path), encoding: .utf8),
                      let range = text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) else { continue }
                let start = text.index(range.lowerBound, offsetBy: -60, limitedBy: text.startIndex) ?? text.startIndex
                let end = text.index(range.upperBound, offsetBy: 80, limitedBy: text.endIndex) ?? text.endIndex
                out.append((r, text[start..<end].replacingOccurrences(of: "\n", with: " ")))
                if out.count >= 80 { break }
            }
            return out
        }.value
    }

    // MARK: - Activity

    /// Notes touched on a day: the last modification date of each note, plus what the app itself saw that day.
    func touched(on day: String) -> [NoteRecord] {
        var paths = Set(records.filter { TurkishCalendar.dayKey($0.modified) == day }.map(\.path))
        paths.formUnion(ledger[day]?.touched ?? [])
        return paths.compactMap { byPath[$0] }.sorted { $0.modified > $1.modified }
    }

    func created(on day: String) -> [NoteRecord] {
        var paths = Set(records.filter { TurkishCalendar.dayKey($0.created) == day }.map(\.path))
        paths.formUnion(ledger[day]?.created ?? [])
        return paths.compactMap { byPath[$0] }
    }

    /// day key → number of notes touched, for the last `days` days.
    func activity(days: Int) -> [String: (all: Int, mine: Int)] {
        let start = TurkishCalendar.calendar.date(byAdding: .day, value: -days, to: TurkishCalendar.calendar.startOfDay(for: Date()))!
        var out: [String: (Int, Int)] = [:]
        var seen: [String: Set<String>] = [:]
        for r in records where r.modified >= start {
            let k = TurkishCalendar.dayKey(r.modified)
            seen[k, default: []].insert(r.path)
        }
        for (k, l) in ledger { seen[k, default: []].formUnion(l.touched) }
        for (k, paths) in seen {
            let mine = paths.filter { let o = byPath[$0]?.origin; return o == .me || o == .shared }.count
            out[k] = (paths.count, mine)
        }
        return out
    }

    func originCounts() -> [Origin: Int] {
        var out: [Origin: Int] = [:]
        for r in records { out[r.origin, default: 0] += 1 }
        return out
    }

    var totalWords: Int { records.reduce(0) { $0 + ($1.words ?? 0) } }

    func journal(for day: String) -> NoteRecord? {
        let standard = journalPath(for: TurkishCalendar.date(fromKey: day) ?? Date())
        if let r = byPath[standard] { return r }
        return records.first { $0.kind == .journal && $0.journalDay == day && !$0.path.hasPrefix("_Karantina") }
    }

    func recent(kind: NoteKind, limit: Int) -> [NoteRecord] {
        Array(records.filter { $0.kind == kind }.prefix(limit))
    }

    // MARK: - Files

    func url(for path: String) throws -> URL {
        guard let root else { throw VaultError.noVault }
        let url = root.appendingPathComponent(path).standardizedFileURL
        guard url.path.hasPrefix(root.standardizedFileURL.path) else { throw VaultError.outsideVault }
        return url
    }

    func read(_ path: String) async throws -> LoadedNote {
        let url = try url(for: path)
        return try await Task.detached(priority: .userInitiated) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            var result: Result<LoadedNote, Error> = .failure(VaultError.unreadable(path))
            var coordinationError: NSError?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { u in
                do {
                    let text = try String(contentsOf: u, encoding: .utf8)
                    let modified = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                    result = .success(LoadedNote(text: text, modified: modified))
                } catch { result = .failure(error) }
            }
            if let coordinationError { throw coordinationError }
            return try result.get()
        }.value
    }

    /// Writes a note. When `expected` is given and the file changed since then, throws `.conflict`.
    @discardableResult
    func write(_ path: String, text: String, expected: Date?, force: Bool = false) async throws -> Date {
        let url = try url(for: path)
        guard path.lowercased().hasSuffix(".md") || path.lowercased().hasSuffix(".json"),
              !path.hasPrefix(".obsidian") else { throw VaultError.outsideVault }
        let modified = try await Task.detached(priority: .userInitiated) { () throws -> Date in
            if !force, let expected,
               let current = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               abs(current.timeIntervalSince(expected)) > 0.01,
               let currentText = try? String(contentsOf: url, encoding: .utf8), currentText != text {
                throw VaultError.conflict(current: currentText, modified: current)
            }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var failure: Error?
            var coordinationError: NSError?
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { u in
                do { try text.data(using: .utf8)!.write(to: u, options: .atomic) } catch { failure = error }
            }
            if let e = coordinationError ?? failure { throw e }
            return (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        }.value
        noteWritten(path: path, text: text, modified: modified)
        return modified
    }

    /// Updates the index right away so the change shows everywhere without a rescan.
    private func noteWritten(path: String, text: String, modified: Date) {
        guard path.hasSuffix(".md") else { return }
        let fm = Frontmatter.split(text)
        let isNew = cache.records[path] == nil
        let oldWords = cache.records[path]?.words ?? 0
        var r = cache.records[path] ?? NoteRecord(path: path, modified: modified, created: modified, size: 0, words: nil,
                                                  origin: .me, kind: .note, journalDay: nil, links: [], discipline: nil)
        r.modified = modified
        r.size = text.utf8.count
        r.origin = Classifier.origin(path: path, fm: fm, overrides: OriginOverrides())
        r.kind = Classifier.kind(path: path, fm: fm)
        r.journalDay = r.kind == .journal ? Classifier.journalDay(path: path, fm: fm) : nil
        r.words = TextTools.wordCount(fm.body)
        r.links = TextTools.wikilinks(fm.body)
        r.discipline = fm["disiplin"]?.text
        cache.records[path] = r
        let today = TurkishCalendar.dayKey(Date())
        var day = cache.ledger[today] ?? DayLedger()
        day.touched.insert(path)
        if isNew { day.created.insert(path) }
        let delta = max(0, (r.words ?? 0) - oldWords)
        day.wordsAdded += delta
        if r.origin == .me || r.origin == .shared { day.wordsAddedMine += delta }
        cache.ledger[today] = day
        apply(cache)
        let snapshot = cache
        let url = cacheURL
        Task.detached(priority: .background) {
            if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: url, options: .atomic) }
        }
    }

    // MARK: - Creating notes

    func journalPath(for date: Date) -> String {
        let c = TurkishCalendar.calendar.dateComponents([.year, .month], from: date)
        return String(format: "%@/%04d/%02d/%@.md", Classifier.journalRoot, c.year!, c.month!, TurkishCalendar.journalTitle(date))
    }

    func folder(for kind: NoteKind) -> String {
        switch kind {
        case .journal: return Classifier.journalRoot
        case .idea: return Self.ideasFolder
        case .essay: return "Yazarlık/Denemeler"
        case .article: return "Yazarlık/Makaleler"
        case .poem: return "07 - Şiirler"
        case .book: return "04 - Books"
        case .concept: return "05 - Notlar/Kavramlar"
        case .note: return "Inbox"
        }
    }

    private func freePath(_ path: String) -> String {
        guard byPath[path] != nil || (try? url(for: path)).map({ FileManager.default.fileExists(atPath: $0.path) }) == true else { return path }
        let base = String(path.dropLast(3))
        for i in 2...99 {
            let p = "\(base) \(i).md"
            if byPath[p] == nil, let u = try? url(for: p), !FileManager.default.fileExists(atPath: u.path) { return p }
        }
        return base + " \(UUID().uuidString.prefix(4)).md"
    }

    /// Opens today's journal, creating it from the vault template when missing. Returns its path.
    func ensureJournal(for date: Date = Date()) async throws -> String {
        let day = TurkishCalendar.dayKey(date)
        if let existing = journal(for: day) { return existing.path }
        let path = journalPath(for: date)
        if let u = try? url(for: path), FileManager.default.fileExists(atPath: u.path) { return path }
        let time = Self.timeString(Date())
        var template = (try? await read(Self.journalTemplate).text) ?? "---\n---\n\n{{time}}\n{{title}}\n\n"
        template = template.replacingOccurrences(of: "{{time}}", with: time)
            .replacingOccurrences(of: "{{title}}", with: TurkishCalendar.journalTitle(date))
            .replacingOccurrences(of: "{{date}}", with: day)
        template = Frontmatter.setting("journal", to: "Kişisel Günlük", in: template)
        template = Frontmatter.setting("Günlük Tarihi", to: day, in: template)
        template = Frontmatter.setting("yazan", to: "ben", in: template)
        try await write(path, text: template, expected: nil)
        return path
    }

    func appendToJournal(_ entry: String) async throws -> String {
        let path = try await ensureJournal()
        let current = try await read(path)
        let text = current.text.trimmingCharacters(in: .newlines) + "\n\n" + Self.timeString(Date()) + "\n" + entry.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        try await write(path, text: text, expected: current.modified)
        return path
    }

    func create(kind: NoteKind, title: String, body: String, folder: String?, discipline: String?) async throws -> String {
        if kind == .journal {
            let path = try await ensureJournal()
            if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { _ = try await appendToJournal(body) }
            return path
        }
        let now = Date()
        let day = TurkishCalendar.dayKey(now)
        let time = Self.timeString(now)
        var name = TextTools.safeFileName(title)
        if name.isEmpty {
            switch kind {
            case .idea:
                let words = body.split(whereSeparator: { $0.isWhitespace }).prefix(7).joined(separator: " ")
                name = TextTools.safeFileName(words).isEmpty ? "fikir" : TextTools.safeFileName(words)
            case .poem:
                let d = TurkishCalendar.calendar.component(.day, from: now)
                name = String(format: "Şiir - %02d %@ %d, %@", d, TurkishCalendar.monthName(now),
                              TurkishCalendar.calendar.component(.year, from: now), TurkishCalendar.weekdayName(now))
            default:
                name = "Başlıksız " + kind.label.lowercased()
            }
        }
        let fileName = kind == .idea ? "\(day) \(time.replacingOccurrences(of: ":", with: "")) \(name)" : name
        let target = (kind == .note ? (folder?.isEmpty == false ? folder! : "Inbox") : self.folder(for: kind))
        let path = freePath(TextTools.nfc("\(target)/\(fileName).md"))
        var lines = ["tür: \(kind.vaultType)", "yazan: ben", "tarih: \(day)", "saat: \"\(time)\""]
        if kind == .idea { lines.append("durum: ham") }
        if kind == .essay || kind == .article { lines.append("durum: taslak") }
        if let discipline, !discipline.isEmpty { lines.append("disiplin: \(discipline)") }
        lines.append("etiketler: []")
        let heading = (kind == .essay || kind == .article) && !title.isEmpty ? "# \(title)\n\n" : ""
        let text = "---\n" + lines.joined(separator: "\n") + "\n---\n\n" + heading + body + (body.isEmpty ? "" : "\n")
        try await write(path, text: text, expected: nil)
        return path
    }

    nonisolated static func timeString(_ d: Date) -> String {
        let c = TurkishCalendar.calendar.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour!, c.minute!)
    }

    // MARK: - Kıvılcım

    func loadSparks() {
        guard let root else { return }
        let url = root.appendingPathComponent(Self.sparkFolder + "/dizin.json")
        Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url), let index = try? JSONDecoder().decode(SparkIndex.self, from: data) else { return }
            let items = index.items.sorted { $0.date > $1.date }
            await MainActor.run { self.sparks = items }
        }
    }

    // MARK: - App catalog

    func loadCatalog() {
        guard let root else { return }
        let url = root.appendingPathComponent(Self.catalogPath)
        do {
            let data = try Data(contentsOf: url)
            catalog = try JSONDecoder().decode(AppCatalog.self, from: data)
            catalogError = nil
        } catch {
            catalogError = "Katalog okunamadı: \(error.localizedDescription)"
        }
    }

    func saveCatalog(_ c: AppCatalog) async {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(c), let text = String(data: data, encoding: .utf8) else { return }
        do {
            try await write(Self.catalogPath, text: text + "\n", expected: nil, force: true)
            catalog = c
        } catch {
            message = "Katalog yazılamadı: \(error.localizedDescription)"
        }
    }

    /// Newest change inside an app's source folder (Markdown notes only — what the index knows).
    func lastActivity(source: String?) -> Date? {
        guard let source, !source.isEmpty else { return nil }
        let prefix = source.hasSuffix("/") ? source : source + "/"
        return records.first { $0.path.hasPrefix(prefix) }?.modified
    }
}
