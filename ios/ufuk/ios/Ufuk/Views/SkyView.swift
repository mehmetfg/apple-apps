// Gökyüzü: sunrise and sunset in several forms — today's arc with a countdown, the 24-hour light ring
// with the commute on it, the whole year's curve, the next two weeks and the turning points that
// matter for riding (from which day the ride home is dark, the earliest sunset, the shortest day).
import Charts
import SwiftUI

struct YearDay: Identifiable, Hashable, Sendable {
    var id: Date { day }
    var day: Date
    var sun: SunDay
    func hour(_ d: Date?) -> Double? {
        d.map { $0.timeIntervalSince(Calendar.current.startOfDay(for: day)) / 3600 }
    }
}

@MainActor
final class SunYear: ObservableObject {
    @Published private(set) var days: [YearDay] = []
    private var key = ""

    func load(lat: Double, lon: Double) {
        let k = "\(Int(lat * 100))|\(Int(lon * 100))|\(Calendar.current.component(.year, from: .now))|\(Calendar.current.component(.dayOfYear, from: .now))"
        guard k != key else { return }
        key = k
        Task.detached(priority: .userInitiated) {
            let cal = Calendar.current
            let start = cal.startOfDay(for: .now).addingTimeInterval(-40 * 86400)
            let out = (0..<366).map { i -> YearDay in
                let d = cal.startOfDay(for: start.addingTimeInterval(Double(i) * 86400 + 3600))
                return YearDay(day: d, sun: Sun.day(d, lat: lat, lon: lon))
            }
            await MainActor.run { self.days = out }
        }
    }
}

struct SkyView: View {
    @EnvironmentObject var s: Store
    @StateObject private var year = SunYear()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SunArcCard().rise()
                    DayRingCard().rise(0.06)
                    if !year.days.isEmpty {
                        MilestonesCard(days: year.days).rise(0.1)
                        YearChartCard(days: year.days).rise(0.14)
                        FortnightCard(days: Array(year.days.drop { $0.day < Date.now.startOfDay }.prefix(14))).rise(0.18)
                    } else {
                        ProgressView("Yılın güneşi hesaplanıyor").tint(.white).foregroundStyle(.white).glassCard()
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 30)
            }
            .scrollContentBackground(.hidden)
            .background(SkyBackground(state: s.skyState))
            .navigationTitle("Gökyüzü")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear { let p = s.commutePoint; year.load(lat: p.latitude, lon: p.longitude) }
        }
    }
}

// MARK: - today's arc

struct SunArcCard: View {
    @EnvironmentObject var s: Store

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { tl in
            let t = s.sunToday, now = tl.date
            VStack(spacing: 14) {
                ArcShape(sun: t, now: now).frame(height: 170)
                HStack {
                    stat("Şafak", t.dawn, "sun.horizon")
                    stat("Doğuş", t.sunrise, "sunrise.fill")
                    stat("Batış", t.sunset, "sunset.fill")
                    stat("Karanlık", t.dusk, "moon.stars.fill")
                }
                Divider().overlay(.white.opacity(0.3))
                countdown(now)
            }
            .foregroundStyle(.white).glassCard()
        }
    }

    private func stat(_ title: String, _ d: Date?, _ sym: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: sym).symbolRenderingMode(.multicolor).font(.title3)
            Text(Fmt.t(d)).font(.headline.monospacedDigit())
            Text(title).font(.caption2).foregroundStyle(Palette.soft)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func countdown(_ now: Date) -> some View {
        let t = s.sunToday, y = s.sun(on: .now.addingTimeInterval(-86400))
        let delta = Int(t.daylight - y.daylight)
        VStack(spacing: 6) {
            if let ss = t.sunset, now < ss, let r = t.sunrise, now > r {
                Text("Gün batımına \(Fmt.span(ss.timeIntervalSince(now)))").font(.title3.weight(.semibold))
            } else if let d = t.dusk, now < d, let ss = t.sunset, now >= ss {
                Text("Tam karanlığa \(Fmt.span(d.timeIntervalSince(now)))").font(.title3.weight(.semibold))
            } else {
                let next = (t.sunrise.map { now < $0 } ?? false) ? t.sunrise : s.sunTomorrow.sunrise
                Text("Doğuşa \(Fmt.span((next ?? now).timeIntervalSince(now)))").font(.title3.weight(.semibold))
            }
            Text("Gün \(Fmt.span(t.daylight)) · dünden \(delta >= 0 ? "+" : "−")\(abs(delta) / 60) dk \(abs(delta) % 60) sn")
                .font(.footnote).foregroundStyle(Palette.soft)
        }
    }
}

/// The sun's path from sunrise to sunset over a horizon; the dot is the sun now (below the line at night).
struct ArcShape: View {
    var sun: SunDay
    var now: Date

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height, base = h * 0.78, top = h * 0.08
            guard let r = sun.sunrise, let ss = sun.sunset else { return }
            let dayLen = ss.timeIntervalSince(r)
            let span = dayLen + 2 * 3 * 3600                     // 3 hours each side
            func x(_ d: Date) -> CGFloat { CGFloat((d.timeIntervalSince(r) + 3 * 3600) / span) * w }
            func y(_ d: Date) -> CGFloat {
                let f = d.timeIntervalSince(r) / dayLen
                return base - CGFloat(sin(f * .pi)) * (base - top) * (f >= 0 && f <= 1 ? 1 : 0.35)
            }
            // twilight bands under the horizon
            if let dawn = sun.dawn, let dusk = sun.dusk {
                ctx.fill(Path(CGRect(x: x(dawn), y: base, width: x(r) - x(dawn), height: 6)), with: .color(.orange.opacity(0.5)))
                ctx.fill(Path(CGRect(x: x(ss), y: base, width: x(dusk) - x(ss), height: 6)), with: .color(.purple.opacity(0.6)))
            }
            // the path
            var p = Path()
            let steps = 80
            for i in 0...steps {
                let d = r.addingTimeInterval(-3 * 3600 + span * Double(i) / Double(steps))
                let pt = CGPoint(x: x(d), y: y(d))
                i == 0 ? p.move(to: pt) : p.addLine(to: pt)
            }
            ctx.stroke(p, with: .color(.white.opacity(0.45)), style: .init(lineWidth: 1.5, dash: [4, 5]))
            // the travelled part, warm
            var done = Path()
            let upTo = min(max(now, r.addingTimeInterval(-3 * 3600)), ss.addingTimeInterval(3 * 3600))
            let n = Int(Double(steps) * (upTo.timeIntervalSince(r) + 3 * 3600) / span)
            for i in 0...max(0, n) {
                let d = r.addingTimeInterval(-3 * 3600 + span * Double(i) / Double(steps))
                let pt = CGPoint(x: x(d), y: y(d))
                i == 0 ? done.move(to: pt) : done.addLine(to: pt)
            }
            ctx.stroke(done, with: .linearGradient(Gradient(colors: [.orange, .yellow]), startPoint: .zero, endPoint: CGPoint(x: w, y: 0)), lineWidth: 3)
            // horizon
            ctx.stroke(Path { $0.move(to: .init(x: 0, y: base)); $0.addLine(to: .init(x: w, y: base)) }, with: .color(.white.opacity(0.6)), lineWidth: 1)
            // the sun
            let sp = CGPoint(x: x(upTo), y: y(upTo))
            let up = now > r && now < ss
            var glow = ctx; glow.addFilter(.blur(radius: 12))
            glow.fill(Path(ellipseIn: CGRect(x: sp.x - 20, y: sp.y - 20, width: 40, height: 40)), with: .color((up ? Color.yellow : .indigo).opacity(0.8)))
            ctx.fill(Path(ellipseIn: CGRect(x: sp.x - 9, y: sp.y - 9, width: 18, height: 18)), with: .color(up ? .yellow : Color(white: 0.85)))
            // noon marker
            let noon = r.addingTimeInterval(dayLen / 2)
            ctx.draw(Text("öğle \(Fmt.t(noon))").font(.caption2).foregroundStyle(.white.opacity(0.7)), at: CGPoint(x: x(noon), y: top - 2))
        }
        .accessibilityLabel("Güneşin bugünkü yolu")
    }
}

// MARK: - 24-hour ring

struct DayRingCard: View {
    @EnvironmentObject var s: Store
    var body: some View {
        let t = s.sunToday
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "24 saatin ışığı", symbol: "clock")
            HStack(spacing: 18) {
                DayRing(sun: t, marks: [(s.morningDepart, "sabah çıkış"), (s.eveningDepart + s.rideMinutes, "eve varış")])
                    .frame(width: 170, height: 170)
                VStack(alignment: .leading, spacing: 8) {
                    legend(.yellow, "Gündüz", Fmt.span(t.daylight))
                    legend(.orange, "Alacakaranlık", Fmt.span(((t.sunrise ?? .now).timeIntervalSince(t.dawn ?? .now)) + ((t.dusk ?? .now).timeIntervalSince(t.sunset ?? .now))))
                    legend(Color(red: 0.2, green: 0.25, blue: 0.5), "Gece", Fmt.span(86400 - ((t.dusk ?? .now).timeIntervalSince(t.dawn ?? .now))))
                    legend(.white, "Yolculukların", "çentikler")
                }
                .font(.footnote)
            }
        }
        .foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }

    private func legend(_ c: Color, _ name: String, _ v: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(c).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 0) { Text(name); Text(v).foregroundStyle(Palette.soft).font(.caption) }
        }
    }
}

struct DayRing: View {
    var sun: SunDay
    var marks: [(Int, String)]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { tl in
            Canvas { ctx, size in draw(&ctx, size, tl.date) }
        }
        .accessibilityLabel("Günün ışık halkası")
    }

    private func ang(_ h: Double) -> Angle { .degrees(h / 24 * 360 - 90) }       // 00:00 at the top
    private func hour(_ d: Date?) -> Double? { d.map { $0.timeIntervalSince(Calendar.current.startOfDay(for: $0)) / 3600 } }
    private func point(_ c: CGPoint, _ a: Double, _ r: CGFloat) -> CGPoint {
        CGPoint(x: c.x + CGFloat(cos(a)) * r, y: c.y + CGFloat(sin(a)) * r)
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ now: Date) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let r: CGFloat = min(size.width, size.height) / 2 - 10
        func arc(_ a: Double, _ b: Double, _ color: Color) {
            var p = Path()
            p.addArc(center: c, radius: r, startAngle: ang(a), endAngle: ang(b), clockwise: false)
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 16, lineCap: .butt))
        }
        arc(0, 24, Color(red: 0.2, green: 0.25, blue: 0.5))
        if let dw = hour(sun.dawn), let sr = hour(sun.sunrise), let ss = hour(sun.sunset), let dk = hour(sun.dusk) {
            arc(dw, sr, .orange)
            arc(sr, ss, .yellow)
            arc(ss, dk, Color.purple.opacity(0.9))
        }
        for (m, _) in marks {
            let a = ang(Double(m) / 60).radians
            var p = Path()
            p.move(to: point(c, a, r - 12))
            p.addLine(to: point(c, a, r + 12))
            ctx.stroke(p, with: .color(.white), lineWidth: 3)
        }
        let a = ang(hour(now) ?? 0).radians
        var hand = Path()
        hand.move(to: c)
        hand.addLine(to: point(c, a, r - 22))
        ctx.stroke(hand, with: .color(.white), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)), with: .color(.white))
        let labels: [(String, Double)] = [("00", 0), ("06", 6), ("12", 12), ("18", 18)]
        for (lbl, hh) in labels {
            let text = Text(lbl).font(.caption2.bold()).foregroundStyle(.white.opacity(0.75))
            ctx.draw(text, at: point(c, ang(hh).radians, r - 30))
        }
    }
}

// MARK: - turning points

struct MilestonesCard: View {
    @EnvironmentObject var s: Store
    var days: [YearDay]

    struct Item: Identifiable { var id: String { text }; var symbol: String; var text: String; var date: Date? }

    var items: [Item] {
        let today = Date.now.startOfDay
        let ahead = days.filter { $0.day >= today }
        var out: [Item] = []
        let arrive = Double(s.eveningDepart + s.rideMinutes) / 60
        let depart = Double(s.morningDepart) / 60
        let darkHome = { (d: YearDay) in (d.hour(d.sun.dusk) ?? 24) < arrive }
        let darkOut = { (d: YearDay) in (d.hour(d.sun.dawn) ?? 0) > depart }
        if let first = ahead.first {
            if darkHome(first), let end = ahead.first(where: { !darkHome($0) }) {
                out.append(.init(symbol: "light.beacon.max.fill", text: "Eve dönüşün karanlıkta. \(Fmt.day.string(from: end.day))'dan sonra ışıkta.", date: end.day))
            } else if let startDark = ahead.first(where: darkHome) {
                out.append(.init(symbol: "light.beacon.max.fill", text: "Eve dönüşün \(Fmt.day.string(from: startDark.day)) itibarıyla karanlığa kalıyor.", date: startDark.day))
            } else if let earliest = ahead.min(by: { ($0.hour($0.sun.dusk) ?? 99) < ($1.hour($1.sun.dusk) ?? 99) }),
                      let h = earliest.hour(earliest.sun.dusk) {
                out.append(.init(symbol: "sun.haze.fill",
                                 text: "Eve dönüşün yıl boyu ışıkta: en erken kararma \(Fmt.t(earliest.sun.dusk)), varışından \(Int((h - arrive) * 60)) dk sonra.", date: nil))
            }
            if darkOut(first), let end = ahead.first(where: { !darkOut($0) }) {
                out.append(.init(symbol: "sunrise", text: "Sabah çıkışın karanlıkta. \(Fmt.day.string(from: end.day))'dan sonra aydınlıkta.", date: end.day))
            } else if let startDark = ahead.first(where: darkOut) {
                out.append(.init(symbol: "sunrise", text: "Sabah çıkışın \(Fmt.day.string(from: startDark.day)) itibarıyla karanlıkta başlıyor.", date: startDark.day))
            }
        }
        if let e = ahead.min(by: { ($0.hour($0.sun.sunset) ?? 99) < ($1.hour($1.sun.sunset) ?? 99) }) {
            out.append(.init(symbol: "sunset.fill", text: "En erken gün batımı: \(Fmt.day.string(from: e.day)), \(Fmt.t(e.sun.sunset)).", date: e.day))
        }
        if let l = ahead.max(by: { ($0.hour($0.sun.sunrise) ?? 0) < ($1.hour($1.sun.sunrise) ?? 0) }) {
            out.append(.init(symbol: "sunrise.fill", text: "En geç doğuş: \(Fmt.day.string(from: l.day)), \(Fmt.t(l.sun.sunrise)).", date: l.day))
        }
        if let sh = ahead.min(by: { $0.sun.daylight < $1.sun.daylight }) {
            out.append(.init(symbol: "circle.lefthalf.filled", text: "En kısa gün: \(Fmt.day.string(from: sh.day)), \(Fmt.span(sh.sun.daylight)). Sonra günler uzar.", date: sh.day))
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Dönüm noktaları", symbol: "flag.checkered")
            ForEach(items) { i in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: i.symbol).symbolRenderingMode(.multicolor).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(i.text).font(.callout)
                        if let d = i.date { Text(d, style: .relative).font(.caption).foregroundStyle(Palette.soft) }
                    }
                }
            }
            Text("Gün batımı en erkene gündönümünden önce, doğuş en geçe ondan sonra ulaşır: güneşin öğlesi kış boyunca kayar.")
                .font(.caption).foregroundStyle(Palette.soft)
        }
        .foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }
}

// MARK: - the year

struct YearChartCard: View {
    @EnvironmentObject var s: Store
    var days: [YearDay]
    @State private var picked: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Bir yılın ışığı", symbol: "chart.xyaxis.line")
            Chart {
                ForEach(days) { d in
                    if let a = d.hour(d.sun.dawn), let b = d.hour(d.sun.dusk) {
                        AreaMark(x: .value("Gün", d.day), yStart: .value("Şafak", a), yEnd: .value("Karanlık", b), series: .value("k", "alaca"))
                            .foregroundStyle(Color(red: 0.95, green: 0.55, blue: 0.75).opacity(0.55))
                    }
                    if let a = d.hour(d.sun.sunrise), let b = d.hour(d.sun.sunset) {
                        AreaMark(x: .value("Gün", d.day), yStart: .value("Doğuş", a), yEnd: .value("Batış", b), series: .value("k", "gün"))
                            .foregroundStyle(.yellow.opacity(0.75).gradient)
                    }
                }
                RuleMark(y: .value("Sabah çıkış", Double(s.morningDepart) / 60))
                    .foregroundStyle(.white.opacity(0.8)).lineStyle(.init(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .leading) { Text("sabah çıkış").font(.caption2).foregroundStyle(.white) }
                RuleMark(y: .value("Eve varış", Double(s.eveningDepart + s.rideMinutes) / 60))
                    .foregroundStyle(.white.opacity(0.8)).lineStyle(.init(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .bottom, alignment: .leading) { Text("eve varış").font(.caption2).foregroundStyle(.white) }
                RuleMark(x: .value("Bugün", picked ?? Date.now.startOfDay)).foregroundStyle(.white)
            }
            .chartYScale(domain: 4...21)
            .chartYAxis {
                AxisMarks(values: [5, 7, 9, 12, 15, 17, 19, 21]) { v in
                    AxisGridLine().foregroundStyle(.white.opacity(0.15))
                    AxisValueLabel { if let h = v.as(Double.self) { Text(String(format: "%02d:00", Int(h))).foregroundStyle(.white.opacity(0.8)) } }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisGridLine().foregroundStyle(.white.opacity(0.15))
                    AxisValueLabel(format: .dateTime.month(.abbreviated)).foregroundStyle(.white.opacity(0.8))
                }
            }
            .chartXSelection(value: $picked)
            .frame(height: 230)
            if let p = picked ?? Optional(Date.now.startOfDay), let d = days.min(by: { abs($0.day.timeIntervalSince(p)) < abs($1.day.timeIntervalSince(p)) }) {
                Text("\(Fmt.day.string(from: d.day)): doğuş \(Fmt.t(d.sun.sunrise)), batış \(Fmt.t(d.sun.sunset)), karanlık \(Fmt.t(d.sun.dusk)) · \(Fmt.span(d.sun.daylight))")
                    .font(.footnote.monospacedDigit()).foregroundStyle(Palette.soft)
            }
        }
        .foregroundStyle(.white).glassCard()
    }
}

// MARK: - two weeks

struct FortnightCard: View {
    var days: [YearDay]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Önümüzdeki 14 gün", symbol: "calendar")
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Gün"); Text("Doğuş"); Text("Batış"); Text("Karanlık"); Text("Fark")
                }
                .font(.caption.weight(.semibold)).foregroundStyle(Palette.soft)
                ForEach(Array(days.enumerated()), id: \.element.id) { i, d in
                    let prev = i > 0 ? days[i - 1].sun.daylight : nil
                    GridRow {
                        Text(Fmt.short.string(from: d.day)).fontWeight(Calendar.current.isDateInToday(d.day) ? .bold : .regular)
                        Text(Fmt.t(d.sun.sunrise)); Text(Fmt.t(d.sun.sunset)); Text(Fmt.t(d.sun.dusk))
                        Text(prev.map { let x = Int((d.sun.daylight - $0) / 60 * 10) ; return String(format: "%+.1f dk", Double(x) / 10) } ?? "")
                            .foregroundStyle(Palette.soft)
                    }
                    .font(.callout.monospacedDigit())
                }
            }
        }
        .foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }
}
