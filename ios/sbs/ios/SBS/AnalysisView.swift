// Analiz: the lab values as unit charts. One dot is one measured value.
//  · DotRing     every current marker as a dot, grouped by area, coloured by status
//  · RangeStrips one row for each area; each tick shows where a value sits against its own range
//  · tiles       share in range, and how many values moved toward or away from their range since the previous test
import SwiftUI

struct DotRing: View {
    struct Group { var color: Color; var tones: [Tone] }
    var groups: [Group]
    var center: String
    var caption: String
    var rows = 3

    var body: some View {
        Canvas { ctx, size in
            let slots = groups.reduce(0) { $0 + Int(ceil(Double($1.tones.count) / Double(rows))) + 1 }
            guard slots > 0 else { return }
            let R = min(size.width, size.height) / 2
            let step = 2 * Double.pi / Double(slots)
            let inner = R * 0.62
            let pitch = (R - inner) / CGFloat(rows)
            let d = min(pitch * 0.82, CGFloat(step) * inner * 0.86)
            var slot = 0
            for g in groups {
                for (i, tone) in g.tones.enumerated() {
                    let a = -Double.pi / 2 + step * (Double(slot + i / rows) + 0.5)
                    let r = R - pitch * (CGFloat(i % rows) + 0.5)
                    let p = CGPoint(x: size.width / 2 + r * CGFloat(cos(a)), y: size.height / 2 + r * CGFloat(sin(a)))
                    let rect = CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)
                    switch tone {
                    case .good: ctx.fill(Path(ellipseIn: rect), with: .color(g.color))
                    case .watch:
                        ctx.fill(Path(ellipseIn: rect), with: .color(Color.watch))
                    case .attention:
                        ctx.fill(Path(ellipseIn: rect), with: .color(Color.attention))
                    case .unknown: ctx.fill(Path(ellipseIn: rect), with: .color(Color.track))
                    }
                }
                slot += Int(ceil(Double(g.tones.count) / Double(rows))) + 1
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay {
            VStack(spacing: 0) {
                Text(center).font(.system(size: 54, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(caption).font(.footnote.weight(.medium)).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(center) \(caption)")
    }
}

/// Where each value sits against its own laboratory range: the shaded zone is "in range" for every marker.
struct RangeStrip: View {
    var markers: [Marker]
    var color: Color

    /// 0 = lower bound, 1 = upper bound; clamped to −0.45…1.45 so far values still show at the edge.
    static func position(_ m: Marker) -> Double? {
        guard let v = m.lastValue else { return nil }
        switch (m.refLow, m.refHigh) {
        case let (lo?, hi?) where hi > lo: return min(max((v - lo) / (hi - lo), -0.45), 1.45)
        case let (nil, hi?) where hi > 0: return min(max(v / hi, -0.45), 1.45)
        case let (lo?, nil) where lo > 0: return v >= lo ? 0.5 : max(v / lo - 1, -0.45)
        default: return nil
        }
    }

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let x: (Double) -> CGFloat = { p in w * CGFloat((p + 0.5) / 2.0) }
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 5).fill(Color.track.opacity(0.35)).frame(width: w, height: h)
                RoundedRectangle(cornerRadius: 5).fill(Color.good.opacity(0.16)).frame(width: x(1) - x(0), height: h).offset(x: x(0))
                ForEach(markers) { m in
                    if let p = Self.position(m) {
                        let tone = Tone(status: m.status)
                        Capsule().fill(tone == .good ? color : tone.color)
                            .frame(width: tone == .good ? 3 : 4.5, height: tone == .good ? h * 0.62 : h)
                            .position(x: x(p), y: h / 2)
                    }
                }
            }
        }
        .frame(height: 22)
    }
}

struct DeltaChip: View {
    var text: String
    var tone: Tone
    var body: some View {
        Text(text).font(.caption2.weight(.bold)).monospacedDigit()
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(tone.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 5)).foregroundStyle(tone.color)
    }
}

struct AnalysisCards: View {
    var d: Derived

    static let order = ["heart", "metabolism", "liver", "kidney", "blood", "immune", "thyroid", "muscle"]
    static let names = ["heart": "Kalp ve damar", "metabolism": "Metabolizma", "liver": "Karaciğer", "kidney": "Böbrek", "blood": "Kan",
                        "immune": "Bağışıklık", "thyroid": "Tiroid", "muscle": "Kas"]

    /// Cool tones only: red and orange are kept for "out of range" and "borderline".
    static let palette: [String: Color] = [
        "heart": Color(light: 0x7C5CFF, dark: 0x9D85FF), "metabolism": Color(light: 0x18A8B8, dark: 0x4CCAD8),
        "liver": Color(light: 0x8D7B68, dark: 0xB09E8A), "kidney": Color(light: 0x2F7BF5, dark: 0x5C9BFF),
        "blood": Color(light: 0x4B50C8, dark: 0x7479EE), "immune": Color(light: 0x2FAF62, dark: 0x57CF85),
        "thyroid": Color(light: 0x00968F, dark: 0x2FC0B8), "muscle": Color(light: 0x6E6E78, dark: 0x9A9AA6)]
    private func color(_ area: String) -> Color { Self.palette[area] ?? .calm }
    private func rank(_ m: Marker) -> Int { m.status == "attention" ? 0 : (m.status == "watch" ? 1 : 2) }

    var body: some View {
        let cur = d.current
        let areas = Self.order.filter { a in cur.contains { $0.area == a } }
        let grouped = areas.map { a in (a, cur.filter { $0.area == a }.sorted { rank($0) < rank($1) }) }
        let good = cur.filter { $0.status == "in" }.count
        let better = cur.filter { $0.course == "better" }.count, worse = cur.filter { $0.course == "worse" }.count
        VStack(alignment: .leading, spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Göstergeler").font(.headline)
                        Spacer()
                        Text(Day.short(d.lastLab)).font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(alignment: .center, spacing: 16) {
                        DotRing(groups: grouped.map { .init(color: color($0.0), tones: $0.1.map { Tone(status: $0.status) }) },
                                center: "\(cur.count)", caption: "değer")
                            .frame(maxWidth: 190)
                        VStack(spacing: 7) {
                            ForEach(grouped, id: \.0) { area, ms in
                                let out = ms.filter { $0.status != "in" }.count
                                HStack(spacing: 6) {
                                    Circle().fill(color(area)).frame(width: 8, height: 8)
                                    Text(Self.names[area] ?? area).font(.caption).lineLimit(1)
                                    Spacer(minLength: 2)
                                    Text("\(ms.count)").font(.caption.weight(.semibold)).monospacedDigit()
                                    DeltaChip(text: out == 0 ? "✓" : "\(out)", tone: out == 0 ? .good : (ms.contains { $0.status == "attention" } ? .attention : .watch))
                                        .frame(width: 26)
                                }
                            }
                        }
                    }
                    Text("Bir nokta bir tahlil değeri. Alan renginde: aralıkta · turuncu: sınırda · kırmızı: aralık dışında.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                tile("Aralıkta", "%\(cur.isEmpty ? 0 : Int((Double(good) / Double(cur.count) * 100).rounded()))", "\(good)/\(cur.count)", .good)
                tile("Aralığa yaklaşan", "\(better)", "önceki tahlile göre", .good)
                tile("Uzaklaşan", "\(worse)", "önceki tahlile göre", worse > 0 ? .attention : .good)
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Aralığa göre dağılım").font(.headline)
                        Spacer()
                        Text("alt sınır  ·  üst sınır").font(.caption2).foregroundStyle(.secondary)
                    }
                    ForEach(grouped, id: \.0) { area, ms in
                        HStack(spacing: 10) {
                            Text(Self.names[area] ?? area).font(.caption).frame(width: 92, alignment: .leading).lineLimit(1)
                            RangeStrip(markers: ms, color: color(area))
                        }
                    }
                    Text("Yeşil bölge her değerin kendi laboratuvar aralığı. Çizgi bölgenin dışındaysa değer aralık dışında; kenardaki çizgi çok uzakta demek.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func tile(_ title: String, _ value: String, _ note: String, _ tone: Tone) -> some View {
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Text(value).font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(tone.color)
                Text(note).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

struct AnalysisView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var health: Health

    var body: some View {
        let d = Derived(store, health)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                AnalysisCards(d: d)
                SectionTitle(text: "Aralık dışındakiler")
                ForEach(d.outOfRange.sorted { ($0.status == "attention" ? 0 : 1) < ($1.status == "attention" ? 0 : 1) }) { MarkerCard(marker: $0, state: d.state) }
            }
            .padding(.horizontal, 18).padding(.bottom, 100)
        }
        .sbsGround()
        .navigationTitle("Analiz")
        .navigationBarTitleDisplayMode(.inline)
    }
}
