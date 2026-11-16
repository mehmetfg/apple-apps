// Test hook: launch with -siritest. Writes Documents/siritest/log.txt and, for the full chain, <voice>_<speed>.wav
// (48 kHz mono, 16 bit). Nothing is played.
//   1. the engine alone: how its `rate` number changes the length on this system, and what each call costs;
//   2. the app's chain at 1×, 2.75× (330 words a minute) and 3.6× (430): the characters a second it reaches
//      against the 14.0 × speed asked for, and how long the engine and the steps after it take.
import Foundation

enum SiriTest {
    static func run() async {
        let dir = URL.documentsDirectory.appending(path: "siritest", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var log = ["\(ProcessInfo.processInfo.operatingSystemVersionString) · voices at \(SiriEngine.root?.path ?? "nowhere")"]
        func save() { try? log.joined(separator: "\n").write(to: dir.appending(path: "log.txt"), atomically: true, encoding: .utf8) }
        func onQueue<T>(_ work: @escaping () -> T) async -> T {
            await withCheckedContinuation { k in ProfileRenderer.shared.queue.async { k.resume(returning: work()) } }
        }
        func timed<T>(_ f: () -> T) -> (T, Double) { let s = Date(); let v = f(); return (v, Date().timeIntervalSince(s)) }
        let text = VoiceDump.sample
        let short = "Berkeley'in maddeyi inkâr etmesinin sebebi, her şeyden önce dinseldi: madde, onun gözünde, ateizmin ve kuşkuculuğun dayanağıydı."

        for voice in SiriEngine.Voice.allCases {
            guard SiriEngine.isInstalled(voice) else { log.append("\(voice): not installed"); save(); continue }
            let lines: [String] = await onQueue {
                var out: [String] = []
                let (made, opened) = timed { SiriEngine(voice: voice) }
                guard let e = made else { return ["\(voice): engine did not open"] }
                out.append(String(format: "%@ engine open %.3f s", voice.rawValue, opened))
                var base = 0.0
                for rate in [1.0, 1.0, 1.25, 1.5, 2, 2.5, 3, 3.5, 4] {
                    let (r, s) = timed { e.raw(short, rate: rate, cancelled: { false }) }
                    let d = Double(r?.samples.count ?? 0) / 48_000
                    if rate == 1 { base = d }
                    out.append(String(format: "  raw rate %.2f: %.2f s audio (%.2f× shorter) in %.3f s", rate, d, base / max(d, 0.001), s))
                }
                for (k, v) in [("neuralSentenceDuration", Float(0.6)), ("neuralSentenceDuration", 1.6)] {
                    let (r, _) = timed { e.raw(short, rate: 1, extra: [k: v], cancelled: { false }) }
                    out.append(String(format: "  raw %@ %.1f: %.2f s audio", k, v, Double(r?.samples.count ?? 0) / 48_000))
                }
                let (_, scaleTook) = timed { _ = e.synthesize(short, rate: 1.5, cancelled: { false }) }
                out.append(String(format: "  first fast call (with the rate check) %.3f s", scaleTook))
                return out
            }
            log += lines; save()
        }

        for profile in [VoiceProfile.siriElif, .siriKaan] {
            guard profile.isAvailable else { continue }
            for speed in [1.0, 2.75, 3.6] {
                let line: String = await onQueue {
                    let (r, took) = timed { ProfileRenderer.shared.render(text, profile: profile, speed: speed, cancelled: { false }) }
                    guard let r else { return "\(profile.id) \(speed)×: no audio" }
                    VoiceDump.write(r.samples, to: dir.appending(path: "\(profile.id)_\(speed).wav"))
                    // each word's start against the audio, and where the last loud 10 ms is
                    let ns = text as NSString
                    var lastLoud = 0
                    for k in stride(from: 0, to: max(0, r.samples.count - 480), by: 480) {
                        var m: Float = 0
                        for j in 0..<480 { m = max(m, abs(r.samples[k + j])) }
                        if m > 0.02 { lastLoud = k }
                    }
                    let lines = r.words.map { String(format: "%.3f\t%@", Double($0.sample) / 48_000, ns.substring(with: $0.range)) }
                        + [String(format: "last loud %.3f · audio %.3f", Double(lastLoud) / 48_000, Double(r.samples.count) / 48_000)]
                    try? lines.joined(separator: "\n").write(to: dir.appending(path: "\(profile.id)_\(speed).words.txt"), atomically: true, encoding: .utf8)
                    let seconds = Double(r.samples.count) / 48_000
                    let cps = Double(text.count) / seconds
                    let ordered = zip(r.words, r.words.dropFirst()).allSatisfy { $0.sample <= $1.sample && $0.range.location < $1.range.location }
                    let t = ProfileRenderer.shared.lastTimes
                    return String(format: "%@ %.2f×: %.2f s audio in %.2f s (%.1f× real time) · engine %.2f s, after it %.3f s · %d words%@ · %.1f characters a second (asked %.1f, %.0f %%)",
                                  profile.id, speed, seconds, took, seconds / max(took, 0.001), t.engine, t.after, r.words.count,
                                  ordered ? "" : " (out of order)", cps, 14 * speed, 100 * cps / (14 * speed))
                }
                log.append(line); save()
            }
        }
        log.append("done"); save()
    }
}
