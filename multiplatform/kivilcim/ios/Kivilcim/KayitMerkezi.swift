// Telefonda kaydın tek merkezi: uygulama içi düğme, kilit ekranı denetimi, widget, Siri — hepsi buraya gelir.
// Kayıt önce telefona yazılır (Application Support/Kivilcim/kayit), bitince künye eklenir ve vault'a gönderilir.
// Kayıt sürerken kilit ekranında ve Dynamic Island'da Canlı Etkinlik durur (sistem ses kaydı niyeti için şart koşar).
import Foundation
import AVFoundation
import ActivityKit
import Speech
import SoundAnalysis
import SwiftUI
import UIKit
import WidgetKit

@MainActor
final class KayitMerkezi: NSObject, ObservableObject, AVAudioRecorderDelegate {
    static let shared = KayitMerkezi()

    @Published private(set) var kayitta = false
    @Published private(set) var duraklatildi = false
    /// Level and elapsed time change about 14 times a second: they are published by `meter`, not by this object,
    /// so a tick redraws only the views that show them (RecordingClock, MeterBars, MeterWave).
    let meter = RecordingMeter()
    var sure: TimeInterval { meter.sure }
    var seviyeler: [Float] { meter.seviyeler }
    @Published var hata: String?
    @Published private(set) var sonKimlik: String?
    /// Son biten kayıt (uygulama içi ada "Kaydedildi" gösterir).
    @Published private(set) var sonBitis: Bitis?
    struct Bitis: Equatable { let an: Date; let baslik: String; let sure: Double; var id: String = ""; var kind: String = "spark" }
    /// spark (short idea) or journal (long spoken diary); the next recording uses this unless the caller names one.
    @Published var kind = UserDefaults.standard.string(forKey: "kayitTuru") ?? "spark" {
        didSet { UserDefaults.standard.set(kind, forKey: "kayitTuru") }
    }
    @Published private(set) var aktifTur = "spark"
    /// The book/topic this recording is about, when another app started it with kivilcim://kaydet?topic=…
    /// (a Teoria book id or "k:<name>"). Goes into the sidecar's `topic`, the field the Mac writes for a topic
    /// chosen before recording, so links.py treats both the same. nil for every other way of starting.
    @Published private(set) var activeTopic: String?
    /// The app this recording is about, when it was started from that app's page (Merkez › Uygulamalar).
    @Published private(set) var activeApp: String?
    /// After a spark ends in the app: the quick sheet (title · priority · note) opens for this id.
    @Published var hizliDuzen: String?

    static let tavan: TimeInterval = 30 * 60
    static let gunlukTavan: TimeInterval = 60 * 60
    var tavan: TimeInterval {
        surekli ? Continuous.partCap : aktifTur == "journal" ? KayitMerkezi.gunlukTavan : KayitMerkezi.tavan
    }

    // MARK: Continuous mode (2026-11-08)
    // Start once, listen all day. The recorder never stops; the phone only decides which stretches to keep:
    // a part with speech closes after a minute of silence (or at 10 min) and is sent; a part with no speech is
    // thrown away after a minute and starts over. So a 20-minute silent walk costs at most one minute on disk.

    enum Continuous {
        static let partCap: TimeInterval = 10 * 60
        /// speech, then this much silence → the part is closed and sent
        static let closeAfterSilence: TimeInterval = 60
        /// no speech for this long at the start of a part → the part is discarded and starts over
        static let discardAfter: TimeInterval = 60
        /// less speech than this in a part → it holds nothing worth keeping (a cough, a door)
        static let minSpeech: TimeInterval = 2
        /// level above the running noise floor that counts as sound worth listening to
        static let speechMargin: Float = 10
        /// a single click or step is not speech: the level must stay up this long (5 meter ticks)
        static let speechHold: TimeInterval = 0.35
        /// Apple's on-device sound classifier: a window counts as speech above this confidence. Measured
        /// 2026-11-08 on a real room + synthetic speech: quiet room 0.5 s in 120 s, a −26 dB whisper 6 s in 7 s.
        static let classifierSpeech: Double = 0.7
        static let lowBattery: Float = 0.15
    }
    var surekli: Bool { aktifTur == "continuous" }
    /// Parts kept (sent) in this continuous session; shown under the clock.
    @Published private(set) var keptParts = 0
    @Published private(set) var speaking = false
    private var noiseFloor: Float = -50
    private var speechInPart: TimeInterval = 0
    private var lastSpeechAt: TimeInterval = 0
    private var lastTickAt: TimeInterval = 0
    private var loudFor: TimeInterval = 0
    private var lastBatteryCheck = Date.distantPast
    private var kaydedici: AVAudioRecorder?
    private var zamanlayici: Timer?
    private var kimlik = ""
    private var baslangic = Date()
    private var kalite = Kalite.dengeli
    private var etkinlik: Activity<KayitEtkinligi>?
    /// Canlı Etkinlik sayacının başlangıcı: her devamda duraklanan süre kadar ileri alınır.
    private var sayacBaslangic = Date()
    private var duraklamaAni: Date?
    private var arkaPlan: UIBackgroundTaskIdentifier = .invalid
    /// A long talk does not stop at the cap: it goes on in a new part (2026-11-04; on 11-03 a 30 min cap
    /// silently cut the evening talk at 22:05). Each part is its own file and note, linked to the one before.
    private var parca = 1
    private var oncekiParca: String?
    private var parcaGeciyor = false
    private var oncekiToplam: TimeInterval = 0

    var kaliteSecimi: Kalite { Kalite(rawValue: UserDefaults.standard.string(forKey: "kalite") ?? "") ?? .dengeli }

    nonisolated static var kayitKlasoru: URL {
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
            // background time is taken here, synchronously: once the call takes the microphone the app has no
            // audio to keep it awake, and iOS may suspend it before the save below gets to run
            if basladi { MainActor.assumeIsolated { KayitMerkezi.shared.kesintiZamani() } }
            Task { @MainActor in await KayitMerkezi.shared.kesinti(basladi: basladi, neden: neden) }
        }
        // the audio system restarted (rare): the recorder is dead, so what it holds is saved now
        NotificationCenter.default.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                guard KayitMerkezi.shared.kayitta else { return }
                Tani.yaz("ses sistemi yeniden başladı → kayıt saklanıyor")
                await KayitMerkezi.shared.bitir()
            }
        }
        // the app is being closed (swiped away, or iOS ends it while it runs): there is no time for anything async,
        // so the file is closed and its sidecar written right here; it goes to the vault on the next launch
        NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { KayitMerkezi.shared.acilKaydet(neden: "uygulama kapanıyor") }
        }
    }

    // MARK: Never lose a recording (2026-11-10)

    private var kesintiGorevi: UIBackgroundTaskIdentifier = .invalid
    /// Continuous listening stopped for a call: it starts again by itself when the call is over.
    private var resumeContinuous = false

    fileprivate func kesintiZamani() {
        guard kayitta, kesintiGorevi == .invalid else { return }
        kesintiGorevi = UIApplication.shared.beginBackgroundTask(withName: "kivilcim-kesinti") { [weak self] in
            MainActor.assumeIsolated {
                // time is up and the recording is still open: close it now, synchronously
                self?.acilKaydet(neden: "kesintide arka plan süresi bitti")
                self?.kesintiBitir()
            }
        }
    }

    private func kesintiBitir() {
        if kesintiGorevi != .invalid { UIApplication.shared.endBackgroundTask(kesintiGorevi); kesintiGorevi = .invalid }
    }

    /// Closes the open recording without any await: the recorder finalizes the file inside stop(), the sidecar is
    /// a small synchronous write. For the moments when the async bitir() would not get to run.
    func acilKaydet(neden: String) {
        guard kayitta, let k = kaydedici else { return }
        let gecen = k.currentTime > 0 ? k.currentTime : Date().timeIntervalSince(baslangic)
        k.delegate = nil
        k.stop()
        zamanlayici?.invalidate(); zamanlayici = nil
        kaydedici = nil; kayitta = false; duraklatildi = false; duraklamaAni = nil; kesintide = false
        Tani.yaz("acil kayıt (\(neden)) \(kimlik) · \(Int(gecen)) sn")
        if gecen >= 1.0 {
            TelefonDeposu.shared.yeniKayit(sidecar(kimlik, baslangic, gecen, devam: oncekiParca))
        } else {
            try? FileManager.default.removeItem(at: KayitMerkezi.kayitKlasoru.appendingPathComponent(kimlik + ".m4a"))
        }
        WidgetDurumu.d.set(false, forKey: "kayitta")
        if let e = etkinlik { etkinlik = nil; Task { await e.end(nil, dismissalPolicy: .immediate) } }
    }

    /// Recordings whose sidecar was never written (the app was killed while recording, or the phone shut down):
    /// the list is taken at launch, before any new recording can start, and each file that plays is added as a
    /// normal recording. An empty file from a start that failed is removed; a file that cannot be read is moved
    /// to kayit/bozuk, kept for repair on the Mac, and not tried again.
    nonisolated static func recoverOrphans() {
        let fm = FileManager.default
        let dir = kayitKlasoru
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return }
        let orphans = files.filter {
            $0.pathExtension == "m4a" && !fm.fileExists(atPath: $0.deletingPathExtension().appendingPathExtension("json").path)
        }
        guard !orphans.isEmpty else { return }
        Task { @MainActor in
            var found = 0
            for u in orphans {
                let id = u.deletingPathExtension().lastPathComponent
                let size = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                let sure = (try? await AVURLAsset(url: u).load(.duration).seconds) ?? 0
                if sure.isFinite, sure >= 1 {
                    let an = orphanDate(id) ?? ((try? u.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date())
                    let k = Kunye(id: id, cihaz: "iphone", zaman: Zaman.iso(an), sure: (sure * 10).rounded() / 10,
                                  kalite: KayitMerkezi.shared.kaliteSecimi.rawValue,
                                  dil: UserDefaults.standard.string(forKey: "dil") ?? "tr", onMetin: nil, kind: "spark")
                    TelefonDeposu.shared.yeniKayit(k)
                    found += 1
                    Tani.yaz("kurtarıldı: \(id) · \(Int(sure)) sn")
                } else if size < 8_192 {
                    try? fm.removeItem(at: u)
                    Tani.yaz("boş kayıt dosyası silindi: \(id) (\(size) bayt)")
                } else {
                    let bozuk = dir.appendingPathComponent("bozuk")
                    try? fm.createDirectory(at: bozuk, withIntermediateDirectories: true)
                    try? fm.moveItem(at: u, to: bozuk.appendingPathComponent(u.lastPathComponent))
                    Tani.yaz("HATA: \(id) okunamadı (\(size / 1024) KB) → kayit/bozuk'ta saklandı")
                }
            }
            if found > 0 { await TelefonDeposu.shared.gonder() }
        }
    }

    nonisolated private static func orphanDate(_ id: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .autoupdatingCurrent; f.dateFormat = "yyyyMMdd-HHmmss"
        return f.date(from: String(id.prefix(15)))
    }

    @discardableResult
    func degistir(kaynak: String = "uygulama", tur: String? = nil) async -> Bool {
        // Denetim bazen bir dokunuşu iki kez yolluyor: ikincisi 1 sn sonra gelip yeni kaydı kapatıyordu (2026-10-30)
        if kayitta, Date().timeIntervalSince(baslangic) < 1.5 { Tani.yaz("değiştir: kayıt yeni başladı, ikinci dokunuş yok sayıldı"); return true }
        if kayitta { await bitir(); return true }
        return await baslat(kaynak: kaynak, tur: tur)
    }

    /// Kayıt başladıysa true. Arka planda mikrofon açılamazsa false döner; niyet o zaman öne geçip yeniden dener.
    @discardableResult
    func baslat(kaynak: String = "uygulama", tur: String? = nil, topic: String? = nil, app: String? = nil) async -> Bool {
        guard !kayitta else { Tani.yaz("başlat: zaten kayıtta"); return true }
        aktifTur = tur ?? kind
        activeTopic = topic
        activeApp = app
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
        kalite = kaliteSecimi
        baslangic = Date()
        sayacBaslangic = baslangic; duraklamaAni = nil; duraklatildi = false
        parca = 1; oncekiParca = nil; parcaGeciyor = false; oncekiToplam = 0
        resetSpeech(); keptParts = 0; noiseFloor = -50
        if surekli { UIDevice.current.isBatteryMonitoringEnabled = true }
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
            // 30 s of slack past the cap: the tick rolls over to the next part at cap − 0.5 s; if the main actor
            // is late, the recorder must still be running, or the talk would end at the cap instead of going on.
            guard k.record(forDuration: tavan + 30) else {
                Tani.yaz("HATA: kaydedici başlamadı"); hata = "Kayıt başlamadı."; await etkinlikBitir(nil, 0); return false
            }
            kaydedici = k; kayitta = true; meter.sure = 0; meter.seviyeler = []; hata = nil
        } catch {
            Tani.yaz("HATA: kaydedici: \(error.localizedDescription)")
            hata = error.localizedDescription; await etkinlikBitir(nil, 0); return false
        }
        Tani.yaz("kayıt başladı \(kimlik) · canlı etkinlik: \(etkinlik == nil ? "YOK" : "var")")
        yerDenetle(kimlik)
        KivilcimBus.publishLive(id: kimlik, active: true)
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

    /// Free space is looked at after capture has begun, off the main thread: the query is not needed to start and
    /// can take a while. Under 30 MB the recording stops at once with the same message as before; what was
    /// captured is kept by the usual rules (bitir()).
    private func yerDenetle(_ baslayan: String) {
        Task {
            let bos = await Task.detached(priority: .userInitiated) {
                (try? KayitMerkezi.kayitKlasoru.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
                    .volumeAvailableCapacityForImportantUsage ?? Int64.max
            }.value
            guard bos <= 30_000_000, kayitta, kimlik == baslayan else { return }
            Tani.yaz("HATA: yer az")
            await bitir()
            hata = "Telefonda yer çok az (30 MB'tan az)."
        }
    }

    private func tik() {
        guard let k = kaydedici, k.isRecording else { return }
        k.updateMeters()
        meter.sure = oncekiToplam + k.currentTime   // the screen counts the whole talk, not the part
        let db = k.averagePower(forChannel: 0)
        // the level bars are only drawn inside the app: on the lock screen nobody sees them, so skip the work
        if UIApplication.shared.applicationState == .active {
            var s = meter.seviyeler
            s.append(max(0.05, min(1, (db + 52) / 52)))
            if s.count > 80 { s.removeFirst(s.count - 80) }
            meter.seviyeler = s
        }
        if surekli, !parcaGeciyor, let karar = listen(db: db, t: k.currentTime) {
            parcaGeciyor = true; Task { await parcaDegistir(karar) }; return
        }
        // duraklatma record(forDuration:) tavanını düşürür; tavanı burada tutarız.
        // Tavan dolunca kayıt bitmez: yeni parçaya geçer (konuşma kaybolmasın).
        if k.currentTime >= tavan - 0.5, !parcaGeciyor { parcaGeciyor = true; Task { await parcaDegistir(.cap) }; return }
        // No Live Activity update here (2026-11-10): its clock is the system timer and runs by itself. The old
        // once-a-second waveform update was throttled by the system and made the lock-screen card move in jerks.
    }

    enum PartEnd { case cap, silence, empty }

    private func resetSpeech() { speechInPart = 0; lastSpeechAt = 0; lastTickAt = 0; loudFor = 0; speaking = false }

    /// One tick of the level detector: cheap, every meter tick, decides only when a part ends. Whether a closed
    /// part holds speech is decided afterwards by Apple's classifier (`speechSeconds`), because level alone cannot
    /// tell a voice from a keyboard or a fan (2026-11-08 test: a silent room kept a part open for minutes).
    /// The floor follows the room within seconds, so a steady noise stops counting quickly.
    private func listen(db: Float, t: TimeInterval) -> PartEnd? {
        let dt = max(0, min(0.5, t - lastTickAt)); lastTickAt = t
        noiseFloor += (db - noiseFloor) * (db < noiseFloor ? 0.02 : 0.01)
        noiseFloor = max(-80, min(-20, noiseFloor))
        let loud = db > noiseFloor + Continuous.speechMargin && db > -60
        loudFor = loud ? loudFor + dt : 0
        let now = loudFor >= Continuous.speechHold
        if now { speechInPart += dt; lastSpeechAt = t }
        // held for 1.5 s after the last word, so the screen does not flicker (and redraw) between syllables
        let shown = lastSpeechAt > 0 && t - lastSpeechAt < 1.5
        if shown != speaking { speaking = shown }
        if Date().timeIntervalSince(lastBatteryCheck) >= 60 { lastBatteryCheck = Date(); checkBattery() }
        let quiet = t - lastSpeechAt
        if speechInPart >= Continuous.minSpeech, quiet >= Continuous.closeAfterSilence { return .silence }
        if speechInPart < Continuous.minSpeech, quiet >= Continuous.discardAfter { return .empty }
        return nil
    }

    /// Runs Apple's sound classifier over a closed part. Under `minSpeech` seconds of speech the file is deleted
    /// and false comes back. If the classifier cannot run, the part is kept (Whisper on the Mac drops silence).
    private func keepIfSpeech(_ u: URL, _ gecen: TimeInterval) async -> Bool {
        let s = await Task.detached(priority: .utility) { KayitMerkezi.speechSeconds(u) }.value
        guard let s else { Tani.yaz("sürekli: sınıflandırıcı çalışmadı → parça saklanıyor"); return true }
        if s >= Continuous.minSpeech { Tani.yaz("sürekli: \(Int(gecen)) sn parçada \(String(format: "%.1f", s)) sn konuşma → saklandı"); return true }
        try? FileManager.default.removeItem(at: u)
        Tani.yaz("sürekli: \(Int(gecen)) sn parçada konuşma yok (\(String(format: "%.1f", s)) sn) → silindi")
        return false
    }

    /// Seconds of speech in a file by the built-in classifier: 1 s windows, half overlapping, so each window over
    /// the threshold adds 0.5 s. nil when the classifier is not available.
    nonisolated static func speechSeconds(_ u: URL) -> Double? {
        guard let analyzer = try? SNAudioFileAnalyzer(url: u),
              let request = try? SNClassifySoundRequest(classifierIdentifier: .version1) else { return nil }
        request.windowDuration = CMTime(seconds: 1, preferredTimescale: 1000)
        request.overlapFactor = 0.5
        let counter = SpeechCounter(threshold: Continuous.classifierSpeech)
        guard (try? analyzer.add(request, withObserver: counter)) != nil else { return nil }
        analyzer.analyze()
        return counter.failed ? nil : Double(counter.windows) * 0.5
    }

    private func checkBattery() {
        let d = UIDevice.current
        guard d.batteryLevel >= 0, d.batteryLevel < Continuous.lowBattery, d.batteryState == .unplugged else { return }
        Tani.yaz("sürekli: pil %\(Int(d.batteryLevel * 100)) → dinleme bitiyor")
        Task {
            await bitir()
            hata = "Pil %\(Int(Continuous.lowBattery * 100))'in altına indi; sürekli dinleme durdu."
        }
    }

    private func sidecar(_ id: String, _ an: Date, _ gecen: TimeInterval, devam: String?) -> Kunye {
        Kunye(id: id, cihaz: "iphone", zaman: Zaman.iso(an), sure: (gecen * 10).rounded() / 10,
              kalite: kalite.rawValue, dil: UserDefaults.standard.string(forKey: "dil") ?? "tr", onMetin: nil,
              kind: surekli ? "journal" : aktifTur, devam: devam, topic: activeTopic, mode: surekli ? "continuous" : nil, app: activeApp)
    }

    /// Kısa kesinti (bildirim sesi, Canlı Etkinlik uyarısı) kaydı bitirmez: biterse kayıt kaldığı yerden sürer.
    /// 4 sn içinde bitmezse (arama vb.) o ana kadarki kayıt saklanır.
    private var kesintide = false
    func kesinti(basladi: Bool, neden: String) async {
        if !basladi, resumeContinuous, !kayitta {
            resumeContinuous = false
            let ok = await baslat(kaynak: "çağrıdan sonra", tur: "continuous")
            Tani.yaz("sürekli dinleme çağrıdan sonra \(ok ? "yeniden başladı" : "BAŞLAYAMADI (uygulamadan yeniden başlat)")")
            return
        }
        guard kayitta else { return }
        if basladi {
            Tani.yaz("ses kesintisi başladı (neden: \(neden))")
            kesintide = true
            defer { kesintiBitir() }
            try? await Task.sleep(for: .seconds(4))
            guard kesintide, kayitta else { return }
            // A call (or anything that holds the microphone longer than an alert sound): what was recorded is saved
            // now, under the background time taken when the interruption began. Continuous listening too, since an
            // open file left waiting through a call is lost if iOS ends the app meanwhile; it starts again after.
            if surekli { resumeContinuous = true }
            Tani.yaz("kesinti sürüyor → kayıt saklanıyor\(surekli ? " · sürekli dinleme çağrıdan sonra sürecek" : "")")
            kesintide = false
            await bitir()
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
        speaking = false
        // the background time starts before the classifier: with the microphone off the app may be suspended
        arkaPlan = UIApplication.shared.beginBackgroundTask(withName: "kivilcim-kaydet") { [weak self] in
            Task { @MainActor in self?.arkaPlaniKapat() }
        }
        var emptyContinuous = surekli && speechInPart < Continuous.minSpeech
        if surekli, !emptyContinuous, gecen >= 1.0, !(await keepIfSpeech(u, gecen)) { emptyContinuous = true }
        if gecen < 1.0 || emptyContinuous {
            Tani.yaz(emptyContinuous ? "bitir: sürekli dinleme bitti · son parçada konuşma yok → silindi · \(keptParts) parça saklandı"
                                     : "bitir: 1 sn'den kısa → silindi")
            KivilcimBus.publishLive(id: sonBitis?.id, active: false)
            try? FileManager.default.removeItem(at: u)
            await etkinlikBitir(nil, 0)
            widgetDurumu(kayitta: false)
            arkaPlaniKapat()
            return
        }
        if UserDefaults.standard.bool(forKey: "dokunsal") { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        let kunye = sidecar(kimlik, baslangic, gecen, devam: oncekiParca)
        if surekli { keptParts += 1 }
        sonKimlik = kimlik
        KivilcimBus.publishLive(id: kimlik, active: false)
        Tani.yaz("kayıt bitti \(kimlik) · \(Int(gecen)) sn")
        Task.detached(priority: .utility) { Tani.mirror() }
        let depo = TelefonDeposu.shared
        depo.yeniKayit(kunye)
        sonBitis = Bitis(an: Date(), baslik: depo.oge(kimlik)?.baslik ?? "Sesli fikir", sure: gecen, id: kimlik, kind: aktifTur)
        if aktifTur == "spark", UIApplication.shared.applicationState == .active { hizliDuzen = kimlik }
        await etkinlikBitir(depo.oge(kimlik)?.baslik, gecen)
        widgetDurumu(kayitta: false)
        await depo.gonder()                                  // vault'a hemen (olmazsa sonra yeniden dener)
        if UserDefaults.standard.bool(forKey: "onDokum") {
            if let metin = await KayitMerkezi.tani(u, dil: kunye.dil) {
                depo.onMetin(kimlik, metin)
                await depo.gonder()
            }
        }
        await Task.detached(priority: .utility) { Tani.kirp() }.value   // the log is trimmed here, never on the way to a recording
        arkaPlaniKapat()
    }

    func vazgec() async {
        guard kayitta else { return }
        kaydedici?.stop(); kaydedici = nil
        zamanlayici?.invalidate(); zamanlayici = nil; kayitta = false; duraklatildi = false; duraklamaAni = nil
        Tani.yaz("kayıttan vazgeçildi")
        KivilcimBus.publishLive(id: sonBitis?.id, active: false)
        try? FileManager.default.removeItem(at: KayitMerkezi.kayitKlasoru.appendingPathComponent(kimlik + ".m4a"))
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        await etkinlikBitir(nil, 0)
        widgetDurumu(kayitta: false)
    }

    private func arkaPlaniKapat() {
        if arkaPlan != .invalid { UIApplication.shared.endBackgroundTask(arkaPlan); arkaPlan = .invalid }
    }

    /// The cap is reached: the next part starts first, then the full part is closed and sent. The audio session stays
    /// open the whole time, so this works on the lock screen too (a new session could not start in the background).
    /// Continuous mode adds two more reasons than the cap: a part with speech closes after a minute of silence
    /// (sent like any part, not linked as a continuation: the talk ended), and a part with no speech is deleted.
    private func parcaDegistir(_ neden: PartEnd = .cap) async {
        defer { parcaGeciyor = false }
        guard kayitta, let eski = kaydedici else { return }
        let yeniAn = Date()
        let yeniKimlik = Kimlik.yeni("iphone", yeniAn)
        let u = KayitMerkezi.kayitKlasoru.appendingPathComponent(yeniKimlik + ".m4a")
        let ayar: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: kalite.hz, AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: kalite.bit, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        guard let yeni = try? AVAudioRecorder(url: u, settings: ayar) else {
            Tani.yaz("HATA: yeni parça açılamadı → kayıt bitiyor"); await bitir(); return
        }
        yeni.delegate = self
        yeni.isMeteringEnabled = true
        guard yeni.record(forDuration: tavan + 30) else {   // same slack as the first part
            Tani.yaz("HATA: yeni parça başlamadı → kayıt bitiyor"); await bitir(); return
        }
        // the old part: stop it without its delegate (the delegate would end the whole recording)
        eski.delegate = nil
        let gecen = eski.currentTime > 0 ? eski.currentTime : Date().timeIntervalSince(baslangic)
        eski.stop()
        let eskiKimlik = kimlik, eskiBaslangic = baslangic
        let bos = surekli && (neden == .empty || speechInPart < Continuous.minSpeech)
        let konusma = Int(speechInPart)
        kaydedici = yeni; kimlik = yeniKimlik; baslangic = yeniAn; oncekiToplam += gecen
        resetSpeech()
        KivilcimBus.publishLive(id: yeniKimlik, active: true)
        if bos {
            // nothing was said: the file goes, the chain stays as it was, no alert
            try? FileManager.default.removeItem(at: KayitMerkezi.kayitKlasoru.appendingPathComponent(eskiKimlik + ".m4a"))
            Tani.yaz("sürekli: \(Int(gecen)) sn sessiz parça atıldı → yeniden \(yeniKimlik)")
            return
        }
        let kunye = sidecar(eskiKimlik, eskiBaslangic, gecen, devam: oncekiParca)
        Tani.yaz("parça \(parca) bitti \(eskiKimlik) · \(Int(gecen)) sn · ses \(konusma) sn · \(neden) → parça \(parca + 1) \(yeniKimlik)")
        // a part closed by silence is the end of a talk: the next one starts a new chain
        oncekiParca = neden == .silence ? nil : eskiKimlik
        parca += 1
        if surekli {
            // classify, keep, send and draft run on their own: this function must return at once, or the
            // next part change (and the cap) would wait behind them
            let eskiU = KayitMerkezi.kayitKlasoru.appendingPathComponent(eskiKimlik + ".m4a")
            Task {
                guard await keepIfSpeech(eskiU, gecen) else { return }
                TelefonDeposu.shared.yeniKayit(kunye)
                keptParts += 1
                await etkinlikTazele()
                await TelefonDeposu.shared.gonder()
                if UserDefaults.standard.bool(forKey: "onDokum"),
                   let metin = await KayitMerkezi.tani(KayitMerkezi.kayitKlasoru.appendingPathComponent(eskiKimlik + ".m4a"), dil: kunye.dil) {
                    TelefonDeposu.shared.onMetin(eskiKimlik, metin)
                    await TelefonDeposu.shared.gonder()
                }
            }
            return
        }
        TelefonDeposu.shared.yeniKayit(kunye)
        if UserDefaults.standard.bool(forKey: "dokunsal") { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
        await etkinlikTazele(uyari: AlertConfiguration(title: "Kıvılcım sürüyor",
                                                       body: "\(Int(tavan / 60)) dk doldu, \(parca). parça başladı",
                                                       sound: .named("sessiz.caf")))
        await TelefonDeposu.shared.gonder()
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            guard KayitMerkezi.shared.kayitta, recorder === KayitMerkezi.shared.kaydedici else { return }
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
                                            content: .init(state: d, staleDate: nil))
        } catch { Tani.yaz("HATA: Canlı Etkinlik başlamadı: \(error.localizedDescription)") }
    }

    /// Sends the clock start and the pause moment to the Live Activity. Called only when the state changes (start,
    /// pause, resume, a new part); the system timer in the card counts on its own between updates. No stale date:
    /// the card has nothing that goes out of date while it waits.
    private func etkinlikTazele(uyari: AlertConfiguration? = nil) async {
        guard let e = etkinlik, kayitta else { return }
        let d = KayitEtkinligi.ContentState(baslangic: sayacBaslangic, duraklama: duraklamaAni)
        await e.update(.init(state: d, staleDate: nil), alertConfiguration: uyari)
    }

    /// The recording is over (saved or discarded): the popup goes away at once. No "saved" card, no priority buttons
    /// (2026-11-10, asked for: stop → it disappears). Priority can still be set in the app or in the open-items widget.
    private func etkinlikBitir(_ baslik: String?, _ sure: Double) async {
        guard let e = etkinlik else { return }
        etkinlik = nil
        await e.end(nil, dismissalPolicy: .immediate)
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

/// Level bars and elapsed time of the running recording. A separate object from KayitMerkezi: these two values
/// change about 14 times a second, and whoever observes KayitMerkezi (the App body, every screen) must not be
/// re-evaluated at that rate.
@MainActor
final class RecordingMeter: ObservableObject {
    @Published fileprivate(set) var seviyeler: [Float] = []
    @Published fileprivate(set) var sure: TimeInterval = 0
}

/// Elapsed time of the recording (or a fixed duration, for the "saved" state).
struct RecordingClock: View {
    @ObservedObject var meter: RecordingMeter
    var fixed: Double? = nil
    var body: some View { Text(Zaman.sure(fixed ?? meter.sure)) }
}

struct MeterBars: View {
    @ObservedObject var meter: RecordingMeter
    var adet: Int
    var body: some View { DuzeyCubuklari(seviyeler: meter.seviyeler, adet: adet) }
}

struct MeterWave: View {
    @ObservedObject var meter: RecordingMeter
    let duraklatildi: Bool
    var adet: Int
    var body: some View { Dalga(seviyeler: meter.seviyeler.map(Double.init), duraklatildi: duraklatildi, adet: adet) }
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

/// Counts the classifier windows that hear speech (synchronous file analysis; read after analyze() returns).
final class SpeechCounter: NSObject, SNResultsObserving, @unchecked Sendable {
    let threshold: Double
    private(set) var windows = 0
    private(set) var failed = false
    init(threshold: Double) { self.threshold = threshold }
    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let c = result as? SNClassificationResult,
              (c.classification(forIdentifier: "speech")?.confidence ?? 0) >= threshold else { return }
        windows += 1
    }
    func request(_ request: SNRequest, didFailWithError error: Error) { failed = true }
}
