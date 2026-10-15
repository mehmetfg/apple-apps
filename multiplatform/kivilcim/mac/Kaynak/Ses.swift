// Mac'te kayıt ve çalma. Kayıt önce ~/Library/Application Support/Kivilcim/kayit/'a yazılır (iCloud yarım
// dosya eşitlemesin), bitince Depo onu vault'a taşır. Biçim: AAC mono, kalite Ayarlar'dan (Kalite).
import Foundation
import AVFoundation
import AppKit

@MainActor
final class Kaydedici: NSObject, ObservableObject, AVAudioRecorderDelegate {
    static let shared = Kaydedici()

    @Published private(set) var kayitta = false
    @Published private(set) var sure: TimeInterval = 0
    @Published private(set) var seviyeler: [Float] = []
    @Published var hata: String?
    @Published private(set) var sonKaydedilen: String?

    static let tavan: TimeInterval = 30 * 60
    private var kaydedici: AVAudioRecorder?
    private var zamanlayici: Timer?
    private var dosya: URL?
    private var baslangic = Date()
    private var kalite = Kalite.dengeli

    var kaliteSecimi: Kalite { Kalite(rawValue: UserDefaults.standard.string(forKey: "kalite") ?? "") ?? .dengeli }
    var dilSecimi: String { UserDefaults.standard.string(forKey: "dil") ?? "tr" }

    func degistir() { kayitta ? bitir() : baslat() }

    func baslat() {
        guard !kayitta else { return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { tamam in
                Task { @MainActor in if tamam { Kaydedici.shared.baslat() } else { Kaydedici.shared.izinYok() } }
            }
            return
        default: izinYok(); return
        }
        let klasor = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Kivilcim/kayit")
        try? FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
        kalite = kaliteSecimi
        let u = klasor.appendingPathComponent(UUID().uuidString + ".m4a")
        let ayar: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: kalite.hz, AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: kalite.bit, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            let k = try AVAudioRecorder(url: u, settings: ayar)
            k.delegate = self
            k.isMeteringEnabled = true
            guard k.record(forDuration: Kaydedici.tavan) else { hata = "Kayıt başlamadı (mikrofon meşgul olabilir)."; return }
            kaydedici = k; dosya = u; baslangic = Date(); sure = 0; seviyeler = []; kayitta = true; hata = nil
            NSSound(named: "Tink")?.play()
            zamanlayici = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { _ in
                Task { @MainActor in Kaydedici.shared.tik() }
            }
            RunLoop.main.add(zamanlayici!, forMode: .common)
        } catch { hata = error.localizedDescription }
    }

    private func izinYok() {
        hata = "Mikrofon izni yok. Sistem Ayarları › Gizlilik ve Güvenlik › Mikrofon › Kıvılcım'ı aç."
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") { NSWorkspace.shared.open(u) }
    }

    private func tik() {
        guard let k = kaydedici, k.isRecording else { return }
        k.updateMeters()
        sure = k.currentTime
        let db = k.averagePower(forChannel: 0)
        seviyeler.append(max(0.05, min(1, (db + 52) / 52)))
        if seviyeler.count > 80 { seviyeler.removeFirst(seviyeler.count - 80) }
    }

    func bitir() {
        guard kayitta, let k = kaydedici, let u = dosya else { return }
        let gecen = k.currentTime > 0 ? k.currentTime : Date().timeIntervalSince(baslangic)
        k.stop()
        temizle()
        if gecen < 1.0 {          // yanlışlıkla dokunuş
            try? FileManager.default.removeItem(at: u); return
        }
        NSSound(named: "Pop")?.play()
        let kimlik = Kimlik.yeni("mac", baslangic)
        let kunye = Kunye(id: kimlik, cihaz: "mac", zaman: Zaman.iso(baslangic), sure: (gecen * 10).rounded() / 10,
                          kalite: kalite.rawValue, dil: dilSecimi, onMetin: nil)
        sonKaydedilen = kimlik
        Depo.shared.kayitEkle(gecici: u, kunye: kunye)
    }

    func vazgec() {
        guard kayitta else { return }
        kaydedici?.stop()
        if let d = dosya { try? FileManager.default.removeItem(at: d) }
        temizle()
        NSSound(named: "Funk")?.play()
    }

    private func temizle() {
        zamanlayici?.invalidate(); zamanlayici = nil
        kaydedici = nil; dosya = nil; kayitta = false
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        // tavan dolarsa kendiliğinden biter: elde olan kaydedilir
        Task { @MainActor in if Kaydedici.shared.kayitta { Kaydedici.shared.bitir() } }
    }
}

@MainActor
final class Oynatici: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = Oynatici()
    @Published private(set) var calan: String?
    @Published private(set) var konum: Double = 0
    @Published private(set) var uzunluk: Double = 0
    @Published var hiz: Float = 1 { didSet { calici?.rate = hiz } }
    private var calici: AVAudioPlayer?
    private var zamanlayici: Timer?

    func degistir(_ o: Oge) {
        if calan == o.id, let c = calici {
            if c.isPlaying { c.pause() } else { c.play() }
            objectWillChange.send(); return
        }
        guard let u = Depo.shared.sesURL(o) else { return }
        try? FileManager.default.startDownloadingUbiquitousItem(at: u)
        guard let c = try? AVAudioPlayer(contentsOf: u) else { return }
        calici?.stop()
        c.delegate = self; c.enableRate = true; c.rate = hiz
        c.play()
        calici = c; calan = o.id; uzunluk = c.duration; konum = 0
        zamanlayici?.invalidate()
        zamanlayici = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            Task { @MainActor in Oynatici.shared.konum = Oynatici.shared.calici?.currentTime ?? 0 }
        }
    }

    var caliyor: Bool { calici?.isPlaying ?? false }
    func atla(_ t: Double) { calici?.currentTime = max(0, min(uzunluk, t)); konum = calici?.currentTime ?? 0 }
    func durdur() { calici?.stop(); calan = nil; zamanlayici?.invalidate() }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in Oynatici.shared.calan = nil; Oynatici.shared.zamanlayici?.invalidate() }
    }
}
