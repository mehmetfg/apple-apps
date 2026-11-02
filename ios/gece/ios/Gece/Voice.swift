// Short spoken cues in Turkish, quiet and slow, so the eyes can stay closed.
import AVFoundation
import UIKit

@MainActor
final class Voice {
    static let shared = Voice()
    private let synth = AVSpeechSynthesizer()
    private lazy var voice: AVSpeechSynthesisVoice? = {
        let tr = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("tr") }
        return tr.first { $0.quality == .premium } ?? tr.first { $0.quality == .enhanced } ?? tr.first
    }()

    func say(_ text: String) {
        guard Store.shared.voice else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers, .duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        synth.stopSpeaking(at: .word)
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        u.rate = 0.45
        u.volume = 0.8
        synth.speak(u)
    }

    func stop() { synth.stopSpeaking(at: .immediate) }

    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .soft) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
