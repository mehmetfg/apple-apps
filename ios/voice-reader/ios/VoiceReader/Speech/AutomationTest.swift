// Simulator test hooks for the automation and the bicycle mark toggle (VoiceReaderApp: -autotest <n>, -resumetest <n>,
// -cardtest, -marktest).
import Foundation

@MainActor
enum AutomationTest {
    static func run(_ model: AppModel, scale: Int) async {
        var a = Automation.pilot
        a.name = "Deneme ÷\(scale)"
        for i in a.steps.indices { a.steps[i].seconds = max(3, a.steps[i].seconds / scale) }
        var log: [String] = ["automation \(a.steps.map(\.title).joined(separator: " → "))"]
        for s in a.steps where s.kind == .read {
            let d = s.folder.flatMap { model.automationDocument(in: $0) }
            log.append("before \(s.folder ?? "?"): \(d?.title ?? "-") at \(d?.position ?? -1)/\(d?.length ?? -1)")
        }
        model.startAutomation(a)
        let started = Date.now
        while model.automationRun != nil, Date.now.timeIntervalSince(started) < Double(a.totalSeconds) + 120 {
            try? await Task.sleep(for: .seconds(1))
            let r = model.automationRun
            let w = model.player.spokenWord.map { model.player.excerptWord($0) } ?? "-"
            log.append(String(format: "%5.1f", Date.now.timeIntervalSince(started))
                + " step \(r?.step ?? -1) \(r.map { "\($0.phase)" } ?? "done") · \(model.player.title) · cursor \(model.player.cursor)"
                + " · playing \(model.player.isPlaying) · listened \(Int(model.player.segmentListened)) · word \(w)")
            try? log.joined(separator: "\n").write(to: URL.libraryDirectory.appending(path: "auto-test.txt"), atomically: true, encoding: .utf8)
        }
        for s in a.steps where s.kind == .read {
            for d in model.store.documents where d.folder == s.folder && d.lastOpenedAt != nil {
                log.append("after \(s.folder ?? "?"): \(d.title) at \(d.position)/\(d.length)")
            }
        }
        log.append("finished in \(Int(Date.now.timeIntervalSince(started))) s")
        try? log.joined(separator: "\n").write(to: URL.libraryDirectory.appending(path: "auto-test.txt"), atomically: true, encoding: .utf8)
    }

    /// -resumetest <n>: the pilot n times shorter; stopped a few seconds into its third step, then resumed (Kaldığı
    /// yerden) and played to its end. Logs to Library/resume-test.txt.
    static func resume(_ model: AppModel, scale: Int) async {
        var a = Automation.pilot
        a.name = "Sürdürme ÷\(scale)"
        for i in a.steps.indices { a.steps[i].seconds = max(3, a.steps[i].seconds / scale) }
        var log: [String] = ["automation \(a.steps.map(\.title).joined(separator: " → "))"]
        func write() { try? log.joined(separator: "\n").write(to: URL.libraryDirectory.appending(path: "resume-test.txt"), atomically: true, encoding: .utf8) }
        func line(_ t: Double) -> String {
            let r = model.automationRun
            return String(format: "%5.1f", t) + " step \(r?.step ?? -1) \(r.map { "\($0.phase)" } ?? "done") · \(model.player.title)"
                + " · cursor \(model.player.cursor) · before \(Int(r?.listenedBefore ?? -1)) · listened \(Int(model.player.segmentListened))"
        }
        model.startAutomation(a)
        var started = Date.now
        while Date.now.timeIntervalSince(started) < 300 {
            try? await Task.sleep(for: .seconds(1))
            log.append(line(Date.now.timeIntervalSince(started))); write()
            if let r = model.automationRun, r.step == 2, r.phase == .reading, model.player.segmentListened >= 8 { break }
        }
        let cursorAtStop = model.player.cursor
        model.stopAutomation()
        let p = model.automations.progress[a.id]
        let rp = model.automations.resumePoint(for: a)
        log.append("STOPPED at cursor \(cursorAtStop) · saved step \(p?.step ?? -1) listened \(String(format: "%.1f", p?.listened ?? -1))"
                   + " · resume point step \(rp?.step ?? -1) listened \(String(format: "%.1f", rp?.listened ?? -1))")
        write()
        try? await Task.sleep(for: .seconds(3))
        model.startAutomation(a, resume: true)
        log.append("RESUMED · run step \(model.automationRun?.step ?? -1)")
        started = Date.now
        while model.automationRun != nil, Date.now.timeIntervalSince(started) < 300 {
            try? await Task.sleep(for: .seconds(1))
            log.append(line(Date.now.timeIntervalSince(started))); write()
        }
        log.append("finished in \(Int(Date.now.timeIntervalSince(started))) s · progress after end \(model.automations.progress[a.id] == nil ? "cleared" : "KEPT")"
                   + " · resume point \(model.automations.resumePoint(for: a).map { "\($0.step)" } ?? "none")")
        write()
    }

    /// -cardtest: the library card's three states for screenshots: the featured automation plays for 14 s (running),
    /// then stops (Kaldığı yerden · Baştan).
    static func card(_ model: AppModel) async {
        guard let a = model.automations.featured else { return }
        model.startAutomation(a)
        try? await Task.sleep(for: .seconds(14))
        model.stopAutomation()
    }

    static func mark(_ model: AppModel) async {
        guard let d = model.store.documents.first(where: { $0.folder == "Felsefe" }) else { return }
        await model.open(d.id)
        model.player.play()
        try? await Task.sleep(for: .seconds(4))
        var log: [String] = []
        func count() -> Int { model.currentDocument?.highlights.count ?? -1 }
        log.append("start \(count()) marked \(model.spokenSentenceMarked)")
        model.markSpokenSentence()
        log.append("after 1st press \(count()) marked \(model.spokenSentenceMarked)")
        model.markSpokenSentence()
        log.append("after 2nd press \(count()) marked \(model.spokenSentenceMarked)")
        model.player.pause()
        try? log.joined(separator: "\n").write(to: URL.libraryDirectory.appending(path: "mark-test.txt"), atomically: true, encoding: .utf8)
    }
}
