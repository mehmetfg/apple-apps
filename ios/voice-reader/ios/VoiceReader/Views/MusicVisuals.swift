// Müzik modu's moving backdrops besides the bars (2026-10-28, after an audio-visualizer short the user liked, not a
// copy of it): Aurora (neon ribbons braiding, mirrored on the floor), Damla (a drop on dark water at every beat, its
// rings spreading in perspective), Nabız (a wave packet running across on every beat, leaving its afterglow) and
// Lissajous (a slowly turning neon figure whose shape follows the tempo) Tünel (flying through stars) and Nefes (a slowly breathing mandala, for thinking). All are drawn on a Canvas from the beat's
// time and the microphone's loudness; nothing is stored between frames, so they cost nothing when paused.
import SwiftUI

/// What every visual gets: when the last beat fell, the tempo, the loudness and the beat count.
struct BeatInput {
    let lastBeat: Date
    let bpm: Double
    let level: Double
    let beat: Int
    let paused: Bool

    var period: Double { 60 / max(30, bpm) }
    /// 1 on the beat, falling towards 0 before the next.
    func pulse(_ date: Date) -> Double { exp(-date.timeIntervalSince(lastBeat) / period * 3) }
}

private extension GraphicsContext {
    /// Draws `path` twice: wide and blurred (the glow), then thin and bright.
    func neon(_ path: Path, _ shading: GraphicsContext.Shading, width: CGFloat, glow: CGFloat, opacity: Double = 1) {
        var halo = self
        halo.opacity = opacity * 0.8
        halo.addFilter(.blur(radius: glow))
        halo.stroke(path, with: shading, style: StrokeStyle(lineWidth: width * 3, lineCap: .round, lineJoin: .round))
        var core = self
        core.opacity = opacity
        core.stroke(path, with: shading, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }
}

/// A cheap repeatable random number for a seed (the same speck stays in its place frame after frame).
private func noise(_ n: Int) -> Double {
    let x = sin(Double(n) * 12.9898 + 78.233) * 43758.5453
    return x - floor(x)
}

// MARK: - Aurora

/// Four neon ribbons across the middle, each a sum of slow waves; they swell on the beat and braid round each other.
/// Their colours drift with time; a faint, squashed reflection lies under them.
struct AuroraVisual: View {
    let input: BeatInput

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: input.paused)) { ctx in
            Canvas { g, size in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let p = input.pulse(ctx.date)
                let cy = size.height * 0.46
                let amp = size.height * (0.035 + 0.09 * p + 0.06 * input.level)
                let hue = (t / 40).truncatingRemainder(dividingBy: 1)
                for k in 0..<4 {
                    let path = ribbon(width: size.width, cy: cy, amp: amp * (1 - Double(k) * 0.16), t: t, k: k)
                    let a = Color(hue: (hue + Double(k) * 0.07).truncatingRemainder(dividingBy: 1), saturation: 0.85, brightness: 1)
                    let b = Color(hue: (hue + 0.22 + Double(k) * 0.05).truncatingRemainder(dividingBy: 1), saturation: 0.8, brightness: 1)
                    let shade = GraphicsContext.Shading.linearGradient(Gradient(colors: [b.opacity(0.2), a, b, a.opacity(0.2)]),
                                                                       startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0))
                    g.neon(path, shade, width: k == 0 ? 2.4 : 1.4, glow: 10 + 10 * p, opacity: k == 0 ? 1 : 0.6)
                    // the reflection: the same ribbon upside down, flattened and faint
                    var mirror = g
                    mirror.translateBy(x: 0, y: cy * 2 + size.height * 0.16)
                    mirror.scaleBy(x: 1, y: -0.45)
                    mirror.translateBy(x: 0, y: cy * 0.55)
                    mirror.neon(path, shade, width: 1.2, glow: 14, opacity: 0.16)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func ribbon(width: CGFloat, cy: CGFloat, amp: Double, t: Double, k: Int) -> Path {
        var path = Path()
        let steps = 90
        let phase = Double(k) * 1.7
        for i in 0...steps {
            let x = Double(i) / Double(steps)
            let taper = pow(sin(.pi * x), 1.4)                              // quiet at the edges, wide in the middle
            let y = sin(x * 9 + t * 1.3 + phase) * 0.55 + sin(x * 17 - t * 2.1 + phase * 2) * 0.3 + sin(x * 4 + t * 0.6) * 0.35
            let pt = CGPoint(x: CGFloat(x) * width, y: cy + CGFloat(y * amp * taper))
            i == 0 ? path.move(to: pt) : path.addLine(to: pt)
        }
        return path
    }
}

// MARK: - Damla

/// Dark water seen from above at a slant: every beat a drop falls in the middle, and its rings spread out, thinning
/// and fading; sparks rise from where it fell. Rings of the last eight beats are on the water at once.
struct DropVisual: View {
    let input: BeatInput

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: input.paused)) { ctx in
            Canvas { g, size in
                let since = ctx.date.timeIntervalSince(input.lastBeat)
                let cx = size.width / 2, cy = size.height * 0.62
                let maxR = size.width * 0.75
                let tilt: CGFloat = 0.3                                     // the water's slant: rings are flat ellipses
                // a soft pool of light where the drops fall
                let glow = Path(ellipseIn: CGRect(x: cx - maxR * 0.6, y: cy - maxR * 0.6 * tilt, width: maxR * 1.2, height: maxR * 1.2 * tilt))
                g.fill(glow, with: .radialGradient(Gradient(colors: [Color(red: 0.55, green: 0.2, blue: 0.9).opacity(0.25), .clear]),
                                                   center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: maxR * 0.6))
                for back in 0..<8 {
                    // the ring of the beat `back` beats ago, grown for as long as it has been on the water
                    let age = since + Double(back) * input.period
                    let life = age / (input.period * 8)
                    guard life < 1 else { continue }
                    for wave in 0..<3 {
                        let r = maxR * CGFloat(min(1, life * 1.15)) * (1 - CGFloat(wave) * 0.12)
                        guard r > 4 else { continue }
                        let rect = CGRect(x: cx - r, y: cy - r * tilt, width: r * 2, height: r * 2 * tilt)
                        let hue = 0.72 + 0.18 * life - Double(wave) * 0.04
                        let color = Color(hue: hue.truncatingRemainder(dividingBy: 1), saturation: 0.8, brightness: 1)
                        g.neon(Path(ellipseIn: rect), .color(color), width: CGFloat(2.6 * (1 - life)) + 0.4, glow: 8,
                               opacity: (1 - life) * (wave == 0 ? 0.95 : 0.45))
                    }
                    // grain on the newest rings, like light breaking on the water
                    if back < 2 {
                        let r = maxR * CGFloat(min(1, life * 1.15))
                        for n in 0..<70 {
                            let a = noise(n + back * 97) * 2 * .pi
                            let j = 1 + (noise(n * 7 + back) - 0.5) * 0.12
                            let pt = CGPoint(x: cx + cos(a) * r * CGFloat(j), y: cy + sin(a) * r * tilt * CGFloat(j))
                            g.fill(Path(ellipseIn: CGRect(x: pt.x - 1.2, y: pt.y - 1.2, width: 2.4, height: 2.4)),
                                   with: .color(.white.opacity(0.5 * (1 - life))))
                        }
                    }
                }
                // sparks rising from the last drop
                let s = min(1, since / (input.period * 1.5))
                if s < 1 {
                    for n in 0..<14 {
                        let dx = (noise(n + input.beat * 31) - 0.5) * size.width * 0.3
                        let up = (0.2 + noise(n * 3 + input.beat) * 0.8) * size.height * 0.22 * s
                        let pt = CGPoint(x: cx + CGFloat(dx * s), y: cy - CGFloat(up))
                        g.fill(Path(ellipseIn: CGRect(x: pt.x - 2, y: pt.y - 2, width: 4, height: 4)),
                               with: .color(Color(red: 1, green: 0.8, blue: 0.95).opacity(1 - s)))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Nabız

/// A wave packet runs from left to right once every beat (fast in the middle, as a pulse should be); the trace it
/// leaves stays as a fading afterglow of the last few beats. Green at the edges, gold where it is high.
struct PulseVisual: View {
    let input: BeatInput

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: input.paused)) { ctx in
            Canvas { g, size in
                let since = ctx.date.timeIntervalSince(input.lastBeat)
                let cy = size.height * 0.46
                let shade = GraphicsContext.Shading.linearGradient(
                    Gradient(colors: [Color(red: 0.2, green: 0.95, blue: 0.45), Color(red: 1, green: 0.88, blue: 0.25),
                                      Color(red: 0.2, green: 0.95, blue: 0.45)]),
                    startPoint: CGPoint(x: 0, y: cy), endPoint: CGPoint(x: size.width, y: cy))
                // the flat line under it all
                var base = Path()
                base.move(to: CGPoint(x: 0, y: cy)); base.addLine(to: CGPoint(x: size.width, y: cy))
                g.stroke(base, with: .color(Color(red: 0.2, green: 0.95, blue: 0.45).opacity(0.18)), lineWidth: 1)
                for back in 0..<4 {
                    let travel = (since + Double(back) * input.period) / input.period     // 0 → 1 across the screen
                    let fade = back == 0 ? 1 : 0.4 / Double(back * back)
                    let center = Double(size.width) * (-0.15 + 1.3 * min(1.2, travel))
                    let amp = Double(size.height) * (0.07 + 0.05 * input.level) * (back == 0 ? 1 : 0.8)
                    var path = Path()
                    let steps = 160
                    for i in 0...steps {
                        let x = Double(size.width) * Double(i) / Double(steps)
                        let d = (x - center) / (Double(size.width) * 0.11)
                        let env = exp(-d * d)
                        let y = Double(cy) - sin(d * 9) * amp * env
                        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
                    }
                    g.neon(path, shade, width: back == 0 ? 2.2 : 1.4, glow: 9, opacity: fade)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Lissajous

/// A neon Lissajous figure, slowly turning: its two frequencies follow the tempo (a slow song a calm three-to-two,
/// a fast one a busier figure), it opens up on the beat and a tail of light runs along it.
struct LissajousVisual: View {
    let input: BeatInput

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: input.paused)) { ctx in
            Canvas { g, size in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let p = input.pulse(ctx.date)
                let cx = size.width / 2, cy = size.height * 0.46
                let r = min(size.width, size.height) * (0.3 + 0.05 * p + 0.04 * input.level)
                let (fa, fb): (Double, Double) = input.bpm < 90 ? (3, 2) : input.bpm < 120 ? (5, 4) : (7, 6)
                let spin = t * 0.15
                var path = Path()
                let steps = 600
                for i in 0...steps {
                    let s = Double(i) / Double(steps) * 2 * .pi
                    let x = sin(fa * s + t * 0.25), y = sin(fb * s)
                    let rx = x * cos(spin) - y * sin(spin), ry = x * sin(spin) + y * cos(spin)
                    let pt = CGPoint(x: cx + CGFloat(rx) * r, y: cy + CGFloat(ry) * r)
                    i == 0 ? path.move(to: pt) : path.addLine(to: pt)
                }
                let hue = (t / 30).truncatingRemainder(dividingBy: 1)
                let a = Color(hue: hue, saturation: 0.75, brightness: 1)
                let b = Color(hue: (hue + 0.35).truncatingRemainder(dividingBy: 1), saturation: 0.75, brightness: 1)
                g.neon(path, .linearGradient(Gradient(colors: [a, b]), startPoint: CGPoint(x: cx - r, y: cy - r),
                                             endPoint: CGPoint(x: cx + r, y: cy + r)),
                       width: 1.3, glow: 8 + 8 * p, opacity: 0.55 + 0.45 * p)
                // the running light: a short bright tail along the curve
                let head = (t * 0.12).truncatingRemainder(dividingBy: 1)
                let tail = path.trimmedPath(from: max(0, head - 0.04), to: head)
                g.neon(tail, .color(.white), width: 3, glow: 12)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Tünel

/// Flying through stars: specks come from the middle towards the viewer, longer and brighter as they near; on the
/// beat the flight speeds up for a moment and the light at the far end flares.
struct TunnelVisual: View {
    let input: BeatInput
    private static let count = 220

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: input.paused)) { ctx in
            Canvas { g, size in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let p = input.pulse(ctx.date)
                let cx = size.width / 2, cy = size.height * 0.46
                let reach = Double(max(size.width, size.height)) * 0.75
                // the far light
                let r = CGFloat(30 + 50 * p)
                g.fill(Path(ellipseIn: CGRect(x: cx - r * 2, y: cy - r * 2, width: r * 4, height: r * 4)),
                       with: .radialGradient(Gradient(colors: [Color(red: 0.75, green: 0.6, blue: 1).opacity(0.25 + 0.4 * p), .clear]),
                                             center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r * 2))
                // the flight's distance: steady, plus a push on every beat
                let travel = t * 0.18 + Double(input.beat) * 0.06 + (1 - p) * 0.06
                for n in 0..<Self.count {
                    let angle = noise(n) * 2 * .pi
                    let z = (noise(n * 13) + travel).truncatingRemainder(dividingBy: 1)   // 0 far … 1 here
                    let d = pow(z, 2.2) * reach
                    let len = (6 + 40 * z) * (1 + 1.5 * p)
                    let a = CGPoint(x: cx + CGFloat(cos(angle) * d), y: cy + CGFloat(sin(angle) * d))
                    let b = CGPoint(x: cx + CGFloat(cos(angle) * (d + len)), y: cy + CGFloat(sin(angle) * (d + len)))
                    var s = Path(); s.move(to: a); s.addLine(to: b)
                    let hue = 0.6 + 0.25 * noise(n * 5)
                    g.stroke(s, with: .color(Color(hue: hue, saturation: 0.35 + 0.4 * z, brightness: 1).opacity(min(1, z * 1.6))),
                             style: StrokeStyle(lineWidth: CGFloat(0.6 + 2.2 * z), lineCap: .round))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Nefes

/// For thinking rather than moving: a mandala of overlapping circles (the old flower figure) turning very slowly, that
/// opens over four beats and closes over the next four, like a long breath. The beat itself only brightens it a
/// little; the eye follows the breath, not the drum.
struct BreathVisual: View {
    let input: BeatInput

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: input.paused)) { ctx in
            Canvas { g, size in draw(&g, size: size, at: ctx.date) }
        }
        .allowsHitTesting(false)
    }

    private func draw(_ g: inout GraphicsContext, size: CGSize, at date: Date) {
                let t = date.timeIntervalSinceReferenceDate
                let p = input.pulse(date)
                // one breath = eight beats: in for four, out for four (smooth, never a jump)
                let cycle = input.period * 8
                let breath: Double = 0.5 - 0.5 * cos(t / cycle * 2 * Double.pi)
                let cx = size.width / 2, cy = size.height * 0.46
                let unit: CGFloat = min(size.width, size.height) * CGFloat(0.1 + 0.06 * breath)
                let spin = t * 0.02
                let hue: Double = 0.55 + 0.12 * sin(t / 50)
                let color = Color(hue: hue, saturation: 0.45, brightness: 1)
                // the flower: a ring of six circles round one, then twelve round those, each ring turning its own way
                var petals = Path()
                petals.addEllipse(in: CGRect(x: cx - unit, y: cy - unit, width: unit * 2, height: unit * 2))
                for ring in 1...2 {
                    let n = ring * 6
                    let dir = ring == 1 ? 1.0 : -0.6
                    for k in 0..<n {
                        let a = Double(k) / Double(n) * 2 * .pi + spin * dir
                        let d = unit * CGFloat(ring) * CGFloat(0.85 + 0.15 * breath)
                        let c = CGPoint(x: cx + CGFloat(cos(a)) * d, y: cy + CGFloat(sin(a)) * d)
                        petals.addEllipse(in: CGRect(x: c.x - unit, y: c.y - unit, width: unit * 2, height: unit * 2))
                    }
                }
                var halo = g
                halo.opacity = 0.35 + 0.2 * breath
                halo.addFilter(.blur(radius: 10))
                halo.stroke(petals, with: .color(color), lineWidth: 2)
                g.stroke(petals, with: .color(color.opacity(0.35 + 0.25 * breath + 0.15 * p)), lineWidth: 0.8)
                // the outer boundary breathes too, and a single point travels round it, slowly
                let rOut = unit * 3.2
                let outer = Path(ellipseIn: CGRect(x: cx - rOut, y: cy - rOut, width: rOut * 2, height: rOut * 2))
                g.stroke(outer, with: .color(color.opacity(0.18 + 0.12 * breath)), lineWidth: 1)
                let a = t / (cycle * 2) * 2 * .pi
                let dot = CGPoint(x: cx + CGFloat(cos(a)) * rOut, y: cy + CGFloat(sin(a)) * rOut)
                var spark = g
                spark.addFilter(.blur(radius: 4))
                spark.fill(Path(ellipseIn: CGRect(x: dot.x - 5, y: dot.y - 5, width: 10, height: 10)), with: .color(.white.opacity(0.8)))
                // the word of the moment: in, out
                let inhale = sin(t / cycle * 2 * .pi) > 0
                g.draw(Text(inhale ? "nefes al" : "nefes ver").font(.system(size: 13, weight: .medium, design: .serif))
                        .foregroundStyle(color.opacity(0.35)),
                       at: CGPoint(x: cx, y: cy + rOut + 30))
    }
}
