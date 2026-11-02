// What the app hands to its widgets (2026-10-28): a small snapshot in the shared App Group folder — the book to go
// on with, the books being read, today's and the week's listening, and the marked passages of the recent books —
// and each book's cover as a small picture. The widgets only read it; a tap on one opens the app by a wisepath://
// link (resume · book/<id> · stats). Compiled into the app and the widget extension both.
import Foundation

enum WidgetShared {
    static let group = "group.com.fatihgocgun.okur"
    static let kind = (continue: "WisePathContinue", reading: "WisePathReading", stats: "WisePathStats", quote: "WisePathQuote")

    static var folder: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) }
    static var snapshotURL: URL? { folder?.appending(path: "widget.json") }
    static func coverURL(_ id: UUID) -> URL? { folder?.appending(path: "covers/\(id.uuidString).jpg") }

    static func load() -> WidgetSnapshot? {
        guard let u = snapshotURL, let data = try? Data(contentsOf: u) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// The quote widget's "next" key moves this on; the widget reads it with the time-based rotation.
    static var quoteShift: Int {
        get { UserDefaults(suiteName: group)?.integer(forKey: "quoteShift") ?? 0 }
        set { UserDefaults(suiteName: group)?.set(newValue, forKey: "quoteShift") }
    }
}

struct WidgetSnapshot: Codable {
    struct Book: Codable, Identifiable, Hashable {
        var id: UUID
        var title: String
        var author: String?
        var progress: Double
        var status: String
        var finished: Bool
        var quotes: [String]
    }
    struct Day: Codable, Hashable {
        var label: String
        var minutes: Double
        var today: Bool
    }

    var current: Book?
    var reading: [Book]                 // in progress, the last opened first
    var books: [Book]                   // the recent books with marks, for the quote widget's choice
    var todayMinutes: Double
    var todayPages: Double
    var week: [Day]
    var updated: Date
}
