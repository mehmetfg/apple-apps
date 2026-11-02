// Supertonic-3 (Supertone Inc., model OpenRAIL-M, sample code MIT): text → duration → text encoding → N denoising
// steps → vocoder. Adapted from the official Swift sample (github.com/supertone-inc/supertonic, Helper.swift) via
// Ema's Supertonic.swift. Weights live in separate .bin files with prepacking off, so they are not copied into
// memory (measured on the Mac: 375 MB → 102 MB). A style may be a weighted blend: "M4:0.5,M5:0.5".
import Foundation
import OnnxRuntimeBindings

final class SupertonicEngine: NeuralEngine {
    struct ModelConfig: Decodable {
        struct AE: Decodable { let sample_rate: Int; let base_chunk_size: Int }
        struct TTL: Decodable { let chunk_compress_factor: Int; let latent_dim: Int }
        let ae: AE
        let ttl: TTL
    }
    private struct StyleData: Decodable {
        struct Part: Decodable { let data: [[[Float]]]; let dims: [Int] }
        let style_ttl: Part
        let style_dp: Part
    }

    /// Models ship inside the app bundle (the build flattens them into its root).
    static var folder: URL? { Bundle.main.resourceURL }
    static var isInstalled: Bool {
        guard let f = folder else { return false }
        return FileManager.default.fileExists(atPath: f.appendingPathComponent("vocoder.bin").path)
    }

    let alphabet = TextPrep.alphabet
    let style: String
    private let config: ModelConfig
    private let indexer: [Int64]
    private let env: ORTEnv
    private let durationSession, encoderSession, estimatorSession, vocoderSession: ORTSession
    private let styleTTL: ORTValue, styleDP: ORTValue
    private let lock = NSLock()

    init(style: String) throws {
        guard let f = Self.folder else { throw NSError(domain: "SupertonicEngine", code: 2) }
        self.style = style
        config = try JSONDecoder().decode(ModelConfig.self, from: Data(contentsOf: f.appendingPathComponent("tts.json")))
        indexer = try JSONDecoder().decode([Int64].self, from: Data(contentsOf: f.appendingPathComponent("unicode_indexer.json")))
        let e = try ORTEnv(loggingLevel: .warning)
        env = e
        let options = try ORTSessionOptions()
        try options.setIntraOpNumThreads(4)
        try options.addConfigEntry(withKey: "session.disable_prepacking", value: "1")
        let open = { (name: String) throws -> ORTSession in
            try ORTSession(env: e, modelPath: f.appendingPathComponent(name + ".onnx").path, sessionOptions: options)
        }
        durationSession = try open("duration_predictor"); encoderSession = try open("text_encoder")
        estimatorSession = try open("vector_estimator"); vocoderSession = try open("vocoder")
        var ttl: [Float] = [], dp: [Float] = []
        var ttlDims: [Int] = [], dpDims: [Int] = []
        var totalWeight: Float = 0
        for part in style.split(separator: ",") {
            let name = part.split(separator: ":").first.map(String.init) ?? String(part)
            let w = part.split(separator: ":").dropFirst().first.flatMap { Float($0) } ?? 1
            let v = try JSONDecoder().decode(StyleData.self, from: Data(contentsOf: f.appendingPathComponent("st-\(name).json")))
            let a = v.style_ttl.data.flatMap { $0.flatMap { $0 } }, b = v.style_dp.data.flatMap { $0.flatMap { $0 } }
            if ttl.isEmpty { ttl = [Float](repeating: 0, count: a.count); dp = [Float](repeating: 0, count: b.count) }
            for i in a.indices { ttl[i] += w * a[i] }
            for i in b.indices { dp[i] += w * b[i] }
            ttlDims = v.style_ttl.dims; dpDims = v.style_dp.dims
            totalWeight += w
        }
        styleTTL = try Self.tensor(ttl.map { $0 / totalWeight }, ttlDims)
        styleDP = try Self.tensor(dp.map { $0 / totalWeight }, dpDims)
    }

    /// Same text preparation as Ema (numbers, lower case, ~10 s chunks); word durations proportional to letters.
    /// Above 1.4× fewer denoising steps so generation keeps up with playback.
    func synthesize(_ text: String, speed: Double, keepGoing: () -> Bool, deliver: ([Float], [Int]) -> Void) throws {
        var rng = SeededNoise(7)
        // measured on iPhone 13 Pro Max: 8 steps ≈ 2× real time; fast listening needs fewer
        let steps = speed > 1.4 ? 4 : 8          // 3 steps measured 62 % word error at 360 wpm; 4 steps 19 %, 8 steps 15 %
        for (chunk, pause) in TextPrep.split(TextPrep.letters(text, alphabet: alphabet), speed: 1, firstLimit: 70) {
            guard keepGoing() else { return }
            var wav = Resampler.convert(try generate(chunk, steps: steps, rng: &rng), from: Double(config.ae.sample_rate), to: NeuralAudio.sampleRate)
            // level matched to Ema (peak ≈ 0.6; raw Supertonic ≈ 0.3) so switching voices does not jump
            let peak = wav.map(abs).max() ?? 0
            if peak > 0.01 { let k = min(3, 0.6 / peak); wav = wav.map { $0 * k } }
            if pause > 0 { wav += [Float](repeating: 0, count: Int(pause * NeuralAudio.sampleRate)) }
            let words = chunk.split(separator: " ").map { max($0.count, 1) }
            let letters = words.reduce(0, +)
            var durations = words.map { $0 * wav.count / max(letters, 1) }
            if !durations.isEmpty { durations[durations.count - 1] += wav.count - durations.reduce(0, +) }
            deliver(wav, durations)
        }
    }

    private func generate(_ text: String, steps: Int, rng: inout SeededNoise) throws -> [Float] {
        let prepared = "<tr>" + Self.prepare(text) + "</tr>"
        let codes = prepared.unicodeScalars.map { Int($0.value) < indexer.count ? indexer[Int($0.value)] : -1 }
        let L = codes.count
        let mask = [Float](repeating: 1, count: L)
        lock.lock(); defer { lock.unlock() }
        let ids = try Self.tensor(codes, [1, L]), textMask = try Self.tensor(mask, [1, 1, L])

        let d = try durationSession.run(withInputs: ["text_ids": ids, "style_dp": styleDP, "text_mask": textMask],
                                        outputNames: ["duration"], runOptions: nil)
        let duration: Float = try Self.read(d["duration"]!)[0]
        let embedding = try encoderSession.run(withInputs: ["text_ids": ids, "style_ttl": styleTTL, "text_mask": textMask],
                                               outputNames: ["text_emb"], runOptions: nil)["text_emb"]!

        let sr = config.ae.sample_rate, chunkSize = config.ae.base_chunk_size * config.ttl.chunk_compress_factor
        let waveLength = Int(duration * Float(sr))
        let T = (waveLength + chunkSize - 1) / chunkSize
        let D = config.ttl.latent_dim * config.ttl.chunk_compress_factor
        var x = [Float](repeating: 0, count: D * T)
        let temperature = NeuralAudio.temperature
        for i in x.indices { x[i] = rng.normal() * temperature }
        let latentMask = try Self.tensor([Float](repeating: 1, count: T), [1, 1, T])
        let total = try Self.tensor([Float(steps)], [1])
        for s in 0..<steps {
            var inputs: [String: ORTValue] = ["text_emb": embedding, "style_ttl": styleTTL, "latent_mask": latentMask,
                                              "text_mask": textMask, "total_step": total]
            inputs["noisy_latent"] = try Self.tensor(x, [1, D, T])
            inputs["current_step"] = try Self.tensor([Float(s)], [1])
            let o = try estimatorSession.run(withInputs: inputs, outputNames: ["denoised_latent"], runOptions: nil)
            x = try Self.read(o["denoised_latent"]!)
        }
        let w = try vocoderSession.run(withInputs: ["latent": Self.tensor(x, [1, D, T])], outputNames: ["wav_tts"], runOptions: nil)
        let audio: [Float] = try Self.read(w["wav_tts"]!)
        return Array(audio.prefix(waveLength))
    }

    /// The official sample's text clean-up, the part Turkish needs (NFKD, quotes and dashes, final full stop).
    static func prepare(_ input: String) -> String {
        var s = input.decomposedStringWithCompatibilityMapping
        for (a, b) in ["–": "-", "—": "-", "_": " ", "\u{201C}": "\"", "\u{201D}": "\"", "\u{2018}": "'", "\u{2019}": "'",
                       "[": " ", "]": " ", "|": " ", "/": " ", "#": " "] {
            s = s.replacingOccurrences(of: a, with: b)
        }
        for p in [",", ".", "!", "?", ";", ":", "'"] { s = s.replacingOccurrences(of: " " + p, with: p) }
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        if let last = s.last, !".!?;:,'\")]}…".contains(last) { s += "." }
        return s
    }

    private static func tensor<T>(_ array: [T], _ shape: [Int]) throws -> ORTValue {
        let type: ORTTensorElementDataType = T.self == Float.self ? .float : .int64
        let data = array.withUnsafeBufferPointer { NSMutableData(bytes: $0.baseAddress, length: $0.count * MemoryLayout<T>.stride) }
        return try ORTValue(tensorData: data, elementType: type, shape: shape.map { NSNumber(value: $0) })
    }

    private static func read(_ value: ORTValue) throws -> [Float] {
        let v = try value.tensorData() as Data
        return v.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
