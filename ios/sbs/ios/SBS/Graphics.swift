// The large graphics: segmented ring, arc gauge, typical band, sparkline, petal wheel, body figure.
import SwiftUI

/// A ring of coloured segments with a large number in the middle (the "score" ring of the Health app).
struct SegmentRing: View {
    struct Part: Identifiable { var id = UUID(); var value: Double; var color: Color }
    var parts: [Part]
    var center: String
    var caption: String
    var lineWidth: CGFloat = 36

    var body: some View {
        let total = max(parts.reduce(0) { $0 + $1.value }, 1)
        let gap = 0.035
        ZStack {
            ForEach(Array(arcs(total: total, gap: gap).enumerated()), id: \.offset) { _, a in
                Circle().trim(from: a.0, to: a.1)
                    .stroke(a.2, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 0) {
                Text(center).font(.system(size: 64, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(caption).font(.footnote.weight(.medium)).foregroundStyle(.secondary)
            }
        }
        .padding(lineWidth / 2)
    }

    private func arcs(total: Double, gap: Double) -> [(Double, Double, Color)] {
        let live = parts.filter { $0.value > 0 }
        guard live.count > 1 else { return live.map { _ in (0, 1, live[0].color) } }
        var out: [(Double, Double, Color)] = []
        var at = 0.0
        let usable = 1 - gap * Double(live.count)
        for p in live {
            let span = max(usable * p.value / total, 0.012)
            out.append((at + gap / 2, at + gap / 2 + span, p.color))
            at += span + gap
        }
        return out
    }
}

/// A half-open arc with a marker dot and a large value (the "Readiness" gauge).
struct ArcGauge: View {
    var fraction: Double          // 0…1, where the dot sits
    var band: ClosedRange<Double>? // the typical part of the arc, 0…1
    var value: String
    var caption: String
    var color: Color

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let lw = w * 0.085
            let r = (w - lw) / 2
            let center = CGPoint(x: w / 2, y: r + lw / 2)
            ZStack {
                arc(0, 1, center, r).stroke(Color.track, style: StrokeStyle(lineWidth: lw, lineCap: .round))
                if let band {
                    arc(band.lowerBound, band.upperBound, center, r).stroke(color.opacity(0.35), style: StrokeStyle(lineWidth: lw, lineCap: .round))
                }
                Circle().fill(color).frame(width: lw * 0.62, height: lw * 0.62)
                    .position(point(min(max(fraction, 0), 1), center, r))
                VStack(spacing: 2) {
                    Text(value).font(.system(size: w * 0.19, weight: .semibold, design: .rounded)).foregroundStyle(color).monospacedDigit()
                    Text(caption).font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                }
                .position(x: center.x, y: center.y - r * 0.22)
            }
        }
        .aspectRatio(1.85, contentMode: .fit)
    }

    private func angle(_ f: Double) -> Angle { .degrees(180 + 180 * f) }
    private func point(_ f: Double, _ c: CGPoint, _ r: CGFloat) -> CGPoint {
        let a = angle(f).radians
        return CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
    }
    private func arc(_ a: Double, _ b: Double, _ c: CGPoint, _ r: CGFloat) -> Path {
        Path { $0.addArc(center: c, radius: r, startAngle: angle(a), endAngle: angle(b), clockwise: false) }
    }
}

/// Dots over a shaded band: where each of the last days sits against the person's own typical range.
struct TypicalBand: View {
    struct Dot: Identifiable { var id: String; var label: String; var value: Double? }
    var dots: [Dot]
    var typical: ClosedRange<Double>?
    var color: Color

    var body: some View {
        let values = dots.compactMap(\.value)
        let lo = min(values.min() ?? 0, typical?.lowerBound ?? .infinity)
        let hi = max(values.max() ?? 1, typical?.upperBound ?? -.infinity)
        let pad = max((hi - lo) * 0.25, 1)
        let range = (lo - pad)...(hi + pad)
        VStack(spacing: 8) {
            GeometryReader { g in
                let h = g.size.height
                let step = g.size.width / CGFloat(max(dots.count, 1))
                let y: (Double) -> CGFloat = { v in h - CGFloat((v - range.lowerBound) / (range.upperBound - range.lowerBound)) * h }
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 6).fill(Color.track.opacity(0.55)).frame(height: 5).offset(y: 0)
                    RoundedRectangle(cornerRadius: 6).fill(Color.track.opacity(0.55)).frame(height: 5).offset(y: h - 5)
                    if let typical {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color.opacity(0.22))
                            .frame(height: max(y(typical.lowerBound) - y(typical.upperBound), 18))
                            .offset(y: y(typical.upperBound))
                    }
                    ForEach(Array(dots.enumerated()), id: \.element.id) { i, d in
                        if let v = d.value {
                            Circle().fill(color).overlay(Circle().stroke(.white, lineWidth: 3))
                                .frame(width: 18, height: 18)
                                .position(x: step * (CGFloat(i) + 0.5), y: y(v))
                        }
                    }
                }
            }
            .frame(height: 150)
            HStack(spacing: 0) {
                ForEach(dots) { d in
                    Text(d.label).font(.caption2.weight(.medium)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
        }
    }
}

/// A small trend line with the reference band behind it.
struct Sparkline: View {
    var values: [Double]
    var low: Double?
    var high: Double?
    var color: Color

    var body: some View {
        GeometryReader { g in
            let all = values + [low, high].compactMap { $0 }
            let lo = all.min() ?? 0, hi = all.max() ?? 1
            let span = max(hi - lo, 0.0001)
            let pts: [CGPoint] = values.enumerated().map { i, v in
                CGPoint(x: values.count < 2 ? g.size.width / 2 : g.size.width * CGFloat(i) / CGFloat(values.count - 1),
                        y: g.size.height * (1 - CGFloat((v - lo) / span)) * 0.84 + g.size.height * 0.08)
            }
            ZStack {
                if low != nil || high != nil {
                    let top = g.size.height * (1 - CGFloat(((high ?? hi) - lo) / span)) * 0.84 + g.size.height * 0.08
                    let bottom = g.size.height * (1 - CGFloat(((low ?? lo) - lo) / span)) * 0.84 + g.size.height * 0.08
                    RoundedRectangle(cornerRadius: 4).fill(Color.good.opacity(0.16))
                        .frame(height: max(bottom - top, 3)).position(x: g.size.width / 2, y: (top + bottom) / 2)
                }
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: first)
                    pts.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                if let last = pts.last { Circle().fill(color).frame(width: 8, height: 8).position(last) }
            }
        }
    }
}

// MARK: - petal wheel ("where things stand")

struct Petal: Shape {
    var angle: Double
    var half: Double
    var inner: CGFloat = 0.20
    var outer: CGFloat = 0.98

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let R = min(rect.width, rect.height) / 2
        func pt(_ r: CGFloat, _ a: Double) -> CGPoint { CGPoint(x: c.x + r * R * CGFloat(cos(a)), y: c.y + r * R * CGFloat(sin(a))) }
        let tip = pt(inner, angle), a = pt(outer * 0.94, angle - half), b = pt(outer * 0.94, angle + half)
        let crown = pt(outer * 1.04, angle)
        let corner = R * 0.085
        var p = Path()
        p.move(to: CGPoint(x: (tip.x + a.x) / 2, y: (tip.y + a.y) / 2))
        p.addArc(tangent1End: a, tangent2End: crown, radius: corner)
        p.addArc(tangent1End: crown, tangent2End: b, radius: corner * 2.4)
        p.addArc(tangent1End: b, tangent2End: tip, radius: corner)
        p.addArc(tangent1End: tip, tangent2End: a, radius: corner * 0.9)
        p.closeSubpath()
        return p
    }
}

struct PetalItem: Identifiable, Hashable {
    var id: String
    var name: String
    var symbol: String
    var color: Color
    var tone: Tone
    var detail: String
}

struct PetalWheel: View {
    var items: [PetalItem]
    var selected: String?
    var onTap: (PetalItem) -> Void

    var body: some View {
        GeometryReader { g in
            let n = max(items.count, 1)
            let half = Double.pi / Double(n) * 0.80
            let R = min(g.size.width, g.size.height) / 2
            ZStack {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    let angle = -Double.pi / 2 + 2 * Double.pi * Double(i) / Double(n)
                    let shape = Petal(angle: angle, half: half)
                    let dim = selected != nil && selected != item.id
                    ZStack {
                        switch item.tone {
                        case .good:
                            shape.fill(item.color)
                        case .watch:
                            shape.fill(item.color.opacity(0.30))
                            shape.stroke(item.color, lineWidth: 2.5)
                        case .attention:
                            shape.fill(item.color.opacity(0.10))
                            shape.stroke(item.color, style: StrokeStyle(lineWidth: 2.5))
                        case .unknown:
                            shape.fill(Color.track.opacity(0.45))
                        }
                        Image(systemName: item.symbol)
                            .font(.system(size: R * 0.13, weight: .semibold))
                            .foregroundStyle(item.tone == .good ? .white : (item.tone == .unknown ? Color.secondary : item.color))
                            .position(x: g.size.width / 2 + R * 0.66 * CGFloat(cos(angle)), y: g.size.height / 2 + R * 0.66 * CGFloat(sin(angle)))
                    }
                    .opacity(dim ? 0.35 : 1)
                    .contentShape(shape)
                    .onTapGesture { onTap(item) }
                    .accessibilityElement()
                    .accessibilityLabel("\(item.name): \(item.tone.areaLabel)")
                    .accessibilityAddTraits(.isButton)
                }
            }
            .animation(.snappy, value: selected)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - body figure

/// A simple front figure. Marks sit on regions; the size of a mark follows the number of records there.
struct BodyFigure: View {
    var marks: [String: Int]
    var selected: String?
    var onTap: (String) -> Void

    static let spots: [(id: String, x: CGFloat, y: CGFloat)] = [
        ("head", 0.50, 0.075), ("neck", 0.50, 0.165), ("chest", 0.50, 0.27), ("arm", 0.215, 0.37), ("abdomen", 0.50, 0.385),
        ("low_back", 0.50, 0.475), ("hand", 0.81, 0.535), ("hip", 0.40, 0.55), ("knee", 0.405, 0.735), ("leg", 0.60, 0.83), ("foot", 0.40, 0.955)]

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let fill = Color.track.opacity(0.75)
            ZStack {
                Circle().fill(fill).frame(width: w * 0.20, height: w * 0.20).position(x: w * 0.5, y: h * 0.075)
                Capsule().fill(fill).frame(width: w * 0.085, height: h * 0.07).position(x: w * 0.5, y: h * 0.16)
                RoundedRectangle(cornerRadius: w * 0.11, style: .continuous).fill(fill).frame(width: w * 0.40, height: h * 0.36).position(x: w * 0.5, y: h * 0.365)
                Capsule().fill(fill).frame(width: w * 0.105, height: h * 0.36).rotationEffect(.degrees(9)).position(x: w * 0.215, y: h * 0.385)
                Capsule().fill(fill).frame(width: w * 0.105, height: h * 0.36).rotationEffect(.degrees(-9)).position(x: w * 0.785, y: h * 0.385)
                Capsule().fill(fill).frame(width: w * 0.165, height: h * 0.44).position(x: w * 0.405, y: h * 0.74)
                Capsule().fill(fill).frame(width: w * 0.165, height: h * 0.44).position(x: w * 0.595, y: h * 0.74)
                ForEach(Self.spots, id: \.id) { s in
                    let n = marks[s.id] ?? 0
                    let on = selected == s.id
                    ZStack {
                        if n > 0 {
                            Circle().fill(Color.attention.opacity(0.22)).frame(width: 30 + CGFloat(min(n, 5)) * 7, height: 30 + CGFloat(min(n, 5)) * 7)
                            Circle().fill(Color.attention).frame(width: 15, height: 15).overlay(Circle().stroke(.white, lineWidth: 2.5))
                        } else {
                            Circle().fill(Color.secondary.opacity(on ? 0.6 : 0.22)).frame(width: 9, height: 9)
                        }
                        if on { Circle().stroke(Color.calm, lineWidth: 2.5).frame(width: 44, height: 44) }
                    }
                    .frame(width: 48, height: 48)
                    .contentShape(Circle())
                    .position(x: w * s.x, y: h * s.y)
                    .onTapGesture { onTap(s.id) }
                    .accessibilityElement()
                    .accessibilityLabel("\(Region.name(s.id)): \(n) kayıt")
                    .accessibilityAddTraits(.isButton)
                }
            }
        }
        .aspectRatio(0.52, contentMode: .fit)
    }
}
