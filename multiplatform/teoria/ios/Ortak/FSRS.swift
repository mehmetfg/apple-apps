// FSRS-4.5 — Aşina'daki çekirdeğin aynısı (Anki'nin varsayılan zamanlayıcısı), hedef hatırlama %90.
// Vault kuralı: vade borcu yok. Vade yalnız sıralama için kullanılır; "N kart bekliyor" hiçbir yerde gösterilmez.
import Foundation

enum Not: Int, Codable {
    case unuttum = 1, zor, iyi, kolay

    /// Alıştırma puanından (0…1) FSRS notu.
    static func puandan(_ p: Double) -> Not {
        switch p {
        case ..<0.35: .unuttum
        case ..<0.7: .zor
        case ..<0.95: .iyi
        default: .kolay
        }
    }
}

struct Kart: Codable, Hashable {
    var kararlilik: Double
    var zorluk: Double
    var son: Date
    var vade: Date
    var tekrar: Int
    var hata: Int

    /// Kararlılık 21 günü geçince kavram "oturmuş" sayılır (gökyüzünde parlak yıldız).
    var oturmus: Bool { kararlilik >= 21 }
    func hatirlama(_ an: Date = Date()) -> Double {
        FSRS.hatirlama(gun: max(0, an.timeIntervalSince(son) / 86_400), kararlilik: kararlilik)
    }
}

enum FSRS {
    static let w: [Double] = [0.4872, 1.4003, 3.7145, 13.8206, 5.1618, 1.2298, 0.8975, 0.031,
                              1.6474, 0.1367, 1.0461, 2.1072, 0.0793, 0.3246, 1.587, 0.2272, 2.8755]
    static let hedef = 0.9
    static let azalma = -0.5
    static let carpan = 19.0 / 81.0
    static let tavanGun = 365.0

    static func hatirlama(gun t: Double, kararlilik s: Double) -> Double {
        pow(1 + carpan * t / max(s, 0.01), azalma)
    }

    static func aralik(_ s: Double) -> Double {
        let g = s / carpan * (pow(hedef, 1 / azalma) - 1)
        return min(max(g, 1), tavanGun)
    }

    static func ilkZorluk(_ n: Not) -> Double { sinirla(w[4] - Double(n.rawValue - 3) * w[5]) }
    static func sinirla(_ d: Double) -> Double { min(max(d, 1), 10) }

    static func yeni(_ n: Not, an: Date) -> Kart {
        let s = w[n.rawValue - 1]
        let gun = n == .unuttum ? 1 : aralik(s).rounded()
        return Kart(kararlilik: s, zorluk: ilkZorluk(n), son: an, vade: an.gunBasi.gun(Int(gun)),
                    tekrar: 1, hata: n == .unuttum ? 1 : 0)
    }

    static func tekrar(_ k: Kart, _ n: Not, an: Date) -> Kart {
        var y = k
        let gecen = max(0, an.timeIntervalSince(k.son) / 86_400)
        // Aynı gün içindeki ikinci karşılaşma kararlılığı şişirmesin.
        if gecen < 0.5 {
            if n == .unuttum {
                y.hata += 1
                y.kararlilik = min(k.kararlilik, w[0])
                y.vade = an.gunBasi.gun(1)
            }
            y.son = an
            return y
        }
        let r = hatirlama(gun: gecen, kararlilik: k.kararlilik)
        let d = k.zorluk
        let d1 = d - w[6] * Double(n.rawValue - 3)
        y.zorluk = sinirla(w[7] * ilkZorluk(.kolay) + (1 - w[7]) * d1)
        if n == .unuttum {
            let s = w[11] * pow(d, -w[12]) * (pow(k.kararlilik + 1, w[13]) - 1) * exp(w[14] * (1 - r))
            y.kararlilik = min(max(s, 0.1), k.kararlilik)
            y.hata += 1
            y.vade = an.gunBasi.gun(1)
        } else {
            let ceza = n == .zor ? w[15] : 1
            let bonus = n == .kolay ? w[16] : 1
            let artis = exp(w[8]) * (11 - d) * pow(k.kararlilik, -w[9]) * (exp(w[10] * (1 - r)) - 1)
            y.kararlilik = k.kararlilik * (artis * ceza * bonus + 1)
            y.vade = an.gunBasi.gun(Int(aralik(y.kararlilik).rounded()))
        }
        y.son = an
        y.tekrar += 1
        return y
    }
}
