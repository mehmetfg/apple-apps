// Pitch change that keeps the formants (TD-PSOLA): the signal is cut at every glottal period and the periods are
// placed closer together or further apart; the colour of mouth and throat stays, the duration stays.
// Ema's measurement at −4 semitones: formant-envelope difference TimePitch 1.22 vs PSOLA 0.17; Whisper clean in both.
// Ported from Ema's Perde.swift, logic unchanged.
import Foundation
import Accelerate

enum PitchShift {
    static func shift(_ x: [Float], semitones: Double, sampleRate sr: Int = 48_000) -> [Float] {
        guard abs(semitones) >= 0.05, x.count > sr / 10 else { return x }
        let hop = sr / 200
        let f0 = f0Track(x, sr: sr, hop: hop)
        guard !f0.isEmpty else { return x }
        let factor = pow(2, semitones / 12)
        return resynthesize(x, f0: f0, hop: hop, sr: sr) { _ in factor }
    }

    /// Steadier intonation: every voiced period is moved toward the voice's middle pitch, so the rises and falls keep
    /// their direction but only `keep` of their size (0.7 = 30 % narrower), as Yelda's narrow melody (4.1 semitones
    /// between the 10th and 90th percentile) against Cem's 5.7. The middle is the median pitch of the piece; the
    /// formants and the duration stay. Small moves (under a semitone mostly), so PSOLA's grains stay clean.
    static func flatten(_ x: [Float], keep: Double, sampleRate sr: Int = 48_000) -> [Float] {
        guard keep < 0.99, x.count > sr / 10 else { return x }
        let hop = sr / 200
        let f0 = f0Track(x, sr: sr, hop: hop)
        let voiced = f0.filter { $0 > 0 }.sorted()
        guard voiced.count > 20 else { return x }
        let middle = voiced[voiced.count / 2]
        // per-frame factor, smoothed over ±25 ms so a period never jumps against its neighbour
        var raw = f0.map { $0 > 0 ? pow(middle / $0, 1 - keep) : 1 }
        let w = 5
        var smooth = raw
        for i in raw.indices where f0[i] > 0 {
            var s = 0.0, n = 0.0
            for k in max(0, i - w)...min(raw.count - 1, i + w) where f0[k] > 0 { s += raw[k]; n += 1 }
            smooth[i] = s / n
        }
        raw = smooth
        return resynthesize(x, f0: f0, hop: hop, sr: sr) { t in raw[min(t / hop, raw.count - 1)] }
    }

    /// TD-PSOLA with a pitch factor that may change along the signal (factor(sample) > 1 = higher).
    private static func resynthesize(_ x: [Float], f0: [Double], hop: Int, sr: Int, factor factorAt: (Int) -> Double) -> [Float] {
        func period(_ t: Double) -> Double? {
            let i = min(Int(t) / hop, f0.count - 1)
            return f0[i] > 0 ? Double(sr) / f0[i] : nil
        }
        func argMax(_ a: Int, _ b: Int, absolute: Bool) -> Int {
            var best = a, value = -Float.infinity
            for i in a..<b { let v = absolute ? abs(x[i]) : x[i]; if v > value { value = v; best = i } }
            return best
        }

        // analysis marks: one per period at the peak when voiced, every 5 ms when unvoiced
        var marks: [Int] = [], periods: [Double?] = []
        var t = 0.0
        while t < Double(x.count) {
            guard let p = period(t) else {
                marks.append(Int(t)); periods.append(nil); t += Double(hop); continue
            }
            let a = Int(t), b = Int(min(Double(x.count), t + p))
            if periods.isEmpty || periods.last! == nil { t = Double(b > a ? argMax(a, b, absolute: true) : a) }
            marks.append(Int(t)); periods.append(p)
            let nt = t + p
            let lo = Int(nt - p / 4), hi = Int(min(Double(x.count), nt + p / 4))
            t = hi > lo ? Double(argMax(lo, hi, absolute: false)) : nt
            if t <= Double(marks.last!) { t = Double(marks.last! + 1) }
        }

        // synthesis: place the marks at the new period, overlap-add two-period Hann grains
        var y = [Float](repeating: 0, count: x.count + sr / 10)
        var norm = [Float](repeating: 0, count: y.count)
        var ts = 0.0, j = 0
        while ts < Double(x.count) {
            while j + 1 < marks.count && abs(Double(marks[j + 1]) - ts) < abs(Double(marks[j]) - ts) { j += 1 }
            let m = marks[j]
            let L: Int, step: Double
            if let p = periods[j] { L = Int(p); step = p / factorAt(m) } else { L = hop; step = Double(hop) }
            let M = 2 * L + 1
            let a0 = max(0, m - L), a1 = min(x.count, m + L + 1)
            let o = Int(ts) - (m - a0)
            if o >= 0 {
                for i in a0..<a1 where o + i - a0 < y.count {
                    let k = i - (m - L)
                    let w = Float(0.5 - 0.5 * cos(2 * Double.pi * Double(k) / Double(M - 1)))
                    y[o + i - a0] += x[i] * w
                    norm[o + i - a0] += w
                }
            }
            ts += step
        }
        // level by grain density (window sum smoothed with a 10 ms box)
        let K = sr / 100
        var smooth = [Float](repeating: 0, count: norm.count)
        var sum: Float = 0
        for i in 0..<(norm.count + K / 2) {
            if i < norm.count { sum += norm[i] }
            if i - K >= 0 { sum -= norm[i - K] }
            let c = i - K / 2
            if c >= 0 && c < norm.count { smooth[c] = sum / Float(K) }
        }
        var output = [Float](repeating: 0, count: x.count)
        for i in 0..<x.count { output[i] = y[i] / max(smooth[i], 0.3) }
        return output
    }

    /// YIN pitch track on a signal reduced to 16 kHz; Hz for every `hop` (0 = silent or unvoiced).
    static func f0Track(_ x: [Float], sr: Int, hop: Int, fmin: Double = 70, fmax: Double = 400, threshold: Float = 0.15) -> [Double] {
        let k = 3, s = sr / k, h = hop / k
        var y = [Float](repeating: 0, count: (x.count + k - 1) / k)
        for i in 0..<y.count {
            let c = i * k
            let a = c > 0 ? x[c - 1] : 0, b = x[c], d = c + 1 < x.count ? x[c + 1] : 0
            y[i] = (a + b + d) / 3
        }
        let W = Int(Double(s) / fmin) + 1, tmin = Int(Double(s) / fmax), tmax = Int(Double(s) / fmin)
        let n = x.count / hop
        var f0 = [Double](repeating: 0, count: n)
        var energy: Float = 0
        for v in x { energy += v * v }
        let rms = (energy / Float(x.count)).squareRoot()
        let yp = y + [Float](repeating: 0, count: 2 * W + tmax)
        var d = [Float](repeating: 0, count: tmax + 1)
        var corr = [Float](repeating: 0, count: tmax + 1)
        // d[t] = Σ (y[a+q] − y[a+t+q])² = E(a) + E(a+t) − 2·Σ y[a+q]·y[a+t+q]: one vDSP correlation and a sliding
        // energy instead of the W × tmax double loop (the same numbers, about 40× less work on the phone).
        for i in 0..<n {
            let a = i * h
            var e: Float = 0
            yp.withUnsafeBufferPointer { vDSP_svesq($0.baseAddress! + a, 1, &e, vDSP_Length(W)) }
            if (e / Float(W)).squareRoot() < 0.06 * rms { continue }
            yp.withUnsafeBufferPointer { b in
                let base = b.baseAddress! + a
                vDSP_conv(base, 1, base, 1, &corr, 1, vDSP_Length(tmax + 1), vDSP_Length(W))
                var et = e
                for t in 0...tmax {
                    if t > 0 { et += base[t + W - 1] * base[t + W - 1] - base[t - 1] * base[t - 1] }
                    d[t] = max(0, e + et - 2 * corr[t])
                }
            }
            var cumulative: Float = 0
            var dn = [Float](repeating: 1, count: tmax + 1)
            for t in 1...tmax { cumulative += d[t]; dn[t] = d[t] * Float(t) / max(cumulative, 1e-12) }
            guard var t = (tmin...tmax).first(where: { dn[$0] < threshold }) else { continue }
            while t + 1 <= tmax && dn[t + 1] < dn[t] { t += 1 }
            f0[i] = Double(s) / Double(t)
        }
        var g = f0
        if n > 4 {
            for i in 2..<(n - 2) where f0[i] > 0 {
                let v = f0[(i - 2)...(i + 2)].filter { $0 > 0 }.sorted()
                if v.count >= 3 { g[i] = v.count % 2 == 1 ? v[v.count / 2] : (v[v.count / 2 - 1] + v[v.count / 2]) / 2 }
            }
        }
        return g
    }
}
