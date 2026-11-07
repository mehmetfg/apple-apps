// Records one sentence that you build yourself from the widget (🎙 in "Cümle cümle"). Runs in the app's process,
// usually in the background: the widget's intent wakes the app, a Live Activity shows the timer (iOS requires it).
// After the recording: on-device speech recognition → compared with the target sentence → the widget shows the result
// and the fading ladder moves. Files stay in the App Group (kurma/) until the app copies them to the vault.
import Foundation
import AVFoundation
import PDMBus
import ActivityKit
import Speech
import UIKit
import WidgetKit

/// Sidecar JSON next to each recording; read later by Claude for evaluation ("Memories kurma değerlendir").
struct RebuildRecord: Codable, Hashable {
    var file: String
    var day: Int
    var sentence: Int
    var target: String
    var tr: String?
    var device: String
    var recordedAt: Date
    var seconds: Double
    var rung: Int                 // how much of the sentence was hidden while you built it
    var heard: String?
    var ratio: Double?
    var missed: [String]?
}

@MainActor
final class SentenceRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    static let shared = SentenceRecorder()

    /// "day-index" while recording, for the app's screens (Oku); the widget reads RebuildState.activeKey.
    @Published private(set) var activeKey: String?
    /// The last finished attempt, so the screen that started it can show the result.
    @Published private(set) var lastAttempt: RebuildAttempt?

    private var recorder: AVAudioRecorder?
    private var activity: Activity<RebuildActivity>?
    private var current: (day: Int, index: Int, en: String, tr: String?, rung: Int, file: URL, start: Date)?
    private var background: UIBackgroundTaskIdentifier = .invalid

    /// en/tr: from the app's own screens (the sentence is at hand); the widget passes only day + index.
    func toggle(day: Int, index: Int, en: String? = nil, tr: String? = nil) async {
        if current != nil {
            let same = current?.day == day && current?.index == index
            await stop()
            if same { return }
        }
        await start(day: day, index: index, en: en, tr: tr)
    }

    /// In the app (foreground) the permissions can be asked; from the lock screen they cannot.
    func askPermissions() async -> Bool {
        guard await AVAudioApplication.requestRecordPermission() else { return false }
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            _ = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        }
        return true
    }

    func start(day: Int, index: Int, en: String? = nil, tr: String? = nil) async {
        let st = RebuildState.self
        st.d.removeObject(forKey: st.errorKey)
        guard AVAudioApplication.shared.recordPermission == .granted else {
            fail("Önce uygulamada bir kez kayıt yap: mikrofon izni orada sorulur.")
            return
        }
        NotificationCenter.default.post(name: SentencePlayer.willPlay, object: nil)   // the app's own player pauses
        SentencePlayer.shared.stop()
        // Capture first: only the audio session stands between the tap and the first recorded sample. The sentence
        // text, the Live Activity and the widget state follow once the recorder is running.
        do {
            let o = AVAudioSession.sharedInstance()
            try o.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try o.setActive(true)
        } catch { fail("Mikrofon açılamadı."); return }
        let name = String(format: "%03d-%02d", day, index) + "-\(Cihaz.ad)-\(UUID().uuidString.prefix(8).lowercased()).m4a"
        let url = st.folder.appendingPathComponent(name)
        guard let r = try? AVAudioRecorder(url: url, settings: Kaydedici.ayarlar), r.record(forDuration: st.tavan) else {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            fail("Kayıt başlamadı."); return
        }
        let begin = Date()
        r.delegate = self
        let w = en == nil || tr == nil ? Paylasim.oku()?.sentences?.first(where: { $0.i == index }) : nil
        guard let text = en ?? w?.en else {      // the sentence is not in the snapshot: nothing to compare with
            r.delegate = nil
            r.stop()
            try? FileManager.default.removeItem(at: url)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            return
        }
        let s = (en: text, tr: tr ?? w?.tr)
        recorder = r
        current = (day, index, s.en, s.tr, st.rung(day, index), url, begin)
        activeKey = st.key(day, index)
        lastAttempt = nil
        startActivity(day: day, index: index, tr: s.tr ?? "", start: begin)
        st.d.set(st.key(day, index), forKey: st.activeKey)
        st.d.set(begin, forKey: st.activeStartKey)
        st.reload()
    }

    func stop() async {
        guard let c = current, let r = recorder else { return }
        let seconds = r.currentTime > 0 ? r.currentTime : Date().timeIntervalSince(c.start)
        r.stop()
        recorder = nil; current = nil
        activeKey = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let st = RebuildState.self
        st.d.removeObject(forKey: st.activeKey)
        st.d.removeObject(forKey: st.revealKey)
        if seconds < 1 {
            try? FileManager.default.removeItem(at: c.file)
            await endActivity(nil); st.reload(); return
        }
        background = UIApplication.shared.beginBackgroundTask(withName: "memories-kurma") { [weak self] in
            Task { @MainActor in self?.endBackground() }
        }
        st.reload()
        var heard: String?
        var ratio: Double?
        var missed: [String] = []
        // Recognition permission cannot be asked on the lock screen; if never asked, skip (the recording is still kept).
        if SFSpeechRecognizer.authorizationStatus() == .authorized, let h = await Kaydedici.tani(c.file) {
            heard = h
            let m = Metin.takilanlar(metin: c.en, duyulan: h)
            ratio = (m.oran * 100).rounded() / 100
            // here every unheard word counts (a single sentence: the tail is part of the sentence too)
            let target = Metin.kelimeler(c.en)
            for (k, w) in target.enumerated() where !m.eslesen.contains(k) && w.count > 1 && !missed.contains(w) && missed.count < 6 {
                missed.append(w)
            }
        }
        let attempt = RebuildAttempt(day: c.day, index: c.index, date: c.start, seconds: seconds, ratio: ratio, missed: missed, heard: heard)
        st.save(attempt)
        lastAttempt = attempt
        st.step(c.day, c.index, ratio: ratio)
        let record = RebuildRecord(file: c.file.lastPathComponent, day: c.day, sentence: c.index, target: c.en, tr: c.tr,
                                   device: Cihaz.ad, recordedAt: c.start, seconds: (seconds * 10).rounded() / 10,
                                   rung: c.rung, heard: heard, ratio: ratio, missed: missed.isEmpty ? nil : missed)
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys, .prettyPrinted]
        if let v = try? e.encode(record) {
            try? v.write(to: c.file.deletingPathExtension().appendingPathExtension("json"), options: .atomic)
        }
        await endActivity(attempt)
        st.reload()
        await emitWordEvents(day: c.day, sentence: c.en, ratio: ratio, missed: missed)
        syncToVault()
        endBackground()
    }

    /// Sends the new recording to the vault. From the widget the app runs in the background and is suspended as
    /// soon as nothing holds it, so the sync gets its own background task (and stops when that time is up).
    private func syncToVault() {
        var id = UIBackgroundTaskIdentifier.invalid
        var work: Task<Void, Never>?
        let end = {
            if id != .invalid { UIApplication.shared.endBackgroundTask(id); id = .invalid }
        }
        id = UIApplication.shared.beginBackgroundTask(withName: "memories-kurma-sync") {
            work?.cancel()
            Task { @MainActor in end() }
        }
        work = Task { @MainActor in
            await Depo.shared.esitleSimdi(localChange: true)
            if !Task.isCancelled { await Depo.shared.syncBus() }
            end()
        }
    }

    /// Tells the PDM bus how the day's TARGET words in this sentence went (never every word of the sentence):
    /// `word.struggled` for a target word among the missed ones; `word.practiced` for the others when the attempt
    /// scored 85 % or more. Runs in the app's process (the recording intent does), so the app's bus is used.
    private func emitWordEvents(day: Int, sentence: String, ratio: Double?, missed: [String]) async {
        guard let ratio else { return }             // not recognised: nothing was scored
        let depo = Depo.shared
        await depo.whenLoaded()
        guard let p = depo.paketler.first(where: { $0.gun == day }) else { return }
        let targets = Metin.kelimeler(sentence).compactMap { p.kelime($0)?.w }.uniqued()
        guard !targets.isEmpty else { return }
        let struggled = Set(missed.compactMap { p.kelime($0)?.w })
        let data: [String: PDMValue] = ["day": .int(day), "score": .int(Int((ratio * 100).rounded()))]
        for w in targets {
            if struggled.contains(w) { depo.bus.emit("word.struggled", subject: PDMSubject.word(w), data: data) }
            else if ratio >= 0.85 { depo.bus.emit("word.practiced", subject: PDMSubject.word(w), data: data) }
        }
    }

    private func fail(_ s: String) {
        RebuildState.d.set(s, forKey: RebuildState.errorKey)
        RebuildState.reload()
    }

    private func endBackground() {
        if background != .invalid { UIApplication.shared.endBackgroundTask(background); background = .invalid }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        // 30-second cap or an interruption: keep what was recorded.
        Task { @MainActor in await SentenceRecorder.shared.stop() }
    }

    // MARK: Live Activity

    private func startActivity(day: Int, index: Int, tr: String, start: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let old = Activity<RebuildActivity>.activities
        Task { for a in old { await a.end(nil, dismissalPolicy: .immediate) } }
        activity = try? Activity.request(attributes: RebuildActivity(day: day, index: index, tr: tr),
                                         content: .init(state: .init(start: start),
                                                        staleDate: start.addingTimeInterval(RebuildState.tavan + 5)))
    }

    private func endActivity(_ a: RebuildAttempt?) async {
        guard let act = activity else { return }
        activity = nil
        if let a {
            let s = RebuildActivity.ContentState(start: a.date, done: true, ratio: a.ratio, missed: a.missed)
            await act.end(.init(state: s, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(5)))
        } else {
            await act.end(nil, dismissalPolicy: .immediate)
        }
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] { var g = Set<Element>(); return filter { g.insert($0).inserted } }
}
