// Ses: kayıt (AAC 16 kHz), telefonda İngilizce döküm (cihaz içi), konuşma ve sabah yürüyüşü.
//
// Yürüyüş: kulaklıkta önce kendi sesin ("your version"), sonra düzeltilmiş hâli ("better"), ardından kendi hatalarından
// sorular. Cevap kulaklığın tuşuyla: OYNAT/DURAKLAT = doğru · İLERİ = yanlış · GERİ = tekrar. FiiO BTR15 gibi her
// Bluetooth alıcı bu komutları gönderir; hangi tuşun ne gönderdiği Ayarlar › Kulaklık sınaması'nda görülür.
import AVFoundation
import MediaPlayer
import Speech
import SwiftUI

@MainActor
final class Kayitci: NSObject, ObservableObject {
    @Published var kayitta = false
    @Published var gecen: Double = 0
    @Published var seviye: Double = 0
    @Published var hata: String?
    private var k: AVAudioRecorder?
    private var z: Timer?
    private var sinir: Double = 90
    private var bitince: ((Double) -> Void)?

    func baslat(id: String, sinir: Double = 90, bitince: @escaping (Double) -> Void) async {
        hata = nil
        guard await AVAudioApplication.requestRecordPermission() else { hata = "Mikrofon izni yok: Ayarlar › Ayna › Mikrofon."; return }
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try s.setActive(true)
            let r = try AVAudioRecorder(url: Depo.sesKlasoru.appendingPathComponent(id + ".m4a"),
                                        settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 32000])
            r.isMeteringEnabled = true
            r.record(forDuration: sinir + 5)
            k = r
        } catch { hata = error.localizedDescription; return }
        self.sinir = sinir; self.bitince = bitince
        gecen = 0; kayitta = true
        z = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in Task { @MainActor in self?.tik() } }
    }

    private func tik() {
        guard let k, kayitta else { return }
        gecen = k.currentTime; k.updateMeters()
        seviye = Double(max(0, min(1, (k.averagePower(forChannel: 0) + 50) / 50)))
        if gecen >= sinir { bitir() }
    }

    func bitir() {
        guard kayitta, let k else { return }
        let sure = k.currentTime
        k.stop(); z?.invalidate(); kayitta = false; seviye = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if sure >= 3 { bitince?(sure) } else { hata = "3 saniyeden kısa — sayılmadı." }
        bitince = nil
    }

    /// Cihaz içi İngilizce döküm (iPhone 13'te destekli). Ağa gitmez; desteklenmiyorsa nil — Mac'in Whisper dökümü beklenir.
    static func dok(_ url: URL) async -> String? {
        let izin = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        guard izin == .authorized, let t = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), t.supportsOnDeviceRecognition else { return nil }
        let r = SFSpeechURLRecognitionRequest(url: url)
        r.requiresOnDeviceRecognition = true
        r.addsPunctuation = true
        return await withCheckedContinuation { c in
            var bitti = false
            t.recognitionTask(with: r) { s, h in
                guard !bitti else { return }
                if let s, s.isFinal { bitti = true; c.resume(returning: s.bestTranscription.formattedString) }
                else if h != nil { bitti = true; c.resume(returning: nil) }
            }
        }
    }
}

// MARK: konuşma

@MainActor
final class Konusmaci: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = Konusmaci()
    private let s = AVSpeechSynthesizer()
    private var bekleyen: CheckedContinuation<Void, Never>?
    var aksan: String { UserDefaults.standard.string(forKey: "aksan") ?? "en-GB" }

    override init() { super.init(); s.delegate = self }

    func soyle(_ metin: String, hiz: Float = 0.46, dil: String? = nil) async {
        s.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: metin)
        let d = dil ?? aksan
        u.voice = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == d }.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: d)
        u.rate = hiz
        await withCheckedContinuation { c in bekleyen?.resume(); bekleyen = c; s.speak(u) }
    }

    func dur() { s.stopSpeaking(at: .immediate); bekleyen?.resume(); bekleyen = nil }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.bekleyen?.resume(); self.bekleyen = nil }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.bekleyen?.resume(); self.bekleyen = nil }
    }
}

// MARK: sabah yürüyüşü

@MainActor
final class Yuruyus: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = Yuruyus()
    enum Cevap { case evet, hayir, tekrar }

    @Published var calisiyor = false
    @Published var simdi = ""                 // ekranda ne oluyor
    @Published var soru: Soru?
    @Published var dogruSayi = 0
    @Published var soruSayi = 0
    @Published var sonKomut = "—"            // kulaklık sınaması: en son gelen komut

    private var oynatici: AVAudioPlayer?
    private var sessiz: AVAudioPlayer?
    private var calmaBitti: CheckedContinuation<Void, Never>?
    private var cevapBekleyen: CheckedContinuation<Cevap, Never>?
    private var gorev: Task<Void, Never>?

    override init() {
        super.init()
        let m = MPRemoteCommandCenter.shared()
        m.playCommand.addTarget { [weak self] _ in self?.komut("Oynat", .evet); return .success }
        m.pauseCommand.addTarget { [weak self] _ in self?.komut("Duraklat", .evet); return .success }
        m.togglePlayPauseCommand.addTarget { [weak self] _ in self?.komut("Oynat/Duraklat", .evet); return .success }
        m.nextTrackCommand.addTarget { [weak self] _ in self?.komut("İleri", .hayir); return .success }
        m.previousTrackCommand.addTarget { [weak self] _ in self?.komut("Geri", .tekrar); return .success }
    }

    nonisolated private func komut(_ ad: String, _ c: Cevap) {
        Task { @MainActor in
            self.sonKomut = "\(ad) · \(Date().formatted(date: .omitted, time: .standard))"
            self.cevapla(c)
        }
    }

    func cevapla(_ c: Cevap) { cevapBekleyen?.resume(returning: c); cevapBekleyen = nil }

    /// Kulaklık sınaması için: oturumu açar, sessiz ses çalar ki uygulama "şu an çalan" olsun ve tuşlar buraya gelsin.
    func dinlemeyiAc() {
        oturum()
        sessiziCal()
        bilgi("Ayna · kulaklık sınaması")
    }

    private func oturum() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func bilgi(_ baslik: String) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [MPMediaItemPropertyTitle: baslik, MPMediaItemPropertyArtist: "Ayna",
                                                            MPNowPlayingInfoPropertyPlaybackRate: 1.0]
    }

    private func sessiziCal() {
        guard sessiz == nil || !(sessiz?.isPlaying ?? false) else { return }
        sessiz = try? AVAudioPlayer(data: Yuruyus.sessizWav())
        sessiz?.numberOfLoops = -1
        sessiz?.volume = 0.01
        sessiz?.play()
    }

    func baslat(_ kayitlar: [Kayit], merkez: Merkez) {
        guard !calisiyor else { return }
        calisiyor = true; dogruSayi = 0; soruSayi = 0
        oturum(); sessiziCal(); bilgi("Ayna · sabah yürüyüşü")
        gorev = Task { [weak self] in
            guard let self else { return }
            let k = Konusmaci.shared
            await k.soyle("Good morning. \(kayitlar.count) of your stories. Play means yes, next means no.")
            for x in kayitlar {
                if Task.isCancelled { break }
                simdi = x.istem
                bilgi("Ayna · \(x.istem)")
                let kendi = Depo.sesKlasoru.appendingPathComponent(x.id + ".m4a")
                if FileManager.default.fileExists(atPath: kendi.path) {
                    await k.soyle("Your version.")
                    await cal(kendi)
                }
                await k.soyle("Better.")
                let duz = Depo.sesKlasoru.appendingPathComponent(x.id + "-duz.m4a")
                if x.sesVar, FileManager.default.fileExists(atPath: duz.path) { await cal(duz) } else { await k.soyle(x.duzeltme ?? "", hiz: 0.44) }
                for h in x.hatalar.prefix(3) {
                    await k.soyle("You said: \(h.yanlis). Better: \(h.dogru).", hiz: 0.44)
                }
                for q in x.sorular {
                    if Task.isCancelled { break }
                    soru = q; soruSayi += 1
                    var c: Cevap = .tekrar
                    repeat {
                        await k.soyle(q.cumle + ". Correct?", hiz: 0.44)
                        c = await cevapBekle()
                    } while c == .tekrar && !Task.isCancelled
                    let dogru = (c == .evet) == q.dogru
                    if dogru { dogruSayi += 1; Haptik.basari() } else { Haptik.uyari() }
                    await k.soyle(dogru ? "Right." : "Not quite.", hiz: 0.5)
                    if !q.aciklama.isEmpty { await k.soyle(q.aciklama, hiz: 0.46) }
                }
                soru = nil
                merkez.dinlendi(x.id)
            }
            if !Task.isCancelled { await k.soyle("Done. \(dogruSayi) of \(soruSayi). Tonight, tell one more moment.") }
            bitir()
        }
    }

    func bitir() {
        gorev?.cancel(); gorev = nil
        Konusmaci.shared.dur()
        oynatici?.stop(); calmaBitti?.resume(); calmaBitti = nil
        cevapBekleyen?.resume(returning: .hayir); cevapBekleyen = nil
        sessiz?.stop(); sessiz = nil
        calisiyor = false; soru = nil; simdi = ""
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func cevapBekle() async -> Cevap {
        await withCheckedContinuation { c in cevapBekleyen = c }
    }

    private func cal(_ u: URL) async {
        oynatici = try? AVAudioPlayer(contentsOf: u)
        oynatici?.delegate = self
        guard oynatici?.play() == true else { return }
        await withCheckedContinuation { c in calmaBitti = c }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.calmaBitti?.resume(); self.calmaBitti = nil }
    }

    /// 1 saniyelik sessiz WAV — bekleme sırasında uygulamayı "şu an çalan" tutar, kulaklık tuşları buraya gelir.
    static func sessizWav() -> Data {
        let sr: UInt32 = 8000, n = sr
        var d = Data()
        func ek<T>(_ v: T) { var x = v; d.append(Data(bytes: &x, count: MemoryLayout<T>.size)) }
        d.append("RIFF".data(using: .ascii)!); ek(UInt32(36 + n * 2)); d.append("WAVEfmt ".data(using: .ascii)!)
        ek(UInt32(16)); ek(UInt16(1)); ek(UInt16(1)); ek(sr); ek(sr * 2); ek(UInt16(2)); ek(UInt16(16))
        d.append("data".data(using: .ascii)!); ek(UInt32(n * 2)); d.append(Data(count: Int(n * 2)))
        return d
    }
}
