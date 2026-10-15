// Seslendirme. Oxford'daki kelimeler Oxford'un gerçek İngiliz telaffuzuyla (ilk çalışta indirilip saklanır, sonra çevrimdışı),
// ötekiler telefonun İngilizce sesiyle. Ses düğmesi kapalıyken kendiliğinden konuşmaz; dokununca yine okur.
import AVFoundation
import Foundation

@MainActor
final class Ses: NSObject, ObservableObject {
    static let shared = Ses()
    @Published var acik: Bool = UserDefaults.standard.object(forKey: "sesAcik") as? Bool ?? true {
        didSet { UserDefaults.standard.set(acik, forKey: "sesAcik") }
    }
    @Published var oxford: Bool = UserDefaults.standard.object(forKey: "oxfordSes") as? Bool ?? true {
        didSet { UserDefaults.standard.set(oxford, forKey: "oxfordSes") }
    }
    @Published var aksan: String = UserDefaults.standard.string(forKey: "aksan") ?? "en-GB" {
        didSet { UserDefaults.standard.set(aksan, forKey: "aksan") }
    }

    private let sentez = AVSpeechSynthesizer()
    private var oynatici: AVAudioPlayer?
    private var sonKonusma = Date.distantPast

    private func oturum() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    /// Kamera yeni bir eşya bulunca: ses açıksa ve son konuşmadan 1,2 sn geçtiyse okur.
    func kendiliginden(_ k: Kelime) {
        guard acik, Date().timeIntervalSince(sonKonusma) > 1.2 else { return }
        oku(k)
    }

    func oku(_ k: Kelime) {
        sonKonusma = Date()
        oturum()
        if oxford, let u = URL(string: k.sesURL), !k.sesURL.isEmpty {
            let yerel = Ses.onbellek(k)
            if let d = try? Data(contentsOf: yerel) { cal(d); return }
            Task {
                var r = URLRequest(url: u); r.setValue("Mozilla/5.0 (iPhone)", forHTTPHeaderField: "User-Agent")
                if let (d, cevap) = try? await URLSession.shared.data(for: r), (cevap as? HTTPURLResponse)?.statusCode == 200, d.count > 1000 {
                    try? d.write(to: yerel)
                    cal(d)
                } else { soyle(k.en) }
            }
            return
        }
        soyle(k.en)
    }

    func soyle(_ metin: String) {
        sentez.stopSpeaking(at: .immediate)
        let s = AVSpeechUtterance(string: metin)
        s.voice = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == aksan }.max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: aksan)
        s.rate = 0.45
        sentez.speak(s)
    }

    private func cal(_ d: Data) {
        oynatici = try? AVAudioPlayer(data: d)
        oynatici?.play()
    }

    static func onbellek(_ k: Kelime) -> URL {
        let u = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("oxford", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u.appendingPathComponent(k.en.replacingOccurrences(of: " ", with: "_") + ".mp3")
    }
}
