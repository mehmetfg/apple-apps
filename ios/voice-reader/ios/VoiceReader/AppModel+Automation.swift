// Runs a listening automation: each reading step opens its folder's current book where it was left and reads for the
// step's minutes of listening, then stops at the end of a sentence; a pause step is a quiet break with a spoken
// announcement of what comes next. Between steps the player keeps its engine running on silence and its session
// active, so the whole row plays through with the phone locked and nothing pressed.
import AVFoundation
import UIKit

extension AppModel {
    // MARK: choosing the book

    /// A folder's current book: the one listened to last that is not finished; if none was opened yet, the first
    /// unfinished one by title.
    func automationDocument(in folder: String, excluding: Set<UUID> = []) -> DocumentRecord? {
        let docs = store.documents.filter { $0.folder == folder && !$0.isFinished && !excluding.contains($0.id) }
        if let last = docs.filter({ $0.lastOpenedAt != nil }).max(by: { $0.lastOpenedAt! < $1.lastOpenedAt! }) { return last }
        return docs.min { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// The book the folder is on: the one opened last in it, finished or not; if none was opened yet, its first
    /// unfinished book. A finished one is not skipped in silence: the step asks what to do (`askAutomationChoice`).
    func automationStepBook(in folder: String) -> DocumentRecord? {
        let docs = store.documents.filter { $0.folder == folder }
        if let last = docs.filter({ $0.lastOpenedAt != nil }).max(by: { $0.lastOpenedAt! < $1.lastOpenedAt! }) { return last }
        return automationDocument(in: folder)
    }

    // MARK: a finished book in the way

    /// Says what happened and waits for the reader: on screen (the alert) or with the headphone keys.
    func askAutomationChoice(_ c: AutomationChoice) async -> AutomationChoice.Answer {
        automationChoice = c
        automationRun?.phase = .announcing
        automationRun?.documentTitle = c.finishedTitle
        var text = c.finishedTitle.map { "Sıradaki kitap bitmiş: \($0)." } ?? "\(c.folder) klasöründe bitmemiş kitap yok."
        if let n = c.nextTitle { text += " İleri tuşu: \(n)." }
        if let t = c.currentTitle { text += " Geri tuşu: \(t) kitabından sür." }
        text += " Oynat tuşu: durdur."
        Task { await announcer.say(text, voice: announcerVoice, mix: settings.musicMix != .off) }
        let answer = await withCheckedContinuation { automationChoiceWaiter = $0 }
        announcer.stop()
        automationChoice = nil
        return answer
    }

    /// The reader answered (`key`: −1 ⏮ current · 0 ⏯ stop · 1 ⏭ next, or the alert's buttons). False when no choice
    /// is waiting, so the key does its usual job.
    @discardableResult
    func answerAutomationChoice(key: Int) -> Bool {
        guard let c = automationChoice, let w = automationChoiceWaiter else { return false }
        let answer: AutomationChoice.Answer
        switch key {
        case 1: guard c.nextID != nil else { return true }; answer = .next
        case -1: guard c.currentID != nil else { return true }; answer = .current
        default: answer = .stop
        }
        automationChoiceWaiter = nil
        w.resume(returning: answer)
        return true
    }

    // MARK: running

    /// `resume`: go on from the step where the automation was left (Kaldığı yerden), with the time already heard in it;
    /// otherwise from its first step with full times. Either way each book reads on from its own place.
    func startAutomation(_ a: Automation, resume: Bool = false) {
        stopAutomation()
        guard !a.steps.isEmpty else { return }
        if recorder.isRecording { cancelVoiceNote() }
        let from = resume ? automations.resumePoint(for: a) : nil
        automations.select(a.id)
        automationRun = AutomationRun(automation: a, step: from?.step ?? 0)
        player.keepSessionAtEnd = true
        automationTask = Task { await self.runAutomation(a, from: from) }
    }

    /// Writes where the running automation is, so it can go on from there later (after Durdur, after another book
    /// was opened, after the app was closed).
    func saveAutomationProgress() {
        guard let run = automationRun, !run.ending else { return }
        let heard = run.phase == .reading ? player.segmentListened : 0
        automations.noteProgress(run.automation, step: run.step, listened: run.listenedBefore + heard)
    }

    /// While a step reads, the place is written every ten seconds or so (the player reports every two).
    func automationTick() {
        guard automationRun?.phase == .reading, Date.now.timeIntervalSince(automationSavedAt) >= 10 else { return }
        automationSavedAt = .now
        saveAutomationProgress()
    }

    /// Ends the automation where it is; the book stays at its place, paused, and the automation remembers its step.
    func stopAutomation() {
        guard automationRun != nil else { return }
        saveAutomationProgress()
        automationTask?.cancel(); automationTask = nil
        automationWaiter?.resume(returning: .cancelled); automationWaiter = nil
        automationChoiceWaiter?.resume(returning: .stop); automationChoiceWaiter = nil
        automationChoice = nil
        announcer.stop()
        automationRun = nil
        player.endSegments()
        if player.isPlaying { player.pause() } else if player.isSpeaking { player.stop() }
    }

    /// The player's step time is up (`.timeUp`) or the book ended (`.finished`).
    func segmentEnded(_ outcome: SegmentOutcome) {
        automationWaiter?.resume(returning: outcome)
        automationWaiter = nil
    }

    private func runAutomation(_ a: Automation, from: ResumePoint?) async {
        let start = from?.step ?? 0
        var intro: String? = from == nil ? "Otomasyon başlıyor." : "Otomasyon kaldığı yerden sürüyor."
        for i in start..<a.steps.count {
            guard !Task.isCancelled, automationRun != nil else { return }
            let step = a.steps[i]
            let heard = i == start ? from?.listened ?? 0 : 0
            automationRun?.step = i
            automationRun?.phase = .announcing
            automationRun?.stepSeconds = Double(step.seconds)
            automationRun?.listenedBefore = heard
            automations.noteProgress(a, step: i, listened: heard)
            switch step.kind {
            case .read:
                await runReading(step, listened: heard, intro: intro)
                intro = nil
            case .pause:
                await runPause(step, next: a.steps[(i + 1)...].first { $0.kind == .read })
            }
        }
        guard !Task.isCancelled, automationRun != nil else { return }
        automationRun?.ending = true
        automationRun?.phase = .announcing
        automations.clearProgress(a.id)
        await announcer.say("Otomasyon bitti.", voice: announcerVoice, mix: settings.musicMix != .off)
        guard automationRun != nil else { return }
        automationRun = nil
        player.endSegments()
        player.stop()
    }

    /// Reads the folder's current book for the rest of the step's time (`listened`: seconds heard in it before a
    /// stop). When that book is finished (before the step or during it) the reader chooses: the folder's next
    /// unfinished book, the book already loaded, or stop. A finished book is never read again by the automation.
    private func runReading(_ step: AutomationStep, listened: Double, intro: String?) async {
        guard let folder = step.folder else { return }
        var remaining = Double(step.seconds) - listened
        var done: Set<UUID> = []
        var said = intro.map { [$0] } ?? []
        var stepBook = automationStepBook(in: folder)
        while remaining > 5, !Task.isCancelled, automationRun != nil {
            let doc: DocumentRecord
            if let b = stepBook.flatMap({ store.document($0.id) }), !b.isFinished {
                doc = b
            } else {
                let next = automationDocument(in: folder, excluding: done)
                let current = player.documentID.flatMap { store.document($0) }
                    .flatMap { !$0.isFinished && $0.id != next?.id ? $0 : nil }
                if !said.isEmpty {
                    await announcer.say(said.joined(separator: " "), voice: announcerVoice, mix: settings.musicMix != .off)
                    said = []
                }
                guard next != nil || current != nil else {
                    automationRun?.phase = .announcing
                    await announcer.say("\(folder) klasöründe okunacak kitap yok, geçiyorum.", voice: announcerVoice,
                                        mix: settings.musicMix != .off)
                    return
                }
                let answer = await askAutomationChoice(AutomationChoice(
                    finishedTitle: stepBook?.title, folder: folder, nextID: next?.id, nextTitle: next?.title,
                    currentID: current?.id, currentTitle: current?.title))
                guard !Task.isCancelled, automationRun != nil else { return }
                switch answer {
                case .next: doc = next!
                case .current: doc = current!
                case .stop: stopAutomation(); return
                }
                stepBook = doc
            }
            automationRun?.phase = .announcing
            automationRun?.documentTitle = doc.title
            await open(doc.id, automated: true)
            guard !Task.isCancelled, automationRun != nil else { return }
            said.append(done.isEmpty ? "\(folder). \(doc.title)." : "Sıradaki kitap: \(doc.title).")
            await announcer.say(said.joined(separator: " "), voice: announcerVoice, mix: settings.musicMix != .off)
            said = []
            guard !Task.isCancelled, automationRun != nil else { return }
            automationRun?.phase = .reading
            player.startSegment(seconds: remaining)
            player.playAfterHold()
            let outcome = await withCheckedContinuation { automationWaiter = $0 }
            switch outcome {
            case .timeUp, .cancelled: return
            case .finished:
                remaining -= player.segmentListened
                automationRun?.listenedBefore = Double(step.seconds) - remaining
                automationRun?.phase = .announcing
                saveAutomationProgress()
                done.insert(doc.id)
                stepBook = store.document(doc.id)
            }
        }
    }

    private func runPause(_ step: AutomationStep, next: AutomationStep?) async {
        automationRun?.phase = .thinking
        automationRun?.documentTitle = nil
        let ends = Date.now.addingTimeInterval(Double(step.seconds))
        automationRun?.phaseEnds = ends
        var text = "Düşünme arası, \(Self.spokenLength(step.seconds))."
        if let f = next?.folder { text += " Sonra \(f)." }
        await announcer.say(text, voice: announcerVoice, mix: settings.musicMix != .off)
        let left = ends.timeIntervalSinceNow
        if left > 0 { try? await Task.sleep(for: .seconds(left)) }
        automationRun?.phaseEnds = nil
    }

    private static func spokenLength(_ s: Int) -> String {
        let words = ["", "bir", "iki", "üç", "dört", "beş", "altı", "yedi", "sekiz", "dokuz", "on"]
        let m = s / 60, r = s % 60
        if r == 0, m >= 1, m <= 10 { return "\(words[m]) dakika" }
        if m == 0 { return "\(r) saniye" }
        return "\(m) dakika \(r) saniye"
    }

    /// The announcements use the Turkish system voice chosen in the settings (Yelda), else the device's Turkish voice.
    var announcerVoice: (voice: AVSpeechSynthesisVoice?, pitch: Float, volume: Float) {
        let id = settings.voiceByLanguage["tr"] ?? ""
        let v = Voices.voice(id) ?? Voices.defaultVoice(for: "tr", chosen: [:])
        let t = v.map { tune($0.identifier) } ?? VoiceTune()
        return (v, Float(t.pitch), Float(t.volume))
    }
}

/// Speaks the automation's short announcements through the app's own (already active) session.
@MainActor
final class Announcer: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private var waiter: CheckedContinuation<Void, Never>?
    private var serial = 0

    override init() {
        super.init()
        synth.delegate = self
        synth.usesApplicationAudioSession = true
    }

    func say(_ text: String, voice: (voice: AVSpeechSynthesisVoice?, pitch: Float, volume: Float), mix: Bool) async {
        stop()
        let session = AVAudioSession.sharedInstance()
        if session.category != .playback {
            try? session.setCategory(.playback, mode: .spokenAudio, options: mix ? [.mixWithOthers] : [])
        }
        try? session.setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.voice = voice.voice
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 1.1
        u.pitchMultiplier = voice.pitch
        u.volume = max(0.6, voice.volume)
        u.postUtteranceDelay = 0.4
        serial += 1
        let mine = serial
        await withCheckedContinuation { c in
            waiter = c
            synth.speak(u)
            // a safety net: a voice that never reports its end does not hold the automation
            let seconds = Double(text.count) / 8 + 6
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                if self?.serial == mine { self?.finish() }
            }
        }
    }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        finish()
    }

    private func finish() {
        waiter?.resume()
        waiter = nil
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in self.finish() }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in self.finish() }
    }
}
