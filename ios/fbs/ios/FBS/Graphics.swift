// The graphics: unit ring (one dot is one share of the money), segmented ring, time strip, sparkline.
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
                Text(center).font(.system(size: 56, weight: .semibold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                Text(caption).font(.footnote.weight(.medium)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, lineWidth * 1.4)
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

/// Unit chart in the manner of the dot rings: `units` dots, each group gets dots in proportion to its value.
struct UnitRing: View {
    struct Part: Identifiable { var id: String; var value: Double; var color: Color }
    var parts: [Part]
    var center: String
    var caption: String
    var units = 100
    var rows = 4

    var body: some View {
        let total = parts.reduce(0) { $0 + max($1.value, 0) }
        // largest remainder: the dots add up to exactly `units`
        let raw = parts.map { total > 0 ? max($0.value, 0) / total * Double(units) : 0 }
        var counts = raw.map { Int($0) }
        let rest = units - counts.reduce(0, +)
        for i in raw.indices.sorted(by: { raw[$0] - Double(counts[$0]) > raw[$1] - Double(counts[$1]) }).prefix(max(rest, 0)) where total > 0 { counts[i] += 1 }
        return Canvas { ctx, size in
            let groups = zip(parts, counts).filter { $0.1 > 0 }
            let cols = groups.reduce(0) { $0 + Int(ceil(Double($1.1) / Double(rows))) } + groups.count
            let R = min(size.width, size.height) / 2
            let inner = R * 0.60
            let pitch = (R - inner) / CGFloat(rows)
            if total == 0 {
                for i in 0..<(units / rows) {
                    for r in 0..<rows {
                        let a = -Double.pi / 2 + 2 * Double.pi * (Double(i) + 0.5) / Double(units / rows)
                        let rr = R - pitch * (CGFloat(r) + 0.5)
                        let dot = pitch * 0.62
                        let p = CGPoint(x: size.width / 2 + rr * CGFloat(cos(a)), y: size.height / 2 + rr * CGFloat(sin(a)))
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x - dot / 2, y: p.y - dot / 2, width: dot, height: dot)), with: .color(Color.track))
                    }
                }
                return
            }
            let step = 2 * Double.pi / Double(max(cols, 1))
            let dot = min(pitch * 0.74, CGFloat(step) * inner * 0.86)
            var col = 0
            for (part, n) in groups {
                for i in 0..<n {
                    let a = -Double.pi / 2 + step * (Double(col + i / rows) + 0.5)
                    let rr = R - pitch * (CGFloat(i % rows) + 0.5)
                    let p = CGPoint(x: size.width / 2 + rr * CGFloat(cos(a)), y: size.height / 2 + rr * CGFloat(sin(a)))
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - dot / 2, y: p.y - dot / 2, width: dot, height: dot)), with: .color(part.color))
                }
                col += Int(ceil(Double(n) / Double(rows))) + 1
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay {
            VStack(spacing: 2) {
                Text(center).font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                Text(caption).font(.footnote.weight(.medium)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 60)
        }
        .accessibilityElement()
        .accessibilityLabel("\(center), \(caption)")
    }
}

/// A time strip: start on the left, end on the right, today as a dot. Used for commitments and warranties.
struct TimeStrip: View {
    var progress: Double
    var color: Color
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.track.opacity(0.6))
                Capsule().fill(color.opacity(0.85)).frame(width: max(g.size.width * progress, height))
                Circle().fill(.white).overlay(Circle().stroke(color, lineWidth: 2.5))
                    .frame(width: height + 6, height: height + 6)
                    .offset(x: min(max(g.size.width * progress - (height + 6) / 2, 0), g.size.width - height - 6))
            }
        }
        .frame(height: height + 6)
    }
}

/// Income and expense side by side for each month, as two thin bars.
struct MonthBars: View {
    var months: [MonthSummary]
    var selected: Date?
    var onTap: (Date) -> Void

    var body: some View {
        let top = max(months.map { max($0.income, $0.expense) }.max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(months) { m in
                let on = selected.map { Calendar.current.isDate($0, equalTo: m.start, toGranularity: .month) } ?? false
                VStack(spacing: 5) {
                    HStack(alignment: .bottom, spacing: 3) {
                        Capsule().fill(Color.money).frame(width: 9, height: max(CGFloat(m.income / top) * 120, 3))
                        Capsule().fill(Color.spend).frame(width: 9, height: max(CGFloat(m.expense / top) * 120, 3))
                    }
                    .opacity(selected == nil || on ? 1 : 0.4)
                    Text(m.start.formatted(.dateTime.month(.narrow).locale(Day.tr))).font(.caption2.weight(on ? .bold : .regular))
                        .foregroundStyle(on ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { onTap(m.start) }
                .accessibilityElement()
                .accessibilityLabel("\(Day.month(m.start)): gelir \(TL.text(m.income)), gider \(TL.text(m.expense))")
                .accessibilityAddTraits(.isButton)
            }
        }
        .frame(height: 140, alignment: .bottom)
    }
}
