import AppKit
import CoreGraphics
import Foundation

enum AreaID: String, CaseIterable, Identifiable {
    case body = "beden", english = "ingilizce", reading = "okuma", technical = "teknik", general = "genel"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .body: "Beden"
        case .english: "İngilizce"
        case .reading: "Okuma"
        case .technical: "Teknik"
        case .general: "Genel"
        }
    }
}

enum ProductionKind: String { case written, spoken }

/// One stretch of time. `build` = work done with Claude (Yapım), kept apart from production.
struct Session: Equatable {
    var start: Date
    var end: Date
    var area: AreaID
    var kind: ProductionKind
    var source: String      // auto | manual | trace
    var app: String
    var build: Bool

    var seconds: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

/// Which frontmost app counts as what. Window titles are not read, so no Accessibility permission.
enum Classifier {
    struct Rule { let area: AreaID; let kind: ProductionKind; let build: Bool; let name: String }

    static let rules: [String: Rule] = [
        "com.fatihgocgun.cumle": Rule(area: .english, kind: .written, build: false, name: "Cümle"),
        "com.fatihgocgun.teoria.mac": Rule(area: .reading, kind: .written, build: false, name: "Teoria"),
        "com.fatihgocgun.kivilcim.mac": Rule(area: .general, kind: .spoken, build: false, name: "Kıvılcım"),
        "md.obsidian": Rule(area: .general, kind: .written, build: false, name: "Obsidian"),
        "com.apple.iWork.Pages": Rule(area: .general, kind: .written, build: false, name: "Pages"),
        "com.apple.TextEdit": Rule(area: .general, kind: .written, build: false, name: "TextEdit"),
        "com.apple.dt.Xcode": Rule(area: .technical, kind: .written, build: false, name: "Xcode"),
        "com.microsoft.VSCode": Rule(area: .technical, kind: .written, build: false, name: "VS Code"),
        "com.anthropic.claudefordesktop": Rule(area: .technical, kind: .written, build: true, name: "Claude"),
        "com.todesktop.230313mzl4w4u92": Rule(area: .technical, kind: .written, build: true, name: "Cursor"),
        "com.apple.Terminal": Rule(area: .technical, kind: .written, build: true, name: "Terminal"),
        "com.googlecode.iterm2": Rule(area: .technical, kind: .written, build: true, name: "iTerm"),
    ]

    static func rule(for bundleID: String?) -> Rule? { bundleID.flatMap { rules[$0] } }
}

/// Reads every production trace and folds overlapping time into one count.
enum Ledger {
    static var eventsFolder: URL { Vault.url("_bus/events/tekne") }

    static func sessions(since: Date) -> [Session] {
        var out: [Session] = []
        for file in Vault.files(in: eventsFolder, ext: "jsonl") {
            for e in Vault.jsonLines(file) {
                guard let type = e["type"] as? String, type == "production.session" || type == "build.session",
                      let d = e["data"] as? [String: Any],
                      let s = (d["start"] as? String).flatMap(Day.parse),
                      let en = (d["end"] as? String).flatMap(Day.parse), en > since else { continue }
                out.append(Session(start: s, end: en,
                                   area: AreaID(rawValue: d["area"] as? String ?? "") ?? .general,
                                   kind: ProductionKind(rawValue: d["kind"] as? String ?? "") ?? .written,
                                   source: d["source"] as? String ?? "auto",
                                   app: d["app"] as? String ?? "",
                                   build: type == "build.session"))
            }
        }
        out += cumleTraces(since: since)
        return out
    }

    /// Cümle result files in ~/Downloads: sure_dk is active writing time (gaps over 2 min not counted).
    static func cumleTraces(since: Date) -> [Session] {
        var out: [Session] = []
        let files = Vault.files(in: Vault.downloads, ext: "json").filter {
            $0.lastPathComponent.range(of: #"-gun\d+-tezgah\.json$"#, options: .regularExpression) != nil
        }
        for f in files {
            guard let d = Vault.json(f), let endStr = d["bitis"] as? String, let end = Day.parse(endStr), end > since else { continue }
            if let minutes = d["sure_dk"] as? Double ?? (d["sure_dk"] as? Int).map(Double.init), minutes > 0 {
                out.append(Session(start: end.addingTimeInterval(-minutes * 60), end: end, area: .english,
                                   kind: .written, source: "trace", app: "Cümle", build: false))
            }
            if let spoken = d["sesli_okuma"] as? [String: Any], let sec = spoken["sure_sn"] as? Double, sec > 0 {
                out.append(Session(start: end.addingTimeInterval(-sec), end: end, area: .english,
                                   kind: .spoken, source: "trace", app: "Cümle sesli", build: false))
            }
        }
        return out
    }

    /// Union of intervals in seconds: overlapping time is counted once.
    static func unionSeconds(_ list: [Session]) -> TimeInterval {
        let sorted = list.filter { $0.seconds > 0 }.sorted { $0.start < $1.start }
        var total: TimeInterval = 0
        var cur: (Date, Date)?
        for s in sorted {
            if let c = cur, s.start <= c.1 {
                cur = (c.0, max(c.1, s.end))
            } else {
                if let c = cur { total += c.1.timeIntervalSince(c.0) }
                cur = (s.start, s.end)
            }
        }
        if let c = cur { total += c.1.timeIntervalSince(c.0) }
        return total
    }

    static func clip(_ list: [Session], from: Date, to: Date) -> [Session] {
        list.compactMap { s in
            let a = max(s.start, from), b = min(s.end, to)
            guard b > a else { return nil }
            var c = s; c.start = a; c.end = b
            return c
        }
    }
}

struct DaySummary: Identifiable {
    let id: String        // yyyy-MM-dd
    let date: Date
    let production: Int   // minutes, union
    let build: Int
    let byArea: [AreaID: Int]
    let written: Int
    let spoken: Int
}

enum Summaries {
    static func make(_ all: [Session], days: Int, now: Date = Date()) -> [DaySummary] {
        (0..<days).reversed().map { back in
            let start = Day.daysAgo(back, from: now)
            let end = Day.cal.date(byAdding: .day, value: 1, to: start)!
            let today = Ledger.clip(all, from: start, to: min(end, now))
            let prod = today.filter { !$0.build }
            var byArea: [AreaID: Int] = [:]
            for a in AreaID.allCases {
                let m = Int(Ledger.unionSeconds(prod.filter { $0.area == a }) / 60)
                if m > 0 { byArea[a] = m }
            }
            return DaySummary(id: Day.key(start), date: start,
                              production: Int(Ledger.unionSeconds(prod) / 60),
                              build: Int(Ledger.unionSeconds(today.filter(\.build)) / 60),
                              byArea: byArea,
                              written: Int(Ledger.unionSeconds(prod.filter { $0.kind == .written }) / 60),
                              spoken: Int(Ledger.unionSeconds(prod.filter { $0.kind == .spoken }) / 60))
        }
    }
}

/// Watches the frontmost app and keyboard/mouse idle time; writes closed sessions as bus events.
@MainActor
final class Tracker: ObservableObject {
    @Published private(set) var auto: Session?
    @Published private(set) var manual: Session?
    @Published private(set) var revision = 0

    static let idleLimit: TimeInterval = 120
    static let tick: TimeInterval = 10
    static let maxChunk: TimeInterval = 15 * 60
    static let minimumKept: TimeInterval = 30

    private var timer: Timer?
    private let manualKey = "tekne.manual"

    init() {
        if let saved = UserDefaults.standard.dictionary(forKey: manualKey),
           let start = saved["start"] as? Double,
           let area = AreaID(rawValue: saved["area"] as? String ?? ""),
           let kind = ProductionKind(rawValue: saved["kind"] as? String ?? "") {
            manual = Session(start: Date(timeIntervalSince1970: start), end: Date(), area: area, kind: kind,
                             source: "manual", app: "Elle", build: false)
        }
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.tick, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.step() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeAuto(at: Date()) }
        }
        step()
    }

    nonisolated static func idleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    func step() {
        step(now: Date(), idle: Self.idleSeconds(), bundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    /// One tick. Parameters are explicit so the logic can be tested with a fake clock.
    func step(now: Date, idle: TimeInterval, bundleID: String?) {
        if manual != nil { manual?.end = now }
        let rule = Classifier.rule(for: bundleID)
        let active = idle < Self.idleLimit
        if var cur = auto {
            let same = rule.map { $0.name == cur.app } ?? false
            if active && same && now.timeIntervalSince(cur.end) < Self.idleLimit {
                cur.end = now
                if cur.seconds >= Self.maxChunk {
                    write(cur)
                    cur.start = now
                }
                auto = cur
                return
            }
            closeAuto(at: active ? now : now.addingTimeInterval(-idle))
        }
        if active, let r = rule {
            let begin = now.addingTimeInterval(-min(idle, Self.tick))
            auto = Session(start: begin, end: now, area: r.area, kind: r.kind, source: "auto", app: r.name, build: r.build)
        }
    }

    func closeAuto(at end: Date) {
        guard var cur = auto else { return }
        cur.end = max(cur.start, min(cur.end, end))
        write(cur)
        auto = nil
    }

    func startManual(area: AreaID, kind: ProductionKind) {
        stopManual()
        let now = Date()
        manual = Session(start: now, end: now, area: area, kind: kind, source: "manual", app: "Elle", build: false)
        UserDefaults.standard.set(["start": now.timeIntervalSince1970, "area": area.rawValue, "kind": kind.rawValue], forKey: manualKey)
    }

    func stopManual() {
        guard var m = manual else { return }
        m.end = Date()
        write(m)
        manual = nil
        UserDefaults.standard.removeObject(forKey: manualKey)
    }

    func flush() {
        closeAuto(at: Date())
        if var m = manual {   // keep the manual timer running across restarts; save what is done so far
            m.end = Date()
            write(m)
            manual?.start = m.end
            UserDefaults.standard.set(["start": m.end.timeIntervalSince1970, "area": m.area.rawValue, "kind": m.kind.rawValue], forKey: manualKey)
        }
    }

    /// Open sessions, counted live but not yet on disk.
    var openSessions: [Session] { [auto, manual].compactMap { $0 } }

    private func write(_ s: Session) {
        guard s.seconds >= Self.minimumKept else { return }
        let event: [String: Any] = [
            "v": 1, "id": UUID().uuidString.lowercased(), "ts": Day.iso(s.end), "app": "tekne", "device": Vault.device,
            "type": s.build ? "build.session" : "production.session", "subject": "area:\(s.area.rawValue)",
            "data": ["start": Day.iso(s.start), "end": Day.iso(s.end), "minutes": NSDecimalNumber(string: String(format: "%.1f", s.seconds / 60)), "seconds": Int(s.seconds.rounded()),
                     "kind": s.kind.rawValue, "area": s.area.rawValue, "source": s.source, "app": s.app],
        ]
        do {
            try FileManager.default.createDirectory(at: Ledger.eventsFolder, withIntermediateDirectories: true)
            let file = Ledger.eventsFolder.appendingPathComponent(Vault.device + ".jsonl")
            var line = try JSONSerialization.data(withJSONObject: event, options: [.sortedKeys])
            line.append(0x0A)
            if let h = try? FileHandle(forWritingTo: file) {
                defer { try? h.close() }
                try h.seekToEnd()
                try h.write(contentsOf: line)
            } else {
                try line.write(to: file)
            }
            revision += 1
        } catch {
            NSLog("Tekne: event not written: \(error)")
        }
    }
}
