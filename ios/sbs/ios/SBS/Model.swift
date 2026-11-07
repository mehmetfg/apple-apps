// The shape of SBS/state/sbs.json (written by sbs.py on the Mac). Keys arrive in snake_case.
import Foundation
import SwiftUI

/// A ledger value is a number, a text ("<0.6", "nonreactive") or nothing.
enum Flex: Codable, Hashable {
    case number(Double), text(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { self = .number(d) } else { self = .text((try? c.decode(String.self)) ?? "") }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .number(let d): try c.encode(d)
        case .text(let s): try c.encode(s)
        }
    }

    var display: String {
        switch self {
        case .number(let d): return d.clean
        case .text(let s): return s
        }
    }
}

struct SBSState: Codable {
    var generated: String?
    var counts: [String: Int]?
    var sources: [String: SourceInfo]?
    var labDates: [String]?
    var highlights: [Highlight]
    var areas: [Area]
    var markers: [Marker]
    var conditions: [Condition]
    var crisisLevels: [CrisisLevel]
    var episodes: [Episode]
    var supplements: [Supplement]
    var medications: [Medication]
    var documents: [DocumentItem]
    var days: [DayRow]
    var ledger: [LedgerRecord]

    func marker(_ id: String) -> Marker? { markers.first { $0.id == id } }
    func condition(_ id: String?) -> Condition? { conditions.first { $0.id == id } }
}

struct SourceInfo: Codable, Hashable { var count: Int; var last: String }

struct Highlight: Codable, Identifiable, Hashable {
    var id: String
    var tone: String      // alert · watch · good
    var marker: String?
    var title: String
    var detail: String
}

struct Area: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var state: String     // good · watch · attention · unknown
    var detail: String
    var markers: [String]
    var inRange: Int
    var total: Int
    var lastDate: String?
}

struct MarkerPoint: Codable, Hashable, Identifiable {
    var date: String
    var value: Double?
    var text: String
    var flag: String?
    var id: String { date }
    var day: Date { Day.parse(date) ?? .distantPast }
    /// "177.5" → "177,5"; "<0.6" and words stay as written.
    var shown: String { value != nil && text.first?.isNumber == true ? value!.clean : text.replacingOccurrences(of: ".", with: ",") }
}

struct Marker: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var area: String
    var panel: String
    var unit: String
    var refText: String
    var refLow: Double?
    var refHigh: Double?
    var status: String    // in · watch · attention · info
    var direction: String?
    var trend: String?
    var course: String?
    var stale: Bool
    var lastDate: String
    var lastValue: Double?
    var lastText: String
    var points: [MarkerPoint]

    var numericPoints: [MarkerPoint] { points.filter { $0.value != nil } }
    var lastShown: String { points.last?.shown ?? lastText }
}

struct ProtocolCard: Codable, Hashable {
    var own: [String]
    var general: [String]
    var redFlags: [String]
    var source: String?
}

struct Condition: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var region: String
    var kind: String
    var symptoms: [String]
    var triggers: [String]
    var `protocol`: ProtocolCard
    var markers: [String]
    var episodeCount: Int
    var lastEpisode: String?
    var seenTriggers: [String]
}

struct CrisisLevel: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var when: String
    var steps: [String]
}

struct Episode: Codable, Identifiable, Hashable {
    var id: String
    var date: String
    var condition: String?
    var region: String?
    var title: String?
    var text: String?
    var triggers: [String]?
    var did: String?
    var outcome: String?
    var ended: String?
    var severity: Int?
    var source: String?
}

struct Supplement: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var dose: String?
    var slot: String?
    var caution: String?
    var active: Bool?
}

struct Medication: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var use: String?
    var source: String?
}

struct DocumentItem: Codable, Identifiable, Hashable {
    var id: String
    var date: String?
    var kind: String?
    var title: String
    var file: String?
    var note: String?
}

struct DayRow: Codable, Identifiable, Hashable {
    var date: String
    var supplements: Int?
    var planned: Int?
    var proteinG: Double?
    var proteinGoal: Double?
    var waterMl: Double?
    var waterGoal: Double?
    var workoutMin: Double?
    var moveMin: Double?
    var sleepH: Double?
    var steps: Double?
    var episodes: Int?
    var id: String { date }
}

struct LedgerRecord: Codable, Identifiable, Hashable {
    var id: String
    var ts: String
    var day: String
    var kind: String      // input · process · output
    var type: String
    var title: String
    var value: Flex?
    var unit: String?
    var detail: String?
    var source: String
    var ref: String?
}

// MARK: - small helpers

enum Day {
    static let iso: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func parse(_ s: String?) -> Date? { s.flatMap { iso.date(from: String($0.prefix(10))) } }
    static func key(_ d: Date) -> String { iso.string(from: d) }

    /// "22 Eki 2026"
    static func short(_ s: String?) -> String {
        guard let d = parse(s) else { return s ?? "—" }
        return d.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "tr_TR")))
    }

    /// "22 Eki"
    static func dayMonth(_ s: String?) -> String {
        guard let d = parse(s) else { return s ?? "—" }
        return d.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "tr_TR")))
    }

    static func daysAgo(_ s: String?) -> Int? {
        guard let d = parse(s) else { return nil }
        return Calendar.current.dateComponents([.day], from: d, to: Calendar.current.startOfDay(for: .now)).day
    }
}

extension Double {
    /// 177.5 → "177,5" · 262 → "262"
    var clean: String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.maximumFractionDigits = abs(self) < 10 ? 2 : 1
        f.minimumFractionDigits = 0
        f.usesGroupingSeparator = abs(self) >= 10000
        return f.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}

enum Region {
    static let names: [String: String] = [
        "head": "Baş", "neck": "Boyun", "chest": "Göğüs", "abdomen": "Karın", "low_back": "Bel", "arm": "Kol",
        "hand": "El", "hip": "Kalça", "knee": "Diz", "leg": "Bacak", "foot": "Ayak", "mind": "Zihin", "whole": "Genel"]
    static func name(_ id: String?) -> String { names[id ?? ""] ?? "Genel" }
}
