// Telefonda kaydın tek merkezi: uygulama içi düğme, kilit ekranı denetimi, widget, Siri — hepsi buraya gelir.
// Kayıt önce telefona yazılır (Application Support/Kivilcim/kayit), bitince künye eklenir ve vault'a gönderilir.
// Kayıt sürerken kilit ekranında ve Dynamic Island'da Canlı Etkinlik durur (sistem ses kaydı niyeti için şart koşar).
import Foundation
import AVFoundation
import ActivityKit
import Speech
import UIKit
import WidgetKit

@MainActor
final class KayitMerkezi: NSObject, ObservableObject, AVAudioRecorderDelegate {
    static let shared = KayitMerkezi()

    @Published private(set) var kayitta = false
    @Published private(set) var duraklatildi = false
    @Published private(set) var sure: TimeInterval = 0
    @Published private(set) var seviyeler: [Float] = []
    @Published var hata: String?
    @Published private(set) var sonKimlik: String?
    /// Son biten kayıt (uygulama içi ada "Kaydedildi" gösterir).
    @Published private(set) var sonBitis: Bitis?
    struct Bitis: Equatable { let an: Date; let baslik: String; let sure: Double }

    static let tavan: TimeInterval = 30 * 60
    private var kaydedici: AVAudioRecorder?
    private var zamanlayici: Timer?
    private var kimlik = ""
    private var baslangic = Date()
    private var kalite = Kalite.dengeli
    private var etkinlik: Activity<KayitEtkinligi>?
    /// Canlı Etkinlik sayacının başlangıcı: her devamda duraklanan süre kadar ileri alınır.
    private var sayacBaslangic = Date()
    private var duraklamaAni: Date?
    private var sonEtkinlikTazesi = Date.distantPast
    private var arkaPlan: UIBackgroundTaskIdentifier = .invalid

    var kaliteSecimi: Kalite { Kalite(rawValue: UserDefaults.standard.string(forKey: "kalite") ?? "") ?? .dengeli }

    static var kayitKlasoru: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Kivilcim/kayit")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    override init() {
        super.init()
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { n in
            guard let t = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
            let basladi = t == AVAudioSession.InterruptionType.began.rawValue
            let neden = (n.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt).map(String.init) ?? "-"
            Task { @MainActor in await KayitMerkezi.shared.kesinti(basladi: basladi, neden: neden) }
        }
    }

    @discardableResult
    func degistir(kaynak: String = "uygulama") async -> Bool {
        // Denetim bazen bir dokunuşu iki kez yolluyor: ikincisi 1 sn sonra gelip yeni kaydı kapatıyordu (2026-10-30)
        if kayitta, Date().timeIntervalSince(baslangic) < 1.5 { Tani.yaz("değiştir: kayıt yeni başladı, ikinci dokunuş yok sayıldı"); return true }
        if kayitta { await bitir(); return true }
        return await baslat(kaynak: kaynak)
    }

    /// Kayıt başladıysa true. Arka planda mikrofon açılamazsa false döner; niyet o zaman öne geçip yeniden dener.
    @discardableResult
    func baslat(kaynak: String = "uygulama") async -> Bool {
        guard !kayitta else { Tani.yaz("başlat: zaten kayıtta"); return true }
        // İkon menüsü / "Aç ve kaydet" sırasında uygulama henüz öne gelmemişken açılan kaydedici ~1 sn'de duruyordu
        // (2026-10-11…30 tanı kaydı, "geçişte" → "1 sn"); öne gelmesini en çok 2 sn bekle.
        var bekleme = 0
        while UIApplication.shared.applicationState == .inactive && bekleme < 40 {
            try? await Task.sleep(for: .milliseconds(50)); bekleme += 1
        }
        let durum = UIApplication.shared.applicationState
        Tani.yaz("başlat: kaynak=\(kaynak) uygulama=\(durum == .active ? "önde" : durum == .background ? "arka planda" : "geçişte")")
        switch AVAudioApplication.shared.recordPermission {
        case .granted: break
        case .undetermined:
            guard durum == .active else {
                Tani.yaz("HATA: mikrofon izni hiç sorulmamış; kilit ekranında sorulamaz")
                hata = "Önce uygulamayı açıp mikrofon iznini ver."; return false
            }
            guard await AVAudioApplication.requestRecordPermission() else { hata = "Mikrofon izni verilmedi."; return false }
        default:
            Tani.yaz("HATA: mikrofon izni kapalı")
            hata = "Mikrofon izni kapalı: Ayarlar › Kıvılcım › Mikrofon."; return false
        }
        let bos = (try? KayitMerkezi.kayitKlasoru.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? Int64.max
        guard bos > 30_000_000 else { hata = "Telefonda yer çok az (30 MB'tan az)."; Tani.yaz("HATA: yer az"); return false }
        kalite = kaliteSecimi
        baslangic = Date()
        sayacBaslangic = baslangic; duraklamaAni = nil; duraklatildi = false
        kimlik = Kimlik.yeni("iphone", baslangic)
        // Sistem, kilit ekranından başlayan ses kaydında Canlı Etkinliği ÖNCE ister; yoksa kaydı keser.
        etkinlikBaslat()
        do {
            let o = AVAudioSession.sharedInstance()
            try o.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            do { try o.setActive(true) } catch where durum == .background {
                // arka planda karışmasız oturum başkasını kesemeyebilir: karışan oturumla bir kez daha dene
                Tani.yaz("ses oturumu arka planda açılamadı (\((error as NSError).code)); karışan oturumla yeniden")
                try o.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers])
                try o.setActive(true)
            }
        } catch {
            Tani.yaz("HATA: ses oturumu açılamadı (\((error as NSError).code)): \(error.localizedDescription)")
            hata = "Mikrofon açılamadı: \(error.localizedDescription)"; await etkinlikBitir(nil, 0); return false
        }
        let u = KayitMerkezi.kayitKlasoru.appendingPathComponent(kimlik + ".m4a")
        let ayar: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: kalite.hz, AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: kalite.bit, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            let k = try AVAudioRecorder(url: u, settings: ayar)
            k.delegate = self
            k.isMeteringEnabled = true
            guard k.record(forDuration: KayitMerkezi.tavan) else {
                Tani.yaz("HATA: kaydedici başlamadı"); hata = "Kayıt başlamadı."; await etkinlikBitir(nil, 0); return false
            }
            kaydedici = k; kayitta = true; sure = 0; seviyeler = []; hata = nil
        } catch {
            Tani.yaz("HATA: kaydedici: \(error.localizedDescription)")
            hata = error.localizedDescription; await etkinlikBitir(nil, 0); return false
        }
        Tani.yaz("kayıt başladı \(kimlik) · canlı etkinlik: \(etkinlik == nil ? "YOK" : "var")")
        widgetDurumu(kayitta: true)
        // Uygulama dışından başladıysa: adasız telefonda (13 Pro Max) üstte ada gibi şerit, adalıda ada bir an açılır.
        // Uyarının sesi oturumu kısa kesebilir; kesinti() kaydı bitirmez, sürdürür. Uygulama öndeyse içteki ada yeter.
        if durum == .active { await etkinlikTazele() }
        else { await etkinlikTazele(uyari: AlertConfiguration(title: "Kıvılcım dinliyor", body: "Bitirmek için ■", sound: .named("sessiz.caf"))) }
        zamanlayici = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { _ in
            Task { @MainActor in KayitMerkezi.shared.tik() }
        }
        if UserDefaults.standard.bool(forKey: "dokunsal") { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
        return true
    }

    private func tik() {
        guard let k = kaydedici, k.isRecording else { return }
        k.updateMeters()
        sure = k.currentTime
        let db = k.averagePower(forChannel: 0)
        seviyeler.append(max(0.05, min(1, (db + 52) / 52)))
        if seviyeler.count > 80 { seviyeler.removeFirst(seviyeler.count - 80) }
        // duraklatma record(forDuration:) tavanını düşürür; tavanı burada tutarız
        if sure >= KayitMerkezi.tavan { Task { await bitir() }; return }
        if Date().timeIntervalSince(sonEtkinlikTazesi) >= 1 { sonEtkinlikTazesi = Date(); Task { await etkinlikTazele() } }
    }

    /// Kısa kesinti (bildirim sesi, Canlı Etkinlik uyarısı) kaydı bitirmez: biterse kayıt kaldığı yerden sürer.
    /// 4 sn içinde bitmezse (arama vb.) o ana kadarki kayıt saklanır.
    private var kesintide = false
    func kesinti(basladi: Bool, neden: String) async {
        guard kayitta else { return }
        if basladi {
            Tani.yaz("ses kesintisi başladı (neden: \(neden))")
            kesintide = true
            try? await Task.sleep(for: .seconds(4))
            if kesintide, kayitta { Tani.yaz("kesinti sürüyor → kayıt saklanıyor"); kesintide = false; await bitir() }
        } else if kesintide {
            kesintide = false
            guard !duraklatildi, let k = kaydedici else { return }
            try? AVAudioSession.sharedInstance().setActive(true)
            Tani.yaz("kesinti bitti → kayıt \(k.record() ? "sürüyor" : "SÜRDÜRÜLEMEDİ")")
        }
    }

    func duraklatDegistir() async {
        guard kayitta, let k = kaydedici else { return }
        if duraklatildi {
            if !k.record() {
                // arka planda duraklarken oturum düşmüş olabilir: karışan oturumla yeniden aç, bir kez daha dene
                let o = AVAudioSession.sharedInstance()
                try? o.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers])
                try? o.setActive(true)
                guard k.record() else { Tani.yaz("HATA: devam edilemedi"); return }
                Tani.yaz("devam: oturum yeniden açılarak sürdü")
            }
            if let d = duraklamaAni { sayacBaslangic = sayacBaslangic.addingTimeInterval(Date().timeIntervalSince(d)) }
            duraklamaAni = nil; duraklatildi = false
            Tani.yaz("kayıt sürüyor")
        } else {
            k.pause()
            duraklamaAni = Date(); duraklatildi = true
            Tani.yaz("kayıt duraklatıldı · \(Int(k.currentTime)) sn")
        }
        if UserDefaults.standard.bool(forKey: "dokunsal") { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        await etkinlikTazele()
    }

    func bitir() async {
        guard kayitta, let k = kaydedici else { Tani.yaz("bitir: kayıt yoktu"); return }
        let gecen = k.currentTime > 0 ? k.currentTime : Date().timeIntervalSince(baslangic)
        k.stop()
        zamanlayici?.invalidate(); zamanlayici = nil
        kaydedici = nil; kayitta = false; duraklatildi = false; duraklamaAni = nil; kesintide = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let u = KayitMerkezi.kayitKlasoru.appendingPathComponent(kimlik + ".m4a")
        if gecen < 1.0 {
            Tani.yaz("bitir: 1 sn'den kısa → silindi")
            try? FileManager.default.removeItem(at: u)
            await etkinlikBitir(nil, 0)
            widgetDurumu(kayitta: false)
            return
        }
        if UserDefaults.standard.bool(forKey: "dokunsal") { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        arkaPlan = UIApplication.shared.beginBackgroundTask(withName: "kivilcim-kaydet") { [weak self] in
            Task { @MainActor in self?.arkaPlaniKapat() }
        }
        let kunye = Kunye(id: kimlik, cihaz: "iphone", zaman: Zaman.iso(baslangic), sure: (gecen * 10).rounded() / 10,
                          kalite: kalite.rawValue, dil: UserDefaults.standard.string(forKey: "dil") ?? "tr", onMetin: nil)
        sonKimlik = kimlik
        Tani.yaz("kayıt bitti \(kimlik) · \(Int(gecen)) sn")
        let depo = TelefonDeposu.shared
        depo.yeniKayit(kunye)
        sonBitis = Bitis(an: Date(), baslik: depo.oge(kimlik)?.baslik ?? "Sesli fikir", sure: gecen)
        await etkinlikBitir(depo.oge(kimlik)?.baslik, gecen)
        widgetDurumu(kayitta: false)
        await depo.gonder()                                  // vault'a hemen (olmazsa sonra yeniden dener)
        if UserDefaults.standard.bool(forKey: "onDokum") {
            if let metin = await KayitMerkezi.tani(u, dil: kunye.dil) {
                depo.onMetin(kimlik, metin)
                await depo.gonder()
            }
        }
        arkaPlaniKapat()
    }

    func vazgec() async {
        guard kayitta else { return }
        kaydedici?.stop(); kaydedici = nil
        zamanlayici?.invalidate(); zamanlayici = nil; kayitta = false; duraklatildi = false; duraklamaAni = nil
        Tani.yaz("kayıttan vazgeçildi")
        try? FileManager.default.removeItem(at: KayitMerkezi.kayitKlasoru.appendingPathComponent(kimlik + ".m4a"))
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        await etkinlikBitir(nil, 0)
        widgetDurumu(kayitta: false)
    }

    private func arkaPlaniKapat() {
        if arkaPlan != .invalid { UIApplication.shared.endBackgroundTask(arkaPlan); arkaPlan = .invalid }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            guard KayitMerkezi.shared.kayitta else { return }
            Tani.yaz("kaydedici kendiliğinden durdu (başarılı: \(flag ? "evet" : "HAYIR")) · \(Int(recorder.currentTime)) sn")
            await KayitMerkezi.shared.bitir()
        }
    }

    // MARK: Canlı Etkinlik

    private func etkinlikBaslat() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { Tani.yaz("UYARI: Canlı Etkinlikler kapalı (Ayarlar › Kıvılcım)"); return }
        let eskiler = Activity<KayitEtkinligi>.activities
        Task { for a in eskiler { await a.end(nil, dismissalPolicy: .immediate) } }
        let d = KayitEtkinligi.ContentState(baslangic: baslangic)
        do {
            etkinlik = try Activity.request(attributes: KayitEtkinligi(kalite: kalite.ad),
                                            content: .init(state: d, staleDate: baslangic.addingTimeInterval(KayitMerkezi.tavan)))
        } catch { Tani.yaz("HATA: Canlı Etkinlik başlamadı: \(error.localizedDescription)") }
    }

    /// Sayaç, duraklama ve son düzeyleri Canlı Etkinliğe yollar (saniyede bir; sistem sıklığı kendisi de kısar).
    private func etkinlikTazele(uyari: AlertConfiguration? = nil) async {
        guard let e = etkinlik, kayitta else { return }
        sonEtkinlikTazesi = Date()
        let d = KayitEtkinligi.ContentState(baslangic: sayacBaslangic, duraklama: duraklamaAni, seviyeler: dalga())
        await e.update(.init(state: d, staleDate: Date().addingTimeInterval(KayitMerkezi.tavan)), alertConfiguration: uyari)
    }

    /// Son ~3 saniyenin düzeyleri 18 çubuğa indirgenir (her çubuk kendi diliminin tepesi).
    private func dalga() -> [Double] {
        let adet = 18
        if duraklatildi { return Array(repeating: 0.06, count: adet) }
        let son = Array(seviyeler.suffix(adet * 2))
        guard !son.isEmpty else { return [] }
        let dilim = max(1, son.count / adet)
        return stride(from: 0, to: son.count, by: dilim).prefix(adet).map { i in
            (Double(son[i..<min(son.count, i + dilim)].max() ?? 0) * 100).rounded() / 100
        }
    }

    private func etkinlikBitir(_ baslik: String?, _ sure: Double) async {
        guard let e = etkinlik else { return }
        if let baslik {
            let d = KayitEtkinligi.ContentState(baslangic: baslangic, bitti: true, sure: sure, baslik: baslik)
            // adasız telefonda "kaydedildi" şeridi; adalı telefonda ada bir an açılıp onay gösterir
            await e.update(.init(state: d, staleDate: nil),
                           alertConfiguration: AlertConfiguration(title: "Kaydedildi", body: "\(baslik)", sound: .named("sessiz.caf")))
            await e.end(.init(state: d, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(6)))
        } else {
            await e.end(nil, dismissalPolicy: .immediate)
        }
        etkinlik = nil
    }

    private func widgetDurumu(kayitta: Bool) {
        WidgetDurumu.d.set(kayitta, forKey: "kayitta")
        WidgetCenter.shared.reloadAllTimelines()
        if #available(iOS 18.0, *) { ControlCenter.shared.reloadAllControls() }
    }

    // MARK: Cihaz içi ön döküm (isteğe bağlı; asıl döküm Mac'te Whisper)

    static func tani(_ u: URL, dil: String) async -> String? {
        // izin sorusu kilit ekranında gösterilemez: arka plandaysa ve henüz sorulmadıysa atla
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined,
           await UIApplication.shared.applicationState != .active { return nil }
        let durum: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard durum == .authorized else { return nil }
        let yerel = dil == "en" ? "en-US" : "tr-TR"
        guard let tanici = SFSpeechRecognizer(locale: Locale(identifier: yerel)), tanici.isAvailable else { return nil }
        let istek = SFSpeechURLRecognitionRequest(url: u)
        istek.shouldReportPartialResults = true
        if tanici.supportsOnDeviceRecognition { istek.requiresOnDeviceRecognition = true }
        else if !UserDefaults.standard.bool(forKey: "sunucuDokum") { return nil }   // ses Apple'a gitmesin
        istek.taskHint = .dictation
        istek.addsPunctuation = true
        return await withCheckedContinuation { (c: CheckedContinuation<String?, Never>) in
            let b = Biriktirici()
            tanici.recognitionTask(with: istek) { sonuc, hata in
                _ = tanici   // the recognizer must stay alive until the task ends, or the callback never fires
                if b.bitti { return }
                if let sonuc {
                    b.ekle(sonuc.bestTranscription.formattedString, parcaSonu: sonuc.speechRecognitionMetadata != nil)
                    if sonuc.isFinal { b.bitti = true; c.resume(returning: b.metin) }
                } else if hata != nil {
                    b.bitti = true
                    c.resume(returning: b.metin.isEmpty ? nil : b.metin)
                }
            }
        }
    }
}

/// Uzun kayıtta tanıyıcı parça parça verir; parçaları kayıpsız birleştirir (Memories'te bulunan hata, aynı çözüm).
final class Biriktirici: @unchecked Sendable {
    var bitti = false
    private var kalici: [String] = []
    private var simdiki = ""
    func ekle(_ t: String, parcaSonu: Bool) {
        if let l = kalici.last, t == l { simdiki = ""; return }
        let once = kalici.joined(separator: " ")
        if !once.isEmpty, t.hasPrefix(once) { kalici = []; simdiki = t } else { simdiki = t }
        if parcaSonu, !simdiki.isEmpty { kalici.append(simdiki); simdiki = "" }
    }
    var metin: String { (kalici + (simdiki.isEmpty ? [] : [simdiki])).joined(separator: " ") }
}
