// Kalınlık for the iPhone's own voices (Yelda, Cem…) on Voice Dream's scale, set from inside the app.
//
// Measured on macOS 27.2 with compact Yelda, the same engine as iOS 27 (2026-11-06; the phone gave the same 181 Hz
// on 2026-10-26). `pitchMultiplier` p → median pitch:
//
//     1.0 → 207 Hz · 0.75 → 194 · 0.5 → 181 · 0.25 → 168 · 0.0 → 156 · −0.2 → 147 · −0.4 → 137 · −0.6 → 128 · −1.0 → 106
//
// so the pitch ratio is (3 + p) / 4 below 1, where the engines before iOS 27 (and Voice Dream's recordings) gave
// (1 + p) / 2: Voice Dream's Kalınlık 50 is now p = 0. The public setter stops at 0.5, which is why Yelda stayed at
// 181 Hz and only the phone's Spoken Content settings reached her old depth (those go in below the setter). The stop
// is in the setter alone: the same number written into the utterance's stored value is taken by the engine as it is,
// with the same voice colour, speed and level (18.67 s and −15.7 dBFS at every value above). Above 1 nothing changed.
//
// The stored value is not public API. It is looked up by name and type at run time; if a later iOS renames it, the
// setter's 0.5 is what remains and nothing breaks.
import AVFoundation
import ObjectiveC

enum SystemPitch {
    /// Kalınlık as the settings keep it: 1 = the voice itself, 0.5 = Voice Dream's 50, down to 0.2 (about 124 Hz for Yelda).
    static let range: ClosedRange<Double> = 0.2...2.0

    /// Voice Dream's Kalınlık as a pitch ratio, and back.
    static func ratio(_ k: Double) -> Double { k < 1 ? (1 + k) / 2 : k }
    static func kalinlik(ratio r: Double) -> Double { r < 1 ? 2 * r - 1 : r }

    /// The engine of iOS 27 and later, with the weaker pitch curve.
    static let newEngine: Bool = { if #available(iOS 27, macOS 27, *) { return true } else { return false } }()

    private static let slot: Int? = {
        guard let iv = class_getInstanceVariable(AVSpeechUtterance.self, "_pitchMultiplier"),
              let t = ivar_getTypeEncoding(iv), String(cString: t) == "f" else { return nil }
        return ivar_getOffset(iv)
    }()

    /// Whether Kalınlık under 50 can be reached on this phone.
    static var reachesDeep: Bool { newEngine && slot != nil }

    /// Set the utterance's pitch so that the voice sounds at Voice Dream's Kalınlık `k`.
    static func apply(_ k: Double, to u: AVSpeechUtterance) {
        let k = min(max(k, range.lowerBound), range.upperBound)
        guard newEngine, k < 1 else { u.pitchMultiplier = Float(max(k, 0.5)); return }
        let p = Float(4 * ratio(k) - 3)                 // what this engine needs for that ratio
        u.pitchMultiplier = max(p, 0.5)
        guard p < 0.5, let slot else { return }
        Unmanaged.passUnretained(u).toOpaque().advanced(by: slot).assumingMemoryBound(to: Float.self).pointee = p
    }
}

/// The Turkish voice as the phone's Spoken Content settings make it, measured so that Wise Path can make the same
/// sound with its own Kalınlık and speed.
struct PhoneVoice: Sendable {
    var kalinlik: Double            // Voice Dream's scale, 0.5 = 50
    var speed: Double?              // multiple of 1×; nil when iOS took the app's own rate in that mode
    var phoneHz: Double             // the pitch the phone's settings give
    var ownHz: Double               // the pitch Wise Path reached with `kalinlik`
    var plainHz: Double             // the voice itself
    var miss: Double { 12 * log2(ownHz / phoneHz) }        // semitones between the two
    var matched: Bool { abs(miss) < 0.5 }
}

/// Test hook (-depthtest): the pitch this device's engine gives for Kalınlık 100 … 20, and what "Bu tınıyı Wise
/// Path'e al" would measure, written to Documents/depthtest.txt. Nothing is played.
enum DepthTest {
    static func run() async {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("tr") && $0.identifier.hasPrefix("com.apple") }
        var log = ["\(ProcessInfo.processInfo.operatingSystemVersionString) · new engine \(SystemPitch.newEngine) · deep \(SystemPitch.reachesDeep)"]
        log += voices.map { "voice \($0.identifier)" }
        if let y = voices.first(where: { $0.name == "Yelda" && $0.quality == .default }) ?? voices.first {
            let lines: [String] = await withCheckedContinuation { k in
                ProfileRenderer.shared.queue.async {
                    var out: [String] = []
                    for kal in [1.0, 0.75, 0.5, 0.4, 0.3, 0.2] {
                        let text = "Felsefe, insanın kendi aklını kendi üzerine çevirmesiyle başlar."
                        guard let r = ProfileRenderer.shared.renderSystem(text, voiceID: y.identifier, rate: 0.5,
                                                                          tune: VoiceTune(pitch: kal, volume: 1, steady: 0), cancelled: { false })
                        else { out.append("Kalınlık \(Int(kal * 100)): no audio"); continue }
                        let v = PitchShift.f0Track(r.samples, sr: 48_000, hop: 240).filter { $0 > 0 }.sorted()
                        let hz = v.isEmpty ? 0 : v[v.count / 2]
                        out.append(String(format: "Kalınlık %3d → %.1f Hz (%.2f s)", Int(kal * 100), hz, Double(r.samples.count) / 48_000))
                    }
                    if let m = ProfileRenderer.shared.phoneVoice(voiceID: y.identifier) {
                        out.append(String(format: "phone settings %.1f Hz · own %.1f Hz at Kalınlık %d (miss %.2f st) · plain %.1f Hz · speed %@",
                                          m.phoneHz, m.ownHz, Int((m.kalinlik * 100).rounded()), m.miss, m.plainHz,
                                          m.speed.map { String(format: "%.2f×", $0) } ?? "the app's rate was taken"))
                    } else { out.append("phone voice: not measurable") }
                    k.resume(returning: out)
                }
            }
            log += lines
        }
        try? log.joined(separator: "\n").write(to: URL.documentsDirectory.appending(path: "depthtest.txt"), atomically: true, encoding: .utf8)
    }
}
