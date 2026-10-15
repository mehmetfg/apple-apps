// Read aloud — the book as Voice Dream reads it, inside Teoria: the device's Turkish voices, speed (1× … 3.5×) and tone
// (a lower pitch makes the voice deeper). Paragraph by paragraph from the page you are on.
//
// The voice is not spoken by the system: each paragraph is synthesised into audio buffers and played by Teoria's own
// audio engine. That makes Teoria a real "Now Playing" app (lock screen, Control Center, headphone buttons) and lets the
// cursor follow the audio that is actually coming out: every word's position in the audio is recorded while it is
// synthesised, and the word under the play head is the one drawn on the page.
import Foundation
import AVFoundation
import os
private let vlog = SyncLog()

/// Diagnostics for cursor sync: lines go to the system log; to Documents/voice-sync.log only when the
/// `teoria.voice.debugLog` default is on (the file write used to run on the main thread up to 25 times a second).
private struct SyncLog: Sendable {
    private static let os = Logger(subsystem: "teoria.voice", category: "sync")
    private static let toFile = UserDefaults.standard.bool(forKey: "teoria.voice.debugLog")
    private static let url = URL.documentsDirectory.appending(path: "voice-sync.log")
    private static let lock = NSLock()
    func log(_ m: String) {
        Self.os.debug("\(m, privacy: .public)")
        guard Self.toFile else { return }
        let data = Data((String(format: "%.3f ", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 10000)) + m + "\n").utf8)
        Self.lock.lock(); defer { Self.lock.unlock() }
        if let h = try? FileHandle(forWritingTo: Self.url) {
            if (try? h.seekToEnd()) ?? 0 > 3_000_000 { try? h.truncate(atOffset: 0) }
            h.write(data); try? h.close()
        } else { try? data.write(to: Self.url) }
    }
}
#if os(iOS)
import MediaPlayer
import UIKit
#endif

struct SpokenBlock: Hashable { let ch: Int; let b: Int; let text: String }

@MainActor
final class ReaderVoice: NSObject, ObservableObject {
    static let shared = ReaderVoice()

    @Published private(set) var speaking = false
    @Published private(set) var paused = false
    @Published private(set) var live: (ch: Int, b: Int, range: NSRange)?     // the word being heard (UTF-16, block text)
    @Published private(set) var bookID: String?

    @Published var voiceID: String { didSet { UserDefaults.standard.set(voiceID, forKey: "teoria.voice.id"); restartSoon() } }
    /// Playback speed as a multiple of normal (1× … 3.5×), shown as "1,5×".
    @Published var speed: Double { didSet { UserDefaults.standard.set(speed, forKey: "teoria.voice.speed"); restartSoon() } }
    @Published var pitch: Double { didSet { UserDefaults.standard.set(pitch, forKey: "teoria.voice.pitch"); restartSoon() } }

    #if os(iOS)
    var artwork: MPMediaItemArtwork?
    #endif

    private let synth = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var format: AVAudioFormat?                  // what the player is connected with
    nonisolated private let recorder = Recorder()

    private var queue: [SpokenBlock] = []
    private var index = 0                               // paragraph under the play head
    private var title = ""
    private var restartTask: Task<Void, Never>?
    private var ticker: Timer?

    /// One synthesised paragraph on the player's timeline (frames since the player started).
    private struct Segment {
        let id: Int
        let block: Int
        let offset: Int                                 // the paragraph may start mid-text (UTF-16)
        let start: AVAudioFramePosition
        let length: Int                                 // characters spoken in this segment
        var end: AVAudioFramePosition?                  // known once the paragraph is fully synthesised
        var shift: AVAudioFramePosition = 0             // silence the player sat through waiting for this paragraph
        var words: [(at: AVAudioFramePosition, range: NSRange)] = []
    }
    private var segments: [Segment] = []
    private var scheduledEnd: AVAudioFramePosition = 0  // frames handed to the player so far
    private var synthesizing = false
    private var nextBlock = 0
    private var nextOffset = 0
    private var generation = 0
    private var serial = 0
    private var ratio = 1.0                             // player sample rate / voice sample rate
    private var lastAudio = Date.distantPast            // when the synthesiser last handed over audio (stall watchdog)

    override init() {
        let d = UserDefaults.standard
        let saved = d.string(forKey: "teoria.voice.id").flatMap { AVSpeechSynthesisVoice(identifier: $0) != nil ? $0 : nil }
        voiceID = saved ?? ReaderVoice.voices.first?.identifier ?? ""
        speed = d.object(forKey: "teoria.voice.speed") as? Double ?? 1.0
        pitch = d.object(forKey: "teoria.voice.pitch") as? Double ?? 0.9
        super.init()
        synth.delegate = self
        engine.attach(player)
        #if os(iOS)
        remote()
        #endif
    }

    /// Turkish voices on this device, best quality first (Premium › Enhanced › Default).
    static var voices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("tr") }
            .sorted { ($0.quality.rawValue, $0.name) > ($1.quality.rawValue, $1.name) }
    }
    static func qualityName(_ v: AVSpeechSynthesisVoice) -> String {
        switch v.quality { case .premium: "Premium"; case .enhanced: "Gelişmiş"; default: "Standart" }
    }

    static let speeds: [Double] = stride(from: 1.0, through: 3.5, by: 0.25).map { $0 }
    static func speedName(_ m: Double) -> String {
        var t = String(format: "%.2f", m)
        while t.hasSuffix("0") { t.removeLast() }
        if t.hasSuffix(".") { t.removeLast() }
        return t.replacingOccurrences(of: ".", with: ",") + "×"
    }

    /// AVSpeech's rate is not linear. Measured with the Turkish voice (synthesised length of the same passage):
    /// rate → multiple of rate 0.5. Interpolated in between.
    private static let curve: [(rate: Double, mult: Double)] = [
        (0.50, 1.00), (0.55, 1.30), (0.60, 1.60), (0.65, 1.87), (0.70, 2.21), (0.75, 2.49),
        (0.80, 2.79), (0.85, 3.03), (0.90, 3.40), (0.95, 3.67), (1.00, 3.88),
    ]
    static func rate(for m: Double) -> Float {
        let m = min(max(m, 1), 3.88)
        for (a, b) in zip(curve, curve.dropFirst()) where m <= b.mult {
            return Float(a.rate + (b.rate - a.rate) * (m - a.mult) / (b.mult - a.mult))
        }
        return 1
    }

    private var voice: AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice(identifier: voiceID) ?? Self.voices.first ?? AVSpeechSynthesisVoice(language: "tr-TR")
    }

    // MARK: control

    func play(book: String, title: String, blocks: [SpokenBlock], from i: Int, offset: Int = 0) {
        stop()
        guard !blocks.isEmpty else { return }
        bookID = book; self.title = title
        queue = blocks
        #if os(iOS)
        // no mixing options: only a non-mixable session becomes the lock screen's "Now Playing" app
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
        UIApplication.shared.beginReceivingRemoteControlEvents()
        #endif
        speaking = true; paused = false
        restart(at: max(0, min(i, blocks.count - 1)), offset: offset)
        let t = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    func toggle() {
        if !speaking { return }
        if paused { resume() } else { pause() }
    }

    func pause() {
        guard speaking, !paused else { return }
        player.pause()
        paused = true
        nowPlaying()
    }

    func resume() {
        guard speaking, paused else { return }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        paused = false
        if engine.isRunning {
            if scheduledEnd > 0 { player.play() }
        } else {
            // the system stopped the engine (call, Siri, route change): pick up again from the sentence being heard
            let blk = queue[safe: index]?.text ?? ""
            restart(at: index, offset: sentenceStart(blk, before: live?.range.location ?? 0))
        }
        nowPlaying()
    }

    func stop() {
        restartTask?.cancel()
        ticker?.invalidate(); ticker = nil
        generation += 1
        recorder.reset(nil)
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        player.stop()
        engine.stop()
        queue = []; index = 0; segments = []; scheduledEnd = 0; synthesizing = false
        speaking = false; paused = false; live = nil
        #if os(iOS)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    func skip(_ d: Int) {
        guard speaking, !queue.isEmpty else { return }
        restart(at: max(0, min(queue.count - 1, index + d)), offset: 0)
    }

    /// A setting changed while reading: continue from the sentence being heard, with the new voice / speed / tone.
    private func restartSoon() {
        guard speaking else { return }
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self, !Task.isCancelled, self.speaking else { return }
            let blk = self.queue[safe: self.index]?.text ?? ""
            self.restart(at: self.index, offset: self.sentenceStart(blk, before: self.live?.range.location ?? 0))
        }
    }

    /// Drop everything scheduled and start the timeline again at a paragraph (and a point inside it).
    private func restart(at block: Int, offset: Int) {
        generation += 1
        recorder.reset(nil)
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        player.stop()
        segments = []; scheduledEnd = 0; synthesizing = false
        index = block; nextBlock = block; nextOffset = offset
        if let blk = queue[safe: block] { live = (blk.ch, blk.b, NSRange(location: offset, length: 0)) }
        synthesizeNext()
        nowPlaying()
    }

    private func sentenceStart(_ t: String, before i: Int) -> Int {
        let ns = t as NSString
        var j = min(i, ns.length)
        while j > 0 {
            let c = ns.character(at: j - 1)
            if c == 46 || c == 33 || c == 63 || c == 8230 { break }     // . ! ? …
            j -= 1
        }
        while j < ns.length, ns.character(at: j) == 32 { j += 1 }
        return j
    }

    // MARK: synthesis → player

    /// Keep about half a minute of audio ahead of the play head; synthesis is many times faster than speech.
    private func synthesizeNext() {
        guard speaking, !synthesizing, let blk = queue[safe: nextBlock] else { return }
        let rate = format?.sampleRate ?? 22050
        if scheduledEnd - playhead > AVAudioFramePosition(rate * 30) { return }
        let ns = blk.text as NSString
        let off = min(nextOffset, ns.length)
        let text = off > 0 ? ns.substring(from: off) : blk.text
        nextOffset = 0
        // nothing to say (empty paragraph, or a restart at its very end): the synthesiser would never call back
        // and reading would stall here, so move straight on to the next paragraph
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            nextBlock += 1
            synthesizeNext()
            return
        }
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        u.rate = Self.rate(for: speed)
        u.pitchMultiplier = Float(pitch)
        serial += 1
        let sid = serial
        segments.append(Segment(id: sid, block: nextBlock, offset: off, start: scheduledEnd, length: ns.length - off))
        synthesizing = true
        lastAudio = .now
        let gen = generation
        let rec = recorder
        let uid = ObjectIdentifier(u)
        rec.reset(uid)
        synth.write(u, toBufferCallback: { [weak self] buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            guard let at = rec.advance(by: Int64(pcm.frameLength), for: uid) else { return }
            if at == 0 || pcm.frameLength > 4096 || pcm.frameLength == 0 { vlog.log("BUF at=\(at) n=\(pcm.frameLength) sr=\(pcm.format.sampleRate) fmt=\(pcm.format.commonFormat.rawValue) main=\(Thread.isMainThread)") }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.received(pcm, at: at, gen: gen, sid: sid) } }
        }, toMarkerCallback: { ms in
            for m in ms { vlog.log("MARK \(m.mark.rawValue) off=\(m.byteSampleOffset) r=\(m.textRange.location)") }
        })
    }

    private func received(_ pcm: AVAudioPCMBuffer, at: Int64, gen: Int, sid: Int) {
        // only the paragraph being synthesised, and only until it is done (the synthesiser can report the end twice)
        guard gen == generation, speaking, let seg = segments.last, seg.id == sid, seg.end == nil else { return }
        lastAudio = .now
        if pcm.frameLength == 0 {                                   // the paragraph is done
            finishSegment()
            return
        }
        guard let out = prepare(pcm) else { return }
        // the player ran dry (synthesis slower than speech): new audio plays from now, so the timeline moves with it
        let ph = playhead
        if player.isPlaying, ph > scheduledEnd {
            let gap = ph - scheduledEnd
            segments[segments.count - 1].shift += gap
            scheduledEnd = ph
            vlog.log("UNDERRUN gap=\(gap)")
        }
        player.scheduleBuffer(out)
        scheduledEnd += AVAudioFramePosition(out.frameLength)
        if !paused, !player.isPlaying { player.play() }
    }

    /// The current paragraph is fully synthesised (or given up on): close its segment, breathe, go on.
    private func finishSegment() {
        guard let seg = segments.last, seg.end == nil else { return }
        synthesizing = false
        segments[segments.count - 1].end = scheduledEnd
        vlog.log("SEG done words=\(seg.words.count) frames=\(self.scheduledEnd - seg.start)")
        if let f = format {                                         // a short breath between paragraphs
            let n = AVAudioFrameCount(f.sampleRate * 0.22 / speed)
            if let gap = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: n) {
                gap.frameLength = n
                player.scheduleBuffer(gap)
                scheduledEnd += AVAudioFramePosition(n)
            }
        }
        nextBlock = seg.block + 1
        synthesizeNext()
    }

    private func word(_ r: NSRange, at: Int64, gen: Int) {
        guard gen == generation, !segments.isEmpty else { return }
        let i = segments.count - 1
        let seg = segments[i]
        let frame = seg.start + seg.shift + AVAudioFramePosition(Double(at) * ratio)
        segments[i].words.append((frame, NSRange(location: seg.offset + r.location, length: r.length)))
    }

    /// Connect the player with the voice's format on first use; convert if a later voice differs.
    private func prepare(_ pcm: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let src = pcm.format
        guard let wanted = src.commonFormat == .pcmFormatFloat32 && !src.isInterleaved ? src
            : AVAudioFormat(standardFormatWithSampleRate: src.sampleRate, channels: src.channelCount) else { return nil }
        if format == nil || (scheduledEnd == 0 && format != wanted) {
            if engine.isRunning { engine.stop() }
            engine.connect(player, to: engine.mainMixerNode, format: wanted)
            format = wanted
        }
        if !engine.isRunning {
            engine.prepare()
            do { try engine.start() } catch { vlog.log("ENGINE start failed: \(error)"); return nil }
        }
        guard let f = format else { return nil }
        ratio = f.sampleRate / src.sampleRate
        if src == f { return pcm }
        guard let conv = AVAudioConverter(from: src, to: f),
              let out = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: AVAudioFrameCount(Double(pcm.frameLength) * ratio) + 64)
        else { return nil }
        var fed = false
        var err: NSError?
        conv.convert(to: out, error: &err) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true; status.pointee = .haveData; return pcm
        }
        return err == nil ? out : nil
    }

    /// Frames played since the player started (stands still while paused).
    private var playhead: AVAudioFramePosition {
        guard let nt = player.lastRenderTime, nt.isSampleTimeValid,
              let pt = player.playerTime(forNodeTime: nt) else { return 0 }
        return max(0, pt.sampleTime)
    }

    /// 25 times a second: put the cursor on the word being heard, turn to the next paragraph, keep synthesis ahead.
    private func tick() {
        guard speaking else { return }
        // the synthesiser went quiet mid-paragraph (it sometimes never sends the final empty buffer): don't hang, go on
        if synthesizing, Date.now.timeIntervalSince(lastAudio) > 6 {
            vlog.log("STALL block=\(self.nextBlock) — skipping on")
            recorder.reset(nil)
            if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
            finishSegment()
        }
        synthesizeNext()
        if !synthesizing, nextBlock >= queue.count, scheduledEnd == 0 { stop(); return }   // nothing left that has words
        guard !paused, player.isPlaying else { return }
        // what is heard lags what is rendered by the output's latency (a few ms on the speaker, ~0.2 s on Bluetooth)
        let pos = playhead - latencyFrames
        guard let si = segments.lastIndex(where: { $0.start <= pos }) else { return }
        let seg = segments[si]
        guard let blk = queue[safe: seg.block] else { return }
        if index != seg.block { index = seg.block; nowPlaying() }
        let w = wordAt(pos, in: seg, text: blk.text) ?? NSRange(location: seg.offset, length: 0)
        if live?.range != w {
            let ns = blk.text as NSString
            let word = w.length > 0 && NSMaxRange(w) <= ns.length ? ns.substring(with: w) : "-"
            vlog.log("TICK pos=\(pos) lat=\(latencyFrames) end=\(scheduledEnd) blk=\(seg.block) w=\(w.location) \(word) voice=\(voiceID) x=\(speed)")
        }
        if live?.ch != blk.ch || live?.b != blk.b || live?.range != w { live = (blk.ch, blk.b, w) }
        // the end of the book
        if !synthesizing, nextBlock >= queue.count, pos >= scheduledEnd { stop() }
    }

    private var latencyFrames: AVAudioFramePosition {
        var secs = engine.outputNode.presentationLatency
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        secs = max(secs, session.outputLatency + session.ioBufferDuration)
        #endif
        return AVAudioFramePosition(secs * (format?.sampleRate ?? 22050))
    }

    /// The word under the play head. Words whose stamps coincide (a voice that hands over audio in large chunks) are
    /// spread over their chunk by character position; a voice that reports no words at all is followed by proportion.
    private func wordAt(_ pos: AVAudioFramePosition, in seg: Segment, text: String) -> NSRange? {
        let ws = seg.words
        let tail = seg.offset + seg.length
        if ws.isEmpty {
            guard let end = seg.end, end > seg.start else { return nil }
            let c = seg.offset + Int(Double(pos - seg.start) / Double(end - seg.start) * Double(seg.length))
            return wordRange(text, around: min(max(c, seg.offset), tail - 1))
        }
        guard let k = ws.lastIndex(where: { $0.at <= pos }) else { return nil }
        var a = k, b = k
        while a > 0, ws[a - 1].at == ws[k].at { a -= 1 }
        while b + 1 < ws.count, ws[b + 1].at == ws[k].at { b += 1 }
        if a == b { return ws[k].range }
        let t0 = ws[a].at
        let t1 = b + 1 < ws.count ? ws[b + 1].at : (seg.end ?? t0)
        guard t1 > t0 else { return ws[a].range }
        let c0 = ws[a].range.location
        let c1 = b + 1 < ws.count ? ws[b + 1].range.location : tail
        let c = c0 + Int(Double(pos - t0) / Double(t1 - t0) * Double(c1 - c0))
        return ws[a...b].last(where: { $0.range.location <= c })?.range ?? ws[a].range
    }

    private func wordRange(_ t: String, around i: Int) -> NSRange {
        let ns = t as NSString
        guard ns.length > 0 else { return NSRange(location: 0, length: 0) }
        func space(_ j: Int) -> Bool { let c = ns.character(at: j); return c == 32 || c == 10 || c == 160 }
        var a = min(max(i, 0), ns.length - 1), z = a
        while a > 0, !space(a - 1) { a -= 1 }
        while z < ns.length, !space(z) { z += 1 }
        return NSRange(location: a, length: z - a)
    }

    /// The sentence around what is being heard now (block address + UTF-16 range in the block's text).
    func currentSentence() -> (ch: Int, b: Int, s: Int, e: Int, quote: String)? {
        guard let l = live, let blk = queue.first(where: { $0.ch == l.ch && $0.b == l.b }) else { return nil }
        let ns = blk.text as NSString
        let a = sentenceStart(blk.text, before: max(l.range.location, 0) + 1)
        var z = max(a, l.range.location)
        while z < ns.length {
            let c = ns.character(at: z); z += 1
            if c == 46 || c == 33 || c == 63 || c == 8230 { break }
        }
        let q = ns.substring(with: NSRange(location: a, length: z - a)).trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? nil : (l.ch, l.b, a, z, q)
    }

    // MARK: lock screen

    #if os(iOS)
    private func remote() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.resume() }; return .success }
        c.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        c.stopCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.skip(1) }; return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.skip(-1) }; return .success }
        c.changePlaybackPositionCommand.isEnabled = false
        // a call or Siri interrupts: pause, and continue when the system says so
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let opts = n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            MainActor.assumeIsolated {
                if raw == AVAudioSession.InterruptionType.began.rawValue { self?.pause() }
                else if AVAudioSession.InterruptionOptions(rawValue: opts).contains(.shouldResume) { self?.resume() }
            }
        }
        // a new output (Bluetooth connects, sample rate changes) stops the engine: continue from the sentence being heard
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.engineChanged() }
        }
        // the media server restarted: every audio object is invalid, start again cleanly
        NotificationCenter.default.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.engineChanged() }
        }
        // headphones unplugged: pause like a music player
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] n in
            let r = n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if r == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { MainActor.assumeIsolated { self?.pause() } }
        }
    }
    #endif

    private func engineChanged() {
        guard speaking else { return }
        vlog.log("ENGINE configuration changed paused=\(self.paused)")
        format = nil                                                // reconnect with the new output on the next buffer
        if paused { return }                                        // resume() restarts a stopped engine
        let blk = queue[safe: index]?.text ?? ""
        restart(at: index, offset: sentenceStart(blk, before: live?.range.location ?? 0))
    }

    private func nowPlaying() {
        #if os(iOS)
        guard speaking else { return }
        // time on the lock screen is estimated from characters (≈ 14 a second at 1×)
        let cps = 14.0 * speed
        let total = queue.reduce(0) { $0 + $1.text.utf16.count }
        let done = queue.prefix(index).reduce(0) { $0 + $1.text.utf16.count } + (live?.range.location ?? 0)
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: "Teoria · \(Self.speedName(speed))",
            MPNowPlayingInfoPropertyPlaybackRate: paused ? 0.0 : 1.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPMediaItemPropertyPlaybackDuration: Double(total) / cps,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: Double(done) / cps,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let art = artwork { info[MPMediaItemPropertyArtwork] = art }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #endif
    }
}

extension ReaderVoice: AVSpeechSynthesizerDelegate {
    /// While a paragraph is being written into buffers, the word callbacks arrive between the buffers: the frame count
    /// at that moment is where the word begins in the audio.
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, willSpeakRangeOfSpeechString r: NSRange, utterance u: AVSpeechUtterance) {
        guard let at = recorder.position(of: ObjectIdentifier(u)) else { return }
        vlog.log("WORD r=\(r.location) at=\(at) main=\(Thread.isMainThread)")
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.word(r, at: at, gen: self.generation) }
        }
    }
}

/// Frame counter shared by the buffer callback and the word callback, whichever thread they arrive on.
private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var frames: Int64 = 0
    private var current: ObjectIdentifier?

    func reset(_ id: ObjectIdentifier?) { lock.lock(); frames = 0; current = id; lock.unlock() }
    func advance(by n: Int64, for id: ObjectIdentifier) -> Int64? {
        lock.lock(); defer { lock.unlock() }
        guard id == current else { return nil }
        let at = frames; frames += n; return at
    }
    func position(of id: ObjectIdentifier) -> Int64? { lock.lock(); defer { lock.unlock() }; return id == current ? frames : nil }
}
