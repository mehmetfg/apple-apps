// Ses: cümle okuma (sistem sesi, en-GB önce), kelime sesi (Oxford'un gerçek kaydı, olmazsa sistem sesi),
// paketin ses dosyası (telefonda dinlenen Kokoro sesi) ve kendi sesinle okuma kaydı + cihaz içi tanıma.
// Tarayıcıdaki Tezgâh'ın Chrome kilitlenmesi derdi yok: AVSpeechSynthesizer sırayı kendisi tutar.
import Foundation
import AVFoundation
import Speech

@MainActor
final class Ses: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var calanCumle: Int?
    @Published var zincirde = false
    @Published var acik: Bool { didSet { UserDefaults.standard.set(acik, forKey: "ses.acik") } }
    @Published var hiz: Double { didSet { UserDefaults.standard.set(hiz, forKey: "ses.hiz") } }
    @Published var sesAdi: String { didSet { UserDefaults.standard.set(sesAdi, forKey: "ses.ad") } }

    private let s = AVSpeechSynthesizer()
    private var sira: [(Int?, String)] = []
    private var oxOyuncu: AVPlayer?
    private var oxOlu = false

    override init() {
        let d = UserDefaults.standard
        acik = d.object(forKey: "ses.acik") as? Bool ?? true
        hiz = d.object(forKey: "ses.hiz") as? Double ?? 0.9
        sesAdi = d.string(forKey: "ses.ad") ?? ""
        super.init()
        s.delegate = self
    }

    /// İngilizce sesler: en-GB > en-US > öteki; premium/gelişmiş kalite önce; şaka sesleri dışarıda.
    static var sesler: [AVSpeechSynthesisVoice] {
        let saka: Set<String> = ["bad news", "bahh", "bells", "boing", "bubbles", "cellos", "good news", "jester", "organ",
                                 "pipe organ", "superstar", "trinoids", "whisper", "wobble", "zarvox", "albert", "deranged",
                                 "hysterical", "junior", "ralph", "fred", "kathy", "bruce", "princess", "grandma", "grandpa",
                                 "rocko", "shelley", "sandy", "eddy", "flo", "reed", "rishi"]
        func puan(_ v: AVSpeechSynthesisVoice) -> Int {
            var p = v.language == "en-GB" ? 10 : v.language == "en-US" ? 8 : 4
            p += v.quality == .premium ? 6 : v.quality == .enhanced ? 4 : 0
            return p
        }
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") && !saka.contains($0.name.lowercased()) }
            .sorted { puan($0) > puan($1) }
    }
    var ses: AVSpeechSynthesisVoice? {
        Ses.sesler.first { $0.identifier == sesAdi } ?? Ses.sesler.first
    }

    private func soz(_ metin: String, hiz h: Double? = nil) -> AVSpeechUtterance {
        let u = AVSpeechUtterance(string: metin)
        u.voice = ses ?? AVSpeechSynthesisVoice(language: "en-GB")
        u.rate = Float(AVSpeechUtteranceDefaultSpeechRate) * Float(h ?? hiz)
        u.postUtteranceDelay = 0.15
        return u
    }

    /// Tek metin. `zorla` = kullanıcı bastı (ses kapalı olsa da çalar); değilse yalnız ses açıksa (yazımdan sonra doğrusu).
    func soyle(_ metin: String, zorla: Bool = true, cumle: Int? = nil) {
        guard zorla || acik, !metin.isEmpty else { return }
        dur()
        sira = [(cumle, metin)]
        ilerle()
    }

    /// Paragrafı cümle cümle — çalan cümle `calanCumle`'de.
    func zincir(_ metinler: [String]) {
        dur()
        sira = metinler.enumerated().map { ($0.offset, $0.element) }
        zincirde = true
        ilerle()
    }

    func dur() {
        sira = []
        zincirde = false
        calanCumle = nil
        if s.isSpeaking { s.stopSpeaking(at: .immediate) }
        oxOyuncu?.pause()
    }

    private func ilerle() {
        guard !sira.isEmpty else { calanCumle = nil; zincirde = false; return }
        let (i, m) = sira.removeFirst()
        calanCumle = i
        s.speak(soz(m))
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.ilerle() }
    }

    /// Kelime sesi: Oxford kaydı; adres ölü/çevrimdışıysa bir kez dener, sonra sistem sesine düşer.
    func kelime(_ w: String, sozluk: Sozluk) {
        dur()
        if let k = sozluk.bul(w), !k.ses.isEmpty, !oxOlu, let u = URL(string: Sozluk.ox + k.ses) {
            let o = AVPlayer(url: u)
            oxOyuncu = o
            o.play()
            let w2 = k.w
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard let self, self.oxOyuncu === o else { return }
                if o.currentItem?.status == .failed || (o.currentTime().seconds == 0 && o.rate == 0) {
                    self.oxOlu = true
                    self.s.speak(self.soz(w2, hiz: 0.85))
                }
            }
            return
        }
        s.speak(soz(sozluk.bul(w)?.w ?? w, hiz: 0.85))
    }

    func dene() { soyle("By the time I got home, my neighbour had already told me.") }
}

// MARK: - Paketin sesi (telefondaki Kokoro kaydı) ve kayıt dinleme

@MainActor
final class Calici: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var calan: URL?
    @Published var zaman: Double = 0
    @Published var sure: Double = 0
    private var p: AVAudioPlayer?
    private var t: Timer?

    func cal(_ u: URL) {
        if calan == u { durdur(); return }
        durdur()
        guard let x = try? AVAudioPlayer(contentsOf: u) else { return }
        x.delegate = self
        x.play()
        p = x; calan = u; sure = x.duration
        t = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.zaman = self?.p?.currentTime ?? 0 }
        }
    }
    func durdur() { p?.stop(); p = nil; calan = nil; t?.invalidate(); t = nil; zaman = 0 }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.durdur() }
    }
}

// MARK: - Kendi sesinle okuma (Mac)

/// Kayıt + cihaz içi tanıma. Dosya iPhone'unkiyle aynı biçim (AAC 16 kHz mono) ve aynı klasöre gider:
/// paket/gun-NNN/kayit/NNN-mac-<makine>-xxxx.m4a — ertesi sabah Whisper ikisini birlikte çözümler.
@MainActor
final class Kaydedici: NSObject, ObservableObject, AVAudioRecorderDelegate {
    enum Hal: Equatable { case bos, kayit, cozuluyor, bitti, hata(String) }
    @Published var hal: Hal = .bos
    @Published var sure: Double = 0
    @Published var seviye: Float = 0
    @Published var eslesen: Set<Int> = []
    @Published var okunan = 0
    @Published var sonuc: (yuzde: Int, okunan: Int, toplam: Int, takilan: [String])?

    private var k: AVAudioRecorder?
    private var u: URL?
    private var zaman: Timer?
    static let tavan: Double = 300

    func baslat(gun: Int) async {
        let izin = await AVCaptureDevice.requestAccess(for: .audio)
        guard izin else { hal = .hata("Mikrofon izni yok: Sistem Ayarları › Gizlilik › Mikrofon › Cümle."); return }
        let kk = OnCalisma.kayitKlasoru(gun)
        try? FileManager.default.createDirectory(at: kk, withIntermediateDirectories: true)
        let hedef = kk.appendingPathComponent(OnCalisma.yeniKayitAdi(gun))
        let ayar: [String: Any] = [AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 16_000,
                                   AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 24_000]
        do {
            let r = try AVAudioRecorder(url: hedef, settings: ayar)
            r.delegate = self
            r.isMeteringEnabled = true
            guard r.record(forDuration: Kaydedici.tavan) else { hal = .hata("Kayıt başlamadı."); return }
            k = r; u = hedef; sure = 0; eslesen = []; okunan = 0; sonuc = nil; hal = .kayit
            zaman = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tik() }
            }
        } catch { hal = .hata(error.localizedDescription) }
    }

    private func tik() {
        guard let r = k, r.isRecording else { return }
        r.updateMeters()
        sure = r.currentTime
        seviye = max(0, min(1, (r.averagePower(forChannel: 0) + 50) / 50))
    }

    /// Bitir → tanı → metinle karşılaştır. Dönen: dosya adı ve sonuç (çağıran olayı yazar).
    func bitir(metin: String, tanima: Bool) async -> (ad: String, sure: Double)? {
        let gecen = k?.currentTime ?? sure
        k?.stop(); zaman?.invalidate(); zaman = nil; seviye = 0
        guard let dosya = u else { hal = .bos; return nil }
        if gecen < 2 { try? FileManager.default.removeItem(at: dosya); hal = .bos; u = nil; return nil }   // yanlışlıkla dokunuş
        hal = .cozuluyor
        if tanima, let duyulan = await Kaydedici.tani(dosya) {
            let r = Kaydedici.karsilastir(metin: metin, duyulan: duyulan)
            eslesen = r.eslesen; okunan = r.okunan
            sonuc = (r.yuzde, r.okunan, r.toplam, r.takilan)
        }
        hal = .bitti
        return (dosya.lastPathComponent, gecen)
    }

    func vazgec() {
        k?.stop(); zaman?.invalidate(); zaman = nil
        if let d = u { try? FileManager.default.removeItem(at: d) }
        u = nil; hal = .bos; sure = 0
    }

    /// Cihaz içi tanıma. Uzun kayıtta tanıyıcı sonucu parça parça verir (her duraklamada yeni parça):
    /// yalnız son parçayı almak, metnin başını "takılan" gösteriyordu — parçalar biriktirilir.
    static func tani(_ u: URL) async -> String? {
        let durum: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard durum == .authorized else { return nil }
        guard let t = SFSpeechRecognizer(locale: Locale(identifier: "en-GB")) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              t.isAvailable else { return nil }
        let istek = SFSpeechURLRecognitionRequest(url: u)
        istek.shouldReportPartialResults = true
        istek.taskHint = .dictation
        if t.supportsOnDeviceRecognition { istek.requiresOnDeviceRecognition = true }
        return await withCheckedContinuation { (c: CheckedContinuation<String?, Never>) in
            let b = Biriktirici()
            t.recognitionTask(with: istek) { sonuc, hata in
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

    /// Okunan kelimelerden tanınanlar; takılan = SON tanınan kelimeye kadar tanınmayanlar (okunmayan kuyruk sayılmaz).
    static func karsilastir(metin: String, duyulan: String) -> (eslesen: Set<Int>, okunan: Int, toplam: Int, yuzde: Int, takilan: [String]) {
        let asil = Metin.kelimeler(metin), a = asil.map(Metin.sadele), b = Metin.kelimeler(duyulan).map(Metin.sadele)
        let n = a.count, m = b.count
        var s = Set<Int>()
        if n > 0 && m > 0 {
            var L = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) { L[i][j] = a[i] == b[j] ? L[i + 1][j + 1] + 1 : max(L[i + 1][j], L[i][j + 1]) }
            }
            var i = 0, j = 0
            while i < n && j < m {
                if a[i] == b[j] { s.insert(i); i += 1; j += 1 } else if L[i + 1][j] >= L[i][j + 1] { i += 1 } else { j += 1 }
            }
        }
        let son = s.max() ?? -1
        var takilan: [String] = []
        if son >= 0 {
            for k in 0...son where !s.contains(k) {
                let w = a[k]
                if w.count > 2, !Metin.dolguDisi.contains(w), !takilan.contains(w) { takilan.append(w) }
            }
        }
        let okunan = son + 1
        return (s, okunan, n, okunan > 0 ? Int((100.0 * Double(s.count) / Double(okunan)).rounded()) : 0, takilan)
    }
}

/// Tanıma parçalarını biriktirir. Parça sonu bildirilince metin kalıcı olur; tanıyıcı birikimli metin verirse
/// (eski davranış) yeni parça öncekilerin devamı sayılır, çift yazılmaz.
final class Biriktirici: @unchecked Sendable {
    var bitti = false
    private var kalici: [String] = []
    private var simdiki = ""
    func ekle(_ t: String, parcaSonu: Bool) {
        if let l = kalici.last, t == l { simdiki = ""; return }    // son parça, isFinal ile yeniden geldi
        let once = kalici.joined(separator: " ")
        if !once.isEmpty, t.hasPrefix(once) { kalici = []; simdiki = t } else { simdiki = t }
        if parcaSonu, !simdiki.isEmpty { kalici.append(simdiki); simdiki = "" }
    }
    var metin: String { (kalici + (simdiki.isEmpty ? [] : [simdiki])).joined(separator: " ") }
}
