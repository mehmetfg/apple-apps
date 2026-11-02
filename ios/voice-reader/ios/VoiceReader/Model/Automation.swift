// Listening automations: a row of steps played one after another without touching the phone. A reading step takes a
// library folder's current book (the one last listened to and not finished) from where it was left, for so many
// minutes of listening; a pause step is a quiet thinking break with a short spoken announcement of what comes next.
// Kept in UserDefaults as JSON, with the step each one was left at, so a stopped automation goes on from there.
import Foundation
import Observation

struct AutomationStep: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case read, pause }
    var id = UUID()
    var kind: Kind
    var folder: String?             // read: the library folder
    var seconds: Int                // read: minutes of listening × 60 · pause: length of the break

    static func read(_ folder: String, minutes: Int) -> AutomationStep { .init(kind: .read, folder: folder, seconds: minutes * 60) }
    static func pause(seconds: Int) -> AutomationStep { .init(kind: .pause, folder: nil, seconds: seconds) }

    var title: String {
        switch kind {
        case .read: "\(folder ?? "Klasör seçilmedi") · \(Format.minutes(seconds))"
        case .pause: "Düşünme arası · \(Format.clock(seconds))"
        }
    }
}

struct Automation: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var steps: [AutomationStep]

    var readingSeconds: Int { steps.filter { $0.kind == .read }.reduce(0) { $0 + $1.seconds } }
    var totalSeconds: Int { steps.reduce(0) { $0 + $1.seconds } }

    /// The pilot (2026-10-23): philosophy, science, engineering, a minute's pause between them.
    static let pilot = Automation(name: "Üç dal · 15 dakika", steps: [
        .read("Felsefe", minutes: 15), .pause(seconds: 60),
        .read("Bilimler", minutes: 15), .pause(seconds: 60),
        .read("Mühendislik", minutes: 15),
    ])
}

/// Where an automation was left: the step it was in and the listening already done in that step. Kept for each
/// automation, so each one goes on from its own place; cleared when it plays to its end.
struct AutomationProgress: Codable, Hashable, Sendable {
    var stepID: UUID
    var step: Int
    var listened: Double            // reading step: seconds already heard in it
    var savedAt: Date
}

/// A place to go on from: the step and the seconds already heard in it.
struct ResumePoint: Hashable, Sendable {
    var step: Int
    var listened: Double
}

@MainActor
@Observable
final class AutomationStore {
    private(set) var list: [Automation] = []
    private(set) var progress: [UUID: AutomationProgress] = [:]
    private(set) var lastRunID: UUID?
    @ObservationIgnored private let key = "automations.v1"
    @ObservationIgnored private let progressKey = "automations.progress.v1"
    @ObservationIgnored private let lastKey = "automations.last"

    init() {
        if let data = UserDefaults.standard.data(forKey: key), let l = try? JSONDecoder().decode([Automation].self, from: data) {
            list = l
        }
        if !UserDefaults.standard.bool(forKey: "automations.pilot") {
            UserDefaults.standard.set(true, forKey: "automations.pilot")
            list.insert(.pilot, at: 0)
            save()
        }
        if let data = UserDefaults.standard.data(forKey: progressKey),
           let p = try? JSONDecoder().decode([UUID: AutomationProgress].self, from: data) {
            let ids = Set(list.map(\.id))
            progress = p.filter { ids.contains($0.key) }
        }
        lastRunID = UserDefaults.standard.string(forKey: lastKey).flatMap(UUID.init)
    }

    func automation(_ id: UUID) -> Automation? { list.first { $0.id == id } }

    /// The automation the library card offers: the one chosen or run last, else the first in the list.
    var featured: Automation? { lastRunID.flatMap(automation) ?? list.first }

    func select(_ id: UUID) {
        lastRunID = id
        UserDefaults.standard.set(id.uuidString, forKey: lastKey)
    }

    func upsert(_ a: Automation) {
        if let i = list.firstIndex(where: { $0.id == a.id }) { list[i] = a } else { list.append(a) }
        save()
    }

    func delete(_ ids: some Sequence<UUID>) {
        let set = Set(ids)
        list.removeAll { set.contains($0.id) }
        for id in set { progress[id] = nil }
        save()
        saveProgress()
    }

    func move(from: IndexSet, to: Int) {
        list.move(fromOffsets: from, toOffset: to)
        save()
    }

    // MARK: where it was left

    /// Where `a` goes on from, or nil when it was not started or played to its end. A thinking break counts as done
    /// once it began, and a reading step with only a few seconds left as read: going on starts with the next reading.
    /// A step edited away falls back to the place it had.
    func resumePoint(for a: Automation) -> ResumePoint? {
        guard let p = progress[a.id] else { return nil }
        var i = a.steps.firstIndex { $0.id == p.stepID } ?? min(p.step, a.steps.count)
        var listened = a.steps.indices.contains(i) && a.steps[i].id == p.stepID ? p.listened : 0
        while a.steps.indices.contains(i), a.steps[i].kind == .pause || Double(a.steps[i].seconds) - listened <= 5 {
            i += 1
            listened = 0
        }
        guard a.steps.indices.contains(i), i > 0 || listened > 0 else { return nil }
        return ResumePoint(step: i, listened: listened)
    }

    func noteProgress(_ a: Automation, step: Int, listened: Double) {
        guard a.steps.indices.contains(step) else { clearProgress(a.id); return }
        progress[a.id] = AutomationProgress(stepID: a.steps[step].id, step: step, listened: max(0, listened), savedAt: .now)
        saveProgress()
    }

    func clearProgress(_ id: UUID) {
        guard progress[id] != nil else { return }
        progress[id] = nil
        saveProgress()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: key) }
    }

    private func saveProgress() {
        if let data = try? JSONEncoder().encode(progress) { UserDefaults.standard.set(data, forKey: progressKey) }
    }
}

/// What an automation is doing now (shown in the mini player and the automation screen).
struct AutomationRun: Equatable {
    enum Phase: Equatable { case announcing, reading, thinking }
    var automation: Automation
    var step = 0
    var phase: Phase = .announcing
    var ending = false              // the last step is done, "Otomasyon bitti" is being said
    var documentTitle: String?
    var phaseEnds: Date?            // thinking: when the pause ends
    var stepSeconds: Double = 0     // reading: the step's listening time
    var listenedBefore: Double = 0  // reading: time already listened in this step (a book ended, the next one went on)

    var stepTitle: String {
        guard automation.steps.indices.contains(step) else { return "" }
        let s = automation.steps[step]
        return s.kind == .read ? (s.folder ?? "") : "Düşünme arası"
    }
    var position: String { "\(step + 1)/\(automation.steps.count)" }
}

enum SegmentOutcome: Sendable { case timeUp, finished, cancelled }

extension Format {
    /// 900 → "15 dk", 90 → "1,5 dk".
    static func minutes(_ s: Int) -> String {
        s % 60 == 0 ? "\(s / 60) dk" : String(format: "%.1f dk", Double(s) / 60).replacingOccurrences(of: ".", with: ",")
    }
    /// 75 → "1:15".
    static func clock(_ s: Int) -> String { "\(s / 60):\(String(format: "%02d", s % 60))" }
}

/// Play or a jump was asked on a finished book: the reader decides whether a new reading starts.
struct FinishedPrompt: Identifiable, Equatable {
    var id: UUID
    var title: String
    var finishedAt: Date
    var times: Int                  // readings finished so far
    var target: Int?                // the place asked for, if not the start or the end
}

/// An automation step's book is finished: go to the folder's next unfinished book, go on with the book that is
/// loaded, or stop. Answered on screen or with the headphone keys (⏭ next · ⏮ current · ⏯ stop).
struct AutomationChoice: Equatable {
    enum Answer: Sendable { case next, current, stop }
    var finishedTitle: String?      // nil: the folder had no book yet
    var folder: String
    var nextID: UUID?
    var nextTitle: String?
    var currentID: UUID?
    var currentTitle: String?
}
