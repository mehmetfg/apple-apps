// Listening: what was heard on this phone in the last days, for the app that studies it (Teoria's Akşam tekrarı).
//
// The reading app writes only `PDM/listening/<app>.json` in the shared App Group: per day and per document the seconds,
// the words and the heard spans (UTF-16 characters of the reading app's text), plus each document's title, folder,
// length, its id in Teoria and the marks made on it in those days. Like the live state, this path does not wait for
// the vault, iCloud or the Mac: Teoria reads it the same evening, before the Mac has seen the day.
//
// The evening settings (on or off, the time) and the day whose evening session was closed live in the group's
// defaults (`PDMEvening`): Teoria writes them, the reading app reads them when it plans its reminder.
import Foundation

public struct PDMListening: Codable, Sendable, Equatable {
    /// One document heard on one day.
    public struct Heard: Codable, Sendable, Equatable {
        public var seconds: Double
        public var words: Int
        /// Heard spans `[from, to]` in characters, joined where they touch.
        public var ranges: [[Int]]
        public init(seconds: Double, words: Int, ranges: [[Int]]) { self.seconds = seconds; self.words = words; self.ranges = ranges }
    }

    /// A mark (highlight) made in the document.
    public struct Mark: Codable, Sendable, Equatable {
        public var at: Int
        public var length: Int
        public var text: String
        public var note: String?
        public var created: Date
        public init(at: Int, length: Int, text: String, note: String? = nil, created: Date) {
            self.at = at; self.length = length; self.text = text; self.note = note; self.created = created
        }
    }

    public struct Doc: Codable, Sendable, Equatable {
        public var title: String
        public var folder: String?
        public var length: Int
        /// The same book's id in Teoria, when the reading app found it.
        public var teoria: String?
        public var marks: [Mark]
        public init(title: String, folder: String?, length: Int, teoria: String?, marks: [Mark]) {
            self.title = title; self.folder = folder; self.length = length; self.teoria = teoria; self.marks = marks
        }
        public var branch: String { PDMListening.branch(folder: folder, title: title) }
    }

    public var v = 1
    public var app: String
    public var device: String
    public var updated: Date
    /// Day (`yyyy-MM-dd`) → document id (upper-case UUID) → what was heard.
    public var days: [String: [String: Heard]]
    public var docs: [String: Doc]

    public init(app: String, device: String = PDMBus.device, updated: Date = Date(), days: [String: [String: Heard]], docs: [String: Doc]) {
        self.app = app; self.device = device; self.updated = updated; self.days = days; self.docs = docs
    }

    /// The branch of a document, the rule of Teoria's Sabah (`veri/sabah.py` › `branch`): the reading app's folder
    /// when it is one of the series, else the first word of the title, else "Diğer".
    public static func branch(folder: String?, title: String) -> String {
        func key(_ s: String) -> String {
            s.lowercased(with: Locale(identifier: "tr_TR"))
                .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let names = ["felsefe": "Felsefe", "bilimler": "Bilimler", "muhendislik": "Mühendislik"]
        if let f = folder, let b = names[key(f)] { return b }
        let first = key(title).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).first.map(String.init) ?? ""
        return names[first] ?? "Diğer"
    }

    /// The day key the apps use (local calendar).
    public static func dayKey(_ d: Date = Date()) -> String { PDMBus.dayKey(d) }

    func sameContent(as o: PDMListening) -> Bool { days == o.days && docs == o.docs && app == o.app }
}

extension PDMBus {
    static var listeningFolder: URL {
        let d = container.appendingPathComponent("listening", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private static let listeningLock = NSLock()
    private static var lastListening: [String: PDMListening] = [:]

    private static func listeningCoder() -> (JSONEncoder, JSONDecoder) {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return (e, d)
    }

    /// Writes what this app heard. Safe to call often: the file is written only when the content changed.
    /// The `app` field is set to the identifier of this bus. Call it off the main thread.
    public func publishListening(_ listening: PDMListening) {
        var v = listening
        v.app = app
        Self.listeningLock.lock()
        let same = Self.lastListening[app].map { $0.sameContent(as: v) } ?? false
        if !same { Self.lastListening[app] = v }
        Self.listeningLock.unlock()
        guard !same, let data = try? Self.listeningCoder().0.encode(v) else { return }
        try? data.write(to: Self.listeningFolder.appendingPathComponent("\(app).json"), options: .atomic)
    }

    /// What one app heard, or nil.
    public static func listening(of app: String) -> PDMListening? {
        guard let d = try? Data(contentsOf: listeningFolder.appendingPathComponent("\(app).json")) else { return nil }
        return try? listeningCoder().1.decode(PDMListening.self, from: d)
    }

    /// What every reading app on this phone heard, newest first.
    public static func allListening() -> [PDMListening] {
        let files = (try? FileManager.default.contentsOfDirectory(at: listeningFolder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { listening(of: $0.deletingPathExtension().lastPathComponent) }
            .sorted { $0.updated > $1.updated }
    }
}

/// The evening session's settings, shared by the reading app (which plans the reminder: it is the one running while
/// you listen) and Teoria (which runs the session and closes it).
public enum PDMEvening {
    static let enabledKey = "evening.enabled", hourKey = "evening.hour", minuteKey = "evening.minute", closedKey = "evening.closed"
    /// Below this, a day's listening asks for no evening session.
    public static let minimumMinutes = 3.0

    /// The reminder before bed. On by default.
    public static var enabled: Bool {
        get { PDMBus.defaults.object(forKey: enabledKey) as? Bool ?? true }
        set { PDMBus.defaults.set(newValue, forKey: enabledKey) }
    }
    /// The reminder's time, 22:30 by default.
    public static var hour: Int {
        get { PDMBus.defaults.object(forKey: hourKey) as? Int ?? 22 }
        set { PDMBus.defaults.set(min(max(newValue, 0), 23), forKey: hourKey) }
    }
    public static var minute: Int {
        get { PDMBus.defaults.object(forKey: minuteKey) as? Int ?? 30 }
        set { PDMBus.defaults.set(min(max(newValue, 0), 59), forKey: minuteKey) }
    }
    /// The last day whose evening session was closed (`yyyy-MM-dd`).
    public static var closedDay: String? {
        get { PDMBus.defaults.string(forKey: closedKey) }
        set { PDMBus.defaults.set(newValue, forKey: closedKey) }
    }
    public static func isClosed(_ day: String = PDMListening.dayKey()) -> Bool { closedDay == day }
}
