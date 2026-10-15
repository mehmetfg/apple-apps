import AVFoundation

// Kullanıcının kendi müzik dosyaları (mp3/m4a/wav): Dosyalar › Ema › Müzik.
// Uzantı klavye korumalı alanında MP3/AAC çözemiyor (AudioComponentRegistrar reddediliyor, 2026-10-09 ölçümü).
// Bu yüzden uygulama her dosyayı ham sese (48 kHz, tek kanal, 16 bit) çevirip App Group › Muzik/*.pcm yazar;
// uzantı yalnız bu ham dosyaları parça parça okur. Spotify ve Apple Music şifreli olduğu için bu yolla çalınamaz.
enum Muzik {
    static let uzantilar = Set(["mp3", "m4a", "aac", "wav", "aif", "aiff", "caf"])

    static var ortakKlasor: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Ayar.grup)?.appendingPathComponent("Muzik")
    }

    static var liste: [URL] {
        guard let k = ortakKlasor,
              let l = try? FileManager.default.contentsOfDirectory(at: k, includingPropertiesForKeys: nil) else { return [] }
        return l.filter { $0.pathExtension == "pcm" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Uygulama tarafı: Belgeler/Müzik'teki dosyaları ham sese çevirip ortak alana yazar (yeniyi çevirir, sileneni siler).
    static func esitle() {
        let fm = FileManager.default
        guard let hedef = ortakKlasor,
              let belgeler = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let kaynak = belgeler.appendingPathComponent("Müzik")
        try? fm.createDirectory(at: kaynak, withIntermediateDirectories: true)
        try? fm.createDirectory(at: hedef, withIntermediateDirectories: true)
        let dosyalar = ((try? fm.contentsOfDirectory(at: kaynak, includingPropertiesForKeys: nil)) ?? [])
            .filter { uzantilar.contains($0.pathExtension.lowercased()) }
        let adlar = Set(dosyalar.map { $0.lastPathComponent + ".pcm" })
        for u in (try? fm.contentsOfDirectory(at: hedef, includingPropertiesForKeys: nil)) ?? [] where !adlar.contains(u.lastPathComponent) {
            try? fm.removeItem(at: u)
        }
        for u in dosyalar {
            let h = hedef.appendingPathComponent(u.lastPathComponent + ".pcm")
            let kt = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let ht = (try? h.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            guard ht < kt, let o = MuzikOkuyucu(u) else { continue }
            let gecici = h.appendingPathExtension("yaziliyor")
            fm.createFile(atPath: gecici.path, contents: nil)
            guard let yaz = try? FileHandle(forWritingTo: gecici) else { continue }
            while true {
                let m = o.oku(Int(Ses.ornekHizi) * 5)
                if m.isEmpty { break }
                var v = m.map { Int16(max(-1, min(1, $0)) * 32767).littleEndian }
                yaz.write(Data(bytes: &v, count: v.count * 2))
            }
            try? yaz.close()
            try? fm.removeItem(at: h)
            try? fm.moveItem(at: gecici, to: h)
        }
    }

    /// Ekranda gösterilecek ad (".mp3.pcm" → "...mp3").
    static func ad(_ u: URL) -> String { u.deletingPathExtension().lastPathComponent }
}

/// Uzantı tarafı: ham müzik dosyasını (48 kHz, tek kanal, Int16) parça parça okur; çözücü gerekmez.
final class PcmOkuyucu {
    private let tutucu: FileHandle
    let toplamSaniye: Double

    init?(_ url: URL) {
        guard let t = try? FileHandle(forReadingFrom: url),
              let boy = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int, boy > 0 else { return nil }
        tutucu = t
        toplamSaniye = Double(boy / 2) / Ses.ornekHizi
    }

    func oku(_ n: Int) -> [Float] {
        guard let d = try? tutucu.read(upToCount: n * 2), !d.isEmpty else { return [] }
        return d.withUnsafeBytes { b in b.bindMemory(to: Int16.self).map { Float(Int16(littleEndian: $0)) / 32767 } }
    }
}

/// Bir müzik dosyasını parça parça 48 kHz tek kanala çevirerek okur (bütün dosya belleğe alınmaz).
final class MuzikOkuyucu {
    private let dosya: AVAudioFile
    private let donusturucu: AVAudioConverter
    private let hedef = AVAudioFormat(standardFormatWithSampleRate: Ses.ornekHizi, channels: 1)!
    private var bitti = false
    let toplamSaniye: Double

    init?(_ url: URL) {
        guard let f = try? AVAudioFile(forReading: url),
              let d = AVAudioConverter(from: f.processingFormat, to: hedef) else { return nil }
        dosya = f
        donusturucu = d
        toplamSaniye = Double(f.length) / f.processingFormat.sampleRate
    }

    /// En çok `n` örnek; dosya bitince boş dizi.
    func oku(_ n: Int) -> [Float] {
        guard !bitti, let cikti = AVAudioPCMBuffer(pcmFormat: hedef, frameCapacity: AVAudioFrameCount(n)) else { return [] }
        let kaynakKare = AVAudioFrameCount(Double(n) * dosya.processingFormat.sampleRate / Ses.ornekHizi) + 1
        var hata: NSError?
        let durum = donusturucu.convert(to: cikti, error: &hata) { _, d in
            guard let g = AVAudioPCMBuffer(pcmFormat: self.dosya.processingFormat, frameCapacity: kaynakKare),
                  (try? self.dosya.read(into: g, frameCount: kaynakKare)) != nil, g.frameLength > 0 else {
                d.pointee = .endOfStream
                return nil
            }
            d.pointee = .haveData
            return g
        }
        if durum == .endOfStream || durum == .error || cikti.frameLength == 0 { bitti = true }
        return Array(UnsafeBufferPointer(start: cikti.floatChannelData![0], count: Int(cikti.frameLength)))
    }
}

/// Uzantıdaki müzik durumu: ne kadar dinlendi, sıradaki parça, arka plan müziğinin konumu.
/// Uzantı süreci kapanırsa sıfırlanır; 30 dk istek gelmezse yeni oturum sayılır.
final class MuzikDurumu {
    static let ortak = MuzikDurumu()
    private let kilit = NSLock()
    private var dinlenen: Double = 0
    private var sonIstek = Date.distantPast
    private var sira = 0
    private var arkaPlan: PcmOkuyucu?
    private var arkaPlanSira = 0

    /// İstek başında: müzik arası zamanı geldiyse çalınacak parçayı verir ve sayacı sıfırlar.
    func araParcasi() -> PcmOkuyucu? {
        kilit.lock(); defer { kilit.unlock() }
        if Date().timeIntervalSince(sonIstek) > 1800 { dinlenen = 0 }
        sonIstek = Date()
        guard Ayar.muzikArasi, dinlenen >= Double(Ayar.muzikDakika) * 60 else { return nil }
        let l = Muzik.liste
        guard !l.isEmpty else { return nil }
        for _ in 0..<l.count {
            let u = l[sira % l.count]
            sira += 1
            if let o = PcmOkuyucu(u) { dinlenen = 0; return o }
        }
        return nil
    }

    func konusuldu(_ saniye: Double) {
        kilit.lock(); dinlenen += saniye; sonIstek = Date(); kilit.unlock()
    }

    /// Arka plan müziğini sese karıştırır (açıksa); parçalar sırayla döner.
    func karistir(_ ses: inout [Float]) {
        guard Ayar.arkaPlan, !ses.isEmpty else { return }
        kilit.lock(); defer { kilit.unlock() }
        let seviye = Float(Ayar.arkaPlanSeviye)
        var i = 0
        var deneme = 0
        while i < ses.count && deneme < 4 {
            if arkaPlan == nil {
                let l = Muzik.liste
                guard !l.isEmpty else { return }
                arkaPlan = PcmOkuyucu(l[arkaPlanSira % l.count])
                arkaPlanSira += 1
                if arkaPlan == nil { deneme += 1; continue }
            }
            let m = arkaPlan!.oku(ses.count - i)
            if m.isEmpty { arkaPlan = nil; deneme += 1; continue }
            for (k, v) in m.enumerated() { ses[i + k] += v * seviye }
            i += m.count
        }
    }
}
