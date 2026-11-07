// What the body feels on the bike, and the base layer threshold learned from the person's own answers.
import Foundation

enum Feel: String, Codable, CaseIterable, Sendable {
    case cold, ok, warm
    var label: String { switch self { case .cold: "Üşüdüm"; case .ok: "Tam"; case .warm: "Terledim" } }
    var symbol: String { switch self { case .cold: "snowflake"; case .ok: "hand.thumbsup.fill"; case .warm: "flame.fill" } }
}

struct RideFeedback: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var date: Date
    var leg: LegKind
    var feel: Feel
    var baseLayer: Bool
    var rideFeel: Double          // what Ufuk computed for that ride
    var temp: Double
    var wind: Double
    var wet: Bool
    var mood: Int?                // 1…5, optional
}

struct Thresholds: Sendable {
    var baseLayer: Double         // below this ride-feel: wear the base layer
    var windproof: Double         // below this: a windproof layer on top
    var samples: Int
}

enum Clothing {
    static let priorBase = 12.0
    static let priorWind = 4.0

    /// Felt temperature on the bike. The air you meet is your speed plus part of the wind (you do not
    /// always ride into it). Below 15 °C the wind-chill formula (JAG/TI), above it a mild airflow loss.
    /// Wet skin and clothes take about two more degrees.
    static func rideFeel(temp: Double, wind: Double, speed: Double, wet: Bool) -> Double {
        let v = speed + 0.6 * wind
        var f: Double
        if temp <= 15, v > 4.8 {
            let p = pow(v, 0.16)
            f = 13.12 + 0.6215 * temp - 11.37 * p + 0.3965 * temp * p
        } else {
            f = temp - 0.05 * v
        }
        if wet { f -= 2 }
        return f
    }

    /// Learns the threshold that best separates "a base layer was needed" from "not needed", then pulls it
    /// toward the prior while there are few answers, so one odd morning does not move it far.
    static func learn(_ fb: [RideFeedback]) -> Thresholds {
        // needed: cold without layer · fine with layer · cold even with layer
        let base = fb.map { ($0.rideFeel, ($0.feel == .cold) || ($0.feel == .ok && $0.baseLayer)) }
        // windproof needed: cold with the base layer on; not needed: fine or warm with the layer
        let wind = fb.filter(\.baseLayer).map { ($0.rideFeel, $0.feel == .cold) }
        return Thresholds(baseLayer: fit(base, prior: priorBase), windproof: fit(wind, prior: priorWind), samples: fb.count)
    }

    static func fit(_ pts: [(Double, Bool)], prior: Double, priorWeight: Double = 3) -> Double {
        guard !pts.isEmpty else { return prior }
        let xs = pts.map(\.0).sorted()
        var cands = [prior, (xs.first ?? prior) - 1, (xs.last ?? prior) + 1]
        for i in 1..<max(1, xs.count) where xs.count > 1 { cands.append((xs[i - 1] + xs[i]) / 2) }
        func score(_ t: Double) -> Int { pts.filter { ($0.0 < t) == $0.1 }.count }
        let best = cands.max { a, b in
            let sa = score(a), sb = score(b)
            return sa != sb ? sa < sb : abs(a - prior) > abs(b - prior)
        } ?? prior
        let n = Double(pts.count)
        return (prior * priorWeight + best * n) / (priorWeight + n)
    }
}
