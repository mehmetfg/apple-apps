import Foundation

/// Paths and small file helpers. The vault is the single source; Tekne reads it and writes
/// only its own event file (_bus/events/tekne/<device>.jsonl) and today's journal front matter.
enum Vault {
    static let root: URL = {
        if let p = ProcessInfo.processInfo.environment["TEKNE_VAULT"] { return URL(fileURLWithPath: p) }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/iCloud~md~obsidian/Documents/Personel Data Management")
    }()

    static let downloads: URL = {
        if let p = ProcessInfo.processInfo.environment["TEKNE_DOWNLOADS"] { return URL(fileURLWithPath: p) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }()

    /// Same rule as _bus/emit.py device(): short host name, lower case, [a-z0-9-] only.
    static let device: String = {
        if let d = ProcessInfo.processInfo.environment["PDM_BUS_DEVICE"], !d.isEmpty { return d }
        let host = (ProcessInfo.processInfo.hostName.split(separator: ".").first.map(String.init)) ?? "mac"
        let cleaned = host.lowercased().replacingOccurrences(of: "[^a-z0-9-]+", with: "-", options: .regularExpression)
        let trimmed = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "mac" : trimmed
    }()

    static func url(_ relative: String) -> URL { root.appendingPathComponent(relative) }

    static func json(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func json(_ relative: String) -> [String: Any]? { json(url(relative)) }

    static func jsonLines(_ url: URL) -> [[String: Any]] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            guard let d = line.data(using: .utf8) else { return nil }
            return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
        }
    }

    static func files(in folder: URL, ext: String) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return items.filter { $0.pathExtension == ext }
    }
}

enum Day {
    static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "tr_TR")
        c.firstWeekday = 2
        return c
    }()

    static func key(_ d: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func parse(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        let p = DateFormatter()
        p.locale = Locale(identifier: "en_US_POSIX")
        p.dateFormat = "yyyy-MM-dd"
        return p.date(from: String(s.prefix(10)))
    }

    static func iso(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: d)
    }

    static func daysAgo(_ n: Int, from d: Date = Date()) -> Date {
        cal.date(byAdding: .day, value: -n, to: cal.startOfDay(for: d))!
    }
}
