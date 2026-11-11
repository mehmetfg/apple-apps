// Akşam tekrarı (2026-11-07): what you heard today, studied before bed in Teoria.
//
// Wise Path is the app that runs while you listen on the way, so it is the one that knows the day's listening first and
// the one that can plan the reminder. After each save of the listening log:
//   1. the last three days go into the shared App Group (PDMBus › PDMListening): per book the seconds, the heard spans
//      and the marks made there. Teoria reads them the same evening, without the Mac or iCloud.
//   2. one local notification is planned for the evening time set in Teoria (22:30 unless changed): "Akşam tekrarı ·
//      bugün 35 dk dinledin · Felsefe 20 dk · Bilimler 15 dk". Tapping it opens Teoria's session (teoria://aksam).
//      Under 3 minutes of listening, with the session already closed in Teoria, or with the reminder turned off,
//      nothing is planned. Heard after the evening time: 20 minutes after the listening stops.
// No goals, no streaks: a day without listening asks for nothing.
import Foundation
import PDMBus
import UIKit
import UserNotifications

extension AppModel {
    /// The listening log was saved: share the last days and plan the reminder.
    func listeningSaved(_ days: [String: ListeningDay]) {
        let cal = Calendar.current
        let keys = (0..<3).compactMap { cal.date(byAdding: .day, value: -$0, to: .now) }.map(ListeningLog.key)
        var heard: [String: [String: PDMListening.Heard]] = [:]
        var ids = Set<String>()
        for k in keys {
            guard let d = days[k] else { continue }
            var m: [String: PDMListening.Heard] = [:]
            for (id, v) in d.docs where v.seconds >= 5 {
                m[id] = .init(seconds: v.seconds.rounded(), words: v.words, ranges: v.ranges)
                ids.insert(id)
            }
            if !m.isEmpty { heard[k] = m }
        }
        let since = cal.startOfDay(for: cal.date(byAdding: .day, value: -2, to: .now) ?? .now)
        var docs: [String: PDMListening.Doc] = [:]
        for id in ids {
            guard let u = UUID(uuidString: id), let r = store.document(u) else { continue }
            let spans = keys.compactMap { heard[$0]?[id]?.ranges }.flatMap { $0 }.filter { $0.count == 2 }
            // the marks of these days, and the older ones that stand in what was heard again
            let marks = r.highlights
                .filter { h in h.createdAt >= since || spans.contains { h.location < $0[1] && h.location + h.length > $0[0] } }
                .sorted { $0.location < $1.location }
                .suffix(60)
                .map { PDMListening.Mark(at: $0.location, length: $0.length, text: $0.text, note: $0.note, created: $0.createdAt) }
            docs[id] = .init(title: r.title, folder: r.folder, length: r.length, teoria: teoriaIDs[u], marks: Array(marks))
        }
        let l = PDMListening(app: "wisepath", days: heard, docs: docs)
        let bus = bus
        DispatchQueue.global(qos: .utility).async { bus.publishListening(l) }
        EveningReminder.plan(l)
    }
}

@MainActor
enum EveningReminder {
    static let id = "wisepath.evening"
    private static var planned: String?          // what is pending now: title|body|minute (nil = nothing)
    private static var asked = false

    static func plan(_ l: PDMListening) {
        let center = UNUserNotificationCenter.current()
        let today = PDMListening.dayKey()
        var perBranch: [String: Double] = [:]
        for (id, h) in l.days[today] ?? [:] { perBranch[l.docs[id]?.branch ?? "Diğer", default: 0] += h.seconds / 60 }
        let total = perBranch.values.reduce(0, +)
        guard PDMEvening.enabled, !PDMEvening.isClosed(today), total >= PDMEvening.minimumMinutes else {
            center.removePendingNotificationRequests(withIdentifiers: [id])
            planned = nil
            return
        }
        let now = Date()
        var fire = Calendar.current.date(bySettingHour: PDMEvening.hour, minute: PDMEvening.minute, second: 0, of: now) ?? now
        if fire < now.addingTimeInterval(60) { fire = now.addingTimeInterval(20 * 60) }
        let order = ["Felsefe", "Bilimler", "Mühendislik", "Diğer"]
        let parts = perBranch.filter { $0.value >= 1 }
            .sorted { (order.firstIndex(of: $0.key) ?? 9, -$0.value) < (order.firstIndex(of: $1.key) ?? 9, -$1.value) }
            .map { "\($0.key) \(Int($0.value.rounded())) dk" }
        let title = "Akşam tekrarı · bugün \(Int(total.rounded())) dk dinledin"
        let body = (parts.isEmpty ? "" : parts.joined(separator: " · ") + " — ") + "önce dinlediğin yerlerin kısa gösterimi, sonra test."
        let key = "\(title)|\(body)|\(Int(fire.timeIntervalSince1970 / 60))"
        guard key != planned else { return }
        planned = key
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        c.threadIdentifier = "evening"
        c.userInfo = ["open": "teoria://aksam"]
        let when = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let request = UNNotificationRequest(identifier: id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false))
        let ask = !asked
        asked = true
        Task {
            if ask, await center.notificationSettings().authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            try? await center.add(request)       // the same identifier replaces the one planned before
        }
    }
}

/// A tap on Wise Path's notification: one that carries a link (the evening session) opens it.
extension AppDelegate: UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let s = response.notification.request.content.userInfo["open"] as? String, let url = URL(string: s) else { return }
        try? await Task.sleep(for: .milliseconds(300))      // a cold start: let the scene come up first
        await MainActor.run { UIApplication.shared.open(url) }
    }
}
