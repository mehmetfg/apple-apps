// Local notifications: the morning decision, the 15:00 darkness notice with the 16–19 rain window,
// tomorrow's sunrise in the evening, a short "how was it?" after each ride and sudden-change alerts.
// Sun times are exact, so they are scheduled a week ahead; weather lines only where the forecast reaches.
import Foundation
import UserNotifications

enum Notifier {
    static let prefix = "ufuk."

    static func registerCategories() {
        let feel = Feel.allCases.map { UNNotificationAction(identifier: "feel.\($0.rawValue)", title: $0.label, options: []) }
        let fb = UNNotificationCategory(identifier: "FEEDBACK", actions: feel, intentIdentifiers: [])
        let ride = UNNotificationAction(identifier: "ride.start", title: "Yola çıkıyorum", options: [.foreground])
        let brief = UNNotificationCategory(identifier: "BRIEF", actions: [ride], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([fb, brief])
    }

    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    private static func add(_ id: String, at date: Date, title: String, body: String, category: String? = nil,
                            info: [String: String] = [:], sensitive: Bool = false) async {
        guard date > .now else { return }
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default
        c.userInfo = info
        if let category { c.categoryIdentifier = category }
        c.interruptionLevel = sensitive ? .timeSensitive : .active
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let req = UNNotificationRequest(identifier: prefix + id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        try? await UNUserNotificationCenter.current().add(req)
    }

    @MainActor
    static func schedule(_ s: Store) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) && !$0.hasPrefix(prefix + "alert") }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        let cal = Calendar.current
        let set = s.settings

        // Morning decision for the next morning leg.
        if let m = s.morning {
            let when = Decision.at(m.day, s.notifyMorning)
            let sun = s.sun(on: m.day)
            var body = m.detail
            if let f = m.feel { body += " Bisiklette \(Fmt.deg(f))." }
            body += " Aydınlanma \(Fmt.t(sun.dawn)), güneş \(Fmt.t(sun.sunrise))."
            if let h = m.hazards.first(where: { $0.level >= .caution }) { body = "⚠︎ \(h.text). " + body }
            await add("brief.\(Store.dayKey.string(from: m.day))", at: when, title: "Sabah · \(m.verdict)", body: body, category: "BRIEF",
                      info: ["leg": "morning"], sensitive: m.hazards.contains { $0.level == .danger })
        }

        for i in 0..<7 {
            let day = cal.startOfDay(for: .now).addingTimeInterval(Double(i) * 86400 + 3600).startOfDay
            let sun = s.sun(on: day)
            let key = Store.dayKey.string(from: day)

            // 15:00 — when it gets dark, and the evening window if the forecast reaches that day.
            var body = "Gün batımı \(Fmt.t(sun.sunset)), tam karanlık \(Fmt.t(sun.dusk))."
            if let f = s.forecast, f.slots.last.map({ $0.time > Decision.at(day, set.eveningEnd) }) == true {
                let e = Decision.leg(.evening, day: day, f: f, s: set, sun: sun, th: s.thresholds)
                body += " 16–19: \(e.verdict)."
                if let h = e.hazards.first(where: { $0.level >= .caution }) { body += " ⚠︎ \(h.text)." }
            }
            if let dusk = sun.dusk, Decision.at(day, set.eveningDepart + set.rideMinutes) > dusk {
                body += " Eve karanlıkta varacaksın."
            }
            await add("dusk.\(key)", at: Decision.at(day, s.notifyDusk), title: "Hava \(Fmt.at(sun.dusk)) kararıyor", body: body,
                      category: "BRIEF", info: ["leg": "evening"])

            // Evening — tomorrow's sunrise and how the morning ride sits against it.
            let next = day.addingTimeInterval(86400 + 3600).startOfDay
            let ns = s.sun(on: next)
            let depart = Decision.at(next, set.morningDepart)
            let delta = Int((ns.daylight - sun.daylight) / 60)
            var sb = "Şafak \(Fmt.t(ns.dawn)). Çıkışın \(Fmt.t(depart)): "
            sb += (ns.dawn.map { depart < $0 } ?? false) ? "karanlıkta, ışıkları tak." : ((ns.sunrise.map { depart < $0 } ?? false) ? "alacakaranlıkta." : "aydınlıkta.")
            sb += " Gün \(Fmt.span(ns.daylight)) (\(delta >= 0 ? "+" : "−")\(abs(delta)) dk)."
            // The evening before: if tomorrow morning brings rain, say so first and give the dry departure, if there is one.
            var title = "Yarın güneş \(Fmt.at(ns.sunrise)) doğuyor"
            if let f = s.forecast, f.slots.last.map({ $0.time > Decision.at(next, set.morningEnd) }) == true,
               s.weekendRides || !(cal.component(.weekday, from: next) == 1 || cal.component(.weekday, from: next) == 7) {
                let m = Decision.leg(.morning, day: next, f: f, s: set, sun: ns, th: s.thresholds)
                if m.windowMax >= 0.4 {
                    title = "Yarın sabah yağmur bekleniyor · \(Fmt.pct(m.windowMax))"
                    let start = m.rainStart.map { " \(Fmt.t($0)) civarı başlıyor." } ?? ""
                    let dry = m.bestMax < 0.2 ? " Yağmursuz çıkış: \(Fmt.at(m.best)) (\(Fmt.pct(m.bestMax)))." : " 07–09 arasında kuru çıkış yok; yağmurluğu hazırla."
                    sb = "07–09 penceresi.\(start)\(dry) " + sb
                } else {
                    sb = "Sabah 07–09 kuru görünüyor (en çok \(Fmt.pct(m.windowMax))), \(Fmt.at(m.best)) çık. " + sb
                }
            }
            await add("sunrise.\(key)", at: Decision.at(day, s.notifySunrise), title: title, body: sb)

            // After each ride: one tap to teach the base layer threshold.
            let weekday = cal.component(.weekday, from: day)
            if s.askFeedback, s.weekendRides || !(weekday == 1 || weekday == 7), i < 2 {
                for (kind, dep) in [(LegKind.morning, set.morningDepart), (.evening, set.eveningDepart)] {
                    await add("ask.\(kind.rawValue).\(key)", at: Decision.at(day, dep + set.rideMinutes + 15),
                              title: kind == .morning ? "Sabah yolu nasıldı?" : "Dönüş nasıldı?",
                              body: "Bir dokunuş yeter: hissettiğin sıcaklık kaydedilir.", category: "FEEDBACK",
                              info: ["leg": kind.rawValue])
                }
            }
        }
    }

    /// Called after every refresh (also in the background): tells the person when the coming ride changed.
    @MainActor
    static func checkChange(old: (Leg?, Leg?), new: (Leg?, Leg?), store: Store) async {
        for (o, n) in [(old.0, new.0), (old.1, new.1)] {
            guard let n else { continue }
            let lead = n.planned.timeIntervalSince(.now)
            guard lead > 0, lead < 3 * 3600 else { continue }
            let key = "alerted.\(n.kind.rawValue).\(Store.dayKey.string(from: n.day))"
            let was = o?.plannedMax ?? UserDefaults.standard.double(forKey: key + ".p")
            let now = n.plannedMax
            UserDefaults.standard.set(now, forKey: key + ".p")
            let name = n.kind == .morning ? "Sabah" : "Dönüş"
            if was < 0.25, now >= 0.45 {
                let start = n.rainStart.map { " \(Fmt.t($0)) civarı" } ?? ""
                let tip = n.best != n.planned ? " \(Fmt.at(n.best)) çıkarsan \(Fmt.pct(n.bestMax))." : " Yağmurluğu al."
                await add("alert.\(key).\(Int(Date.now.timeIntervalSince1970))", at: .now.addingTimeInterval(2),
                          title: "\(name): yağış girdi\(start)", body: "İhtimal \(Fmt.pct(was)) → \(Fmt.pct(now)).\(tip)", sensitive: true)
            } else if was >= 0.45, now < 0.2 {
                await add("alert.\(key).\(Int(Date.now.timeIntervalSince1970))", at: .now.addingTimeInterval(2),
                          title: "\(name): yağış çekildi", body: "Artık \(Fmt.pct(now)). \(Fmt.at(n.planned)) çıkabilirsin.")
            }
            if let d = n.hazards.first(where: { $0.level == .danger }), !(o?.hazards.contains(d) ?? false) {
                await add("alert.hz.\(key).\(Int(Date.now.timeIntervalSince1970))", at: .now.addingTimeInterval(3),
                          title: "\(name): dikkat", body: d.text, sensitive: true)
            }
        }
    }

    #if DEBUG
    /// Writes the pending requests to Documents/notifications.txt for checking the wording in the simulator.
    static func dump() async {
        let reqs = await UNUserNotificationCenter.current().pendingNotificationRequests().sorted { $0.identifier < $1.identifier }
        let lines = reqs.map { r -> String in
            let when = (r.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate().map { Fmt.day.string(from: $0) + " " + Fmt.t($0) } ?? "?"
            return "[\(when)] \(r.content.title)\n    \(r.content.body)"
        }
        try? lines.joined(separator: "\n").write(to: URL.documentsDirectory.appending(path: "notifications.txt"), atomically: true, encoding: .utf8)
    }
    #endif
}
