import Accelerate

/// Plays a system voice (Yelda, Cem…) with Voice Dream's tone, a little louder, never clipped (2026-10-24).
///
/// Voice Dream plays Yelda exactly as the synthesiser makes it (−18 LUFS, peaks −1.9 dBFS). The crackle heard before
/// was ours: with the music slider at 0 the live chain asked for +14 dB from Apple's dynamics processor and a 2 ms
/// peak limiter, which re-shaped every pitch period (6.4 ms at Kalınlık 50) and still came out 2 dB quieter.
///
/// Nothing here changes the tone; the user heard every change of tone as loss. The second version turned the band above
/// 2.5 kHz of each vowel down (it measures as noise: the periods do not repeat there) and cut above 8.5 kHz: "boğuk".
/// The first lifted 2.8 kHz by 4 dB and compressed 3:1: hiss. So, all of them inaudible as colour:
///
/// 1. Needle repair: above 2.5 kHz (Linkwitz–Riley halves, flat when summed) a sample beyond 6× the level of the
///    4 ms around it is pulled back; about one in two seconds of speech.
/// 2. A phase rotator (four all-pass sections, 150–700 Hz) and a 70 Hz high-pass: the magnitude is untouched above
///    100 Hz, but Yelda's sharp glottal pulses are spread a little in time, 2 dB less peak for the same sound.
/// 3. A light compressor (1.5:1, 5 ms attack, 110 ms release) and a look-ahead limiter (5 ms, −1 dBFS): the gain each
///    sample needs is held over ±5 ms and averaged, so it never moves inside a pitch period.
///
/// About −16.4 LUFS, 2 dB over Voice Dream. Output lags input by `latency` samples; `flush()` pushes the tail out.
final class VoiceMaster {
    static let sampleRate = 48_000.0
    /// Extra dB with the music in the background and the voice in front (0…3); the compressor takes it, not the limiter.
    var boost: Float = 0

    // crackle repair: the band above 2.5 kHz, judged against the ±2 ms around each sample
    private let around: Int
    private let split: OpaquePointer, splitLow: OpaquePointer
    private var splitDelay: [Float], splitLowDelay: [Float]
    private var lowLine: [Float], highLine: [Float], energyLine: [Double]
    private var aroundPos = 0
    private var energy: Double = 0
    static let needle: Float = 6                // × the local level of the band (4 touched plain noise)
    private(set) var repaired = 0               // samples pulled back

    // tone
    private let tone: OpaquePointer
    private var toneDelay: [Float]

    // compressor (dB domain)
    private var detector: Float = 0
    private var reduction: Float = 0
    private var trim = VoiceMaster.makeUp       // make-up gain in use, eased towards makeUp + boost over 50 ms
    private let trimCoef: Float
    private let detectorCoef: Float, attackCoef: Float, releaseCoef: Float
    static let inputGain: Float = 4, threshold: Float = -24, ratio: Float = 1.5, knee: Float = 10, makeUp: Float = 2

    // limiter
    var ceiling: Float = 0.89                  // −1 dBFS
    private let look: Int
    private var line: [Float]
    private var linePos = 0
    private var dqIndex: [Int], dqValue: [Float]
    private var dqFront = 0, dqCount = 0
    private var held: [Float]
    private var heldPos = 0
    private var heldSum: Double
    private var envelope: Float = 1
    private let limiterRelease: Float
    private var t = 0

    var latency: Int { around + look }

    init() {
        let sr = Self.sampleRate
        around = Int(sr * 0.002)
        lowLine = [Float](repeating: 0, count: 2 * around + 1)
        highLine = lowLine
        energyLine = [Double](repeating: 0, count: 2 * around + 1)
        let crossover = [Biquad.highPass(2500, sr), Biquad.highPass(2500, sr)]     // Linkwitz–Riley, 24 dB/oct
        split = vDSP_biquad_CreateSetup(crossover.flatMap { $0 }, vDSP_Length(crossover.count))!
        splitDelay = [Float](repeating: 0, count: 2 * crossover.count + 2)
        // its matching low half: low + high is flat (an all-pass); "dry − high" was not, and turning the high band
        // down by 6 dB lifted 2.5 kHz by 1.8 dB instead, where the two halves are half a turn apart
        let lowHalf = [Biquad.lowPass(2500, sr), Biquad.lowPass(2500, sr)]
        splitLow = vDSP_biquad_CreateSetup(lowHalf.flatMap { $0 }, vDSP_Length(lowHalf.count))!
        splitLowDelay = [Float](repeating: 0, count: 2 * lowHalf.count + 2)
        look = Int(sr * 0.005)
        line = [Float](repeating: 0, count: look)
        dqIndex = [Int](repeating: 0, count: 2 * look + 2)
        dqValue = [Float](repeating: 1, count: 2 * look + 2)
        held = [Float](repeating: 1, count: look + 1)
        heldSum = Double(look + 1)
        limiterRelease = Float(exp(-1 / (0.06 * sr)))
        detectorCoef = Float(exp(-1 / (0.004 * sr)))
        attackCoef = Float(exp(-1 / (0.005 * sr)))
        releaseCoef = Float(exp(-1 / (0.11 * sr)))
        trimCoef = 1 - Float(exp(-1 / (0.05 * sr)))
        let stages: [[Double]] = [
            Biquad.allPass(150, sr), Biquad.allPass(250, sr), Biquad.allPass(400, sr), Biquad.allPass(700, sr),
            Biquad.highPass(70, sr),
        ]
        tone = vDSP_biquad_CreateSetup(stages.flatMap { $0 }, vDSP_Length(stages.count))!
        toneDelay = [Float](repeating: 0, count: 2 * stages.count + 2)
    }

    deinit { vDSP_biquad_DestroySetup(tone); vDSP_biquad_DestroySetup(split); vDSP_biquad_DestroySetup(splitLow) }

    /// Back to silence (a new reading position): the delay lines are emptied, the envelopes rest.
    func reset() {
        for i in splitDelay.indices { splitDelay[i] = 0 }
        for i in splitLowDelay.indices { splitLowDelay[i] = 0 }
        for i in lowLine.indices { lowLine[i] = 0; highLine[i] = 0; energyLine[i] = 0 }
        aroundPos = 0; energy = 0
        for i in toneDelay.indices { toneDelay[i] = 0 }
        detector = 0; reduction = 0; trim = Self.makeUp + boost
        for i in line.indices { line[i] = 0 }
        linePos = 0; dqFront = 0; dqCount = 0
        for i in held.indices { held[i] = 1 }
        heldPos = 0; heldSum = Double(look + 1); envelope = 1
    }

    /// The tail still inside (the last `latency` samples of what went in), pushed out by silence.
    func flush() -> [Float] { process([Float](repeating: 0, count: latency)) }

    /// A whole piece at once, aligned with its input (the delay taken off). Starts and ends on silence inside.
    func whole(_ x: [Float]) -> [Float] { Array((process(x) + flush()).dropFirst(latency)) }

    /// Same number of samples out as in, `latency` samples later.
    func process(_ input: [Float]) -> [Float] {
        guard !input.isEmpty else { return [] }
        let work = decrackle(input)
        var shaped = [Float](repeating: 0, count: work.count)
        vDSP_biquad(tone, &toneDelay, work, 1, &shaped, 1, vDSP_Length(work.count))
        return dynamics(shaped)
    }

    // MARK: crackle repair

    private func decrackle(_ x: [Float]) -> [Float] {
        var high = [Float](repeating: 0, count: x.count)
        vDSP_biquad(split, &splitDelay, x, 1, &high, 1, vDSP_Length(x.count))
        var low = [Float](repeating: 0, count: x.count)
        vDSP_biquad(splitLow, &splitLowDelay, x, 1, &low, 1, vDSP_Length(x.count))
        var y = [Float](repeating: 0, count: x.count)
        let span = lowLine.count                 // 2 · around + 1; the sample leaving is the one in the middle
        for i in 0..<x.count {
            let h = Double(high[i])
            energy += h * h - energyLine[aroundPos]
            energyLine[aroundPos] = h * h
            lowLine[aroundPos] = low[i]; highLine[aroundPos] = high[i]
            aroundPos = (aroundPos + 1) % span
            let mid = (aroundPos + around) % span
            let level = Float(max(energy, 0) / Double(span)).squareRoot()
            let limit = Self.needle * level + 1e-4
            let hc = highLine[mid]
            var kept = hc
            if abs(hc) > limit {
                // keep a quarter of the excess: the needle goes, the consonant stays
                let k = (abs(hc) - limit) * 0.25 + limit
                kept = hc < 0 ? -k : k
                repaired += 1
            }
            y[i] = lowLine[mid] + kept
        }
        return y
    }

    // MARK: compressor + look-ahead limiter

    private func dynamics(_ x: [Float]) -> [Float] {
        var y = [Float](repeating: 0, count: x.count)
        let gain0 = pow(10, Self.inputGain / 20)
        let slope = 1 / Self.ratio - 1
        let half = Self.knee / 2
        let target = Self.makeUp + boost
        let window = 2 * look + 1
        let cap = dqIndex.count
        for i in 0..<x.count {
            let v = x[i] * gain0
            detector = detector * detectorCoef + v * v * (1 - detectorCoef)
            let level = 10 * log10(detector + 1e-10)
            let over = level - Self.threshold
            let want: Float = over <= -half ? 0 : over >= half ? slope * over : slope * (over + half) * (over + half) / (2 * Self.knee)
            reduction = want < reduction ? want + (reduction - want) * attackCoef : want + (reduction - want) * releaseCoef
            trim += (target - trim) * trimCoef
            let c = v * pow(10, (reduction + trim) / 20)

            // limiter: the least gain any sample within ±5 ms of the one leaving needs, averaged over 5 ms
            let a = abs(c)
            let need = a > ceiling ? ceiling / a : 1
            while dqCount > 0, dqValue[(dqFront + dqCount - 1) % cap] >= need { dqCount -= 1 }
            dqIndex[(dqFront + dqCount) % cap] = t; dqValue[(dqFront + dqCount) % cap] = need; dqCount += 1
            while dqIndex[dqFront] <= t - window { dqFront = (dqFront + 1) % cap; dqCount -= 1 }
            let m = dqValue[dqFront]
            heldSum += Double(m - held[heldPos]); held[heldPos] = m; heldPos = (heldPos + 1) % held.count
            let s = min(1, Float(heldSum / Double(held.count)))
            envelope = s < envelope ? s : s + (envelope - s) * limiterRelease
            let out = line[linePos]
            line[linePos] = c; linePos = (linePos + 1) % look
            y[i] = out * envelope
            t += 1
        }
        return y
    }
}

/// RBJ biquad sections for vDSP ([b0, b1, b2, a1, a2] / a0).
enum Biquad {
    static func highPass(_ f0: Double, _ sr: Double, q: Double = 0.707) -> [Double] {
        let w = 2 * Double.pi * f0 / sr, alpha = sin(w) / (2 * q), cw = cos(w), a0 = 1 + alpha
        return [(1 + cw) / 2 / a0, -(1 + cw) / a0, (1 + cw) / 2 / a0, -2 * cw / a0, (1 - alpha) / a0]
    }

    static func lowPass(_ f0: Double, _ sr: Double, q: Double = 0.707) -> [Double] {
        let w = 2 * Double.pi * f0 / sr, alpha = sin(w) / (2 * q), cw = cos(w), a0 = 1 + alpha
        return [(1 - cw) / 2 / a0, (1 - cw) / a0, (1 - cw) / 2 / a0, -2 * cw / a0, (1 - alpha) / a0]
    }

    static func allPass(_ f0: Double, _ sr: Double, q: Double = 0.707) -> [Double] {
        let w = 2 * Double.pi * f0 / sr, alpha = sin(w) / (2 * q), cw = cos(w), a0 = 1 + alpha
        return [(1 - alpha) / a0, -2 * cw / a0, 1, -2 * cw / a0, (1 - alpha) / a0]
    }

    static func peak(_ f0: Double, q: Double, _ gain: Double, _ sr: Double) -> [Double] {
        let A = pow(10, gain / 40), w = 2 * Double.pi * f0 / sr, alpha = sin(w) / (2 * q), cw = cos(w)
        let a0 = 1 + alpha / A
        return [(1 + alpha * A) / a0, -2 * cw / a0, (1 - alpha * A) / a0, -2 * cw / a0, (1 - alpha / A) / a0]
    }

    static func shelf(low: Bool, _ f0: Double, _ gain: Double, _ sr: Double) -> [Double] {
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
}
