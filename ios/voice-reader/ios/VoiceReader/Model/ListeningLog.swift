// The listening log: what was heard each day, per document. Kept from 2026-10-22 on (nothing older exists).
// Once a second, while a reading session or a wait exists, it looks at the player: playing → that document's listening seconds; paused in a reading session →
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

    init() {}

    /// Every field may be missing: a day written by an older or a newer version still reads (2026-11-10: one day
    /// that failed to decode used to empty the whole history on the next save).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        docs = ((try? c.decodeIfPresent([String: Lossy<ListeningDoc>].self, forKey: .docs)) ?? nil)?.compactMapValues(\.value) ?? [:]
        paused = (try? c.decodeIfPresent(Double.self, forKey: .paused)) ?? nil ?? 0
        breaks = (try? c.decodeIfPresent(Double.self, forKey: .breaks)) ?? nil ?? 0
        finished = (try? c.decodeIfPresent([String].self, forKey: .finished)) ?? nil ?? []
    }
}

@MainActor
@Observable
final class ListeningLog {
    static let wordsPerPage = 225.0                  // the vault's A5 page (Orkestra's measure)

    /// The log itself is not observed: it changes every second while a book is read, and every screen that showed
    /// a number from it was drawn again each time. Readers observe `revision`, which moves at most every
    /// `publishEvery` seconds while listening and at once when listening starts, pauses or stops. The counting
    /// itself is untouched: every second and every word still goes into `days` as it happens.
    @ObservationIgnored private(set) var days: [String: ListeningDay] = [:]
    private var revision = 0
    @ObservationIgnored private var published = Date.distantPast
    private static let publishEvery = 15.0

    @ObservationIgnored private var finishedEver: Set<String> = []
    @ObservationIgnored private var lastTick: Date?
    @ObservationIgnored private var lastPlace: (doc: UUID, offset: Int, at: Date)?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private weak var player: SpeechPlayer?
    @ObservationIgnored private var dirty = false
    @ObservationIgnored private var loaded = false       // the file has been read (nothing is written before that)
    @ObservationIgnored private var lastSave = Date.distantPast
    @ObservationIgnored private let file: URL
    @ObservationIgnored private let device: String
    private static let writer = DispatchQueue(label: "voice-reader.listening-save", qos: .utility)

    init(device: String) {
        self.device = device
        let dir = URL.applicationSupportDirectory.appending(path: "VoiceReader/listening", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        file = dir.appending(path: "\(device).json")
        // the log is read off the main thread (it grows with every day listened); what is counted meanwhile
        // (normally nothing: nothing plays in the first moments) is added to it when it arrives
        let file = file
        Task.detached(priority: .userInitiated) { [weak self] in
            // day by day: one bad day is left out, the others are kept; a file that cannot be read at all is put
            // aside under another name before anything is written over it
            let raw = try? Data(contentsOf: file)
            let d = raw.flatMap { try? JSONDecoder().decode([String: Lossy<ListeningDay>].self, from: $0) }?.compactMapValues(\.value)
            if let raw, !raw.isEmpty, d == nil {
                let aside = file.deletingLastPathComponent().appending(path: "\(file.deletingPathExtension().lastPathComponent).unread-\(Int(Date.now.timeIntervalSince1970)).json")
                try? raw.write(to: aside, options: .atomic)
            }
            await self?.adopt(d ?? [:])
        }
        let nc = NotificationCenter.default
        nc.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.save(force: true) }
        }
        // leaving the screen: the write is waited for, so it is on disk before the app can be suspended
        nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.save(force: true); Self.writer.sync {} }
        }
    }

    private func adopt(_ stored: [String: ListeningDay]) {
        guard !loaded else { return }
        var merged = stored
        let known = Set(stored.values.flatMap(\.finished))
        for (k, d) in days {
            var m = merged[k] ?? .init()
            for (id, v) in d.docs {
                var x = m.docs[id] ?? .init()
                x.seconds += v.seconds
                x.words += v.words
                for r in v.ranges where r.count == 2 { x.heard(r[0], r[1]) }
                m.docs[id] = x
            }
            m.paused += d.paused
            m.breaks += d.breaks
            m.finished += d.finished.filter { !known.contains($0) }
            merged[k] = m
        }
        days = merged
        finishedEver.formUnion(known)
        loaded = true
        publish()
    }

    static func key(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Follows the player: the once-a-second look runs only while there is something to count (a reading session,
    /// playing or paused, or a wait), not from launch for ever.
    func start(_ player: SpeechPlayer) {
        guard self.player == nil else { return }
        self.player = player
        watch()
    }

    private func watch() {
        guard let p = player else { return }
        let live = withObservationTracking {
            let paused = p.isPaused                          // a pause or a resume shows on screen at once
            if paused { DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.save(force: true) } } }
            return p.isSpeaking || p.breakEnds != nil
        } onChange: { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.watch() } }
        }
        if live, timer == nil {
            lastTick = .now                                  // counted from the moment the session began
            let t = Timer(timeInterval: 1, repeats: true) { [weak self, weak p] _ in
                MainActor.assumeIsolated {
                    guard let self, let p else { return }
                    self.tick(p)
                }
            }
            t.tolerance = 0.2
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else if !live, timer != nil {
            timer?.invalidate(); timer = nil
            lastTick = nil
            save(force: true)
        }
        publish()
    }

    /// Tells the screens the log changed.
    private func publish() {
        published = .now
        revision += 1
    }

    private func publishSoon() {
        if Date.now.timeIntervalSince(published) >= Self.publishEvery { publish() }
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
        publishSoon()
        save(force: false)
    }

    /// The player reported a new place (every couple of seconds while reading, and on every jump).
    func position(_ id: UUID, _ offset: Int, length: Int, text: (NSRange) -> String) {
        let now = Date.now
        defer { lastPlace = (id, offset, now) }
        if length > 0, Double(offset) / Double(length) >= 0.99, !finishedEver.contains(id.uuidString) {
            finishedEver.insert(id.uuidString)
            days[Self.key(.now), default: .init()].finished.append(id.uuidString)
            dirty = true
            publish()
        }
        guard let last = lastPlace, last.doc == id else { return }
        let delta = offset - last.offset
        // backwards or a jump: not heard. A step forward longer than the voice can have read since the last report
        // (90 characters a second is beyond 500 words a minute) is a skip, not listening: sentence, paragraph and
        // 30-second skips used to be counted as words and pages.
        let reach = Int(now.timeIntervalSince(last.at) * 90) + 150
        guard delta > 0, delta <= min(3000, reach) else { return }
        let words = text(NSRange(location: last.offset, length: delta))
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        guard words > 0 else { return }
        days[Self.key(.now), default: .init()].docs[id.uuidString, default: .init()].words += words
        days[Self.key(.now), default: .init()].docs[id.uuidString, default: .init()].heard(last.offset, offset)
        dirty = true
        publishSoon()
    }

    /// Called on the main thread after each save with the whole log (Akşam tekrarı: the last days go to Teoria
    /// through the shared App Group, and the reminder before bed is planned).
    @ObservationIgnored var onSave: (([String: ListeningDay]) -> Void)?

    /// Hands the log to `onSave` again without writing (the app came to the front: the reminder is planned anew).
    func republish() {
        guard loaded else { return }
        onSave?(days)
    }

    /// The log is encoded and written on a background queue (in order), never on the main thread.
    func save(force: Bool) {
        guard loaded, dirty, force || Date.now.timeIntervalSince(lastSave) > 30 else { return }
        dirty = false
        lastSave = .now
        onSave?(days)
        let days = days, file = file, device = device
        Self.writer.async {
            guard let data = try? JSONEncoder().encode(days) else { return }
            try? data.write(to: file, options: .atomic)
            Task.detached { await VaultMirror.shared.writeListening(data, device: device) }
        }
    }

    // MARK: reading the log

    func day(_ d: Date) -> ListeningDay { _ = revision; return days[Self.key(d)] ?? .init() }

    /// The first day with anything in the log.
    var firstDay: Date? {
        _ = revision
        return days.keys.sorted().first.flatMap { k in
            let p = k.split(separator: "-").compactMap { Int($0) }
            return p.count == 3 ? Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) : nil
        }
    }

    /// All days from `from` to `to` (inclusive), summed.
    func total(from: Date, to: Date) -> ListeningDay {
        _ = revision
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
