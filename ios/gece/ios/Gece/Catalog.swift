// The moves, the three five-move sets (beşli) and tonight's plan. The data is moves.json (the same file that veri/preview.py draws).
import Foundation

struct VideoLink: Codable, Hashable {
    var title: String
    var url: String
}

/// A real physiotherapist's video of the move on YouTube.
struct YouTubeLink: Codable, Hashable {
    var title: String
    var channel: String
    var url: String
    var length: String
}

struct Props: Codable, Hashable {
    var seat: Bool?
    var cushion: Bool?
    var towel: Bool?
    var wall: Double?
}

struct Breath: Codable, Hashable {
    var `in`: Double
    var out: Double
}

struct Keyframe: Hashable {
    var pose: Pose
    var duration: Double
}

struct Move: Identifiable, Hashable {
    var id: String
    var name: String
    var slot: Int
    var seconds: Int
    var sides: Bool
    var area: String
    var dose: String
    var why: String
    var steps: [String]
    var cues: [String]
    var focus: [String]
    var props: Props
    var breath: Breath?
    var video: VideoLink
    var youtube: YouTubeLink?
    /// 1 = most important before sleep (breath, then neck, low back…); the library and the sets follow this order.
    var rank: Int
    var priority: String
    var frames: [Keyframe]

    var loopLength: Double { frames.reduce(0) { $0 + $1.duration } }
}

/// One of the five stops every set walks through: neck, shoulder, spine, hip-leg, breath.
struct Slot: Hashable {
    var n: Int
    var name: String
    var whereText: String
    var pool: [String]
}

/// A beşli: five moves, one per stop, always in the same order. A·TEMEL (the five most important), B·GEVŞE, C·DÜZEL.
struct MoveSet: Hashable {
    var key: String
    var name: String
    var theme: String
    var moves: [String]
    var title: String { "\(key) · \(name)" }
}

/// One step of a night: a move, on one side when the move has two.
struct PlannedStep: Identifiable, Hashable {
    enum Side: String {
        case right = "Sağ", left = "Sol"
        var key: String { self == .right ? "right" : "left" }
    }
    var move: Move
    var side: Side?
    var seconds: Int
    var id: String { move.id + (side.map { "-" + $0.rawValue } ?? "") }
    /// The left side is drawn as a mirror.
    var mirrored: Bool { side == .left }
}

struct NightPlan: Hashable, Identifiable {
    var id = UUID()
    var set: MoveSet
    var steps: [PlannedStep]
    var short: Bool
    var reason: String
    var phase: HabitPhase = .learn
    var nightNo = 1
    /// Moves that hurt on recent nights and were swapped for a gentler one of the same stop: original → substitute.
    var swaps: [String: String] = [:]
    var totalSeconds: Int { steps.reduce(0) { $0 + $1.seconds } }
}

final class Catalog: @unchecked Sendable {
    static let shared = Catalog()

    let moves: [Move]
    let sets: [String: MoveSet]
    let slots: [Slot]
    let redFlags: [String]
    static let order = ["A", "B", "C"]

    func move(_ id: String) -> Move? { moves.first { $0.id == id } }
    /// Every move, most important first.
    var byPriority: [Move] { moves.sorted { $0.rank < $1.rank } }
    func slot(_ n: Int) -> Slot? { slots.first { $0.n == n } }
    var orderedSets: [MoveSet] { Self.order.compactMap { sets[$0] } }

    private init() {
        guard let url = Bundle.main.url(forResource: "moves", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode(RawFile.self, from: data) else {
            moves = []; sets = [:]; slots = []; redFlags = []
            return
        }
        moves = raw.moves.map { m in
            Move(id: m.id, name: m.name, slot: m.slot, seconds: m.seconds, sides: m.sides, area: m.area, dose: m.dose,
                 why: m.why, steps: m.steps, cues: m.cues, focus: m.focus, props: m.props ?? Props(), breath: m.breath,
                 video: m.video, youtube: m.youtube, rank: m.rank ?? 99, priority: m.priority ?? "", frames: m.frames.map { Keyframe(pose: $0.pose(bases: raw.bases), duration: $0.d) })
        }
        sets = Dictionary(raw.sets.map { ($0.key, MoveSet(key: $0.key, name: $0.value.name, theme: $0.value.theme, moves: $0.value.moves)) },
                          uniquingKeysWith: { a, _ in a })
        slots = raw.slots.map { Slot(n: $0.n, name: $0.name, whereText: $0.where, pool: $0.pool) }
        redFlags = raw.redFlags
    }

    /// Tonight's plan: one set, five moves in stop order. short keeps stop 3 (spine) and stop 5 (breath): two minutes.
    /// A move in `avoid` (it hurt on recent nights) gives its place to the first move of the same stop that did not.
    func plan(set key: String, short: Bool = false, avoid: Set<String> = [], reason: String = "") -> NightPlan {
        let set = sets[key] ?? MoveSet(key: key, name: key, theme: "", moves: [])
        var swaps: [String: String] = [:]
        var list: [Move] = []
        for id in set.moves {
            guard var m = move(id) else { continue }
            if avoid.contains(id), let alt = slot(m.slot)?.pool.first(where: { !avoid.contains($0) && !set.moves.contains($0) }).flatMap(move) {
                swaps[id] = alt.id
                m = alt
            }
            list.append(m)
        }
        if short { list = list.filter { $0.slot == 3 || $0.slot == 5 } }
        let steps = list.flatMap { m -> [PlannedStep] in
            m.sides ? [PlannedStep(move: m, side: .right, seconds: m.seconds / 2), PlannedStep(move: m, side: .left, seconds: m.seconds / 2)]
                    : [PlannedStep(move: m, side: nil, seconds: m.seconds)]
        }
        return NightPlan(set: set, steps: steps, short: short, reason: short ? "Mini gece: omurga ve nefes, 2 dakika" : reason, swaps: swaps)
    }
}

// MARK: JSON

private struct RawFile: Decodable {
    var bases: [String: RawPose]
    var moves: [RawMove]
    var slots: [RawSlot]
    var sets: [String: RawSet]
    var redFlags: [String]
}

private struct RawSlot: Decodable {
    var n: Int
    var name: String
    var `where`: String
    var pool: [String]
}

private struct RawSet: Decodable {
    var name: String
    var theme: String
    var moves: [String]
}

private struct RawMove: Decodable {
    var id, name: String
    var slot: Int
    var seconds: Int
    var sides: Bool
    var area, dose, why: String
    var steps, cues, focus: [String]
    var props: Props?
    var breath: Breath?
    var video: VideoLink
    var youtube: YouTubeLink?
    var rank: Int?
    var priority: String?
    var frames: [RawFrame]
}

/// Every field is optional: a frame names a base and changes only what differs.
private struct RawPose: Decodable {
    var hip: [Double]?
    var torso, head, bend, facing: Double?
    var armN, armF, legN, legF: [Double]?
    var footN, footF: Double?
    var scale: [String: [Double]]?

    func merged(over b: RawPose) -> RawPose {
        RawPose(hip: hip ?? b.hip, torso: torso ?? b.torso, head: head ?? b.head, bend: bend ?? b.bend, facing: facing ?? b.facing,
                armN: armN ?? b.armN, armF: armF ?? b.armF, legN: legN ?? b.legN, legF: legF ?? b.legF,
                footN: footN ?? b.footN, footF: footF ?? b.footF, scale: scale ?? b.scale)
    }
}

private struct RawFrame: Decodable {
    var base: String?
    var d: Double
    var fields: RawPose

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        base = try c.decodeIfPresent(String.self, forKey: .base)
        d = try c.decode(Double.self, forKey: .d)
        fields = try RawPose(from: decoder)
    }
    enum Key: String, CodingKey { case base, d }

    func pose(bases: [String: RawPose]) -> Pose {
        let p = base.flatMap { bases[$0] }.map { fields.merged(over: $0) } ?? fields
        func pair(_ v: [Double]?) -> SIMD2<Double> { SIMD2(v?.first ?? 0, v?.dropFirst().first ?? 0) }
        func scale(_ k: String) -> SIMD2<Double> { p.scale?[k].map { SIMD2($0[0], $0[1]) } ?? SIMD2(1, 1) }
        let facing = p.facing ?? 1
        let legN = pair(p.legN), legF = pair(p.legF)
        return Pose(hip: pair(p.hip), torso: p.torso ?? 90, head: p.head ?? 90, bend: p.bend ?? 0, facing: facing,
                    armN: pair(p.armN), armF: pair(p.armF), legN: legN, legF: legF,
                    footN: p.footN ?? legN.y + 90 * facing, footF: p.footF ?? legF.y + 90 * facing,
                    scaleArmN: scale("armN"), scaleArmF: scale("armF"), scaleLegN: scale("legN"), scaleLegF: scale("legF"))
    }
}
