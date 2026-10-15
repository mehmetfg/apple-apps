import Foundation
import OnnxRuntimeBindings

// EMA Lightning'in telefon motoru: harf dizisi → süre planı → 4 adımlı gizil üretim → 48 kHz ses.
// Python eşi: _araçlar/ema/model/referans.py (Motor). Model dosyaları Ortak/Model/ altında.
final class Motor {
    struct Ayar: Decodable {
        let vocab: [String]
        let times: [Double]
        let latent_dim: Int
        let rate: Int
        let hop: Int
        let window: Int
        let context: Int
        let max_word_frames: Int
        let max_frames: Int
    }

    static let ortak: Motor? = try? Motor()

    let ayar: Ayar
    let sozluk: Set<Unicode.Scalar>
    private let stoi: [Unicode.Scalar: Int64]
    private let env: ORTEnv
    private let metin: ORTSession
    private let ses: ORTSession
    private let cozucu: ORTSession
    private let kilit = NSLock()  // ORT oturumları tek iş parçacığından sürülsün

    init() throws {
        let paket = Bundle(for: Motor.self)
        func yol(_ ad: String, _ uzanti: String) throws -> String {
            guard let p = paket.path(forResource: ad, ofType: uzanti) else {
                throw NSError(domain: "Ema", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(ad).\(uzanti) yok"])
            }
            return p
        }
        ayar = try JSONDecoder().decode(Ayar.self, from: Data(contentsOf: URL(fileURLWithPath: yol("ema", "json"))))
        var t: [Unicode.Scalar: Int64] = [:]
        for (i, c) in ayar.vocab.enumerated() where c.unicodeScalars.count == 1 {
            t[c.unicodeScalars.first!] = Int64(i)
        }
        stoi = t
        sozluk = Set(t.keys)
        env = try ORTEnv(loggingLevel: .warning)
        let secenek = try ORTSessionOptions()
        try secenek.setIntraOpNumThreads(2)
        try secenek.setGraphOptimizationLevel(.all)
        metin = try ORTSession(env: env, modelPath: yol("metin", "onnx"), sessionOptions: secenek)
        ses = try ORTSession(env: env, modelPath: yol("ses", "onnx"), sessionOptions: secenek)
        cozucu = try ORTSession(env: env, modelPath: yol("cozucu", "onnx"), sessionOptions: secenek)
    }

    /// Metni parça parça seslendirir; her parçanın sesi (ve ardından sessizliği) hazır olunca `teslim` çağrılır.
    /// `devam` false dönerse iş bırakılır.
    func seslendir(_ yazi: String, hiz: Double = 1.0, tohum: UInt64 = 0,
                   devam: () -> Bool = { true }, teslim: ([Float]) -> Void) throws {
        try seslendirKelimeli(yazi, hiz: hiz, tohum: tohum, devam: devam) { ses, _ in teslim(ses) }
    }

    /// Aynısı, ek olarak parçadaki her model kelimesinin örnek sayısını verir (toplamı ses uzunluğuna eşit;
    /// parça sonundaki sessizlik son kelimeye yazılır). İmleç takibi bununla yapılır.
    func seslendirKelimeli(_ yazi: String, hiz: Double = 1.0, tohum: UInt64 = 0,
                           devam: () -> Bool = { true }, teslim: ([Float], [Int]) -> Void) throws {
        var rng = Tohum(tohum)
        for (p, ara) in Metin.parcala(Metin.harfler(yazi, sozluk: sozluk), hiz: hiz, ilkSinir: 90) {
            guard devam() else { return }
            let lat = try parca(p, hiz: hiz, rng: &rng)
            guard devam() else { return }
            var wav = try coz(lat.veri, kare: lat.kare)
            if ara > 0 { wav += [Float](repeating: 0, count: Int((ara * Double(ayar.rate)).rounded())) }
            var kelime = lat.kelimeKare.map { $0 * ayar.hop }
            if !kelime.isEmpty { kelime[kelime.count - 1] += wav.count - kelime.reduce(0, +) }
            teslim(wav, kelime)
        }
    }

    // MARK: aşamalar

    private func parca(_ p: String, hiz: Double, rng: inout Tohum) throws -> (veri: [Float], kare: Int, kelimeKare: [Int]) {
        let harfler = Array(p.unicodeScalars)
        let L = harfler.count
        let ids = harfler.map { stoi[$0] ?? 1 }
        var cw = [Int64](repeating: 0, count: L), wstart = [Int64](repeating: 0, count: L)
        var w: Int64 = -1, bas: Int64 = 0
        for i in 0..<L {
            if harfler[i] != " " && (i == 0 || harfler[i - 1] == " ") { w += 1; bas = Int64(i) }
            cw[i] = max(w, 0)
            wstart[i] = bas
        }
        kilit.lock(); defer { kilit.unlock() }

        let m = try metin.run(withInputs: ["ids": tensor(ids, [1, L])], outputNames: ["h", "dur"], runOptions: nil)
        let h: [Float] = try oku(m["h"]!)
        var dur: [Float] = try oku(m["dur"]!)
        if hiz != 1 { dur = dur.map { $0 / Float(hiz) } }

        let nw = Int(cw[L - 1]) + 1
        var toplam = [Double](repeating: 0, count: nw)
        for i in 0..<L { toplam[Int(cw[i])] += Double(dur[i]) }
        let say = toplam.map { Int(min(max($0.rounded(.toNearestOrEven), 1), Double(ayar.max_word_frames))) }
        let T = min(say.reduce(0, +), ayar.max_frames)
        var fw = [Int64](), fp = [Float]()
        fw.reserveCapacity(T); fp.reserveCapacity(T)
        outer: for (wi, n) in say.enumerated() {
            for k in 0..<n {
                if fw.count == T { break outer }
                fw.append(Int64(wi))
                fp.append(Float(Double(k) / Double(n)))
            }
        }
        let adim = ayar.times.count, D = ayar.latent_dim
        var gurultu = [Float](repeating: 0, count: adim * T * D)
        for i in gurultu.indices { gurultu[i] = rng.normal() }

        let s = try ses.run(withInputs: [
            "h": tensor(h, [1, L, h.count / L]), "dur": tensor(dur, [1, L]),
            "cw": tensor(cw, [1, L]), "wstart": tensor(wstart, [1, L]),
            "fw": tensor(fw, [1, T]), "fp": tensor(fp, [1, T]),
            "noise": tensor(gurultu, [1, adim, T, D]),
        ], outputNames: ["lat"], runOptions: nil)
        // Kare sınırı kestiyse kelime kare sayıları da kesilir.
        var kalan = T
        let kelimeKare = say.map { n -> Int in let k = min(n, kalan); kalan -= k; return k }
        return (try oku(s["lat"]!), T, kelimeKare)
    }

    /// Gizilleri 4 saniyelik pencerelerle (iki yanda 8 kare bağlamla) çözer; birleşik ses tek seferlik çözümle aynıdır.
    private func coz(_ lat: [Float], kare T: Int) throws -> [Float] {
        let D = ayar.latent_dim, hop = ayar.hop, C = ayar.context
        var cikis = [Float]()
        cikis.reserveCapacity(T * hop)
        var s = 0
        kilit.lock(); defer { kilit.unlock() }
        while s < T {
            let e = min(T, s + ayar.window)
            let a = max(0, s - C), b = min(T, e + C)
            let z = Array(lat[(a * D)..<(b * D)])
            let o = try cozucu.run(withInputs: ["z": tensor(z, [1, b - a, D])], outputNames: ["wav"], runOptions: nil)
            let wav: [Float] = try oku(o["wav"]!)
            cikis += wav[((s - a) * hop)..<min(wav.count, (e - a) * hop)]
            s = e
        }
        return cikis
    }

    // MARK: tensör yardımcıları

    private func tensor<T>(_ dizi: [T], _ sekil: [Int]) throws -> ORTValue {
        let tur: ORTTensorElementDataType = T.self == Float.self ? .float : .int64
        let veri = dizi.withUnsafeBufferPointer { NSMutableData(bytes: $0.baseAddress, length: $0.count * MemoryLayout<T>.stride) }
        return try ORTValue(tensorData: veri, elementType: tur, shape: sekil.map { NSNumber(value: $0) })
    }

    private func oku(_ deger: ORTValue) throws -> [Float] {
        let d = try deger.tensorData() as Data
        return d.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}

/// Tekrarlanabilir normal dağılımlı gürültü (SplitMix64 + Box–Muller).
struct Tohum {
    private var durum: UInt64
    private var yedek: Float?
    init(_ t: UInt64) { durum = t &+ 0x9E37_79B9_7F4A_7C15 }

    private mutating func sonraki() -> UInt64 {
        durum &+= 0x9E37_79B9_7F4A_7C15
        var z = durum
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func normal() -> Float {
        if let y = yedek { yedek = nil; return y }
        let u1 = max(Double(sonraki() >> 11) / Double(1 << 53), 1e-12)
        let u2 = Double(sonraki() >> 11) / Double(1 << 53)
        let r = (-2 * log(u1)).squareRoot()
        yedek = Float(r * sin(2 * .pi * u2))
        return Float(r * cos(2 * .pi * u2))
    }
}
