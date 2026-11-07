// TimeBox — the morning time box shared by Cümle (09–10 English) and Teoria Sabah (10–11 review).
// Kurultay decision 2026-11-05: the clock starts on the first touch, warns 5 minutes before the end,
// at the end shows a soft limit (finish and save, or +10 minutes once), and a "done" card on finish.
// Plan: vault/_bus/plan/sabah.json · day state: vault/_bus/plan/durum/<yyyy-MM-dd>.json (Tekne reads both).
import Foundation
import SwiftUI

struct TimeBoxBlock: Codable, Hashable {
    var id: String          // "english" · "review"
    var title: String       // "İngilizce" · "Mütalaa"
    var app: String         // "cumle" · "teoria"
    var start: String       // "09:00"
    var minutes: Int        // 60
}

struct TimeBoxPlan: Codable {
    var version: Int = 1
    var blocks: [TimeBoxBlock]
    var warnMinutes: Int = 5
    var extendMinutes: Int = 10

    static let standard = TimeBoxPlan(blocks: [
        TimeBoxBlock(id: "english", title: "İngilizce", app: "cumle", start: "09:00", minutes: 60),
        TimeBoxBlock(id: "review", title: "Mütalaa", app: "teoria", start: "10:00", minutes: 60),
        TimeBoxBlock(id: "second", title: "İkinci dikkat", app: "teoria", start: "14:00", minutes: 20),
    ])

    static func file(_ vault: URL) -> URL { vault.appendingPathComponent("_bus/plan/sabah.json") }

    /// Reads the plan; writes the standard one the first time.
    static func load(vault: URL?) -> TimeBoxPlan {
        guard let vault else { return .standard }
        let u = file(vault)
        if let d = try? Data(contentsOf: u), let p = try? JSONDecoder().decode(TimeBoxPlan.self, from: d) { return p }
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? e.encode(standard) { try? d.write(to: u, options: .atomic) }
        return .standard
    }

    func block(_ id: String) -> TimeBoxBlock? { blocks.first { $0.id == id } }
    func index(_ id: String) -> Int { (blocks.firstIndex { $0.id == id } ?? 0) + 1 }
    func next(after id: String) -> TimeBoxBlock? {
        guard let i = blocks.firstIndex(where: { $0.id == id }), i + 1 < blocks.count else { return nil }
        return blocks[i + 1]
    }
}

struct TimeBoxState: Codable, Equatable {
    var started: Date?
    var extendedMinutes: Int = 0
    var finished: Date?
}

/// The day's state file: one entry per block. Several apps and devices write; each entry merges by keeping
/// the earliest start, the largest extension and the earliest finish.
enum TimeBoxDay {
    static func key(_ d: Date = Date()) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }
    static func file(_ vault: URL, _ day: String) -> URL { vault.appendingPathComponent("_bus/plan/durum/\(day).json") }

    static func read(vault: URL, day: String = key()) -> [String: TimeBoxState] {
        guard let d = try? Data(contentsOf: file(vault, day)) else { return [:] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([String: TimeBoxState].self, from: d)) ?? [:]
    }

    static func merge(_ a: TimeBoxState?, _ b: TimeBoxState) -> TimeBoxState {
        guard let a else { return b }
        var r = a
        if let s = b.started { r.started = min(a.started ?? s, s) }
        r.extendedMinutes = max(a.extendedMinutes, b.extendedMinutes)
        if let f = b.finished { r.finished = min(a.finished ?? f, f) }
        return r
    }

    static func write(vault: URL, id: String, _ s: TimeBoxState, day: String = key()) {
        var all = read(vault: vault, day: day)
        all[id] = merge(all[id], s)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let u = file(vault, day)
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? enc.encode(all) { try? d.write(to: u, options: .atomic) }
    }
}

enum TimeBoxPhase: Equatable { case idle, running, warning, over, done }

@MainActor
final class TimeBoxClock: ObservableObject {
    let block: TimeBoxBlock
    let plan: TimeBoxPlan
    @Published private(set) var state: TimeBoxState
    @Published private(set) var now = Date()
    @Published var overDismissedAt: Date?
    /// Called after every change, so the app can persist it (vault file, event log, PDM bus).
    var onChange: ((TimeBoxState, String) -> Void)?
    private var timer: Timer?
    private var day = TimeBoxDay.key()

    init(block: TimeBoxBlock, plan: TimeBoxPlan, state: TimeBoxState = TimeBoxState()) {
        self.block = block
        self.plan = plan
        self.state = state
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    deinit { timer?.invalidate() }

    private func tick() {
        now = Date()
        let k = TimeBoxDay.key(now)
        if k != day { day = k; state = TimeBoxState(); overDismissedAt = nil }   // a new day starts clean
    }

    /// Adopts state coming from elsewhere (another device, the day file); never moves backwards.
    func adopt(_ s: TimeBoxState) {
        let m = TimeBoxDay.merge(state, s)
        if m != state { state = m }
    }

    var limit: TimeInterval { Double(block.minutes + state.extendedMinutes) * 60 }
    var elapsed: TimeInterval {
        guard let s = state.started else { return 0 }
        return (state.finished ?? now).timeIntervalSince(s)
    }
    var remaining: TimeInterval { max(0, limit - elapsed) }
    var progress: Double { limit > 0 ? min(1, elapsed / limit) : 0 }
    var canExtend: Bool { state.extendedMinutes == 0 }
    var minutesUsed: Int { Int((elapsed / 60).rounded()) }

    var phase: TimeBoxPhase {
        if state.finished != nil { return .done }
        guard state.started != nil else { return .idle }
        if elapsed >= limit { return .over }
        if remaining <= Double(plan.warnMinutes * 60) { return .warning }
        return .running
    }

    /// The modal shows at the end, until the user picks something (or dismisses it for 2 minutes).
    var showOver: Bool {
        guard phase == .over else { return false }
        if let d = overDismissedAt, now.timeIntervalSince(d) < 120 { return false }
        return true
    }

    func touch() {
        guard state.started == nil, state.finished == nil else { return }
        state.started = Date()
        onChange?(state, "timebox.started")
    }

    func extend() {
        guard canExtend, state.finished == nil else { return }
        state.extendedMinutes = plan.extendMinutes
        overDismissedAt = nil
        onChange?(state, "timebox.extended")
    }

    func finish() {
        guard state.finished == nil else { return }
        if state.started == nil { state.started = Date() }
        state.finished = Date()
        onChange?(state, "timebox.finished")
    }

    static func clock(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Views

private extension TimeBoxPhase {
    var tint: Color {
        switch self {
        case .warning: Color.orange
        case .over: Color.red
        case .done: Color.green
        default: Color.accentColor
        }
    }
}

/// Thin strip at the top of the working screen.
struct TimeBoxBar: View {
    @ObservedObject var clock: TimeBoxClock

    var label: String {
        switch clock.phase {
        case .idle: "\(clock.block.title) · \(clock.block.minutes) dk · ilk dokunuşta başlar"
        case .running: "\(clock.block.title) · \(TimeBoxClock.clock(clock.remaining)) kaldı"
        case .warning: "5 dakika kaldı · bitir"
        case .over: "Süre doldu"
        case .done: "\(clock.block.title) tamamlandı · \(clock.minutesUsed) dk"
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: clock.phase == .done ? "checkmark.circle.fill" : "timer")
                    .foregroundStyle(clock.phase.tint)
                Text(label).font(.callout.weight(clock.phase == .warning || clock.phase == .over ? .semibold : .regular))
                    .foregroundStyle(clock.phase == .warning || clock.phase == .over ? clock.phase.tint : .primary)
                    .monospacedDigit()
                Spacer()
                if clock.state.extendedMinutes > 0 && clock.phase != .done {
                    Text("+\(clock.state.extendedMinutes) dk").font(.caption).foregroundStyle(.secondary)
                }
                if clock.phase == .running || clock.phase == .warning {
                    Text("blok \(clock.plan.index(clock.block.id))/\(clock.plan.blocks.count)").font(.caption).foregroundStyle(.secondary)
                }
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(clock.phase.tint).frame(width: g.size.width * clock.progress)
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.bar)
        .animation(.easeInOut(duration: 0.3), value: clock.phase)
        .accessibilityElement(children: .combine)
    }
}

/// The soft limit: shown over the work when the time is up.
struct TimeBoxOverCard: View {
    @ObservedObject var clock: TimeBoxClock
    var finishLabel = "Bitir ve kaydet"
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "hourglass.bottomhalf.filled").font(.system(size: 34)).foregroundStyle(.red)
            Text("Bugünlük süre doldu").font(.title2.bold())
            Text("\(clock.block.title) için \(clock.block.minutes + clock.state.extendedMinutes) dakika. Kalanı yarına bırak; yarım iş de kaydedilir.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 380)
            HStack(spacing: 10) {
                if clock.canExtend {
                    Button { clock.extend() } label: { Text("+\(clock.plan.extendMinutes) dk (bir kez)").padding(.horizontal, 6) }
                        .buttonStyle(.bordered)
                }
                Button { onFinish(); clock.finish() } label: { Label(finishLabel, systemImage: "checkmark").padding(.horizontal, 6) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command)
            }
            Button("Şimdi değil") { clock.overDismissedAt = Date() }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 18).fill(.regularMaterial))
        .shadow(radius: 24)
        .padding(24)
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }
}

/// Shown once the block is finished: the "celebrate" moment and what comes next.
struct TimeBoxDoneCard: View {
    @ObservedObject var clock: TimeBoxClock
    var openNext: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 30)).foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(clock.block.title) tamamlandı").font(.headline)
                Text("\(clock.minutesUsed) dk · blok \(clock.plan.index(clock.block.id))/\(clock.plan.blocks.count)"
                     + (clock.state.finished.map { " · " + $0.formatted(date: .omitted, time: .shortened) } ?? ""))
                    .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            if let n = clock.plan.next(after: clock.block.id), let openNext {
                Button { openNext() } label: { Label("Sırada: \(n.title)", systemImage: "arrow.right.circle") }
                    .buttonStyle(.borderedProminent)
            } else if clock.plan.next(after: clock.block.id) == nil {
                Text("Günün blokları bitti").font(.subheadline.weight(.semibold)).foregroundStyle(.green)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.green.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.green.opacity(0.35)))
    }
}

/// Appends one PDM Ağı event: vault/_bus/events/<app>/<device>.jsonl (format of _bus/README.md).
enum TimeBoxBus {
    static func emit(vault: URL, app: String, device: String, type: String, block: TimeBoxBlock, state: TimeBoxState) {
        let iso = ISO8601DateFormatter()
        var data: [String: Any] = ["block": block.id, "title": block.title, "minutes": block.minutes, "extended": state.extendedMinutes]
        if let s = state.started { data["start"] = iso.string(from: s) }
        if let f = state.finished { data["end"] = iso.string(from: f) }
        let event: [String: Any] = ["v": 1, "id": UUID().uuidString.lowercased(), "ts": iso.string(from: Date()), "app": app,
                                    "device": device, "type": type, "subject": "timebox:\(block.id)", "data": data]
        let dir = vault.appendingPathComponent("_bus/events/\(app)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(device).jsonl")
        guard var line = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]) else { return }
        line.append(0x0A)
        if let h = try? FileHandle(forWritingTo: file) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: line)
        } else {
            try? line.write(to: file)
        }
    }
}
