import AVFoundation

enum Ses {
    static let kimlik = "com.fatihgocgun.ema.ses.tr"
    static let ornekHizi: Double = 48_000
    /// İşaret konumu birimi: örnek başına bayt (Float32 tek kanal). Telefonda ölçülerek doğrulanır.
    static var isaretCarpani: Int { Ayar.isaretCarpani }

    static var sistemSesi: AVSpeechSynthesisProviderVoice {
        let ses = AVSpeechSynthesisProviderVoice(name: "Ema", identifier: kimlik,
                                                 primaryLanguages: ["tr-TR"], supportedLanguages: ["tr-TR"])
        ses.gender = .female
        ses.age = 30
        ses.version = "0.1"
        return ses
    }

    // Konuşma hızı SSML'de <prosody rate="150%"> olarak gelir.
    static func hiz(_ ssml: String) -> Double {
        guard let r = ssml.range(of: "rate=\"([0-9.]+)%\"", options: .regularExpression) else { return 1 }
        let sayi = ssml[r].filter { $0.isNumber || $0 == "." }
        return min(max((Double(sayi) ?? 100) / 100, 0.5), 4)
    }

    // <prosody pitch="…" volume="…">: yüzde, dB ya da anahtar kelime gelebilir.
    private static func nitelik(_ ssml: String, _ ad: String) -> String? {
        guard let r = ssml.range(of: ad + "=\"[^\"]*\"", options: .regularExpression) else { return nil }
        return String(ssml[r].dropFirst(ad.count + 2).dropLast())
    }

    private static func sayi(_ s: String) -> Double? {
        Double(s.filter { $0.isNumber || $0 == "." || $0 == "-" || $0 == "+" }.replacingOccurrences(of: "+", with: ""))
    }

    /// SSML'deki perde, yarım ton olarak (0 = değişiklik yok).
    static func perde(_ ssml: String) -> Double {
        guard let d = nitelik(ssml, "pitch") else { return 0 }
        let anahtar = ["x-low": -4.0, "low": -2, "medium": 0, "default": 0, "high": 2, "x-high": 4]
        if let k = anahtar[d] { return k }
        guard let v = sayi(d) else { return 0 }
        if d.hasSuffix("st") { return v }
        if d.hasSuffix("%") {
            let oran = (d.hasPrefix("+") || d.hasPrefix("-")) ? 1 + v / 100 : v / 100
            return oran > 0 ? 12 * log2(oran) : 0
        }
        return v > 0 && v < 4 ? 12 * log2(v) : 0  // çarpan (ör. 1.2)
    }

    /// SSML'deki ses yüksekliği, kat olarak (1 = değişiklik yok).
    static func yukseklik(_ ssml: String) -> Double {
        guard let d = nitelik(ssml, "volume") else { return 1 }
        let anahtar = ["silent": 0.0, "x-soft": 0.5, "soft": 0.7, "medium": 1, "default": 1, "loud": 1.3, "x-loud": 1.6]
        if let k = anahtar[d] { return k }
        guard let v = sayi(d) else { return 1 }
        if d.hasSuffix("dB") { return pow(10, v / 20) }
        if d.hasSuffix("%") { return (d.hasPrefix("+") || d.hasPrefix("-")) ? 1 + v / 100 : v / 100 }
        return v
    }

    /// SSML'den asıl konuşma metni: etiketler atılır, karakter varlıkları çözülür, boşluklara dokunulmaz.
    /// İmleç aralıkları bu metnin konumlarıyla verilir.
    static func konusmaMetni(_ ssml: String) -> String {
        var s = ssml.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (k, v) in ["&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'", "&amp;": "&"] {
            s = s.replacingOccurrences(of: k, with: v)
        }
        return s
    }

    // Sistem metni SSML olarak gönderir; etiketleri atıp düz metni alır.
    static func duzMetin(_ ssml: String) -> String {
        var s = ssml.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (k, v) in ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'"] {
            s = s.replacingOccurrences(of: k, with: v)
        }
        return s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
