// Mac'te kayıt ve çalma. Kayıt önce ~/Library/Application Support/Kivilcim/kayit/'a yazılır (iCloud yarım
// dosya eşitlemesin), bitince Depo onu vault'a taşır. Biçim: AAC mono, kalite Ayarlar'dan (Kalite).
import Foundation
import AVFoundation
import AppKit

/// What is being recorded: a short idea, or a long talk that goes to the day's journal.
enum RecordMode: String, Sendable {
    case spark, journal
    /// One file never grows past this; the talk itself goes on in a new part (2026-11-04).
    var partCap: TimeInterval { self == .journal ? 60 * 60 : 30 * 60 }
    var name: String { self == .journal ? "Uzun konuşma" : "Fikir" }
}

@MainActor
final class Kaydedici: NSObject, ObservableObject, AVAudioRecorderDelegate {
    static let shared = Kaydedici()

    @Published private(set) var kayitta = false
    /// Whole talk, across parts.
    @Published private(set) var sure: TimeInterval = 0
    @Published private(set) var seviyeler: [Float] = []
    @Published var hata: String?
    @Published private(set) var sonKaydedilen: String?
    @Published private(set) var mode: RecordMode = .spark
    @Published private(set) var part = 1
    /// Topic for the next (or current) recording: Teoria book id or "k:<name>". Kept until changed.
    @Published var topic: String? = UserDefaults.standard.string(forKey: "topicNext") {
        didSet { UserDefaults.standard.set(topic, forKey: "topicNext") }
    }

    static let tavan: TimeInterval = 30 * 60
    private var kaydedici: AVAudioRecorder?
    private var zamanlayici: Timer?
    private var dosya: URL?
    private var baslangic = Date()        // this part
    private var talkStart = Date()        // the whole talk
    private var prevParts: TimeInterval = 0
    private var prevId: String?
    private var kalite = Kalite.dengeli

    var kaliteSecimi: Kalite { Kalite(rawValue: UserDefaults.standard.string(forKey: "kalite") ?? "") ?? .dengeli }
    var dilSecimi: String { UserDefaults.standard.string(forKey: "dil") ?? "tr" }

    func degistir() { kayitta ? bitir() : baslat() }
    func toggle(_ m: RecordMode) { kayitta ? bitir() : baslat(m) }

    func baslat(_ m: RecordMode = .spark) {
        guard !kayitta else { return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { tamam in
                Task { @MainActor in if tamam { Kaydedici.shared.baslat(m) } else { Kaydedici.shared.izinYok() } }
            }
            return
        default: izinYok(); return
        }
        mode = m; part = 1; prevParts = 0; prevId = nil; talkStart = Date()
        kalite = kaliteSecimi
        guard startPart() else { return }
        seviyeler = []; kayitta = true; hata = nil
        NSSound(named: "Tink")?.play()
        zamanlayici = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { _ in
            Task { @MainActor in Kaydedici.shared.tik() }
        }
        RunLoop.main.add(zamanlayici!, forMode: .common)
    }

    /// Opens a new file. Recorded into Application Support first, so iCloud never syncs a half-written file.
    @discardableResult
    private func startPart() -> Bool {
        let klasor = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Kivilcim/kayit")
        try? FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
        let u = klasor.appendingPathComponent(UUID().uuidString + ".m4a")
        let ayar: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: kalite.hz, AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: kalite.bit, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            let k = try AVAudioRecorder(url: u, settings: ayar)
            k.delegate = self
            k.isMeteringEnabled = true
            guard k.record(forDuration: mode.partCap) else { hata = "Kayıt başlamadı (mikrofon meşgul olabilir)."; return false }
            kaydedici = k; dosya = u; baslangic = Date()
            return true
        } catch { hata = error.localizedDescription; return false }
    }

    private func izinYok() {
        hata = "Mikrofon izni yok. Sistem Ayarları › Gizlilik ve Güvenlik › Mikrofon › Kıvılcım'ı aç."
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") { NSWorkspace.shared.open(u) }
    }

    private func tik() {
        guard let k = kaydedici, k.isRecording else { return }
        k.updateMeters()
        sure = prevParts + k.currentTime
        let db = k.averagePower(forChannel: 0)
        seviyeler.append(max(0.05, min(1, (db + 52) / 52)))
        if seviyeler.count > 80 { seviyeler.removeFirst(seviyeler.count - 80) }
        // a few seconds before the cap: roll over ourselves, so not even the recorder's own stop is waited for
        if k.currentTime >= mode.partCap - 2 { rollOver() }
    }

    /// The cap is near: close this part, hand it to the store, go on in a new file at once.
    private func rollOver() {
        guard kayitta, let k = kaydedici, let u = dosya else { return }
        let gecen = k.currentTime
        let start = baslangic
        k.delegate = nil
        k.stop()
        let id = save(u, start: start, seconds: gecen)
        prevParts += gecen; prevId = id; part += 1
        if !startPart() {          // could not open the next file: what we have is saved; stop cleanly
            temizle(); return
        }
        NSSound(named: "Purr")?.play()
        Depo.shared.gunluk("uzun konuşma sürüyor: \(part). parça başladı (önceki \(id))")
    }

    private func save(_ u: URL, start: Date, seconds: TimeInterval) -> String {
        let kimlik = Kimlik.yeni("mac", start)
        var kunye = Kunye(id: kimlik, cihaz: "mac", zaman: Zaman.iso(start), sure: (seconds * 10).rounded() / 10,
                          kalite: kalite.rawValue, dil: dilSecimi, onMetin: nil)
        kunye.kind = mode == .journal ? "journal" : nil
        kunye.devam = prevId
        kunye.topic = topic
        sonKaydedilen = kimlik
        Depo.shared.kayitEkle(gecici: u, kunye: kunye)
        return kimlik
    }

    func bitir() {
        guard kayitta, let k = kaydedici, let u = dosya else { return }
        let gecen = k.currentTime > 0 ? k.currentTime : Date().timeIntervalSince(baslangic)
        k.delegate = nil
        k.stop()
        let first = prevId == nil
        temizle()
        if gecen < 1.0 && first {          // accidental tap
            try? FileManager.default.removeItem(at: u); return
        }
        if gecen < 1.0 { try? FileManager.default.removeItem(at: u); return }   // empty tail of a long talk
        NSSound(named: "Pop")?.play()
        _ = save(u, start: baslangic, seconds: gecen)
    }

    func vazgec() {
        guard kayitta else { return }
        // a long talk that already saved parts keeps them; only the current part is thrown away
        kaydedici?.delegate = nil
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
        // the recorder stopped on its own (cap, device gone): never lose the talk, go on in a new part
        Task { @MainActor in if Kaydedici.shared.kayitta { Kaydedici.shared.rollOver() } }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            Depo.shared.gunluk("kayıt hatası: \(error?.localizedDescription ?? "?")")
            if Kaydedici.shared.kayitta { Kaydedici.shared.rollOver() }
        }
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
        guard let u = Depo.shared.sesURL(o) else { return }
        play(id: o.id, url: u)
    }

    /// Plays from `start` seconds (a journal segment). Same id while playing = pause / resume.
    func play(id: String, url u: URL, from start: Double? = nil) {
        if calan == id, let c = calici {
            if let st = start { c.currentTime = st; if !c.isPlaying { c.play() } }
            else if c.isPlaying { c.pause() } else { c.play() }
            konum = c.currentTime
            objectWillChange.send(); return
        }
        try? FileManager.default.startDownloadingUbiquitousItem(at: u)
        guard let c = try? AVAudioPlayer(contentsOf: u) else { return }
        calici?.stop()
        c.delegate = self; c.enableRate = true; c.rate = hiz
        if let st = start { c.currentTime = st }
        c.play()
        calici = c; calan = id; uzunluk = c.duration; konum = c.currentTime
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
