import AVFoundation

/// İngilizce sesli okuma. Voice Dream ya da Fon çalıyorsa onları kesmez, yalnız kısar.
@MainActor
final class Ses: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = Ses()
    private let sentez = AVSpeechSynthesizer()
    private lazy var ses: AVSpeechSynthesisVoice? = {
        let adaylar = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "en-US" }
        return adaylar.first { $0.quality == .premium } ?? adaylar.first { $0.quality == .enhanced }
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }()

    override init() {
        super.init()
        sentez.delegate = self
    }

    func soyle(_ metin: String, yavas: Bool = false) {
        if sentez.isSpeaking { sentez.stopSpeaking(at: .immediate) }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let s = AVSpeechUtterance(string: metin.replacingOccurrences(of: "`", with: ""))
        s.voice = ses
        s.rate = yavas ? 0.38 : 0.48
        sentez.speak(s)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
