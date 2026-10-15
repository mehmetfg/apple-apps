// Oynatıcı: paketin tek ses dosyası (açıklama → metin → kelimeler ve yapılar).
// · Bölüme atla, ‹ cümle (bir cümle geri), ↻ (cümleyi yinele), hız 0,8–1,2.
// · Arka planda ve kilit ekranında çalar; kulaklık düğmeleri çalışır.
// · Dinleme ancak sesin ≥ %80'i GERÇEKTEN çalınınca sayılır (sona sarmak sayılmaz); ikinci tam dinleme yeniden sayılır.
// · Arama/Siri kesince durur, kesinti bitince 2 sn geriden devam eder. Kulaklık çıkınca durur, hoparlörden kendiliğinden çalmaz.
// · Tek cümle çalma (Oku ekranı): yalnız o cümlenin aralığı çalar, sonra durur.
import Foundation
import AVFoundation
import MediaPlayer

@MainActor
final class Oynatici: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var paket: Paket?
    @Published private(set) var caliyor = false
    @Published private(set) var zaman: Double = 0
    @Published private(set) var sure: Double = 0
    @Published private(set) var satir: Satir?
    @Published private(set) var bolum: Bolum?
    @Published private(set) var tekCumle: Int?
    @Published var hata: String?

    weak var depo: Depo?
    private var calici: AVAudioPlayer?
    private var zamanlayici: Timer?
    private var dinlenen: Double = 0        // bu turda gerçekten çalınan saniye (ses zamanı)
    private var sonZaman: Double = 0
    private var durAt: Double?
    private var kesintidenDon = false
    static let esik = 0.8

    override init() {
        super.init()
        let m = NotificationCenter.default
        m.addObserver(self, selector: #selector(kesinti(_:)), name: AVAudioSession.interruptionNotification, object: nil)
        m.addObserver(self, selector: #selector(yolDegisti(_:)), name: AVAudioSession.routeChangeNotification, object: nil)
        uzaktanKomutlar()
    }

    var hiz: Double { depo?.hiz ?? 1.0 }

    // MARK: Yükle / çal

    @discardableResult
    func yukle(_ p: Paket) -> Bool {
        if paket?.gun == p.gun, paket?.surum == p.surum, calici != nil { return true }
        guard let u = depo?.sesURL(p) else {
            hata = "Bu paketin sesi henüz telefona inmedi. Vault'a bağlanınca kendiliğinden iner."
            return false
        }
        do {
            let c = try AVAudioPlayer(contentsOf: u)
            c.enableRate = true
            c.delegate = self
            c.prepareToPlay()
            calici?.stop()
            calici = c; paket = p; sure = c.duration; zaman = 0; sonZaman = 0; dinlenen = 0; hata = nil
            guncelle()
            return true
        } catch {
            hata = "Ses açılamadı: \(error.localizedDescription)"
            return false
        }
    }

    func cal(_ p: Paket? = nil, t: Double? = nil) {
        if let p, !yukle(p) { return }
        guard let c = calici else { return }
        oturumAc()
        if let t { c.currentTime = max(0, min(t, c.duration - 0.2)); sonZaman = c.currentTime }
        c.rate = Float(hiz)
        c.play()
        caliyor = true
        zamanlayiciKur()
        simdiCaliyor()
    }

    func duraklat() {
        calici?.pause()
        caliyor = false
        zamanlayici?.invalidate(); zamanlayici = nil
        durAt = nil; tekCumle = nil
        simdiCaliyor()
    }

    func degistir() { caliyor ? duraklat() : cal() }

    func git(_ t: Double) {
        guard let c = calici else { return }
        c.currentTime = max(0, min(t, c.duration - 0.2))
        sonZaman = c.currentTime          // sarma dinleme sayılmaz
        guncelle(); simdiCaliyor()
    }

    func atla(_ sn: Double) { git(zaman + sn) }

    func bolumeGit(_ b: Bolum) {
        durAt = nil; tekCumle = nil
        git(b.baslangic)
        if !caliyor { cal() }
    }

    /// Bir cümle geri: çalan satırın başı (≥ 1,5 sn geçtiyse), değilse bir önceki satır.
    func oncekiCumle() {
        guard let p = paket, let s = p.satirlar else { return }
        let simdi = s.lastIndex { zaman + 0.05 >= $0.baslangic } ?? 0
        let hedef = zaman - s[simdi].baslangic > 1.5 ? simdi : max(0, simdi - 1)
        git(s[hedef].baslangic)
        if let c = s[hedef].cumle { depo?.takildi(p, cumle: c, nasil: "geri") }
    }

    func cumleyiYinele() {
        guard let s = satir else { return }
        git(s.baslangic)
        if !caliyor { cal() }
        if let p = paket, let c = s.cumle { depo?.takildi(p, cumle: c, nasil: "yinele") }
    }

    func sonrakiCumle() {
        guard let p = paket, let s = p.satirlar,
              let i = s.firstIndex(where: { $0.baslangic > zaman + 0.1 }) else { return }
        git(s[i].baslangic)
    }

    /// Oku ekranından tek cümle: yalnız o cümlenin aralığı.
    func cumleCal(_ p: Paket, _ i: Int) {
        guard let s = p.cumleZamani(i) else { return }
        if tekCumle == i && caliyor { duraklat(); return }
        guard yukle(p) else { return }
        durAt = s.bitis + 0.15
        tekCumle = i
        cal(t: s.baslangic)
    }

    func hizDegisti() {
        if caliyor { calici?.rate = Float(hiz) }
        simdiCaliyor()
    }

    // MARK: Zaman ve dinleme sayımı

    private func zamanlayiciKur() {
        zamanlayici?.invalidate()
        zamanlayici = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tik() }
        }
    }

    private func tik() {
        guard let c = calici else { return }
        let t = c.currentTime
        let fark = t - sonZaman
        if c.isPlaying, fark > 0, fark < 1.0 { dinlenen += fark }   // sarma (büyük sıçrama) sayılmaz
        sonZaman = t
        zaman = t
        guncelle()
        if let d = durAt, t >= d { duraklat() }
        if tekCumle == nil, sure > 0, dinlenen >= sure * Oynatici.esik { sayildi() }
    }

    private func sayildi() {
        guard let p = paket else { return }
        let oran = min(1, dinlenen / max(sure, 1))
        dinlenen = 0
        depo?.dinledi(p, oran: oran, sure: sure)
    }

    private func guncelle() {
        guard let p = paket else { return }
        let s = p.satir(zaman), b = p.bolum(zaman)
        if s != satir { satir = s }
        if b != bolum { bolum = b; simdiCaliyor() }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.caliyor = false
            self.zamanlayici?.invalidate(); self.zamanlayici = nil
            self.zaman = 0; self.sonZaman = 0
            self.calici?.currentTime = 0
            self.guncelle()
            self.simdiCaliyor()
        }
    }

    // MARK: Ses oturumu, kesinti, kulaklık

    private func oturumAc() {
        let o = AVAudioSession.sharedInstance()
        try? o.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
        try? o.setActive(true)
    }

    @objc nonisolated private func kesinti(_ n: Notification) {
        guard let tur = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init) else { return }
        let devam = ((n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0) & AVAudioSession.InterruptionOptions.shouldResume.rawValue != 0
        Task { @MainActor in
            switch tur {
            case .began:
                self.kesintidenDon = self.caliyor
                self.calici?.pause(); self.caliyor = false
                self.zamanlayici?.invalidate(); self.zamanlayici = nil
            case .ended:
                if self.kesintidenDon && devam { self.git(self.zaman - 2); self.cal() }
                self.kesintidenDon = false
            @unknown default: break
            }
        }
    }

    @objc nonisolated private func yolDegisti(_ n: Notification) {
        guard let neden = (n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init),
              neden == .oldDeviceUnavailable else { return }
        Task { @MainActor in if self.caliyor { self.duraklat() } }
    }

    // MARK: Kilit ekranı

    private func uzaktanKomutlar() {
        let m = MPRemoteCommandCenter.shared()
        m.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.cal() }; return .success }
        m.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.duraklat() }; return .success }
        m.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.degistir() }; return .success }
        m.skipBackwardCommand.preferredIntervals = [10]
        m.skipBackwardCommand.addTarget { [weak self] _ in Task { @MainActor in self?.atla(-10) }; return .success }
        m.skipForwardCommand.preferredIntervals = [10]
        m.skipForwardCommand.addTarget { [weak self] _ in Task { @MainActor in self?.atla(10) }; return .success }
        m.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.oncekiCumle() }; return .success }
        m.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.sonrakiCumle() }; return .success }
        m.changePlaybackPositionCommand.addTarget { [weak self] e in
            if let e = e as? MPChangePlaybackPositionCommandEvent { Task { @MainActor in self?.git(e.positionTime) } }
            return .success
        }
    }

    private func simdiCaliyor() {
        guard let p = paket else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "Gün \(p.gun) · \(p.ad)",
            MPMediaItemPropertyArtist: bolum?.etiket ?? "Ön çalışma",
            MPMediaItemPropertyAlbumTitle: "Memories",
            MPMediaItemPropertyPlaybackDuration: sure,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: zaman,
            MPNowPlayingInfoPropertyPlaybackRate: caliyor ? hiz : 0,
        ]
    }
}
