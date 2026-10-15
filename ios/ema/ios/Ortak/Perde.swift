import Foundation

// Formantları koruyarak perde değiştirme (TD-PSOLA). Ses her titreşim periyodunda yakalanır,
// periyotlar sıklaştırılır/seyreltilir; ağız-gırtlak rengi (formantlar) yerinde kalır, süre değişmez.
// 2026-10-08 ölçümü, −4 yarım ton: formant zarfı farkı TimePitch 1,22 · PSOLA 0,17; Whisper ikisinde de hatasız.
// Python eşi: scratchpad psola.py (deney), mantık birebir.
enum Perde {
    static func kaydir(_ x: [Float], yarimTon: Double, oran sr: Int = 48_000) -> [Float] {
        guard abs(yarimTon) >= 0.05, x.count > sr / 10 else { return x }
        let hop = sr / 200
        let f0 = f0Izi(x, sr: sr, hop: hop)
        guard !f0.isEmpty else { return x }
        let carpan = pow(2, yarimTon / 12)
        func periyot(_ t: Double) -> Double? {
            let i = min(Int(t) / hop, f0.count - 1)
            return f0[i] > 0 ? Double(sr) / f0[i] : nil
        }
        func enBuyuk(_ a: Int, _ b: Int, mutlak: Bool) -> Int {
            var en = a, d = -Float.infinity
            for i in a..<b { let v = mutlak ? abs(x[i]) : x[i]; if v > d { d = v; en = i } }
            return en
        }

        // Analiz işaretleri: ötümlüde periyot periyot tepe, ötümsüzde 5 ms aralık.
        var konum: [Int] = [], per: [Double?] = []
        var t = 0.0
        while t < Double(x.count) {
            guard let p = periyot(t) else {
                konum.append(Int(t)); per.append(nil); t += Double(hop); continue
            }
            let a = Int(t), b = Int(min(Double(x.count), t + p))
            if per.isEmpty || per.last! == nil { t = Double(b > a ? enBuyuk(a, b, mutlak: true) : a) }
            konum.append(Int(t)); per.append(p)
            let nt = t + p
            let lo = Int(nt - p / 4), hi = Int(min(Double(x.count), nt + p / 4))
            t = hi > lo ? Double(enBuyuk(lo, hi, mutlak: false)) : nt
            if t <= Double(konum.last!) { t = Double(konum.last! + 1) }
        }

        // Sentez: işaretleri yeni periyotla yerleştir, iki periyotluk Hann parçalarını üst üste ekle.
        var y = [Float](repeating: 0, count: x.count + sr / 10)
        var nrm = [Float](repeating: 0, count: y.count)
        var ts = 0.0, j = 0
        while ts < Double(x.count) {
            while j + 1 < konum.count && abs(Double(konum[j + 1]) - ts) < abs(Double(konum[j]) - ts) { j += 1 }
            let m = konum[j]
            let L: Int, adim: Double
            if let p = per[j] { L = Int(p); adim = p / carpan } else { L = hop; adim = Double(hop) }
            let M = 2 * L + 1
            let a0 = max(0, m - L), a1 = min(x.count, m + L + 1)
            let o = Int(ts) - (m - a0)
            if o >= 0 {
                for i in a0..<a1 where o + i - a0 < y.count {
                    let k = i - (m - L)
                    let w = Float(0.5 - 0.5 * cos(2 * Double.pi * Double(k) / Double(M - 1)))
                    y[o + i - a0] += x[i] * w
                    nrm[o + i - a0] += w
                }
            }
            ts += adim
        }
        // Genliği periyot yoğunluğuna göre dengele (10 ms kutu süzgeciyle yumuşatılmış pencere toplamı).
        let K = sr / 100
        var duz = [Float](repeating: 0, count: nrm.count)
        var top: Float = 0
        for i in 0..<(nrm.count + K / 2) {
            if i < nrm.count { top += nrm[i] }
            if i - K >= 0 { top -= nrm[i - K] }
            let c = i - K / 2
            if c >= 0 && c < nrm.count { duz[c] = top / Float(K) }
        }
        var cikis = [Float](repeating: 0, count: x.count)
        for i in 0..<x.count { cikis[i] = y[i] / max(duz[i], 0.3) }
        return cikis
    }

    /// YIN perde izi, 16 kHz'e indirilmiş sinyalde; her `hop` için Hz (0 = sessiz/ötümsüz).
    static func f0Izi(_ x: [Float], sr: Int, hop: Int, fmin: Double = 70, fmax: Double = 400, esik: Float = 0.15) -> [Double] {
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
        var kare: Float = 0
        for v in x { kare += v * v }
        let rms = (kare / Float(x.count)).squareRoot()
        let yp = y + [Float](repeating: 0, count: 2 * W + tmax)
        var d = [Float](repeating: 0, count: tmax + 1)
        for i in 0..<n {
            let a = i * h
            var e: Float = 0
            for q in 0..<W { e += yp[a + q] * yp[a + q] }
            if (e / Float(W)).squareRoot() < 0.06 * rms { continue }
            for t in 0...tmax {
                var top: Float = 0
                for q in 0..<W { let f = yp[a + q] - yp[a + t + q]; top += f * f }
                d[t] = top
            }
            var birikim: Float = 0
            var dn = [Float](repeating: 1, count: tmax + 1)
            for t in 1...tmax { birikim += d[t]; dn[t] = d[t] * Float(t) / max(birikim, 1e-12) }
            guard var t = (tmin...tmax).first(where: { dn[$0] < esik }) else { continue }
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
