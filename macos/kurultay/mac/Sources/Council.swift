import Foundation
import SwiftUI

/// The assembly: seats (one tab each), sessions on disk, rounds of questions.
@MainActor
final class Council: ObservableObject {
    @Published var seats: [SeatConfig] = []
    @Published var providers: [String: ProviderConfig] = [:]
    @Published var sessions: [Session] = []
    @Published var selectedSession: String?
    @Published var adapterError: String?
    @Published var engine = ChromeHost.installed ? "chrome" : "webkit"
    /// Kıvılcım records chosen for the next question (from the Kıvılcım pane or kurultay:// links).
    @Published var sparkBasket: [String] = []
    let library = SparkLibrary()
    private(set) var web: [String: WebSeat] = [:]
    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var inboxTimer: Timer?
    private var accountTimer: Timer?

    init() {
        reloadAdapters()
        sessions = SessionFiles.loadAll()
        selectedSession = sessions.first?.id
        library.load()
        SparkLinks.write(sessions)
        inboxTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkInbox() }
        }
        // sign-ins: an encrypted copy every 5 minutes, so a Chrome crash cannot take them
        accountTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task { @MainActor in await AccountKeeper.backup() }
        }
        Task { @MainActor in try? await Task.sleep(for: .seconds(20)); await AccountKeeper.backup() }
    }

    var activeSeats: [SeatConfig] { seats.filter { $0.enabled ?? true } }

    func session(_ id: String?) -> Session? { sessions.first { $0.id == id } }

    // MARK: Adapters

    func reloadAdapters() {
        let url = FileManager.default.fileExists(atPath: Paths.adapters.path) ? Paths.adapters
            : Bundle.main.url(forResource: "adapters", withExtension: "json")
        guard let url, let d = try? Data(contentsOf: url) else { adapterError = "adapters.json bulunamadı"; return }
        do {
            let f = try JSONDecoder().decode(AdapterFile.self, from: d)
            seats = f.seats
            AccountKeeper.setSeats(f.seats.map(\.url))
            providers = f.providers ?? [:]
            adapterError = nil
            let wanted = (f.engine == "webkit" || !ChromeHost.installed) ? "webkit" : "chrome"
            if wanted != engine { engine = wanted; web.removeAll() }
            for (i, s) in f.seats.enumerated() {
                if let w = web[s.id] { w.updateConfig(s) } else { web[s.id] = WebSeat(config: s, engine: engine, index: i) }
            }
        } catch {
            adapterError = "adapters.json okunamadı: \(error)"
        }
    }

    func setEnabled(_ id: String, _ on: Bool) {
        guard let i = seats.firstIndex(where: { $0.id == id }) else { return }
        seats[i].enabled = on
        guard let d = try? Data(contentsOf: Paths.adapters),
              var obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              var list = obj["seats"] as? [[String: Any]],
              let j = list.firstIndex(where: { $0["id"] as? String == id }) else { return }
        list[j]["enabled"] = on
        obj["seats"] = list
        if let out = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            try? out.write(to: Paths.adapters, options: .atomic)
        }
    }

    // MARK: Sessions

    func newSession(title: String, seats wanted: [String]? = nil, origin: String = "mac") -> Session {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd-HHmm"
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = Session(id: "\(df.string(from: Date()))-\(slug(t.isEmpty ? "kurultay" : t))", title: t.isEmpty ? "Kurultay" : t,
                        created: Date(), seats: wanted ?? activeSeats.map(\.id), rounds: [], origin: origin)
        sessions.insert(s, at: 0)
        selectedSession = s.id
        SessionFiles.save(s)
        return s
    }

    private func update(_ id: String, _ change: (inout Session) -> Void) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        change(&sessions[i])
        SessionFiles.save(sessions[i])
    }

    /// Asks one round. Returns the round number at once; answers arrive in the background.
    @discardableResult
    func ask(session id: String, text: String, seats wanted: [String]? = nil, timeout: TimeInterval = 600, question: String? = nil) -> Int? {
        guard let s = session(id) else { return nil }
        let chosen = (wanted?.isEmpty == false ? wanted! : s.seats).filter { w in seats.contains { $0.id == w } }
        let roundId = (s.rounds.last?.id ?? 0) + 1
        var answers: [String: Answer] = [:]
        for seat in chosen { answers[seat] = Answer(seat: seat, state: .waiting) }
        update(id) { sess in
            sess.rounds.append(Round(id: roundId, text: text, asked: Date(), answers: answers, question: question))
            for seat in chosen where !sess.seats.contains(seat) { sess.seats.append(seat) }
        }
        if session(id)?.follow == true { FollowLauncher.mark(id, state: "bekliyor", round: roundId) }
        for seat in chosen {
            // a seat that did not answer an earlier round starts its own conversation
            let previous = s.rounds.reversed().compactMap { $0.answers[seat] }.first { $0.state == .done && $0.via == "web" }
            Task { await runSeat(session: id, round: roundId, seat: seat, text: text, newChat: previous == nil, resume: previous?.chatUrl, timeout: timeout) }
        }
        return roundId
    }

    /// Asks again, in the same round, the seats that did not finish (default: every seat not ✓).
    @discardableResult
    func retry(session id: String, round: Int? = nil, seats wanted: [String]? = nil, timeout: TimeInterval = 600) -> [String] {
        guard let s = session(id), let r = (round.flatMap { n in s.rounds.first { $0.id == n } } ?? s.rounds.last) else { return [] }
        let chosen = r.answers.filter { k, a in (wanted?.contains(k) ?? true) && (wanted != nil || a.state != .done) && !(a.state == .waiting || a.state == .sending || a.state == .thinking || a.state == .writing) }.map(\.key)
        if !chosen.isEmpty, s.follow == true { FollowLauncher.mark(id, state: "bekliyor", round: r.id) }
        for seat in chosen {
            setAnswer(id, r.id, seat) { $0 = Answer(seat: seat, state: .waiting) }
            let previous = s.rounds.filter { $0.id < r.id }.reversed().compactMap { $0.answers[seat] }.first { $0.state == .done && $0.via == "web" }
            Task { await runSeat(session: id, round: r.id, seat: seat, text: r.text, newChat: previous == nil, resume: previous?.chatUrl, timeout: timeout) }
        }
        return chosen.sorted()
    }

    private func setAnswer(_ id: String, _ round: Int, _ seat: String, _ change: (inout Answer) -> Void) {
        update(id) { sess in
            guard let r = sess.rounds.firstIndex(where: { $0.id == round }), var a = sess.rounds[r].answers[seat] else { return }
            change(&a)
            sess.rounds[r].answers[seat] = a
        }
        if let r = session(id)?.rounds.first(where: { $0.id == round }), r.done { roundFinished(id, round) }
    }

    private func runSeat(session id: String, round: Int, seat: String, text: String, newChat: Bool, resume: String?, timeout: TimeInterval) async {
        guard let cfg = seats.first(where: { $0.id == seat }) else { return }
        // a seat with a character limit gets a shortened copy instead of failing (Gemini: 32,000)
        let full = text
        let short = SparkPrompt.fit(full, limit: cfg.maxChars)
        let text = short ?? full
        let cutNote = short.map { "soru bu model için kısaltıldı: \(full.count.formatted()) → \($0.count.formatted()) karakter" }
        setAnswer(id, round, seat) { $0.state = .sending; $0.started = Date(); $0.error = cutNote }
        var failure: String?
        if let w = web[seat] {
            // one question at a time per tab
            while w.busyAsking { try? await Task.sleep(for: .seconds(1)) }
            let outcome = await w.ask(text, newChat: newChat, resume: resume, timeout: timeout) { [weak self] state, partial in
                self?.setAnswer(id, round, seat) { a in
                    a.state = state
                    if !partial.isEmpty { a.text = partial }
                }
            }
            switch outcome {
            case let .done(t, th, url):
                setAnswer(id, round, seat) { $0.state = .done; $0.text = t; $0.thinking = th; $0.finished = Date(); $0.via = "web"; $0.chatUrl = url }
                return
            case let .timeout(t, th, url):
                if !t.isEmpty || cfg.api == nil {
                    setAnswer(id, round, seat) { $0.state = .timeout; $0.text = t; $0.thinking = th; $0.finished = Date(); $0.chatUrl = url }
                    return
                }
                failure = "süre doldu"
            case let .failed(reason):
                failure = reason
            }
        }
        // fallback: the free API of the same model family
        if let api = cfg.api, let prov = providers[api.provider], let key = Keychain.get(api.provider) {
            setAnswer(id, round, seat) { $0.state = .thinking; $0.via = "api"; $0.error = failure.map { "tarayıcı: \($0)" } }
            var messages: [[String: String]] = []
            for r in session(id)?.rounds ?? [] where r.id < round {
                if let a = r.answers[seat], a.state == .done { messages += [["role": "user", "content": r.text], ["role": "assistant", "content": a.text]] }
            }
            messages.append(["role": "user", "content": text])
            do {
                let res = try await ApiClient.ask(provider: prov, key: key, model: api.model, messages: messages)
                setAnswer(id, round, seat) { $0.state = .done; $0.text = res.text; $0.thinking = res.reasoning == nil ? "api" : "on"; $0.finished = Date() }
            } catch {
                setAnswer(id, round, seat) { $0.state = .failed; $0.error = [failure.map { "tarayıcı: \($0)" }, "API: \(error.localizedDescription)"].compactMap { $0 }.joined(separator: " · "); $0.finished = Date() }
            }
            return
        }
        setAnswer(id, round, seat) { $0.state = .failed; $0.error = failure ?? "ulaşılamadı"; $0.finished = Date() }
    }

    // MARK: Waiting (HTTP long poll)

    private func key(_ id: String, _ round: Int) -> String { "\(id)#\(round)" }

    func wait(session id: String, round: Int, timeout: TimeInterval) async {
        if session(id)?.rounds.first(where: { $0.id == round })?.done ?? true { return }
        await withTaskGroup(of: Void.self) { g in
            g.addTask { @MainActor in
                await withCheckedContinuation { c in self.waiters[self.key(id, round), default: []].append(c) }
            }
            g.addTask { try? await Task.sleep(for: .seconds(timeout)) }
            await g.next()
            g.cancelAll()
        }
    }

    private func roundFinished(_ id: String, _ round: Int) {
        for c in waiters.removeValue(forKey: key(id, round)) ?? [] { c.resume() }
        writePending()
        if session(id)?.follow == true { FollowLauncher.launch(id, round: round) }
    }

    // MARK: Kıvılcım

    func addToBasket(_ ids: [String]) {
        for i in ids where !sparkBasket.contains(i) { sparkBasket.append(i) }
    }

    /// New session whose first question carries the chosen Kıvılcım transcripts; Claude follows it when `follow`.
    @discardableResult
    func askWithSparks(title: String, question: String, sparkIds: [String], seats wanted: [String]?, follow: Bool,
                       closing: Bool = true, origin: String = "kivilcim") -> String? {
        let chosen = sparkIds.compactMap { library.spark($0) }.sorted { $0.date < $1.date }
        guard !chosen.isEmpty, !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let t = title.trimmingCharacters(in: .whitespaces).isEmpty ? (chosen.count == 1 ? chosen[0].title : "\(chosen[0].title) +\(chosen.count - 1)") : title
        let s = newSession(title: t, seats: wanted, origin: origin)
        update(s.id) { $0.sources = chosen.map(\.ref); $0.follow = follow }
        ask(session: s.id, text: SparkPrompt.compose(question: question, sparks: chosen, closing: closing), seats: wanted, question: question)
        SparkLinks.write(sessions)
        return s.id
    }

    // MARK: Claude's queue + iPhone inbox

    /// Sessions whose last round is finished and newer than the report: Claude evaluates these.
    func writePending() {
        var lines: [String] = []
        for s in sessions {
            guard let last = s.rounds.last, last.done else { continue }
            let rep = SessionFiles.report(s.id)
            let repDate = (rep.flatMap { try? $0.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }) ?? .distantPast
            let dec = SessionFiles.decision(s.id)
            if rep == nil || repDate < last.asked {
                lines.append("- [ ] `\(s.id)` · \(s.title) · \(s.rounds.count) soru · \(last.doneCount)/\(last.answers.count) cevap → rapor yazılacak")
            } else if dec?.state == "duzelt" {
                lines.append("- [ ] `\(s.id)` · \(s.title) · düzeltme istendi: \(dec?.note ?? "")")
            } else if dec?.state == "onaylandi" {
                lines.append("- [ ] `\(s.id)` · \(s.title) · ONAYLANDI → tatbik et")
            }
        }
        let md = "# Kurultay — Bekleyenler\n\nUygulama yazar. Tetik: \"Kurultay'ı değerlendir\" (Claude, `/kurultay`).\n\n"
            + (lines.isEmpty ? "_Bekleyen yok._\n" : lines.joined(separator: "\n") + "\n")
        try? FileManager.default.createDirectory(at: Paths.tool, withIntermediateDirectories: true)
        try? md.write(to: Paths.pending, atomically: true, encoding: .utf8)
    }

    func checkInbox() {
        let fm = FileManager.default
        try? fm.createDirectory(at: Paths.inbox, withIntermediateDirectories: true)
        try? fm.createDirectory(at: Paths.processed, withIntermediateDirectories: true)
        let files = (try? fm.contentsOfDirectory(at: Paths.inbox, includingPropertiesForKeys: nil))?.filter { $0.pathExtension == "json" } ?? []
        for f in files {
            guard let d = try? Data(contentsOf: f), let req = try? JSONDecoder.kurultay.decode(InboxRequest.self, from: d) else { continue }
            try? fm.moveItem(at: f, to: Paths.processed.appendingPathComponent(f.lastPathComponent))
            if let ks = req.kivilcim, !ks.isEmpty, req.session == nil {
                askWithSparks(title: req.title ?? "", question: req.text, sparkIds: ks, seats: req.seats, follow: req.follow ?? true, origin: "istek")
                continue
            }
            let id = req.session.flatMap { session($0)?.id } ?? newSession(title: req.title ?? String(req.text.prefix(60)), seats: req.seats, origin: "iphone").id
            ask(session: id, text: req.text, seats: req.seats)
        }
        // pick up reports and decisions written by Claude or the iPhone
        let fresh = SessionFiles.loadAll()
        if fresh.map(\.id) != sessions.map(\.id) {
            for s in fresh where session(s.id) == nil { sessions.append(s) }
            sessions.sort { $0.created > $1.created }
        }
        SparkLinks.write(sessions)   // report, decision and summary appear under the Kıvılcım record
        objectWillChange.send()
    }

    func decide(_ id: String, state: String, note: String?) {
        SessionFiles.saveDecision(id, Decision(state: state, note: note?.isEmpty == true ? nil : note, date: Date(), by: "mac"))
        writePending()
        SparkLinks.write(sessions)
        objectWillChange.send()
    }
}
