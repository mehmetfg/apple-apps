// iCloud sync. One folder, iCloud Drive › Voice Reader, shared by the iPhone app, the Mac app and Claude:
//
//   Loader/                      drop files here (subfolder = library folder: Loader/Felsefe/x.epub); the first
//                                device that sees a file imports it and moves it to Loader/Alındı/
//   Library/<id>/meta.json       the document (title, author, format, language, added)
//   Library/<id>/content.json    the readable text — written once, never changed
//   Library/<id>/cover.jpg
//   Library/<id>/parts/001.md…   pages appended later (Claude); every device appends them in order to the end of
//                                the text, so earlier positions and highlights stay valid
//   State/<device>.json          where each document was left on that device, with the time; newest wins
//   Events/<device>.jsonl        highlights, notes, bookmarks, folders, labels, titles, deletions — append-only
//
// Every file has one writer (its device), so iCloud never has to resolve a conflict.
import Foundation

struct SyncEvent: Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case highlightAdd, highlightRemove, highlightNote, bookmarkAdd, bookmarkRemove
        case docFolder, docFlag, docTitle, docDelete, folderAdd, folderRemove, folderRename
    }
    var id = UUID()
    var at = Date()
    var kind: Kind
    var doc: UUID?
    var highlight: Highlight?
    var bookmark: Bookmark?
    var ref: UUID?
    var text: String?
    var text2: String?
}

struct DocumentMeta: Codable, Sendable {
    var id: UUID
    var title: String
    var author: String?
    var format: DocumentFormat
    var sourceName: String
    var language: String?
    var addedAt: Date
    var folder: String?
}

struct DeviceState: Codable, Sendable {
    /// `length` and `title` are for readers outside the app (the Mac hub, Claude): percent = position / length.
    struct Entry: Codable, Sendable { var position: Int; var opened: Date?; var at: Date; var length: Int?; var title: String? }
    var docs: [UUID: Entry] = [:]
}

/// Everything sync touches on disk; runs off the main thread.
actor CloudFiles {
    let root: URL
    let device: String
    private let fm = FileManager.default

    init(root: URL, device: String) {
        self.root = root
        self.device = device
        for d in ["Loader", "Loader/Alındı", "Library", "State", "Events"] {
            try? FileManager.default.createDirectory(at: root.appending(path: d), withIntermediateDirectories: true)
        }
    }

    // MARK: reading (iCloud may hold only a placeholder: ask for it and try again next pass)

    private func ready(_ url: URL) -> Bool {
        let v = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey, .isUbiquitousItemKey])
        guard v?.isUbiquitousItem == true else { return fm.fileExists(atPath: url.path) }
        if v?.ubiquitousItemDownloadingStatus == .current { return true }
        try? fm.startDownloadingUbiquitousItem(at: url)
        return false
    }

    private func read(_ url: URL) -> Data? {
        guard ready(url) else { return nil }
        var data: Data?
        var err: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &err) { u in data = try? Data(contentsOf: u) }
        return data
    }

    private func write(_ data: Data, to url: URL) {
        var err: NSError?
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &err) { u in
            try? data.write(to: u, options: .atomic)
        }
    }

    /// Names in a folder, placeholders (".name.icloud") shown under their real name.
    private func names(_ dir: URL) -> [String] {
        let items = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        return items.compactMap { n in
            if n.hasPrefix("."), n.hasSuffix(".icloud") { return String(n.dropFirst().dropLast(7)) }
            return n.hasPrefix(".") ? nil : n
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        var d: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &d) && d.boolValue
    }

    // MARK: library

    func libraryIDs() -> [UUID] { names(root.appending(path: "Library")).compactMap(UUID.init(uuidString:)) }

    func meta(_ id: UUID) -> DocumentMeta? {
        read(root.appending(path: "Library/\(id.uuidString)/meta.json")).flatMap { try? JSONDecoder().decode(DocumentMeta.self, from: $0) }
    }

    func content(_ id: UUID) -> DocumentContent? {
        read(root.appending(path: "Library/\(id.uuidString)/content.json")).flatMap { try? JSONDecoder().decode(DocumentContent.self, from: $0) }
    }

    func cover(_ id: UUID) -> Data? {
        let u = root.appending(path: "Library/\(id.uuidString)/cover.jpg")
        return fm.fileExists(atPath: u.path) || fm.fileExists(atPath: u.deletingLastPathComponent().appending(path: ".cover.jpg.icloud").path) ? read(u) : nil
    }

    func publish(_ meta: DocumentMeta, content: Data, cover: Data?) {
        let dir = root.appending(path: "Library/\(meta.id.uuidString)")
        if let m = try? JSONEncoder().encode(meta) { write(m, to: dir.appending(path: "meta.json")) }
        write(content, to: dir.appending(path: "content.json"))
        if let cover { write(cover, to: dir.appending(path: "cover.jpg")) }
    }

    func removeDocument(_ id: UUID) {
        var err: NSError?
        let u = root.appending(path: "Library/\(id.uuidString)")
        NSFileCoordinator().coordinate(writingItemAt: u, options: .forDeleting, error: &err) { url in try? fm.removeItem(at: url) }
    }

    /// Appended pages after the first `known`, in name order, as text; nil for a page not downloaded yet (stop there).
    func parts(_ id: UUID, after known: Int) -> [String] {
        let dir = root.appending(path: "Library/\(id.uuidString)/parts")
        let all = names(dir).filter { $0.hasSuffix(".md") || $0.hasSuffix(".txt") }.sorted()
        guard all.count > known else { return [] }
        var out: [String] = []
        for n in all[known...] {
            guard let d = read(dir.appending(path: n)) else { break }
            out.append(DocumentImporter.decode(d))
        }
        return out
    }

    // MARK: state

    func writeState(_ s: DeviceState) {
        if let d = try? JSONEncoder().encode(s) { write(d, to: root.appending(path: "State/\(device).json")) }
    }

    func otherStates() -> [DeviceState] {
        names(root.appending(path: "State")).filter { $0.hasSuffix(".json") && $0 != "\(device).json" }
            .compactMap { read(root.appending(path: "State/\($0)")).flatMap { try? JSONDecoder().decode(DeviceState.self, from: $0) } }
    }

    // MARK: events

    func append(_ events: [SyncEvent]) {
        guard !events.isEmpty else { return }
        let url = root.appending(path: "Events/\(device).jsonl")
        var data = read(url) ?? Data()
        let enc = JSONEncoder()
        for e in events { if let line = try? enc.encode(e) { data.append(line); data.append(0x0A) } }
        write(data, to: url)
    }

    /// New events from other devices since the line counts in `seen`; returns them and the new counts.
    func otherEvents(seen: [String: Int]) -> ([SyncEvent], [String: Int]) {
        var counts = seen
        var out: [SyncEvent] = []
        let dec = JSONDecoder()
        for n in names(root.appending(path: "Events")) where n.hasSuffix(".jsonl") && n != "\(device).jsonl" {
            guard let d = read(root.appending(path: "Events/\(n)")) else { continue }
            let lines = d.split(separator: 0x0A)
            let from = counts[n] ?? 0
            guard lines.count > from else { continue }
            for l in lines[from...] { if let e = try? dec.decode(SyncEvent.self, from: Data(l)) { out.append(e) } }
            counts[n] = lines.count
        }
        return (out, counts)
    }

    // MARK: loader

    /// Files waiting in Loader/ (and Loader/<folder>/), claimed for this device by moving them aside.
    func claimLoader() -> [(url: URL, folder: String?)] {
        let loader = root.appending(path: "Loader")
        let claim = loader.appending(path: ".claimed-\(device)")
        try? fm.createDirectory(at: claim, withIntermediateDirectories: true)
        var found: [(URL, String?)] = []
        func take(_ url: URL, folder: String?) {
            guard ready(url) else { return }
            let dst = claim.appending(path: (folder.map { $0 + "__" } ?? "") + url.lastPathComponent)
            if (try? fm.moveItem(at: url, to: dst)) != nil { found.append((dst, folder)) }    // another device may win
        }
        for n in names(loader) where n != "Alındı" {
            let u = loader.appending(path: n)
            if isDirectory(u) {
                for m in names(u) where !isDirectory(u.appending(path: m)) { take(u.appending(path: m), folder: n) }
            } else {
                take(u, folder: nil)
            }
        }
        // files claimed earlier but not finished (app closed mid-import)
        for n in names(claim) where !found.contains(where: { $0.0.lastPathComponent == n }) {
            let parts = n.components(separatedBy: "__")
            found.append((claim.appending(path: n), parts.count > 1 ? parts[0] : nil))
        }
        return found
    }

    func finishLoader(_ url: URL) {
        let name = url.lastPathComponent.components(separatedBy: "__").last ?? url.lastPathComponent
        var dst = root.appending(path: "Loader/Alındı/\(name)")
        if fm.fileExists(atPath: dst.path) {
            dst = root.appending(path: "Loader/Alındı/\(UUID().uuidString.prefix(6))-\(name)")
        }
        try? fm.moveItem(at: url, to: dst)
    }
}

/// Connects the library to the iCloud folder: pushes local changes, pulls the others'.
@MainActor
final class SyncEngine {
    private(set) var files: CloudFiles?
    private(set) var status = "iCloud bağlanıyor…" { didSet { writeDiagnostics() } }

    /// Library/sync-status.txt: what sync last did (read from the Mac with devicectl when something looks wrong).
    func noteVaultStatus() { writeDiagnostics() }

    private func writeDiagnostics() {
        let lines = ["\(Date.now)", "device \(Self.device)", "status \(status)", "root \(files?.root.path ?? "-")",
                     "vault \(UserDefaults.standard.string(forKey: "vault.status") ?? "seçilmedi")"]
        try? lines.joined(separator: "\n").write(to: URL.libraryDirectory.appending(path: "sync-status.txt"), atomically: true, encoding: .utf8)
    }
    private weak var model: AppModel?
    private var pendingEvents: [SyncEvent] = []
    private var cloudBacklog: [SyncEvent] = []
    private var stateTask: Task<Void, Never>?
    private var running = false
    private var timer: Timer?

    static let device: String = {
        if let d = UserDefaults.standard.string(forKey: "sync.device") { return d }
        #if os(iOS)
        let kind = "iphone"
        #else
        let kind = "mac"
        #endif
        let d = "\(kind)-\(UUID().uuidString.prefix(8).lowercased())"
        UserDefaults.standard.set(d, forKey: "sync.device")
        return d
    }()

    init(model: AppModel) { self.model = model }

    /// Find the container (a blocking call, so off the main thread), then sync now and every minute.
    func start() {
        Task.detached(priority: .utility) {
            let url = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.fatihgocgun.voicereader")?
                .appending(path: "Documents", directoryHint: .isDirectory)
            await MainActor.run {
                guard let url else {
                    self.status = "iCloud kapalı: yalnız vault kopyası"
                    Task { await self.mirrorLibrary() }
                    return
                }
                self.files = CloudFiles(root: url, device: Self.device)
                self.status = "iCloud açık"
                Task { await self.publishMissing(); await self.sync() }
                let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in Task { @MainActor in await self?.sync() } }
                RunLoop.main.add(t, forMode: .common)
                self.timer = t
            }
        }
    }

    // MARK: push

    func record(_ e: SyncEvent) {
        pendingEvents.append(e)
        Task { await flushEvents() }
    }

    private func flushEvents() async {
        guard !pendingEvents.isEmpty else { return }
        let batch = pendingEvents
        pendingEvents = []
        await VaultMirror.shared.append(batch, device: Self.device)     // the vault copy, even when iCloud is off
        cloudBacklog += batch                                              // held until iCloud is there
        if let files { let b = cloudBacklog; cloudBacklog = []; await files.append(b) }
    }

    /// A document imported on this device goes to iCloud for the others.
    func publish(_ id: UUID) {
        guard let files, let model, let d = model.store.document(id), let content = model.store.contentData(id) else { return }
        let meta = DocumentMeta(id: d.id, title: d.title, author: d.author, format: d.format, sourceName: d.sourceName,
                                language: d.language, addedAt: d.addedAt, folder: d.folder)
        let cover = model.store.coverData(id)
        Task { await files.publish(meta, content: content, cover: cover) }
    }

    /// First run with iCloud: documents that existed before sync go up once.
    private func publishMissing() async {
        guard let files, let model else { return }
        let remote = Set(await files.libraryIDs())
        for d in model.store.documents where !remote.contains(d.id) { publish(d.id) }
    }

    /// Positions are written a few seconds after they settle, not on every word.
    func positionsChanged() {
        stateTask?.cancel()
        stateTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, !Task.isCancelled, let model = self.model else { return }
            var s = DeviceState()
            for listed in model.store.documents where listed.positionAt != nil || listed.lastOpenedAt != nil {
                let d = model.store.document(listed.id) ?? listed          // the exact place from the journal
                s.docs[d.id] = .init(position: d.position, opened: d.lastOpenedAt, at: d.positionAt ?? d.lastOpenedAt ?? d.addedAt,
                                     length: d.length, title: d.title)
            }
            await VaultMirror.shared.writeState(s, device: Self.device)
            await self.files?.writeState(s)
        }
    }

    /// The vault copy: document list and (first time) every existing highlight and bookmark.
    func mirrorLibrary() async {
        defer { writeDiagnostics() }
        guard let model else { return }
        let docs = model.store.documents
        await VaultMirror.shared.seedIfNeeded(docs, device: Self.device)
        await VaultMirror.shared.writeMeta(docs.map { .init(id: $0.id, title: $0.title, author: $0.author, folder: $0.folder,
                                                             length: $0.length, language: $0.language) })
        for id in await VaultMirror.shared.missingTexts(docs.map(\.id)) {
            if let data = model.store.contentData(id) { await VaultMirror.shared.writeText(data, id: id) }
        }
    }

    // MARK: pull

    func sync() async {
        await mirrorLibrary()
        guard let files, let model, !running else { return }
        running = true
        defer { running = false }
        await flushEvents()

        // 1. new documents from other devices
        let known = Set(model.store.documents.map(\.id))
        let deleted = Set(UserDefaults.standard.stringArray(forKey: "sync.deleted") ?? [])
        for id in await files.libraryIDs() where !known.contains(id) && !deleted.contains(id.uuidString) {
            guard let meta = await files.meta(id), let content = await files.content(id) else { continue }
            let cover = await files.cover(id)
            var words = 0
            content.text.enumerateSubstrings(in: content.text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in words += 1 }
            var r = DocumentRecord(title: meta.title, author: meta.author, format: meta.format, sourceName: meta.sourceName,
                                   length: content.text.utf16.count, wordCount: words, language: meta.language)
            r.id = meta.id
            r.addedAt = meta.addedAt
            r.folder = meta.folder
            if let f = meta.folder { model.store.addFolder(f) }
            try? model.store.insert(r, content: content, cover: cover)
        }

        // 2. events (highlights, bookmarks, folders…) from the others
        let seen = UserDefaults.standard.dictionary(forKey: "sync.seen") as? [String: Int] ?? [:]
        let (events, counts) = await files.otherEvents(seen: seen)
        for e in events.sorted(by: { $0.at < $1.at }) { model.apply(e) }
        UserDefaults.standard.set(counts, forKey: "sync.seen")

        // 3. positions: another device that read further carries this one forward. Sync never takes a place
        //    back; going back is only ever done by hand (an old state file, a test device, a clock off by
        //    minutes must not undo listening).
        for state in await files.otherStates() {
            for (id, entry) in state.docs {
                guard let d = model.store.document(id), entry.at > (d.positionAt ?? .distantPast),
                      entry.position > d.position else { continue }
                if model.player.documentID == id, model.player.isSpeaking { continue }
                model.store.setPosition(id, min(entry.position, d.length), at: entry.at)
                if let o = entry.opened, o > (d.lastOpenedAt ?? .distantPast) { model.store.update(id) { $0.lastOpenedAt = o } }
                if model.player.documentID == id { model.player.moveCursor(to: entry.position, play: false) }
            }
        }

        // 4. pages appended to documents
        for d in model.store.documents {
            let added = await files.parts(d.id, after: d.partsApplied ?? 0)
            if !added.isEmpty { await model.appendParts(added, to: d.id) }
        }

        // 5. the Loader inbox
        let claimed = await files.claimLoader()
        for (url, folder) in claimed {
            let before = Set(model.store.documents.map(\.id))
            model.folder = folder
            if let folder { model.store.addFolder(folder) }
            await model.importFiles([url], fromSync: true)      // importing publishes it
            model.folder = nil
            _ = before
            await files.finishLoader(url)
        }
        status = "Eşitlendi · \(Date.now.formatted(date: .omitted, time: .shortened))"
    }
}
