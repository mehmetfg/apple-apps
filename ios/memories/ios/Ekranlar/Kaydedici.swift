// Kendi sesinle okuma. Metin ekranda durur, sen okursun; kayıt bitince cihazın içinde yazıya çevrilir
// (SFSpeechRecognizer, sunucuya gitmez — destek yoksa tanıma atlanır, kayıt yine saklanır).
// Tanınmayan kelime SARI kalır: hata değil, "kontrol et" demektir. Aksan payı vardır; puan verilmez.
// Dosya: AAC 16 kHz mono 24 kbit/sn ≈ 180 KB/dk, en çok 4 dk. Ad: 021-iphone-a1b2c3d4.m4a
// (Mac'teki ③ çözümle aynı klasörü okur; cihaz adı dosya adının ikinci parçasıdır.)
import Foundation
import AVFoundation
import Speech

@MainActor
final class Kaydedici: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    enum Hal: Equatable { case bos, kayit, cozuluyor, bitti, izinYok, hata(String) }

    @Published var hal: Hal = .bos
    @Published var sure: TimeInterval = 0
    @Published var seviyeler: [Float] = []
    @Published var sonuc: KayitBilgisi?
    @Published var eslesen: Set<Int> = []     // metin kelimelerinden tanınanların sırası
    @Published var calan: String?

    static let tavan: TimeInterval = 240
    private var kaydedici: AVAudioRecorder?
    private var calici: AVAudioPlayer?
    private var zamanlayici: Timer?
    private var dosya: URL?
    private var baslangic = Date()

    static let ayarlar: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 16_000,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 24_000,
        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
    ]

    static func yerVar(_ klasor: URL) -> Bool {
        let d = (try? klasor.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? Int64.max
        return d > 50_000_000
    }

    func baslat(gun: Int, klasor: URL) async {
        guard await AVAudioApplication.requestRecordPermission() else { hal = .izinYok; return }
        try? FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
        guard Kaydedici.yerVar(klasor) else { hal = .hata("Cihazda yer az (50 MB'tan az). Biraz yer açınca kayıt açılır."); return }
        do {
            let o = AVAudioSession.sharedInstance()
            try o.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try o.setActive(true)
        } catch { hal = .hata("Mikrofon açılamadı: \(error.localizedDescription)"); return }
        let ad = String(format: "%03d", gun) + "-\(Cihaz.ad)-\(UUID().uuidString.prefix(8).lowercased()).m4a"
        let u = klasor.appendingPathComponent(ad)
        do {
            let k = try AVAudioRecorder(url: u, settings: Kaydedici.ayarlar)
            k.delegate = self
            k.isMeteringEnabled = true
            guard k.record(forDuration: Kaydedici.tavan) else { hal = .hata("Kayıt başlamadı."); return }
            kaydedici = k; dosya = u; sure = 0; seviyeler = []; sonuc = nil; eslesen = []; baslangic = Date(); hal = .kayit
            zamanlayici = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tik() }
            }
        } catch { hal = .hata(error.localizedDescription) }
    }

    private func tik() {
        guard let k = kaydedici, k.isRecording else { return }
        k.updateMeters()
        sure = k.currentTime
        let db = k.averagePower(forChannel: 0)
        seviyeler.append(max(0.04, min(1, (db + 50) / 50)))
        if seviyeler.count > 60 { seviyeler.removeFirst(seviyeler.count - 60) }
    }

    /// Kaydı bitirir; metinle karşılaştırıp kayıt bilgisini döndürür (depoya eklemeyi çağıran yapar).
    func bitir(metin: String, gun: Int) async -> KayitBilgisi? {
        let gecen = kaydedici?.currentTime ?? sure
        kaydedici?.stop()
        zamanlayici?.invalidate(); zamanlayici = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard let u = dosya else { hal = .bos; return nil }
        if gecen < 2 {        // yanlışlıkla dokunuş: kayıt sayılmaz
            try? FileManager.default.removeItem(at: u)
            hal = .bos; dosya = nil
            return nil
        }
        hal = .cozuluyor
        var k = KayitBilgisi(ad: u.lastPathComponent, gun: gun, cihaz: Cihaz.ad, zaman: baslangic, sure: gecen)
        if let duyulan = await Kaydedici.tani(u) {
            let r = Metin.takilanlar(metin: metin, duyulan: duyulan)
            k.tanima = (r.oran * 100).rounded() / 100
            k.takilan = Array(r.takilan.prefix(20))
            eslesen = r.eslesen
        }
        sonuc = k
        hal = .bitti
        return k
    }

    func vazgec() {
        kaydedici?.stop()
        zamanlayici?.invalidate(); zamanlayici = nil
        if let d = dosya { try? FileManager.default.removeItem(at: d) }
        dosya = nil; hal = .bos; sure = 0; sonuc = nil; eslesen = []
    }

    func sifirla() { dosya = nil; hal = .bos; sure = 0; seviyeler = []; sonuc = nil; eslesen = [] }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        // Arama gelirse ya da tavan dolarsa: o ana kadar kaydedilen saklanır, "bitir" kullanıcıyla gelir.
        Task { @MainActor in
            self.zamanlayici?.invalidate(); self.zamanlayici = nil
        }
    }

    // MARK: Cihaz içi tanıma

    static func tani(_ u: URL) async -> String? {
        let durum: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard durum == .authorized else { return nil }
        let tanici = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-GB"))
        guard let tanici, tanici.isAvailable else { return nil }
        let istek = SFSpeechURLRecognitionRequest(url: u)
        // Uzun kayıtta tanıyıcı sonucu parça parça verir (her duraklamada yeni parça). Eskiden yalnız son
        // parça alınıyordu: Gün 22'de 2:12'lik okumanın %12'si "tanındı", takılan listesi metnin başı çıktı.
        istek.shouldReportPartialResults = true
        if tanici.supportsOnDeviceRecognition { istek.requiresOnDeviceRecognition = true }
        istek.taskHint = .dictation
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

    // MARK: Çalma

    func cal(_ u: URL, kimlik: String) {
        if calan == kimlik { calici?.stop(); calan = nil; return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        calici = try? AVAudioPlayer(contentsOf: u)
        calici?.delegate = self
        calici?.play()
        calan = calici == nil ? nil : kimlik
    }

    func durdur() { calici?.stop(); calan = nil }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.calan = nil }
    }
}

/// Tanıma parçalarını biriktirir. Parça sonu bildirilince metin kalıcı olur; tanıyıcı birikimli metin verirse
/// yeni parça öncekilerin devamı sayılır, çift yazılmaz. (Mac'teki Cümle ile aynı kural.)
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
