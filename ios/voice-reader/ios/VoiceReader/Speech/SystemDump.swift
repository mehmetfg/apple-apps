// Test hook: launch with -sysdump writes Documents/sysdump/ for the Turkish system voice as this iOS makes it:
// for every case the raw audio copied inside the buffer callback (<case>_cb.wav, the source rate), the same buffers
// read again a moment later on the main thread (<case>_late.wav: differs from _cb when the synthesiser reuses its
// buffers), and a log of every buffer (format, frames, object, arrival time) and every word callback.
import AVFoundation

enum SystemDump {
    static let sample = VoiceDump.sample

    static func run() async {
        let dir = URL.documentsDirectory.appending(path: "sysdump", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tr = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("tr") && $0.identifier.hasPrefix("com.apple") }
        var log = ["iOS \(ProcessInfo.processInfo.operatingSystemVersionString)"]
        log += tr.map { "voice \($0.identifier) quality \($0.quality.rawValue)" }
        let fallback = AVSpeechSynthesisVoice(language: "tr-TR")
        log.append("language tr-TR → \(fallback?.identifier ?? "nil")")
        log.append("super-compact Yelda → \(AVSpeechSynthesisVoice(identifier: "com.apple.voice.super-compact.tr-TR.Yelda")?.identifier ?? "nil")")
        let synth = AVSpeechSynthesizer()
        let words = WordLog()
        synth.delegate = words
        for v in tr where (v.name == "Yelda" || v.name == "Cem") && !CommandLine.arguments.contains("ats") {
            for (rate, pitch) in [(Float(0.5), Float(1)), (0.5, 0.5), (SpeechPlayer.rate(for: 2.75), 0.5), (SpeechPlayer.rate(for: 3.58), 0.5)] {
                let name = "\(v.name)-\(v.identifier.contains("super") ? "sc" : v.identifier.contains("compact") ? "c" : "x")_r\(rate)_p\(pitch)"
                log.append("== \(name)")
                let r = await speak(synth, words, voice: v, rate: rate, pitch: pitch)
                log += r.log
                write(r.cb, rate: r.rate, to: dir.appending(path: "\(name)_cb.wav"))
                write(r.late, rate: r.rate, to: dir.appending(path: "\(name)_late.wav"))
            }
        }
        // -sysdump ats: the utterance takes the user's Spoken Content settings (iOS 27: Perde, Ekolayzer…)
        if CommandLine.arguments.contains("ats"), let y = tr.first(where: { $0.name == "Yelda" }) {
            let gain = await withCheckedContinuation { (k: CheckedContinuation<Float?, Never>) in
                ProfileRenderer.shared.queue.async { k.resume(returning: ProfileRenderer.shared.assistiveGain(voiceID: y.identifier)) }
            }
            log.append("assistive gain \(gain.map { String(format: "%.1f dB", 20 * log10($0)) } ?? "nil")")
            let plain = await speak(synth, words, voice: y, rate: 0.81, pitch: 0.5)
            write(plain.cb, rate: plain.rate, to: dir.appending(path: "plain_r081_p05_cb.wav"))
            for (tag, rate, own) in [("ats_r081", Float(0.81), false), ("ats_r05", 0.5, false), ("ats_novoice", 0.81, true)] {
                let u = AVSpeechUtterance(string: sample)
                u.prefersAssistiveTechnologySettings = true
                u.rate = rate
                let r = await speak(synth, words, utterance: u, voice: own ? nil : y, rate: rate, pitch: 1)
                log.append("\(tag): \(String(format: "%.2f", Double(r.cb.count) / r.rate)) s")
                write(r.cb, rate: r.rate, to: dir.appending(path: "\(tag)_cb.wav"))
            }
        }
        try? log.joined(separator: "\n").write(to: dir.appending(path: "log.txt"), atomically: true, encoding: .utf8)
        try? "done".write(to: dir.appending(path: "done.txt"), atomically: true, encoding: .utf8)
    }

    private struct Result { var cb: [Float] = []; var late: [Float] = []; var rate = 22_050.0; var log: [String] = [] }

    private static func speak(_ synth: AVSpeechSynthesizer, _ words: WordLog, utterance: AVSpeechUtterance? = nil,
                              voice: AVSpeechSynthesisVoice?, rate: Float, pitch: Float) async -> Result {
        let u = utterance ?? AVSpeechUtterance(string: sample)
        if let voice { u.voice = voice }
        if utterance == nil { u.rate = rate; u.pitchMultiplier = pitch }
        let box = Box()
        words.reset(box)
        let t0 = Date()
        return await withCheckedContinuation { (k: CheckedContinuation<Result, Never>) in
            synth.write(u) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { box.add("non-PCM buffer \(type(of: buffer))"); return }
                let n = Int(pcm.frameLength)
                let f = pcm.format
                let samples = read(pcm)
                box.lock.lock()
                let at = box.frames
                box.frames += n
                box.res.rate = f.sampleRate
                box.res.cb += samples
                box.lock.unlock()
                if box.count < 12 || n == 0 || f.sampleRate != box.res.rate {
                    box.add(String(format: "buf %d t=%.3f frames=%d at=%d sr=%.0f fmt=%d ch=%d inter=%d obj=%@ thread=%@",
                                   box.count, Date().timeIntervalSince(t0), n, at, f.sampleRate, Int(f.commonFormat.rawValue),
                                   Int(f.channelCount), f.isInterleaved ? 1 : 0, "\(ObjectIdentifier(pcm))",
                                   Thread.isMainThread ? "main" : "bg"))
                }
                box.count += 1
                box.lock.lock(); box.last = Date(); box.lock.unlock()
                if n == 0 { box.add(String(format: "ZERO buffer t=%.3f at=%d", Date().timeIntervalSince(t0), at)) }
                DispatchQueue.main.async {
                    box.res.late += read(pcm)
                    // a zero-length buffer is the end; wait 1.5 s more in case more audio follows it (it should not)
                    if n == 0, !box.waiting { box.waiting = true; finish(box, t0: t0, k) }
                }
            }
        }
    }

    @MainActor private static func finish(_ box: Box, t0: Date, _ k: CheckedContinuation<Result, Never>) {
        box.lock.lock(); let idle = Date().timeIntervalSince(box.last); box.lock.unlock()
        if idle < 1.5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { MainActor.assumeIsolated { finish(box, t0: t0, k) } }
            return
        }
        box.add(String(format: "end after %d buffers, %.3f s, audio %.3f s, words %d", box.count,
                       Date().timeIntervalSince(t0), Double(box.frames) / box.res.rate, box.words))
        box.res.log = box.lines
        k.resume(returning: box.res)
    }

    private static func read(_ pcm: AVAudioPCMBuffer) -> [Float] {
        let n = Int(pcm.frameLength)
        if let f = pcm.floatChannelData { return Array(UnsafeBufferPointer(start: f[0], count: n)) }
        if let i = pcm.int16ChannelData { return UnsafeBufferPointer(start: i[0], count: n).map { Float($0) / 32768 } }
        if let i = pcm.int32ChannelData { return UnsafeBufferPointer(start: i[0], count: n).map { Float($0) / 2_147_483_648 } }
        return []
    }

    private final class Box: @unchecked Sendable {
        let lock = NSLock()
        var res = Result()
        var frames = 0
        var count = 0
        var words = 0
        var last = Date()
        var waiting = false
        var lines: [String] = []
        func add(_ s: String) { lock.lock(); lines.append(s); lock.unlock() }
    }

    private final class WordLog: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
        private var box: Box?
        func reset(_ b: Box) { box = b }
        func speechSynthesizer(_ s: AVSpeechSynthesizer, willSpeakRangeOfSpeechString r: NSRange, utterance u: AVSpeechUtterance) {
            guard let b = box else { return }
            b.lock.lock(); let at = b.frames; b.words += 1; let i = b.words; b.lock.unlock()
            if i <= 6 || i % 10 == 0 { b.add("word \(i) \(r.location)+\(r.length) at=\(at) '\((u.speechString as NSString).substring(with: r))'") }
        }
        func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
            guard let b = box else { return }
            b.lock.lock(); let at = b.frames; b.lock.unlock()
            b.add("FINISH at=\(at)")
        }
    }

    static func write(_ samples: [Float], rate: Double, to url: URL) {
        var data = Data()
        func le<T: FixedWidthInteger>(_ v: T) { var x = v.littleEndian; data.append(Data(bytes: &x, count: MemoryLayout<T>.size)) }
        let n = samples.count, sr = UInt32(rate)
        data.append("RIFF".data(using: .ascii)!); le(UInt32(36 + n * 2)); data.append("WAVEfmt ".data(using: .ascii)!)
        le(UInt32(16)); le(UInt16(1)); le(UInt16(1)); le(sr); le(sr * 2); le(UInt16(2)); le(UInt16(16))
        data.append("data".data(using: .ascii)!); le(UInt32(n * 2))
        for v in samples { le(Int16(max(-1, min(1, v)) * 32767)) }
        try? data.write(to: url)
    }
}

/// Test hook: -skiptest reads two long paragraphs (six sentences each) with Yelda at 330 words a minute through the
/// real player and logs the spoken word every 0.2 s to Documents/skiptest.txt. A skipped stretch shows as a jump of
/// hundreds of characters; the run passes when the last word of each paragraph is reached.
@MainActor enum SkipTest {
    static func run(_ model: AppModel) async {
        let para = VoiceDump.sample + " " + VoiceDump.sample
        let text = para + "\n" + para
        let p = model.player
        p.voiceID = AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix("tr") && $0.name == "Yelda" }?.identifier ?? p.voiceID
        // -steadytest: the same reading with Cem and Düzlük 40 (the rendered path: PitchShift.flatten on every piece)
        if CommandLine.arguments.contains("-steadytest") {
            if let cem = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.language.hasPrefix("tr") && $0.name.hasPrefix("Cem") }) {
                p.voiceID = cem.identifier
            }
            p.voiceTune[p.voiceID] = VoiceTune(pitch: 1, volume: 1, steady: 0.4)
        }
        p.speed = 330 / SpeechPlayer.wordsAtOneX
        // -fasttest: the same reading at 470 words a minute through FastSpeech
        if CommandLine.arguments.contains("-fasttest") { p.fastClear = true; p.speed = 470 / SpeechPlayer.wordsAtOneX }
        p.load(id: UUID(), title: "Atlama sınaması", author: nil, content: DocumentContent(text: text, chapters: [], pages: []), at: 0)
        p.play()
        var log = ["voice \(p.voiceID) speed \(p.speed) steady \(p.voiceTune[p.voiceID]?.steady ?? 0) length \((text as NSString).length)"]
        var last = -1, maxJump = 0, seen: [Int] = []
        let start = Date()
        while Date().timeIntervalSince(start) < 70 {
            try? await Task.sleep(for: .milliseconds(200))
            if let w = p.spokenWord?.location, w != last {
                if last >= 0 { maxJump = max(maxJump, w - last) }
                seen.append(w); last = w
            }
            if !p.isSpeaking { break }
        }
        let len = (text as NSString).length, half = (para as NSString).length
        log.append(String(format: "%.1f s, %d positions, last %d of %d, largest jump %d characters", Date().timeIntervalSince(start), seen.count, last, len, maxJump))
        log.append("reached end of paragraph 1: \(seen.contains { $0 > half - 40 && $0 < half }) · paragraph 2: \(last > len - 40)")
        log.append(seen.map(String.init).joined(separator: " "))
        p.pause()
        try? log.joined(separator: "\n").write(to: URL.documentsDirectory.appending(path: "skiptest.txt"), atomically: true, encoding: .utf8)
    }
}
