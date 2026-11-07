// Widgets: the departure time first, with the next hours and when light comes and dark falls (home and lock screen), the sun (sunrise, sunset, dark, light left) and the
// ride's Live Activity. All read the snapshot the app writes; nothing is fetched here.
import ActivityKit
import SwiftUI
import WidgetKit

struct Entry: TimelineEntry {
    var date: Date
    var snap: Snapshot?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, snap: .preview) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now, snap: Snapshot.load() ?? .preview))
    }
    /// One entry every 15 minutes for six hours, so the shown leg and the countdowns move with the day.
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let snap = Snapshot.load()
        let entries = (0..<24).map { Entry(date: .now.addingTimeInterval(Double($0) * 900), snap: snap) }
        completion(Timeline(entries: entries, policy: .after(.now.addingTimeInterval(6 * 3600))))
    }
}

extension Snapshot {
    /// Before 09:00 the morning, then the evening until 19:00, then tomorrow's morning.
    func current(at d: Date) -> LegSummary? {
        let legs = legs.filter { $0.windowEnd > d }.sorted { $0.windowStart < $1.windowStart }
        return legs.first ?? self.legs.first
    }
}

struct Bars: View {
    var probs: [Double]
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(probs.enumerated()), id: \.offset) { _, p in
                RoundedRectangle(cornerRadius: 2).fill(Palette.rain(p)).frame(height: max(3, 30 * p))
            }
        }
        .frame(height: 30, alignment: .bottom)
    }
}

/// Six hours as small columns: hour, weather symbol, temperature, rain chance bar; dark hours dimmed.
/// Rain chance as text tinted by how wet it is.
struct ProbText: View {
    var p: Double
    var font: Font = .caption.weight(.semibold)
    var body: some View { Text(Fmt.pct(p)).font(font.monospacedDigit()).foregroundStyle(Palette.rain(p)) }
}

/// One commute window: "Sabah 07–09 · %91 · çık 08:30".
struct WindowRow: View {
    var leg: LegSummary
    var now: Date
    var large = false
    var body: some View {
        let tomorrow = Calendar.current.isDateInTomorrow(leg.windowStart) && now < leg.windowStart
        HStack(spacing: 5) {
            Circle().fill(Palette.rain(leg.maxProb)).frame(width: 6, height: 6)
            Text("\(leg.kind == .morning ? "Sabah" : "Akşam") \(leg.kind == .morning ? "07–09" : "16–19")\(tomorrow ? " · yarın" : "")")
                .font((large ? Font.callout : .caption2).weight(.medium)).lineLimit(1)
            Spacer(minLength: 2)
            ProbText(p: leg.maxProb, font: large ? .callout.weight(.semibold) : .caption2.weight(.semibold))
            if let go = leg.bestDeparture {
                Text("çık \(Fmt.t(go))").font((large ? Font.caption : .system(size: 10)).monospacedDigit()).opacity(0.7)
            }
        }
    }
}

extension Snapshot {
    /// Both windows, the coming one first (at night that is tomorrow's morning).
    func windows(at d: Date) -> [LegSummary] {
        legs.filter { $0.kind != .lunch }.sorted { a, b in
            let ea = a.windowEnd > d, eb = b.windowEnd > d
            return ea != eb ? ea : a.windowStart < b.windowStart
        }
    }
}

/// Çıkış: rain now, today's high and low, sunset big in the middle with sunrise and dark beside it,
/// the morning and evening windows with their best departure in small type.
struct RideWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: Entry

    var body: some View {
        let s = entry.snap, now = entry.date
        let sun = s?.lightDay(at: now) ?? SunDay()
        let rise = (sun.sunrise.map { now < $0 } ?? false) || s?.tomorrow == sun ? sun.sunrise : s?.tomorrow.sunrise
        let wins = s?.windows(at: now) ?? []
        let next = wins.first
        switch family {
        case .accessoryInline:
            Text("Yağış \(Fmt.pct(s?.nowProb ?? 0)) · batış \(Fmt.t(sun.sunset))")
        case .accessoryCircular:
            Gauge(value: s?.nowProb ?? 0) { Image(systemName: "sunset.fill") } currentValueLabel: {
                Text(Fmt.t(sun.sunset)).font(.system(size: 11, weight: .semibold).monospacedDigit())
            }
            .gaugeStyle(.accessoryCircular)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("Batış \(Fmt.t(sun.sunset)) · karanlık \(Fmt.t(sun.dusk))").font(.system(size: 13, weight: .semibold).monospacedDigit())
                Text(wins.map { "\($0.kind == .morning ? "Sabah" : "Akşam") \(Fmt.pct($0.maxProb))" }.joined(separator: " · ")).font(.caption2)
                Text("Şimdi \(Fmt.pct(s?.nowProb ?? 0))\(next?.bestDeparture.map { " · çık \(Fmt.t($0))" } ?? "")").font(.caption2)
            }
        case .systemSmall:
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(Fmt.deg(s?.temperature)).font(.headline)
                    Spacer()
                    ProbText(p: s?.nowProb ?? 0)
                }
                Spacer(minLength: 0)
                Text("GÜN BATIMI").font(.system(size: 9, weight: .semibold)).opacity(0.7)
                Text(Fmt.t(sun.sunset)).font(.system(size: 36, weight: .semibold, design: .rounded).monospacedDigit()).minimumScaleFactor(0.7)
                Text("doğuş \(Fmt.t(rise)) · karanlık \(Fmt.t(sun.dusk))").font(.system(size: 10).monospacedDigit()).opacity(0.75)
                Spacer(minLength: 0)
                if let n = next {
                    HStack(spacing: 4) {
                        Text(n.kind == .morning ? "Sabah" : "Akşam").font(.system(size: 11, weight: .medium))
                        ProbText(p: n.maxProb, font: .system(size: 11, weight: .semibold))
                        Spacer(minLength: 0)
                        if let go = n.bestDeparture { Text("çık \(Fmt.t(go))").font(.system(size: 10).monospacedDigit()).opacity(0.7) }
                    }
                }
            }
            .foregroundStyle(.white)
        case .systemLarge:
            VStack(alignment: .leading, spacing: 14) {
                nowBlock(s, large: true)
                Divider().overlay(.white.opacity(0.25))
                sunBlock(sun, rise: rise, large: true).frame(maxWidth: .infinity)
                Divider().overlay(.white.opacity(0.25))
                VStack(spacing: 10) { ForEach(wins, id: \.kind) { WindowRow(leg: $0, now: now, large: true) } }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
        default:
            VStack(spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    nowBlock(s, large: false).frame(width: 96, alignment: .leading)
                    sunBlock(sun, rise: rise, large: false).frame(maxWidth: .infinity)
                }
                VStack(spacing: 3) { ForEach(wins, id: \.kind) { WindowRow(leg: $0, now: now) } }
            }
            .foregroundStyle(.white)
        }
    }

    /// Now: temperature and condition in words, the rain chance this quarter hour, today's high and low.
    private func nowBlock(_ s: Snapshot?, large: Bool) -> some View {
        VStack(alignment: .leading, spacing: large ? 4 : 2) {
            Text("ŞİMDİ").font(.system(size: large ? 11 : 9, weight: .semibold)).opacity(0.7)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Fmt.deg(s?.temperature)).font(.system(size: large ? 40 : 26, weight: .semibold, design: .rounded))
                if large { Text(WMO.word(s?.weatherCode)).font(.title3) }
            }
            if !large { Text(WMO.word(s?.weatherCode)).font(.system(size: 11)).lineLimit(1).opacity(0.85) }
            HStack(spacing: 4) {
                Text("yağış").font(.system(size: large ? 14 : 11)).opacity(0.75)
                ProbText(p: s?.nowProb ?? 0, font: large ? .callout.weight(.semibold) : .system(size: 11, weight: .semibold))
                if large { Spacer(); hiLo(s, large: true) }
            }
            if !large { hiLo(s, large: false) }
        }
    }

    private func hiLo(_ s: Snapshot?, large: Bool) -> some View {
        Text("↑\(Fmt.deg(s?.todayMax))  ↓\(Fmt.deg(s?.todayMin))").font(.system(size: large ? 15 : 11, weight: .medium).monospacedDigit())
    }

    /// Sunset in the middle and large; sunrise next to it, dark small underneath.
    private func sunBlock(_ sun: SunDay, rise: Date?, large: Bool) -> some View {
        VStack(spacing: large ? 4 : 1) {
            Text("GÜN BATIMI").font(.system(size: large ? 11 : 9, weight: .semibold)).opacity(0.7)
            Text(Fmt.t(sun.sunset)).font(.system(size: large ? 72 : 46, weight: .semibold, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.6).lineLimit(1)
            HStack(spacing: large ? 18 : 10) {
                Label(Fmt.t(rise), systemImage: "sunrise.fill").font(.system(size: large ? 16 : 12, weight: .semibold).monospacedDigit())
                Label("karanlık \(Fmt.t(sun.dusk))", systemImage: "moon.fill").font(.system(size: large ? 12 : 10).monospacedDigit()).opacity(0.7)
            }
            .labelStyle(.titleAndIcon).symbolRenderingMode(.multicolor)
        }
    }
}

/// Saatler: the next hours as columns, and beside them when rain comes or goes, the wind, the dark.
struct HoursWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: Entry

    var body: some View {
        let s = entry.snap, now = entry.date
        let hours = (s?.hours ?? []).filter { $0.time.addingTimeInterval(3600) > now }
        let shown = Array(hours.prefix(family == .systemLarge ? 12 : 6))
        let go = s?.windows(at: now).first?.bestDeparture
        VStack(alignment: .leading, spacing: 8) {
            if family == .systemLarge {
                side(shown, s: s, now: now, large: true)
                columns(Array(shown.prefix(6)), go: go)
                if shown.count > 6 { columns(Array(shown.dropFirst(6)), go: go) }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    columns(shown, go: go)
                    side(shown, s: s, now: now, large: false).frame(width: 92, alignment: .leading)
                }
            }
        }
        .foregroundStyle(.white)
    }

    private func columns(_ hs: [HourSummary], go: Date?) -> some View {
        HStack(spacing: 2) {
            ForEach(hs, id: \.time) { h in
                let isGo = go.map { $0 >= h.time && $0 < h.time.addingTimeInterval(3600) } ?? false
                VStack(spacing: 3) {
                    Text(Fmt.t(h.time).prefix(2)).font(.system(size: 11, weight: isGo ? .bold : .regular).monospacedDigit())
                    Text(Fmt.deg(h.temp)).font(.system(size: 13, weight: .semibold))
                    RoundedRectangle(cornerRadius: 2).fill(Palette.rain(h.prob)).frame(width: 7, height: max(3, 30 * h.prob))
                        .frame(height: 30, alignment: .bottom)
                    Text("\(Int((h.prob * 100).rounded()))").font(.system(size: 10).monospacedDigit()).foregroundStyle(Palette.rain(h.prob))
                    Text("\(Int(h.wind))").font(.system(size: 9).monospacedDigit()).opacity(0.6)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 7).fill(.black.opacity(h.dark ? 0.28 : 0)))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(isGo ? 0.8 : 0), lineWidth: 1))
            }
        }
    }

    /// The one thing the strip means: rain starts at, stops at, or stays away.
    private func side(_ hs: [HourSummary], s: Snapshot?, now: Date, large: Bool) -> some View {
        let wetNow = (s?.nowProb ?? 0) >= 0.4
        let change = hs.first { ($0.prob >= 0.4) != wetNow && $0.time > now.addingTimeInterval(-3600) }
        let line: String = {
            if let c = change { return wetNow ? "Yağış \(Fmt.at(c.time)) diniyor" : "Yağış \(Fmt.at(c.time)) başlıyor" }
            return wetNow ? "\(hs.count) saat yağışlı" : "\(hs.count) saat kuru"
        }()
        let wind = hs.map(\.wind).max() ?? 0
        let sun = s?.lightDay(at: now) ?? SunDay()
        return VStack(alignment: .leading, spacing: large ? 4 : 3) {
            Text("ÖNÜMÜZDEKİ SAATLER").font(.system(size: 9, weight: .semibold)).opacity(0.7)
            Text(line).font(.system(size: large ? 20 : 14, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.8)
            Text("rüzgâr en çok \(Int(wind)) km/sa").font(.system(size: large ? 13 : 10)).opacity(0.8)
            Text("karanlık \(Fmt.t(sun.dusk))").font(.system(size: large ? 13 : 10).monospacedDigit()).opacity(0.8)
            Text("üst: sıcaklık · alt: yağış % · rüzgâr").font(.system(size: 8)).opacity(0.5)
        }
    }
}

/// 5 gün: the next five days, one row each: day, high and low on one shared scale, rain chance and amount.
struct DaysWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: Entry

    var body: some View {
        let all = entry.snap?.days ?? []
        let days = Array(all.filter { $0.day > Calendar.current.startOfDay(for: entry.date) }.prefix(5))
        let lo = days.map(\.tMin).min() ?? 0, hi = days.map(\.tMax).max() ?? 1
        let large = family == .systemLarge
        VStack(alignment: .leading, spacing: large ? 20 : 4) {
            Text("ÖNÜMÜZDEKİ 5 GÜN").font(.system(size: large ? 11 : 9, weight: .semibold)).opacity(0.7)
            if days.isEmpty { Text("Uygulamayı bir kez aç").font(.caption) }
            ForEach(days, id: \.day) { d in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(Fmt.short.string(from: d.day)).font(.system(size: large ? 15 : 12, weight: .semibold))
                        if large { Text(WMO.word(d.code)).font(.caption2).opacity(0.7).lineLimit(1) }
                    }
                    .frame(width: large ? 88 : 48, alignment: .leading)
                    Text(Fmt.deg(d.tMin)).font(.system(size: large ? 14 : 12).monospacedDigit()).opacity(0.75).frame(width: 30, alignment: .trailing)
                    GeometryReader { g in
                        let w = g.size.width, span = max(1, hi - lo)
                        Capsule().fill(.white.opacity(0.15)).frame(height: 5)
                            .overlay(alignment: .leading) {
                                Capsule().fill(LinearGradient(colors: [Color(red: 0.55, green: 0.8, blue: 1), Color(red: 1, green: 0.75, blue: 0.4)], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(6, w * (d.tMax - d.tMin) / span), height: 5)
                                    .offset(x: w * (d.tMin - lo) / span)
                            }
                            .frame(maxHeight: .infinity)
                    }
                    .frame(height: 12)
                    Text(Fmt.deg(d.tMax)).font(.system(size: large ? 14 : 12, weight: .semibold).monospacedDigit()).frame(width: 30, alignment: .leading)
                    ProbText(p: d.rainProb, font: .system(size: large ? 14 : 12, weight: .semibold)).frame(width: 36, alignment: .trailing)
                    if large { Text(d.rainMM >= 0.1 ? String(format: "%.0f mm", d.rainMM) : "—").font(.caption.monospacedDigit()).opacity(0.7).frame(width: 40, alignment: .trailing) }
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
    }
}

struct SunWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: Entry

    var body: some View {
        let t = entry.snap?.today ?? SunDay(), m = entry.snap?.tomorrow ?? SunDay()
        let now = entry.date
        let up = (t.sunrise.map { now > $0 } ?? false) && (t.sunset.map { now < $0 } ?? false)
        let left: Double = {
            guard up, let r = t.sunrise, let s = t.sunset else { return 0 }
            return max(0, min(1, s.timeIntervalSince(now) / s.timeIntervalSince(r)))
        }()
        switch family {
        case .accessoryCircular:
            Gauge(value: left) { Image(systemName: up ? "sunset.fill" : "sunrise.fill") } currentValueLabel: {
                Text(Fmt.t(up ? t.sunset : ((t.sunrise.map { now < $0 } ?? false) ? t.sunrise : m.sunrise))).font(.system(size: 11).monospacedDigit())
            }
            .gaugeStyle(.accessoryCircular)
        case .accessoryInline:
            Text(up ? "Batış \(Fmt.t(t.sunset)) · karanlık \(Fmt.t(t.dusk))" : "Doğuş \(Fmt.t((t.sunrise.map { now < $0 } ?? false) ? t.sunrise : m.sunrise))")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("Güneş", systemImage: "sun.horizon.fill").font(.caption2.weight(.semibold))
                Text("↑ \(Fmt.t(t.sunrise))  ↓ \(Fmt.t(t.sunset))").font(.headline.monospacedDigit())
                Text("Karanlık \(Fmt.t(t.dusk)) · yarın ↑ \(Fmt.t(m.sunrise))").font(.caption2)
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: up ? "sun.max.fill" : "moon.stars.fill").symbolRenderingMode(.multicolor)
                    Spacer()
                    if up, let s = t.sunset { Text(s, style: .relative).font(.caption2.monospacedDigit()).multilineTextAlignment(.trailing) }
                }
                Spacer(minLength: 0)
                row("sunrise.fill", "Doğuş", (t.sunrise.map { now < $0 } ?? true) ? t.sunrise : m.sunrise)
                row("sunset.fill", "Batış", t.sunset)
                row("moon.haze.fill", "Karanlık", t.dusk)
            }
            .foregroundStyle(.white)
        }
    }

    private func row(_ sym: String, _ name: String, _ d: Date?) -> some View {
        HStack {
            Image(systemName: sym).symbolRenderingMode(.multicolor).frame(width: 18)
            Text(name).font(.caption)
            Spacer()
            Text(Fmt.t(d)).font(.callout.weight(.semibold).monospacedDigit())
        }
    }
}

struct WidgetSky: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.10, green: 0.22, blue: 0.45), Color(red: 0.36, green: 0.30, blue: 0.55)], startPoint: .top, endPoint: .bottom)
    }
}

struct RideWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UfukRide", provider: Provider()) { e in
            RideWidgetView(entry: e).containerBackground(for: .widget) { WidgetSky() }
        }
        .configurationDisplayName("Bugün")
        .description("Şimdiki yağış, bugünün en yüksek ve en düşük sıcaklığı, gün batımı, doğuş ve kararma, sabah ve akşam yağışı.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct HoursWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UfukHours", provider: Provider()) { e in
            HoursWidgetView(entry: e).containerBackground(for: .widget) { WidgetSky() }
        }
        .configurationDisplayName("Saatler")
        .description("Önümüzdeki saatlerin sıcaklığı, yağışı ve rüzgârı; yağmurun ne zaman başlayıp dineceği.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct DaysWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UfukDays", provider: Provider()) { e in
            DaysWidgetView(entry: e).containerBackground(for: .widget) { WidgetSky() }
        }
        .configurationDisplayName("5 gün")
        .description("Önümüzdeki beş günün en düşük ve en yüksek sıcaklığı, yağış ihtimali.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct SunWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UfukSun", provider: Provider()) { e in
            SunWidgetView(entry: e).containerBackground(for: .widget) { WidgetSky() }
        }
        .configurationDisplayName("Güneş")
        .description("Doğuş, batış, kararma ve kalan ışık.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct RideLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideAttributes.self) { ctx in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("\(ctx.attributes.leg) yolu", systemImage: "bicycle").font(.headline)
                    Spacer()
                    Text("varış \(Fmt.t(ctx.attributes.arrival))").font(.caption.monospacedDigit())
                }
                Text(ctx.state.note).font(.title3.weight(.semibold))
                Bars(probs: ctx.state.probs)
                HStack {
                    Text("\(Fmt.t(ctx.state.slotStart)) → +90 dk").font(.caption2)
                    Spacer()
                    if let d = ctx.state.dusk { Label("Karanlık \(Fmt.t(d))", systemImage: "moon.fill").font(.caption2) }
                    if let f = ctx.state.rideFeel { Text("· \(Fmt.deg(f))").font(.caption2) }
                }
            }
            .padding()
            .foregroundStyle(.white)
            .activityBackgroundTint(Color(red: 0.08, green: 0.14, blue: 0.30))
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Label(ctx.attributes.leg, systemImage: "bicycle") }
                DynamicIslandExpandedRegion(.trailing) { Text(Fmt.t(ctx.attributes.arrival)).monospacedDigit() }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading) { Text(ctx.state.note).font(.headline); Bars(probs: ctx.state.probs) }
                }
            } compactLeading: {
                Image(systemName: (ctx.state.probs.max() ?? 0) >= 0.4 ? "cloud.rain.fill" : "bicycle")
            } compactTrailing: {
                Text("\(Int(((ctx.state.probs.max() ?? 0) * 100).rounded()))%").monospacedDigit()
            } minimal: {
                Image(systemName: (ctx.state.probs.max() ?? 0) >= 0.4 ? "cloud.rain.fill" : "bicycle")
            }
        }
    }
}

@main
struct UfukWidgets: WidgetBundle {
    var body: some Widget {
        RideWidget()
        HoursWidget()
        DaysWidget()
        SunWidget()
        RideLiveActivity()
    }
}
