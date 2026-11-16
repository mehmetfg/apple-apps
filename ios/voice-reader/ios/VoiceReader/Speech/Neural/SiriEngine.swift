// Siri's own Turkish voices (Elif, Kaan) inside Wise Path: Apple's neural engine run in this process.
//
// Found 2026-11-11. Siri's voices are closed to apps two ways: `AVSpeechSynthesisVoice` does not list them, and the
// daemon that speaks for Siri (sirittsd) refuses a sandboxed app ("Couldn't communicate with a helper application",
// tried on iOS 27.0.1). But the engine that daemon uses lives in a framework every process can load
// (SiriTTSService), and it takes the voice as a folder path. With the voice folders shipped inside the app
// (Models/SiriVoices.bundle, copied from this Mac's own Siri assets by studio/siri/install-voices.sh) the same
// engine speaks here, offline: FastSpeech2 → WaveRNN, 48 kHz. Measured on the iPhone 13 Pro Max: 20.9 s of speech in
// 2.6 s (7.8× real time), first audio after 0.03 s, word times included.
//
// Not public API (personal app; it never goes to the App Store). Everything is looked up by name at run time: if a
// later iOS renames or removes any of it, `SiriEngine.isInstalled` turns false, the voices are greyed out in the
// list and reading falls to the next voice. Nothing else breaks.
//
// Speed. The engine has its own rate (the pitch and the sound of the voice stay). How much of a high speed the model
// takes and how much WSOLA takes afterwards was measured with Whisper, per voice (`Voice.modelShare`, README entry of
// 2026-11-11). The model's share also makes rendering cheaper: on the iPhone a sentence costs 1.15 s at the voice's
// own pace, 0.78 s at 1.5× and 0.66 s at 2× (the steps after the engine take under 0.04 s in all).
import Foundation
import ObjectiveC

final class SiriEngine {
    /// The two Turkish Siri voices and how fast each speaks by itself, as a multiple of the app's 1× (120 words a
    /// minute, 14.0 characters a second): Elif reads 15.7 characters a second, Kaan 16.3 (Mac, 889 characters).
    enum Voice: String, CaseIterable, Sendable {
        case elif, kaan
        var pace: Double { self == .elif ? 1.12 : 1.165 }

        /// The most the model itself is asked to speed up; the rest of a higher speed is WSOLA's. Whisper, 889
        /// characters at 330 words a minute, words heard at full speed: Elif 84 % with 1.5, 97 % with 2; Kaan 90 %
        /// with 1.5, 68 % with 2. Slowed back to 200 words a minute both stay at 97–99 % for every share from 1 to 2.5
        /// (at 430 too), so the full-speed score decides.
        var modelShare: Double { self == .elif ? 2 : 1.5 }
    }

    /// The engine's rate and the WSOLA tempo after it for a playback speed (a multiple of the app's 1×).
    static func split(speed: Double, voice: Voice) -> (rate: Double, tempo: Double) {
        let total = max(speed, 0.3) / voice.pace              // against the voice's own pace
        let rate = min(max(total, 0.5), max(1, voice.modelShare))
        return (rate, max(1, total / rate))
    }

    // MARK: files

    private static let framework = "/System/Library/PrivateFrameworks/SiriTTSService.framework/SiriTTSService"

    /// The folder that holds `elif/`, `kaan/` and `resource/`: shipped in the app, or put in Application Support
    /// (`WP_SIRI_VOICES` names it for the Mac tools that compile this file).
    static let root: URL? = {
        let fm = FileManager.default
        var places: [URL] = []
        if let e = ProcessInfo.processInfo.environment["WP_SIRI_VOICES"] { places.append(URL(fileURLWithPath: e)) }
        if let b = Bundle.main.url(forResource: "SiriVoices", withExtension: "bundle") { places.append(b) }
        if let s = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first { places.append(s.appendingPathComponent("SiriVoices")) }
        return places.first { fm.fileExists(atPath: $0.appendingPathComponent("resource").path) }
    }()

    private static let engineClass: NSObject.Type? = {
        guard dlopen(framework, RTLD_NOW) != nil,
              let c = NSClassFromString("SiriTTSSynthesisEngine") as? NSObject.Type,
              c.instancesRespond(to: NSSelectorFromString("initWithVoicePath:resourcePath:error:")),
              c.instancesRespond(to: NSSelectorFromString("synthesize:error:")),
              NSClassFromString("SiriTTSSynthesisEngineRequest") != nil else { return nil }
        return c
    }()

    static func isInstalled(_ voice: Voice) -> Bool {
        guard engineClass != nil, let root else { return false }
        return FileManager.default.fileExists(atPath: root.appendingPathComponent(voice.rawValue).appendingPathComponent("gryphon.cfg").path)
    }

    // MARK: engine

    private let engine: NSObject
    private let synthesizeIMP: IMP
    private let stopSelector = NSSelectorFromString("stopSynthesis")
    private var serial = 0

    init?(voice: Voice) {
        guard Self.isInstalled(voice), let cls = Self.engineClass, let root = Self.root else { return nil }
        let initSel = NSSelectorFromString("initWithVoicePath:resourcePath:error:")
        let synthSel = NSSelectorFromString("synthesize:error:")
        guard let initIMP = class_getMethodImplementation(cls, initSel),
              let synthIMP = class_getMethodImplementation(cls, synthSel),
              let blank = (cls as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() else { return nil }
        typealias Init = @convention(c) (AnyObject, Selector, NSString, NSString, AutoreleasingUnsafeMutablePointer<NSError?>?) -> Unmanaged<AnyObject>?
        var error: NSError?
        let made = unsafeBitCast(initIMP, to: Init.self)(blank, initSel,
                                                         root.appendingPathComponent(voice.rawValue).path as NSString,
                                                         root.appendingPathComponent("resource").path as NSString, &error)
        // `init` hands back the object `alloc` made, still owned once; that one ownership is taken here
        guard let e = made?.takeRetainedValue() as? NSObject else { return nil }
        engine = e
        synthesizeIMP = synthIMP
    }

    /// How the engine's rate number maps to speed above 1 on this system. Measured once a run, because it differs:
    /// macOS 15.6 takes it as it is (1.5 → 1.5× shorter); iOS 27.0.1 ignores 1…2 and halves the rest (2.5 → 1.25×,
    /// 3 → 1.5×, 4 → 2×, measured 2026-11-11 on the iPhone; below 1 both take it as it is). One short sentence at 1
    /// and at 3, nobody hears it (≈ 0.2 s, on the render queue before the first fast piece).
    nonisolated(unsafe) private static var rateScale: Double?

    private func engineRate(_ rate: Double) -> Double {
        let r = min(max(rate, 0.5), 4)
        guard r > 1 else { return r }
        if Self.rateScale == nil {
            let probe = "Bu cümle yalnız hızı ölçmek için okunur."
            if let a = raw(probe, rate: 1, cancelled: { false }), let b = raw(probe, rate: 3, cancelled: { false }), b.samples.count > 0 {
                let got = Double(a.samples.count) / Double(b.samples.count)      // 3 when taken as it is, 1.5 when halved
                Self.rateScale = got < 2.2 ? 2 : 1
            }
        }
        return min(r * (Self.rateScale ?? 1), 4)
    }

    /// Done ahead of the first piece (ProfileRenderer.warmUp): the rate check above, so a fast first piece does not wait for it.
    func warm() { _ = engineRate(2) }

    /// What the engine's callbacks collect; they may arrive on the engine's own thread.
    private final class Sink: @unchecked Sendable {
        let lock = NSLock()
        var pcm = Data()
        var timings: [(seconds: Double, bytes: NSRange)] = []
        var stopped = false
    }

    /// Speaks `text` at the engine's `rate` (1 = the voice's own pace). Blocks until done; `cancelled` is asked at
    /// every piece of audio and stops the engine when it says yes. Word starts are in samples, ranges in `text`.
    func synthesize(_ text: String, rate: Double, cancelled: @escaping () -> Bool) -> RenderedSpeech? {
        let asked = engineRate(rate)
        guard var r = raw(text, rate: asked, cancelled: cancelled) else { return nil }
        // Where the system halves the rate (iOS), it does not halve the word times: they come as if the number had
        // been taken as it is, so on the iPhone every word above 1× was reported at half its real time (the last
        // word of a 8.5 s piece at 4.2 s) and the highlight ran ahead, then stood still. Measured 2026-11-12:
        // last word start / audio 0.98 at 1×, 0.49 at 2.75× and 3.6×, both voices.
        if asked > 1, let k = Self.rateScale, k != 1 {
            let end = max(r.samples.count - 1, 0)
            r.words = r.words.map { (min(Int(Double($0.sample) * k), end), $0.range) }
        }
        return r
    }

    /// The engine as it is, `rate` passed through untouched (`extra`: other request numbers, for the test hook).
    func raw(_ text: String, rate: Double, extra: [String: Float] = [:], cancelled: @escaping () -> Bool) -> RenderedSpeech? {
        guard let requestClass = NSClassFromString("SiriTTSSynthesisEngineRequest") as? NSObject.Type else { return nil }
        let request = requestClass.init()
        serial += 1
        request.setValue(text, forKey: "text")
        request.setValue("wp-\(serial)", forKey: "requestId")
        request.setValue(NSNumber(value: Float(rate)), forKey: "rate")
        for (k, v) in extra { request.setValue(NSNumber(value: v), forKey: k) }

        let sink = Sink()
        let engine = self.engine, stopSelector = self.stopSelector
        let audio: @convention(block) (NSData) -> Void = { d in
            sink.lock.lock(); defer { sink.lock.unlock() }
            if sink.stopped { return }
            if cancelled() { sink.stopped = true; _ = engine.perform(stopSelector); return }
            sink.pcm.append(d as Data)
        }
        let words: @convention(block) (NSArray) -> Void = { list in
            sink.lock.lock(); defer { sink.lock.unlock() }
            for case let w as NSObject in list {
                guard let t = w.value(forKey: "startTime") as? Double, let r = w.value(forKey: "textRange") as? NSValue else { continue }
                sink.timings.append((t, r.rangeValue))
            }
        }
        request.setValue(unsafeBitCast(audio, to: AnyObject.self), forKey: "audioHandler")
        request.setValue(unsafeBitCast(words, to: AnyObject.self), forKey: "wordTimingsHandler")
        typealias Synthesize = @convention(c) (AnyObject, Selector, AnyObject, AutoreleasingUnsafeMutablePointer<NSError?>?) -> ObjCBool
        var error: NSError?
        let ok = unsafeBitCast(synthesizeIMP, to: Synthesize.self)(engine, NSSelectorFromString("synthesize:error:"), request, &error)
        sink.lock.lock(); defer { sink.lock.unlock() }
        guard ok.boolValue, !sink.stopped, sink.pcm.count > 1 else { return nil }
        let samples: [Float] = sink.pcm.withUnsafeBytes { raw in raw.bindMemory(to: Int16.self).map { Float($0) / 32768 } }
        return RenderedSpeech(samples: samples, words: Self.wordStarts(sink.timings, in: text, sampleCount: samples.count))
    }

    /// The engine counts in UTF-8 bytes of the text it was given; the reader counts in UTF-16.
    static func wordStarts(_ timings: [(seconds: Double, bytes: NSRange)], in text: String, sampleCount: Int) -> [(sample: Int, range: NSRange)] {
        guard !timings.isEmpty else { return [] }
        var unitAtByte = [Int](repeating: 0, count: text.utf8.count + 1)
        var byte = 0, unit = 0
        for scalar in text.unicodeScalars {
            let b = UTF8.width(scalar), u = UTF16.width(scalar)
            for k in 0..<b { unitAtByte[byte + k] = unit }
            byte += b; unit += u
        }
        unitAtByte[byte] = unit
        var out: [(sample: Int, range: NSRange)] = []
        var last = -1
        for t in timings {
            let a = min(max(t.bytes.location, 0), byte), z = min(a + max(t.bytes.length, 0), byte)
            let range = NSRange(location: unitAtByte[a], length: unitAtByte[z] - unitAtByte[a])
            guard range.length > 0, range.location > last else { continue }      // one start a word, in reading order
            last = range.location
            out.append((min(max(Int(t.seconds * 48_000), 0), max(sampleCount - 1, 0)), range))
        }
        return out
    }
}
