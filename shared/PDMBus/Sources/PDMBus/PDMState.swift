// Codable models for the state files that the hub writes (`_bus/state/*.json`, README §5).
// All keys are optional: an older or newer hub must not stop an app.
import Foundation

/// One word of the focus list (`words.json` → `focus`, `today.json` → `focus_words`).
public struct PDMFocusWord: Codable, Hashable, Sendable, Identifiable {
    public var word: String
    public var why: String?
    public var status: String?
    public var cefr: String?
    public var tr: String?
    public var example: String?
    public var id: String { word.lowercased() }

    public init(word: String, why: String? = nil, status: String? = nil, cefr: String? = nil,
                tr: String? = nil, example: String? = nil) {
        self.word = word; self.why = why; self.status = status; self.cefr = cefr; self.tr = tr; self.example = example
    }
}

/// One word in `words.json` → `words`. The `sources` object is not decoded.
public struct PDMWordRecord: Codable, Hashable, Sendable {
    public var status: String
    public var cefr: String?
    public var tier: String?
    public var tr: String?
    public var last: String?
}

/// `_bus/state/words.json` (about 800 KB). Decode it in the app only, never in a widget.
public struct PDMWords: Codable, Sendable {
    public var v: Int?
    public var generated: String?
    public var counts: [String: Int]?
    public var focus: [PDMFocusWord]?
    public var words: [String: PDMWordRecord]?
}

/// The small form of `words.json` that the bus keeps in the App Group. Widgets read this.
public struct PDMWordSummary: Codable, Sendable {
    public var generated: String?
    public var refreshed: Date
    public var counts: [String: Int]
    public var focus: [PDMFocusWord]
    /// Words with the status `known` or `dropped`. Do not show them again.
    public var closed: [String]

    public init(_ w: PDMWords, refreshed: Date = Date()) {
        generated = w.generated
        self.refreshed = refreshed
        counts = w.counts ?? [:]
        focus = (w.focus ?? []).filter { !["known", "dropped"].contains($0.status ?? "") }
        closed = (w.words ?? [:]).filter { ["known", "dropped"].contains($0.value.status) }.map(\.key).sorted()
    }

    /// The focus words that are not closed, in the order of the hub.
    public func openFocus(extraClosed: Set<String> = []) -> [PDMFocusWord] {
        let c = Set(closed).union(extraClosed.map { $0.lowercased() })
        return focus.filter { !c.contains($0.word.lowercased()) }
    }
}

/// `_bus/state/today.json`.
/// A grammar topic that Cümle points to today (`today.json` › `focus_grammar`). `id` is a GramerApp topic id.
public struct PDMFocusGrammar: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String?
    public var why: String?
    /// "struggled" (hard sentences on the last written day) · "errors" (a repeated error type) · "next" (the next day).
    public var kind: String?
}

public struct PDMToday: Codable, Sendable {
    public struct Change: Codable, Hashable, Sendable { public var date: String?; public var title: String? }
    public struct Line: Codable, Hashable, Sendable, Identifiable { public var id: String; public var name: String?; public var today: String? }
    public struct Cumle: Codable, Hashable, Sendable {
        public var deskDay: Int?
        public var lastWrittenDay: Int?
        enum CodingKeys: String, CodingKey { case deskDay = "desk_day", lastWrittenDay = "last_written_day" }
    }
    public struct Muhendis: Codable, Hashable, Sendable { public var id: String?; public var baslik: String?; public var soru: String? }

    public var v: Int?
    public var generated: String?
    public var date: String?
    public var recentChanges: [Change]?
    public var openDecisions: [String]?
    public var lines: [Line]?
    public var cumle: Cumle?
    public var muhendis: Muhendis?
    public var focusWords: [PDMFocusWord]?
    public var focusGrammar: [PDMFocusGrammar]?

    enum CodingKeys: String, CodingKey {
        case v, generated, date, lines, cumle, muhendis
        case recentChanges = "recent_changes", openDecisions = "open_decisions", focusWords = "focus_words"
        case focusGrammar = "focus_grammar"
    }
}
