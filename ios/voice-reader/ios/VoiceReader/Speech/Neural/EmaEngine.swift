// Ema Lightning on the phone: letters → duration plan → 4-step latent generation → 48 kHz audio.
// Ported from Ema's Motor.swift (same graph, same arithmetic; Python reference: _araçlar/ema/model/referans.py).
import Foundation
import OnnxRuntimeBindings

final class EmaEngine: NeuralEngine {
    struct Config: Decodable {
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

    let config: Config
    let alphabet: Set<Unicode.Scalar>
    private let index: [Unicode.Scalar: Int64]
    private let env: ORTEnv
    private let textSession: ORTSession
    private let acousticSession: ORTSession
    private let decoderSession: ORTSession
    private let lock = NSLock()

    init() throws {
        func path(_ name: String, _ ext: String) throws -> String {
            guard let p = Bundle.main.path(forResource: name, ofType: ext) else {
                throw NSError(domain: "EmaEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(name).\(ext) missing"])
            }
            return p
        }
        config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: URL(fileURLWithPath: path("ema", "json"))))
        var table: [Unicode.Scalar: Int64] = [:]
        for (i, c) in config.vocab.enumerated() where c.unicodeScalars.count == 1 {
            table[c.unicodeScalars.first!] = Int64(i)
        }
        index = table
        alphabet = Set(table.keys)
        env = try ORTEnv(loggingLevel: .warning)
        let options = try ORTSessionOptions()
        try options.setIntraOpNumThreads(4)
        try options.setGraphOptimizationLevel(.all)
        textSession = try ORTSession(env: env, modelPath: path("ema-text", "onnx"), sessionOptions: options)
        acousticSession = try ORTSession(env: env, modelPath: path("ema-acoustic", "onnx"), sessionOptions: options)
        decoderSession = try ORTSession(env: env, modelPath: path("ema-decoder", "onnx"), sessionOptions: options)
    }

    /// Speaks `text` chunk by chunk; each chunk's samples (followed by its pause) and the sample count of every
    /// model word go to `deliver` (word counts sum to the chunk length; the pause is added to the last word).
    func synthesize(_ text: String, speed: Double, keepGoing: () -> Bool, deliver: ([Float], [Int]) -> Void) throws {
        var rng = SeededNoise(0)
        for (chunk, pause) in TextPrep.split(TextPrep.letters(text, alphabet: alphabet), speed: speed, firstLimit: 90) {
            guard keepGoing() else { return }
            let latent = try plan(chunk, speed: speed, rng: &rng)
            guard keepGoing() else { return }
            var wav = try decode(latent.data, frames: latent.frames)
            if pause > 0 { wav += [Float](repeating: 0, count: Int((pause * Double(config.rate)).rounded())) }
            var words = latent.wordFrames.map { $0 * config.hop }
            if !words.isEmpty { words[words.count - 1] += wav.count - words.reduce(0, +) }
            deliver(wav, words)
        }
    }

    // MARK: stages

    private func plan(_ chunk: String, speed: Double, rng: inout SeededNoise) throws -> (data: [Float], frames: Int, wordFrames: [Int]) {
        let letters = Array(chunk.unicodeScalars)
        let L = letters.count
        let ids = letters.map { index[$0] ?? 1 }
        var charWord = [Int64](repeating: 0, count: L), wordStart = [Int64](repeating: 0, count: L)
        var w: Int64 = -1, start: Int64 = 0
        for i in 0..<L {
            if letters[i] != " " && (i == 0 || letters[i - 1] == " ") { w += 1; start = Int64(i) }
            charWord[i] = max(w, 0)
            wordStart[i] = start
        }
        lock.lock(); defer { lock.unlock() }

        let t = try textSession.run(withInputs: ["ids": tensor(ids, [1, L])], outputNames: ["h", "dur"], runOptions: nil)
        let h: [Float] = try read(t["h"]!)
        var dur: [Float] = try read(t["dur"]!)
        if speed != 1 { dur = dur.map { $0 / Float(speed) } }

        let wordCount = Int(charWord[L - 1]) + 1
        var totals = [Double](repeating: 0, count: wordCount)
        for i in 0..<L { totals[Int(charWord[i])] += Double(dur[i]) }
        let frames = totals.map { Int(min(max($0.rounded(.toNearestOrEven), 1), Double(config.max_word_frames))) }
        let T = min(frames.reduce(0, +), config.max_frames)
        var frameWord = [Int64](), framePos = [Float]()
        frameWord.reserveCapacity(T); framePos.reserveCapacity(T)
        outer: for (wi, n) in frames.enumerated() {
            for k in 0..<n {
                if frameWord.count == T { break outer }
                frameWord.append(Int64(wi))
                framePos.append(Float(Double(k) / Double(n)))
            }
        }
        let steps = config.times.count, D = config.latent_dim
        var noise = [Float](repeating: 0, count: steps * T * D)
        let temperature = NeuralAudio.temperature
        for i in noise.indices { noise[i] = rng.normal() * temperature }

        let a = try acousticSession.run(withInputs: [
            "h": tensor(h, [1, L, h.count / L]), "dur": tensor(dur, [1, L]),
            "cw": tensor(charWord, [1, L]), "wstart": tensor(wordStart, [1, L]),
            "fw": tensor(frameWord, [1, T]), "fp": tensor(framePos, [1, T]),
            "noise": tensor(noise, [1, steps, T, D]),
        ], outputNames: ["lat"], runOptions: nil)
        var remaining = T                                   // when the frame cap cut the plan, cut word frames too
        let wordFrames = frames.map { n -> Int in let k = min(n, remaining); remaining -= k; return k }
        return (try read(a["lat"]!), T, wordFrames)
    }

    /// Decodes latents in 4-second windows with 8 frames of context each side; the joined result equals one pass.
    private func decode(_ latent: [Float], frames T: Int) throws -> [Float] {
        let D = config.latent_dim, hop = config.hop, C = config.context
        var output = [Float]()
        output.reserveCapacity(T * hop)
        var s = 0
        lock.lock(); defer { lock.unlock() }
        while s < T {
            let e = min(T, s + config.window)
            let a = max(0, s - C), b = min(T, e + C)
            let z = Array(latent[(a * D)..<(b * D)])
            let o = try decoderSession.run(withInputs: ["z": tensor(z, [1, b - a, D])], outputNames: ["wav"], runOptions: nil)
            let wav: [Float] = try read(o["wav"]!)
            output += wav[((s - a) * hop)..<min(wav.count, (e - a) * hop)]
            s = e
        }
        return output
    }

    // MARK: tensors

    private func tensor<T>(_ array: [T], _ shape: [Int]) throws -> ORTValue {
        let type: ORTTensorElementDataType = T.self == Float.self ? .float : .int64
        let data = array.withUnsafeBufferPointer { NSMutableData(bytes: $0.baseAddress, length: $0.count * MemoryLayout<T>.stride) }
        return try ORTValue(tensorData: data, elementType: type, shape: shape.map { NSNumber(value: $0) })
    }

    private func read(_ value: ORTValue) throws -> [Float] {
        let d = try value.tensorData() as Data
        return d.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}

/// Repeatable normal noise (SplitMix64 + Box–Muller).
struct SeededNoise {
    private var state: UInt64
    private var spare: Float?
    init(_ seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    private mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func normal() -> Float {
        if let s = spare { spare = nil; return s }
        let u1 = max(Double(next() >> 11) / Double(1 << 53), 1e-12)
        let u2 = Double(next() >> 11) / Double(1 << 53)
        let r = (-2 * log(u1)).squareRoot()
        spare = Float(r * sin(2 * .pi * u2))
        return Float(r * cos(2 * .pi * u2))
    }
}
