// The voice-note recorder: one tap starts, one tap stops. AAC mono 16 kHz 32 kbit/s (Kıvılcım's quality: ≈240 KB a
// minute, enough for Whisper). Recording needs a play-and-record session; the reader pauses first and takes its own
// session back afterwards. When Bluetooth headphones with a microphone are connected (FiiO BTR15 on the bicycle), the
// voice comes from their microphone (the hands-free profile, HFP); the phone in a pocket hears nothing. While recording,
// sound on the headphones is call quality; after the note the reader's session brings A2DP back. Without such
// headphones the phone's microphone records, as before.
// The text is written on the phone right away (iOS speech recognition, Turkish, on the device when it can); the Mac
// writes a cleaner one with Whisper later.
import Foundation
import AVFoundation
import Speech
import Observation

@MainActor
@Observable
final class NoteRecorder {
    enum Phase: Equatable { case idle, starting, recording, saving }
    private(set) var phase: Phase = .idle
    private(set) var startedAt: Date?
    private(set) var level: Float = 0                 // 0…1, for the button's ring
    var error: String?

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var meter: Timer?
    @ObservationIgnored private var file: URL?
    /// Counts the starts: `start()` waits (permission, the Bluetooth link) and must not go on once `stop()` ended it.
    @ObservationIgnored private var attempt = 0

    var isRecording: Bool { phase == .recording || phase == .starting }

    /// Starts recording; false when the microphone is not allowed (the error says so).
    func start(withMusic: Bool) async -> Bool {
        guard phase == .idle else { return false }
        phase = .starting
        attempt += 1
        let mine = attempt
        let granted = await AVAudioApplication.requestRecordPermission()
        // a second press while waiting ended this start (`stop()`): nothing is recorded, the session is left alone
        guard mine == attempt, phase == .starting else { return false }
        guard granted else {
            error = "Mikrofon izni yok: Ayarlar › Wise Path › Mikrofon."
            phase = .idle
            return false
        }
        let s = AVAudioSession.sharedInstance()
        var opts: AVAudioSession.CategoryOptions = [.allowBluetoothA2DP, Self.handsFree]
        if withMusic { opts.insert(.mixWithOthers) }
        do {
            try s.setCategory(.playAndRecord, mode: .default, options: opts)
            try s.setActive(true)
        } catch {
            self.error = "Kayıt başlamadı: \(error.localizedDescription)"
            phase = .idle
            return false
        }
        await useHeadsetMicrophone(s, attempt: mine)
        guard mine == attempt, phase == .starting else { return false }
        let url = FileManager.default.temporaryDirectory.appending(path: "note-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32000, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        guard let r = try? AVAudioRecorder(url: url, settings: settings) else {
            error = "Kayıt başlamadı."
            phase = .idle
            return false
        }
        r.isMeteringEnabled = true
        guard r.record() else {
            error = "Kayıt başlamadı."
            phase = .idle
            return false
        }
        recorder = r
        file = url
        startedAt = .now
        phase = .recording
        let t = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let r = self.recorder else { return }
                r.updateMeters()
                self.level = max(0, min(1, (r.averagePower(forChannel: 0) + 50) / 50))
            }
        }
        RunLoop.main.add(t, forMode: .common)
        meter = t
        return true
    }

    /// Stops and returns the file and its length; nil for a slip (under half a second).
    func stop() -> (url: URL, seconds: Double)? {
        meter?.invalidate(); meter = nil
        level = 0
        guard let r = recorder, let url = file else {
            // stopped while still starting: that start is void (it checks `attempt` after each wait) and the
            // session it may have opened is given back before the reader takes its own again
            if phase == .starting {
                attempt += 1
                try? AVAudioSession.sharedInstance().setPreferredInput(nil)
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
            phase = .idle
            return nil
        }
        let seconds = r.currentTime
        r.stop()
        recorder = nil
        file = nil
        startedAt = nil
        phase = .idle
        try? AVAudioSession.sharedInstance().setPreferredInput(nil)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard seconds >= 0.5 else { try? FileManager.default.removeItem(at: url); return nil }
        return (url, seconds)
    }

    func cancel() { if let r = stop() { try? FileManager.default.removeItem(at: r.url) } }

    // MARK: microphone

    /// The microphone of the last recording, for the recording strip: "BTR15" or "Telefon".
    private(set) var inputName: String?
    private(set) var headsetInput = false

    private static var handsFree: AVAudioSession.CategoryOptions {
        if #available(iOS 26, *) { .allowBluetoothHFP } else { .allowBluetooth }
    }

    /// Prefers a Bluetooth headset microphone, then a wired one, then the phone. The hands-free link takes a moment
    /// to come up; the recording starts once it has (at most ~1.5 s), so the first words are not lost.
    private func useHeadsetMicrophone(_ s: AVAudioSession, attempt mine: Int) async {
        let inputs = s.availableInputs ?? []
        let headset = inputs.first { $0.portType == .bluetoothHFP } ?? inputs.first { $0.portType == .headsetMic }
        if let headset {
            try? s.setPreferredInput(headset)
            for _ in 0..<15 where s.currentRoute.inputs.first?.portType != headset.portType {
                try? await Task.sleep(for: .milliseconds(100))
                guard mine == attempt else { return }
            }
        }
        let now = s.currentRoute.inputs.first
        headsetInput = now.map { $0.portType == .bluetoothHFP || $0.portType == .headsetMic } ?? false
        inputName = headsetInput ? now?.portName : "Telefon"
    }

    // MARK: text

    /// The recording as text, on the phone. Empty when recognition is not allowed or heard nothing.
    nonisolated static func transcribe(_ url: URL, language: String = "tr-TR") async -> String {
        let status = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        guard status == .authorized, let rec = SFSpeechRecognizer(locale: Locale(identifier: language)), rec.isAvailable else { return "" }
        let req = SFSpeechURLRecognitionRequest(url: url)
        req.shouldReportPartialResults = false
        req.addsPunctuation = true
        if rec.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        // The recognizer is held until the answer is in: a local one could be released while the task still ran,
        // and then the callback (and the answer) never came.
        let hold = RecognitionHold(rec)
        return await withCheckedContinuation { c in
            let finish: @Sendable (String) -> Void = { s in
                if hold.finish() { c.resume(returning: s) }
            }
            hold.set(rec.recognitionTask(with: req) { result, error in
                if let result, result.isFinal { finish(result.bestTranscription.formattedString) }
                else if error != nil { finish(result?.bestTranscription.formattedString ?? "") }
            })
            DispatchQueue.global().asyncAfter(deadline: .now() + 90) { hold.cancel(); finish("") }
        }
    }
}

/// Keeps a speech recognizer and its task alive until the recognition has answered (or timed out), once.
private final class RecognitionHold: @unchecked Sendable {
    private let lock = NSLock()
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private var done = false

    init(_ r: SFSpeechRecognizer) { recognizer = r }

    func set(_ t: SFSpeechRecognitionTask) {
        lock.lock(); defer { lock.unlock() }
        if !done { task = t }
    }

    func cancel() {
        lock.lock(); let t = task; lock.unlock()
        t?.cancel()
    }

    /// True the first time only; lets the recognizer and the task go.
    func finish() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        recognizer = nil
        task = nil
        return true
    }
}
