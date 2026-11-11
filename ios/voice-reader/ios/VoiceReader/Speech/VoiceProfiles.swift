// Voice Reader's own voices. Each is a base voice (Ema's neural model, a Supertonic style blend, or an Apple voice)
// shaped by the same chain: pitch (TD-PSOLA, formants kept) → warmth EQ → speed (WSOLA, pitch kept) → level.
// The chain and the four settings were chosen by measurement (Kıymet preface, Whisper, sentence by sentence,
// 360 words a minute, 2026-10-19): Ema Tok 11.5 % word error, Derin 15.2 %, Cem Tok 15.2 %, Yelda Kalın 25.8 %.
// Speed is never given to a model (it garbles at 3×); the model speaks at its natural pace and WSOLA compresses.
import Foundation
import AVFoundation
import Accelerate

struct VoiceProfile: Identifiable, Hashable, Sendable {
    enum Engine: Hashable, Sendable {
        case ema
        case supertonic(String)          // style or blend, "M4:0.5,M5:0.5"
        case apple(String)               // Apple voice name ("Cem"): the best installed variant is used
        case studio                      // rendered on the Mac (StudioPack); where a piece has no audio, Ema speaks it
    }
    enum Tone: Hashable, Sendable { case flat, warm, deep }

    let id: String
    let name: String
    let detail: String
    let engine: Engine
    let semitones: Double
    let tone: Tone

    static let emaTok = VoiceProfile(id: "vr.ema-tok", name: "Ema Tok", detail: "Kadın · tok, berrak · hızlı dinlemede en net",
                                     engine: .ema, semitones: -4, tone: .warm)
    static let derin = VoiceProfile(id: "vr.derin", name: "Derin", detail: "Erkek · derin, tok · yeni ses (Supertonic M4+M5)",
                                    engine: .supertonic("M4:0.5,M5:0.5"), semitones: 0, tone: .deep)
    static let cemTok = VoiceProfile(id: "vr.cem-tok", name: "Cem Tok", detail: "Erkek · Apple Cem, bir ton kalın",
                                     engine: .apple("Cem"), semitones: -1, tone: .deep)
    static let yeldaKalin = VoiceProfile(id: "vr.yelda-kalin", name: "Yelda Kalın", detail: "Kadın · Apple Yelda, üç ton kalın",
                                         engine: .apple("Yelda"), semitones: -3, tone: .warm)

    static let studio = VoiceProfile(id: "vr.studio", name: "Anlatıcı", detail: "Erkek · stüdyo sesi, Mac'te önceden seslendirilir",
                                     engine: .studio, semitones: 0, tone: .flat)

    static let all: [VoiceProfile] = [emaTok, derin, cemTok, yeldaKalin]

    static func with(id: String) -> VoiceProfile? { id == studio.id ? studio : all.first { $0.id == id } }

    /// The installed Turkish Apple voice with this name, the plain (compact) one first as measured, then the others.
    static func appleVoice(named name: String) -> AVSpeechSynthesisVoice? {
        let voices = Voices.installed().filter { $0.language.hasPrefix("tr") && $0.name == name }
        let order: [AVSpeechSynthesisVoiceQuality] = [.default, .enhanced, .premium]
        return voices.min { (order.firstIndex(of: $0.quality) ?? 9) < (order.firstIndex(of: $1.quality) ?? 9) }
    }

    /// Usable on this device (the Apple base voice may be missing).
    var isAvailable: Bool {
        switch engine {
        case .ema: Bundle.main.url(forResource: "ema", withExtension: "json") != nil     // the model is not in every build
        case .studio: true
        case .supertonic: SupertonicEngine.isInstalled
        case .apple(let name): Self.appleVoice(named: name) != nil
        }
    }
}

/// One rendered piece of speech: 48 kHz mono samples and where each word starts in them.
struct RenderedSpeech: Sendable {
    var samples: [Float]
    var words: [(sample: Int, range: NSRange)]       // ranges in the text that was given to `render`
}

/// Renders text with a profile, off the main thread. One engine is kept open at a time.
final class ProfileRenderer: @unchecked Sendable {
    static let shared = ProfileRenderer()
    /// How much of the speed Ema's model takes itself; WSOLA gives the rest. Measured in the simulator at 2.75×
    /// (330 words a minute, 2026-10-21): all of it from WSOLA left Ema cracking: PSOLA then misread the squeezed
    /// periods (−2 instead of −4 semitones, 4 % sudden jumps, Whisper 49 %). The model at 1.5× and WSOLA 1.83×:
    /// the pitch right (188 Hz), 3.3 % jumps, Whisper 80 %; 1.3× and 1.7× were worse, pitch-before-speed too.
    nonisolated(unsafe) static var emaModelSpeed = 1.5
    /// Skip the profile's pitch change (test knob).
    nonisolated(unsafe) static var skipPitch = false
    /// Change the pitch before the speed (test knob).
    nonisolated(unsafe) static var pitchFirst = false
    let queue = DispatchQueue(label: "voice-reader.render", qos: .userInitiated)
    private var open: (VoiceProfile.Engine, NeuralEngine)?
    private let apple = AppleCapture()

    /// How much quieter iOS hands over a voice read with the phone's Spoken Content settings, as a gain that undoes it.
    /// iOS mixes its own speech-volume setting into the buffers it gives apps: on iOS 27.0.1 the same Yelda came at
    /// −16.4 dBFS one hour and −28 dBFS the next (the user had moved that slider), so it is measured, not assumed:
    /// one short sentence, nobody hears it, read with and without those settings. Nil when it cannot be measured.
    func assistiveGain(voiceID: String) -> Float? {
        let text = "Bu cümle sesin düzeyini ölçmek için okunur, kimse duymaz; düzey her okumada yeniden ölçülür."
        guard let a = apple.render(text, voiceID: voiceID, rate: 0.5, assistive: true, cancelled: { false }),
              let b = apple.render(text, voiceID: voiceID, rate: 0.5, assistive: false, cancelled: { false })
        else { return nil }
        func speaking(_ x: [Float]) -> Float {      // mean square of the parts that speak (above −40 dBFS)
            let s = x.filter { abs($0) > 0.01 }
            return s.isEmpty ? 0 : s.reduce(0) { $0 + $1 * $1 } / Float(s.count)
        }
        let ea = speaking(a.samples), eb = speaking(b.samples)
        guard ea > 1e-8, eb > 1e-8 else { return nil }
        return min(max((eb / ea).squareRoot(), 0.5), 16)      // −6 … +24 dB
    }
    private let master = VoiceMaster()          // system voices rendered whole (Düzlük on), used only on `queue`

    /// Measure the Turkish voice as the phone's Spoken Content settings make it, and find the Kalınlık and speed
    /// that give the same sound from Wise Path's own settings. Nobody hears it (about two seconds of work).
    /// The pitch is the median over the voiced frames (YIN); the Kalınlık is then tried and corrected twice, so the
    /// answer is what this phone's engine really gives, not what a formula says. Nil when it cannot be measured.
    func phoneVoice(voiceID: String) -> PhoneVoice? {
        let text = "Felsefe, insanın kendi aklını kendi üzerine çevirmesiyle başlar. Bu cümle yalnız sesi ölçmek için okunur ve kimse duymaz."
        func hz(_ r: RenderedSpeech) -> Double? {
            let v = PitchShift.f0Track(r.samples, sr: 48_000, hop: 240).filter { $0 > 0 }.sorted()
            return v.count > 40 ? v[v.count / 2] : nil
        }
        func seconds(_ r: RenderedSpeech) -> Double {          // from the first to the last sample that speaks
            guard let a = r.samples.firstIndex(where: { abs($0) > 0.01 }), let z = r.samples.lastIndex(where: { abs($0) > 0.01 }), z > a
            else { return 0 }
            return Double(z - a) / 48_000
        }
        let never: () -> Bool = { false }
        guard let plain = apple.render(text, voiceID: voiceID, rate: 0.5, cancelled: never), let plainHz = hz(plain),
              let phone = apple.render(text, voiceID: voiceID, rate: 0.5, assistive: true, cancelled: never), let phoneHz = hz(phone)
        else { return nil }
        var k = min(max(SystemPitch.kalinlik(ratio: phoneHz / plainHz), SystemPitch.range.lowerBound), SystemPitch.range.upperBound)
        var ownHz = plainHz
        for _ in 0..<3 {
            guard let own = apple.render(text, voiceID: voiceID, rate: 0.5, pitch: Float(k), cancelled: never), let f = hz(own) else { return nil }
            ownHz = f
            if abs(12 * log2(f / phoneHz)) < 0.2 { break }
            k = min(max(SystemPitch.kalinlik(ratio: SystemPitch.ratio(k) * phoneHz / f), SystemPitch.range.lowerBound), SystemPitch.range.upperBound)
        }
        // speed: iOS sometimes takes the app's rate in that mode and sometimes its own (seen both on iOS 27.0.1).
        // Read again at a faster rate: the same length means the phone's own rate rules, and it is measured.
        var speed: Double?
        if let faster = apple.render(text, voiceID: voiceID, rate: 0.59, assistive: true, cancelled: never) {
            let a = seconds(phone), b = seconds(faster), p = seconds(plain)
            if a > 1, b > a * 0.93, p > 1 { speed = min(max(p / a, 0.5), 3.6) }
        }
        return PhoneVoice(kalinlik: (k * 100).rounded() / 100, speed: speed, phoneHz: phoneHz, ownHz: ownHz, plainHz: plainHz)
    }

    /// Open the profile's engine ahead of the first sentence (models load in about a second), off the main thread.
    func warmUp(_ profile: VoiceProfile) {
        queue.async { [self] in
            if case .apple = profile.engine { return }
            _ = engine(profile.engine == .studio ? .ema : profile.engine)
        }
    }

    /// Render `text` (one or a few sentences). `speed` is the playback multiple; `depth` is the user's extra pitch in
    /// semitones on top of the profile's (negative = deeper); returns nil when cancelled.
    func render(_ text: String, profile: VoiceProfile, speed: Double, depth: Double = 0, steady: Double = 0, calm: Double = 0,
                boost: Double = 0, cancelled: @escaping () -> Bool) -> RenderedSpeech? {
        NeuralAudio.temperature = Float(1 - min(max(calm, 0), 0.9))
        defer { NeuralAudio.temperature = 1 }
        guard var r = base(text, profile: profile, speed: speed, cancelled: cancelled), !cancelled() else { return nil }
        // Order measured on 14 Ema sentences, Whisper (2026-10-20): speed first, then pitch. At 2.5× the words heard
        // rose from 92.7 % to 96.8 % (pitch first: WSOLA had to join PSOLA's grains, and the joins doubled up);
        // PSOLA also has fewer samples to work on.
        r.samples = ToneEQ.apply(r.samples, profile.tone)
        let semitones = Self.skipPitch ? 0 : profile.semitones + depth
        if Self.pitchFirst, abs(semitones) > 0.01, r.samples.count > 4800 { r.samples = PitchShift.shift(r.samples, semitones: semitones) }
        let modelSpeed = profile.engine == .ema || profile.engine == .studio ? min(speed, max(1, Self.emaModelSpeed)) : 1
        let tempo = max(1, speed / modelSpeed)
        if tempo > 1.01, r.samples.count > 4096 {
            let before = r.samples.count
            r.samples = TimeStretch.compress(r.samples, tempo: tempo)
            let k = Double(r.samples.count) / Double(before)
            r.words = r.words.map { (Int(Double($0.sample) * k), $0.range) }
        }
        if !Self.pitchFirst, abs(semitones) > 0.01, r.samples.count > 4800 { r.samples = PitchShift.shift(r.samples, semitones: semitones) }
        if steady > 0.01 { r.samples = PitchShift.flatten(r.samples, keep: 1 - steady) }
        r.samples = Level.apply(r.samples, boost: boost)
        return r
    }

    /// A system voice exactly as the live path plays it (its own rate step, pitch and volume, no EQ, no level stage),
    /// with only its melody narrowed by `tune.steady`; with `clear` then through VoiceMaster, as the live path.
    func renderSystem(_ text: String, voiceID: String, rate: Float, tune: VoiceTune, assistive: Bool = false, gain: Float = 1,
                      clear: Bool = false, boost: Float = 0, squeeze: (tempo: Double, words: Double)? = nil,
                      cancelled: @escaping () -> Bool) -> RenderedSpeech? {
        guard var r = apple.render(text, voiceID: voiceID, rate: rate, pitch: Float(tune.pitch), volume: Float(tune.volume),
                                   assistive: assistive, cancelled: cancelled), !cancelled() else { return nil }
        if gain != 1 { r.samples = r.samples.map { $0 * gain } }
        r.samples = PitchShift.flatten(r.samples, keep: 1 - tune.steady)
        // Yüksek hız: shortened unevenly to the speed asked for, the word times moved with it, the ends closed again
        if let squeeze, squeeze.tempo > 1.01 {
            let q = FastSpeech.squeeze(r.samples, tempo: squeeze.tempo)
            r.words = r.words.map { (q.moved($0.sample), $0.range) }
            r.samples = FastSpeech.tighten(q.samples, target: FastSpeech.closing(at: squeeze.words), ends: q.phraseEnds.map(q.moved))
        }
        if clear { master.boost = boost; r.samples = master.whole(r.samples) }
        // 3 ms fades: pieces are queued back to back
        let fade = min(144, r.samples.count / 4)
        for i in 0..<fade {
            let w = Float(i) / Float(max(fade, 1))
            r.samples[i] *= w
            r.samples[r.samples.count - 1 - i] *= w
        }
        return r
    }

    private func engine(_ e: VoiceProfile.Engine) -> NeuralEngine? {
        if let (k, m) = open, k == e { return m }
        open = nil
        let m: NeuralEngine?
        switch e {
        case .ema, .studio: m = try? EmaEngine()
        case .supertonic(let s): m = try? SupertonicEngine(style: s)
        case .apple: m = nil
        }
        if let m { open = (e, m) }
        return m
    }

    private func base(_ text: String, profile: VoiceProfile, speed: Double, cancelled: @escaping () -> Bool) -> RenderedSpeech? {
        switch profile.engine {
        case .apple(let name):
            // natural pace, or slower than natural when asked (below 1× the voice itself slows down)
            guard let id = VoiceProfile.appleVoice(named: name)?.identifier else { return nil }
            return apple.render(text, voiceID: id, rate: speed < 1 ? SpeechPlayer.rate(for: speed) : AVSpeechUtteranceDefaultSpeechRate,
                                cancelled: cancelled)
        case .ema, .supertonic, .studio:
            // a Studio piece reaches here only when its audio is missing: Ema speaks it
            let engineKind: VoiceProfile.Engine = profile.engine == .studio ? .ema : profile.engine
            guard let m = engine(engineKind) else { return nil }
            let map = TextPrep.wordMap(text, alphabet: m.alphabet)   // every model word → its word in `text`
            var samples: [Float] = []
            var words: [(Int, NSRange)] = []
            var w = 0
            let isEma = engineKind == .ema
            do {
                try m.synthesize(text, speed: isEma ? (speed < 1 ? speed : min(speed, max(1, Self.emaModelSpeed))) : max(1, speed), keepGoing: { !cancelled() }) { wav, wordSamples in
                    var at = samples.count
                    for n in wordSamples {
                        if w < map.count { words.append((at, map[w])) }
                        at += n; w += 1
                    }
                    samples += wav
                }
            } catch { return nil }
            if cancelled() { return nil }
            // one entry per original word (a number read as several model words keeps its first start)
            var seen = Set<Int>()
            words = words.filter { seen.insert($0.1.location).inserted }
            return RenderedSpeech(samples: samples, words: words)
        }
    }
}

/// Synthesises an Apple voice into memory (not the speaker), recording where each word begins.
private final class AppleCapture: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let synth = AVSpeechSynthesizer()
    private let lock = NSLock()
    private var frames = 0
    private var marks: [(Int, NSRange)] = []
    private var current: ObjectIdentifier?
    private var sawEmpty = false
    private var lastBuffer = Date()
    private var finishedID: ObjectIdentifier?

    override init() { super.init(); synth.delegate = self }

    func render(_ text: String, voiceID: String, rate: Float, pitch: Float = 1, volume: Float = 1, assistive: Bool = false,
                cancelled: () -> Bool) -> RenderedSpeech? {
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(identifier: voiceID)
        u.rate = rate
        SystemPitch.apply(Double(pitch), to: u)
        u.volume = volume
        u.prefersAssistiveTechnologySettings = assistive
        lock.lock(); frames = 0; marks = []; current = ObjectIdentifier(u); lock.unlock()
        var out: [Float] = []
        var rate: Double = 22_050
        lock.lock(); sawEmpty = false; lastBuffer = .now; finishedID = nil; lock.unlock()
        let mine = ObjectIdentifier(u)
        synth.write(u) { [weak self] buffer in
            guard let self, let pcm = buffer as? AVAudioPCMBuffer else { return }
            // a buffer of an utterance given up (a cancel) arriving late: it is not this render's audio, and its
            // closing empty buffer is not this render's end
            self.lock.lock(); let live = self.current == mine; self.lock.unlock()
            guard live else { return }
            // iOS 27 sends an empty buffer in the middle of a long utterance too, so it is not the end by itself
            if pcm.frameLength == 0 { self.lock.lock(); self.sawEmpty = true; self.lastBuffer = .now; self.lock.unlock(); return }
            let n = Int(pcm.frameLength)
            let f = pcm.format.sampleRate
            let add: [Float]
            if let p = pcm.floatChannelData { add = Array(UnsafeBufferPointer(start: p[0], count: n)) }
            else if let i = pcm.int16ChannelData { add = UnsafeBufferPointer(start: i[0], count: n).map { Float($0) / 32768 } }
            else { add = [] }
            self.lock.lock(); rate = f; out += add; self.frames += n; self.lastBuffer = .now; self.lock.unlock()
        }
        // done when the synthesiser says the utterance finished, or half a second after an empty buffer with nothing
        // after it; give up on a stalled synthesiser or a cancel
        let start = Date()
        let uid = ObjectIdentifier(u)
        while true {
            Thread.sleep(forTimeInterval: 0.05)
            lock.lock()
            let over = finishedID == uid || (sawEmpty && Date().timeIntervalSince(lastBuffer) > 0.5)
            lock.unlock()
            if over { break }
            if cancelled() || Date().timeIntervalSince(start) > 60 {
                lock.lock(); current = nil; lock.unlock()
                synth.stopSpeaking(at: .immediate)
                return nil
            }
        }
        lock.lock(); let m = marks; current = nil; let heard = out; let heardRate = rate; lock.unlock()
        let k = 48_000 / heardRate
        let samples = Resampler.convert(heard, from: heardRate, to: 48_000)
        return RenderedSpeech(samples: samples, words: m.map { (Int(Double($0.0) * k), $0.1) })
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, willSpeakRangeOfSpeechString r: NSRange, utterance u: AVSpeechUtterance) {
        lock.lock(); defer { lock.unlock() }
        guard ObjectIdentifier(u) == current else { return }
        marks.append((frames, r))
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        lock.lock(); finishedID = ObjectIdentifier(u); lock.unlock()
    }
}

/// Warmth EQ (RBJ biquads), as measured in the voice lab: body, a touch of presence, a softer top.
enum ToneEQ {
    static func apply(_ x: [Float], _ tone: VoiceProfile.Tone) -> [Float] {
        // A 75 Hz high-pass first on every voice: below it a phone speaker or earbud makes no sound, only distortion,
        // and that rumble eats the headroom the level stage needs.
        switch tone {
        case .flat: return chain(x, [highPass(f0: 75)])
        case .warm:
            return chain(x, [highPass(f0: 75), shelf(low: true, f0: 180, gain: 3), peak(f0: 2800, q: 1.0, gain: 1.5),
                             shelf(low: false, f0: 7000, gain: -2)])
        case .deep:
            return chain(x, [highPass(f0: 75), shelf(low: true, f0: 140, gain: 4.5), peak(f0: 350, q: 1.2, gain: -1.5),
                             peak(f0: 2500, q: 1.0, gain: 2), shelf(low: false, f0: 6500, gain: -3)])
        }
    }

    private static let sr = 48_000.0

    private static func chain(_ x: [Float], _ stages: [[Double]]) -> [Float] {
        guard !x.isEmpty, let setup = vDSP_biquad_CreateSetup(stages.flatMap { $0 }, vDSP_Length(stages.count)) else { return x }
        defer { vDSP_biquad_DestroySetup(setup) }
        var delay = [Float](repeating: 0, count: 2 * stages.count + 2)
        var y = [Float](repeating: 0, count: x.count)
        vDSP_biquad(setup, &delay, x, 1, &y, 1, vDSP_Length(x.count))
        return y
    }

    private static func shelf(low: Bool, f0: Double, gain: Double) -> [Double] {
        let A = pow(10, gain / 40), w = 2 * Double.pi * f0 / sr, cw = cos(w), s = sin(w)
        let sq = 2 * sqrt(A) * (s / 2 * sqrt(2.0))
        let b0, b1, b2, a0, a1, a2: Double
        if low {
            b0 = A * ((A + 1) - (A - 1) * cw + sq); b1 = 2 * A * ((A - 1) - (A + 1) * cw); b2 = A * ((A + 1) - (A - 1) * cw - sq)
            a0 = (A + 1) + (A - 1) * cw + sq; a1 = -2 * ((A - 1) + (A + 1) * cw); a2 = (A + 1) + (A - 1) * cw - sq
        } else {
            b0 = A * ((A + 1) + (A - 1) * cw + sq); b1 = -2 * A * ((A - 1) + (A + 1) * cw); b2 = A * ((A + 1) + (A - 1) * cw - sq)
            a0 = (A + 1) - (A - 1) * cw + sq; a1 = 2 * ((A - 1) - (A + 1) * cw); a2 = (A + 1) - (A - 1) * cw - sq
        }
        return [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0]
    }

    private static func highPass(f0: Double, q: Double = 0.707) -> [Double] {
        let w = 2 * Double.pi * f0 / sr, alpha = sin(w) / (2 * q), cw = cos(w), a0 = 1 + alpha
        return [(1 + cw) / 2 / a0, -(1 + cw) / a0, (1 + cw) / 2 / a0, -2 * cw / a0, (1 - alpha) / a0]
    }

    private static func peak(f0: Double, q: Double, gain: Double) -> [Double] {
        let A = pow(10, gain / 40), w = 2 * Double.pi * f0 / sr, alpha = sin(w) / (2 * q), cw = cos(w)
        let a0 = 1 + alpha / A
        return [(1 + alpha * A) / a0, -2 * cw / a0, (1 - alpha * A) / a0, -2 * cw / a0, (1 - alpha / A) / a0]
    }
}

/// Every voice at the same loudness, without distortion: the speaking parts (20 ms frames above −50 dBFS) are brought to
/// −19 dBFS RMS by a plain gain, then a look-ahead limiter holds the peaks under −1.5 dBFS. The old stage drove every
/// sample through tanh, which rounded off each peak; at a high volume that rounding is what was heard as harshness.
///
/// `boost` (dB, 0…16) makes the voice louder here, before playback, instead of in the live chain: the live chain put
/// the boost as plain gain into a fast peak limiter, which at +14 dB (music slider at 0) cut 24 % of all samples by
/// more than 3 dB; that clipping was the crackle, worst at high speed where speech has fewer gaps. Here a compressor
/// that sees 10 ms ahead lowers the loud syllables smoothly (−10 dBFS threshold, 2:1), then the look-ahead limiter
/// catches what is left.
enum Level {
    static func apply(_ x: [Float], boost: Double = 0) -> [Float] {
        guard x.count > 960 else { return x }
        let frame = 960
        var energy = 0.0, counted = 0
        var i = 0
        while i + frame <= x.count {
            var r: Float = 0
            x.withUnsafeBufferPointer { vDSP_rmsqv($0.baseAddress! + i, 1, &r, vDSP_Length(frame)) }
            if r > 0.0032 { energy += Double(r * r) * Double(frame); counted += frame }
            i += frame
        }
        guard counted > 0 else { return x }
        let rms = Float((energy / Double(counted)).squareRoot())
        var g = min(6, max(0.25, 0.112 / rms))
        var y = [Float](repeating: 0, count: x.count)
        vDSP_vsmul(x, 1, &g, &y, 1, vDSP_Length(x.count))
        if boost > 0.3 { y = Compressor.apply(y, makeUp: Float(min(boost, 16))) }
        y = Limiter.apply(y, ceiling: 0.84)
        // 3 ms fades at both ends: pieces are queued back to back, and a piece that starts or stops away from zero clicks
        let fade = min(144, y.count / 4)
        for i in 0..<fade {
            let w = Float(i) / Float(fade)
            y[i] *= w
            y[y.count - 1 - i] *= w
        }
        return y
    }
}

/// Look-ahead compressor with make-up gain: level from 10 ms RMS frames, gain from a static curve (threshold, ratio),
/// then the same smoothing as the limiter (minimum over ±L, average over ±L, release) so it never clicks.
enum Compressor {
    static func apply(_ x: [Float], makeUp: Float, threshold: Float = -10, ratio: Float = 2, sampleRate: Double = 48_000) -> [Float] {
        let n = x.count
        let f = Int(sampleRate * 0.01)
        guard n > 2 * f else { return x }
        let frames = (n + f - 1) / f
        var gainDB = [Float](repeating: makeUp, count: frames)
        for k in 0..<frames {
            let a = k * f, len = min(f, n - a)
            var r: Float = 0
            x.withUnsafeBufferPointer { vDSP_rmsqv($0.baseAddress! + a, 1, &r, vDSP_Length(len)) }
            let level = 20 * log10(max(r, 1e-6)) + makeUp
            if level > threshold { gainDB[k] = makeUp - (level - threshold) * (1 - 1 / ratio) }
        }
        // look-ahead: each frame takes the lowest gain within ±1 frame, then a 3-frame average
        var low = gainDB
        for k in 0..<frames { low[k] = gainDB[max(0, k - 1)...min(frames - 1, k + 1)].min()! }
        var smooth = low
        for k in 0..<frames { let w = low[max(0, k - 1)...min(frames - 1, k + 1)]; smooth[k] = w.reduce(0, +) / Float(w.count) }
        // per sample: linear between frame centres, release 60 ms upwards
        let release = Float(exp(-1 / (0.06 * sampleRate)))
        var y = [Float](repeating: 0, count: n)
        var env = smooth[0]
        for i in 0..<n {
            let pos = (Float(i) - Float(f) / 2) / Float(f)
            let k0 = max(0, min(frames - 1, Int(pos.rounded(.down)))), k1 = min(frames - 1, k0 + 1)
            let t = max(0, min(1, pos - Float(k0)))
            let target = smooth[k0] + (smooth[k1] - smooth[k0]) * t
            env = target < env ? target : target + (env - target) * release
            y[i] = x[i] * pow(10, env / 20)
        }
        return y
    }
}

/// Look-ahead peak limiter (L = 8 ms). The gain each sample needs is min-filtered over ±L and then box-averaged over ±L, so the
/// gain never exceeds what any peak in reach needs and still moves smoothly (no clicks, no clipping); it recovers
/// with an 80 ms release.
enum Limiter {
    static func apply(_ x: [Float], ceiling: Float, sampleRate: Double = 48_000) -> [Float] {
        let n = x.count
        guard n > 0 else { return x }
        var peak: Float = 0
        vDSP_maxmgv(x, 1, &peak, vDSP_Length(n))
        guard peak > ceiling else { return x }
        let L = Int(sampleRate * 0.008)
        var need = [Float](repeating: 1, count: n)
        for i in 0..<n { let a = abs(x[i]); if a > ceiling { need[i] = ceiling / a } }
        // sliding minimum over [i-L, i+L] (monotonic deque)
        var m = [Float](repeating: 1, count: n)
        var dq = [Int](); dq.reserveCapacity(2 * L + 2)
        var head = 0
        var next = 0
        for i in 0..<n {
            while next < n, next <= i + L {
                while dq.count > head, need[dq[dq.count - 1]] >= need[next] { dq.removeLast() }
                dq.append(next); next += 1
            }
            while dq[head] < i - L { head += 1 }
            m[i] = need[dq[head]]
            if head > 4096 { dq.removeFirst(head); head = 0 }
        }
        // box average over [i-L, i+L]
        var prefix = [Double](repeating: 0, count: n + 1)
        for i in 0..<n { prefix[i + 1] = prefix[i] + Double(m[i]) }
        let release = Float(exp(-1 / (0.08 * sampleRate)))
        var y = [Float](repeating: 0, count: n)
        var env: Float = 1
        for i in 0..<n {
            let a = max(0, i - L), b = min(n, i + L + 1)
            let s = Float((prefix[b] - prefix[a]) / Double(b - a))
            env = s < env ? s : s + (env - s) * release
            y[i] = x[i] * env
        }
        return y
    }
}
