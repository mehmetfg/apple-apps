import Foundation

// Ön sınama üreticisi: model yok, her kelime için kısa bir bip.
// Kelime sayısı duyulursa metnin uzantıya ulaştığı anlaşılır. Sonraki adımda yerine EMA motoru gelir.
enum Uretici {
    static func uret(_ metin: String) -> [Float] {
        let kelimeler = metin.split(whereSeparator: \.isWhitespace)
        let hiz = Ses.ornekHizi
        let bip = Int(0.12 * hiz), bosluk = Int(0.10 * hiz)
        var cikis: [Float] = []
        cikis.reserveCapacity(kelimeler.count * (bip + bosluk))
        for (i, k) in kelimeler.enumerated() {
            let frekans = 520.0 + Double(k.count % 6) * 60.0 + (i % 2 == 0 ? 0 : 40)
            for n in 0..<bip {
                let zarf = min(1, Double(n) / 240, Double(bip - n) / 240)
                cikis.append(Float(0.3 * zarf * sin(2 * .pi * frekans * Double(n) / hiz)))
            }
            cikis.append(contentsOf: repeatElement(0, count: bosluk))
        }
        return cikis
    }
}
