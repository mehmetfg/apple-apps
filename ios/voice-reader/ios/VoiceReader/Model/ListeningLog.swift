// The listening log: what was heard each day, per document. Kept from 2026-10-22 on (nothing older exists).
// Once a second it looks at the player: playing → that document's listening seconds; paused in a reading session →
// paused seconds; in a music break → break seconds. Words heard come from the cursor's advance (the words in the text
// between two reported places, a jump of more than 3000 characters is not counted). A document reaching 99 % is
// recorded as finished on that day, once.
//
//   Application Support/VoiceReader/listening/<device>.json   the log (also copied to the vault: durum/Listening)
//
// No goals, no streaks: the screen only shows what happened.
import Foundation
import Observation
import UIKit

struct ListeningDoc: Codable, Hashable, Sendable {
    var seconds: Double = 0
    var words: Int = 0
    var ranges: [[Int]] = []                         // heard spans [from, to] in characters (Teoria's Sabah maps them to chapters)

    init() {}

    init(from decoder: Decoder) throws {             // logs written before 2026-10-26 have no ranges
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seconds = try c.decodeIfPresent(Double.self, forKey: .seconds) ?? 0
        words = try c.decodeIfPresent(Int.self, forKey: .words) ?? 0
        ranges = try c.decodeIfPresent([[Int]].self, forKey: .ranges) ?? []
    }

    /// Adds a heard span, joining it to the last one when they touch.
    mutating func heard(_ from: Int, _ to: Int) {
        if var last = ranges.last, last.count == 2, from >= last[0], from - last[1] <= 50 {
            last[1] = max(last[1], to)
            ranges[ranges.count - 1] = last
        } else {
            ranges.append([from, to])
        }
    }
}

struct ListeningDay: Codable, Hashable, Sendable {
    var docs: [String: ListeningDoc] = [:]          // document id → heard that day
    var paused: Double = 0                           // a reading session existed but was paused
    var breaks: Double = 0                           // music breaks
    var finished: [String] = []                      // documents that reached 99 % that day

    var seconds: Double { docs.values.reduce(0) { $0 + $1.seconds } }
    var words: Int { docs.values.reduce(0) { $0 + $1.words } }
}

@MainActor
@Observable
final class ListeningLog {
    static let wordsPerPage = 225.0                  // the vault's A5 page (Orkestra's measure)

    private(set) var days: [String: ListeningDay] = [:]
    @ObservationIgnored private var finishedEver: Set<String> = []
    @ObservationIgnored private var lastTick: Date?
    @ObservationIgnored private var lastPlace: (doc: UUID, offset: Int)?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var dirty = false
    @ObservationIgnored private var lastSave = Date.distantPast
    @ObservationIgnored private let file: URL
    @ObservationIgnored private let device: String

    init(device: String) {
        self.device = device
        let dir = URL.applicationSupportDirectory.appending(path: "VoiceReader/listening", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        file = dir.appending(path: "\(device).json")
        if let data = try? Data(contentsOf: file), let d = try? JSONDecoder().decode([String: ListeningDay].self, from: data) {
            days = d
            finishedEver = Set(d.values.flatMap(\.finished))
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.save(force: true) }
        }
    }

    static func key(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Starts the once-a-second look at the player.
    func start(_ player: SpeechPlayer) {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self, weak player] _ in
            MainActor.assumeIsolated {
                guard let self, let player else { return }
                self.tick(player)
            }
        }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick(_ p: SpeechPlayer) {
        let now = Date.now
        defer { lastTick = now }
        guard let last = lastTick else { return }
        let dt = now.timeIntervalSince(last)
        guard dt > 0, dt < 5 else { return }             // the app was asleep: not listening time
        let k = Self.key(now)
        if p.breakEnds != nil {
            days[k, default: .init()].breaks += dt
        } else if p.isPlaying, let id = p.documentID {
            days[k, default: .init()].docs[id.uuidString, default: .init()].seconds += dt
        } else if p.isSpeaking {
            days[k, default: .init()].paused += dt
        } else {
            return
        }
        dirty = true
        save(force: false)
    }

    /// The player reported a new place (every couple of seconds while reading, and on every jump).
    func position(_ id: UUID, _ offset: Int, length: Int, text: (NSRange) -> String) {
        defer { lastPlace = (id, offset) }
        if length > 0, Double(offset) / Double(length) >= 0.99, !finishedEver.contains(id.uuidString) {
            finishedEver.insert(id.uuidString)
            days[Self.key(.now), default: .init()].finished.append(id.uuidString)
            dirty = true
        }
        guard let last = lastPlace, last.doc == id else { return }
        let delta = offset - last.offset
        guard delta > 0, delta <= 3000 else { return }   // backwards or a jump: not heard
        let words = text(NSRange(location: last.offset, length: delta))
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        guard words > 0 else { return }
        days[Self.key(.now), default: .init()].docs[id.uuidString, default: .init()].words += words
        days[Self.key(.now), default: .init()].docs[id.uuidString, default: .init()].heard(last.offset, offset)
        dirty = true
    }

    func save(force: Bool) {
        guard dirty, force || Date.now.timeIntervalSince(lastSave) > 30 else { return }
        dirty = false
        lastSave = .now
        guard let data = try? JSONEncoder().encode(days) else { return }
        try? data.write(to: file, options: .atomic)
        let device = device
        Task.detached { await VaultMirror.shared.writeListening(data, device: device) }
    }

    // MARK: reading the log

    func day(_ d: Date) -> ListeningDay { days[Self.key(d)] ?? .init() }

    /// The first day with anything in the log.
    var firstDay: Date? {
        days.keys.sorted().first.flatMap { k in
            let p = k.split(separator: "-").compactMap { Int($0) }
            return p.count == 3 ? Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) : nil
        }
    }

    /// All days from `from` to `to` (inclusive), summed.
    func total(from: Date, to: Date) -> ListeningDay {
        var out = ListeningDay()
        var d = Calendar.current.startOfDay(for: from)
        let end = Calendar.current.startOfDay(for: to)
        while d <= end {
            if let x = days[Self.key(d)] {
                for (id, v) in x.docs {
                    out.docs[id, default: .init()].seconds += v.seconds
                    out.docs[id, default: .init()].words += v.words
                }
                out.paused += x.paused
                out.breaks += x.breaks
                out.finished += x.finished
            }
            guard let n = Calendar.current.date(byAdding: .day, value: 1, to: d) else { break }
            d = n
        }
        return out
    }
}
