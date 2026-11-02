// Shared pieces for the neural engines.
import AVFoundation

/// A neural engine: text → 48 kHz mono samples, plus the sample count of every model word (for the cursor).
protocol NeuralEngine: AnyObject {
    var alphabet: Set<Unicode.Scalar> { get }
    func synthesize(_ text: String, speed: Double, keepGoing: () -> Bool, deliver: ([Float], [Int]) -> Void) throws
}

enum NeuralAudio {
    static let sampleRate: Double = 48_000

    /// Size of the starting noise the flow models (Ema, Supertonic) shape into speech: 1 = as trained; smaller makes
    /// the model choose a more average, steadier melody instead of sampling a lively one. Set per render on the
    /// render queue (ProfileRenderer), read by the engines on the same queue.
    nonisolated(unsafe) static var temperature: Float = 1
}

extension TextPrep {
    /// The models' letter table (ema.json), read once without opening an engine.
    static let alphabet: Set<Unicode.Scalar> = {
        struct Table: Decodable { let vocab: [String] }
        guard let u = Bundle.main.url(forResource: "ema", withExtension: "json"),
              let d = try? Data(contentsOf: u), let t = try? JSONDecoder().decode(Table.self, from: d) else { return [] }
        return Set(t.vocab.compactMap { $0.unicodeScalars.count == 1 ? $0.unicodeScalars.first : nil })
    }()
}

/// Sample-rate conversion at the highest quality (Supertonic 44.1 kHz and Apple 22 kHz → 48 kHz).
enum Resampler {
    static func convert(_ x: [Float], from source: Double, to target: Double) -> [Float] {
        guard source != target, !x.isEmpty,
              let a = AVAudioFormat(standardFormatWithSampleRate: source, channels: 1),
              let b = AVAudioFormat(standardFormatWithSampleRate: target, channels: 1),
              let converter = AVAudioConverter(from: a, to: b),
              let input = AVAudioPCMBuffer(pcmFormat: a, frameCapacity: AVAudioFrameCount(x.count)) else { return x }
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        input.frameLength = input.frameCapacity
        x.withUnsafeBufferPointer { input.floatChannelData![0].update(from: $0.baseAddress!, count: x.count) }
        let capacity = AVAudioFrameCount(Double(x.count) * target / source) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: b, frameCapacity: capacity) else { return x }
        var given = false
        _ = converter.convert(to: output, error: nil) { _, status in
            if given { status.pointee = .endOfStream; return nil }
            given = true
            status.pointee = .haveData
            return input
        }
        return Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
    }
}
