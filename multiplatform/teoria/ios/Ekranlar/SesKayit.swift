// Sesli not: bir konuyu kendi sesinle anlat — hatırlamak ve yorumlamak için.
// Az yer kaplar: AAC, 16 kHz, mono, 24 kbit/sn ≈ 180 KB/dakika. Bir not en çok 3 dakika.
// Dosya önce cihaza yazılır, sonra vault'a (ses/) kopyalanır; Mac'te döküm + değerlendirme hattına girer.
import Foundation
import AVFoundation

@MainActor
final class SesKayit: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    enum Hal: Equatable { case bos, kayit, bitti, izinYok, hata(String) }

    @Published var hal: Hal = .bos
    @Published var sure: TimeInterval = 0
    @Published var seviye: Float = 0          // dalga çizimi için 0…1
    @Published var seviyeler: [Float] = []
    @Published var calan: String?

    static let tavan: TimeInterval = 180
    private var kaydedici: AVAudioRecorder?
    private var calici: AVAudioPlayer?
    private var zamanlayici: Timer?
    private(set) var dosya: URL?

    static let ayarlar: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 16_000,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 24_000,
        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
    ]

    func izinIste() async -> Bool {
        #if os(iOS)
        return await AVAudioApplication.requestRecordPermission()
        #else
        return await AVCaptureDevice.requestAccess(for: .audio)
        #endif
    }

    /// Boş yer 50 MB'ın altındaysa kayıt açılmaz (yarım dosya kalmasın).
    static func yerVar(_ klasor: URL) -> Bool {
        let d = (try? klasor.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? Int64.max
        return d > 50_000_000
    }

    func baslat(klasor: URL) async {
        guard await izinIste() else { hal = .izinYok; return }
        try? FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
        guard SesKayit.yerVar(klasor) else { hal = .hata("Cihazda yer az. Biraz yer açınca kayıt açılır; yazılı not her zaman çalışır."); return }
        #if os(iOS)
        do {
            let o = AVAudioSession.sharedInstance()
            try o.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
            try o.setActive(true)
        } catch { hal = .hata("Mikrofon açılamadı: \(error.localizedDescription)"); return }
        #endif
        let ad = "\(Tarih.gun(Date()))-\(UUID().uuidString.prefix(8).lowercased()).m4a"
        let u = klasor.appendingPathComponent(ad)
        do {
            let k = try AVAudioRecorder(url: u, settings: SesKayit.ayarlar)
            k.delegate = self
            k.isMeteringEnabled = true
            guard k.record(forDuration: SesKayit.tavan) else { hal = .hata("Kayıt başlamadı."); return }
            kaydedici = k; dosya = u; sure = 0; seviyeler = []; hal = .kayit
            zamanlayici = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tik() }
            }
        } catch { hal = .hata(error.localizedDescription) }
    }

    private func tik() {
        guard let k = kaydedici, k.isRecording else { return }
        k.updateMeters()
        sure = k.currentTime
        let db = k.averagePower(forChannel: 0)
        seviye = max(0, min(1, (db + 50) / 50))
        seviyeler.append(seviye)
        if seviyeler.count > 120 { seviyeler.removeFirst(seviyeler.count - 120) }
    }

    func durdur() {
        kaydedici?.stop()
        zamanlayici?.invalidate(); zamanlayici = nil
        if hal == .kayit { hal = .bitti }
    }

    func vazgec() {
        durdur()
        if let d = dosya { try? FileManager.default.removeItem(at: d) }
        dosya = nil; hal = .bos; sure = 0
    }

    func sifirla() { dosya = nil; hal = .bos; sure = 0; seviyeler = [] }

    // Arama gelirse ya da sistem keserse: o ana kadar kaydedilen saklanır.
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            self.zamanlayici?.invalidate(); self.zamanlayici = nil
            if self.hal == .kayit { self.hal = .bitti }
        }
    }

    // MARK: Çalma

    func cal(_ u: URL, kimlik: String) {
        if calan == kimlik { calici?.stop(); calan = nil; return }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        calici = try? AVAudioPlayer(contentsOf: u)
        calici?.delegate = self
        calici?.play()
        calan = calici == nil ? nil : kimlik
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.calan = nil }
    }

    static func boyut(_ u: URL) -> String {
        let b = (try? FileManager.default.attributesOfItem(atPath: u.path)[.size] as? Int) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .file)
    }

    static func sureYazi(_ s: TimeInterval) -> String {
        String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)
    }
}
