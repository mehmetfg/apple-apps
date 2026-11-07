// The living background: the sky's colour follows the real sun elevation at the commute point, clouds
// drift with the cloud cover, rain falls with the current rate and wind, stars come out after dusk.
import SwiftUI

struct SkyState: Equatable {
    var elevation: Double       // sun, degrees
    var dayFraction: Double     // 0 at sunrise, 1 at sunset (outside: <0 or >1)
    var cloud: Double           // 0…1
    var rain: Double            // mm/h
    var wind: Double            // km/h
    var thunder: Bool

    static let clear = SkyState(elevation: 30, dayFraction: 0.5, cloud: 0.2, rain: 0, wind: 5, thunder: false)
}

extension Store {
    var skyState: SkyState {
        let p = commutePoint
        let e = Sun.elevation(.now, lat: p.latitude, lon: p.longitude)
        var frac = 0.5
        if let r = sunToday.sunrise, let s = sunToday.sunset, s > r { frac = Date.now.timeIntervalSince(r) / s.timeIntervalSince(r) }
        let c = forecast?.current
        let rate = appleNow?.precipitationIntensity ?? ((c?.precipMean ?? 0) * 4 * (c?.modelAgree ?? 0))
        return SkyState(elevation: e, dayFraction: frac, cloud: (c?.cloud ?? 30) / 100, rain: rate, wind: c?.wind ?? 5, thunder: (c?.code ?? 0) >= 95)
    }
}

struct SkyBackground: View {
    var state: SkyState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static func mix(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ t: Double) -> (Double, Double, Double) {
        let t = min(1, max(0, t)); return (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
    }

    /// Two gradient colours from the sun elevation, then greyed by clouds and darkened by rain.
    static func colors(_ s: SkyState) -> (Color, Color) {
        typealias C = (Double, Double, Double)
        let stops: [(Double, C, C)] = [
            (-18, (0.02, 0.03, 0.09), (0.06, 0.08, 0.17)),
            (-10, (0.05, 0.07, 0.19), (0.15, 0.16, 0.34)),
            (-4, (0.13, 0.17, 0.38), (0.80, 0.45, 0.38)),
            (2, (0.22, 0.38, 0.62), (0.96, 0.66, 0.45)),
            (12, (0.20, 0.47, 0.85), (0.58, 0.77, 0.96)),
            (40, (0.12, 0.42, 0.88), (0.50, 0.74, 0.98)),
        ]
        var top = stops[0].1, bottom = stops[0].2
        for i in 1..<stops.count where s.elevation >= stops[i - 1].0 {
            let t = (s.elevation - stops[i - 1].0) / (stops[i].0 - stops[i - 1].0)
            top = mix(stops[i - 1].1, stops[i].1, t); bottom = mix(stops[i - 1].2, stops[i].2, t)
        }
        let grey = s.elevation > -4 ? (0.42, 0.47, 0.54) : (0.07, 0.08, 0.11)
        let g = min(0.75, s.cloud * 0.6 + min(1, s.rain / 3) * 0.3)
        top = mix(top, grey, g); bottom = mix(bottom, grey, g * 0.9)
        let dark = min(0.35, s.rain / 8)
        top = mix(top, (0, 0, 0), dark); bottom = mix(bottom, (0, 0, 0), dark)
        return (Color(red: top.0, green: top.1, blue: top.2), Color(red: bottom.0, green: bottom.1, blue: bottom.2))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { tl in
            let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in draw(&ctx, size, t) }
        }
        .background(LinearGradient(colors: [Self.colors(state).0, Self.colors(state).1], startPoint: .top, endPoint: .bottom))
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.2), value: state)
        .accessibilityHidden(true)
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let w = size.width, h = size.height

        // stars, fading in below the horizon
        let night = min(1, max(0, (-state.elevation - 3) / 8)) * (1 - state.cloud * 0.8)
        if night > 0.02 {
            var rng = SplitMix(seed: 7)
            for _ in 0..<90 {
                let x = rng.next() * w, y = rng.next() * h * 0.6, r = 0.6 + rng.next() * 1.3
                let tw = 0.55 + 0.45 * sin(t * (0.6 + rng.next()) + rng.next() * 6)
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(night * tw * 0.9)))
            }
        }

        // the sun on its arc
        if state.elevation > -8 {
            let f = min(1.1, max(-0.1, state.dayFraction))
            let x = w * (0.08 + 0.84 * f)
            let y = h * 0.58 - sin(min(1, max(0, f)) * .pi) * h * 0.42
            let vis = min(1, max(0, (state.elevation + 6) / 8)) * (1 - state.cloud * 0.7)
            let warm = state.elevation < 8
            var g = ctx
            g.addFilter(.blur(radius: 40))
            g.fill(Path(ellipseIn: CGRect(x: x - 90, y: y - 90, width: 180, height: 180)),
                   with: .color((warm ? Color.orange : Color.yellow).opacity(0.45 * vis)))
            ctx.fill(Path(ellipseIn: CGRect(x: x - 26, y: y - 26, width: 52, height: 52)),
                     with: .color((warm ? Color(red: 1, green: 0.78, blue: 0.5) : Color(red: 1, green: 0.96, blue: 0.82)).opacity(vis)))
        }

        // clouds: soft blobs drifting with the wind
        if state.cloud > 0.05 {
            var c = ctx
            c.addFilter(.blur(radius: 28))
            var rng = SplitMix(seed: 3)
            let n = Int(4 + state.cloud * 10)
            let speed = 4 + state.wind * 0.8
            let tone = state.elevation > -4 ? Color.white : Color(white: 0.55)
            for _ in 0..<n {
                let bw = 140 + rng.next() * 220, bh = 50 + rng.next() * 60
                let x0 = rng.next() * (w + bw)
                let x = (x0 + t * speed * (0.6 + rng.next() * 0.6)).truncatingRemainder(dividingBy: w + bw) - bw
                let y = rng.next() * h * 0.5
                c.fill(Path(ellipseIn: CGRect(x: x, y: y, width: bw, height: bh)),
                       with: .color(tone.opacity(0.18 + state.cloud * 0.35)))
            }
        }

        // rain streaks
        if state.rain > 0.05 {
            var rng = SplitMix(seed: 11)
            let n = Int(min(220, 30 + state.rain * 45))
            let slant = min(0.5, state.wind / 60)
            for _ in 0..<n {
                let x0 = rng.next() * w, speed = 500 + rng.next() * 400, len = 10 + rng.next() * 14
                let y = (rng.next() * h + t * speed).truncatingRemainder(dividingBy: h + 40) - 20
                let x = (x0 + y * slant).truncatingRemainder(dividingBy: w)
                var p = Path(); p.move(to: .init(x: x, y: y)); p.addLine(to: .init(x: x + len * slant, y: y + len))
                ctx.stroke(p, with: .color(.white.opacity(0.28)), lineWidth: 1)
            }
        }

        // a rare flash when thunder is forecast
        if state.thunder, (t.truncatingRemainder(dividingBy: 11)) < 0.12 {
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(0.25)))
        }
    }
}

/// Deterministic random numbers so the stars and clouds keep their places between frames.
struct SplitMix {
    var s: UInt64
    init(seed: UInt64) { s = seed }
    mutating func next() -> Double {
        s &+= 0x9E3779B97F4A7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
    }
}

// MARK: - Liquid Glass

extension View {
    /// Liquid Glass on iOS 26, frosted material before it.
    @ViewBuilder func glassCard(_ radius: CGFloat = 26, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.padding(18)
                .glassEffect(tint.map { Glass.regular.tint($0.opacity(0.35)) }.map { interactive ? $0.interactive() : $0 } ?? (interactive ? .regular.interactive() : .regular),
                             in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            self.padding(18)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).fill((tint ?? .clear).opacity(0.18)).allowsHitTesting(false))
        }
    }

    @ViewBuilder func glassPill(tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            self.padding(.horizontal, 12).padding(.vertical, 7)
                .glassEffect(tint.map { Glass.regular.tint($0.opacity(0.45)) } ?? .regular, in: Capsule())
        } else {
            self.padding(.horizontal, 12).padding(.vertical, 7).background((tint ?? .white).opacity(0.18), in: Capsule())
        }
    }

    /// Cards rise into place the first time they appear.
    func rise(_ delay: Double = 0) -> some View { modifier(Rise(delay: delay)) }
}

private struct Rise: ViewModifier {
    var delay: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 24)
            .scaleEffect(shown || reduceMotion ? 1 : 0.97)
            .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.82).delay(delay)) { shown = true } }
    }
}
