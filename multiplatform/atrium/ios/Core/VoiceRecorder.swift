// Records a voice idea straight into Kıvılcım's inbox (ses/<yyyy-MM>/<id>.m4a + .json).
// Kıvılcım on the Mac transcribes it with local Whisper — no tokens, no server.
import AVFoundation
import Foundation

@MainActor
final class VoiceRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var level: Float = 0
    @Published private(set) var levels: [Float] = []
    @Published var error: String?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var tempURL: URL?
    private var startedAt = Date()
    private var recordingId = ""

    #if os(macOS)
    static let device = "mac"
    #else
    static let device = "iphone"
    #endif

    func start() async {
        error = nil
        #if os(iOS)
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else { error = "Mikrofon izni yok. Ayarlar › Atrium › Mikrofon."; return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch { self.error = error.localizedDescription; return }
        #else
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        guard granted else { error = "Mikrofon izni yok. Sistem Ayarları › Gizlilik › Mikrofon › Atrium."; return }
        #endif
        let now = Date()
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        recordingId = "\(f.string(from: now))-\(Self.device)-\(String(format: "%04x", Int.random(in: 0..<65_536)))"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(recordingId + ".m4a")
        // Kıvılcım's "balanced" quality: 16 kHz mono AAC 32 kbit/s (Whisper-clean, ~240 KB/min).
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16_000,
                                       AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 32_000]
        do {
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.isMeteringEnabled = true
            r.delegate = self
            guard r.record(forDuration: 30 * 60) else { error = "Kayıt başlamadı."; return }
            recorder = r
            tempURL = url
            startedAt = now
            levels = []
            isRecording = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        } catch { self.error = error.localizedDescription }
    }

    private func tick() {
        guard let r = recorder, r.isRecording else { return }
        r.updateMeters()
        elapsed = r.currentTime
        let db = r.averagePower(forChannel: 0)
        level = max(0, min(1, (db + 50) / 50))
        levels.append(level)
        if levels.count > 60 { levels.removeFirst(levels.count - 60) }
    }

    func cancel() {
        recorder?.stop()
        recorder?.deleteRecording()
        finish()
    }

    /// Stops and moves the file into the vault. Returns the vault-relative audio path.
    func stop(into store: VaultStore) async -> String? {
        guard let r = recorder, let tempURL else { return nil }
        let duration = r.currentTime
        r.stop()
        finish()
        guard duration >= 1 else { try? FileManager.default.removeItem(at: tempURL); error = "1 saniyeden kısa kayıt saklanmadı."; return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        let month = f.string(from: startedAt)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let folder = "\(VaultStore.sparkFolder)/ses/\(month)"
        let audioPath = "\(folder)/\(recordingId).m4a"
        let sidecar: [String: Any] = ["id": recordingId, "cihaz": Self.device, "dil": "tr", "kalite": "dengeli",
                                      "sure": (duration * 10).rounded() / 10, "zaman": f.string(from: startedAt), "kaynak": "atrium"]
        do {
            let audioURL = try store.url(for: audioPath)
            let jsonURL = try store.url(for: "\(folder)/\(recordingId).json")
            let id = recordingId
            try await Task.detached(priority: .userInitiated) {
                try FileManager.default.createDirectory(at: audioURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                var coordinationError: NSError?
                var failure: Error?
                NSFileCoordinator().coordinate(writingItemAt: audioURL, options: .forReplacing, error: &coordinationError) { u in
                    do {
                        if FileManager.default.fileExists(atPath: u.path) { try FileManager.default.removeItem(at: u) }
                        try FileManager.default.copyItem(at: tempURL, to: u)
                    } catch { failure = error }
                }
                if let e = coordinationError ?? failure { throw e }
                let data = try JSONSerialization.data(withJSONObject: sidecar, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: jsonURL, options: .atomic)
                try? FileManager.default.removeItem(at: tempURL)
                _ = id
            }.value
            return audioPath
        } catch {
            self.error = "Ses vault'a yazılamadı: \(error.localizedDescription). Kayıt geçici klasörde duruyor."
            return nil
        }
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        recorder = nil
        isRecording = false
        level = 0
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {}
}
