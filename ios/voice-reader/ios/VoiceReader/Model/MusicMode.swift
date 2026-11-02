// Müzik modu: the book in silence while music plays. Wise Path does not speak; the sentences of the part already read
// come and go on the screen with the music's beat: the reader's own marks first, then Teoria's key sentences and the
// book's main idea. The beat is heard through the microphone (music from the speaker) or given by tapping (music in
// the headphones, which the microphone cannot hear); without either it keeps a steady 96 a minute.
import Foundation
import AVFoundation
import Observation

struct MusicLine: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable { case mark, key, idea }
    var id = UUID()
    var text: String
    var kind: Kind
    var why: String?                    // Teoria: why this sentence matters
    var chapter: String?

    var label: String {
        switch kind {
        case .mark: "işaretin"
        case .key: "can alıcı"
        case .idea: "ana fikir"
        }
    }
}

/// Teoria's insight file, only the parts the music mode shows.
struct TeoriaInsight: Decodable, Sendable {
    struct Core: Decodable, Sendable { var theme: String?; var claim: String?; var idea: String? }
    struct Key: Decodable, Sendable { var quote: String; var why: String?; var weight: Int? }
    var core: Core?
    var keys: [Key]?
}

enum MusicPool {
    /// The lines for a book: every mark (in book order), the key sentences found in the part already read (heaviest
    /// first), and the main idea. Marks come every other line so the reader's own choices lead.
    static func build(doc: DocumentRecord, text: String, insight: TeoriaInsight?, chapterAt: (Int) -> String?) -> [MusicLine] {
        let marks = doc.highlights.sorted { $0.location < $1.location }
            .map { MusicLine(text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines), kind: .mark, chapter: chapterAt($0.location)) }
            .filter { $0.text.count >= 12 }
        let ns = text as NSString
        let readUpTo = doc.isFinished ? ns.length : doc.position
        var keys: [MusicLine] = []
        for k in (insight?.keys ?? []).sorted(by: { ($0.weight ?? 0) > ($1.weight ?? 0) }) {
            // only sentences already heard: the quote is looked up in the text by its first words
            let probe = String(k.quote.prefix(40))
            let r = ns.range(of: probe, options: [.caseInsensitive, .diacriticInsensitive])
            guard r.location != NSNotFound, r.location <= readUpTo else { continue }
            keys.append(MusicLine(text: k.quote, kind: .key, why: k.why, chapter: chapterAt(r.location)))
        }
        var ideas: [MusicLine] = []
        if doc.progress > 0.15 || doc.isFinished, let c = insight?.core {
            for t in [c.claim, c.idea].compactMap({ $0 }) where t.count > 20 { ideas.append(MusicLine(text: t, kind: .idea)) }
        }
        var out: [MusicLine] = []
        var m = marks[...], k = (keys + ideas)[...]
        while !m.isEmpty || !k.isEmpty {
            if let x = m.popFirst() { out.append(x) }
            if let x = k.popFirst() { out.append(x) }
        }
        return out
    }
}

/// The beat: from the microphone when it hears a steady pulse, else from the tapped (or default) tempo.
@MainActor
@Observable
final class BeatTracker {
    enum Source: Equatable { case clock, microphone }
    private(set) var beat = 0                   // goes up by one on every beat
    private(set) var bpm: Double = 96
    private(set) var level: Double = 0          // loudness heard, 0…1 (for the glow)
    private(set) var source: Source = .clock
    private(set) var listening = false          // the microphone is on
    var paused = false

    @ObservationIgnored private var clock: Task<Void, Never>?
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var onsets: [Date] = []
    @ObservationIgnored private var taps: [Date] = []
    @ObservationIgnored private var lastMicBeat = Date.distantPast

    /// The microphone only when the music comes out of the phone's speaker: with headphones it hears nothing, and
    /// switching the session to play-and-record there cut Spotify (2026-10-28).
    func start(microphone: Bool) {
        startClock()
        if microphone, Self.speakerOut { Task { await startMicrophone() } }
    }

    static var speakerOut: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.allSatisfy { $0.portType == .builtInSpeaker || $0.portType == .builtInReceiver }
    }

    func stop() {
        clock?.cancel(); clock = nil
        stopMicrophone()
    }

    /// Four or more taps in time set the tempo (the average of the last intervals).
    func tap() {
        let now = Date.now
        taps.append(now)
        taps.removeAll { now.timeIntervalSince($0) > 3 }
        guard taps.count >= 3 else { return }
        let gaps = zip(taps.dropFirst(), taps).map { $0.timeIntervalSince($1) }
        let mean = gaps.reduce(0, +) / Double(gaps.count)
        guard mean > 0.25, mean < 1.6 else { return }
        bpm = (60 / mean).rounded()
        source = .clock
        startClock()
    }

    private func startClock() {
        clock?.cancel()
        clock = Task { [weak self] in
            while !Task.isCancelled {
                let wait = 60 / (self?.bpm ?? 96)
                try? await Task.sleep(for: .seconds(wait))
                guard let self, !Task.isCancelled else { return }
                // the microphone leads while it hears a pulse; the clock fills in when it has been quiet for 3 s
                if self.source == .microphone, Date.now.timeIntervalSince(self.lastMicBeat) < 3 { continue }
                self.source = .clock
                if !self.paused { self.beat += 1 }
            }
        }
    }

    // MARK: microphone

    /// Listens without taking the music away: play-and-record mixed with others, the phone's own microphone (no
    /// Bluetooth headset microphone, which would turn the music into call quality).
    private func startMicrophone() async {
        guard await AVAudioApplication.requestRecordPermission() else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP])
        try? session.setActive(true)
        let e = AVAudioEngine()
        let input = e.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }
        let detector = OnsetDetector()
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let ch = buffer.floatChannelData?[0] else { return }
            let n = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<n { sum += ch[i] * ch[i] }
            let rms = sqrt(sum / Float(max(1, n)))
            let hit = detector.feed(rms)
            Task { @MainActor in self?.heard(rms: rms, onset: hit) }
        }
        do { try e.start(); engine = e; listening = true } catch { input.removeTap(onBus: 0) }
    }

    /// The session is let go first (other audio is told it may come back), then set back to playback: changing the
    /// category of an active session interrupted the music.
    private func stopMicrophone() {
        guard engine != nil else { return }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        listening = false
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
    }

    private func heard(rms: Float, onset: Bool) {
        level = level * 0.7 + min(1, Double(rms) * 8) * 0.3
        guard onset else { return }
        let now = Date.now
        onsets.append(now)
        onsets.removeAll { now.timeIntervalSince($0) > 5 }
        // a pulse is steady when the last gaps are close to one another
        let gaps = zip(onsets.dropFirst(), onsets).map { $0.timeIntervalSince($1) }.suffix(6)
        guard gaps.count >= 4 else { return }
        let mean = gaps.reduce(0, +) / Double(gaps.count)
        let spread = sqrt(gaps.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(gaps.count)) / mean
        guard spread < 0.3, mean > 0.25, mean < 1.6 else { return }
        bpm = (60 / mean).rounded()
        source = .microphone
        lastMicBeat = now
        if !paused { beat += 1 }
    }
}

/// Energy onsets: a block clearly louder than the last second's average, at most one every 0.25 s.
private final class OnsetDetector: @unchecked Sendable {
    private var history: [Float] = []
    private var since = 99
    func feed(_ rms: Float) -> Bool {
        history.append(rms)
        if history.count > 43 { history.removeFirst() }          // ≈ 1 s of 1024-frame blocks at 44.1 kHz
        since += 1
        let avg = history.reduce(0, +) / Float(history.count)
        guard rms > 0.01, rms > avg * 1.45, since > 10 else { return false }
        since = 0
        return true
    }
}
