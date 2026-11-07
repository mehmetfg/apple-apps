// Link layer model, shared by Mac and iPhone (moved from mac/Kaynak/Baglar.swift 2026-11-07). links.py (run by isle.py)
// writes <kok>/links.json: every topic (mostly a Teoria book), the spoken and written production tied to it from
// Kıvılcım, Teoria and Wise Path, and the spoken minutes per day and week. The apps only read it.
import Foundation

struct Links: Codable, Sendable {
    var version: Int = 1
    var built: String = ""
    var topics: [LinkTopic] = []
    var direction: Direction = Direction()
    var recent_books: [RecentBook] = []

    static let empty = Links()

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        version = (try? c.decode(Int.self, forKey: .version)) ?? 1
        built = (try? c.decode(String.self, forKey: .built)) ?? ""
        topics = (try? c.decode([LinkTopic].self, forKey: .topics)) ?? []
        direction = (try? c.decode(Direction.self, forKey: .direction)) ?? Direction()
        recent_books = (try? c.decode([RecentBook].self, forKey: .recent_books)) ?? []
    }

    func topic(_ id: String) -> LinkTopic? { topics.first { $0.id == id } }
}

struct LinkTopic: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var short: String
    var series: String
    var no: Int
    var color: String
    var teoria: Bool
    var percent: Int
    var last_read: String
    var count: Int
    var seconds: Int
    var latest: String
    var entries: [LinkEntry]
    var page: String

    var latestDate: Date { Zaman.coz(latest) ?? .distantPast }
}

struct LinkEntry: Codable, Identifiable, Hashable, Sendable {
    var source: String          // kivilcim · teoria · wisepath
    var id: String
    var item: String            // Kıvılcım record id, "" for Teoria / Wise Path notes
    var date: String
    var title: String
    var audio: String           // vault-relative; the sound stays where it was recorded
    var kind: String
    var how: String
    var offset: Double
    var note: String
    var seconds: Int
    var text: String
    var quote: String
    var chapter: String
    var parts: [LinkPart]

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        source = (try? c.decode(String.self, forKey: .source)) ?? "kivilcim"
        id = try c.decode(String.self, forKey: .id)
        item = (try? c.decode(String.self, forKey: .item)) ?? ""
        date = (try? c.decode(String.self, forKey: .date)) ?? ""
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        audio = (try? c.decode(String.self, forKey: .audio)) ?? ""
        kind = (try? c.decode(String.self, forKey: .kind)) ?? ""
        how = (try? c.decode(String.self, forKey: .how)) ?? ""
        offset = (try? c.decode(Double.self, forKey: .offset)) ?? 0
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        seconds = (try? c.decode(Int.self, forKey: .seconds)) ?? 0
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        quote = (try? c.decode(String.self, forKey: .quote)) ?? ""
        chapter = (try? c.decode(String.self, forKey: .chapter)) ?? ""
        parts = (try? c.decode([LinkPart].self, forKey: .parts)) ?? []
    }

    var when: Date { Zaman.coz(date) ?? .distantPast }
    /// Unique across topics: a journal can sit under several topics.
    var rowID: String { id + "|" + source }
    var sourceName: String {
        switch source { case "teoria": "Teoria"; case "wisepath": "Wise Path"; default: kind == "journal" ? "Uzun konuşma" : "Kıvılcım" }
    }
    var sourceSymbol: String {
        switch source { case "teoria": "text.book.closed"; case "wisepath": "headphones"; default: kind == "journal" ? "book.pages" : "waveform" }
    }
}

struct LinkPart: Codable, Hashable, Sendable {
    var t: Double
    var x: String
}

struct Direction: Codable, Sendable {
    var days: [DirectionDay] = []
    var weeks: [DirectionWeek] = []
}

struct DirectionDay: Codable, Hashable, Sendable {
    var day: String
    var seconds: Int
    var topics: [String: Int]
}

struct DirectionWeek: Codable, Hashable, Sendable {
    var week: String
    var seconds: Int
    var topics: [String: Int]
}

struct RecentBook: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var short: String
    var last: String
}

/// A journal's transcript with timestamps (dokum/<id>.json → parcalar).
struct Segment: Codable, Hashable, Sendable {
    var t: Double
    var x: String
}

func minutesText(_ s: Int) -> String {
    s < 60 ? "\(s) sn" : s < 3600 ? "\(Int((Double(s) / 60).rounded())) dk" : String(format: "%.1f sa", Double(s) / 3600).replacingOccurrences(of: ".", with: ",")
}
