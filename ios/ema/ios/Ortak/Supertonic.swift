import Foundation
import OnnxRuntimeBindings

// Supertonic-3 (Supertone Inc., model OpenRAIL-M, örnek kod MIT) — telefon motoru.
// Akış resmî Swift örneğinden (github.com/supertone-inc/supertonic, swift/Sources/Helper.swift) uyarlandı:
// metin → süre kestirimi → metin kodlama → N adımlı gürültü giderme → ses üretici.
// Modeller App Group › Modeller/supertonic-3 altında, ağırlıklar ayrı .bin dosyalarında; ön işleme kapalı
// açılınca ağırlıklar belleğe kopyalanmaz (Mac ölçümü: 375 MB → 102 MB), uzantının sınırına sığar.
final class Supertonic: Seslendirici {
    struct Yapi: Decodable {
        struct AE: Decodable { let sample_rate: Int; let base_chunk_size: Int }
        struct TTL: Decodable { let chunk_compress_factor: Int; let latent_dim: Int }
        let ae: AE
        let ttl: TTL
    }
    private struct StilVerisi: Decodable {
        struct Parca: Decodable { let data: [[[Float]]]; let dims: [Int] }
        let style_ttl: Parca
        let style_dp: Parca
    }

    static var klasor: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Ayar.grup)?
            .appendingPathComponent("Modeller/supertonic-3")
    }
    static var kurulu: Bool {
        guard let k = klasor else { return false }
        return FileManager.default.fileExists(atPath: k.appendingPathComponent("onnx/vocoder.bin").path)
    }

    let sozluk = Metin.sozluk
    let stil: String
    private let yapi: Yapi
    private let indeks: [Int64]
    private let env: ORTEnv
    private let dp, te, ve, vo: ORTSession
    private let stilTTL: ORTValue, stilDP: ORTValue
    private let kilit = NSLock()

    init(stil: String) throws {
        guard let k = Supertonic.klasor else { throw NSError(domain: "Ema", code: 2) }
        self.stil = stil
        let onnx = k.appendingPathComponent("onnx")
        yapi = try JSONDecoder().decode(Yapi.self, from: Data(contentsOf: onnx.appendingPathComponent("tts.json")))
        indeks = try JSONDecoder().decode([Int64].self, from: Data(contentsOf: onnx.appendingPathComponent("unicode_indexer.json")))
        let e = try ORTEnv(loggingLevel: .warning)
        env = e
        let s = try ORTSessionOptions()
        try s.setIntraOpNumThreads(2)
        try s.addConfigEntry(withKey: "session.disable_prepacking", value: "1")
        let ac = { (ad: String) throws -> ORTSession in
            try ORTSession(env: e, modelPath: onnx.appendingPathComponent(ad + ".onnx").path, sessionOptions: s)
        }
        dp = try ac("duration_predictor"); te = try ac("text_encoder")
        ve = try ac("vector_estimator"); vo = try ac("vocoder")
        let v = try JSONDecoder().decode(StilVerisi.self,
                                         from: Data(contentsOf: k.appendingPathComponent("voice_styles/\(stil).json")))
        stilTTL = try Supertonic.tensor(v.style_ttl.data.flatMap { $0.flatMap { $0 } }, v.style_ttl.dims)
        stilDP = try Supertonic.tensor(v.style_dp.data.flatMap { $0.flatMap { $0 } }, v.style_dp.dims)
    }

    /// Ema ile aynı metin hazırlığı (rakamlar, küçük harf, 10 sn'lik parçalar); kelime süreleri harf sayısına orantılı.
    func seslendirKelimeli(_ yazi: String, hiz: Double, devam: () -> Bool, teslim: ([Float], [Int]) -> Void) throws {
        var rng = Tohum(7)
        let adim = hiz > 1.4 ? 5 : 8  // hızlı dinlemede daha az adım: üretim yetişsin
        for (p, ara) in Metin.parcala(Metin.harfler(yazi, sozluk: sozluk), hiz: 1, ilkSinir: 70) {
            guard devam() else { return }
            var wav = Ornekleme.donustur(try uret(p, adim: adim, rng: &rng), kaynak: Double(yapi.ae.sample_rate), hedef: Ses.ornekHizi)
            // Seviye Ema'ya eşitlenir (tepe ≈0,6; Supertonic çıplak hâlde ≈0,3): sesler arasında geçişte zıplamasın.
            let tepe = wav.map(abs).max() ?? 0
            if tepe > 0.01 { let k = min(3, 0.6 / tepe); wav = wav.map { $0 * k } }
            if ara > 0 { wav += [Float](repeating: 0, count: Int(ara * Ses.ornekHizi)) }
            let kelimeler = p.split(separator: " ").map { max($0.count, 1) }
            let toplamHarf = kelimeler.reduce(0, +)
            var sureler = kelimeler.map { $0 * wav.count / max(toplamHarf, 1) }
            if !sureler.isEmpty { sureler[sureler.count - 1] += wav.count - sureler.reduce(0, +) }
            teslim(wav, sureler)
        }
    }

    // MARK: tek parça

    private func uret(_ metin: String, adim: Int, rng: inout Tohum) throws -> [Float] {
        let hazir = "<tr>" + Supertonic.hazirla(metin) + "</tr>"
        let kod = hazir.unicodeScalars.map { Int($0.value) < indeks.count ? indeks[Int($0.value)] : -1 }
        let L = kod.count
        let maske = [Float](repeating: 1, count: L)
        kilit.lock(); defer { kilit.unlock() }
        let ids = try Supertonic.tensor(kod, [1, L]), tm = try Supertonic.tensor(maske, [1, 1, L])

        let d = try dp.run(withInputs: ["text_ids": ids, "style_dp": stilDP, "text_mask": tm], outputNames: ["duration"], runOptions: nil)
        let sure: Float = try Supertonic.oku(d["duration"]!)[0]
        let emb = try te.run(withInputs: ["text_ids": ids, "style_ttl": stilTTL, "text_mask": tm],
                             outputNames: ["text_emb"], runOptions: nil)["text_emb"]!

        let sr = yapi.ae.sample_rate, parcaBoyu = yapi.ae.base_chunk_size * yapi.ttl.chunk_compress_factor
        let dalga = Int(sure * Float(sr))
        let T = (dalga + parcaBoyu - 1) / parcaBoyu
        let D = yapi.ttl.latent_dim * yapi.ttl.chunk_compress_factor
        var x = [Float](repeating: 0, count: D * T)
        for i in x.indices { x[i] = rng.normal() }
        let lm = try Supertonic.tensor([Float](repeating: 1, count: T), [1, 1, T])
        let toplam = try Supertonic.tensor([Float(adim)], [1])
        for a in 0..<adim {
            var girdi: [String: ORTValue] = ["text_emb": emb, "style_ttl": stilTTL, "latent_mask": lm,
                                             "text_mask": tm, "total_step": toplam]
            girdi["noisy_latent"] = try Supertonic.tensor(x, [1, D, T])
            girdi["current_step"] = try Supertonic.tensor([Float(a)], [1])
            let o = try ve.run(withInputs: girdi, outputNames: ["denoised_latent"], runOptions: nil)
            x = try Supertonic.oku(o["denoised_latent"]!)
        }
        let w = try vo.run(withInputs: ["latent": Supertonic.tensor(x, [1, D, T])], outputNames: ["wav_tts"], runOptions: nil)
        let ses: [Float] = try Supertonic.oku(w["wav_tts"]!)
        return Array(ses.prefix(dalga))
    }

    /// Resmî örnekteki metin temizliğinin Türkçe için gerekli kısmı (NFKD, tırnak/tire, sonda nokta).
    static func hazirla(_ girdi: String) -> String {
        var s = girdi.decomposedStringWithCompatibilityMapping
        for (a, b) in ["–": "-", "—": "-", "_": " ", "\u{201C}": "\"", "\u{201D}": "\"", "\u{2018}": "'", "\u{2019}": "'",
                       "[": " ", "]": " ", "|": " ", "/": " ", "#": " "] {
            s = s.replacingOccurrences(of: a, with: b)
        }
        for p in [",", ".", "!", "?", ";", ":", "'"] { s = s.replacingOccurrences(of: " " + p, with: p) }
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        if let son = s.last, !".!?;:,'\")]}…".contains(son) { s += "." }
        return s
    }

    private static func tensor<T>(_ dizi: [T], _ sekil: [Int]) throws -> ORTValue {
        let tur: ORTTensorElementDataType = T.self == Float.self ? .float : .int64
        let veri = dizi.withUnsafeBufferPointer { NSMutableData(bytes: $0.baseAddress, length: $0.count * MemoryLayout<T>.stride) }
        return try ORTValue(tensorData: veri, elementType: tur, shape: sekil.map { NSNumber(value: $0) })
    }

    private static func oku(_ d: ORTValue) throws -> [Float] {
        let v = try d.tensorData() as Data
        return v.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
