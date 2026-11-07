import AVFoundation
import Combine
import MediaPlayer

/// Ücretsiz, reklamsız ya da az konuşmalı klasik müzik akışları. Akış AVPlayer'la çalar: Tını'nın efekt zinciri
/// yalnız dosyalara uygulanır, radyoda ses düzeyi ve kip (kitapla / yalnız) geçerlidir.
struct Istasyon: Identifiable, Hashable {
    let id: String
    let ad: String
    let aciklama: String
    let adres: URL
}

@MainActor
final class Radyo: NSObject, ObservableObject, AVPlayerItemMetadataOutputPushDelegate {
    static let shared = Radyo()

    static let istasyonlar: [Istasyon] = [
        Istasyon(id: "rart-vivaldi", ad: "RadioArt · Vivaldi", aciklama: "Yalnız Vivaldi, konuşmasız",
                 adres: URL(string: "https://live.radioart.com/fVivaldi.mp3")!),
        Istasyon(id: "rart-barok", ad: "RadioArt · Barok", aciklama: "Bach, Händel, Corelli, Telemann",
                 adres: URL(string: "https://live.radioart.com/fBaroque.mp3")!),
        Istasyon(id: "venice", ad: "Venice Classic Radio", aciklama: "Barok ağırlıklı, reklamsız, konuşmasız",
                 adres: URL(string: "https://uk2.streamingpulse.com/ssl/vcr1")!),
        Istasyon(id: "swiss", ad: "Radio Swiss Classic", aciklama: "Sakin klasik, çok az konuşma",
                 adres: URL(string: "https://stream.srg-ssr.ch/m/rsc_de/mp3_128")!),
        Istasyon(id: "rart-bach", ad: "RadioArt · Bach", aciklama: "Yalnız Bach",
                 adres: URL(string: "https://live.radioart.com/fBach.mp3")!),
        Istasyon(id: "rart-mozart", ad: "RadioArt · Mozart", aciklama: "Yalnız Mozart",
                 adres: URL(string: "https://live.radioart.com/fMozart.mp3")!),
        Istasyon(id: "rart-klasik", ad: "RadioArt · Klasik Dönem", aciklama: "Haydn, Mozart, erken Beethoven",
                 adres: URL(string: "https://live.radioart.com/fClassical_period.mp3")!),
        Istasyon(id: "rart-piyano", ad: "RadioArt · Piyano", aciklama: "Solo piyano, okurken en sessizi",
                 adres: URL(string: "https://live.radioart.com/fPiano.mp3")!),
        Istasyon(id: "trt3", ad: "TRT Radyo 3", aciklama: "Klasik ve caz, arada Türkçe anons",
                 adres: URL(string: "https://radio-trtradyo3.live.trt.com.tr/master_128.m3u8")!),
    ]

    @Published private(set) var istasyon: Istasyon?
    @Published private(set) var caliyor = false
    @Published private(set) var yukleniyor = false
    @Published private(set) var simdiCalan: String?
    @Published private(set) var hata: String?

    private let oynatici = AVPlayer()
    private var gozlemciler: Set<AnyCancellable> = []
    private var oturumAcik = false

    private override init() {
        super.init()
        oynatici.automaticallyWaitsToMinimizeStalling = true
        Calar.shared.$ses.combineLatest(Calar.shared.$avls)
            .sink { [weak self] s, a in self?.oynatici.volume = a ? min(s, 0.5) : s }
            .store(in: &gozlemciler)
        oynatici.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] d in
                guard let self, self.caliyor else { return }
                self.yukleniyor = d == .waitingToPlayAtSpecifiedRate
            }
            .store(in: &gozlemciler)
        NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.yenidenBaglan() }
        }
    }

    func cal(_ i: Istasyon) {
        if istasyon == i, caliyor { durdur(); return }
        Calar.shared.durdur(solarak: false)
        guard oturumuAc() else { hata = "Ses oturumu açılamadı."; return }
        istasyon = i
        simdiCalan = nil
        hata = nil
        let oge = AVPlayerItem(url: i.adres)
        let cikis = AVPlayerItemMetadataOutput(identifiers: nil)
        cikis.setDelegate(self, queue: .main)
        oge.add(cikis)
        oynatici.replaceCurrentItem(with: oge)
        oynatici.play()
        caliyor = true
        yukleniyor = true
        UserDefaults.standard.set(i.id, forKey: "sonIstasyon")
        kilitEkrani()
    }

    func durdur() {
        guard caliyor else { return }
        oynatici.pause()
        oynatici.replaceCurrentItem(with: nil)
        caliyor = false
        yukleniyor = false
        simdiCalan = nil
        if oturumAcik {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            oturumAcik = false
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// Bağlantı koparsa (tünel, Wi-Fi değişimi) aynı istasyona bir kez yeniden bağlanır.
    private func yenidenBaglan() {
        guard caliyor, let i = istasyon else { return }
        hata = "Bağlantı koptu, yeniden bağlanılıyor…"
        Task {
            try? await Task.sleep(for: .seconds(2))
            guard self.caliyor, self.istasyon == i else { return }
            self.oynatici.replaceCurrentItem(with: AVPlayerItem(url: i.adres))
            self.oynatici.play()
        }
    }

    private func oturumuAc() -> Bool {
        let kip = Calar.shared.kip
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: kip == .kitapla ? [.mixWithOthers] : [])
            try AVAudioSession.sharedInstance().setActive(true)
            oturumAcik = true
            return true
        } catch {
            return false
        }
    }

    private func kilitEkrani() {
        guard Calar.shared.kip == .yalniz, let i = istasyon else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: simdiCalan ?? i.ad,
            MPMediaItemPropertyArtist: i.ad,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: caliyor ? 1.0 : 0.0,
        ]
    }

    // Icecast "StreamTitle" künyesi: o an çalan eser.
    nonisolated func metadataOutput(_ output: AVPlayerItemMetadataOutput, didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
                                    from track: AVPlayerItemTrack?) {
        Task { @MainActor in
            for g in groups {
                for m in g.items {
                    if let s = try? await m.load(.stringValue), !s.trimmingCharacters(in: .whitespaces).isEmpty {
                        self.simdiCalan = s
                        self.yukleniyor = false
                        self.kilitEkrani()
                        return
                    }
                }
            }
        }
    }
}
