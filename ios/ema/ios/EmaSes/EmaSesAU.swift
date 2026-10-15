import AVFoundation
import CoreAudioKit
import os

// Sistemin konuşma motoru bu sınıfı çağırır: metni (SSML) verir, sesi parça parça çeker.
// Üretim arka planda cümle cümle ilerler; ilk cümle hazır olur olmaz ses akmaya başlar.
public class EmaSesAU: AVSpeechSynthesisProviderAudioUnit {
    private var cikisVeriyolu: AUAudioUnitBusArray!
    private let bicim = AVAudioFormat(standardFormatWithSampleRate: Ses.ornekHizi, channels: 1)!
    private let kuyruk = DispatchQueue(label: "ema.uretim", qos: .userInitiated)

    // Render iş parçacığıyla paylaşılan durum.
    private var kilit = os_unfair_lock()
    private var ornekler: [Float] = []
    private var konum = 0
    private var uretimBitti = true
    private var bitti = true
    private var nesil = 0  // her yeni istek bir öncekini geçersiz kılar

    public override init(componentDescription: AudioComponentDescription,
                         options: AudioComponentInstantiationOptions = []) throws {
        Sesler.piperKurulu = { Piper.kurulu($0) }
        Sesler.piperYapici = { try? Piper(ad: $0) }
        try super.init(componentDescription: componentDescription, options: options)
        let veriyolu = try AUAudioUnitBus(format: bicim)
        cikisVeriyolu = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [veriyolu])
        kuyruk.async { _ = Sesler.motor(Sesler.ema) }  // Ema'yı önceden yükle
    }

    public override var outputBusses: AUAudioUnitBusArray { cikisVeriyolu }

    public override var speechVoices: [AVSpeechSynthesisProviderVoice] {
        get { Sesler.hepsi.map(\.sistemSesi) }
        set {}
    }

    public override func synthesizeSpeechRequest(_ istek: AVSpeechSynthesisProviderRequest) {
        let ssml = istek.ssmlRepresentation
        let metin = Ses.duzMetin(ssml), hiz = Ses.hiz(ssml), konusma = Ses.konusmaMetni(ssml)
        let perde = Ayar.perde + Ses.perde(ssml), yukseklik = Ayar.yukseklik * Ses.yukseklik(ssml)
        Ayar.uzantiKaydi("ses \(Sesler.tanim(istek.voice.identifier).ad) · bellek payı \(os_proc_available_memory() / 1_048_576) MB · istek: \(metin.count) harf · hız \(hiz) · grup \(FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Ayar.grup) == nil ? "YOK" : "var")")
        os_unfair_lock_lock(&kilit)
        nesil += 1
        let benim = nesil
        ornekler = []
        konum = 0
        uretimBitti = false
        bitti = false
        os_unfair_lock_unlock(&kilit)

        kuyruk.async { [weak self] in
            guard let self else { return }
            let gecerli = { () -> Bool in
                os_unfair_lock_lock(&self.kilit); defer { os_unfair_lock_unlock(&self.kilit) }
                return self.nesil == benim
            }
            let ekle = { (parca: [Float]) in
                os_unfair_lock_lock(&self.kilit)
                if self.nesil == benim {
                    if self.konum > 480_000 {  // çalınmış kısmı at, bellek büyümesin
                        self.ornekler.removeFirst(self.konum)
                        self.konum = 0
                    }
                    self.ornekler += parca
                }
                os_unfair_lock_unlock(&self.kilit)
            }
            let isleyici = Isleyici(perdeYarimTon: perde, yukseklik: yukseklik, tempo: hiz, oran: Ses.ornekHizi)
            // Müzik arası: zamanı geldiyse konuşmadan önce bir parça çalar. Tampon en çok 10 sn dolar,
            // dosya parça parça okunur (bütün şarkı belleğe alınmaz).
            var muzikOrnek = 0
            if let parca = MuzikDurumu.ortak.araParcasi() {
                let sr = Int(Ses.ornekHizi), gecis = sr  // 1 sn yumuşak giriş/çıkış
                let toplam = Int(parca.toplamSaniye * Ses.ornekHizi)
                Ayar.uzantiKaydi("müzik arası: \(Int(parca.toplamSaniye)) sn")
                while gecerli() {
                    while gecerli() && self.dolu() > 10 * sr { usleep(50_000) }
                    var m = parca.oku(2 * sr)
                    if m.isEmpty { break }
                    for k in m.indices {
                        let n = muzikOrnek + k
                        m[k] *= 0.8 * Float(min(1, Double(n) / Double(gecis), Double(max(0, toplam - n)) / Double(gecis)))
                    }
                    muzikOrnek += m.count
                    ekle(m)
                }
                ekle([Float](repeating: 0, count: sr / 2))
                muzikOrnek += sr / 2
            }
            let tanim = Sesler.tanim(istek.voice.identifier)
            if let motor = Sesler.motor(tanim) {
                let modelHizi = tanim.tur == .ema ? min(hiz, 1) : hiz
                // İmleç: her model kelimesi asıl metindeki bir sözcüğe eşlenir, sesteki yeri işaret olarak bildirilir.
                let harita = Metin.kelimeHaritasi(konusma, sozluk: motor.sozluk)
                Ayar.uzantiKaydi("harita \(harita.count) · konuşma metni \(konusma.count) harf")
                var kelimeNo = 0, istekOrnek = muzikOrnek
                var sonAralik = NSRange(location: NSNotFound, length: 0)
                try? motor.seslendirKelimeli(metin, hiz: modelHizi, devam: gecerli) { ses, kelimeler in
                    var (cikis, sureler) = isleyici.isle(ses, kelimeler: kelimeler)
                    MuzikDurumu.ortak.karistir(&cikis)
                    MuzikDurumu.ortak.konusuldu(Double(cikis.count) / Ses.ornekHizi)
                    var isaretler: [AVSpeechSynthesisMarker] = []
                    var konum = istekOrnek
                    for sure in sureler {
                        if kelimeNo < harita.count, harita[kelimeNo] != sonAralik {
                            sonAralik = harita[kelimeNo]
                            isaretler.append(AVSpeechSynthesisMarker(markerType: .word, forTextRange: sonAralik,
                                                                     atByteSampleOffset: konum * Ses.isaretCarpani))
                        }
                        kelimeNo += 1
                        konum += sure
                    }
                    istekOrnek += cikis.count
                    if !isaretler.isEmpty, gecerli() {
                        let blok = self.speechSynthesisOutputMetadataBlock
                        Ayar.uzantiKaydi("işaret \(isaretler.count) · blok \(blok == nil ? "YOK" : "var") · ilk \(isaretler[0].byteSampleOffset) · harita \(harita.count) kelime")
                        blok?(isaretler, istek)
                    }
                    ekle(cikis)
                }
                ekle(isleyici.bitir())
            } else {
                ekle(Uretici.uret(metin))  // model yüklenemezse bip: en azından hata duyulur
            }
            os_unfair_lock_lock(&self.kilit)
            if self.nesil == benim { self.uretimBitti = true }
            os_unfair_lock_unlock(&self.kilit)
        }
    }

    /// Çalınmayı bekleyen örnek sayısı.
    private func dolu() -> Int {
        os_unfair_lock_lock(&kilit); defer { os_unfair_lock_unlock(&kilit) }
        return ornekler.count - konum
    }

    public override func cancelSpeechRequest() {
        os_unfair_lock_lock(&kilit)
        nesil += 1
        ornekler = []
        konum = 0
        uretimBitti = true
        bitti = true
        os_unfair_lock_unlock(&kilit)
    }

    public override var internalRenderBlock: AUInternalRenderBlock {
        return { [unowned self] bayraklar, _, kareSayisi, _, cikis, _, _ in
            let liste = UnsafeMutableAudioBufferListPointer(cikis)
            let hedef = liste[0].mData!.assumingMemoryBound(to: Float.self)
            let n = Int(kareSayisi)
            // Konuşma servisi sesi kendi tamponuna çeker; üretim sürerken sessizlik vermek yerine
            // sesin gelmesini bekle (en çok 5 sn). Yoksa dosyaya yazımda araya dakikalarca boşluk girer.
            var bekleme = 0
            while true {
                os_unfair_lock_lock(&self.kilit)
                let hazir = self.bitti || self.uretimBitti || self.ornekler.count - self.konum >= n
                if hazir || bekleme >= 1000 { break }
                os_unfair_lock_unlock(&self.kilit)
                usleep(5_000)
                bekleme += 1
            }
            let alinan = max(0, min(n, self.ornekler.count - self.konum))
            if alinan > 0 {
                self.ornekler.withUnsafeBufferPointer { kaynak in
                    hedef.update(from: kaynak.baseAddress! + self.konum, count: alinan)
                }
                self.konum += alinan
            }
            if alinan < n { (hedef + alinan).update(repeating: 0, count: n - alinan) }
            if self.bitti || (self.uretimBitti && self.konum >= self.ornekler.count) {
                bayraklar.pointee = .offlineUnitRenderAction_Complete
                self.bitti = true
            }
            os_unfair_lock_unlock(&self.kilit)
            liste[0].mDataByteSize = UInt32(n * MemoryLayout<Float>.size)
            return noErr
        }
    }
}

// Uzantının giriş noktası (Info.plist: NSExtensionPrincipalClass).
public class AudioUnitFactory: NSObject, AUAudioUnitFactory {
    public func beginRequest(with context: NSExtensionContext) {}

    public func createAudioUnit(with aciklama: AudioComponentDescription) throws -> AUAudioUnit {
        try EmaSesAU(componentDescription: aciklama, options: [])
    }
}
