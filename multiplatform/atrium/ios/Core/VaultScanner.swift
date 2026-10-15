// Walks the vault folder and keeps an incremental index of every Markdown note.
// Unchanged files (same modification date and size) are never re-read.
import Foundation

struct IndexCache: Codable {
    var version = 2
    var records: [String: NoteRecord] = [:]
    var ledger: [String: DayLedger] = [:]
    var lastScan: Date?
}

struct ScanResult {
    var cache: IndexCache
    var changed: [String]
    var added: [String]
    var removed: [String]
    var pendingDownloads: Int
}

enum VaultScanner {
    static let skippedFolders: Set<String> = [".obsidian", ".git", ".trash", "_Backup", "_Karantina", "node_modules",
                                              ".smart-env", "__pycache__", ".claude", "graphify-out", ".build",
                                              "DerivedData", "xcuserdata"]

    static func scan(root: URL, previous: IndexCache, firstRun: Bool, progress: ((Int) -> Void)? = nil) -> ScanResult {
        var cache = previous
        let overrides = loadOverrides(root: root)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .creationDateKey, .fileSizeKey, .isDirectoryKey,
                                      .ubiquitousItemDownloadingStatusKey, .isUbiquitousItemKey]
        var seen = Set<String>()
        var changed: [String] = []
        var added: [String] = []
        var pending = 0
        let rootPath = root.standardizedFileURL.path
        let today = TurkishCalendar.dayKey(Date())
        var count = 0

        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants]) else {
            return ScanResult(cache: cache, changed: [], added: [], removed: [], pendingDownloads: 0)
        }
        for case let url as URL in walker {
            var fileName = url.lastPathComponent
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                if skippedFolders.contains(fileName) || fileName.hasSuffix(".xcodeproj") || fileName.hasSuffix(".xcassets") { walker.skipDescendants() }
                continue
            }
            // Legacy iCloud placeholder: ".Name.md.icloud"
            var placeholder = false
            if fileName.hasPrefix("."), fileName.hasSuffix(".md.icloud") {
                fileName = String(fileName.dropFirst().dropLast(7))
                placeholder = true
            } else if fileName.hasPrefix(".") {
                continue
            }
            guard fileName.lowercased().hasSuffix(".md") else { continue }
            let folderPath = url.deletingLastPathComponent().standardizedFileURL.path
            var relFolder = folderPath.count > rootPath.count ? String(folderPath.dropFirst(rootPath.count + 1)) : ""
            relFolder = TextTools.nfc(relFolder)
            let path = TextTools.nfc(relFolder.isEmpty ? fileName : relFolder + "/" + fileName)
            seen.insert(path)
            count += 1
            if count % 200 == 0 { progress?(count) }

            let modified = values?.contentModificationDate ?? Date.distantPast
            let created = values?.creationDate ?? modified
            let size = values?.fileSize ?? 0
            if let status = values?.ubiquitousItemDownloadingStatus, status != .current { placeholder = true }

            if let old = cache.records[path], abs(old.modified.timeIntervalSince(modified)) < 0.5, old.size == size, old.words != nil || placeholder {
                continue
            }
            var record = cache.records[path] ?? NoteRecord(path: path, modified: modified, created: created, size: size, words: nil,
                                                          origin: .unknown, kind: .note, journalDay: nil, links: [], discipline: nil)
            let previousWords = cache.records[path]?.words
            record.modified = modified
            record.created = min(created, modified)
            record.size = size
            if placeholder {
                pending += 1
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                let fm = Frontmatter(raw: nil, body: "", closed: true, fields: [])
                record.origin = Classifier.origin(path: path, fm: fm, overrides: overrides)
                record.kind = Classifier.kind(path: path, fm: fm)
                record.journalDay = record.kind == .journal ? Classifier.journalDay(path: path, fm: fm) : nil
            } else if let text = try? String(contentsOf: url, encoding: .utf8) {
                let fm = Frontmatter.split(text)
                record.origin = Classifier.origin(path: path, fm: fm, overrides: overrides)
                record.kind = Classifier.kind(path: path, fm: fm)
                record.journalDay = record.kind == .journal ? Classifier.journalDay(path: path, fm: fm) : nil
                record.words = TextTools.wordCount(fm.body)
                record.links = TextTools.wikilinks(fm.body)
                record.discipline = fm["disiplin"]?.text
            }
            let isNew = cache.records[path] == nil
            cache.records[path] = record
            if isNew { added.append(path) } else { changed.append(path) }

            // Ledger: only real changes seen after the first scan count as today's activity.
            if !firstRun, TurkishCalendar.dayKey(modified) == today {
                var day = cache.ledger[today] ?? DayLedger()
                day.touched.insert(path)
                if isNew { day.created.insert(path) }
                if let w = record.words {
                    let delta = max(0, w - (previousWords ?? 0))
                    day.wordsAdded += delta
                    if record.origin == .me || record.origin == .shared { day.wordsAddedMine += delta }
                }
                cache.ledger[today] = day
            }
        }
        let removed = cache.records.keys.filter { !seen.contains($0) }
        for p in removed { cache.records.removeValue(forKey: p) }
        cache.lastScan = Date()
        progress?(count)
        return ScanResult(cache: cache, changed: changed, added: added, removed: Array(removed), pendingDownloads: pending)
    }

    static func loadOverrides(root: URL) -> OriginOverrides {
        let url = root.appendingPathComponent("Artifacts/_vault/koken.json")
        guard let data = try? Data(contentsOf: url) else { return OriginOverrides() }
        return (try? JSONDecoder().decode(OriginOverrides.self, from: data)) ?? OriginOverrides()
    }
}
