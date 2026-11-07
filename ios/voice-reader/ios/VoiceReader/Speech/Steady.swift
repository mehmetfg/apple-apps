// Kararlı ölçü: brings any rendered voice toward the steadiness measured in the user's Yelda (2026-11-06, from a
// screen recording of Wise Path reading with her: 143 Hz, the melody inside 3.7 semitones between the 10th and 90th
// percentile, every phrase's middle pitch within 0.3 semitones of the others, the level of every 400 ms within
// 2.3 dB, 91 % of the time speaking). An AI narrator (VoxCPM2) measured 9.2 semitones, 2.3 and 4.7 dB on the same
// scale; that movement is what the ear has to follow, and at 260–330 words a minute it tires.
//
// Measured on the Mac with this code: the AI narrator 9.2 → 4.7 semitones, phrases 2.25 → 0.93, level 4.7 → 2.1 dB;
// Cem 6.4 → 3.0, level 2.5 → 1.5; Yelda (Enhanced) 5.8 → 3.9. `keep` never goes under 0.45 by itself: with the
// resynthesis of 2026-11-06 (PitchShift: only voiced runs rebuilt, each on its own marks) Cem (Enhanced) at 330
// words a minute keeps its share of cleanly periodic frames down to there (41 % → 40 %; the version before lost
// most of them at 0.6, 41 % → 11 %, which is why the floor used to be 0.6).
import Foundation
import Accelerate

enum Steady {
    /// The melody's width the ear settles into (Yelda as the user listens to her: 3.7 semitones between the 10th and
    /// 90th percentile of the pitch).
    static let spread = 3.7

    /// Median pitch (Hz) and melody width (semitones, 10th–90th percentile) of a piece; nil when too little is voiced.
    static func melody(_ x: [Float], sampleRate sr: Int = 48_000) -> (hz: Double, spread: Double)? {
        let v = PitchShift.f0Track(x, sr: sr, hop: sr / 200).filter { $0 > 0 }.sorted()
        guard v.count > 60 else { return nil }
        let lo = v[v.count / 10], hi = v[v.count * 9 / 10]
        return (v[v.count / 2], 12 * log2(hi / lo))
    }

    /// How much of the melody to keep so that its width comes down to `target` (never less than `floor`).
    static func keep(for spread: Double, target: Double = Steady.spread, floor: Double = 0.45) -> Double {
        spread <= target ? 1 : max(floor, target / spread)
    }

    /// Even level: the loudness of the speaking parts, taken over 400 ms, is drawn toward its median by `strength`
    /// (0.75 = three quarters of the way), at most ±`limit` dB, moving over 150 ms; pauses keep the gain around them.
    /// A word is never shaped: the gain moves slower than a syllable.
    static func even(_ x: [Float], sampleRate sr: Double = 48_000, strength: Float = 0.75, limit: Float = 6) -> [Float] {
        let hop = Int(sr * 0.01), n = x.count / hop
        guard n > 60 else { return x }
        var e = [Float](repeating: 0, count: n)
        x.withUnsafeBufferPointer { p in
            for i in 0..<n { var s: Float = 0; vDSP_svesq(p.baseAddress! + i * hop, 1, &s, vDSP_Length(hop)); e[i] = s / Float(hop) }
        }
        let peak = e.sorted()[n * 95 / 100]
        guard peak > 1e-9 else { return x }
        let gate = peak * 0.001                              // 30 dB under the loud parts: below it nobody speaks
        // loudness over ±200 ms, counting only the frames that speak
        let w = 20
        var loud = [Float](repeating: -.infinity, count: n)
        for i in 0..<n {
            var s: Float = 0, c: Float = 0
            for k in max(0, i - w)...min(n - 1, i + w) where e[k] > gate { s += e[k]; c += 1 }
            if c >= 8, e[i] > gate { loud[i] = 10 * log10(s / c) }
        }
        let spoken = loud.filter { $0.isFinite }.sorted()
        guard spoken.count > 40 else { return x }
        let target = spoken[spoken.count / 2]
        var gain = [Float](repeating: 0, count: n)
        var last: Float = 0
        for i in 0..<n {
            if loud[i].isFinite { last = min(limit, max(-limit, strength * (target - loud[i]))) }
            gain[i] = last
        }
        // the gain of a pause's first frames comes from before it; smooth over ±150 ms (two passes of a box)
        for _ in 0..<2 {
            var g2 = gain
            let r = 15
            var s: Float = 0
            for k in 0...min(n - 1, r) { s += gain[k] }
            var c = min(n - 1, r) + 1
            for i in 0..<n {
                g2[i] = s / Float(c)
                if i + r + 1 < n { s += gain[i + r + 1]; c += 1 }
                if i - r >= 0 { s -= gain[i - r]; c -= 1 }
            }
            gain = g2
        }
        var y = x
        for i in 0..<x.count {
            let pos = Float(i) / Float(hop) - 0.5
            let k0 = max(0, min(n - 1, Int(pos.rounded(.down)))), k1 = min(n - 1, k0 + 1)
            let t = max(0, min(1, pos - Float(k0)))
            y[i] = x[i] * pow(10, (gain[k0] + (gain[k1] - gain[k0]) * t) / 20)
        }
        return y
    }
}
