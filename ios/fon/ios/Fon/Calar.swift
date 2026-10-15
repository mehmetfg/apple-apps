import AVFoundation
import Foundation

/// Fon'un tek çalarıdır. Asıl iş ses oturumundaki `.mixWithOthers` seçeneğindedir:
/// Voice Dream gibi uygulamalar ses oturumunu tek başına ister; karışabilir bir oturum
/// onları kesmez, onlar da onu kesmez. Bu yüzden Fon kilit ekranındaki "Şimdi Çalınan"ı da
/// almaz — oradaki düğmeler Voice Dream'de kalır, Fon kendi uygulamasından ya da Kestirmeler'den yönetilir.
@MainActor
final class Calar: NSObject, ObservableObject {
    static let shared = Calar()

    enum Durum: Equatable { case durdu, caliyor, konusmaYok }

    /// Başka bir uygulama (Voice Dream vb.) ses çalarken ve susunca müziğin ne yapacağı.
    enum Eslik: String, CaseIterable, Identifiable {
        case kapali, onePlanaCik, sessizeIn
        var id: String { rawValue }
        var ad: String {
            switch self {
            case .kapali: return "Kapalı"
            case .onePlanaCik: return "Konuşmada kıs, durunca öne çık"
            case .sessizeIn: return "Konuşma durunca sessize in"
            }
        }
    }

    @Published private(set) var parcalar: [Parca] = []
    @Published private(set) var simdiki: Parca?
    @Published private(set) var durum: Durum = .durdu
    @Published private(set) var uykuBitis: Date?
    /// Eşlik açıkken her saniye ölçülen sonuç; ekranda "algılanan" olarak görünür. nil = ölçülmüyor.
    @Published private(set) var konusmaAlgilandi: Bool?
    @Published var ses: Float {
        didSet {
            UserDefaults.standard.set(ses, forKey: "ses")
            if durum == .caliyor { player?.setVolume(hedefSes(), fadeDuration: 0.15) }
        }
    }
    @Published var karisik: Bool { didSet { UserDefaults.standard.set(karisik, forKey: "karisik") } }
    @Published var tekParcaTekrar: Bool {
        didSet {
            UserDefaults.standard.set(tekParcaTekrar, forKey: "tekParcaTekrar")
            player?.numberOfLoops = tekParcaTekrar ? -1 : 0
        }
    }
    /// Konuşma yokken (Voice Dream durmuşken) müziğin sesi — yalnız `.onePlanaCik` kipinde.
    @Published var onPlanSes: Float {
        didSet {
            UserDefaults.standard.set(onPlanSes, forKey: "onPlanSes")
            if durum == .konusmaYok { player?.setVolume(hedefSes(), fadeDuration: 0.15) }
        }
    }
    /// Deneysel: karışmayan başka bir uygulamanın sesi izlenir. Konuşma varken müzik `ses`te kalır;
    /// konuşma 3 sn susunca kipe göre öne çıkar (`onPlanSes`) ya da sessize iner. Sessizken de çalmayı
    /// sürdürür ki iOS uygulamayı askıya almasın ve konuşma dönünce yakalayabilsin.
    @Published var eslik: Eslik {
        didSet {
            UserDefaults.standard.set(eslik.rawValue, forKey: "eslik")
            eslikiAyarla()
        }
    }

    var caliyorMu: Bool { durum != .durdu }

    private var player: AVAudioPlayer?
    private var oturumAcik = false
    private var kesintideCaliyordu = false
    private var sonCalinanlar: [String] = []
    private var uykuGorevi: Task<Void, Never>?
    private var solmaJetonu = 0
    private var eslikZamanlayici: Timer?
    private var konusmaSessizSayac = 0
    private var arkaArkayaHata = 0

    private override init() {
        let d = UserDefaults.standard
        ses = d.object(forKey: "ses") as? Float ?? 0.3
        karisik = d.object(forKey: "karisik") as? Bool ?? true
        tekParcaTekrar = d.bool(forKey: "tekParcaTekrar")
        onPlanSes = d.object(forKey: "onPlanSes") as? Float ?? 0.7
        // 1.0'daki açık/kapalı anahtarı "sessize in" kipine denk gelir.
        eslik = d.string(forKey: "eslik").flatMap(Eslik.init) ?? (d.bool(forKey: "konusmayaEslik") ? .sessizeIn : .kapali)
        super.init()
        yenile()
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(kesinti(_:)), name: AVAudioSession.interruptionNotification, object: nil)
        nc.addObserver(self, selector: #selector(yolDegisti(_:)), name: AVAudioSession.routeChangeNotification, object: nil)
        nc.addObserver(self, selector: #selector(medyaSifirlandi), name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
    }

    // MARK: Kitaplık

    func yenile() {
        Depo.gelenKutusunuBosalt()
        parcalar = Depo.parcalar()
        if let s = simdiki, !parcalar.contains(s), durum == .durdu { simdiki = nil }
        if simdiki == nil, let son = UserDefaults.standard.string(forKey: "sonParca") {
            simdiki = parcalar.first { $0.id == son }
        }
    }

    func sil(_ parca: Parca) {
        if simdiki == parca {
            let calıyordu = caliyorMu
            sonraki(otomatik: false, calmayaDevam: calıyordu)
        }
        Depo.sil(parca)
        yenile()
        if parcalar.isEmpty { durdur(solarak: false) }
    }

    // MARK: Denetim

    func acKapa() { caliyorMu ? durdur() : baslat() }

    func baslat() {
        guard !parcalar.isEmpty, !caliyorMu else { return }
        if player == nil || simdiki == nil || !parcalar.contains(simdiki!) {
            cal(simdiki.flatMap { parcalar.contains($0) ? $0 : nil } ?? siradaki(sonra: nil))
            return
        }
        guard oturumuAc() else { return }
        player?.volume = 0
        player?.play()
        durum = .caliyor
        hedefSeseSol(sure: 2.5)
        eslikiAyarla()
    }

    func cal(_ parca: Parca) {
        guard oturumuAc() else { return }
        do {
            let yeni = try AVAudioPlayer(contentsOf: parca.url)
            yeni.delegate = self
            yeni.numberOfLoops = tekParcaTekrar ? -1 : 0
            yeni.volume = 0
            yeni.prepareToPlay()
            player?.stop()
            player = yeni
            simdiki = parca
            UserDefaults.standard.set(parca.id, forKey: "sonParca")
            sonCalinanlar.append(parca.id)
            if sonCalinanlar.count > max(1, parcalar.count / 2) { sonCalinanlar.removeFirst() }
            yeni.play()
            arkaArkayaHata = 0
            durum = .caliyor
            hedefSeseSol(sure: 2.5)
            eslikiAyarla()
        } catch {
            // Bozuk ya da desteklenmeyen dosya: sıradakine geç, hepsi bozuksa dur.
            arkaArkayaHata += 1
            simdiki = parca
            if arkaArkayaHata < parcalar.count { sonraki(otomatik: true) } else { durdur(solarak: false) }
        }
    }

    func sonraki() { sonraki(otomatik: false) }

    func durdur(solarak: Bool = true) {
        uykuyuIptal()
        solmaJetonu += 1
        let jeton = solmaJetonu
        let bitir: () -> Void = { [weak self] in
            guard let self, jeton == self.solmaJetonu else { return }
            self.player?.pause()
            self.oturumuKapat()
        }
        durum = .durdu
        eslikiAyarla()
        if solarak, let p = player, p.isPlaying {
            p.setVolume(0, fadeDuration: 1.2)
            Task { try? await Task.sleep(for: .seconds(1.25)); bitir() }
        } else {
            bitir()
        }
    }

    func uyku(dakika: Int) {
        uykuyuIptal()
        guard dakika > 0 else { return }
        if !caliyorMu { baslat() }
        let bitis = Date().addingTimeInterval(TimeInterval(dakika * 60))
        uykuBitis = bitis
        uykuGorevi = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double(dakika * 60) - 8))
            guard !Task.isCancelled, let self else { return }
            // Son 8 saniyede yavaşça kısılır.
            self.player?.setVolume(0, fadeDuration: 8)
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self.uykuBitis = nil
            self.durdur(solarak: false)
        }
    }

    func uykuyuIptal() {
        uykuGorevi?.cancel()
        uykuGorevi = nil
        uykuBitis = nil
    }

    // MARK: İç işler

    private func sonraki(otomatik: Bool, calmayaDevam: Bool = true) {
        guard !parcalar.isEmpty else { durdur(solarak: false); return }
        let p = siradaki(sonra: simdiki)
        if calmayaDevam || otomatik { cal(p) } else { simdiki = p; player = nil }
    }

    private func siradaki(sonra: Parca?) -> Parca {
        if karisik, parcalar.count > 1 {
            let aday = parcalar.filter { !sonCalinanlar.contains($0.id) && $0 != sonra }
            return (aday.isEmpty ? parcalar.filter { $0 != sonra } : aday).randomElement()!
        }
        guard let sonra, let i = parcalar.firstIndex(of: sonra) else { return parcalar[0] }
        return parcalar[(i + 1) % parcalar.count]
    }

    private func hedefSes() -> Float {
        guard durum == .konusmaYok else { return ses }
        switch eslik {
        case .kapali: return ses
        case .onePlanaCik: return onPlanSes
        case .sessizeIn: return 0
        }
    }

    private func hedefSeseSol(sure: TimeInterval) {
        player?.setVolume(hedefSes(), fadeDuration: sure)
    }

    private func oturumuAc() -> Bool {
        if oturumAcik { return true }
        let oturum = AVAudioSession.sharedInstance()
        do {
            try oturum.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try oturum.setActive(true)
            oturumAcik = true
            return true
        } catch {
            return false
        }
    }

    private func oturumuKapat() {
        guard oturumAcik else { return }
        try? AVAudioSession.sharedInstance().setActive(false)
        oturumAcik = false
    }

    // MARK: Konuşmaya eşlik (deneysel)

    private func eslikiAyarla() {
        eslikZamanlayici?.invalidate()
        eslikZamanlayici = nil
        konusmaSessizSayac = 0
        guard eslik != .kapali, caliyorMu else {
            konusmaAlgilandi = nil
            if durum == .konusmaYok { durum = .caliyor; hedefSeseSol(sure: 1) }
            return
        }
        eslikZamanlayici = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.eslikKontrol() }
        }
    }

    private func eslikKontrol() {
        guard eslik != .kapali, caliyorMu else { return }
        // İki sinyal: ipucu yalnız karışmayan bir uygulama çalarken yanar; Voice Dream öteki sesleri kısarak
        // (karışabilir oturumla) çalıyorsa yalnız isOtherAudioPlaying görür. Biri yeterli.
        let oturum = AVAudioSession.sharedInstance()
        let ipucu = oturum.secondaryAudioShouldBeSilencedHint
        let baska = oturum.isOtherAudioPlaying
        let konusmaVar = ipucu || baska
        konusmaAlgilandi = konusmaVar
        Tani.yaz("ipucu=\(ipucu ? 1 : 0) baska=\(baska ? 1 : 0) durum=\(durum) sayac=\(konusmaSessizSayac)")
        if konusmaVar {
            konusmaSessizSayac = 0
            // Konuşma başladı: hemen kısılır.
            if durum == .konusmaYok { durum = .caliyor; hedefSeseSol(sure: 0.8) }
        } else {
            konusmaSessizSayac += 1  // yarım saniyelik adım; 2 adım ≈ 1 sn
            // Kısa kopmalarda inip çıkmasın diye 1 sn (iki ölçüm) beklenir.
            // Telefonda ölçüldü (2026-10-08): sinyal cümle aralarında düşmüyor, yalnız duraklatınca düşüyor; 1 sn bekleme yeter.
            if konusmaSessizSayac >= 2, durum == .caliyor { durum = .konusmaYok; hedefSeseSol(sure: 1.2) }
        }
    }

    // MARK: Sistem olayları

    @objc private func kesinti(_ not: Notification) {
        guard let deger = not.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let tur = AVAudioSession.InterruptionType(rawValue: deger) else { return }
        Task { @MainActor in
            switch tur {
            case .began:
                // Telefon araması, alarm, Siri. Çalar iOS tarafından duraklatıldı.
                kesintideCaliyordu = caliyorMu
                oturumAcik = false
            case .ended:
                guard kesintideCaliyordu else { return }
                kesintideCaliyordu = false
                if oturumuAc() {
                    player?.volume = 0
                    player?.play()
                    hedefSeseSol(sure: 2)
                }
            @unknown default: break
            }
        }
    }

    @objc private func yolDegisti(_ not: Notification) {
        guard let deger = not.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: deger) == .oldDeviceUnavailable else { return }
        // Kulaklık çıkınca müzik hoparlöre geçmesin.
        Task { @MainActor in self.durdur(solarak: false) }
    }

    @objc private func medyaSifirlandi() {
        Task { @MainActor in
            let calıyordu = caliyorMu
            oturumAcik = false
            player = nil
            durum = .durdu
            if calıyordu, let s = simdiki { cal(s) }
        }
    }
}

extension Calar: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard player === self.player, self.caliyorMu else { return }
            self.sonraki(otomatik: true)
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            guard player === self.player else { return }
            self.sonraki(otomatik: true)
        }
    }
}

/// Eşlik sinyallerinin ham kaydı: Library/Caches/eslik-tani.log (Dosyalar'da görünmez).
/// Mac'ten okunur: xcrun devicectl device copy from --domain-type appDataContainer --domain-identifier com.fatihgocgun.fon
enum Tani {
    private static let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("eslik-tani.log")
    private static let saat: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f }()

    static func yaz(_ satir: String) {
        let metin = saat.string(from: Date()) + " " + satir + "\n"
        guard let veri = metin.data(using: .utf8) else { return }
        if let boyut = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, boyut > 300_000 {
            try? FileManager.default.removeItem(at: url)
        }
        if let el = try? FileHandle(forWritingTo: url) {
            el.seekToEndOfFile(); el.write(veri); try? el.close()
        } else {
            try? veri.write(to: url)
        }
    }
}
