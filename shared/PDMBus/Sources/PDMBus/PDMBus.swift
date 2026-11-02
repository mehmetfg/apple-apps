// The bus client of one app.
//
//   emit()   puts an event into the outbox of the app, in the shared App Group. Works in a widget too.
//   sync()   (app only) moves the outbox to `_bus/events/<app>/<device>.jsonl` in the vault, then
//            copies `_bus/state/words.json` (small form) and `today.json` into the App Group.
//   cached…  reads the App Group copy. Widgets use this: they do not wait for iCloud.
//
// Rules (README §4): each device writes only its own file; a line is never changed; an app writes
// only its own events. So an app empties only its own outbox.
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

public final class PDMBus: @unchecked Sendable {
    public static let appGroup = "group.com.fatihgocgun.pdm"

    public let app: String
    private let vaultRoot: @Sendable () -> URL?

    /// - Parameters:
    ///   - app: the app identifier in `_bus/registry.json` (e.g. `vocuteach`).
    ///   - vaultRoot: the security-scoped vault folder. The default is the folder selected through PDMVault.
    public init(app: String, vaultRoot: @escaping @Sendable () -> URL? = { PDMVault.resolve() }) {
        self.app = app
        self.vaultRoot = vaultRoot
    }

    // MARK: places

    /// The shared App Group, or the app's own Application Support when the group is not signed
    /// (an unsigned simulator build). Then the widget does not see the data, but the app still operates.
    public static var container: URL {
        // PDM_CONTAINER: for tests on the Mac, where an unsigned process must not touch a group container.
        let base = ProcessInfo.processInfo.environment["PDM_CONTAINER"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let u = base.appendingPathComponent("PDM", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    public static var hasSharedGroup: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) != nil
    }

    static var defaults: UserDefaults {
        ProcessInfo.processInfo.environment["PDM_CONTAINER"] != nil ? .standard : (UserDefaults(suiteName: appGroup) ?? .standard)
    }

    var outboxURL: URL {
        let d = Self.container.appendingPathComponent("outbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("\(app).jsonl")
    }

    static var stateFolder: URL {
        let d = container.appendingPathComponent("state", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// `iphone`, `ipad`, `mac` or `simulator`. Each device writes its own events file.
    public static let device: String = {
        #if targetEnvironment(simulator)
        return "simulator"
        #elseif os(macOS)
        return "mac"
        #else
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return machine.hasPrefix("iPad") ? "ipad" : "iphone"
        #endif
    }()

    // MARK: write

    /// Adds one event to the outbox. It goes to the vault at the next `sync()`.
    public func emit(_ type: String, subject: String? = nil, data: [String: PDMValue] = [:]) {
        let e = PDMEvent(app: app, device: Self.device, type: type, subject: subject, data: data)
        guard let line = e.jsonLine() else { return }
        var err: NSError?
        NSFileCoordinator().coordinate(writingItemAt: outboxURL, options: .forMerging, error: &err) { u in
            Self.append(line, to: u)
        }
    }

    /// Writes `app.opened` one time each day. Call it when the app becomes active.
    public func emitOpenedToday() {
        let key = "pdm.opened.\(app)"
        let today = Self.dayKey(Date())
        guard Self.defaults.string(forKey: key) != today else { return }
        Self.defaults.set(today, forKey: key)
        emit("app.opened", subject: PDMSubject.app(app))
    }

    /// The number of events that wait in the outbox.
    public var pendingCount: Int {
        guard let d = try? Data(contentsOf: outboxURL) else { return 0 }
        return d.split(separator: 0x0A).count
    }

    // MARK: sync

    public struct Report: Sendable {
        public enum Status: String, Sendable { case ok, noVault, notVaultRoot, failed }
        public var status: Status
        public var sent = 0
        public var stateRefreshed = false
        public var message: String?
        public var date = Date()

        /// A Turkish sentence for the settings screen.
        public var text: String {
            switch status {
            case .ok: return sent > 0 ? "\(sent) olay vault'a gitti" : "Eşit"
            case .noVault: return "Vault klasörü seçilmedi — olaylar telefonda bekliyor"
            case .notVaultRoot: return "Seçilen klasörde _bus yok — Personel Data Management'ı seç"
            case .failed: return message ?? "Eşitlenemedi"
            }
        }
    }

    /// Sends the outbox to the vault and refreshes the cached state. Call it from the app, not from a widget.
    @discardableResult
    public func sync() async -> Report {
        let r = await Task.detached(priority: .utility) { self.syncNow() }.value
        Self.defaults.set(r.date, forKey: "pdm.sync.\(app).date")
        Self.defaults.set(r.text, forKey: "pdm.sync.\(app).text")
        if r.stateRefreshed {
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        }
        return r
    }

    /// The last sync of this app: date and Turkish text.
    public var lastSync: (date: Date?, text: String?) {
        (Self.defaults.object(forKey: "pdm.sync.\(app).date") as? Date, Self.defaults.string(forKey: "pdm.sync.\(app).text"))
    }

    func syncNow() -> Report {
        guard let root = PDMVault.simulatorOverride ?? vaultRoot() else { return Report(status: .noVault) }
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        guard let bus = PDMVault.busFolder(in: root) else { return Report(status: .notVaultRoot) }
        var r = Report(status: .ok)
        do { r.sent = try flush(into: bus) } catch {
            r.status = .failed
            r.message = "Olaylar yazılamadı: \(error.localizedDescription)"
        }
        r.stateRefreshed = refreshState(from: bus)
        return r
    }

    struct BusError: LocalizedError {
        var errorDescription: String?
    }

    /// Moves the whole outbox to `_bus/events/<app>/<device>.jsonl`. The outbox stays when the append fails.
    func flush(into bus: URL) throws -> Int {
        var sent = 0
        var failure: Error?
        var err: NSError?
        NSFileCoordinator().coordinate(writingItemAt: outboxURL, options: .forMerging, error: &err) { box in
            guard let data = try? Data(contentsOf: box), !data.isEmpty else { return }
            let dir = bus.appendingPathComponent("events", isDirectory: true).appendingPathComponent(app, isDirectory: true)
            let target = dir.appendingPathComponent("\(Self.device).jsonl")
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try Self.waitForDownload(target)
                var werr: NSError?
                var inner: Error?
                NSFileCoordinator().coordinate(writingItemAt: target, options: .forMerging, error: &werr) { u in
                    do { try Self.appendOrThrow(data, to: u) } catch { inner = error }
                }
                if let e = werr ?? inner { throw e }
                try Data().write(to: box)
                sent = data.split(separator: 0x0A).count
            } catch { failure = error }
        }
        if let e = err ?? failure { throw e }
        return sent
    }

    /// On iOS an iCloud file that is not downloaded shows as `.<name>.icloud`. Appending to a
    /// missing file then would make a second copy. So wait for the download, or keep the outbox.
    static func waitForDownload(_ target: URL) throws {
        let fm = FileManager.default
        let placeholder = target.deletingLastPathComponent().appendingPathComponent(".\(target.lastPathComponent).icloud")
        guard !fm.fileExists(atPath: target.path), fm.fileExists(atPath: placeholder.path) else { return }
        try? fm.startDownloadingUbiquitousItem(at: target)
        for _ in 0..<40 where !fm.fileExists(atPath: target.path) { Thread.sleep(forTimeInterval: 0.25) }
        if !fm.fileExists(atPath: target.path) {
            throw BusError(errorDescription: "\(target.lastPathComponent) iCloud'dan inmedi; sonra tekrar denenecek")
        }
    }

    // MARK: state

    /// Copies the state into the App Group: `words-summary.json` (small) and `today.json`.
    func refreshState(from bus: URL) -> Bool {
        var changed = false
        let state = bus.appendingPathComponent("state", isDirectory: true)
        if let d = Self.coordinatedRead(state.appendingPathComponent("words.json")),
           let w = try? JSONDecoder().decode(PDMWords.self, from: d) {
            let old = Self.cachedWords()
            if old?.generated != w.generated || old == nil {
                let s = PDMWordSummary(w)
                let enc = JSONEncoder()
                enc.dateEncodingStrategy = .iso8601
                if let out = try? enc.encode(s) {
                    try? out.write(to: Self.stateFolder.appendingPathComponent("words-summary.json"), options: .atomic)
                    changed = true
                }
            }
        }
        if let d = Self.coordinatedRead(state.appendingPathComponent("today.json")),
           (try? JSONDecoder().decode(PDMToday.self, from: d)) != nil {
            let u = Self.stateFolder.appendingPathComponent("today.json")
            if (try? Data(contentsOf: u)) != d {
                try? d.write(to: u, options: .atomic)
                changed = true
            }
        }
        return changed
    }

    /// The App Group copy of `words.json` (small form). Safe in a widget.
    public static func cachedWords() -> PDMWordSummary? {
        guard let d = try? Data(contentsOf: stateFolder.appendingPathComponent("words-summary.json")) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(PDMWordSummary.self, from: d)
    }

    /// The App Group copy of `today.json`. Safe in a widget.
    public static func cachedToday() -> PDMToday? {
        guard let d = try? Data(contentsOf: stateFolder.appendingPathComponent("today.json")) else { return nil }
        return try? JSONDecoder().decode(PDMToday.self, from: d)
    }

    // MARK: helpers

    static func coordinatedRead(_ u: URL) -> Data? {
        try? FileManager.default.startDownloadingUbiquitousItem(at: u)
        var out: Data?
        var err: NSError?
        NSFileCoordinator().coordinate(readingItemAt: u, options: [], error: &err) { x in out = try? Data(contentsOf: x) }
        return out
    }

    static func append(_ data: Data, to u: URL) { try? appendOrThrow(data, to: u) }

    static func appendOrThrow(_ data: Data, to u: URL) throws {
        if FileManager.default.fileExists(atPath: u.path) {
            let h = try FileHandle(forUpdating: u)
            defer { try? h.close() }
            let end = try h.seekToEnd()
            if end > 0 {
                // A line must start on a new line, also when an earlier write stopped half way.
                try h.seek(toOffset: end - 1)
                if try h.read(upToCount: 1) != Data([0x0A]) { try h.write(contentsOf: Data([0x0A])) }
                try h.seekToEnd()
            }
            try h.write(contentsOf: data)
        } else {
            try data.write(to: u, options: .atomic)
        }
    }

    static func dayKey(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}
