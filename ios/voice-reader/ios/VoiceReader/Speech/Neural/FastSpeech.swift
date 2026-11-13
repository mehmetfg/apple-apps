// Yüksek hız: speech shortened unevenly, so that it stays apart at 400–500 words a minute.
//
// A system voice asked for more than its clean speed (Yelda blurs after about 380 words a minute: the engine squeezes
// everything alike, and the consonants run into each other) is rendered at the clean speed and shortened here:
// pauses go to a small fixed length, steady vowels are squeezed the most, and the places that carry the words
// (consonants, bursts, the moves between sounds: fast spectral change, or much of the energy above 4 kHz) the least.
// Variable-rate WSOLA, pitch kept. Then the phrase ends are closed firmly again (`tighten`): squeezing shortens a
// word's tail but leaves its level, so sped-up words fade out instead of ending (measured 2026-11-06: 1.3 syllables
// to fall 15 dB against Yelda's own 0.8).
//
// Measured on the Mac, 2026-11-06 (studio/fast_speech.py, the same steps): Whisper cannot follow any voice above about
// 330 words a minute, so the audio was slowed back to 200 for it; the words were still there at 430–470 with every
// method (81–91 %) and a little less at 500, with no reliable difference between methods. The user's ear chose this
// one ("daha net"). So this is kept on the ear's word, not on a number.
import Accelerate
import Foundation

enum FastSpeech {
    /// Above this many words a minute a system voice is rendered at `cleanSpeed` and squeezed here.
    static let from = 385.0
    /// The speed the voice is rendered at (the engine's 0.81 step: 2.80 × 120 = 336 words a minute, Voice Dream's 330).
    static let cleanSpeed = 2.80

    struct Result {
        var samples: [Float]
        /// Input positions and where they went, both in samples, rising: to move word times.
        var marks: [(from: Int, to: Int)]
        /// Where the real pauses began before they were shortened (input samples): the phrase ends `tighten` closes.
        var phraseEnds: [Int] = []

        func moved(_ i: Int) -> Int {
            guard var lo = marks.indices.first else { return i }
            var hi = marks.count - 1
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if marks[mid].from <= i { lo = mid } else { hi = mid - 1 }
            }
            let a = marks[lo]
            guard lo + 1 < marks.count else { return min(samples.count, a.to) }
            let b = marks[lo + 1]
            let f = b.from > a.from ? Double(i - a.from) / Double(b.from - a.from) : 0
            return a.to + Int(Double(b.to - a.to) * min(max(f, 0), 1))
        }
    }

    /// `tempo` times shorter (2 = half as long).
    ///
    /// `uneven`: how much of the shortening may be uneven. A system voice comes here already at its clean speed and
    /// is shortened 1.15 to 1.5 times, all of it unevenly. A voice that comes at its natural pace (the neural voices:
    /// Elif, Kaan) needs 2.75 to 4.2 times: done all unevenly the steady vowels would go 5 to 12 times faster and
    /// the consonants 1.6 to 2.6, and above 3.6 times the time asked for could not be reached at all (measured on
    /// Elif from the phone, 2026-11-13: 3.9 asked, 3.6 given). With `uneven` 1.6 the first 1.6 times is uneven, as
    /// for Yelda, and the rest is the same for every sound. The time asked for is now always reached.
    static func squeeze(_ x: [Float], tempo: Double, sampleRate sr: Double = 48_000, shortPause: Double = 0.035,
                        longPause: Double = 0.10, spare: Float = 0.85, uneven: Double = .infinity) -> Result {
        let hop = Int(sr * 0.005), W = Int(sr * 0.02)
        guard tempo > 1.01, x.count > 4 * W else { return Result(samples: x, marks: [(0, 0), (x.count, x.count)]) }
        let (c, pause) = protect(x, sr: sr, hop: hop, window: W)
        let n = c.count
        var rate = [Double](repeating: 1, count: n)
        var phraseEnds: [Int] = []
        var i = 0
        while i < n {
            guard pause[i] else { i += 1; continue }
            var j = i
            while j < n, pause[j] { j += 1 }
            let length = Double(j - i) * Double(hop) / sr
            if length >= 0.15, i > 0 { phraseEnds.append(i * hop) }
            let r = max(1, length / (length >= 0.2 ? longPause : shortPause))
            for k in i..<j { rate[k] = r }
            i = j
        }
        let frame = Double(hop) / sr
        var fixed = 0.0
        for k in 0..<n where pause[k] { fixed += frame / rate[k] }
        let want = max(0.05, Double(x.count) / sr / tempo - fixed)
        // the part that is shortened unevenly (all of it unless `uneven` says less)
        let unevenWant = tempo > uneven ? max(want, Double(x.count) / sr / uneven - fixed) : want
        // speech: rate = S·(1 + (R − 1)·(1 − spare·c)); R so that the speech takes the uneven part's time, then S
        // (the same for every sound) for what is left, also when R reached its end before the time was met
        var lo = 1.0, hi = 12.0, R = 1.0
        func time(_ R: Double) -> Double {
            var t = 0.0
            for k in 0..<n where !pause[k] { t += frame / (1 + (R - 1) * Double(1 - spare * c[k])) }
            return t
        }
        for _ in 0..<40 {
            R = (lo + hi) / 2
            if time(R) > unevenWant { lo = R } else { hi = R }
        }
        let S = max(1, time(R) / want)
        for k in 0..<n where !pause[k] { rate[k] = S * (1 + (R - 1) * Double(1 - spare * c[k])) }

        // variable-rate WSOLA
        let N = W / 2 * 2, H = N / 2, T = Int(sr * 0.006)
        var window = [Float](repeating: 0, count: N)
        vDSP_hann_window(&window, vDSP_Length(N), Int32(vDSP_HANN_DENORM))
        let xp = x + [Float](repeating: 0, count: 2 * N + 2 * T)
        var y = [Float](repeating: 0, count: x.count + 2 * N)
        var norm = [Float](repeating: 0, count: y.count)
        let searchLength = 2 * T + 1
        var corr = [Float](repeating: 0, count: searchLength)
        var energy = [Float](repeating: 0, count: searchLength)
        var marks: [(from: Int, to: Int)] = []
        var a = 0.0, o = 0, previous = -1
        while Int(a) + N + T < x.count, o + N < y.count {
            var s = Int(a)
            if previous >= 0 {
                let low = max(0, s - T)
                let count = min(searchLength, s + T - low + 1)
                xp.withUnsafeBufferPointer { b in
                    let natural = b.baseAddress! + previous + H
                    let region = b.baseAddress! + low
                    vDSP_conv(region, 1, natural, 1, &corr, 1, vDSP_Length(count), vDSP_Length(N))
                    var e: Float = 0
                    vDSP_svesq(region, 1, &e, vDSP_Length(N))
                    for k in 0..<count {
                        if k > 0 { e += region[k + N - 1] * region[k + N - 1] - region[k - 1] * region[k - 1] }
                        energy[k] = max(e, 1e-9).squareRoot()
                    }
                }
                var best = 0
                var bestScore = -Float.infinity
                for k in 0..<count where corr[k] / energy[k] > bestScore { bestScore = corr[k] / energy[k]; best = k }
                s = low + best
            }
            for k in 0..<N {
                y[o + k] += xp[s + k] * window[k]
                norm[o + k] += window[k]
            }
            marks.append((Int(a), o))
            previous = s
            a += Double(H) * rate[min(Int(a) / hop, n - 1)]
            o += H
        }
        let length = o + H
        var out = [Float](repeating: 0, count: length)
        for k in 0..<length { out[k] = y[k] / max(norm[k], 1e-3) }
        marks.append((x.count, length))
        return Result(samples: out, marks: marks, phraseEnds: phraseEnds)
    }

    /// Per 5 ms: how much a place carries the words (0 = a steady vowel, 1 = a consonant or a move between sounds),
    /// and whether it is a pause (35 dB under the loud parts).
    private static func protect(_ x: [Float], sr: Double, hop: Int, window W: Int) -> ([Float], [Bool]) {
        let size = 1024, half = size / 2, log2n = vDSP_Length(10)
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return ([], []) }
        defer { vDSP_destroy_fftsetup(setup) }
        var hann = [Float](repeating: 0, count: W)
        vDSP_hann_window(&hann, vDSP_Length(W), Int32(vDSP_HANN_DENORM))
        let n = (x.count - W) / hop + 1
        var db = [Float](repeating: 0, count: n), flux = [Float](repeating: 0, count: n), hf = [Float](repeating: 0, count: n)
        var frame = [Float](repeating: 0, count: size)
        var real = [Float](repeating: 0, count: half), imag = [Float](repeating: 0, count: half)
        var mags = [Float](repeating: 0, count: half), last = [Float](repeating: 0, count: half), logm = [Float](repeating: 0, count: half)
        let cut = Int(4000 / (sr / Double(size)))
        for f in 0..<n {
            x.withUnsafeBufferPointer { vDSP_vmul($0.baseAddress! + f * hop, 1, hann, 1, &frame, 1, vDSP_Length(W)) }
            real.withUnsafeMutableBufferPointer { rp in
                imag.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    frame.withUnsafeBufferPointer { p in
                        p.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half)) }
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(half))
                }
            }
            mags[0] = mags[1]
            var total: Float = 0, high: Float = 0, change: Float = 0
            for k in 0..<half {
                total += mags[k]
                if k >= cut { high += mags[k] }
                logm[k] = 0.5 * log(mags[k] + 1e-9)
                if f > 0 { let d = logm[k] - last[k]; change += d * d }
            }
            db[f] = 10 * log10(total / Float(half) + 1e-12)
            hf[f] = high / max(total, 1e-12)
            flux[f] = (change / Float(half)).squareRoot()
            swap(&last, &logm)
        }
        let ref = db.sorted()[min(n - 1, n * 95 / 100)]
        let pause = db.map { $0 < ref - 35 }
        let speaking = zip(flux, pause).filter { !$0.1 }.map(\.0).sorted()
        let scale = (speaking.isEmpty ? 1 : speaking[min(speaking.count - 1, speaking.count * 9 / 10)]) + 1e-9
        var c = [Float](repeating: 0, count: n)
        for f in 0..<n { c[f] = min(1, max(0, max(flux[f] / scale, (hf[f] - 0.15) / 0.3))) }
        var smooth = c
        for f in 0..<n {                                    // ±10 ms: the edges of a consonant count too
            var s: Float = 0
            for k in -2...2 { let q = f + k; if q >= 0, q < n { s += c[q] } }
            smooth[f] = s / 5
        }
        return (smooth, pause)
    }

    /// Firm endings: where a phrase runs into a pause, the fall after its last syllable's peak is made steeper
    /// (never more than 2.2 times, never more than 13 dB of extra cut, and less where the sound is a fricative or a
    /// burst, so the last consonant stays). Nothing moves in time. `target`: seconds for the level to fall 15 dB
    /// (0.8 of a syllable at the speed heard).
    ///
    /// `ends`: samples where a real pause began before `squeeze` shortened it. After the squeeze no pause inside a
    /// paragraph is longer than 100 ms, so the 150 ms rule below found only the end of the piece and the phrase ends
    /// in between were left fading (2026-11-10); with `ends` they are closed too, and a stop consonant's short
    /// silence inside a word is still not taken for an ending.
    static func tighten(_ x: [Float], target: Double, sampleRate sr: Double = 48_000, maxFactor: Float = 2.2, maxCut: Float = 13,
                        ends: [Int] = []) -> [Float] {
        let win = Int(sr * 0.01), hop = Int(sr * 0.005)
        guard x.count > Int(sr) / 4 else { return x }
        let n = (x.count - win) / hop + 1
        // energy above 4 kHz (a second-order high-pass)
        let w0 = 2 * Double.pi * 4000 / sr, alpha = sin(w0) / (2 * 0.7071), cw = cos(w0), a0 = 1 + alpha
        let b0 = Float((1 + cw) / 2 / a0), b1 = Float(-(1 + cw) / a0), b2 = b0, a1 = Float(-2 * cw / a0), a2 = Float((1 - alpha) / a0)
        var high = [Float](repeating: 0, count: x.count)
        var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0
        for i in x.indices {
            let v = b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x[i]; y2 = y1; y1 = v
            high[i] = v
        }
        var db = [Float](repeating: 0, count: n), fric = [Float](repeating: 0, count: n)
        for f in 0..<n {
            var e: Float = 0, h: Float = 0
            x.withUnsafeBufferPointer { vDSP_svesq($0.baseAddress! + f * hop, 1, &e, vDSP_Length(win)) }
            high.withUnsafeBufferPointer { vDSP_svesq($0.baseAddress! + f * hop, 1, &h, vDSP_Length(win)) }
            db[f] = 10 * log10(e / Float(win) + 1e-10)
            fric[f] = min(1, max(0, (h / max(e, 1e-10) - 0.2) / 0.3))
        }
        let ref = db.sorted()[min(n - 1, n * 95 / 100)]
        let ms = Double(hop) / sr * 1000, targetMs = target * 1000
        let need = Int(150 / ms)
        let known = ends.map { $0 / hop }.sorted()
        /// A quiet run starting at frame `f` is one of the known phrase ends (within 40 ms).
        func isEnd(_ f: Int) -> Bool {
            guard !known.isEmpty else { return false }
            var lo = 0, hi = known.count - 1
            while lo < hi { let mid = (lo + hi) / 2; if known[mid] < f { lo = mid + 1 } else { hi = mid } }
            let near = Int(40 / ms)
            return abs(known[lo] - f) <= near || (lo > 0 && abs(known[lo - 1] - f) <= near)
        }
        var extra = [Float](repeating: 0, count: n)
        var any = false
        var i = 1
        while i < n {
            guard db[i] < ref - 32, db[i - 1] >= ref - 32 else { i += 1; continue }
            var j = i
            while j < n, db[j] < ref - 32 { j += 1 }
            defer { i = max(j, i + 1) }
            guard j - i >= need || j == n || (j - i >= 4 && isEnd(i)) else { continue }
            let low = max(0, i - Int(250 / ms))
            var q = low
            for k in low..<i where db[k] > db[q] { q = k }
            let top = db[q]
            let end = min(n, i + Int(60 / ms))
            guard end - q > 2 else { continue }
            var fall = [Float](repeating: 0, count: end - q)
            for k in q..<end {
                let a = db[max(q, k - 1)], b = db[k], c = db[min(end - 1, k + 1)]
                fall[k - q] = min(0, max(min(a, b), min(max(a, b), c)) - top)          // median of three
            }
            let t15 = Double(fall.firstIndex { $0 <= -15 } ?? fall.count) * ms
            guard t15 > targetMs * 1.15 else { continue }
            let factor = min(maxFactor, Float(t15 / targetMs))
            var lastCut: Float = 0
            for k in q..<end {
                lastCut = max(-maxCut, (factor - 1) * fall[k - q] * (1 - 0.8 * fric[k]))
                extra[k] = min(extra[k], lastCut)
            }
            let back = min(n, end + Int(40 / ms))                                      // in the silence the cut lets go
            if back > end { for k in end..<back { extra[k] = lastCut * (1 - Float(k - end) / Float(back - end)) } }
            any = true
        }
        guard any else { return x }
        var smooth = extra
        for f in 1..<(n - 1) { smooth[f] = (extra[f - 1] + extra[f] + extra[f + 1]) / 3 }
        var out = x
        let centre = win / 2
        for s in x.indices {
            let p = Double(s - centre) / Double(hop)
            let f0 = min(n - 1, max(0, Int(p.rounded(.down)))), f1 = min(n - 1, f0 + 1)
            let t = Float(min(1, max(0, p - Double(f0))))
            let g = smooth[f0] + (smooth[f1] - smooth[f0]) * t
            if g < -0.01 { out[s] *= pow(10, g / 20) }
        }
        return out
    }

    /// Seconds a phrase's end should take to fall 15 dB at `wordsPerMinute`: 0.8 of a syllable (Turkish: about
    /// 2.8 syllables a word).
    static func closing(at wordsPerMinute: Double) -> Double { 0.8 * 60 / (2.8 * max(wordsPerMinute, 60)) }
}
