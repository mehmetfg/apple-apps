// The figure: one side view pose, its joints, keyframe interpolation and the drawing.
// The kinematics are the same as veri/preview.py; change both together.
import SwiftUI

struct Pose: Hashable {
    var hip: SIMD2<Double>
    var torso: Double
    var head: Double
    var bend: Double
    var facing: Double
    var armN, armF, legN, legF: SIMD2<Double>       // (upper, lower) angles in degrees
    var footN, footF: Double
    var scaleArmN, scaleArmF, scaleLegN, scaleLegF: SIMD2<Double>

    static func lerp(_ a: Pose, _ b: Pose, _ t: Double) -> Pose {
        func l(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        func v(_ x: SIMD2<Double>, _ y: SIMD2<Double>) -> SIMD2<Double> { x + (y - x) * t }
        return Pose(hip: v(a.hip, b.hip), torso: l(a.torso, b.torso), head: l(a.head, b.head), bend: l(a.bend, b.bend),
                    facing: t < 0.5 ? a.facing : b.facing,
                    armN: v(a.armN, b.armN), armF: v(a.armF, b.armF), legN: v(a.legN, b.legN), legF: v(a.legF, b.legF),
                    footN: l(a.footN, b.footN), footF: l(a.footF, b.footF),
                    scaleArmN: v(a.scaleArmN, b.scaleArmN), scaleArmF: v(a.scaleArmF, b.scaleArmF),
                    scaleLegN: v(a.scaleLegN, b.scaleLegN), scaleLegF: v(a.scaleLegF, b.scaleLegF))
    }
}

/// Segment lengths, in figure units (height about 1.75).
enum Segment {
    static let torso = 0.52, neck = 0.07, headR = 0.10, upperArm = 0.30, forearm = 0.28, thigh = 0.42, shin = 0.42, foot = 0.13
}

struct Joints {
    var hip, shoulder, neck, head, nose, spine: SIMD2<Double>
    var elbowN, handN, kneeN, ankleN, toeN: SIMD2<Double>
    var elbowF, handF, kneeF, ankleF, toeF: SIMD2<Double>

    var all: [SIMD2<Double>] {
        [hip, shoulder, head + SIMD2(Segment.headR, Segment.headR), head - SIMD2(Segment.headR, Segment.headR),
         elbowN, handN, kneeN, ankleN, toeN, elbowF, handF, kneeF, ankleF, toeF]
    }

    /// A point on the spine curve, 0 = hip, 1 = shoulder.
    func spinePoint(_ t: Double) -> SIMD2<Double> {
        let u = 1 - t
        return u * u * hip + 2 * u * t * spine + t * t * shoulder
    }

    init(_ p: Pose) {
        func unit(_ deg: Double) -> SIMD2<Double> { let r = deg * .pi / 180; return SIMD2(cos(r), sin(r)) }
        hip = p.hip
        shoulder = hip + Segment.torso * unit(p.torso)
        neck = shoulder + Segment.neck * unit(p.head)
        head = neck + Segment.headR * unit(p.head)
        nose = head + Segment.headR * unit(p.head - 90 * p.facing)
        let back = unit(p.torso + 90 * p.facing)
        spine = (hip + shoulder) / 2 + p.bend * 2 * back
        func limb(_ root: SIMD2<Double>, _ a: SIMD2<Double>, _ s: SIMD2<Double>, _ l1: Double, _ l2: Double) -> (SIMD2<Double>, SIMD2<Double>) {
            let m = root + l1 * s.x * unit(a.x)
            return (m, m + l2 * s.y * unit(a.y))
        }
        (elbowN, handN) = limb(shoulder, p.armN, p.scaleArmN, Segment.upperArm, Segment.forearm)
        (elbowF, handF) = limb(shoulder, p.armF, p.scaleArmF, Segment.upperArm, Segment.forearm)
        (kneeN, ankleN) = limb(hip, p.legN, p.scaleLegN, Segment.thigh, Segment.shin)
        (kneeF, ankleF) = limb(hip, p.legF, p.scaleLegF, Segment.thigh, Segment.shin)
        toeN = ankleN + Segment.foot * unit(p.footN)
        toeF = ankleF + Segment.foot * unit(p.footF)
    }
}

extension Move {
    /// The pose at time t (seconds) in the loop. Easing: smoothstep, so every keyframe is a soft stop.
    func pose(at t: Double) -> Pose {
        guard let first = frames.first else { return Catalog.fallbackPose }
        guard frames.count > 1, loopLength > 0 else { return first.pose }
        var x = t.truncatingRemainder(dividingBy: loopLength)
        if x < 0 { x += loopLength }
        // frame i is reached at the end of its duration, coming from frame i-1 (the first from the last)
        for (i, f) in frames.enumerated() {
            if x <= f.duration {
                let from = frames[(i - 1 + frames.count) % frames.count].pose
                let u = f.duration > 0 ? x / f.duration : 1
                return Pose.lerp(from, f.pose, u * u * (3 - 2 * u))
            }
            x -= f.duration
        }
        return frames[frames.count - 1].pose
    }

    /// The box that holds every pose of the loop, with the floor and the props.
    var bounds: CGRect {
        var xs: [Double] = [], ys: [Double] = [0]
        for f in frames {
            for p in Joints(f.pose).all { xs.append(p.x); ys.append(p.y) }
        }
        if let w = props.wall { xs.append(w); ys.append(1.2) }
        let r = CGRect(x: xs.min() ?? 0, y: ys.min() ?? 0, width: (xs.max() ?? 1) - (xs.min() ?? 0), height: (ys.max() ?? 1) - (ys.min() ?? 0))
        return r.insetBy(dx: -0.12, dy: -0.10)
    }

    /// Where each focus area is on the body, for the soft glow.
    func focusPoints(_ j: Joints) -> [SIMD2<Double>] {
        focus.compactMap { f in
            switch f {
            case "neck": return j.neck
            case "lowback": return j.spinePoint(0.22)
            case "thoracic": return j.spinePoint(0.7)
            case "hip": return j.hip
            case "shoulder": return j.shoulder
            case "knee": return j.kneeN
            case "hamstring": return (j.hip + j.kneeN) / 2
            case "breath": return j.spinePoint(0.75)
            default: return nil
            }
        }
    }
}

extension Catalog {
    static let fallbackPose = Pose(hip: SIMD2(0, 0.9), torso: 90, head: 90, bend: 0, facing: 1, armN: SIMD2(-90, -90), armF: SIMD2(-90, -90),
                                   legN: SIMD2(-90, -90), legF: SIMD2(-90, -90), footN: 0, footF: 0,
                                   scaleArmN: SIMD2(1, 1), scaleArmF: SIMD2(1, 1), scaleLegN: SIMD2(1, 1), scaleLegF: SIMD2(1, 1))
}

struct FigureStyle {
    var near = Color(red: 0.96, green: 0.86, blue: 0.70)
    var far = Color(red: 0.96, green: 0.86, blue: 0.70).opacity(0.42)
    var floor = Color.white.opacity(0.18)
    var glow = Color(red: 0.96, green: 0.62, blue: 0.30)
    var prop = Color.white.opacity(0.22)
    var towel = Color(red: 0.55, green: 0.78, blue: 0.95)
    var lineScale: Double = 1
}

/// The figure at one moment. Pure: the same time gives the same picture (the video uses this too).
struct FigureCanvas: View {
    let move: Move
    let time: Double
    var mirrored = false
    var style = FigureStyle()

    var body: some View {
        Canvas { ctx, size in
            draw(in: &ctx, size: size)
        }
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let box = move.bounds
        let s = min(size.width / box.width, size.height / box.height)
        let ox = (size.width - box.width * s) / 2, oy = (size.height - box.height * s) / 2
        func P(_ v: SIMD2<Double>) -> CGPoint {
            var x = ox + (v.x - box.minX) * s
            if mirrored { x = size.width - x }
            return CGPoint(x: x, y: size.height - (oy + (v.y - box.minY) * s))
        }
        let pose = move.pose(at: time)
        let j = Joints(pose)
        let w = s * 0.03 * style.lineScale

        // floor and props
        var floor = Path(); floor.move(to: P(SIMD2(box.minX, 0))); floor.addLine(to: P(SIMD2(box.maxX, 0)))
        ctx.stroke(floor, with: .color(style.floor), style: StrokeStyle(lineWidth: max(1, w * 0.25), lineCap: .round))
        if let wall = move.props.wall {
            var p = Path(); p.move(to: P(SIMD2(wall, 0))); p.addLine(to: P(SIMD2(wall, 1.25)))
            ctx.stroke(p, with: .color(style.prop), style: StrokeStyle(lineWidth: w * 0.45, lineCap: .round))
        }
        if move.props.seat == true {
            let a = P(SIMD2(-0.2, 0.40)), b = P(SIMD2(0.5, 0))
            ctx.fill(Path(roundedRect: CGRect(x: min(a.x, b.x), y: a.y, width: abs(b.x - a.x), height: b.y - a.y), cornerRadius: w * 0.3),
                     with: .color(style.prop.opacity(0.6)))
        }
        if move.props.cushion == true {
            let c = P(j.kneeF)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - w * 2.2, y: P(SIMD2(0, 0)).y - w * 0.9, width: w * 4.4, height: w * 0.9)),
                     with: .color(style.prop))
        }

        // focus glow, breathing with the loop
        let pulse = 0.75 + 0.25 * sin(time * 2 * .pi / 2.4)
        for f in move.focusPoints(j) {
            let c = P(f), r = s * 0.16 * pulse
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                     with: .radialGradient(Gradient(colors: [style.glow.opacity(0.55), style.glow.opacity(0)]),
                                           center: c, startRadius: 0, endRadius: r))
        }

        func line(_ pts: [SIMD2<Double>], _ color: Color, _ width: Double) {
            var p = Path(); p.move(to: P(pts[0])); for q in pts.dropFirst() { p.addLine(to: P(q)) }
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
        // far limbs behind the body
        line([j.hip, j.kneeF, j.ankleF, j.toeF], style.far, w * 0.9)
        line([j.shoulder, j.elbowF, j.handF], style.far, w * 0.8)
        // spine (a curve), neck, head
        var spine = Path(); spine.move(to: P(j.hip)); spine.addQuadCurve(to: P(j.shoulder), control: P(j.spine))
        ctx.stroke(spine, with: .color(style.near), style: StrokeStyle(lineWidth: w * 1.35, lineCap: .round))
        line([j.shoulder, j.neck], style.near, w * 0.85)
        let hc = P(j.head), hr = Segment.headR * s
        ctx.stroke(Path(ellipseIn: CGRect(x: hc.x - hr, y: hc.y - hr, width: 2 * hr, height: 2 * hr)), with: .color(style.near), lineWidth: w * 0.7)
        let nc = P(j.nose)
        ctx.fill(Path(ellipseIn: CGRect(x: nc.x - w * 0.32, y: nc.y - w * 0.32, width: w * 0.64, height: w * 0.64)), with: .color(style.glow))
        // near limbs in front
        line([j.hip, j.kneeN, j.ankleN, j.toeN], style.near, w)
        line([j.shoulder, j.elbowN, j.handN], style.near, w * 0.9)
        if move.props.towel == true {
            line([j.handN, j.toeN], style.towel, w * 0.3)
        }
    }
}

/// The live figure: it moves with the clock. paused stops it on the current frame.
struct FigureView: View {
    let move: Move
    var mirrored = false
    var paused = false
    var style = FigureStyle()
    @State private var start = Date()
    @State private var frozen: Double?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: paused)) { tl in
            FigureCanvas(move: move, time: frozen ?? tl.date.timeIntervalSince(start), mirrored: mirrored, style: style)
        }
        .onChange(of: paused) { _, p in
            if p {
                frozen = Date().timeIntervalSince(start)
            } else {
                if let f = frozen { start = Date().addingTimeInterval(-f) }
                frozen = nil
            }
        }
        .onChange(of: move.id) { start = Date() }
        .accessibilityLabel("\(move.name) hareketinin animasyonu")
    }
}
