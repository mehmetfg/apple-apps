// Live state: what one app does now, for the other apps on the same device.
//
// Each app writes only `PDM/live/<app>.json` in the shared App Group. Each app and each widget
// can read all the files. This path does not use the vault, iCloud or the Mac: the file is there
// immediately. Use it for "now" (the book that plays, the last capture). Use events for history.
import Foundation

/// The current item of one app.
public struct PDMLive: Codable, Sendable, Equatable {
    /// The app identifier from the registry.
    public var app: String
    /// The time of the last write.
    public var updated: Date
    /// The kind of item: `book`, `idea`, `day`.
    public var kind: String?
    /// The identifier of the item in the app that wrote the file.
    public var id: String?
    public var title: String?
    /// One short line below the title. Example: the chapter.
    public var detail: String?
    /// 0…1.
    public var progress: Double?
    /// True while the app plays or records.
    public var active: Bool?
    /// A deep link that opens this item in the app that wrote the file.
    public var link: String?
    /// The identifier of the same item in other apps. Example: `["teoria": "by-k1-c04"]`.
    public var refs: [String: String]?

    public init(app: String, updated: Date = Date(), kind: String? = nil, id: String? = nil, title: String? = nil,
                detail: String? = nil, progress: Double? = nil, active: Bool? = nil, link: String? = nil,
                refs: [String: String]? = nil) {
        self.app = app; self.updated = updated; self.kind = kind; self.id = id; self.title = title
        self.detail = detail; self.progress = progress; self.active = active; self.link = link; self.refs = refs
    }

    /// True when the two values show the same item in the same condition. The time and small
    /// progress steps (less than 1 %) are ignored.
    func sameContent(as o: PDMLive) -> Bool {
        app == o.app && kind == o.kind && id == o.id && title == o.title && detail == o.detail
            && active == o.active && link == o.link && refs == o.refs
            && Int((progress ?? -1) * 100) == Int((o.progress ?? -1) * 100)
    }
}

extension PDMBus {
    static var liveFolder: URL {
        let d = container.appendingPathComponent("live", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private static let liveLock = NSLock()
    private static var lastLive: [String: PDMLive] = [:]

    private static func liveCoder() -> (JSONEncoder, JSONDecoder) {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return (e, d)
    }

    /// Writes the current item of this app. Safe to call frequently: the file is written only when
    /// the content changes or when the last write is older than `refresh` seconds.
    /// The `app` field of `live` is set to the identifier of this bus.
    public func publishLive(_ live: PDMLive, refresh: TimeInterval = 60) {
        var v = live
        v.app = app
        Self.liveLock.lock()
        let old = Self.lastLive[app]
        let skip = old.map { $0.sameContent(as: v) && v.updated.timeIntervalSince($0.updated) < refresh } ?? false
        if !skip { Self.lastLive[app] = v }
        Self.liveLock.unlock()
        guard !skip, let data = try? Self.liveCoder().0.encode(v) else { return }
        try? data.write(to: Self.liveFolder.appendingPathComponent("\(app).json"), options: .atomic)
    }

    /// Removes the current item of this app (for example when the user removes the book).
    public func clearLive() {
        Self.liveLock.lock(); Self.lastLive[app] = nil; Self.liveLock.unlock()
        try? FileManager.default.removeItem(at: Self.liveFolder.appendingPathComponent("\(app).json"))
    }

    /// The current item of one app, or nil. With `maxAge`, an older item gives nil.
    public static func live(of app: String, maxAge: TimeInterval? = nil) -> PDMLive? {
        guard let d = try? Data(contentsOf: liveFolder.appendingPathComponent("\(app).json")),
              let v = try? liveCoder().1.decode(PDMLive.self, from: d) else { return nil }
        if let maxAge, Date().timeIntervalSince(v.updated) > maxAge { return nil }
        return v
    }

    /// The current items of all apps, newest first.
    public static func allLive(maxAge: TimeInterval? = nil) -> [PDMLive] {
        let files = (try? FileManager.default.contentsOfDirectory(at: liveFolder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { live(of: $0.deletingPathExtension().lastPathComponent, maxAge: maxAge) }
            .sorted { $0.updated > $1.updated }
    }
}
