import Foundation

// Üretilen her parçaya sırasıyla perde (TD-PSOLA, Perde.swift), hız (WSOLA, Germe.swift)
// ve ses yüksekliği uygular. Perde önce gelir: perde izi doğal hızdaki seste daha sağlam çıkar.
// Her parça kendi içinde biter; cümle sınırında taşan kuyruk yoktur.
final class Isleyici {
    private let perde: Double
    private let tempo: Double
    private let kazanc: Float
    private let oran: Double

    init(perdeYarimTon: Double, yukseklik: Double, tempo: Double = 1, oran: Double) {
        perde = min(max(perdeYarimTon, -8), 8)
        self.tempo = min(max(tempo, 1), 4)
        kazanc = Float(min(max(yukseklik, 0.25), 3))
        self.oran = oran
    }

    func isle(_ ornek: [Float]) -> [Float] {
        let p = Perde.kaydir(ornek, yarimTon: perde, oran: Int(oran))
        return sinirla(Germe.sikistir(p, tempo: tempo, oran: oran))
    }

    /// Aynısı, kelime uzunluklarını da yeni süreye göre ölçekler (imleç takibi için).
    func isle(_ ornek: [Float], kelimeler: [Int]) -> ([Float], [Int]) {
        let cikis = isle(ornek)
        guard !kelimeler.isEmpty, !ornek.isEmpty else { return (cikis, kelimeler) }
        let oran = Double(cikis.count) / Double(ornek.count)
        var yeni: [Int] = [], birikim = 0, onceki = 0
        for k in kelimeler {
            birikim += k
            let son = Int((Double(birikim) * oran).rounded())
            yeni.append(son - onceki)
            onceki = son
        }
        yeni[yeni.count - 1] += cikis.count - onceki
        return (cikis, yeni)
    }

    /// Akış arayüzüyle uyum için; işlenmemiş kuyruk kalmaz.
    func bitir() -> [Float] { [] }

    // Kazanç + yumuşak sınırlayıcı: ses yükseltilince tepeler kırpılıp cızırdamasın.
    private func sinirla(_ x: [Float]) -> [Float] {
        if kazanc == 1 { return x }
        return x.map { v in
            let y = v * kazanc, a = abs(y)
            return a <= 0.9 ? y : (y < 0 ? -1 : 1) * (0.9 + 0.1 * tanh((a - 0.9) / 0.1))
        }
    }
}
