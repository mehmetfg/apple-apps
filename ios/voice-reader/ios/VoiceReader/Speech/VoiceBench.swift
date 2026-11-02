// Measures how fast each Voice Reader voice renders on this device (launch with -voicebench).
// Writes Library/voice-bench.txt: for every voice and speed, render time and the real-time factor
// (seconds of audio produced per second of work; above the playback speed means it keeps up).
import Foundation

enum VoiceBench {
    static let sample = "Bin dört yüz elli yıllarının ortasında Mainz şehrinde Johannes Gutenberg adında bir kuyumcu, harfleri tek tek dökülmüş metal parçalardan dizip bir pres altında kâğıda basmanın yolunu bulduğunda, Avrupa'da bir kitabın değeri, onu elle kopyalamak için harcanan aylarca emeğin toplamıydı."

    static func run() async {
        var lines = ["device \(ProcessInfo.processInfo.hostName) · \(Date())"]
        for profile in VoiceProfile.all where profile.isAvailable {
            for speed in [1.0, 2.5] {
                let result = await withCheckedContinuation { (c: CheckedContinuation<String, Never>) in
                    ProfileRenderer.shared.queue.async {
                        _ = ProfileRenderer.shared.render("Isınma cümlesi.", profile: profile, speed: speed, cancelled: { false })
                        let t0 = Date()
                        let r = ProfileRenderer.shared.render(sample, profile: profile, speed: speed, cancelled: { false })
                        let dt = Date().timeIntervalSince(t0)
                        let audio = Double(r?.samples.count ?? 0) / 48_000
                        c.resume(returning: String(format: "%@ %.1fx: render %.2fs, audio %.2fs, real-time %.1fx, words %d",
                                                   profile.name, speed, dt, audio, audio / max(dt, 0.001), r?.words.count ?? 0))
                    }
                }
                lines.append(result)
            }
        }
        try? lines.joined(separator: "\n").write(to: URL.libraryDirectory.appending(path: "voice-bench.txt"), atomically: true, encoding: .utf8)
    }
}
