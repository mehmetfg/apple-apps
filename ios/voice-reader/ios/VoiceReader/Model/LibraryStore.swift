// The library on disk:
//   Application Support/VoiceReader/library.json        every DocumentRecord + the folder names
//   Application Support/VoiceReader/docs/<id>/content.json   the readable text, headings, pages
//   Application Support/VoiceReader/docs/<id>/source.<ext>   the original file, kept for later re-import
//   Application Support/VoiceReader/places.json          the reading place of every document, written within a
//                                                        second of each move (also in UserDefaults); it wins over
//                                                        library.json when newer, so no kill, crash or update loses it
import Foundation
import Observation

@MainActor
@Observable
final class LibraryStore {
    private(set) var documents: [DocumentRecord] = []
    private(set) var folders: [String] = []

    @ObservationIgnored private let root: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var contentCache: [UUID: DocumentContent] = [:]
    @ObservationIgnored private var places: [String: Place] = [:]
    @ObservationIgnored private var placeWritePending = false

    /// Where a document is being read, kept apart from the library so it is written at once and on its own.
    struct Place: Codable { var position: Int; var at: Date }

    private struct LibraryFile: Codable {
        var documents: [DocumentRecord]
        var folders: [String]
        var dropped = 0                                 // records that could not be read (never written back)

        init(documents: [DocumentRecord], folders: [String]) { self.documents = documents; self.folders = folders }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let all = try c.decode([Lossy<DocumentRecord>].self, forKey: .documents)
            documents = all.compactMap(\.value)
            dropped = all.count - documents.count
            folders = (try? c.decodeIfPresent([String].self, forKey: .folders)) ?? nil ?? []
        }

        private enum CodingKeys: String, CodingKey { case documents, folders }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(documents, forKey: .documents)
            try c.encode(folders, forKey: .folders)
        }
    }

    init(root: URL? = nil) {
        let base = root ?? URL.applicationSupportDirectory.appending(path: "VoiceReader", directoryHint: .isDirectory)
        // libraries from before the rename lived in "Okur": move once, keep everything
        let legacy = URL.applicationSupportDirectory.appending(path: "Okur", directoryHint: .isDirectory)
        if root == nil, !FileManager.default.fileExists(atPath: base.path), FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.moveItem(at: legacy, to: base)
        }
        self.root = base
        try? FileManager.default.createDirectory(at: base.appending(path: "docs"), withIntermediateDirectories: true)
        // The reading positions and marks live in this one file, so it is never lost to an update: a file this
        // version cannot fully read is kept aside (never written over), and the copy from the last good launch is
        // used instead.
        let fm = FileManager.default
        if let data = try? Data(contentsOf: libraryURL) {
            let file = try? JSONDecoder().decode(LibraryFile.self, from: data)
            if let file, file.dropped == 0 {
                documents = file.documents
                folders = file.folders
                try? data.write(to: backupURL, options: .atomic)
            } else {
                let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
                try? fm.copyItem(at: libraryURL, to: base.appending(path: "library-unread-\(stamp).json"))
                let backup = (try? Data(contentsOf: backupURL)).flatMap { try? JSONDecoder().decode(LibraryFile.self, from: $0) }
                // what this file still holds wins; a record it lost comes back from the last good launch
                var docs = file?.documents ?? []
                for d in backup?.documents ?? [] where !docs.contains(where: { $0.id == d.id }) { docs.append(d) }
                documents = docs
                folders = Array(Set((file?.folders ?? []) + (backup?.folders ?? []))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            }
        } else if let data = try? Data(contentsOf: backupURL), let file = try? JSONDecoder().decode(LibraryFile.self, from: data) {
            documents = file.documents                  // the main file vanished: the last good launch's copy
            folders = file.folders
        }
        restorePlaces()
    }

    // MARK: reading places

    private var placesURL: URL { root.appending(path: "places.json") }
    private static let placesKey = "places.v1"

    /// The newest place wins: library.json may be minutes older than the journal (or come from a backup).
    private func restorePlaces() {
        let fromFile = (try? Data(contentsOf: placesURL)).flatMap { try? JSONDecoder().decode([String: Place].self, from: $0) } ?? [:]
        let fromDefaults = UserDefaults.standard.data(forKey: Self.placesKey).flatMap { try? JSONDecoder().decode([String: Place].self, from: $0) } ?? [:]
        places = fromFile.merging(fromDefaults) { $0.at >= $1.at ? $0 : $1 }
        var changed = false
        for i in documents.indices {
            guard let p = places[documents[i].id.uuidString], p.at > (documents[i].positionAt ?? .distantPast) else { continue }
            documents[i].position = min(max(0, p.position), documents[i].length)
            documents[i].positionAt = p.at
            changed = true
        }
        if changed { saveSoon() }
    }

    /// The speech cursor moved (or the reader moved it on purpose). The journal is written within a second,
    /// never postponed by the next move; the library follows on its own schedule. The library list itself (which
    /// every screen observes) changes only when the whole per cent changes, on a jump, or at the start or the end:
    /// moving it every two seconds redrew the reader and the library while reading (2026-10-28). `document(_:)`
    /// gives the exact place from the journal meanwhile.
    func setPosition(_ id: UUID, _ offset: Int, at: Date = .now) {
        places[id.uuidString] = Place(position: offset, at: at)
        if let d = documents.first(where: { $0.id == id }) {
            let step = max(1, d.length / 100)
            if d.position == 0 || offset == 0 || offset >= d.length || offset / step != d.position / step || abs(offset - d.position) > step {
                update(id) { $0.position = offset; $0.positionAt = at }
            }
        }
        guard !placeWritePending else { return }
        placeWritePending = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.writePlaces()
        }
    }

    func writePlaces() {
        placeWritePending = false
        guard let data = try? JSONEncoder().encode(places) else { return }
        UserDefaults.standard.set(data, forKey: Self.placesKey)
        let url = placesURL
        Self.writer.async { try? data.write(to: url, options: .atomic) }
    }

    private var backupURL: URL { root.appending(path: "library.backup.json") }

    var isEmpty: Bool { documents.isEmpty }
    private var libraryURL: URL { root.appending(path: "library.json") }
    private func folderURL(_ id: UUID) -> URL { root.appending(path: "docs/\(id.uuidString)", directoryHint: .isDirectory) }

    /// The record, with the exact place from the journal when that is newer than the list's (see `setPosition`).
    func document(_ id: UUID) -> DocumentRecord? {
        guard var d = documents.first(where: { $0.id == id }) else { return nil }
        if let p = places[id.uuidString], p.at > (d.positionAt ?? .distantPast) {
            d.position = min(max(0, p.position), d.length)
            d.positionAt = p.at
        }
        return d
    }

    // MARK: adding and removing

    @discardableResult
    func add(_ imported: ImportedDocument, original: URL?) throws -> DocumentRecord {
        let record = DocumentRecord(
            title: imported.title, author: imported.author, format: imported.format,
            sourceName: imported.sourceName, length: imported.content.text.utf16.count,
            wordCount: imported.wordCount, language: imported.language)
        let dir = folderURL(record.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(imported.content).write(to: dir.appending(path: "content.json"), options: .atomic)
        if let cover = imported.cover { try? cover.write(to: dir.appending(path: "cover.jpg"), options: .atomic) }
        if let original {
            let ext = original.pathExtension.isEmpty ? "dat" : original.pathExtension
            try? FileManager.default.copyItem(at: original, to: dir.appending(path: "source.\(ext)"))
        }
        contentCache[record.id] = imported.content
        documents.insert(record, at: 0)
        saveSoon()
        return record
    }

    /// A document that arrived from another device or from sync: same id, its content and cover as given.
    func insert(_ record: DocumentRecord, content: DocumentContent, cover: Data?) throws {
        guard document(record.id) == nil else { return }
        let dir = folderURL(record.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(content).write(to: dir.appending(path: "content.json"), options: .atomic)
        if let cover { try? cover.write(to: dir.appending(path: "cover.jpg"), options: .atomic); coverVersion += 1 }
        contentCache[record.id] = content
        documents.insert(record, at: 0)
        saveSoon()
    }

    /// Replace a document's text (pages appended by sync); the record's length follows.
    func replaceContent(_ id: UUID, with content: DocumentContent, wordCount: Int) {
        let url = folderURL(id).appending(path: "content.json")
        try? JSONEncoder().encode(content).write(to: url, options: .atomic)
        contentCache[id] = content
        update(id) { $0.length = content.text.utf16.count; $0.wordCount = wordCount }
    }

    /// The document's Mac-rendered audio (Voice Reader Studio), if any.
    func studioFolder(_ id: UUID) -> URL { folderURL(id).appending(path: "studio", directoryHint: .isDirectory) }
    func studioPack(_ id: UUID) -> StudioPack? { StudioPack.load(studioFolder(id)) }

    /// Put a studio pack in place for a document (replacing an older render of it).
    func installStudio(_ id: UUID, from pack: URL) throws {
        let dest = studioFolder(id)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.createDirectory(at: folderURL(id), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: pack, to: dest)
    }

    func contentURL(_ id: UUID) -> URL { folderURL(id).appending(path: "content.json") }
    func contentData(_ id: UUID) -> Data? { try? Data(contentsOf: folderURL(id).appending(path: "content.json")) }
    func coverData(_ id: UUID) -> Data? { try? Data(contentsOf: coverURL(id)) }

    func delete(_ ids: some Sequence<UUID>) {
        let set = Set(ids)
        for id in set {
            try? FileManager.default.removeItem(at: folderURL(id))
            contentCache[id] = nil
        }
        documents.removeAll { set.contains($0.id) }
        saveSoon()
    }

    // MARK: covers

    func coverURL(_ id: UUID) -> URL { folderURL(id).appending(path: "cover.jpg") }

    /// Documents imported before covers existed: take the cover from the kept source file (EPUB, PDF), once.
    func backfillCovers() async {
        let pending = documents.filter { ($0.format == .epub || $0.format == .pdf) && !FileManager.default.fileExists(atPath: coverURL($0.id).path) }
        for d in pending {
            let dir = folderURL(d.id)
            let source = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?.first { $0.lastPathComponent.hasPrefix("source.") }
            guard let source else { continue }
            let target = coverURL(d.id)
            let made = await Task.detached(priority: .utility) { () -> Bool in
                guard let doc = try? DocumentImporter.importFile(at: source), let c = doc.cover else { return false }
                return (try? c.write(to: target, options: .atomic)) != nil
            }.value
            if made { coverVersion += 1 }
        }
    }

    /// Bumped when a cover appears, so cover views reload.
    var coverVersion = 0

    // MARK: reading

    /// The document's text; read from disk off the main thread the first time.
    func content(for id: UUID) async -> DocumentContent? {
        if let c = contentCache[id] { return c }
        let url = folderURL(id).appending(path: "content.json")
        let loaded = await Task.detached(priority: .userInitiated) { () -> DocumentContent? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(DocumentContent.self, from: data)
        }.value
        if let loaded { contentCache[id] = loaded }
        return loaded
    }

    // MARK: editing

    func update(_ id: UUID, save: Bool = true, _ change: (inout DocumentRecord) -> Void) {
        guard let i = documents.firstIndex(where: { $0.id == id }) else { return }
        change(&documents[i])
        if save { saveSoon() }
    }

    func addFolder(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, !folders.contains(n) else { return }
        folders.append(n)
        folders.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        saveSoon()
    }

    func removeFolder(_ name: String) {
        folders.removeAll { $0 == name }
        for i in documents.indices where documents[i].folder == name { documents[i].folder = nil }
        saveSoon()
    }

    func renameFolder(_ old: String, to new: String) {
        let n = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, let i = folders.firstIndex(of: old), !folders.contains(n) else { return }
        folders[i] = n
        for j in documents.indices where documents[j].folder == old { documents[j].folder = n }
        saveSoon()
    }

    // MARK: saving

    /// Writes are coalesced: the speech cursor moves many times a minute. The library (every document with its
    /// highlights) is encoded and written on a background queue, so reading never waits for the disk.
    /// A save already waiting is kept, not restarted: restarting it on every move meant that while a book was
    /// being read the library was never written, and a kill (iOS, an update) took the place back by minutes.
    func saveSoon() {
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            self.saveTask = nil
            let file = LibraryFile(documents: self.documents, folders: self.folders)
            let url = self.libraryURL
            Self.writer.async {
                guard let data = try? JSONEncoder().encode(file) else { return }
                try? data.write(to: url, options: .atomic)
            }
        }
    }
    private static let writer = DispatchQueue(label: "voice-reader.library-save", qos: .utility)

    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        writePlaces()
        let file = LibraryFile(documents: documents, folders: folders)
        guard let data = try? JSONEncoder().encode(file) else { return }
        Self.writer.sync { try? data.write(to: libraryURL, options: .atomic) }    // after any background write
    }
}
