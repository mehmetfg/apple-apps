// Pitch-preserving time compression for fast listening (WSOLA).
// Ema's measurement (Whisper, sentence by sentence, Kıymet preface) at 360 words a minute: word error with the speed
// given to the model 85 %, Apple TimePitch 18 %, this 8 %; at 420 words a minute 22 %. Window 25 ms, search ±8 ms
// (15–50 ms tried, 20–25 ms best). Ported from Ema's Germe.swift, logic unchanged.
import Accelerate

enum TimeStretch {
    static func compress(_ x: [Float], tempo: Double, sampleRate: Double = 48_000) -> [Float] {
        guard tempo > 1.01, x.count > 4096 else { return x }
        let N = Int(0.025 * sampleRate) / 2 * 2, H = N / 2, T = Int(0.008 * sampleRate)
        var window = [Float](repeating: 0, count: N)
        vDSP_hann_window(&window, vDSP_Length(N), Int32(vDSP_HANN_DENORM))
        let target = Int(Double(x.count) / tempo)
        var xp = x
        xp += [Float](repeating: 0, count: 2 * N + 2 * T)
        var y = [Float](repeating: 0, count: target + 2 * N)
        var norm = [Float](repeating: 0, count: target + 2 * N)
        let searchLength = 2 * T + 1
        var corr = [Float](repeating: 0, count: searchLength)
        var energy = [Float](repeating: 0, count: searchLength)
        var previous = 0, o = 0
        while o < target && previous + N + T < x.count {
            let a = Int(Double(o) * tempo)
            var s = a
            if o > 0 {
                // within ±T, find the place most like the natural continuation of the previous grain
                let lo = max(0, a - T)
                let n = min(searchLength, a + T - lo + 1)
                xp.withUnsafeBufferPointer { b in
                    let natural = b.baseAddress! + previous + H
                    let region = b.baseAddress! + lo
                    vDSP_conv(region, 1, natural, 1, &corr, 1, vDSP_Length(n), vDSP_Length(N))
                    var e: Float = 0                                    // sliding-window energy
                    vDSP_svesq(region, 1, &e, vDSP_Length(N))
                    for k in 0..<n {
                        if k > 0 { e += region[k + N - 1] * region[k + N - 1] - region[k - 1] * region[k - 1] }
                        energy[k] = max(e, 1e-9).squareRoot()
                    }
                }
                var best = 0
                var bestScore = -Float.infinity
                for k in 0..<n where corr[k] / energy[k] > bestScore { bestScore = corr[k] / energy[k]; best = k }
                s = lo + best
            }
            for i in 0..<N {
                y[o + i] += xp[s + i] * window[i]
                norm[o + i] += window[i]
            }
            previous = s
            o += H
        }
        var output = [Float](repeating: 0, count: target)
        for i in 0..<target { output[i] = norm[i] > 1e-3 ? y[i] / norm[i] : 0 }
        return output
    }
}
