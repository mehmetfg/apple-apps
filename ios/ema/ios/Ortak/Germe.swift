import Accelerate

// Hızlı dinleme için perdeyi koruyan zaman sıkıştırma (WSOLA).
// 2026-10-08 ölçümü (Whisper, cümle cümle, Kıymet önsözü): 360 k/dk'da kelime hatası
// hızı modele vermekle %85, Apple TimePitch ile %18, bununla %8. 420 k/dk'da %22.
// Pencere 25 ms, arama ±8 ms; 15–50 ms arası denendi, 20–25 ms en iyisi.
enum Germe {
    static func sikistir(_ x: [Float], tempo: Double, oran: Double = 48_000) -> [Float] {
        guard tempo > 1.01, x.count > 4096 else { return x }
        let N = Int(0.025 * oran) / 2 * 2, H = N / 2, T = Int(0.008 * oran)
        var pencere = [Float](repeating: 0, count: N)
        vDSP_hann_window(&pencere, vDSP_Length(N), Int32(vDSP_HANN_DENORM))
        let hedef = Int(Double(x.count) / tempo)
        var xp = x
        xp += [Float](repeating: 0, count: 2 * N + 2 * T)
        var y = [Float](repeating: 0, count: hedef + 2 * N)
        var norm = [Float](repeating: 0, count: hedef + 2 * N)
        let araUzunluk = 2 * T + 1
        var kor = [Float](repeating: 0, count: araUzunluk)
        var enerji = [Float](repeating: 0, count: araUzunluk)
        var onceki = 0, o = 0
        while o < hedef && onceki + N + T < x.count {
            let a = Int(Double(o) * tempo)
            var s = a
            if o > 0 {
                // Bir önceki parçanın doğal devamına en çok benzeyen yeri ±T içinde ara.
                let lo = max(0, a - T)
                let n = min(araUzunluk, a + T - lo + 1)
                xp.withUnsafeBufferPointer { b in
                    let dogal = b.baseAddress! + onceki + H
                    let bolge = b.baseAddress! + lo
                    vDSP_conv(bolge, 1, dogal, 1, &kor, 1, vDSP_Length(n), vDSP_Length(N))
                    // Kayan pencere enerjisi: ilk pencere + farklarla
                    var e: Float = 0
                    vDSP_svesq(bolge, 1, &e, vDSP_Length(N))
                    for k in 0..<n {
                        if k > 0 { e += bolge[k + N - 1] * bolge[k + N - 1] - bolge[k - 1] * bolge[k - 1] }
                        enerji[k] = max(e, 1e-9).squareRoot()
                    }
                }
                var enIyi = 0
                var deger = -Float.infinity
                for k in 0..<n where kor[k] / enerji[k] > deger { deger = kor[k] / enerji[k]; enIyi = k }
                s = lo + enIyi
            }
            for i in 0..<N {
                y[o + i] += xp[s + i] * pencere[i]
                norm[o + i] += pencere[i]
            }
            onceki = s
            o += H
        }
        var cikis = [Float](repeating: 0, count: hedef)
        for i in 0..<hedef { cikis[i] = norm[i] > 1e-3 ? y[i] / norm[i] : 0 }
        return cikis
    }
}
