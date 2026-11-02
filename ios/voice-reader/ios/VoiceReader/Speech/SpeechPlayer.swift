// Reads a document aloud. Built on Teoria's ReaderVoice: each paragraph is synthesised into audio buffers and played by
// our own AVAudioEngine, so Voice Reader is a real "Now Playing" app (lock screen, Control Center, headphone buttons) and the
// highlighted word follows the audio that is actually coming out, including Bluetooth latency.
//
// Positions are UTF-16 offsets in the document's plain text (one paragraph per line).
import Foundation
import AVFoundation
import MediaPlayer
import UIKit
import Observation
import NaturalLanguage
import os
import Accelerate

enum SleepTimer: Equatable, Sendable {
    case off
    case minutes(Int)
    case endOfChapter
}

@MainActor
@Observable
final class SpeechPlayer: NSObject {
    nonisolated static let log = Logger(subsystem: "voice-reader", category: "player")
    // what is being read
    private(set) var documentID: UUID?
    private(set) var title = ""
    private(set) var author: String?
    private(set) var isSpeaking = false              // a reading session exists (playing or paused)
    private(set) var isPaused = false
    var isPlaying: Bool { isSpeaking && !isPaused }

    /// Where reading continues from; follows the spoken word while playing.
    private(set) var cursor = 0
    /// The word and the sentence being heard (document offsets), for the reader's highlight.
    private(set) var spokenWord: NSRange? { didSet { if oldValue != spokenWord { onSpokenChange?() } } }
    private(set) var spokenSentence: NSRange? {
        didSet {
            guard oldValue != spokenSentence else { return }
            if let n = spokenSentence, n != heardSentence { previousSentence = heardSentence; heardSentence = n; sentenceSince = .now }
            onSpokenChange?()
        }
    }
    /// The sentence heard before the current one and when the current one began: a mark pressed in the first
    /// seconds of a sentence was meant for the one that just ended (Yolda, the headphone's ⏭).
    @ObservationIgnored private(set) var previousSentence: NSRange?
    @ObservationIgnored private(set) var sentenceSince = Date.distantPast
    @ObservationIgnored private var heardSentence: NSRange?
    /// Called (on the main actor, possibly twice for one step) when the spoken word or sentence changes. The page listens
    /// here instead of through SwiftUI so that a word change repaints the highlight without re-evaluating any view.
    @ObservationIgnored var onSpokenChange: (() -> Void)?

    /// Music break: after `breakEvery` seconds of listening the voice finishes the sentence it is in, goes quiet in the
    /// pause after it, the music comes up (iOS's ducking is lifted) for `breakLength` seconds, then the music goes down
    /// and the voice comes back slowly from the next sentence. 0 = off.
    var breakEvery: Double = 0 { didSet { if breakEvery == 0 { breakDue = false; breakBoundary = nil } } }
    var breakLength: Double = 30
    private(set) var breakEnds: Date?
    /// What the quiet time is: the timed music break, or a wait the reader asked for (Aktif bekleme).
    enum BreakKind: Equatable { case music, hold, untilMusicStops }
    private(set) var breakKind: BreakKind = .music
    /// Headphone ⏯ / lock-screen pause while reading starts an active wait instead of a plain pause.
    @ObservationIgnored var remotePauseWaits = false
    @ObservationIgnored var remotePauseSeconds: Double? = 120     // nil: until the music stops
    @ObservationIgnored private var listened: Double = 0
    @ObservationIgnored private var breakDue = false
    @ObservationIgnored private var breakTask: Task<Void, Never>?
    /// Where the break starts: the frame at which the next sentence's first word is heard, and that sentence's offset.
    @ObservationIgnored private var breakBoundary: (frame: AVAudioFramePosition, at: Int)?

    /// Automation: after `segmentLimit` seconds of listening the voice finishes its sentence and goes quiet, as before
    /// a music break, but instead of coming back it calls `onSegmentEnd`. The engine keeps running on silence and the
    /// session is kept, so the next step can start with the phone locked. 0 = off.
    private(set) var segmentLimit: Double = 0
    @ObservationIgnored private(set) var segmentListened: Double = 0
    @ObservationIgnored private var segmentDue = false
    @ObservationIgnored var onSegmentEnd: (() -> Void)?
    /// Automation: the end of a document (or a handover to the next one) keeps the session and the engine.
    @ObservationIgnored var keepSessionAtEnd = false

    // fades: the voice's level is `baseVolume` (the loudness setting) × `fade`; a break fades out and back in
    @ObservationIgnored private var baseVolume: Float = 1
    @ObservationIgnored private var fade: Float = 1 { didSet { engine.mainMixerNode.outputVolume = baseVolume * fade } }
    @ObservationIgnored private var fadeTimer: Timer?
    @ObservationIgnored private var fadeInPending = false
    static let fadeOutSeconds = 0.22                   // in the pause after the sentence: no word is cut
    static let fadeInSeconds = 2.0
    static let duckSettleSeconds = 0.8                 // music goes down before the voice starts to come up

    /// Headphone / lock screen ⏭ ⏮ (the FiiO's buttons): the reader can take them (bicycle mode). Return true when taken.
    @ObservationIgnored var remoteSkip: ((_ forward: Bool) -> Bool)?
    /// Headphone keys while the app waits for a choice (automation: the next book is finished): −1 ⏮, 0 ⏯, 1 ⏭.
    /// Return true when taken.
    @ObservationIgnored var remoteChoice: ((_ key: Int) -> Bool)?
    /// Asked before reading starts or the reading place moves (`offset`: where it would go). False: nothing happens.
    /// A finished book stays at its end this way until the reader starts it again.
    @ObservationIgnored var mayMove: ((_ id: UUID, _ offset: Int) -> Bool)?

    private(set) var sleepTimer: SleepTimer = .off
    private(set) var sleepEnds: Date?

    // voice settings for the open document (AppModel sets them)
    var voiceID: String = "" { didSet { if oldValue != voiceID { applyBoost(); restartSoon() } } }
    var speed: Double = 1.0 { didSet { if oldValue != speed { restartSoon(); nowPlaying() } } }
    var pitch: Double = 1.0 { didSet { if oldValue != pitch { restartSoon() } } }
    /// Pitch and volume per system voice, as Voice Dream keeps them (Kalınlık 50…200 → 0.5…2.0, Ses Miktarı 0…100).
    var voiceTune: [String: VoiceTune] = [:] { didSet { if oldValue != voiceTune { restartSoon() } } }
    private func tune(_ vid: String) -> VoiceTune { voiceTune[vid] ?? VoiceTune(pitch: pitch, volume: 1) }
    var options = SpokenText.Options() { didSet { if oldValue != options { restartSoon() } } }
    var startAtSentence = true
    /// The document's language ("tr", "en"), the voice for sentences in the other of the two, and whether to switch.
    var baseLanguage = "tr"
    var otherVoiceID = "" { didSet { if oldValue != otherVoiceID { restartSoon() } } }
    var mixedLanguage = true { didSet { if oldValue != mixedLanguage { restartSoon() } } }
    /// dB of extra loudness: a compressor raises the quiet parts, a limiter holds the peaks (no clipping).
    var volumeBoost: Double = 0 { didSet { if oldValue != volumeBoost { applyBoost(); boostChanged() } } }
    /// System voices through VoiceMaster: Voice Dream's tone, needles taken out, 2 dB over Voice Dream, never clipped.
    /// Off = played exactly
    /// as the synthesiser makes it, as in Voice Dream.
    var clearVoice = true { didSet { if oldValue != clearVoice { applyBoost(); restartSoon() } } }
    /// Turkish system voices take speed, pitch and equalizer from the phone's Spoken Content settings
    /// (prefersAssistiveTechnologySettings). Measured on iOS 27.0.1, 2026-10-26: Yelda at 156 Hz with a 4.2-semitone
    /// melody and the old Yelda's colour (bands within 1 dB), the depth Voice Dream had; the app's rate is ignored.
    var systemSpeech = true { didSet { if oldValue != systemSpeech { applyBoost(); calibrateAssistive(); restartSoon() } } }
    /// VoiceMaster's level for the system voice: always on with the phone's settings (iOS gives Yelda at −16.4 dBFS,
    /// as raw; "çok zayıf" next to Voice Dream), else only with Net ve gür ses.
    private var masters: Bool { clearVoice || systemSpeech }
    /// Gain that brings a voice read with the phone's settings back to the plain voice's level (see assistiveGain).
    @ObservationIgnored private var assistiveGain = UserDefaults.standard.object(forKey: "a.assistiveGain") as? Float ?? 1
    @ObservationIgnored private var liveGain: Float = 1

    /// Measure assistiveGain again (≈ 0.3 s, off the main thread); the next buffers use it.
    func calibrateAssistive() {
        guard systemSpeech else { return }
        let id = Voices.voice(voiceID)?.language.hasPrefix("tr") == true ? voiceID
            : AVSpeechSynthesisVoice(language: "tr-TR")?.identifier ?? voiceID
        ProfileRenderer.shared.queue.async { [weak self] in
            guard let g = ProfileRenderer.shared.assistiveGain(voiceID: id) else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.assistiveGain = g
                    UserDefaults.standard.set(g, forKey: "a.assistiveGain")
                    Self.log.info("assistive gain \(20 * log10(g), privacy: .public) dB")
                }
            }
        }
    }
    private func assistive(_ language: String?) -> Bool { systemSpeech && Voices.base(language ?? baseLanguage) == "tr" }
    /// With music from another app (Spotify…): off stops it and owns the lock screen; otherwise it plays under us.
    var musicMix: MusicMix = .off { didSet { if oldValue != musicMix { applyBoost(); boostChanged(); if isPlaying { activateSession() } } } }
    /// Amount of background music, 0…100. No app may set Spotify's own volume, so this sets the ratio from our side:
    /// the voice's level against the music, and at the low end iOS's ducking of the music as well.
    var musicLevel: Double = 40 {
        didSet {
            guard oldValue != musicLevel else { return }
            let duckChanged = (oldValue <= Self.duckBelow) != (musicLevel <= Self.duckBelow)
            applyBoost()
            boostChanged()
            if duckChanged, isPlaying { activateSession() }
        }
    }
    nonisolated static let duckBelow = 30.0

    /// The voice's offset in dB for a music level: 0 → +14 dB over ducked music (the music a faint bed you only just
    /// hear once the phone is turned down to a normal reading level), 30 → 0 dB over ducked music, then without
    /// ducking 0 dB down to −18 dB at 100 (the music clearly in front). Above 12 dB the compressor and limiter hold
    /// the peaks, so the voice gets denser, not distorted.
    nonisolated static func balanceDB(_ level: Double) -> Double {
        level <= duckBelow ? (duckBelow - level) / duckBelow * 14 : -(level - duckBelow) / (100 - duckBelow) * 18
    }
    private var ducking: Bool { musicMix != .off && musicLevel <= Self.duckBelow }
    /// The open document's Mac-rendered audio (Anlatıcı voice), if it has one; AppModel sets it on opening.
    @ObservationIgnored var studio: StudioPack? { didSet { if voiceID == VoiceProfile.studio.id { restartSoon() } } }
    /// Extra semitones per Voice Reader voice (negative = deeper).
    var voiceDepth: [String: Double] = [:] { didSet { if oldValue != voiceDepth { restartSoon() } } }

    // supplied by AppModel
    @ObservationIgnored var onPosition: ((UUID, Int) -> Void)?
    @ObservationIgnored var onFinished: ((UUID) -> Void)?
    @ObservationIgnored var marks: (NavigationUnit) -> [Int] = { _ in [] }
    @ObservationIgnored var artwork: MPMediaItemArtwork?

    // the document
    @ObservationIgnored private var text: NSString = ""
    @ObservationIgnored private(set) var blocks: [NSRange] = []          // paragraphs (without their newline)
    @ObservationIgnored private(set) var chapters: [Chapter] = []
    @ObservationIgnored private(set) var pages: [Int] = []

    // audio
    @ObservationIgnored private let synth = AVSpeechSynthesizer()
    @ObservationIgnored private let preview = AVSpeechSynthesizer()
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let player = AVAudioPlayerNode()
    @ObservationIgnored private let master = VoiceMaster()
    @ObservationIgnored private var mastering = false              // the live utterance being written goes through it
    @ObservationIgnored private let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter,
        componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
    @ObservationIgnored private var format: AVAudioFormat?
    @ObservationIgnored private var converter: AVAudioConverter?
    @ObservationIgnored private var convertFresh = false
    @ObservationIgnored nonisolated private let recorder = FrameRecorder()

    private struct Segment {
        let id: Int
        let block: Int
        let offset: Int                                 // start inside the paragraph (UTF-16)
        let start: AVAudioFramePosition
        let length: Int                                 // original characters covered
        let spoken: SpokenText
        var end: AVAudioFramePosition?
        var shift: AVAudioFramePosition = 0
        var words: [(at: AVAudioFramePosition, range: NSRange)] = []   // ranges in the paragraph
    }
    @ObservationIgnored private var segments: [Segment] = []
    @ObservationIgnored private let recognizer = NLLanguageRecognizer()
    @ObservationIgnored private var index = 0
    @ObservationIgnored private var scheduledEnd: AVAudioFramePosition = 0
    @ObservationIgnored private var synthesizing = false
    @ObservationIgnored private var liveSynthesis = false             // a system voice is being written right now
    @ObservationIgnored private var liveUtterance: ObjectIdentifier?
    @ObservationIgnored private var cancelToken = CancelToken()
    @ObservationIgnored private var nextBlock = 0
    @ObservationIgnored private var nextOffset = 0
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var serial = 0
    @ObservationIgnored private var ratio = 1.0
    @ObservationIgnored private var lastAudio = Date.distantPast
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var restartTask: Task<Void, Never>?
    @ObservationIgnored private var lastReported = Date.distantPast
    @ObservationIgnored private var sleepChapterEnd: Int?

    // measured reading pace (characters per second at 1×), for remaining-time estimates
    @ObservationIgnored private var paceMark: (date: Date, cursor: Int)?
    private(set) var charsPerSecond: Double = UserDefaults.standard.object(forKey: "a.cps") as? Double ?? 14

    override init() {
        super.init()
        synth.delegate = self
        engine.attach(player)
        engine.attach(limiter)
        applyBoost()
        configureRemote()
    }

    // MARK: loudness

    /// The voice's loudness offset in dB: the boost setting plus, with music, the voice-to-music balance.
    private var totalBoost: Double { volumeBoost + (musicMix == .off ? 0 : Self.balanceDB(musicLevel)) }
    /// Voice Reader's own voices (Ema, Supertonic, Apple-based profiles, Anlatıcı) take the boost when each piece is
    /// rendered, with a look-ahead compressor (Level.apply): as plain gain into the fast live limiter it clipped (24 %
    /// of samples cut by over 3 dB at +14 dB), the crackle at high speed and with the music slider at 0.
    private var rendersOwnVoice: Bool { VoiceProfile.with(id: voiceID) != nil || isCloud }
    private var isCloud: Bool { voiceID == ElevenLabs.readerVoiceID || voiceID == CloudVoice.readerVoiceID }
    var renderBoost: Double { rendersOwnVoice ? max(0, totalBoost) : 0 }
    private func boostChanged() { if rendersOwnVoice { restartSoon() } }

    /// System voices take their loudness from VoiceMaster (2026-10-24). Apple's dynamics processor, which gave them
    /// the boost before, made Yelda 2 dB quieter at +14 dB (music slider at 0), not louder: −20 LUFS against Voice
    /// Dream's −18 (measured on the Mac with the same units). With the music in the background and the voice in front
    /// VoiceMaster adds up to 2 dB more; anything that turns the voice down is plain attenuation at the mixer.
    private func applyBoost() {
        // with the phone's settings +4 dB (measured 2026-10-26 on iOS 27's Yelda: −16.3 → −11.5 dBFS while speaking,
        // 2 dB over iOS's own Spoken Content, peaks −1 dBFS, tone within ±1.2 dB; +6 moved the top 2 dB, +8 gave 0.4 more)
        // Net ve gür ses the same +4 since the user found +2 still under Voice Dream (2026-10-26)
        master.boost = rendersOwnVoice ? 0 : masters ? 4 : 0
        baseVolume = Float(pow(10, min(0, totalBoost) / 20))
        engine.mainMixerNode.outputVolume = baseVolume * fade
        let l = limiter.audioUnit
        AudioUnitSetParameter(l, kLimiterParam_AttackTime, kAudioUnitScope_Global, 0, 0.002, 0)
        AudioUnitSetParameter(l, kLimiterParam_DecayTime, kAudioUnitScope_Global, 0, 0.06, 0)
        AudioUnitSetParameter(l, kLimiterParam_PreGain, kAudioUnitScope_Global, 0, -1, 0)
        // a system voice has its own look-ahead limiter in VoiceMaster, or plays as the synthesiser made it
        limiter.bypass = !rendersOwnVoice
    }


    // MARK: speed

    static let speedRange: ClosedRange<Double> = 0.5...3.6

    /// Words a minute at 1× for the Turkish system voices, as Voice Dream counts them: Yelda at rate 0.5 reads 14.0
    /// characters a second, and Voice Dream's 330 words a minute came out at 39.4 characters a second (≈ 7 a word).
    nonisolated static let wordsAtOneX = 120.0
    nonisolated static func wpm(_ m: Double) -> Int { Int((m * wordsAtOneX).rounded()) }

    /// The Turkish system voices (Yelda, Cem) do not change speed smoothly: the engine has fixed steps and every rate
    /// inside a step sounds the same. Measured on the Mac with Yelda and Cem (same engine, same steps, 2026-10-21):
    /// the middle of each step → its speed as a multiple of rate 0.5. Voice Dream's 330 falls on the 0.79–0.83 step.
    /// A speed is played with the step nearest to it, from the middle of the step, so a small difference between the
    /// phone and the Mac never drops it into the step next to it.
    nonisolated private static let steps: [(rate: Double, mult: Double)] = [
        (0.04, 0.59), (0.075, 0.63), (0.11, 0.67), (0.175, 0.71), (0.25, 0.77), (0.325, 0.83), (0.41, 0.91),
        (0.49, 1.00), (0.51, 1.04), (0.52, 1.08), (0.53, 1.18), (0.54, 1.23), (0.55, 1.29), (0.56, 1.36),
        (0.575, 1.43), (0.59, 1.50), (0.605, 1.59), (0.625, 1.71), (0.645, 1.83), (0.665, 1.96), (0.69, 2.11),
        (0.72, 2.28), (0.76, 2.49), (0.81, 2.80), (0.86, 3.12), (0.93, 3.52), (0.99, 4.03),
    ]
    nonisolated static func rate(for m: Double) -> Float {
        let m = max(m, 0.1)
        let best = steps.min { abs(Foundation.log($0.mult / m)) < abs(Foundation.log($1.mult / m)) }!
        return Float(best.rate)
    }
    /// The speed actually heard from a system voice at a setting (the step it falls on).
    nonisolated static func heard(_ m: Double) -> Double { steps.first { Float($0.rate) == rate(for: m) }?.mult ?? m }
    static func speedName(_ m: Double) -> String {
        var t = String(format: "%.2f", m)
        while t.hasSuffix("0") { t.removeLast() }
        if t.hasSuffix(".") { t.removeLast() }
        return t.replacingOccurrences(of: ".", with: ",") + "×"
    }
    /// Words per minute at a speed, from the measured pace (≈ 6 characters a word including the space).
    func wordsPerMinute(_ m: Double) -> Int { Int((charsPerSecond * m * 60 / 6.2).rounded()) }

    // MARK: loading

    func load(id: UUID, title: String, author: String?, content: DocumentContent, at position: Int, handover: Bool = false) {
        if documentID == id { return }
        stop(release: !handover)
        documentID = id
        self.title = title
        self.author = author
        text = content.text as NSString
        chapters = content.chapters
        pages = content.pages
        var b: [NSRange] = []
        var start = 0
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: [.byParagraphs, .substringNotRequired]) { _, r, _, _ in
            if r.length > 0 { b.append(r) }
            start = r.location
        }
        _ = start
        blocks = b
        cursor = min(max(0, position), text.length)
        spokenWord = nil
        spokenSentence = nil
    }

    /// The open document grew at its end (pages appended by sync): take the longer text without interrupting.
    func extend(_ content: DocumentContent) {
        guard (content.text as NSString).length > text.length else { return }
        text = content.text as NSString
        chapters = content.chapters
        var b: [NSRange] = []
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: [.byParagraphs, .substringNotRequired]) { _, r, _, _ in
            if r.length > 0 { b.append(r) }
        }
        blocks = b
        nowPlaying()
    }

    func unload() {
        stop()
        documentID = nil
        text = ""
        blocks = []
        chapters = []
        pages = []
        cursor = 0
    }

    var length: Int { text.length }

    // MARK: control

    func play() { play(from: cursor) }

    func play(from offset: Int, snap: Bool = true) {
        guard let id = documentID, !blocks.isEmpty, mayMove?(id, offset) != false else { return }
        var at = min(max(0, offset), max(0, text.length - 1))
        if snap, startAtSentence { at = sentenceStart(before: at + 1) }
        let bi = blockIndex(containing: at)
        let local = max(0, at - blocks[bi].location)
        // a jump during a break ends it; only the break's own return fades the voice in
        if breakEnds != nil { breakTask?.cancel(); breakTask = nil; breakEnds = nil }
        calibrateAssistive()
        breakBoundary = nil
        setFade(fadeInPending ? 0 : 1)
        activateSession()
        isSpeaking = true
        isPaused = false
        paceMark = nil
        restart(at: bi, offset: local)
        startTicker()
    }

    private func startTicker() {
        guard ticker == nil else { return }
        let t = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = 0.01
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    func toggle() {
        if !isSpeaking { play() } else if isPaused { resume() } else { pause() }
    }

    /// Pausing stops the engine and the 25-a-second ticker (nothing runs while paused) and, when music plays with us,
    /// lets the session go with notifyOthers: iOS lifts its ducking at once, so Spotify comes up the moment the button
    /// is pressed. Queued audio stays in the player and resumes where it stopped.
    func pause() {
        guard isSpeaking, !isPaused else { return }
        player.pause()
        engine.pause()
        breakBoundary = nil
        fadeInPending = false
        setFade(1)
        isPaused = true
        paceMark = nil
        ticker?.invalidate(); ticker = nil
        report(force: true)
        nowPlaying()
        if musicMix != .off {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    /// Müzik modu: while nothing is read, the session is let go so the other app's music comes to the front at full
    /// level (and starts again if our session had stopped it).
    func releaseToMusic() {
        guard !isPlaying else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func resume() {
        guard isSpeaking, isPaused else { return }
        if breakEnds != nil { endBreak(); return }
        activateSession()
        isPaused = false
        if format != nil, scheduledEnd > 0, (try? engine.start()) != nil {
            player.play()
            startTicker()
        } else {
            play(from: cursor)
        }
        nowPlaying()
    }

    /// `release: false` (automation, between two documents): the engine keeps running and the session stays active,
    /// so iOS keeps the app alive in the background until the next document starts.
    func stop(release: Bool = true) {
        restartTask?.cancel()
        breakTask?.cancel(); breakTask = nil; breakEnds = nil; breakDue = false; segmentDue = false
        cancelToken.cancelled = true
        cancelToken = CancelToken()
        ticker?.invalidate(); ticker = nil
        breakBoundary = nil
        fadeInPending = false
        setFade(1)
        generation += 1
        recorder.reset(nil)
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        player.stop()
        if release { engine.stop() }
        segments = []; scheduledEnd = 0; synthesizing = false; master.reset()
        if isSpeaking { report(force: true) }
        isSpeaking = false; isPaused = false
        spokenWord = nil; spokenSentence = nil
        setSleepTimer(.off)
        guard release else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Move the cursor without speaking (a tap on the page while paused, a jump from the table of contents).
    func moveCursor(to offset: Int, play playing: Bool? = nil) {
        let at = min(max(0, offset), text.length)
        if let id = documentID, at != cursor || playing == true, mayMove?(id, at) == false { return }
        if playing ?? isPlaying {
            play(from: at, snap: false)
        } else {
            if isSpeaking { stopAudioKeepingSession() }
            cursor = at
            let w = wordRange(around: at)
            spokenWord = w.length > 0 ? w : nil
            spokenSentence = sentenceRange(around: at)
            report(force: true)
            nowPlaying()
        }
    }

    /// Paused + jumped: drop the queued audio so "play" starts from the new place.
    private func stopAudioKeepingSession() {
        generation += 1
        cancelToken.cancelled = true
        cancelToken = CancelToken()
        recorder.reset(nil)
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        player.stop()
        segments = []; scheduledEnd = 0; synthesizing = false; master.reset()
    }

    func skip(forward: Bool, unit: NavigationUnit) {
        guard documentID != nil else { return }
        let target = target(from: cursor, forward: forward, unit: unit)
        guard let target else { return }
        moveCursor(to: target)
    }

    func previewVoice(_ v: AVSpeechSynthesisVoice) {
        preview.stopSpeaking(at: .immediate)
        let sample = v.language.hasPrefix("tr") ? "Merhaba, ben \(v.name). Bu sesle okuyabilirim." : "Hello, I am \(v.name). I can read your documents."
        let u = AVSpeechUtterance(string: sample)
        u.voice = v
        u.rate = Self.rate(for: speed)
        u.pitchMultiplier = Float(tune(v.identifier).pitch)
        u.volume = Float(tune(v.identifier).volume)
        u.prefersAssistiveTechnologySettings = assistive(v.language)
        preview.speak(u)
    }

    func setSleepTimer(_ t: SleepTimer) {
        sleepTimer = t
        switch t {
        case .off: sleepEnds = nil; sleepChapterEnd = nil
        case .minutes(let m): sleepEnds = Date.now.addingTimeInterval(Double(m) * 60); sleepChapterEnd = nil
        case .endOfChapter:
            sleepEnds = nil
            sleepChapterEnd = chapters.map(\.offset).filter { $0 > cursor }.min() ?? text.length
        }
    }

    // MARK: navigation targets

    private func target(from at: Int, forward: Bool, unit: NavigationUnit) -> Int? {
        switch unit {
        case .sentence:
            if forward { return sentenceEnd(after: at) }
            let here = sentenceStart(before: at + 1)
            return at - here > 3 ? here : sentenceStart(before: max(0, here - 1))
        case .paragraph:
            let bi = blockIndex(containing: at)
            if forward { return bi + 1 < blocks.count ? blocks[bi + 1].location : nil }
            return at - blocks[bi].location > 3 ? blocks[bi].location : blocks[max(0, bi - 1)].location
        case .page:
            return step(in: pages.isEmpty ? blocks.map(\.location) : pages, from: at, forward: forward)
        case .chapter:
            return step(in: chapters.map(\.offset), from: at, forward: forward) ?? (forward ? nil : 0)
        case .bookmark, .highlight:
            return step(in: marks(unit).sorted(), from: at, forward: forward)
        case .seconds15, .seconds30:
            let secs = unit == .seconds15 ? 15.0 : 30.0
            let d = Int(charsPerSecond * speed * secs)
            let t = forward ? min(text.length - 1, at + d) : max(0, at - d)
            return wordRange(around: t).location
        }
    }

    private func step(in list: [Int], from at: Int, forward: Bool) -> Int? {
        if forward { return list.first { $0 > at + 1 } }
        return list.last { $0 < at - 3 }
    }

    // MARK: text helpers

    func blockIndex(containing at: Int) -> Int {
        guard !blocks.isEmpty else { return 0 }
        var lo = 0, hi = blocks.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if blocks[mid].location <= at { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    private static let enders: Set<unichar> = [46, 33, 63, 8230, 10]   // . ! ? … newline

    /// Whether the character at `k` closes a sentence. A full stop does not when a letter or digit follows directly
    /// ("3.5", "vb.ler") or when it closes a bare number ("1. Bölüm", "12. yüzyıl").
    private func endsSentence(at k: Int) -> Bool {
        guard k >= 0, k < text.length else { return false }
        let c = text.character(at: k)
        guard Self.enders.contains(c) else { return false }
        guard c == 46 else { return true }
        if k + 1 < text.length, let n = UnicodeScalar(text.character(at: k + 1)), CharacterSet.alphanumerics.contains(n) { return false }
        var b = k - 1
        var digits = 0
        while b >= 0, let u = UnicodeScalar(text.character(at: b)), CharacterSet.decimalDigits.contains(u) { digits += 1; b -= 1 }
        if digits > 0, digits <= 3, b < 0 || text.character(at: b) == 32 || text.character(at: b) == 10 { return false }
        return true
    }

    func sentenceStart(before i: Int) -> Int {
        var j = min(max(i, 0), text.length)
        let floor = blocks.isEmpty ? 0 : blocks[blockIndex(containing: max(0, j - 1))].location
        while j > floor {
            if endsSentence(at: j - 1) { break }
            j -= 1
        }
        while j < text.length, text.character(at: j) == 32 { j += 1 }
        return j
    }

    func sentenceEnd(after i: Int) -> Int? {
        var j = min(max(i, 0), text.length)
        while j < text.length {
            let k = j; j += 1
            if endsSentence(at: k) {
                while j < text.length, text.character(at: j) == 32 || text.character(at: j) == 10 { j += 1 }
                return j < text.length ? j : nil
            }
        }
        return nil
    }

    func sentenceRange(around i: Int) -> NSRange? {
        guard text.length > 0 else { return nil }
        let a = sentenceStart(before: min(i + 1, text.length))
        var z = a
        while z < text.length {
            let k = z; z += 1
            if endsSentence(at: k) { break }
        }
        while z > a, text.character(at: z - 1) == 10 || text.character(at: z - 1) == 32 { z -= 1 }
        return z > a ? NSRange(location: a, length: z - a) : nil
    }

    /// The sentence that ends before offset `i` (a sentence start): skips the spaces and line breaks between them.
    func sentence(before i: Int) -> NSRange? {
        var k = min(i, text.length) - 1
        while k > 0, [32, 10, 160].contains(text.character(at: k)) { k -= 1 }
        guard k > 0, let r = sentenceRange(around: k - 1), r.location < i else { return nil }
        return r
    }

    func wordRange(around i: Int) -> NSRange {
        guard text.length > 0 else { return NSRange(location: 0, length: 0) }
        func space(_ j: Int) -> Bool { let c = text.character(at: j); return c == 32 || c == 10 || c == 160 }
        var a = min(max(i, 0), text.length - 1), z = a
        while a > 0, !space(a - 1) { a -= 1 }
        while z < text.length, !space(z) { z += 1 }
        return NSRange(location: a, length: z - a)
    }

    func excerpt(at i: Int, length: Int = 80) -> String {
        guard let s = sentenceRange(around: i) else { return "" }
        let t = text.substring(with: s)
        return t.count > length ? String(t.prefix(length)) + "…" : t
    }

    func excerptWord(_ r: NSRange) -> String { NSMaxRange(r) <= text.length ? text.substring(with: r) : "?" }

    func chapterTitle(at i: Int) -> String? { chapters.last { $0.offset <= i }?.title }

    // MARK: timeline

    private func restartSoon() {
        guard isSpeaking, !isPaused else { return }
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self, !Task.isCancelled, self.isPlaying else { return }
            self.play(from: self.sentenceStart(before: self.cursor + 1), snap: false)
        }
    }

    private func restart(at block: Int, offset: Int) {
        generation += 1
        cancelToken.cancelled = true
        cancelToken = CancelToken()
        liveSynthesis = false
        recorder.reset(nil)
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        player.stop()
        segments = []; scheduledEnd = 0; synthesizing = false; master.reset()
        index = block; nextBlock = block; nextOffset = offset
        cursor = blocks[block].location + offset
        spokenWord = nil
        spokenSentence = sentenceRange(around: cursor)
        synthesizeNext()
        nowPlaying()
    }

    /// Voice for a piece of text: the document's voice, or the other-language voice for a sentence in that language.
    private func voiceID(for language: String?) -> String {
        guard let l = language, l != baseLanguage else { return voiceID }
        return otherVoiceID.isEmpty ? voiceID : otherVoiceID
    }

    /// Keep about half a minute of audio ahead of the play head. A piece is a run of sentences in one language:
    /// a whole paragraph for system voices, at most a few sentences for Voice Reader's own voices (they are rendered
    /// in full before playing, so short pieces start sooner).
    private func synthesizeNext() {
        guard isSpeaking, !synthesizing, nextBlock < blocks.count else { return }
        if scheduledEnd - playhead > AVAudioFramePosition(48_000 * 30) { return }
        if voiceID == VoiceProfile.studio.id, let pack = studio, studioNext(pack) { return }
        if isCloud { elevenNext(); return }
        guard let piece = nextPiece() else { return }
        let range = blocks[piece.block]
        let original = text.substring(with: NSRange(location: range.location + piece.offset, length: piece.length))
        let spoken = SpokenText(original, options: options)
        if spoken.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { synthesizeNext(); return }
        let vid = voiceID(for: piece.language)
        let endsParagraph = piece.offset + piece.length >= range.length
        if vid == VoiceProfile.studio.id {
            // no Mac audio here (a document without a pack, or a place the pack does not reach yet): Ema reads it
            renderProfile(.emaTok, piece: piece, spoken: spoken, endsParagraph: endsParagraph)
        } else if let profile = VoiceProfile.with(id: vid), profile.isAvailable {
            renderProfile(profile, piece: piece, spoken: spoken, endsParagraph: endsParagraph)
        } else if tune(vid).steady > 0.01 {
            renderSteady(vid, piece: piece, spoken: spoken, endsParagraph: endsParagraph)
        } else {
            speakSystem(vid, piece: piece, spoken: spoken)
        }
    }

    /// A system voice with a steadier melody: synthesised into memory at its own rate, pitch and volume (as the live
    /// path), then its melody narrowed (PitchShift.flatten), then queued whole like Voice Reader's own voices.
    private func renderSteady(_ vid: String, piece: Piece, spoken: SpokenText, endsParagraph: Bool) {
        synthesizing = true
        let gen = generation
        let token = cancelToken
        let t = tune(vid)
        let rate = Self.rate(for: speed)
        let text = spoken.string
        let id = AVSpeechSynthesisVoice(identifier: vid) != nil ? vid
            : AVSpeechSynthesisVoice(language: piece.language ?? baseLanguage)?.identifier ?? vid
        let clear = masters, boost = master.boost, settingsVoice = assistive(piece.language)
        let gain = settingsVoice ? assistiveGain : 1
        ProfileRenderer.shared.queue.async { [weak self] in
            let r = ProfileRenderer.shared.renderSystem(text, voiceID: id, rate: rate, tune: t, assistive: settingsVoice, gain: gain, clear: clear, boost: boost,
                                                        cancelled: { token.cancelled })
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, gen == self.generation, self.isSpeaking else { return }
                    self.synthesizing = false
                    guard let r, !r.samples.isEmpty else { self.synthesizeNext(); return }
                    self.schedule(r, piece: piece, spoken: spoken, pause: endsParagraph ? 0.18 : 0)
                }
            }
        }
    }

    private struct Piece { let block: Int; let offset: Int; let length: Int; let language: String? }

    // MARK: Studio voice: audio rendered on the Mac, played as it is

    /// Queue the pack's segment at the reading position. False when the pack has nothing there (then the live path
    /// reads it). A segment whose file is missing is read by Ema, so reading never stops.
    private func studioNext(_ pack: StudioPack) -> Bool {
        let pos = blocks[nextBlock].location + nextOffset
        guard let i = pack.index(at: pos) else { return false }
        let seg = pack.segments[i]
        // a gap the pack does not cover (text after the last rendered segment): live path
        if seg.location > pos, text.substring(with: NSRange(location: pos, length: seg.location - pos))
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { return false }
        let start = max(pos, seg.location)
        let end = min(seg.end, text.length)
        guard end > start else { return false }
        let bi = blockIndex(containing: start)
        let piece = Piece(block: bi, offset: start - blocks[bi].location, length: end - start, language: baseLanguage)
        // continue after the segment
        let eb = blockIndex(containing: end)
        if end >= blocks[eb].location + blocks[eb].length { nextBlock = eb + 1; nextOffset = 0 }
        else { nextBlock = eb; nextOffset = end - blocks[eb].location }
        let original = text.substring(with: NSRange(location: start, length: end - start))
        let spoken = SpokenText(original, options: SpokenText.Options(simplifyLinks: false, skipCitations: false))
        synthesizing = true
        let gen = generation
        let speed = self.speed
        let boost = renderBoost
        ProfileRenderer.shared.queue.async { [weak self] in
            let r = pack.render(i, from: start, speed: speed, boost: boost)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, gen == self.generation, self.isSpeaking else { return }
                    self.synthesizing = false
                    if let r, !r.samples.isEmpty {
                        self.schedule(r, piece: piece, spoken: spoken, pause: seg.pause)
                    } else {
                        Self.log.error("studio audio missing: \(seg.file, privacy: .public)")
                        self.renderProfile(.emaTok, piece: piece, spoken: spoken, endsParagraph: seg.pause >= 0.4)
                    }
                }
            }
        }
        return true
    }

    // MARK: ElevenLabs: a whole paragraph from the server or the disk cache

    /// The rest of the paragraph at the reading position. The whole paragraph is always asked for (so a paragraph is
    /// stored once, whatever word reading started from) and the audio is cut at the starting word. Without a key, a
    /// voice or the network, the paragraph is read by the Turkish system voice and reading never stops.
    private(set) var elevenProblem: String?
    /// The ElevenLabs voice, model or quality changed: read on with the new sound.
    func elevenChanged() { if isCloud { applyBoost(); restartSoon() } }
    private func elevenNext() {
        let bi = nextBlock
        let range = blocks[bi]
        let offset = min(nextOffset, range.length)
        nextBlock += 1; nextOffset = 0
        guard offset < range.length else { synthesizeNext(); return }
        let full = text.substring(with: range)
        let spoken = SpokenText(full, options: options)
        if spoken.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { synthesizeNext(); return }
        let piece = Piece(block: bi, offset: offset, length: range.length - offset, language: baseLanguage)
        let cloud = voiceID == CloudVoice.readerVoiceID
        let ready = cloud ? CloudVoice.shared.ready : ElevenLabs.shared.ready
        let hasKey = cloud ? CloudVoice.shared.hasKey : ElevenLabs.shared.hasKey
        guard ready else { elevenFallback(piece, problem: hasKey ? ElevenError.noVoice : ElevenError.noKey); return }
        synthesizing = true
        let gen = generation
        let from = offset == 0 ? 0 : spoken.spoken(at: offset)
        let speed = self.speed, boost = renderBoost
        Task { [weak self] in
            do {
                let clip = cloud ? try await CloudVoice.shared.synthesize(spoken.string) : try await ElevenLabs.shared.synthesize(spoken.string)
                let r = await withCheckedContinuation { (c: CheckedContinuation<RenderedSpeech?, Never>) in
                    ProfileRenderer.shared.queue.async { c.resume(returning: ElevenCache.render(clip, from: from, speed: speed, boost: boost)) }
                }
                guard let self, gen == self.generation, self.isSpeaking else { return }
                self.synthesizing = false
                guard let r, !r.samples.isEmpty else { self.elevenFallback(piece, problem: ElevenError.undecodable); return }
                self.elevenProblem = nil
                // words come relative to the whole paragraph's spoken text; schedule() adds piece.offset, so shift back
                let words = r.words.map { (sample: $0.sample, range: spoken.original($0.range)) }
                    .map { (sample: $0.sample, range: NSRange(location: $0.range.location - offset, length: $0.range.length)) }
                self.scheduleOriginal(RenderedSpeech(samples: r.samples, words: words), piece: piece, pause: 0.18)
            } catch {
                guard let self, gen == self.generation, self.isSpeaking else { return }
                self.synthesizing = false
                self.elevenFallback(piece, problem: error)
            }
        }
    }

    /// schedule() maps word ranges through the piece's SpokenText; here the ranges are already in the paragraph, so a
    /// plain (identity) SpokenText of the remaining text is used.
    private func scheduleOriginal(_ r: RenderedSpeech, piece: Piece, pause: Double) {
        let rest = text.substring(with: NSRange(location: blocks[piece.block].location + piece.offset, length: piece.length))
        schedule(r, piece: piece, spoken: SpokenText(rest, options: SpokenText.Options(simplifyLinks: false, skipCitations: false)), pause: pause)
    }

    private func elevenFallback(_ piece: Piece, problem: Error) {
        elevenProblem = problem.localizedDescription
        Self.log.error("eleven fallback: \(problem.localizedDescription, privacy: .public)")
        let original = text.substring(with: NSRange(location: blocks[piece.block].location + piece.offset, length: piece.length))
        let vid = AVSpeechSynthesisVoice(language: "tr-TR")?.identifier ?? ""
        speakSystem(vid, piece: piece, spoken: SpokenText(original, options: options))
    }

    /// Cut the next piece from (nextBlock, nextOffset) and advance past it.
    private func nextPiece() -> Piece? {
        while nextBlock < blocks.count {
            let range = blocks[nextBlock]
            let start = min(nextOffset, range.length)
            if start >= range.length { nextBlock += 1; nextOffset = 0; continue }
            let profileVoice = VoiceProfile.with(id: voiceID) != nil || tune(voiceID).steady > 0.01
            let limit = profileVoice ? (segments.isEmpty ? 140 : 280) : Int.max
            var end = start
            var lang: String?
            var first = true
            while end < range.length {
                let sEnd = min(range.length, (sentenceEnd(after: range.location + end).map { $0 - range.location }) ?? range.length)
                let sLen = max(1, sEnd - end)
                let l = mixedLanguage ? language(of: text.substring(with: NSRange(location: range.location + end, length: sLen))) : nil
                let effective = l ?? baseLanguage
                if first { lang = effective; first = false }
                else if effective != lang || (end - start) + sLen > limit { break }
                end = sEnd
                if end - start >= limit { break }
            }
            let piece = Piece(block: nextBlock, offset: start, length: end - start, language: lang)
            nextOffset = end
            if nextOffset >= range.length { nextBlock += 1; nextOffset = 0 }
            return piece
        }
        return nil
    }

    /// Turkish or English for a sentence of at least four words, when the recogniser is sure; nil otherwise.
    private func language(of sentence: String) -> String? {
        guard sentence.split(separator: " ").count >= 4 else { return nil }
        let r = recognizer
        r.reset()
        r.languageConstraints = [.turkish, .english]
        r.processString(sentence)
        let h = r.languageHypotheses(withMaximum: 2)
        if let en = h[.english], en >= 0.85 { return "en" }
        if let tr = h[.turkish], tr >= 0.85 { return "tr" }
        return nil
    }

    // MARK: system voices: live synthesis, word callbacks

    private func speakSystem(_ vid: String, piece: Piece, spoken: SpokenText) {
        let u = AVSpeechUtterance(string: spoken.string)
        u.voice = AVSpeechSynthesisVoice(identifier: vid) ?? AVSpeechSynthesisVoice(language: piece.language ?? baseLanguage)
        u.rate = Self.rate(for: speed)
        let t = tune(vid)
        u.pitchMultiplier = Float(t.pitch)
        u.volume = Float(t.volume)
        u.prefersAssistiveTechnologySettings = assistive(piece.language)
        liveGain = u.prefersAssistiveTechnologySettings ? assistiveGain : 1
        convertFresh = true
        serial += 1
        let sid = serial
        // through VoiceMaster the utterance is heard `latency` frames (7 ms) after it is queued
        mastering = masters
        segments.append(Segment(id: sid, block: piece.block, offset: piece.offset, start: scheduledEnd, length: piece.length, spoken: spoken,
                                shift: mastering ? AVAudioFramePosition(master.latency) : 0))
        synthesizing = true
        liveSynthesis = true
        lastAudio = .now
        let gen = generation
        let rec = recorder
        let uid = ObjectIdentifier(u)
        liveUtterance = uid
        rec.reset(uid)
        synth.write(u) { [weak self] buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            guard let at = rec.advance(by: Int64(pcm.frameLength), for: uid) else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.received(pcm, at: at, gen: gen, sid: sid) } }
        }
    }

    private func received(_ pcm: AVAudioPCMBuffer, at: Int64, gen: Int, sid: Int) {
        guard gen == generation, isSpeaking, let seg = segments.last, seg.id == sid, seg.end == nil else { return }
        lastAudio = .now
        // iOS 27 sends an empty buffer in the middle of a long paragraph as well as at its end (measured on the phone,
        // 2026-10-26: Yelda, after the second of three sentences). Taking it for the end dropped the rest of the
        // paragraph: the next utterance began and the late buffers were thrown away. The end is now the synthesiser's
        // didFinish, or half a second with no audio after an empty buffer.
        if pcm.frameLength == 0 { endIfQuiet(sid, gen: gen); return }
        guard let out = prepare(pcm) else { return }
        if liveGain != 1, let p = out.floatChannelData?[0] {
            var g = liveGain
            vDSP_vsmul(p, 1, &g, p, 1, vDSP_Length(out.frameLength))
        }
        if mastering, let p = out.floatChannelData?[0], out.frameLength > 0 {
            let n = Int(out.frameLength)
            p.update(from: master.process(Array(UnsafeBufferPointer(start: p, count: n))), count: n)
        }
        let ph = playhead
        if player.isPlaying, ph > scheduledEnd {
            segments[segments.count - 1].shift += ph - scheduledEnd
            scheduledEnd = ph
        }
        player.scheduleBuffer(out)
        scheduledEnd += AVAudioFramePosition(out.frameLength)
        if !isPaused, !player.isPlaying { player.play() }
    }

    private func endIfQuiet(_ sid: Int, gen: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, gen == self.generation, let seg = self.segments.last, seg.id == sid, seg.end == nil,
                      Date.now.timeIntervalSince(self.lastAudio) >= 0.5 else { return }
                self.finishSegment()
            }
        }
    }

    /// The synthesiser finished the utterance: end its segment once the buffers already on their way are in.
    fileprivate func utteranceFinished(_ uid: ObjectIdentifier, gen: Int) {
        guard gen == generation, uid == liveUtterance, let sid = segments.last?.id else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, gen == self.generation, let seg = self.segments.last, seg.id == sid, seg.end == nil else { return }
                self.finishSegment()
            }
        }
    }

    private func finishSegment() {
        guard let seg = segments.last, seg.end == nil else { return }
        synthesizing = false
        liveSynthesis = false
        if mastering { scheduleTail() }
        segments[segments.count - 1].end = scheduledEnd
        if seg.offset + seg.length >= blocks[seg.block].length { scheduleSilence(0.22) }
        synthesizeNext()
    }

    /// The last 7 ms of an utterance, still inside VoiceMaster, pushed out before the pause after it.
    private func scheduleTail() {
        mastering = false
        let tail = master.flush()
        guard let f = format, !tail.isEmpty, let buf = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: AVAudioFrameCount(tail.count)) else { return }
        buf.frameLength = buf.frameCapacity
        tail.withUnsafeBufferPointer { buf.floatChannelData![0].update(from: $0.baseAddress!, count: tail.count) }
        let ph = playhead
        if player.isPlaying, ph > scheduledEnd { scheduledEnd = ph }
        player.scheduleBuffer(buf)
        scheduledEnd += AVAudioFramePosition(tail.count)
    }

    private func scheduleSilence(_ seconds: Double) {
        guard let f = format else { return }
        let n = AVAudioFrameCount(f.sampleRate * seconds / max(speed, 0.5))
        guard n > 0, let gap = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: n) else { return }
        gap.frameLength = n
        player.scheduleBuffer(gap)
        scheduledEnd += AVAudioFramePosition(n)
    }

    // MARK: Voice Reader voices: rendered off the main thread, then scheduled whole

    private func renderProfile(_ profile: VoiceProfile, piece: Piece, spoken: SpokenText, endsParagraph: Bool) {
        synthesizing = true
        let gen = generation
        let token = cancelToken
        let speed = self.speed
        let depth = voiceDepth[profile.id] ?? 0
        // On Voice Reader's own voices Düzlük calms the model itself (smaller starting noise): narrowing the melody
        // afterwards with PSOLA cracked them (Ema 0.88 % pitch breaks at 30 %), the calmer model does not
        // (Derin at 50 %: 6.8 → 3.6 semitones, no breaks, Whisper unchanged).
        let calm = voiceTune[profile.id]?.steady ?? 0
        let boost = renderBoost
        let text = spoken.string
        ProfileRenderer.shared.queue.async { [weak self] in
            let r = ProfileRenderer.shared.render(text, profile: profile, speed: speed, depth: depth, calm: calm, boost: boost,
                                                  cancelled: { token.cancelled })
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, gen == self.generation, self.isSpeaking else { return }
                    self.synthesizing = false
                    guard let r, !r.samples.isEmpty else { self.synthesizeNext(); return }
                    self.schedule(r, piece: piece, spoken: spoken, pause: endsParagraph ? 0.18 : 0)
                }
            }
        }
    }

    private func schedule(_ r: RenderedSpeech, piece: Piece, spoken: SpokenText, pause: Double) {
        guard let src = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1),
              let buf = AVAudioPCMBuffer(pcmFormat: src, frameCapacity: AVAudioFrameCount(r.samples.count)) else { return }
        buf.frameLength = buf.frameCapacity
        r.samples.withUnsafeBufferPointer { buf.floatChannelData![0].update(from: $0.baseAddress!, count: r.samples.count) }
        guard let out = prepare(buf) else { return }
        let k = (format?.sampleRate ?? 48_000) / 48_000
        let ph = playhead
        if player.isPlaying, ph > scheduledEnd { scheduledEnd = ph }      // ran dry while rendering: start from now
        serial += 1
        var seg = Segment(id: serial, block: piece.block, offset: piece.offset, start: scheduledEnd, length: piece.length, spoken: spoken)
        seg.words = r.words.map { w in
            let o = spoken.original(w.range)
            return (scheduledEnd + AVAudioFramePosition(Double(w.sample) * k), NSRange(location: piece.offset + o.location, length: o.length))
        }
        player.scheduleBuffer(out)
        scheduledEnd += AVAudioFramePosition(out.frameLength)
        seg.end = scheduledEnd
        segments.append(seg)
        if pause > 0 { scheduleSilence(pause) }
        if !isPaused, !player.isPlaying { player.play() }
        synthesizeNext()
    }

    fileprivate func word(_ r: NSRange, at: Int64, gen: Int) {
        guard gen == generation, !segments.isEmpty else { return }
        let i = segments.count - 1
        let seg = segments[i]
        let frame = seg.start + seg.shift + AVAudioFramePosition(Double(at) * ratio)
        let o = seg.spoken.original(r)
        segments[i].words.append((frame, NSRange(location: seg.offset + o.location, length: o.length)))
    }

    private func prepare(_ pcm: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let src = pcm.format
        // the player always runs at 48 kHz mono, so system voices (22 kHz) and our voices (48 kHz) can alternate
        guard let wanted = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1) else { return nil }
        if format == nil || (scheduledEnd == 0 && format != wanted) {
            if engine.isRunning { engine.stop() }
            engine.connect(player, to: limiter, format: wanted)        // player → limiter → mixer
            engine.connect(limiter, to: engine.mainMixerNode, format: wanted)
            applyBoost()
            format = wanted
        }
        if !engine.isRunning {
            engine.prepare()
            do { try engine.start() } catch { return nil }
        }
        guard let f = format else { return nil }
        ratio = f.sampleRate / src.sampleRate
        if src == f { return pcm }
        // One converter per source format, reused (a new one per buffer cost thousands of allocations a minute), and
        // reset only when a new utterance starts. A system voice arrives in buffers of 255 frames (11.6 ms); the old
        // reset before every buffer threw away the resampler's state 86 times a second, which dropped 6.3 % of the
        // samples and left a click at every seam: 6× the energy above 8 kHz of a clean conversion (Yelda, measured
        // on the Mac 2026-10-21). That roughness is what made the system voices sound unsteady next to Voice Dream.
        if converter?.inputFormat != src || converter?.outputFormat != f { converter = AVAudioConverter(from: src, to: f); convertFresh = false }
        guard let conv = converter,
              let out = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: AVAudioFrameCount(Double(pcm.frameLength) * ratio) + 64)
        else { return nil }
        if convertFresh { conv.reset(); convertFresh = false }
        var fed = false
        var err: NSError?
        conv.convert(to: out, error: &err) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true; status.pointee = .haveData; return pcm
        }
        return err == nil ? out : nil
    }

    private var playhead: AVAudioFramePosition {
        guard let nt = player.lastRenderTime, nt.isSampleTimeValid,
              let pt = player.playerTime(forNodeTime: nt) else { return 0 }
        return max(0, pt.sampleTime)
    }

    private var latencyFrames: AVAudioFramePosition {
        let s = AVAudioSession.sharedInstance()
        let secs = max(engine.outputNode.presentationLatency, s.outputLatency + s.ioBufferDuration)
        return AVAudioFramePosition(secs * (format?.sampleRate ?? 22050))
    }

    /// 25 times a second: follow the word being heard, keep synthesis ahead, run the sleep timer.
    private func tick() {
        guard isSpeaking else { return }
        if liveSynthesis, Date.now.timeIntervalSince(lastAudio) > 6 {
            recorder.reset(nil)
            if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
            finishSegment()
        }
        synthesizeNext()
        if let end = sleepEnds, Date.now >= end { pause(); setSleepTimer(.off); return }
        if !synthesizing, nextBlock >= blocks.count, scheduledEnd == 0 { finished(); return }
        guard !isPaused, player.isPlaying else { return }
        if breakEvery > 0 {
            listened += 0.04
            if listened >= breakEvery { breakDue = true }
        }
        if segmentLimit > 0 {
            segmentListened += 0.04
            if segmentListened >= segmentLimit { segmentDue = true }
        }
        let pos = playhead - latencyFrames
        if fadeInPending, let first = segments.first, pos >= first.start {
            fadeInPending = false
            fadeTo(1, over: Self.fadeInSeconds)
        }
        // the break waits for the sentence to end: find where the next one starts, go quiet just before it
        if breakDue || segmentDue {
            if breakBoundary == nil, let s = spokenSentence { breakBoundary = boundary(after: s) }
            if let b = breakBoundary {
                let fadeFrames = AVAudioFramePosition(Self.fadeOutSeconds * (format?.sampleRate ?? 22050))
                if pos >= b.frame - fadeFrames, fadeTimer == nil, fade > 0.99 { fadeTo(0, over: Self.fadeOutSeconds) }
                if pos >= b.frame { goQuiet(at: b.at); return }
            }
        }
        guard let si = segments.lastIndex(where: { $0.start <= pos }) else { return }
        let seg = segments[si]
        guard seg.block < blocks.count else { return }
        let base = blocks[seg.block].location
        if index != seg.block { index = seg.block; nowPlaying() }
        let local = wordAt(pos, in: seg) ?? NSRange(location: seg.offset, length: 0)
        let w = NSRange(location: base + local.location, length: local.length)
        if spokenWord != w, w.length > 0 {
            spokenWord = w
            cursor = w.location
            if let s = spokenSentence, NSLocationInRange(w.location, s) {} else {
                spokenSentence = sentenceRange(around: w.location)
                // fallback when the next sentence's start was not known in time (not yet synthesised)
                if breakDue || segmentDue, breakBoundary == nil, let s = spokenSentence { goQuiet(at: s.location); return }
            }
            measurePace()
            report(force: false)
            if let stopAt = sleepChapterEnd, w.location >= stopAt { pause(); setSleepTimer(.off); return }
        }
        if !synthesizing, nextBlock >= blocks.count, pos >= scheduledEnd { finished() }
    }

    // MARK: music break

    private func goQuiet(at sentence: Int) {
        if segmentDue { endSegment(at: sentence) } else { startBreak(at: sentence) }
    }

    /// Stop the voice at the start of a sentence and let the music come up. The engine keeps running on silence, so
    /// iOS keeps the app alive in the background and the break ends on time; the queued audio is dropped and the
    /// sentence is read again from its start afterwards.
    private func startBreak(at sentence: Int, length: Double? = nil, kind: BreakKind = .music) {
        breakDue = false
        breakKind = kind
        breakBoundary = nil
        listened = 0
        fadeTimer?.invalidate(); fadeTimer = nil
        setFade(0)
        stopAudioKeepingSession()
        ticker?.invalidate(); ticker = nil
        isPaused = true
        cursor = sentence
        spokenWord = nil
        let length = length ?? breakLength
        breakEnds = kind == .untilMusicStops ? .distantFuture : Date.now.addingTimeInterval(length)
        liftDucking()
        report(force: true)
        nowPlaying()
        breakTask?.cancel()
        breakTask = Task { [weak self] in
            if kind == .untilMusicStops {
                await Self.waitForMusicToStop()
            } else {
                try? await Task.sleep(for: .seconds(length))
            }
            guard let self, !Task.isCancelled, self.breakEnds != nil else { return }
            self.endBreak()
        }
    }

    /// Aktif bekleme: reading stops now and starts again by itself, from the start of the sentence it stopped in,
    /// after `seconds` (nil: once the other app's music has stopped). ⏯ during the wait goes on at once.
    func activePause(seconds: Double?) {
        guard let id = documentID, !blocks.isEmpty else { return }
        let kind: BreakKind = seconds == nil ? .untilMusicStops : .hold
        if isPlaying {
            startBreak(at: sentenceStart(before: min(cursor + 1, text.length)), length: seconds, kind: kind)
            return
        }
        // paused or stopped: wait, then start the way the automation does (music down first, voice fades in)
        guard mayMove?(id, cursor) != false else { return }
        breakKind = kind
        breakEnds = kind == .untilMusicStops ? .distantFuture : Date.now.addingTimeInterval(seconds ?? 0)
        nowPlaying()
        breakTask?.cancel()
        breakTask = Task { [weak self] in
            if kind == .untilMusicStops { await Self.waitForMusicToStop() } else { try? await Task.sleep(for: .seconds(seconds ?? 0)) }
            guard let self, !Task.isCancelled, self.breakEnds != nil else { return }
            if self.isSpeaking, self.isPaused { self.endBreak(); return }
            self.breakEnds = nil
            self.breakTask = nil
            self.playAfterHold()
        }
    }

    /// Ends an active wait without reading (the reader pressed stop on it).
    func cancelWait() {
        guard breakEnds != nil else { return }
        breakTask?.cancel(); breakTask = nil
        breakEnds = nil
        nowPlaying()
    }

    /// Another app's audio (Spotify) was heard and then stayed quiet for three seconds. Checked once a second;
    /// if music never starts, the wait lasts until ⏯.
    private static func waitForMusicToStop() async {
        var heard = false, quiet = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            let playing = AVAudioSession.sharedInstance().isOtherAudioPlaying
            if playing { heard = true; quiet = 0 } else if heard { quiet += 1 }
            if heard, quiet >= 3 { return }
        }
    }

    /// With music: ducking can only be lifted by deactivating; then run again without it, on silence.
    private func liftDucking() {
        guard musicMix != .off else { return }
        engine.stop()
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
        try? session.setActive(true)
        try? engine.start()
    }

    // MARK: automation

    /// The next `seconds` of listening are one automation step (counted only while the voice is heard).
    func startSegment(seconds: Double) {
        segmentLimit = max(0, seconds)
        segmentListened = 0
        segmentDue = false
    }

    func endSegments() {
        segmentLimit = 0
        segmentDue = false
        keepSessionAtEnd = false
    }

    /// The step's time is up: quiet at the start of the next sentence (the place is kept there), the music comes up,
    /// the engine runs on silence; the automation decides what follows.
    private func endSegment(at sentence: Int) {
        segmentDue = false
        segmentLimit = 0
        breakDue = false
        breakBoundary = nil
        listened = 0
        fadeTimer?.invalidate(); fadeTimer = nil
        setFade(0)
        stopAudioKeepingSession()
        ticker?.invalidate(); ticker = nil
        isPaused = true
        cursor = sentence
        spokenWord = nil
        liftDucking()
        report(force: true)
        nowPlaying()
        onSegmentEnd?()
    }

    /// Automation: start reading the loaded document after a quiet hold. With music, the music goes down first (the
    /// ducking session comes back, the engine runs again on silence at once), then the voice comes up over two seconds.
    func playAfterHold() {
        breakTask?.cancel(); breakTask = nil
        guard musicMix != .off else { fadeInPending = true; play(); return }
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
        activateSession()
        if format != nil { try? engine.start() }
        breakTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.duckSettleSeconds))
            guard let self, !Task.isCancelled, self.documentID != nil else { return }
            self.breakTask = nil
            self.fadeInPending = true
            self.play()
        }
    }

    /// The music goes down first (the ducking session comes back), then the voice comes up over two seconds from the
    /// sentence the break stopped before.
    private func endBreak() {
        breakTask?.cancel(); breakTask = nil
        breakEnds = nil
        guard musicMix != .off else { fadeInPending = true; play(from: cursor, snap: false); return }
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
        activateSession()
        let at = cursor
        breakTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.duckSettleSeconds))
            guard let self, !Task.isCancelled, self.isSpeaking, self.isPaused, self.breakEnds == nil else { return }
            self.breakTask = nil
            self.fadeInPending = true
            self.play(from: at, snap: false)
        }
    }

    /// The frame at which the sentence after `s` starts to be heard, and its offset; nil while it is not synthesised.
    private func boundary(after s: NSRange) -> (frame: AVAudioFramePosition, at: Int)? {
        let end = s.location + s.length
        for seg in segments where seg.block < blocks.count {
            let base = blocks[seg.block].location
            if seg.words.isEmpty {
                let a = base + seg.offset, z = a + seg.length
                if a >= end { return (seg.start, a) }
                if end < z, let segEnd = seg.end, segEnd > seg.start {      // no word timings: by proportion
                    let f = seg.start + AVAudioFramePosition(Double(end - a) / Double(max(1, seg.length)) * Double(segEnd - seg.start))
                    return (f, end)
                }
                continue
            }
            if let w = seg.words.first(where: { base + $0.range.location >= end }) {
                return (w.at, base + w.range.location)
            }
        }
        return nil
    }

    // MARK: fades

    private func setFade(_ v: Float) {
        fadeTimer?.invalidate(); fadeTimer = nil
        if fade != v { fade = v }
    }

    /// A smooth (eased) change of the voice's level, 100 steps a second.
    private func fadeTo(_ target: Float, over seconds: Double) {
        fadeTimer?.invalidate()
        let from = fade, start = Date.now
        let t = Timer(timeInterval: 0.01, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                let x = min(1, Date.now.timeIntervalSince(start) / seconds)
                let e = Float(x * x * (3 - 2 * x))
                self.fade = from + (target - from) * e
                if x >= 1 { timer.invalidate(); self.fadeTimer = nil }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        fadeTimer = t
    }

    private func finished() {
        guard let id = documentID else { return }
        cursor = text.length
        stop(release: !keepSessionAtEnd)
        onFinished?(id)
    }

    private func wordAt(_ pos: AVAudioFramePosition, in seg: Segment) -> NSRange? {
        let ws = seg.words
        let tail = seg.offset + seg.length
        let blockLen = blocks[seg.block].length
        if ws.isEmpty {
            guard let end = seg.end, end > seg.start else { return nil }
            let c = seg.offset + Int(Double(pos - seg.start) / Double(end - seg.start) * Double(seg.length))
            let g = wordRange(around: blocks[seg.block].location + min(max(c, seg.offset), max(seg.offset, tail - 1)))
            return NSRange(location: g.location - blocks[seg.block].location, length: g.length)
        }
        guard let k = ws.lastIndex(where: { $0.at <= pos }) else { return nil }
        var a = k, b = k
        while a > 0, ws[a - 1].at == ws[k].at { a -= 1 }
        while b + 1 < ws.count, ws[b + 1].at == ws[k].at { b += 1 }
        if a == b { return clamp(ws[k].range, blockLen) }
        let t0 = ws[a].at
        let t1 = b + 1 < ws.count ? ws[b + 1].at : (seg.end ?? t0)
        guard t1 > t0 else { return clamp(ws[a].range, blockLen) }
        let c0 = ws[a].range.location
        let c1 = b + 1 < ws.count ? ws[b + 1].range.location : tail
        let c = c0 + Int(Double(pos - t0) / Double(t1 - t0) * Double(c1 - c0))
        return clamp(ws[a...b].last(where: { $0.range.location <= c })?.range ?? ws[a].range, blockLen)
    }

    private func clamp(_ r: NSRange, _ len: Int) -> NSRange {
        let a = min(max(0, r.location), len)
        return NSRange(location: a, length: min(r.length, len - a))
    }

    private func measurePace() {
        let now = Date.now
        guard let m = paceMark else { paceMark = (now, cursor); return }
        let dt = now.timeIntervalSince(m.date)
        guard dt >= 20 else { return }
        let dc = cursor - m.cursor
        if dc > 0, dt < 120 {
            let cps = Double(dc) / dt / speed
            if cps > 4, cps < 40 {
                charsPerSecond = charsPerSecond * 0.7 + cps * 0.3
                UserDefaults.standard.set(charsPerSecond, forKey: "a.cps")
            }
        }
        paceMark = (now, cursor)
    }

    private func report(force: Bool) {
        guard let id = documentID else { return }
        if !force, Date.now.timeIntervalSince(lastReported) < 2 { return }
        lastReported = .now
        onPosition?(id, cursor)
    }

    /// Seconds of listening left from the cursor at the current speed.
    var remainingSeconds: Double { Double(max(0, text.length - cursor)) / (charsPerSecond * speed) }
    var totalSeconds: Double { Double(text.length) / (charsPerSecond * speed) }

    // MARK: session

    /// Off: a non-mixable session, so the lock screen and headphone buttons are ours (other audio stops).
    /// Duck: play over music, which iOS lowers while we speak. Mix: play alongside at full level.
    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        let options: AVAudioSession.CategoryOptions = musicMix == .off ? [] : ducking ? [.mixWithOthers, .duckOthers] : [.mixWithOthers]
        if session.category != .playback || session.mode != .spokenAudio || session.categoryOptions != options {
            try? session.setCategory(.playback, mode: .spokenAudio, options: options)
        }
        try? session.setActive(true)
        UIApplication.shared.beginReceivingRemoteControlEvents()
    }

    // MARK: lock screen

    private func configureRemote() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self, self.remoteChoice?(0) != true else { return }
                self.isSpeaking ? self.resume() : self.play()
            }
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self, self.remoteChoice?(0) != true else { return }
                if self.remotePauseWaits, self.isPlaying { self.activePause(seconds: self.remotePauseSeconds) } else { self.pause() }
            }
            return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self, self.remoteChoice?(0) != true else { return }
                if self.remotePauseWaits, self.isPlaying { self.activePause(seconds: self.remotePauseSeconds) } else { self.toggle() }
            }
            return .success
        }
        c.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.remoteChoice?(1) == true || self.remoteSkip?(true) == true { return }
                self.skip(forward: true, unit: Self.lockScreenUnit)
            }
            return .success
        }
        c.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.remoteChoice?(-1) == true || self.remoteSkip?(false) == true { return }
                self.skip(forward: false, unit: Self.lockScreenUnit)
            }
            return .success
        }
        c.changePlaybackPositionCommand.addTarget { [weak self] e in
            guard let e = e as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let t = e.positionTime
            Task { @MainActor in
                guard let self, self.totalSeconds > 0 else { return }
                let at = Int(Double(self.length) * min(1, t / self.totalSeconds))
                self.moveCursor(to: self.sentenceStart(before: at + 1))
            }
            return .success
        }
        let nc = NotificationCenter.default
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let opts = n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            MainActor.assumeIsolated {
                if raw == AVAudioSession.InterruptionType.began.rawValue { self?.pause() }
                else if AVAudioSession.InterruptionOptions(rawValue: opts).contains(.shouldResume) { self?.resume() }
            }
        }
        nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.engineChanged() }
        }
        nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.engineChanged() }
        }
        nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] n in
            let r = n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if r == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { MainActor.assumeIsolated { self?.pause() } }
        }
    }

    /// The lock screen's ⏮ ⏭ follow the reader's navigation unit.
    static var lockScreenUnit: NavigationUnit {
        NavigationUnit(rawValue: UserDefaults.standard.string(forKey: "a.unit") ?? "") ?? .sentence
    }

    private func engineChanged() {
        guard isSpeaking else { return }
        format = nil
        if isPaused { return }
        play(from: sentenceStart(before: cursor + 1), snap: false)
    }

    func nowPlaying() {
        guard documentID != nil else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: [author, chapterTitle(at: cursor)].compactMap { $0 }.joined(separator: " · "),
            MPMediaItemPropertyAlbumTitle: "Wise Path · \(Self.speedName(speed))",
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPMediaItemPropertyPlaybackDuration: totalSeconds,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: totalSeconds - remainingSeconds,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let art = artwork { info[MPMediaItemPropertyArtwork] = art }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

extension SpeechPlayer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, willSpeakRangeOfSpeechString r: NSRange, utterance u: AVSpeechUtterance) {
        guard let at = recorder.position(of: ObjectIdentifier(u)) else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.word(r, at: at, gen: self.generationSnapshot) }
        }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        let uid = ObjectIdentifier(u)
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.utteranceFinished(uid, gen: self.generationSnapshot) }
        }
    }
}

extension SpeechPlayer {
    /// Word callbacks belong to the paragraph being synthesised now; the recorder already rejects stale utterances.
    fileprivate var generationSnapshot: Int { generation }
}

/// Lets a background render notice that its result is no longer wanted.
final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var cancelled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return flag }
        set { lock.lock(); flag = newValue; lock.unlock() }
    }
}

/// Frame counter shared by the buffer callback and the word callback, whichever thread they arrive on.
private final class FrameRecorder: @unchecked Sendable {
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
