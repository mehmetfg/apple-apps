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
    /// `toward`: the pitch to draw the melody to instead of the piece's own middle (a whole book's middle, so that
    /// its pieces also come to the same height: the studio packs).
    static func flatten(_ x: [Float], keep: Double, toward: Double? = nil, sampleRate sr: Int = 48_000) -> [Float] {
        guard keep < 0.99, x.count > sr / 10 else { return x }
        let hop = sr / 200
        // the tidied track (holes of up to 15 ms inside a vowel closed), the same one the resynthesis walks: with the
        // raw track the closed holes kept factor 1, a 5–15 ms step back to the old pitch in the middle of a vowel
        let f0 = tidy(f0Track(x, sr: sr, hop: hop))
        let voiced = f0.filter { $0 > 0 }.sorted()
        guard voiced.count > 20 else { return x }
        let middle = toward ?? voiced[voiced.count / 2]
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
    ///
    /// Only the voiced runs are rebuilt; everything else is the input itself, sample for sample. Each run starts on
    /// its own first pitch mark and its grains reach from the mark before to the mark after (two half windows that add
    /// up to one), so with a factor of 1 the output is the input, and at the run's two ends the rebuilt sound meets the
    /// untouched sound on the same samples. The version before this one ran one synthesis clock over the whole piece:
    /// at every word start the first grain was laid down twice and the word came about 5 ms late, with a copy of it
    /// in the silence before (measured on Cem at 330 words a minute, 2026-11-06: 20 ms level changes of 10 to 13 dB
    /// with no pitch change asked at all). That was the break between words.
    private static func resynthesize(_ x: [Float], f0 raw: [Double], hop: Int, sr: Int, factor factorAt: (Int) -> Double) -> [Float] {
        let f0 = tidy(raw)
        var out = x
        var i = 0
        while i < f0.count {
            guard f0[i] > 0 else { i += 1; continue }
            var j = i
            while j < f0.count, f0[j] > 0 { j += 1 }
            var next = j
            while next < f0.count, f0[next] == 0 { next += 1 }
            rebuild(x, into: &out, from: i * hop, to: min(j * hop, x.count), limit: next < f0.count ? next * hop : x.count,
                    f0: f0, hop: hop, sr: sr, factor: factorAt)
            i = j
        }
        return out
    }

    /// Holes of up to 15 ms inside a vowel are closed and voiced islands under 20 ms are dropped, so a run is a whole
    /// syllable and not pieces of one.
    private static func tidy(_ f: [Double]) -> [Double] {
        var g = f
        var i = 0
        while i < g.count {
            guard g[i] == 0 else { i += 1; continue }
            var j = i
            while j < g.count, g[j] == 0 { j += 1 }
            if i > 0, j < g.count, j - i <= 3, max(g[i - 1], g[j]) / min(g[i - 1], g[j]) < 1.25 {
                for k in i..<j { g[k] = g[i - 1] + (g[j] - g[i - 1]) * Double(k - i + 1) / Double(j - i + 1) }
            }
            i = j
        }
        i = 0
        while i < g.count {
            guard g[i] > 0 else { i += 1; continue }
            var j = i
            while j < g.count, g[j] > 0 { j += 1 }
            if j - i < 4 { for k in i..<j { g[k] = 0 } }
            i = j
        }
        return g
    }

    private static func rebuild(_ x: [Float], into out: inout [Float], from a: Int, to b: Int, limit: Int, f0: [Double], hop: Int, sr: Int,
                                factor factorAt: (Int) -> Double) {
        func period(_ t: Int) -> Double { let v = f0[min(t / hop, f0.count - 1)]; return v > 0 ? Double(sr) / v : 0 }
        let p0 = period(a)
        guard p0 > 0, b - a > Int(3 * p0) else { return }
        // the side of the wave with the stronger peaks carries the marks
        var up: Float = 0, down: Float = 0
        for i in a..<min(b, a + Int(2 * p0)) { up = max(up, x[i]); down = max(down, -x[i]) }
        let sign: Float = up >= down ? 1 : -1
        func peak(_ lo: Int, _ hi: Int) -> Int {
            var best = lo, value = -Float.infinity
            for i in lo..<hi where sign * x[i] > value { value = sign * x[i]; best = i }
            return best
        }
        var m = [peak(a, min(b, a + Int(p0)))]
        while true {
            let p = period(m.last!)
            guard p > 0 else { break }
            let next = Double(m.last!) + p
            let lo = max(m.last! + 1, Int(next - p / 4)), hi = min(x.count, Int(next + p / 4) + 1)
            guard lo < hi, lo < b else { break }
            m.append(peak(lo, hi))
        }
        // the voice goes on a little after the last frame the tracker called voiced: follow it while one period
        // still looks like the one before, so the end of the syllable is rebuilt with the rest of it
        let reach = min(x.count, b + 6 * hop, limit)
        while m.count >= 2 {
            let p = m[m.count - 1] - m[m.count - 2], c = m[m.count - 1]
            guard p > 0, c + p + p / 4 < reach, c - p >= 0 else { break }
            let next = peak(c + p - p / 4, c + p + p / 4 + 1)
            var ab: Float = 0, aa: Float = 0, bb: Float = 0
            for i in 0..<p { let u = x[c - p + i], v = x[next - p + i]; ab += u * v; aa += u * u; bb += v * v }
            guard ab > 0.5 * (aa * bb).squareRoot(), bb > 0.03 * aa else { break }
            m.append(next)
        }
        let n = m.count - 1
        guard n >= 3 else { return }
        func gap(_ k: Int) -> Int { k < n ? m[k + 1] - m[k] : m[n] - m[n - 1] }

        // where the grains go: one local period apart, divided by the factor
        var at: [Double] = []
        var ts = Double(m[0]), k = 0
        while true {
            while k < n, abs(Double(m[k + 1]) - ts) < abs(Double(m[k]) - ts) { k += 1 }
            at.append(ts)
            let step = Double(gap(k)) / factorAt(m[k])
            if ts + step > Double(m[n]) + step / 2 { break }
            ts += step
        }
        // the last grain on the last mark when that asks for a stretch of a few per cent at most
        let span = at.last! - at[0], want = Double(m[n] - m[0])
        var closed = false
        if span > 0, abs(want / span - 1) <= 0.06 {
            for q in at.indices { at[q] = at[0] + (at[q] - at[0]) * want / span }
            closed = true
        }

        let first = max(0, m[0] - gap(0)), last = min(x.count - 1, Int(at.last!) + gap(n) + 1)
        var y = [Float](repeating: 0, count: last - first + 1)
        var norm = y
        k = 0
        for (q, t) in at.enumerated() {
            while k < n, abs(Double(m[k + 1]) - t) < abs(Double(m[k]) - t) { k += 1 }
            let g = closed && q == at.count - 1 ? n : k
            let left = g > 0 ? m[g] - m[g - 1] : gap(0), right = gap(g)
            let c = Int(t.rounded())
            for d in -left...right {
                let src = m[g] + d, dst = c + d - first
                guard src >= 0, src < x.count, dst >= 0, dst < y.count else { continue }
                let w = Float(0.5 + 0.5 * cos(Double.pi * Double(d) / Double(d < 0 ? left : right)))
                y[dst] += x[src] * w
                norm[dst] += w
            }
        }
        // inside the run the grains alone; at its two ends they cross into the sound that was there
        let inner = m[0]...Int(at.last!.rounded())
        for i in first...last {
            let w = norm[i - first]
            if inner.contains(i) { out[i] = y[i - first] / max(w, 0.3) }
            else { out[i] = y[i - first] + (1 - min(w, 1)) * out[i] }
        }
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
