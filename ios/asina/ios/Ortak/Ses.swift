// Söyleniş: önce Oxford'un gerçek kaydı (çevrimiçiyse), olmazsa cihazın İngiliz sesi.
import AVFoundation

@MainActor
final class Ses: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let ortak = Ses()

    private let konusucu = AVSpeechSynthesizer()
    private var oynatici: AVPlayer?
    private var bekleme: NSObjectProtocol?
    @Published private(set) var caliyor = false

    private lazy var sesTipi: AVSpeechSynthesisVoice? = {
        let ingiliz = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "en-GB" }
        return ingiliz.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: "en-GB")
    }()

    override init() {
        super.init()
        konusucu.delegate = self
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
    }

    func soyle(_ k: Kelime, oxford: Bool) {
        if oxford, let u = URL(string: k.au), !k.au.isEmpty {
            cal(u, yedek: k.w)
        } else {
            oku(k.w)
        }
    }

    /// Widget ve bildirimden: elde yalnız kelime ve (varsa) Oxford adresi var.
    func soyle(ad: String, url: String?, oxford: Bool) {
        if oxford, let url, !url.isEmpty, let u = URL(string: url) { cal(u, yedek: ad) } else { oku(ad) }
    }

    /// Çalma bitene (en çok `sn` saniye) kadar bekler — arka planda uygulamanın erken askıya alınmaması için.
    func bekle(en sn: Double = 8) async {
        let bitis = Date().addingTimeInterval(sn)
        try? await Task.sleep(nanoseconds: 500_000_000)
        while caliyor, Date() < bitis { try? await Task.sleep(nanoseconds: 150_000_000) }
    }

    func oku(_ metin: String, yavas: Bool = false) {
        dur()
        try? AVAudioSession.sharedInstance().setActive(true)
        let s = AVSpeechUtterance(string: metin)
        s.voice = sesTipi
        s.rate = yavas ? 0.38 : 0.46
        caliyor = true
        konusucu.speak(s)
    }

    private func cal(_ u: URL, yedek: String) {
        dur()
        try? AVAudioSession.sharedInstance().setActive(true)
        let o = AVPlayer(url: u)
        oynatici = o
        caliyor = true
        bekleme = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                         object: o.currentItem, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.caliyor = false }
        }
        o.play()
        // 1,5 sn içinde başlamazsa (çevrimdışı) cihaz sesine düş.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, self.oynatici === o else { return }
            if o.currentItem?.status != .readyToPlay || o.timeControlStatus != .playing && o.currentTime().seconds < 0.1 {
                self.oku(yedek)
            }
        }
    }

    func dur() {
        oynatici?.pause()
        oynatici = nil
        if let b = bekleme { NotificationCenter.default.removeObserver(b) }
        if konusucu.isSpeaking { konusucu.stopSpeaking(at: .immediate) }
        caliyor = false
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in self.caliyor = false }
    }
}
