// Test hook: launch with -voicedump writes Documents/voicedump/<voice>_<steady>.wav (48 kHz mono, 16 bit) for a fixed
// passage, so the voices' melody can be measured on the Mac (pitch range, sudden jumps) exactly as the phone makes them.
import Foundation

enum VoiceDump {
    static let sample = "Berkeley'in maddeyi inkâr etmesinin sebebi, her şeyden önce dinseldi: madde, onun gözünde, ateizmin ve kuşkuculuğun dayanağıydı. Eğer dünya, Tanrı'dan bağımsız, kendi yasalarıyla işleyen kör bir maddeden oluşuyorsa, Tanrı'ya ihtiyaç kalmaz. Ve eğer gerçek dünya, algılarımızın ötesinde, onlara yalnızca benzeyen bir maddeyse, algılarımızın o dünyaya benzeyip benzemediğini hiçbir zaman bilemeyiz; kuşkucu kazanır."

    static func run() async {
        let dir = URL.documentsDirectory.appending(path: "voicedump", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // VR_DUMP="steady:calm;steady:calm…"
        let cases: [(Double, Double)] = (ProcessInfo.processInfo.environment["VR_DUMP"] ?? "0:0;0.3:0;0:0.5")
            .split(separator: ";").compactMap { p in
                let v = p.split(separator: ":").compactMap { Double($0) }
                return v.count == 2 ? (v[0], v[1]) : nil
            }
        let env = ProcessInfo.processInfo.environment
        let speed = Double(env["VR_SPEED"] ?? "1") ?? 1
        ProfileRenderer.emaModelSpeed = Double(env["VR_MODEL"] ?? "1") ?? 1
        ProfileRenderer.skipPitch = env["VR_NOPITCH"] != nil
        ProfileRenderer.pitchFirst = env["VR_PFIRST"] != nil
        let tag = env["VR_TAG"] ?? ""
        let profiles: [VoiceProfile] = env["VR_ONLY_EMA"] != nil ? [.emaTok] : [.emaTok, .derin]
        for profile in profiles where profile.isAvailable {
            for (s, c) in cases {
                await withCheckedContinuation { (k: CheckedContinuation<Void, Never>) in
                    ProfileRenderer.shared.queue.async {
                        let r = ProfileRenderer.shared.render(sample, profile: profile, speed: speed, steady: s, calm: c, cancelled: { false })
                        if let r { write(r.samples, to: dir.appending(path: "\(profile.id)\(tag)_s\(s)_c\(c).wav")) }
                        k.resume()
                    }
                }
            }
        }
        try? "done".write(to: dir.appending(path: "done.txt"), atomically: true, encoding: .utf8)
    }

    static func write(_ samples: [Float], to url: URL) {
        var data = Data()
        func le<T: FixedWidthInteger>(_ v: T) { var x = v.littleEndian; data.append(Data(bytes: &x, count: MemoryLayout<T>.size)) }
        let n = samples.count
        data.append("RIFF".data(using: .ascii)!); le(UInt32(36 + n * 2)); data.append("WAVEfmt ".data(using: .ascii)!)
        le(UInt32(16)); le(UInt16(1)); le(UInt16(1)); le(UInt32(48_000)); le(UInt32(96_000)); le(UInt16(2)); le(UInt16(16))
        data.append("data".data(using: .ascii)!); le(UInt32(n * 2))
        for v in samples { le(Int16(max(-1, min(1, v)) * 32767)) }
        try? data.write(to: url)
    }
}
