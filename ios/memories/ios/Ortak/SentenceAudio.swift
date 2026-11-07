// Widget buttons for the "Cümle cümle" widget (iOS 17 interactive widgets).
//   · PreviousSentence / NextSentence: move one sentence; only the shared index changes, the widget redraws.
//   · SpeakSentence: AudioPlaybackIntent — the system runs it in the app's own process, so the sentence plays
//     without opening the app (Info.plist has the `audio` background mode). It plays the sentence's range from the
//     day's package audio (the same Kokoro voice as Dinle); if the audio is not on the phone, the device voice reads it.
import AppIntents
import AVFoundation
import WidgetKit

struct PreviousSentence: AppIntent {
    static var title: LocalizedStringResource = "Önceki cümle"
    static var description = IntentDescription("Cümle cümle widget'ında bir önceki cümleye geçer.")
    func perform() async throws -> some IntentResult {
        Paylasim.moveSentence(-1)
        WidgetCenter.shared.reloadTimelines(ofKind: Paylasim.sentenceKind)
        return .result()
    }
}

struct NextSentence: AppIntent {
    static var title: LocalizedStringResource = "Sonraki cümle"
    static var description = IntentDescription("Cümle cümle widget'ında sıradaki cümleye geçer.")
    func perform() async throws -> some IntentResult {
        Paylasim.moveSentence(1)
        WidgetCenter.shared.reloadTimelines(ofKind: Paylasim.sentenceKind)
        return .result()
    }
}

struct SpeakSentence: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Cümleyi seslendir"
    static var description = IntentDescription("Günün metnindeki cümleyi paketin sesiyle okur; uygulama açılmaz.")

    @Parameter(title: "Gün") var day: Int
    @Parameter(title: "Cümle") var index: Int
    @Parameter(title: "Sonra ilerle") var advance: Bool

    init() {}
    init(day: Int, index: Int, advance: Bool = false) {
        self.day = day
        self.index = index
        self.advance = advance
    }

    func perform() async throws -> some IntentResult {
        await SentencePlayer.shared.play(day: day, index: index)
        if advance {
            Paylasim.moveSentence(1)
            WidgetCenter.shared.reloadTimelines(ofKind: Paylasim.sentenceKind)
        }
        return .result()
    }
}

/// A row of the day's list in the largest widget: makes that sentence current and plays it.
struct PlayDaySentence: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Listeden cümle seç"
    static var description = IntentDescription("Günün listesindeki cümleye geçer ve okur; uygulama açılmaz.")

    @Parameter(title: "Gün") var day: Int
    @Parameter(title: "Cümle") var index: Int
    @Parameter(title: "Sıra") var position: Int

    init() {}
    init(day: Int, index: Int, position: Int) {
        self.day = day
        self.index = index
        self.position = position
    }

    func perform() async throws -> some IntentResult {
        Paylasim.selectSentence(position)
        WidgetCenter.shared.reloadTimelines(ofKind: Paylasim.sentenceKind)
        await SentencePlayer.shared.play(day: day, index: index)
        return .result()
    }
}

/// Plays one sentence: its range in the package audio, or the device voice as a fallback.
@MainActor
final class SentencePlayer: NSObject {
    static let shared = SentencePlayer()
    /// Posted before a sentence plays, so the app's own player pauses (two voices must not overlap).
    static let willPlay = Notification.Name("memories.sentence.willPlay")

    private var player: AVAudioPlayer?
    private let synth = AVSpeechSynthesizer()
    private var token = 0

    func play(day: Int, index: Int) async {
        guard let s = Paylasim.oku()?.sentences?.first(where: { $0.i == index }) else { return }
        NotificationCenter.default.post(name: Self.willPlay, object: nil)
        stop()
        token += 1
        let mine = token
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
        try? session.setActive(true)

        let url = Paylasim.audioURL(gun: day)
        if let start = s.start, let end = s.end, end > start, FileManager.default.fileExists(atPath: url.path),
           let p = try? AVAudioPlayer(contentsOf: url) {
            player = p
            p.currentTime = start
            p.play()
            try? await Task.sleep(for: .seconds(end - start + 0.2))
            if token == mine { p.stop(); player = nil }
        } else {
            let u = AVSpeechUtterance(string: s.en)
            u.voice = AVSpeechSynthesisVoice(language: "en-US")
            u.rate = 0.46
            synth.speak(u)
            let limit = Date().addingTimeInterval(30)
            try? await Task.sleep(for: .milliseconds(400))
            while synth.isSpeaking, Date() < limit, token == mine { try? await Task.sleep(for: .milliseconds(150)) }
        }
    }

    /// One word with the device voice (word chips in the widget).
    func say(_ text: String) async {
        NotificationCenter.default.post(name: Self.willPlay, object: nil)
        stop()
        token += 1
        let mine = token
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "en-US")
        u.rate = 0.42
        synth.speak(u)
        let limit = Date().addingTimeInterval(8)
        try? await Task.sleep(for: .milliseconds(300))
        while synth.isSpeaking, Date() < limit, token == mine { try? await Task.sleep(for: .milliseconds(120)) }
    }

    func stop() {
        player?.stop()
        player = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }
}
