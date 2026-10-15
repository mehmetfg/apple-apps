import AVFoundation

/// Bir ses motoru: metni 48 kHz sese çevirir, her model kelimesinin örnek sayısını da verir (imleç için).
protocol Seslendirici: AnyObject {
    var sozluk: Set<Unicode.Scalar> { get }
    func seslendirKelimeli(_ yazi: String, hiz: Double, devam: () -> Bool, teslim: ([Float], [Int]) -> Void) throws
}

extension Motor: Seslendirici {
    func seslendirKelimeli(_ yazi: String, hiz: Double, devam: () -> Bool, teslim: ([Float], [Int]) -> Void) throws {
        try seslendirKelimeli(yazi, hiz: hiz, tohum: 0, devam: devam, teslim: teslim)
    }
}

/// Uzantının sunduğu sesler ve hangi motorla çalıştıkları.
enum Sesler {
    enum Tur: Equatable { case ema, supertonic(String), piper(String) }

    struct Tanim {
        let ad: String
        let kimlik: String
        let cinsiyet: AVSpeechSynthesisVoiceGender
        let tur: Tur

        var sistemSesi: AVSpeechSynthesisProviderVoice {
            let v = AVSpeechSynthesisProviderVoice(name: ad, identifier: kimlik,
                                                   primaryLanguages: ["tr-TR"], supportedLanguages: ["tr-TR"])
            v.gender = cinsiyet
            v.version = "0.2"
            return v
        }
    }

    static let ema = Tanim(ad: "Ema", kimlik: Ses.kimlik, cinsiyet: .female, tur: .ema)

    /// Kurulu olanlar: Ema her zaman; Supertonic modeli ortak alandaysa on sesi.
    static var hepsi: [Tanim] {
        var l = [ema]
        if Supertonic.kurulu {
            for i in 1...5 {
                l.append(Tanim(ad: "Supertonic Kadın \(i)", kimlik: "com.fatihgocgun.ema.ses.st.F\(i)", cinsiyet: .female, tur: .supertonic("F\(i)")))
            }
            for i in 1...5 {
                l.append(Tanim(ad: "Supertonic Erkek \(i)", kimlik: "com.fatihgocgun.ema.ses.st.M\(i)", cinsiyet: .male, tur: .supertonic("M\(i)")))
            }
        }
        for (ad, gorunen) in [("dfki", "Piper Dfki"), ("fahrettin", "Piper Fahrettin"), ("fettah", "Piper Fettah")]
            where piperKurulu?(ad) ?? false {
            l.append(Tanim(ad: gorunen, kimlik: "com.fatihgocgun.ema.ses.piper.\(ad)", cinsiyet: .male, tur: .piper(ad)))
        }
        return l
    }

    /// Piper yalnız uzantıda derleniyor (espeak-ng); uzantı açılışta bu iki kancayı bağlar.
    static var piperKurulu: ((String) -> Bool)?
    static var piperYapici: ((String) -> Seslendirici?)?

    static func tanim(_ kimlik: String?) -> Tanim {
        guard let kimlik else { return ema }
        return hepsi.first { kimlik.hasSuffix($0.kimlik) } ?? ema
    }

    // Bellekte aynı anda tek ağır motor (uzantının sınırı ≈260 MB): ses değişince öbürü bırakılır.
    private static var acik: (Tur, Seslendirici)?
    private static let kilit = NSLock()

    static func motor(_ t: Tanim) -> Seslendirici? {
        kilit.lock(); defer { kilit.unlock() }
        if let (tur, m) = acik, tur == t.tur { return m }
        acik = nil
        switch t.tur {
        case .ema:
            guard let m = try? Motor() else { return nil }
            acik = (t.tur, m)
            return m
        case .supertonic(let stil):
            guard let m = try? Supertonic(stil: stil) else { return nil }
            acik = (t.tur, m)
            return m
        case .piper(let ad):
            guard let m = piperYapici?(ad) else { return nil }
            acik = (t.tur, m)
            return m
        }
    }
}

/// Örnek hızı dönüştürme (Supertonic 44,1 kHz → 48 kHz), AVAudioConverter en yüksek kalite.
enum Ornekleme {
    static func donustur(_ x: [Float], kaynak: Double, hedef: Double) -> [Float] {
        guard kaynak != hedef, !x.isEmpty,
              let gb = AVAudioFormat(standardFormatWithSampleRate: kaynak, channels: 1),
              let cb = AVAudioFormat(standardFormatWithSampleRate: hedef, channels: 1),
              let d = AVAudioConverter(from: gb, to: cb),
              let girdi = AVAudioPCMBuffer(pcmFormat: gb, frameCapacity: AVAudioFrameCount(x.count)) else { return x }
        d.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        girdi.frameLength = girdi.frameCapacity
        x.withUnsafeBufferPointer { girdi.floatChannelData![0].update(from: $0.baseAddress!, count: x.count) }
        let kap = AVAudioFrameCount(Double(x.count) * hedef / kaynak) + 1024
        guard let cikti = AVAudioPCMBuffer(pcmFormat: cb, frameCapacity: kap) else { return x }
        var verildi = false
        _ = d.convert(to: cikti, error: nil) { _, durum in
            if verildi { durum.pointee = .endOfStream; return nil }
            verildi = true
            durum.pointee = .haveData
            return girdi
        }
        return Array(UnsafeBufferPointer(start: cikti.floatChannelData![0], count: Int(cikti.frameLength)))
    }
}
