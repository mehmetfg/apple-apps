import AVFoundation

/// AVAudioEngine kurgusu: oynatıcı → biçim çevirici (mono/yüksek çözünürlük → stereo) → Tını efekt birimi → çıkış.
/// Boşluksuz çalma: sıradaki parça aynı biçimdeyse, şimdiki bitmeden oynatıcının kuyruğuna eklenir ve
/// aralarında tek örnek bile sessizlik kalmaz (canlı albümler, kesintisiz mikslerde önemli).
@MainActor
final class Motor {
    struct Bolum {
        let kimlik: String
        let dosya: AVAudioFile
        let ilkKare: AVAudioFramePosition      // dosyada başladığı kare
        let baslangic: AVAudioFramePosition    // oynatıcı zamanında başladığı örnek
        let kareSayisi: AVAudioFrameCount
    }

    let motor = AVAudioEngine()
    private let oynatici = AVAudioPlayerNode()
    private let cevirici = AVAudioMixerNode()
    private(set) var efekt: AVAudioUnit?
    var zincir: Zincir? { (efekt?.auAudioUnit as? EfektBirimi)?.zincir }

    private var oynaticiBicimi: AVAudioFormat?
    private var bolumler: [Bolum] = []
    private var nesil = 0
    private var sonrakiBaslangic: AVAudioFramePosition = 0

    /// Bir bölüm sesini bitirince: (kimlik, sırada başka bölüm kaldı mı)
    var bolumBitti: ((String, Bool) -> Void)?
    /// Kulaklık takma/çıkarma gibi değişiklikler motoru durdurduğunda.
    var yenidenKurulmali: (() -> Void)?

    init() {
        motor.attach(oynatici)
        motor.attach(cevirici)
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: motor, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.yenidenKurulmali?() }
        }
    }

    /// Efekt birimini bir kez kurar.
    func hazirla() async throws {
        guard efekt == nil else { return }
        EfektBirimi.kaydet()
        let birim = try await AVAudioUnit.instantiate(with: EfektBirimi.tanim, options: [])
        motor.attach(birim)
        efekt = birim
        cikisiBagla()
    }

    private func cikisiBagla() {
        guard let efekt else { return }
        let hz = motor.outputNode.outputFormat(forBus: 0).sampleRate
        let stereo = AVAudioFormat(standardFormatWithSampleRate: hz > 0 ? hz : 48000, channels: 2)!
        motor.disconnectNodeOutput(cevirici)
        motor.disconnectNodeOutput(efekt)
        motor.connect(cevirici, to: efekt, format: stereo)
        motor.connect(efekt, to: motor.mainMixerNode, format: stereo)
        motor.mainMixerNode.outputVolume = 1
    }

    func calistir() throws {
        if !motor.isRunning {
            motor.prepare()
            try motor.start()
        }
    }

    // MARK: Çalma

    var caliyor: Bool { oynatici.isPlaying }

    /// `dosya`yı `saniye`den başlatır; önceki her şey (kuyruk dahil) temizlenir.
    func cal(kimlik: String, dosya: AVAudioFile, saniye: Double = 0) throws {
        nesil += 1
        oynatici.stop()
        bolumler.removeAll()
        sonrakiBaslangic = 0
        let bicim = dosya.processingFormat
        if oynaticiBicimi == nil || !bicimAyni(oynaticiBicimi!, bicim) {
            motor.disconnectNodeOutput(oynatici)
            motor.connect(oynatici, to: cevirici, format: bicim)
            oynaticiBicimi = bicim
        }
        zincir?.sifirla()
        try calistir()
        let ilk = AVAudioFramePosition(max(0, saniye) * bicim.sampleRate)
        guard ilk < dosya.length else { throw NSError(domain: "Tini", code: 1) }
        kuyrugaEkle(kimlik: kimlik, dosya: dosya, ilkKare: ilk)
        oynatici.play()
    }

    /// Sıradaki parçayı boşluksuz eklemeye çalışır. Biçim farklıysa false (o zaman bitince ayrıca başlatılır).
    @discardableResult
    func siradakiniEkle(kimlik: String, dosya: AVAudioFile) -> Bool {
        guard let b = oynaticiBicimi, bicimAyni(b, dosya.processingFormat), !bolumler.isEmpty, bolumler.count < 3 else { return false }
        kuyrugaEkle(kimlik: kimlik, dosya: dosya, ilkKare: 0)
        return true
    }

    /// Henüz başlamamış kuyruk bölümlerini atar (kullanıcı sırayı değiştirince).
    func siradakileriTemizle() {
        guard bolumler.count > 1, let s = simdikiBolum else { return }
        // AVAudioPlayerNode'dan tek bölüm silinemez: şimdikini kaldığı yerden yeniden kur.
        let saniye = konum
        try? cal(kimlik: s.kimlik, dosya: s.dosya, saniye: saniye)
    }

    private func kuyrugaEkle(kimlik: String, dosya: AVAudioFile, ilkKare: AVAudioFramePosition) {
        let sayi = AVAudioFrameCount(dosya.length - ilkKare)
        let bolum = Bolum(kimlik: kimlik, dosya: dosya, ilkKare: ilkKare, baslangic: sonrakiBaslangic, kareSayisi: sayi)
        sonrakiBaslangic += AVAudioFramePosition(sayi)
        bolumler.append(bolum)
        let n = nesil
        oynatici.scheduleSegment(dosya, startingFrame: ilkKare, frameCount: sayi, at: nil,
                                 completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, n == self.nesil else { return }
                guard let i = self.bolumler.firstIndex(where: { $0.baslangic == bolum.baslangic }) else { return }
                self.bolumler.remove(at: i)
                self.bolumBitti?(kimlik, !self.bolumler.isEmpty)
            }
        }
    }

    func duraklat() { oynatici.pause() }

    func devam() throws {
        try calistir()
        oynatici.play()
    }

    func durdur() {
        nesil += 1
        oynatici.stop()
        bolumler.removeAll()
        sonrakiBaslangic = 0
    }

    func motoruDuraklat() {
        if motor.isRunning { motor.pause() }
    }

    // MARK: Konum

    private var oynaticiOrnegi: AVAudioFramePosition? {
        guard let dz = oynatici.lastRenderTime, dz.isSampleTimeValid,
              let oz = oynatici.playerTime(forNodeTime: dz) else { return nil }
        return oz.sampleTime
    }

    /// Şu an sesi duyulan bölüm.
    var simdikiBolum: Bolum? {
        guard let o = oynaticiOrnegi else { return bolumler.first }
        return bolumler.last(where: { $0.baslangic <= o }) ?? bolumler.first
    }

    /// Şimdiki parçada saniye.
    var konum: Double {
        guard let b = simdikiBolum else { return 0 }
        let o = oynaticiOrnegi ?? b.baslangic
        let kare = Double(b.ilkKare + max(0, o - b.baslangic))
        return min(kare, Double(b.dosya.length)) / b.dosya.processingFormat.sampleRate
    }

    func yenidenBagla() {
        cikisiBagla()
    }

    private func bicimAyni(_ a: AVAudioFormat, _ b: AVAudioFormat) -> Bool {
        a.sampleRate == b.sampleRate && a.channelCount == b.channelCount && a.commonFormat == b.commonFormat
            && a.isInterleaved == b.isInterleaved
    }
}
