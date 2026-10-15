import AVFoundation
import SwiftUI

@main
struct EmaApp: App {
    var body: some Scene {
        WindowGroup { AnaEkran() }
    }
}

struct AnaEkran: View {
    @State private var metin = "Herbert Simon, bin dokuz yüz yetmiş bir yılında bu dersi tek bir cümleye sığdırmıştı: bilgi zenginliği, dikkat yoksulluğu doğurur. Elinizdeki eser, kıymeti kaybetmeden anlamanın bir denemesidir."
    @State private var hiz = 1.0
    @State private var sesler: [AVSpeechSynthesisVoice] = []
    @State private var konusucu = AVSpeechSynthesizer()
    @State private var calar: AVAudioPlayer?
    @State private var olcum = "—"
    @State private var calisiyor = false
    @State private var izleyici = Izleyici()
    @State private var sesSinayici: AVSpeechSynthesizer?
    @State private var perde = Ayar.perde
    @State private var yukseklik = Ayar.yukseklik
    @State private var isaretBirimi = Ayar.isaretCarpani
    @State private var muzikArasi = Ayar.muzikArasi
    @State private var muzikDakika = Ayar.muzikDakika
    @State private var arkaPlan = Ayar.arkaPlan
    @State private var arkaPlanSeviye = Ayar.arkaPlanSeviye
    @State private var muzikler: [String] = []

    private var ema: AVSpeechSynthesisVoice? { sesler.first { $0.identifier.hasSuffix(Ses.kimlik) } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Sistem sesi", value: ema == nil ? "görünmüyor" : "hazır ✓")
                } footer: {
                    Text("Ayarlar › Erişilebilirlik › Konuşulan İçerik › Sesler › Türkçe › Ema")
                }
                Section("Metin") {
                    TextEditor(text: $metin).frame(minHeight: 140)
                    LabeledContent("Hız", value: String(format: "%.1f× · ≈%.0f k/dk", hiz, hiz * 148))
                    Slider(value: $hiz, in: 0.5...4, step: 0.1)
                }
                Section {
                    LabeledContent("Perde", value: perde == 0 ? "doğal" : String(format: "%+.1f yarım ton", perde))
                    Slider(value: $perde, in: -8...8, step: 0.5)
                    LabeledContent("Ses yüksekliği", value: String(format: "%%%.0f", yukseklik * 100))
                    Slider(value: $yukseklik, in: 0.5...2, step: 0.1)
                    HStack {
                        Button("Dene") { dene() }.disabled(calisiyor)
                        Spacer()
                        Button("Sıfırla") { perde = 0; yukseklik = 1 }.disabled(perde == 0 && yukseklik == 1)
                    }
                } header: {
                    Text("Ses ayarı")
                } footer: {
                    Text("Ema'yı kullanan her yerde geçerli (Seçimi Seslendir, Voice Dream…). Uygulamanın kendi perde ve ses ayarı bunun üstüne eklenir.")
                }
                .onChange(of: perde) { _, v in Ayar.perde = v }
                .onChange(of: yukseklik) { _, v in Ayar.yukseklik = v }
                Section {
                    Toggle("Müzik arası", isOn: $muzikArasi)
                    Stepper("Her \(muzikDakika) dakikada bir", value: $muzikDakika, in: 5...60, step: 5)
                        .disabled(!muzikArasi)
                    Toggle("Arka plan müziği", isOn: $arkaPlan)
                    if arkaPlan {
                        LabeledContent("Seviye", value: String(format: "%%%.0f", arkaPlanSeviye * 100))
                        Slider(value: $arkaPlanSeviye, in: 0.05...0.5, step: 0.05)
                    }
                    Text(muzikler.isEmpty ? "Henüz müzik yok." : muzikler.joined(separator: "\n"))
                        .font(.footnote).foregroundStyle(.secondary)
                } header: {
                    Text("Müzik")
                } footer: {
                    Text("Dosyalar › iPhone'umda › Ema › Müzik klasörüne mp3/m4a koy. Ema'yı kullanan her yerde (Voice Dream) çalar. Spotify ve Apple Music şifreli olduğu için bu yolla çalınamaz.")
                }
                .onChange(of: muzikArasi) { _, v in Ayar.muzikArasi = v }
                .onChange(of: muzikDakika) { _, v in Ayar.muzikDakika = v }
                .onChange(of: arkaPlan) { _, v in Ayar.arkaPlan = v }
                .onChange(of: arkaPlanSeviye) { _, v in Ayar.arkaPlanSeviye = v }
                Section {
                    Picker("İmleç birimi", selection: $isaretBirimi) {
                        Text("bayt").tag(4)
                        Text("örnek").tag(1)
                    }
                    .onChange(of: isaretBirimi) { _, v in Ayar.isaretCarpani = v }
                } header: {
                    Text("İnce ayar")
                } footer: {
                    Text("Voice Dream'de imleç sesin önüne geçiyor ya da geride kalıyorsa öbürünü seç.")
                }
                Section {
                    Button("Sistem sesiyle oku") { sistemle() }.disabled(ema == nil)
                    Button("Durdur", role: .destructive) { durdur() }
                    Button(calisiyor ? "Üretiliyor…" : "Hız ölçümü (uygulama içinde)") { olc() }.disabled(calisiyor)
                } footer: {
                    Text(olcum)
                }
            }
            .navigationTitle("Ema")
            .onAppear {
                bildir()
                Muzik.esitle()
                muzikler = Muzik.liste.map(Muzik.ad)
                if let k = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Ayar.grup) {
                    try? "okundu-\(Int(Date().timeIntervalSince1970))".write(to: k.appendingPathComponent("okuma-sinama.txt"), atomically: true, encoding: .utf8)
                }
                // Mac'ten ölçüm: devicectl … launch com.fatihgocgun.ema -olc  → Belgeler/olcum.txt + son.wav + sistem.wav
                if ProcessInfo.processInfo.arguments.contains("-olc") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { olc { sesSina("Supertonic Erkek 4", oran: 0.75) { sesSina("Supertonic Erkek 4", oran: 0.75) { sesSina("Piper Dfki", oran: 0.75) { sesSina("Ema", oran: 0.75) {} } } } } }
                }
            }
            .refreshable { yenile(); Muzik.esitle(); muzikler = Muzik.liste.map(Muzik.ad) }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                Muzik.esitle(); muzikler = Muzik.liste.map(Muzik.ad)
            }
        }
    }

    private func bildir() {
        AVSpeechSynthesisProviderVoice.updateSpeechVoices()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { yenile() }
    }

    private func yenile() {
        sesler = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("tr") }
    }

    private func sistemle() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        let s = AVSpeechUtterance(string: metin)
        s.voice = ema
        s.rate = AVSpeechUtteranceDefaultSpeechRate * Float(hiz)
        konusucu.speak(s)
    }

    // Sistem sesi yolu: metni uzantıya gönderir, sesi tampon tampon alıp dosyaya yazar.
    private func sistemDosyaya(oranlar: [Float] = [AVSpeechUtteranceDefaultSpeechRate]) {
        guard let oranHiz = oranlar.first else { return }
        yenile()
        let tum = AVSpeechSynthesisVoice.speechVoices()
        Kayit.ekle("sesler: \(tum.count) toplam · tr: " + tum.filter { $0.language.hasPrefix("tr") }
            .map { "\($0.name)|\($0.identifier)|\($0.language)" }.joined(separator: ", ")
            + " · ema benzeri: " + tum.filter { $0.identifier.contains("ema") || $0.name.contains("Ema") }
            .map { "\($0.name)|\($0.identifier)|\($0.language)" }.joined(separator: ", "))
        guard let ema else { Kayit.ekle("sistem: Ema sesi listede yok"); return }
        let s = AVSpeechUtterance(string: metin)
        s.voice = ema
        s.rate = oranHiz
        s.pitchMultiplier = 1.2  // SSML'de nasıl geldiğini görmek için
        s.volume = 0.8
        var ses: [Float] = []
        var oran = 48000.0
        let t0 = Date()
        var ilk: TimeInterval?
        konusucu.write(s) { tampon in
            guard let pcm = tampon as? AVAudioPCMBuffer else { return }
            if pcm.frameLength == 0 {
                let sure = Date().timeIntervalSince(t0), sn = Double(ses.count) / oran
                Kayit.ekle(String(format: "sistem (rate %.2f): ilk tampon", oranHiz) + String(format: " %.2f sn · %.1f sn ses %.1f sn'de · %.1f× · %.0f Hz",
                                  ilk ?? -1, sn, sure, sn / max(sure, 0.001), oran))
                let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("sistem.wav")
                if oranHiz == oranlar.first { try? Wav.yaz(ses, hiz: Int(oran), url: url) }
                Kayit.ekle("son SSML: " + Ayar.sonSSML())
                DispatchQueue.main.async { sistemDosyaya(oranlar: Array(oranlar.dropFirst())) }
                return
            }
            if ilk == nil { ilk = Date().timeIntervalSince(t0) }
            oran = pcm.format.sampleRate
            if let k = pcm.floatChannelData?[0] {
                ses += UnsafeBufferPointer(start: k, count: Int(pcm.frameLength))
            } else if let k = pcm.int16ChannelData?[0] {
                ses += UnsafeBufferPointer(start: k, count: Int(pcm.frameLength)).map { Float($0) / 32768 }
            }
        }
    }

    // Ayarlı sesi uygulamanın içinde üretip çalar (uzantıyla aynı işleyici).
    private func dene() {
        calisiyor = true
        let yazi = metin, h = hiz, p = perde, y = yukseklik
        DispatchQueue.global(qos: .userInitiated).async {
            guard let motor = Motor.ortak else { DispatchQueue.main.async { calisiyor = false }; return }
            let isl = Isleyici(perdeYarimTon: p, yukseklik: y, tempo: h, oran: Double(motor.ayar.rate))
            var ses: [Float] = []
            try? motor.seslendir(yazi, hiz: min(h, 1)) { ses += isl.isle($0) }
            ses += isl.bitir()
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("dene.wav")
            try? Wav.yaz(ses, hiz: motor.ayar.rate, url: url)
            DispatchQueue.main.async {
                calisiyor = false
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                calar = try? AVAudioPlayer(contentsOf: url)
                calar?.play()
            }
        }
    }

    // Ölçüm: +3 yarım ton, %150 — süre korunuyor mu, tepe seviyesi sınırda mı.
    private func perdeSina(sonra: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let motor = Motor.ortak else { return }
            var ham: [Float] = []
            try? motor.seslendir("Elinizdeki eser, kıymeti kaybetmeden anlamanın bir denemesidir.") { ham += $0 }
            let t0 = Date()
            let isl = Isleyici(perdeYarimTon: 3, yukseklik: 1.5, oran: Double(motor.ayar.rate))
            var ses = isl.isle(ham)
            ses += isl.bitir()
            let dt = Date().timeIntervalSince(t0)
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("perde.wav")
            try? Wav.yaz(ses, hiz: motor.ayar.rate, url: url)
            let r = Double(motor.ayar.rate)
            Kayit.ekle(String(format: "perde: ham %.2f sn → işlenmiş %.2f sn, %.3f sn'de · tepe ham %.2f işlenmiş %.2f",
                              Double(ham.count) / r, Double(ses.count) / r, dt,
                              ham.map(abs).max() ?? 0, ses.map(abs).max() ?? 0))
            DispatchQueue.main.async(execute: sonra)
        }
    }

    // Ölçüm: Kıymet paragrafı 360 ve 500 k/dk — telefonda üretim hızı ve sonuç dosyaları.
    private func hizSina(sonra: @escaping () -> Void) {
        let yazi = "Ekonominin en eski ve en az anlaşılmış derslerinden biri şudur ki bir şey bollaştığında değer ortadan kalkmaz, yalnızca yer değiştirir ve bollaşan şeyin yanında durup onu anlamlı kılan, ama kendisi bollaşmayan şeye doğru akar. Elektrik ucuzladığında değer elektrikte değil, onunla ne yapılacağını bilen mühendiste ve fabrikayı yeniden düzenleyen yöneticide toplandı."
        DispatchQueue.global(qos: .userInitiated).async {
            guard let motor = Motor.ortak else { return }
            let kel = Double(yazi.split(separator: " ").count), r = Double(motor.ayar.rate)
            for (kdk, ad) in [(360.0, "hiz360"), (500.0, "hiz500")] {
                let t0 = Date()
                var ham: [Float] = []
                try? motor.seslendir(yazi, hiz: 1) { ham += $0 }
                let tempo = (Double(ham.count) / r) / (kel / kdk * 60)
                let t1 = Date()
                let isl = Isleyici(perdeYarimTon: 0, yukseklik: 1, tempo: tempo, oran: r)
                var ses = isl.isle(ham); ses += isl.bitir()
                let sure = Double(ses.count) / r
                try? Wav.yaz(ses, hiz: motor.ayar.rate,
                             url: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(ad + ".wav"))
                Kayit.ekle(String(format: "%@: tempo %.2f · %.1f sn ses → %.0f k/dk · model %.2f sn + sıkıştırma %.3f sn",
                                  ad, tempo, sure, kel / sure * 60, t1.timeIntervalSince(t0), Date().timeIntervalSince(t1)))
            }
            DispatchQueue.main.async(execute: sonra)
        }
    }

    // İmleç sınaması: Ema'yla dosyaya yazar gibi üretir; sistemin kelime işaretlerini ve toplam sesi kaydeder.
    // Son işaretin konumu toplam örnek sayısının ~4 katıysa birim bayt (doğru), ~1 katıysa örnek.
    private func imlecSina(deneme: Int = 0, sonra: @escaping () -> Void) {
        yenile()
        guard let ema else {
            if deneme < 10 {
                AVSpeechSynthesisProviderVoice.updateSpeechVoices()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { imlecSina(deneme: deneme + 1, sonra: sonra) }
            } else { Kayit.ekle("imleç: Ema yok"); sonra() }
            return
        }
        let yazi = "Herbert Simon 1971 yılında, bu dersi tek bir cümleye sığdırmıştı: bilgi zenginliği dikkat yoksulluğu doğurur."
        let u = AVSpeechUtterance(string: yazi)
        u.voice = ema
        var kare = 0, isaretler: [String] = []
        var bitti = false
        konusucu.write(u, toBufferCallback: { tampon in
            guard let pcm = tampon as? AVAudioPCMBuffer else { return }
            if pcm.frameLength == 0 {
                guard !bitti else { return }
                bitti = true
                Kayit.ekle("imleç: toplam \(kare) örnek · " + isaretler.joined(separator: " | "))
                Ayar.uzantiKaydi("uygulamadan deneme satırı")
                Kayit.ekle("grup: \(FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Ayar.grup)?.path ?? "YOK") · SSML: " + Ayar.sonSSML().prefix(300))
                Kayit.ekle("uzantı kaydı: " + Ayar.uzantiKaydiOku().split(separator: "\n").suffix(6).joined(separator: " // "))
                DispatchQueue.main.async(execute: sonra)
            } else { kare += Int(pcm.frameLength) }
        }, toMarkerCallback: { liste in
            for m in liste {
                let r = m.textRange
                let parca = r.location != NSNotFound && NSMaxRange(r) <= (yazi as NSString).length ? (yazi as NSString).substring(with: r) : "?"
                isaretler.append("\(m.byteSampleOffset):\(parca)")
            }
        })
    }

    // Sistem yolundan bir sesi dosyaya yazar gibi üretir: süre, ses uzunluğu, gerçek zaman katı.
    private func sesSina(_ ad: String, oran: Float = AVSpeechUtteranceDefaultSpeechRate, deneme: Int = 0, sonra: @escaping () -> Void) {
        let ses = AVSpeechSynthesisVoice.speechVoices().first { $0.name == ad }
        guard let ses else {
            if deneme < 10 {
                AVSpeechSynthesisProviderVoice.updateSpeechVoices()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { sesSina(ad, oran: oran, deneme: deneme + 1, sonra: sonra) }
            } else { Kayit.ekle("\(ad): listede yok"); sonra() }
            return
        }
        let u = AVSpeechUtterance(string: "Ekonominin en eski ve en az anlaşılmış derslerinden biri şudur ki bir şey bollaştığında değer ortadan kalkmaz, yalnızca yer değiştirir.")
        u.voice = ses
        u.rate = oran
        var kare = 0, bitti = false
        var tepe: Float = 0
        var kayit: [Float] = []
        let t0 = Date()
        var ilk: TimeInterval?
        let yaz = AVSpeechSynthesizer()
        sesSinayici = yaz
        yaz.write(u) { tampon in
            guard let pcm = tampon as? AVAudioPCMBuffer else { return }
            if pcm.frameLength == 0 {
                guard !bitti else { return }
                bitti = true
                let sn = Double(kare) / 48000, sure = Date().timeIntervalSince(t0)
                Kayit.ekle(String(format: "%@ (rate %.2f): ilk ses %.2f sn · %.1f sn ses %.1f sn'de · %.1f× · tepe %.2f", ad, oran, ilk ?? -1, sn, sure, sn / max(sure, 0.001), tepe))
                let dosya = ad.replacingOccurrences(of: " ", with: "-") + ".wav"
                try? Wav.yaz(kayit, hiz: 48000, url: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(dosya))
                DispatchQueue.main.async(execute: sonra)
            } else {
                if ilk == nil { ilk = Date().timeIntervalSince(t0) }
                kare += Int(pcm.frameLength)
                if let k = pcm.floatChannelData?[0] {
                    for i in 0..<Int(pcm.frameLength) { tepe = max(tepe, abs(k[i])) }
                    kayit += UnsafeBufferPointer(start: k, count: Int(pcm.frameLength))
                }
            }
        }
    }

    // Müzik arası sınaması: ayarı geçici 0 dk yapar, Ema ile üretir; ses uzunluğu müziği içermeli. Sonra eski hâline döner.
    private func muzikSina(sonra: @escaping () -> Void) {
        Muzik.esitle()
        let eski = (Ayar.muzikArasi, Ayar.muzikDakika)
        Ayar.muzikArasi = true; Ayar.muzikDakika = 0
        Kayit.ekle("müzik dosyaları: " + Muzik.liste.map(Muzik.ad).joined(separator: ", "))
        sesSina("Ema") {
            Ayar.muzikArasi = eski.0; Ayar.muzikDakika = eski.1
            let y = Ayar.yukseklik
            Ayar.yukseklik = 2
            sesSina("Ema") {   // tepe ilk Ema ölçümünün ~2 katıysa uzantı ayarı okuyor
                Ayar.yukseklik = y
                sonra()
            }
        }
    }

    private func durdur() {
        konusucu.stopSpeaking(at: .immediate)
        calar?.stop()
    }

    // Motoru uygulamanın içinde çalıştırır: ilk ses gecikmesi, toplam süre, gerçek zaman katı.
    // Sonucu çalar ve Belgeler/son.wav olarak saklar.
    private func olc(sonra: (() -> Void)? = nil) {
        calisiyor = true
        olcum = "model yükleniyor…"
        let yazi = metin, h = hiz
        DispatchQueue.global(qos: .userInitiated).async {
            let t0 = Date()
            guard let motor = Motor.ortak else {
                DispatchQueue.main.async { olcum = "model yüklenemedi"; calisiyor = false }
                return
            }
            let yukleme = Date().timeIntervalSince(t0)
            let t1 = Date()
            var ilk: TimeInterval?
            var ses: [Float] = []
            do {
                try motor.seslendir(yazi, hiz: h) { parca in
                    if ilk == nil { ilk = Date().timeIntervalSince(t1) }
                    ses += parca
                }
            } catch {
                DispatchQueue.main.async { olcum = "hata: \(error.localizedDescription)"; calisiyor = false }
                return
            }
            let sure = Date().timeIntervalSince(t1)
            let saniye = Double(ses.count) / Double(motor.ayar.rate)
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("son.wav")
            try? Wav.yaz(ses, hiz: motor.ayar.rate, url: url)
            let ozet = String(format: "yükleme %.1f sn · ilk ses %.2f sn · %.1f sn ses %.1f sn'de · %.1f× gerçek zaman",
                              yukleme, ilk ?? 0, saniye, sure, saniye / max(sure, 0.001))
            DispatchQueue.main.async {
                olcum = ozet
                calisiyor = false
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                Kayit.ekle("uygulama: " + ozet)
                if let sonra { sonra() } else {
                    calar = try? AVAudioPlayer(contentsOf: url)
                    calar?.play()
                }
            }
        }
    }
}

final class Izleyici: NSObject, AVSpeechSynthesizerDelegate {
    private var t0 = Date(), metin = "", satir: [String] = [], bitince: ((String) -> Void)?
    func basla(_ m: String, bitince b: @escaping (String) -> Void) { metin = m; satir = []; bitince = b; t0 = Date() }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) { t0 = Date() }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, willSpeakRangeOfSpeechString r: NSRange, utterance u: AVSpeechUtterance) {
        satir.append(String(format: "%.2f:", Date().timeIntervalSince(t0)) + (metin as NSString).substring(with: r))
    }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        bitince?(String(format: "toplam %.2f sn · ", Date().timeIntervalSince(t0)) + satir.joined(separator: " | ")); bitince = nil
    }
}

enum Kayit {
    static func ekle(_ satir: String) {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("olcum.txt")
        let onceki = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try? (onceki + ISO8601DateFormatter().string(from: Date()) + " " + satir + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}

enum Wav {
    static func yaz(_ ornek: [Float], hiz: Int, url: URL) throws {
        var d = Data()
        func ekle<T>(_ v: T) { withUnsafeBytes(of: v) { d.append(contentsOf: $0) } }
        let veri = ornek.count * 2
        d.append(contentsOf: "RIFF".utf8); ekle(UInt32(36 + veri).littleEndian)
        d.append(contentsOf: "WAVEfmt ".utf8); ekle(UInt32(16).littleEndian); ekle(UInt16(1).littleEndian)
        ekle(UInt16(1).littleEndian); ekle(UInt32(hiz).littleEndian); ekle(UInt32(hiz * 2).littleEndian)
        ekle(UInt16(2).littleEndian); ekle(UInt16(16).littleEndian)
        d.append(contentsOf: "data".utf8); ekle(UInt32(veri).littleEndian)
        for x in ornek { ekle(Int16(max(-1, min(1, x)) * 32767).littleEndian) }
        try d.write(to: url)
    }
}
