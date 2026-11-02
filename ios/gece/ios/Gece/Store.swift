// Nights on the phone, the PDM bus, the bedtime reminder and the settings.
import Foundation
import PDMBus
import SwiftUI
import UserNotifications

struct Pain: Codable, Hashable {
    var lowBack: Int
    var neck: Int
    var knee: Int

    static let zero = Pain(lowBack: 0, neck: 0, knee: 0)
    var max: Int { Swift.max(lowBack, neck, knee) }
}

struct StepResult: Codable, Hashable {
    var move: String
    var side: String?
    var done: Bool
    var painful: Bool
    /// Recall phase: did the person name the move before it was shown? nil when not asked.
    var recalled: Bool?
}

struct NightRecord: Codable, Hashable, Identifiable {
    var id = UUID()
    var start: Date
    var end: Date
    var module: String      // the set key: A, B or C
    var short: Bool
    var phase: String?
    var nightNo: Int?
    var steps: [StepResult]
    var before: Pain
    var after: Pain?
    var redFlags: [String]

    var seconds: Int { Int(end.timeIntervalSince(start)) }
    var doneCount: Int { steps.filter(\.done).count }
    var day: String { Health.dayFormat.string(from: start.addingTimeInterval(-5 * 3600)) }   // a night after midnight is the day before
}

@MainActor
final class Store: ObservableObject {
    static let shared = Store()
    let bus = PDMBus(app: "gece")

    @Published private(set) var nights: [NightRecord] = []
    @Published private(set) var checks: [HabitCheck] = []
    @AppStorage("anchor") var anchor = "Dişlerimi fırçaladıktan sonra" { didSet { scheduleReminder() } }
    @AppStorage("bedtimeMinutes") var bedtimeMinutes = 23 * 60 + 30 { didSet { scheduleReminder() } }
    @AppStorage("leadMinutes") var leadMinutes = 30 { didSet { scheduleReminder() } }
    @AppStorage("voice") var voice = true
    @AppStorage("shortNights") var shortNights = false
    @AppStorage("emittedDays") private var emittedDays = ""

    private var folder: URL {
        let d = URL.applicationSupportDirectory.appending(path: "Gece", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private var file: URL { folder.appending(path: "nights.json") }
    private var checksFile: URL { folder.appending(path: "habit-checks.json") }

    private init() {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        if let d = try? Data(contentsOf: file) { nights = (try? dec.decode([NightRecord].self, from: d)) ?? [] }
        if let d = try? Data(contentsOf: checksFile) { checks = (try? dec.decode([HabitCheck].self, from: d)) ?? [] }
    }

    // MARK: habit

    /// Days with a real night: no red flag and at least three moves done. A second run on the same night counts once.
    var practiceDays: [String] {
        var seen = Set<String>()
        return nights.filter { $0.redFlags.isEmpty && $0.doneCount >= 3 }.map(\.day).filter { seen.insert($0).inserted }
    }

    /// Practised nights before tonight (tonight's own run does not move tonight's set).
    var practisedBeforeTonight: Int {
        let today = Health.dayFormat.string(from: Date().addingTimeInterval(-5 * 3600))
        return practiceDays.filter { $0 != today }.count
    }

    var phase: HabitPhase { HabitPhase.of(nights: practisedBeforeTonight, lastChecks: checks) }

    /// Moves marked "Ağrıttı" on two or more of the last 14 nights: not offered again, the stop's gentler move takes the place.
    var avoidMoves: Set<String> {
        var count: [String: Int] = [:]
        for n in nights.suffix(14) {
            for m in Set(n.steps.filter(\.painful).map(\.move)) { count[m, default: 0] += 1 }
        }
        return Set(count.filter { $0.value >= 2 }.keys)
    }

    func tonightPlan(legHeavy: Bool) -> NightPlan {
        let n = practisedBeforeTonight
        let (key, reason) = HabitPhase.setKey(nights: n, legHeavy: legHeavy)
        var p = Catalog.shared.plan(set: key, short: shortNights, avoid: avoidMoves, reason: reason)
        p.phase = phase
        p.nightNo = n + 1
        return p
    }

    /// Nights in a row up to yesterday (or today when tonight is done).
    var streak: Int {
        let days = Set(practiceDays)
        var d = Date().addingTimeInterval(-5 * 3600)
        if !days.contains(Health.dayFormat.string(from: d)) { d = d.addingTimeInterval(-86400) }
        var n = 0
        while days.contains(Health.dayFormat.string(from: d)) { n += 1; d = d.addingTimeInterval(-86400) }
        return n
    }

    /// Yesterday was missed after a start: tonight at least the mini night ("never miss twice").
    var missedYesterday: Bool {
        guard !practiceDays.isEmpty, tonightDone == nil else { return false }
        let y = Health.dayFormat.string(from: Date().addingTimeInterval(-29 * 3600))
        return !practiceDays.contains(y)
    }

    /// The weekly automaticity check is due: after the first week, then every 7 days.
    var checkDue: Bool {
        guard practiceDays.count >= 7 else { return false }
        guard let last = checks.last else { return true }
        return Date().timeIntervalSince(last.date) >= 6.5 * 86400
    }

    func saveCheck(_ items: [Int]) {
        let c = HabitCheck(date: .now, items: items, nightNo: practiceDays.count)
        checks.append(c)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(checks) { try? d.write(to: checksFile, options: .atomic) }
        bus.emit("habit.check", subject: "habit:gece", data: [
            "instrument": .string("SRBAI"), "items": .array(items.map(PDMValue.int)), "score": .double((c.score * 10).rounded() / 10),
            "night_no": .int(c.nightNo), "phase": .string(phase.rawValue), "streak": .int(streak)])
        Task { await bus.sync() }
    }

    var tonightDone: NightRecord? {
        let today = Health.dayFormat.string(from: Date().addingTimeInterval(-5 * 3600))
        return nights.last { $0.day == today && $0.redFlags.isEmpty }
    }

    func save(_ n: NightRecord) {
        nights.append(n)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(nights) { try? d.write(to: file, options: .atomic) }
        emit(n)
        Task { await bus.sync() }
    }

    // MARK: bus events

    private func emit(_ n: NightRecord) {
        func pain(_ p: Pain) -> PDMValue { .object(["low_back": .int(p.lowBack), "neck": .int(p.neck), "knee": .int(p.knee)]) }
        var data: [String: PDMValue] = [
            "day": .string(n.day), "seconds": .int(n.seconds), "module": .string(n.module), "set": .string(n.module),
            "set_name": .string(Catalog.shared.sets[n.module]?.name ?? n.module), "short": .bool(n.short),
            "done": .int(n.doneCount), "planned": .int(n.steps.count),
            "moves": .array(n.steps.map { s in
                .object(["move": .string(s.move), "side": s.side.map(PDMValue.string) ?? .null, "done": .bool(s.done), "painful": .bool(s.painful),
                         "recalled": s.recalled.map(PDMValue.bool) ?? .null])
            }),
            "pain_before": pain(n.before)]
        if let a = n.after { data["pain_after"] = pain(a) }
        if let p = n.phase { data["phase"] = .string(p) }
        if let k = n.nightNo { data["night_no"] = .int(k) }
        let asked = n.steps.compactMap(\.recalled)
        if !asked.isEmpty { data["recall"] = .object(["hit": .int(asked.filter { $0 }.count), "of": .int(asked.count)]) }
        if !anchor.isEmpty { data["anchor"] = .string(anchor) }
        data["streak"] = .int(streak)
        if !n.redFlags.isEmpty {
            data["red_flags"] = .array(n.redFlags.map(PDMValue.string))
            bus.emit("pain.redflag", subject: "night:\(n.day)", data: data)
        } else {
            bus.emit("stretch.session", subject: "night:\(n.day)", data: data)
        }
    }

    /// Finished days (yesterday and the 13 before) go to the bus once: sleep and activity from Health.
    /// Today is never sent: it is not over.
    func emitHealthDays() async {
        let health = Health.shared
        guard health.authorized else { return }
        var sent = Set(emittedDays.split(separator: ",").map(String.init))
        let cal = Calendar.current
        for back in (1...14).reversed() {
            guard let day = cal.date(byAdding: .day, value: -back, to: .now) else { continue }
            let key = Health.dayFormat.string(from: day)
            if sent.contains(key) { continue }
            let s = await health.summary(for: day)
            sent.insert(key)
            // a day with nothing in Health (phone left at home, no watch) is not sent as zeros
            if s.steps == 0 && s.walkKm == 0 && s.cycleKm == 0 && s.workouts.isEmpty && s.sleepHours == nil { continue }
            var a: [String: PDMValue] = ["steps": .int(s.steps), "walk_km": .double(round1(s.walkKm)), "cycle_km": .double(round1(s.cycleKm)),
                                         "active_kcal": .int(Int(s.activeKcal))]
            if let v = s.restingHR { a["resting_hr"] = .int(Int(v)) }
            if let v = s.hrv { a["hrv_ms"] = .int(Int(v)) }
            if let v = s.weightKg { a["weight_kg"] = .double(round1(v)) }
            if !s.workouts.isEmpty {
                a["workouts"] = .array(s.workouts.map { w in
                    .object(["kind": .string(w.kind), "minutes": .int(w.minutes), "km": w.km.map { .double(round1($0)) } ?? .null, "source": .string(w.source)])
                })
            }
            bus.emit("activity.logged", subject: "day:\(key)", data: a)
            if let h = s.sleepHours {
                var d: [String: PDMValue] = ["hours": .double(round1(h))]
                if let st = s.sleepStart { d["start"] = .string(PDMEvent.timestamp(st)) }
                if let en = s.sleepEnd { d["end"] = .string(PDMEvent.timestamp(en)) }
                bus.emit("sleep.logged", subject: "day:\(key)", data: d)
            }
        }
        emittedDays = sent.sorted().suffix(40).joined(separator: ",")
    }

    private func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }

    // MARK: reminder

    var bedtimeText: String { String(format: "%02d:%02d", bedtimeMinutes / 60, bedtimeMinutes % 60) }

    func requestNotifications() async {
        let c = UNUserNotificationCenter.current()
        _ = try? await c.requestAuthorization(options: [.alert, .sound, .badge])
        let start = UNNotificationAction(identifier: "start", title: "Başla", options: [.foreground])
        let later = UNNotificationAction(identifier: "later", title: "15 dk sonra", options: [])
        c.setNotificationCategories([UNNotificationCategory(identifier: "night", actions: [start, later], intentIdentifiers: [])])
        scheduleReminder()
    }

    func scheduleReminder() {
        let c = UNUserNotificationCenter.current()
        c.removePendingNotificationRequests(withIdentifiers: ["night"])
        let at = (bedtimeMinutes - leadMinutes + 24 * 60) % (24 * 60)
        let content = UNMutableNotificationContent()
        content.title = "Yatmaya \(leadMinutes) dakika var"
        content.body = anchor.isEmpty ? "Beşli: 5 hareket, 5 dakika. Sonra uyku." : "\(anchor): beşli. 5 hareket, 5 dakika, sonra uyku."
        content.sound = .default
        content.categoryIdentifier = "night"
        content.interruptionLevel = .timeSensitive
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: at / 60, minute: at % 60), repeats: true)
        c.add(UNNotificationRequest(identifier: "night", content: content, trigger: trigger))
    }

    func snooze() {
        let content = UNMutableNotificationContent()
        content.title = "Gece rutini"
        content.body = "Hazırsan şimdi: 5 dakika. Yorgunsan mini gece, 2 dakika."
        content.sound = .default
        content.categoryIdentifier = "night"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "night-later", content: content,
                                                                     trigger: UNTimeIntervalNotificationTrigger(timeInterval: 15 * 60, repeats: false)))
    }
}
