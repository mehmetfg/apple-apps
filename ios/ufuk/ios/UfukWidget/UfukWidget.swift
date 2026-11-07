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

extension Snapshot {
    /// Both windows, the coming one first (at night that is tomorrow's morning).
    func windows(at d: Date) -> [LegSummary] {
        legs.filter { $0.kind != .lunch }.sorted { a, b in
            let ea = a.windowEnd > d, eb = b.windowEnd > d
            return ea != eb ? ea : a.windowStart < b.windowStart
        }
    }
}

/// The three sun times that come next, in order: sunset, dark, sunrise (or sunrise first before dawn).
struct SunEvent: Identifiable {
    var id: String { symbol }
    var symbol: String
    var name: String
    var time: Date
    var tomorrow: Bool
    var main: Bool
}

extension Snapshot {
    func sunEvents(at now: Date) -> [SunEvent] {
        var list: [SunEvent] = []
        for (day, isTomorrow) in [(today, false), (tomorrow, true)] {
            if let t = day.sunrise { list.append(SunEvent(symbol: "sunrise.fill", name: "Doğuş", time: t, tomorrow: isTomorrow, main: false)) }
            if let t = day.sunset { list.append(SunEvent(symbol: "sunset.fill", name: "Batış", time: t, tomorrow: isTomorrow, main: true)) }
            if let t = day.dusk { list.append(SunEvent(symbol: "moon.stars.fill", name: "Karanlık", time: t, tomorrow: isTomorrow, main: false)) }
        }
        var seen = Set<String>()
        return list.filter { $0.time > now }.sorted { $0.time < $1.time }.filter { seen.insert($0.symbol).inserted }
    }
}

/// Bugün: the one thing to know: between which hours the next ride is dry, the temperature then,
/// a bar of the window with the dry stretch marked, and the next sunset, dark and sunrise with their symbols.
struct RideWidgetView: View {
    @Environment(\.widgetFamily) private var envFamily
    var entry: Entry
    /// Set only by the offscreen preview harness; the system gives the family through the environment.
    var forced: WidgetFamily? = nil
    private var family: WidgetFamily { forced ?? envFamily }

    var body: some View {
        let s = entry.snap, now = entry.date
        let leg = s?.current(at: now)
        let dry = leg?.dryWindow(from: now)
        let sun = s?.sunEvents(at: now) ?? []
        switch family {
        case .accessoryInline:
            Text("\(dry.map { "Kuru \(Fmt.t($0.start))–\(Fmt.t($0.end))" } ?? "Kuru aralık yok") · batış \(Fmt.t(sun.first { $0.main }?.time))")
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    Image(systemName: "sunset.fill").font(.system(size: 13))
                    Text(Fmt.t(sun.first { $0.main }?.time)).font(.system(size: 12, weight: .semibold).monospacedDigit())
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label(dry.map { "Kuru \(Fmt.t($0.start))–\(Fmt.t($0.end))" } ?? "Kuru aralık yok", systemImage: "bicycle")
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                Text(departLine(leg, dry, now)).font(.caption2)
                HStack(spacing: 6) {
                    ForEach(sun) { e in
                        HStack(spacing: 2) { Image(systemName: e.symbol); Text(Fmt.t(e.time)).monospacedDigit() }
                    }
                }
                .font(.caption2)
            }
        case .systemSmall:
            VStack(alignment: .leading, spacing: 3) {
                header(leg, now, size: 10)
                dryBlock(leg, dry, now, big: 22)
                if let leg { WindowBar(leg: leg, dry: dry, now: now, height: 8, labels: false) }
                Spacer(minLength: 0)
                // sunset large on its own line, the other two under it
                if let main = sun.first(where: \.main) {
                    HStack(spacing: 4) {
                        Image(systemName: main.symbol).symbolRenderingMode(.multicolor)
                        Text("Batış").font(.system(size: 11)).opacity(0.8)
                        Spacer(minLength: 0)
                        Text(Fmt.t(main.time)).font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                    }
                    .font(.system(size: 14))
                }
                HStack(spacing: 0) {
                    ForEach(sun.filter { !$0.main }) { e in
                        HStack(spacing: 2) {
                            Image(systemName: e.symbol).symbolRenderingMode(.multicolor)
                            Text(Fmt.t(e.time)).monospacedDigit()
                        }
                        if e.id != sun.filter({ !$0.main }).last?.id { Spacer(minLength: 4) }
                    }
                }
                .font(.system(size: 11, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(.white)
        case .systemLarge:
            VStack(alignment: .leading, spacing: 14) {
                header(leg, now, size: 12)
                dryBlock(leg, dry, now, big: 44)
                if let leg { WindowBar(leg: leg, dry: dry, now: now, height: 16, labels: true) }
                Divider().overlay(.white.opacity(0.25))
                sunList(sun, large: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
        default:
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        header(leg, now, size: 10)
                        dryBlock(leg, dry, now, big: 28)
                    }
                    Spacer(minLength: 0)
                    sunList(sun, large: false).frame(width: 140)
                }
                Spacer(minLength: 0)
                if let leg { WindowBar(leg: leg, dry: dry, now: now, height: 10, labels: true) }
            }
            .foregroundStyle(.white)
        }
    }

    /// "AKŞAM ÇIKIŞI" or "YARIN SABAH", with the bicycle.
    private func header(_ leg: LegSummary?, _ now: Date, size: CGFloat) -> some View {
        let tomorrow = leg.map { Calendar.current.isDateInTomorrow($0.windowStart) } ?? false
        let name = leg.map { $0.kind == .morning ? (tomorrow ? "YARIN SABAH" : "SABAH ÇIKIŞI") : (tomorrow ? "YARIN AKŞAM" : "AKŞAM ÇIKIŞI") } ?? "ÇIKIŞ"
        return Label(name, systemImage: "bicycle").font(.system(size: size, weight: .semibold)).opacity(0.75).lineLimit(1)
    }

    private func departLine(_ leg: LegSummary?, _ dry: DryWindow?, _ now: Date) -> String {
        if let d = dry { return "çık \(Fmt.t(d.departure))\(d.temp.map { " · \(Fmt.deg($0))" } ?? "")" }
        if let w = leg?.leastWet(from: now) { return "en az yağış \(Fmt.t(w.0)) · \(Fmt.pct(w.1))\(w.2.map { " · \(Fmt.deg($0))" } ?? "")" }
        return "Uygulamayı bir kez aç"
    }

    /// The dry stretch big, then the departure and the temperature at that moment.
    private func dryBlock(_ leg: LegSummary?, _ dry: DryWindow?, _ now: Date, big: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(dry == nil ? "Yağmursuz aralık yok" : (dry!.whole ? "Hep kuru" : "Yağmursuz"))
                .font(.system(size: big * 0.42, weight: .medium)).foregroundStyle(dry == nil ? Palette.rain(0.7) : Palette.rain(0))
            if let d = dry {
                Text("\(Fmt.t(d.start))–\(Fmt.t(d.end))").font(.system(size: big, weight: .semibold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.6).lineLimit(1)
            }
            Text(departLine(leg, dry, now)).font(.system(size: big * 0.42, weight: .medium).monospacedDigit()).opacity(0.85).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    /// Sunset first-class; the three in the order they come, each with its symbol.
    private func sunList(_ sun: [SunEvent], large: Bool) -> some View {
        VStack(alignment: .leading, spacing: large ? 10 : 5) {
            ForEach(sun) { e in
                HStack(spacing: 6) {
                    Image(systemName: e.symbol).symbolRenderingMode(.multicolor).frame(width: large ? 26 : 18)
                    Text(e.name + (large && e.tomorrow ? " · yarın" : "")).font(.system(size: large ? 15 : 11)).opacity(0.8).lineLimit(1).fixedSize()
                    Spacer(minLength: 2)
                    Text(Fmt.t(e.time)).monospacedDigit()
                        .font(.system(size: e.main ? (large ? 30 : 18) : (large ? 18 : 13), weight: e.main ? .bold : .medium, design: .rounded)).fixedSize()
                }
                .font(.system(size: e.main ? (large ? 22 : 15) : (large ? 16 : 12)))
            }
        }
    }
}

/// The commute window as a bar of quarters coloured by rain, past quarters dimmed, the dry stretch
/// underlined in white and the bicycle on the departure.
struct WindowBar: View {
    var leg: LegSummary
    var dry: DryWindow?
    var now: Date
    var height: CGFloat
    var labels: Bool

    var body: some View {
        VStack(spacing: 3) {
            GeometryReader { g in
                let n = max(1, leg.probs.count), w = g.size.width / CGFloat(n)
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 1) {
                        ForEach(leg.probs.indices, id: \.self) { i in
                            let past = leg.time(i).addingTimeInterval(900) <= now
                            RoundedRectangle(cornerRadius: 2).fill(Palette.rain(leg.probs[i])).opacity(past ? 0.25 : 1)
                        }
                    }
                    .frame(height: height)
                    if let d = dry {
                        let x0 = CGFloat(d.start.timeIntervalSince(leg.slotStart) / 900) * w
                        let x1 = CGFloat(d.end.timeIntervalSince(leg.slotStart) / 900) * w
                        Capsule().fill(.white).frame(width: max(4, x1 - x0), height: 2).offset(x: x0, y: height + 3)
                        Image(systemName: "bicycle").font(.system(size: max(9, height)))
                            .offset(x: CGFloat(d.departure.timeIntervalSince(leg.slotStart) / 900) * w - 6, y: -max(9, height) - 3)
                    }
                }
            }
            .frame(height: height + 6)
            .padding(.top, dry == nil ? 0 : max(9, height) + 2)
            if labels {
                HStack {
                    ForEach(hourMarks, id: \.self) { h in
                        Text(Fmt.t(h).prefix(2)).font(.system(size: 9).monospacedDigit()).opacity(0.6)
                        if h != hourMarks.last { Spacer(minLength: 0) }
                    }
                }
            }
        }
    }

    private var hourMarks: [Date] {
        stride(from: 0, through: leg.probs.count, by: 4).map { leg.time($0) }
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
        .description("Sıradaki çıkışta yağmursuz aralık, çıkış saatindeki sıcaklık; gün batımı, kararma ve doğuş.")
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
