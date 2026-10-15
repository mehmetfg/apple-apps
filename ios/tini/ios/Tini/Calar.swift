import AVFoundation
import Foundation
import MediaPlayer
import UIKit
import os

let gunluk = Logger(subsystem: "com.fatihgocgun.tini", category: "calar")

/// Tını'nın tek çalarıdır. İki kip:
/// - **Kitapla birlikte** (Fon'dan devralınan): ses oturumu `.mixWithOthers` ile açılır; Voice Dream gibi uygulamaları
///   kesmez, onlar da onu kesmez. Kilit ekranı onlarda kalır; konuşmaya eşlik (kıs / öne çık) burada çalışır.
/// - **Yalnız müzik**: karışmayan oturum; kilit ekranı, kulaklık düğmeleri ve Denetim Merkezi Tını'yı yönetir.
@MainActor
final class Calar: NSObject, ObservableObject {
    static let shared = Calar()

    enum Durum: Equatable { case durdu, caliyor, konusmaYok }

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

    enum Kip: String, CaseIterable, Identifiable {
        case kitapla, yalniz
        var id: String { rawValue }
        var ad: String { self == .kitapla ? "Kitapla birlikte" : "Yalnız müzik" }
        var aciklama: String {
            self == .kitapla
                ? "Voice Dream'i kesmez; konuşmaya göre kısılıp öne çıkabilir. Kilit ekranı kitapta kalır."
                : "Kilit ekranı, kulaklık düğmeleri ve Denetim Merkezi Tını'yı yönetir. Başka ses başlayınca durur."
        }
    }

    enum Tekrar: String, CaseIterable { case kapali, tum, tek }

    // Kitaplık ve kuyruk
    @Published private(set) var parcalar: [Parca] = []
    @Published private(set) var taraniyor = false
    @Published private(set) var kuyruk: [Parca] = []
    @Published private(set) var sira = 0
    @Published private(set) var simdiki: Parca?
    @Published private(set) var durum: Durum = .durdu
    @Published private(set) var konum: Double = 0
    @Published private(set) var uykuBitis: Date?
    @Published private(set) var konusmaAlgilandi: Bool?
    @Published private(set) var hata: String?

    var sure: Double { simdiki?.sure ?? 0 }
    var caliyorMu: Bool { durum != .durdu }
    var zincir: Zincir? { motor.zincir }

    // Ayarlar
    @Published var ses: Float { didSet { kaydetVeUygula("ses", ses) } }
    @Published var onPlanSes: Float { didSet { kaydetVeUygula("onPlanSes", onPlanSes) } }
    @Published var avls: Bool { didSet { UserDefaults.standard.set(avls, forKey: "avls"); sesiUygula(0.2) } }
    @Published var karisik: Bool {
        didSet { UserDefaults.standard.set(karisik, forKey: "karisik"); kuyruguKar(); siradakiniHazirla(yeniden: true) }
    }
    @Published var tekrar: Tekrar {
        didSet { UserDefaults.standard.set(tekrar.rawValue, forKey: "tekrar"); siradakiniHazirla(yeniden: true) }
    }
    @Published var eslik: Eslik { didSet { UserDefaults.standard.set(eslik.rawValue, forKey: "eslik"); eslikiAyarla() } }
    @Published var kip: Kip {
        didSet {
            UserDefaults.standard.set(kip.rawValue, forKey: "kip")
            guard kip != oldValue else { return }
            oturumAcik = false
            if caliyorMu { _ = oturumuAc() }
            kilitEkraniniGuncelle()
            eslikiAyarla()
        }
    }

    private var motor = Motor()
    private var hazirlik: Task<Void, Never>?
    private var asilKuyruk: [Parca] = []
    private var oturumAcik = false
    private var kesintideCaliyordu = false
    private var uykuGorevi: Task<Void, Never>?
    private var solmaJetonu = 0
    private var eslikZamanlayici: Timer?
    private var konumZamanlayici: Timer?
    private var konusmaSessizSayac = 0
    private var arkaArkayaHata = 0
    /// Boşluksuz kuyruğa eklenmiş sıradaki parçanın kuyruk indeksi.
    private var hazirSiradaki: Int?

    private override init() {
        let d = UserDefaults.standard
        ses = d.object(forKey: "ses") as? Float ?? 0.3
        onPlanSes = d.object(forKey: "onPlanSes") as? Float ?? 0.7
        avls = d.bool(forKey: "avls")
        karisik = d.object(forKey: "karisik") as? Bool ?? true
        tekrar = Tekrar(rawValue: d.string(forKey: "tekrar") ?? "") ?? (d.bool(forKey: "tekParcaTekrar") ? .tek : .tum)
        eslik = d.string(forKey: "eslik").flatMap(Eslik.init) ?? (d.bool(forKey: "konusmayaEslik") ? .sessizeIn : .kapali)
        kip = Kip(rawValue: d.string(forKey: "kip") ?? "") ?? .kitapla
        super.init()
        parcalar = Katalog.onbellek()
        if let son = d.string(forKey: "sonParca") { simdiki = parcalar.first { $0.id == son } }
        motorBaglantilari()
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(kesinti(_:)), name: AVAudioSession.interruptionNotification, object: nil)
        nc.addObserver(self, selector: #selector(yolDegisti(_:)), name: AVAudioSession.routeChangeNotification, object: nil)
        nc.addObserver(self, selector: #selector(medyaSifirlandi), name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        uzaktanKomutlar()
        yenile()
    }

    private func motorBaglantilari() {
        motor.bolumBitti = { [weak self] kimlik, kaldi in self?.bolumBitti(kimlik, kaldi: kaldi) }
        motor.yenidenKurulmali = { [weak self] in self?.motorDegisti() }
    }

    private func hazirOl() async {
        if motor.efekt != nil { return }
        if hazirlik == nil {
            hazirlik = Task {
                do { try await motor.hazirla() } catch { hata = "Ses motoru kurulamadı: \(error.localizedDescription)" }
                Ses.shared.zincir = motor.zincir
            }
        }
        await hazirlik?.value
    }

    // MARK: Kitaplık

    func yenile() {
        Depo.gelenKutusunuBosalt()
        guard !taraniyor else { return }
        taraniyor = true
        Task {
            let yeni = await Katalog.tara()
            parcalar = yeni
            taraniyor = false
            if simdiki == nil, let son = UserDefaults.standard.string(forKey: "sonParca") { simdiki = yeni.first { $0.id == son } }
            if kuyruk.isEmpty { asilKuyruk = yeni; kuyruguKar() }
        }
    }

    func sil(_ parca: Parca) {
        if simdiki == parca {
            let caliyordu = caliyorMu
            if caliyordu, kuyruk.count > 1 { sonraki() } else { durdur(solarak: false) }
        }
        Depo.sil(parca)
        asilKuyruk.removeAll { $0 == parca }
        kuyruk.removeAll { $0 == parca }
        if let s = simdiki, let i = kuyruk.firstIndex(of: s) { sira = i }
        yenile()
    }

    // MARK: Denetim

    func acKapa() { caliyorMu ? durdur() : baslat() }

    /// Seçilen listeden çalar; liste kuyruk olur.
    func cal(_ parca: Parca, liste: [Parca]? = nil) {
        asilKuyruk = liste ?? (parcalar.isEmpty ? [parca] : parcalar)
        kuyruk = karisik ? [parca] + asilKuyruk.filter { $0 != parca }.shuffled() : asilKuyruk
        sira = kuyruk.firstIndex(of: parca) ?? 0
        baslat(parca, saniye: 0)
    }

    func listeyiKarisikCal(_ liste: [Parca]) {
        guard let ilk = liste.randomElement() else { return }
        if !karisik { karisik = true }
        cal(ilk, liste: liste)
    }

    func baslat() {
        if caliyorMu { return }
        if kuyruk.isEmpty { asilKuyruk = parcalar; kuyruguKar() }
        guard !kuyruk.isEmpty else { return }
        if let s = simdiki, motor.simdikiBolum?.kimlik == s.id {
            devamEt()
        } else {
            let p = simdiki.flatMap { s in kuyruk.contains(s) ? s : nil } ?? kuyruk[0]
            sira = kuyruk.firstIndex(of: p) ?? 0
            baslat(p, saniye: simdiki == p ? konum : 0)
        }
    }

    private func baslat(_ parca: Parca, saniye: Double) {
        Task {
            await hazirOl()
            guard oturumuAc() else { hata = "Ses oturumu açılamadı."; return }
            do {
                let dosya = try AVAudioFile(forReading: parca.url)
                solmaJetonu += 1
                hazirSiradaki = nil   // motor kuyruğu sıfırlanıyor; sıradaki yeniden eklenecek
                motor.zincir?.kazancaSol(0, sure: 0.001)
                try motor.cal(kimlik: parca.id, dosya: dosya, saniye: saniye)
                parcayaGec(parca)
                konum = saniye
                durum = .caliyor
                arkaArkayaHata = 0
                hata = nil
                sesiUygula(kip == .kitapla && saniye == 0 ? 1.5 : 0.25)
                siradakiniHazirla(yeniden: false)
                eslikiAyarla()
                konumIzle()
            } catch {
                // Bozuk ya da desteklenmeyen dosya: sıradakine geç, hepsi bozuksa dur.
                arkaArkayaHata += 1
                gunluk.error("çalınamadı \(parca.yol, privacy: .public): \(error.localizedDescription, privacy: .public)")
                hata = "Çalınamadı: \(parca.baslik)"
                if arkaArkayaHata < kuyruk.count, let s = siradakiIndeks(elle: true) {
                    sira = s
                    baslat(kuyruk[s], saniye: 0)
                } else {
                    durdur(solarak: false)
                }
            }
        }
    }

    private func devamEt() {
        guard oturumuAc() else { return }
        do { try motor.devam() } catch { baslat(simdiki!, saniye: konum); return }
        solmaJetonu += 1
        durum = .caliyor
        sesiUygula(kip == .kitapla ? 1.5 : 0.2)
        eslikiAyarla()
        konumIzle()
        kilitEkraniniGuncelle()
    }

    func sonraki() {
        guard !kuyruk.isEmpty, let s = siradakiIndeks(elle: true) else { durdur(); return }
        sira = s
        baslat(kuyruk[s], saniye: 0)
    }

    func onceki() {
        guard !kuyruk.isEmpty else { return }
        if konum > 4, let s = simdiki { baslat(s, saniye: 0); return }
        sira = (sira - 1 + kuyruk.count) % kuyruk.count
        baslat(kuyruk[sira], saniye: 0)
    }

    func atla(_ saniye: Double) {
        guard let s = simdiki else { return }
        let hedef = min(max(0, saniye), max(0, s.sure - 0.5))
        if caliyorMu { baslat(s, saniye: hedef) } else { konum = hedef }
    }

    func kuyruktan(_ i: Int) {
        guard kuyruk.indices.contains(i) else { return }
        sira = i
        baslat(kuyruk[i], saniye: 0)
    }

    func durdur(solarak: Bool = true) {
        uykuyuIptal()
        solmaJetonu += 1
        let jeton = solmaJetonu
        durum = .durdu
        eslikiAyarla()
        konumZamanlayici?.invalidate()
        konum = motor.konum
        kilitEkraniniGuncelle()
        let bitir: () -> Void = { [weak self] in
            guard let self, jeton == self.solmaJetonu else { return }
            self.motor.duraklat()
            self.motor.motoruDuraklat()
            self.oturumuKapat()
        }
        if solarak, motor.caliyor {
            motor.zincir?.kazancaSol(0, sure: kip == .kitapla ? 1.2 : 0.25)
            Task { try? await Task.sleep(for: .seconds(kip == .kitapla ? 1.25 : 0.3)); bitir() }
        } else {
            motor.zincir?.kazancaSol(0, sure: 0.01)
            bitir()
        }
    }

    func uyku(dakika: Int) {
        uykuyuIptal()
        guard dakika > 0 else { return }
        if !caliyorMu { baslat() }
        uykuBitis = Date().addingTimeInterval(TimeInterval(dakika * 60))
        uykuGorevi = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double(dakika * 60) - 8))
            guard !Task.isCancelled, let self else { return }
            self.motor.zincir?.kazancaSol(0, sure: 8)   // son 8 saniyede yavaşça kısılır
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self.uykuBitis = nil
            self.durdur(solarak: false)
        }
    }

    func uykuyuIptal() {
        uykuGorevi?.cancel()
        uykuGorevi = nil
        if uykuBitis != nil { uykuBitis = nil; sesiUygula(0.5) }
    }

    // MARK: Kuyruk

    private func kuyruguKar() {
        guard !asilKuyruk.isEmpty else { return }
        if karisik {
            let s = simdiki.flatMap { asilKuyruk.contains($0) ? $0 : nil }
            kuyruk = (s.map { [$0] } ?? []) + asilKuyruk.filter { $0 != s }.shuffled()
        } else {
            kuyruk = asilKuyruk
        }
        sira = simdiki.flatMap { kuyruk.firstIndex(of: $0) } ?? 0
    }

    private func siradakiIndeks(elle: Bool) -> Int? {
        guard !kuyruk.isEmpty else { return nil }
        if tekrar == .tek && !elle { return sira }
        let s = sira + 1
        if s < kuyruk.count { return s }
        return (tekrar == .kapali && !elle) ? nil : 0
    }

    /// Sıradaki parçayı motorun kuyruğuna boşluksuz ekler (biçim aynıysa).
    private func siradakiniHazirla(yeniden: Bool) {
        guard caliyorMu || !yeniden else { return }
        if yeniden, hazirSiradaki != nil {
            hazirSiradaki = nil
            motor.siradakileriTemizle()
        }
        guard hazirSiradaki == nil, let s = siradakiIndeks(elle: false), let dosya = try? AVAudioFile(forReading: kuyruk[s].url) else { return }
        if motor.siradakiniEkle(kimlik: kuyruk[s].id, dosya: dosya) { hazirSiradaki = s }
    }

    private func bolumBitti(_ kimlik: String, kaldi: Bool) {
        gunluk.info("bölüm bitti \(kimlik, privacy: .public) kaldı=\(kaldi) hazır=\(self.hazirSiradaki ?? -1)")
        guard caliyorMu else { return }
        if kaldi, let s = hazirSiradaki {
            // Boşluksuz geçiş oldu: sıradaki zaten çalıyor.
            hazirSiradaki = nil
            sira = s
            parcayaGec(kuyruk[s])
            siradakiniHazirla(yeniden: false)
        } else if let s = siradakiIndeks(elle: false) {
            hazirSiradaki = nil
            sira = s
            baslat(kuyruk[s], saniye: 0)
        } else {
            hazirSiradaki = nil
            durdur(solarak: false)
            konum = 0
        }
    }

    private func parcayaGec(_ p: Parca) {
        simdiki = p
        UserDefaults.standard.set(p.id, forKey: "sonParca")
        motor.zincir?.parcaKazanciAyarla(p.replayGain.map { pow(10, $0 / 20) } ?? 1)
        kilitEkraniniGuncelle()
    }

    private func konumIzle() {
        konumZamanlayici?.invalidate()
        konumZamanlayici = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.caliyorMu else { return }
                self.konum = self.motor.konum
            }
        }
    }

    // MARK: Ses düzeyi

    private func kaydetVeUygula(_ anahtar: String, _ deger: Float) {
        UserDefaults.standard.set(deger, forKey: anahtar)
        sesiUygula(0.12)
    }

    private func hedefSes() -> Float {
        var h = ses
        if durum == .konusmaYok, kip == .kitapla {
            switch eslik {
            case .kapali: break
            case .onePlanaCik: h = onPlanSes
            case .sessizeIn: h = 0
            }
        }
        return avls ? min(h, 0.5) : h
    }

    private func sesiUygula(_ sure: Double) {
        guard caliyorMu else { return }
        motor.zincir?.kazancaSol(hedefSes(), sure: sure)
    }

    // MARK: Ses oturumu

    private func oturumuAc() -> Bool {
        if oturumAcik { return true }
        let oturum = AVAudioSession.sharedInstance()
        do {
            try oturum.setCategory(.playback, mode: .default, options: kip == .kitapla ? [.mixWithOthers] : [])
            try oturum.setActive(true)
            oturumAcik = true
            return true
        } catch {
            return false
        }
    }

    private func oturumuKapat() {
        guard oturumAcik else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        oturumAcik = false
    }

    // MARK: Konuşmaya eşlik (Fon'dan)

    private func eslikiAyarla() {
        eslikZamanlayici?.invalidate()
        eslikZamanlayici = nil
        konusmaSessizSayac = 0
        guard eslik != .kapali, kip == .kitapla, caliyorMu else {
            konusmaAlgilandi = nil
            if durum == .konusmaYok { durum = .caliyor; sesiUygula(1) }
            return
        }
        eslikZamanlayici = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.eslikKontrol() }
        }
    }

    private func eslikKontrol() {
        guard eslik != .kapali, caliyorMu else { return }
        // İki sinyal: ipucu yalnız karışmayan bir uygulama çalarken yanar; Voice Dream öteki sesleri kısarak
        // çalıyorsa yalnız isOtherAudioPlaying görür. Telefonda ikisi birlikte yanıp sönüyor (Fon, 2026-10-08).
        let oturum = AVAudioSession.sharedInstance()
        let konusmaVar = oturum.secondaryAudioShouldBeSilencedHint || oturum.isOtherAudioPlaying
        konusmaAlgilandi = konusmaVar
        if konusmaVar {
            konusmaSessizSayac = 0
            if durum == .konusmaYok { durum = .caliyor; sesiUygula(0.8) }
        } else {
            konusmaSessizSayac += 1
            if konusmaSessizSayac >= 2, durum == .caliyor { durum = .konusmaYok; sesiUygula(1.2) }
        }
    }

    // MARK: Kilit ekranı (yalnız müzik kipinde)

    private func uzaktanKomutlar() {
        let m = MPRemoteCommandCenter.shared()
        m.playCommand.addTarget { [weak self] _ in self?.baslat(); return .success }
        m.pauseCommand.addTarget { [weak self] _ in self?.durdur(); return .success }
        m.togglePlayPauseCommand.addTarget { [weak self] _ in self?.acKapa(); return .success }
        m.nextTrackCommand.addTarget { [weak self] _ in self?.sonraki(); return .success }
        m.previousTrackCommand.addTarget { [weak self] _ in self?.onceki(); return .success }
        m.changePlaybackPositionCommand.addTarget { [weak self] o in
            guard let o = o as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.atla(o.positionTime)
            return .success
        }
    }

    private func kilitEkraniniGuncelle() {
        let merkez = MPNowPlayingInfoCenter.default()
        guard kip == .yalniz, let p = simdiki else { merkez.nowPlayingInfo = nil; return }
        var bilgi: [String: Any] = [
            MPMediaItemPropertyTitle: p.baslik,
            MPMediaItemPropertyArtist: p.sanatci,
            MPMediaItemPropertyAlbumTitle: p.album,
            MPMediaItemPropertyPlaybackDuration: p.sure,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: motor.konum,
            MPNowPlayingInfoPropertyPlaybackRate: caliyorMu ? 1.0 : 0.0,
        ]
        if let resim = p.kapakResmi {
            bilgi[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: resim.size) { _ in resim }
        }
        merkez.nowPlayingInfo = bilgi
    }

    // MARK: Sistem olayları

    @objc private func kesinti(_ not: Notification) {
        guard let deger = not.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let tur = AVAudioSession.InterruptionType(rawValue: deger) else { return }
        let devamEtsin = (not.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
            .map { AVAudioSession.InterruptionOptions(rawValue: $0).contains(.shouldResume) } ?? false
        Task { @MainActor in
            switch tur {
            case .began:
                // Telefon araması, alarm, Siri; yalnız müzik kipinde başka bir müzik uygulaması da.
                kesintideCaliyordu = caliyorMu
                oturumAcik = false
                if caliyorMu { konum = motor.konum; durum = .durdu; eslikiAyarla(); kilitEkraniniGuncelle() }
            case .ended:
                guard kesintideCaliyordu, kip == .kitapla || devamEtsin, let s = simdiki else { return }
                kesintideCaliyordu = false
                baslat(s, saniye: konum)
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

    /// Örnekleme hızı değişti (ör. Bluetooth kulaklık bağlandı): zinciri yeni hıza bağla, kaldığı yerden sürdür.
    private func motorDegisti() {
        let caliyordu = caliyorMu
        let k = motor.konum
        motor.yenidenBagla()
        if caliyordu, let s = simdiki { baslat(s, saniye: k) }
    }

    @objc private func medyaSifirlandi() {
        Task { @MainActor in
            let caliyordu = caliyorMu
            let k = konum
            oturumAcik = false
            durum = .durdu
            motor = Motor()
            motorBaglantilari()
            hazirlik = nil
            if caliyordu, let s = simdiki { baslat(s, saniye: k) }
        }
    }
}
