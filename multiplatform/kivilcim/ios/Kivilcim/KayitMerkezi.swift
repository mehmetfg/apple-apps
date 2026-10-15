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
    @Published private(set) var sure: TimeInterval = 0
    @Published private(set) var seviyeler: [Float] = []
    @Published var hata: String?
    @Published private(set) var sonKimlik: String?

    static let tavan: TimeInterval = 30 * 60
    private var kaydedici: AVAudioRecorder?
    private var zamanlayici: Timer?
    private var kimlik = ""
    private var baslangic = Date()
    private var kalite = Kalite.dengeli
    private var etkinlik: Activity<KayitEtkinligi>?
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
            // Arama gelirse: o ana kadarki kayıt saklanır.
            guard let t = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt, t == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor in if KayitMerkezi.shared.kayitta { await KayitMerkezi.shared.bitir() } }
        }
    }

    func degistir(kaynak: String = "uygulama") async {
        if kayitta { await bitir() } else { await baslat(kaynak: kaynak) }
    }

    func baslat(kaynak: String = "uygulama") async {
        guard !kayitta else { Tani.yaz("başlat: zaten kayıtta"); return }
        let durum = UIApplication.shared.applicationState
        Tani.yaz("başlat: kaynak=\(kaynak) uygulama=\(durum == .active ? "önde" : durum == .background ? "arka planda" : "geçişte")")
        switch AVAudioApplication.shared.recordPermission {
        case .granted: break
        case .undetermined:
            guard durum == .active else {
                Tani.yaz("HATA: mikrofon izni hiç sorulmamış; kilit ekranında sorulamaz")
                hata = "Önce uygulamayı açıp mikrofon iznini ver."; return
            }
            guard await AVAudioApplication.requestRecordPermission() else { hata = "Mikrofon izni verilmedi."; return }
        default:
            Tani.yaz("HATA: mikrofon izni kapalı")
            hata = "Mikrofon izni kapalı: Ayarlar › Kıvılcım › Mikrofon."; return
        }
        let bos = (try? KayitMerkezi.kayitKlasoru.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? Int64.max
        guard bos > 30_000_000 else { hata = "Telefonda yer çok az (30 MB'tan az)."; Tani.yaz("HATA: yer az"); return }
        kalite = kaliteSecimi
        baslangic = Date()
        kimlik = Kimlik.yeni("iphone", baslangic)
        // Sistem, kilit ekranından başlayan ses kaydında Canlı Etkinliği ÖNCE ister; yoksa kaydı keser.
        etkinlikBaslat()
        do {
            let o = AVAudioSession.sharedInstance()
            try o.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try o.setActive(true)
        } catch {
            Tani.yaz("HATA: ses oturumu açılamadı: \(error.localizedDescription)")
            hata = "Mikrofon açılamadı: \(error.localizedDescription)"; await etkinlikBitir(nil, 0); return
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
                Tani.yaz("HATA: kaydedici başlamadı"); hata = "Kayıt başlamadı."; await etkinlikBitir(nil, 0); return
            }
            kaydedici = k; kayitta = true; sure = 0; seviyeler = []; hata = nil
        } catch {
            Tani.yaz("HATA: kaydedici: \(error.localizedDescription)")
            hata = error.localizedDescription; await etkinlikBitir(nil, 0); return
        }
        Tani.yaz("kayıt başladı \(kimlik) · canlı etkinlik: \(etkinlik == nil ? "YOK" : "var")")
        widgetDurumu(kayitta: true)
        zamanlayici = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { _ in
            Task { @MainActor in KayitMerkezi.shared.tik() }
        }
        if UserDefaults.standard.bool(forKey: "dokunsal") { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    }

    private func tik() {
        guard let k = kaydedici, k.isRecording else { return }
        k.updateMeters()
        sure = k.currentTime
        let db = k.averagePower(forChannel: 0)
        seviyeler.append(max(0.05, min(1, (db + 52) / 52)))
        if seviyeler.count > 80 { seviyeler.removeFirst(seviyeler.count - 80) }
    }

    func bitir() async {
        guard kayitta, let k = kaydedici else { Tani.yaz("bitir: kayıt yoktu"); return }
        let gecen = k.currentTime > 0 ? k.currentTime : Date().timeIntervalSince(baslangic)
        k.stop()
        zamanlayici?.invalidate(); zamanlayici = nil
        kaydedici = nil; kayitta = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let u = KayitMerkezi.kayitKlasoru.appendingPathComponent(kimlik + ".m4a")
        if gecen < 1.0 {
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
        zamanlayici?.invalidate(); zamanlayici = nil; kayitta = false
        try? FileManager.default.removeItem(at: KayitMerkezi.kayitKlasoru.appendingPathComponent(kimlik + ".m4a"))
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        await etkinlikBitir(nil, 0)
        widgetDurumu(kayitta: false)
    }

    private func arkaPlaniKapat() {
        if arkaPlan != .invalid { UIApplication.shared.endBackgroundTask(arkaPlan); arkaPlan = .invalid }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in if KayitMerkezi.shared.kayitta { await KayitMerkezi.shared.bitir() } }
    }

    // MARK: Canlı Etkinlik

    private func etkinlikBaslat() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { Tani.yaz("UYARI: Canlı Etkinlikler kapalı (Ayarlar › Kıvılcım)"); return }
        for a in Activity<KayitEtkinligi>.activities { Task { await a.end(nil, dismissalPolicy: .immediate) } }
        let d = KayitEtkinligi.ContentState(baslangic: baslangic)
        do {
            etkinlik = try Activity.request(attributes: KayitEtkinligi(kalite: kalite.ad),
                                            content: .init(state: d, staleDate: baslangic.addingTimeInterval(KayitMerkezi.tavan)))
        } catch { Tani.yaz("HATA: Canlı Etkinlik başlamadı: \(error.localizedDescription)") }
    }

    private func etkinlikBitir(_ baslik: String?, _ sure: Double) async {
        guard let e = etkinlik else { return }
        if let baslik {
            let d = KayitEtkinligi.ContentState(baslangic: baslangic, bitti: true, sure: sure, baslik: baslik)
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
