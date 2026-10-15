import Foundation
import OnnxRuntimeBindings

// Piper (rhasspy, VITS) Türkçe sesleri — dfki · fahrettin · fettah. Yalnız uzantıda (espeak-ng burada derleniyor).
// Metin → espeak-ng IPA (yan cümle işaretleri korunur) → [^ _ s1 _ s2 _ … $] simge kimlikleri → ONNX → 22 050 Hz.
// Python eşi /tmp/piper_ref.py ile sınandı (2026-10-09): Whisper hatası dfki %6,9 · fahrettin %5,5 · fettah %6,4.
// Modeller ve espeak-ng-data App Group › Modeller/piper altında; ağırlıklar ayrı .bin dosyasında, ön işleme kapalı.
final class Piper: Seslendirici {
    static var klasor: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Ayar.grup)?.appendingPathComponent("Modeller/piper")
    }
    static func kurulu(_ ad: String) -> Bool {
        guard let k = klasor else { return false }
        return FileManager.default.fileExists(atPath: k.appendingPathComponent("\(ad)/model.onnx").path)
            && FileManager.default.fileExists(atPath: k.appendingPathComponent("espeak-ng-data/tr_dict").path)
    }

    let sozluk = Metin.sozluk
    private let oran: Double
    private let kimlik: [Unicode.Scalar: Int64]
    private let env: ORTEnv
    private let oturum: ORTSession
    private static let espeakKilit = NSLock()
    private static var espeakHazir = false

    init(ad: String) throws {
        guard let k = Piper.klasor else { throw NSError(domain: "Ema", code: 3) }
        let d = k.appendingPathComponent(ad)
        struct Yapi: Decodable { struct A: Decodable { let sample_rate: Int }; let audio: A }
        oran = Double(try JSONDecoder().decode(Yapi.self, from: Data(contentsOf: d.appendingPathComponent("model.onnx.json"))).audio.sample_rate)
        var t: [Unicode.Scalar: Int64] = [:]
        for satir in try String(contentsOf: d.appendingPathComponent("tokens.txt"), encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false) {
            guard let b = satir.lastIndex(of: " "), let n = Int64(satir[satir.index(after: b)...]) else { continue }
            let sembol = satir[..<b]
            if let s = (sembol.isEmpty ? " " : String(sembol)).unicodeScalars.first { t[s] = n }
        }
        kimlik = t
        env = try ORTEnv(loggingLevel: .warning)
        let s = try ORTSessionOptions()
        try s.setIntraOpNumThreads(2)
        try s.addConfigEntry(withKey: "session.disable_prepacking", value: "1")
        oturum = try ORTSession(env: env, modelPath: d.appendingPathComponent("model.onnx").path, sessionOptions: s)
        try Piper.espeakBaslat(k)
    }

    private static func espeakBaslat(_ k: URL) throws {
        espeakKilit.lock(); defer { espeakKilit.unlock() }
        if espeakHazir { return }
        // espeak_Initialize, espeak-ng-data klasörünü içeren üst klasörü ister.
        let r = espeak_Initialize(AUDIO_OUTPUT_SYNCHRONOUS, 0, k.path, 0)
        guard r > 0, espeak_SetVoiceByName("tr") == EE_OK else { throw NSError(domain: "Ema", code: 4) }
        espeakHazir = true
    }

    /// Bir yan cümlenin IPA'sı (espeak her yan cümle için ayrı satır döndürür, aralarına boşluk konur).
    private static func ipa(_ metin: String) -> String {
        espeakKilit.lock(); defer { espeakKilit.unlock() }
        var parcalar: [String] = []
        metin.withCString { c in
            var p: UnsafeRawPointer? = UnsafeRawPointer(c)
            while let q = p, q.load(as: CChar.self) != 0 {
                guard let r = espeak_TextToPhonemes(&p, espeakCHARS_UTF8, 0x02 /* espeakPHONEMES_IPA */) else { break }
                parcalar.append(String(cString: r))
            }
        }
        return parcalar.joined(separator: " ")
    }

    private func kimlikler(_ parca: String) -> [Int64] {
        let bos = kimlik["_"] ?? 0
        var ids: [Int64] = [kimlik["^"] ?? 1, bos]
        let re = try! NSRegularExpression(pattern: "([^,;:.!?]+)([,;:.!?]*)")
        let ns = parca as NSString
        for m in re.matches(in: parca, range: NSRange(location: 0, length: ns.length)) {
            let bolum = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            guard !bolum.isEmpty else { continue }
            let isaret = m.range(at: 2).length > 0 ? String(ns.substring(with: m.range(at: 2)).prefix(1)) : ""
            for sk in (Piper.ipa(bolum) + isaret + " ").unicodeScalars {
                if let i = kimlik[sk] { ids += [i, bos] }
            }
        }
        return ids + [kimlik["$"] ?? 2]
    }

    func seslendirKelimeli(_ yazi: String, hiz: Double, devam: () -> Bool, teslim: ([Float], [Int]) -> Void) throws {
        for (p, ara) in Metin.parcala(Metin.harfler(yazi, sozluk: sozluk), hiz: 1, ilkSinir: 90) {
            guard devam() else { return }
            let ids = kimlikler(p)
            let o = try oturum.run(withInputs: [
                "input": try ORTValue(tensorData: NSMutableData(bytes: ids, length: ids.count * 8), elementType: .int64, shape: [1, NSNumber(value: ids.count)]),
                "input_lengths": try ORTValue(tensorData: NSMutableData(bytes: [Int64(ids.count)], length: 8), elementType: .int64, shape: [1]),
                "scales": try ORTValue(tensorData: NSMutableData(bytes: [Float(0.667), 1, 0.8], length: 12), elementType: .float, shape: [3]),
            ], outputNames: ["output"], runOptions: nil)
            let veri = try o["output"]!.tensorData() as Data
            var wav = Ornekleme.donustur(veri.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }, kaynak: oran, hedef: Ses.ornekHizi)
            let tepe = wav.map(abs).max() ?? 0
            if tepe > 0.01 { let k = min(3, 0.6 / tepe); wav = wav.map { $0 * k } }
            if ara > 0 { wav += [Float](repeating: 0, count: Int(ara * Ses.ornekHizi)) }
            let kelimeler = p.split(separator: " ").map { max($0.count, 1) }
            let toplam = kelimeler.reduce(0, +)
            var sureler = kelimeler.map { $0 * wav.count / max(toplam, 1) }
            if !sureler.isEmpty { sureler[sureler.count - 1] += wav.count - sureler.reduce(0, +) }
            teslim(wav, sureler)
        }
    }
}
