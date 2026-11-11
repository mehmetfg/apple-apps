// Listening statistics: a small card on the library's home and, behind it, the İstatistik page (Gün / Hafta / Ay).
// Everything is derived: listening from ListeningLog, marks from the highlights' dates, notes from NoteStore.
// 225 words = 1 page. Since 2026-11-10 the page opens with StatsDashboard (StatsDash.swift): today against the daily
// goal, this week over last week, the run of days, the finished books by name; the period sections follow.
import SwiftUI
import Charts

enum StatSpan: String, CaseIterable, Identifiable {
    case day, week, month
    var id: String { rawValue }
    var name: String {
        switch self {
        case .day: "Gün"
        case .week: "Hafta"
        case .month: "Ay"
        }
    }
}

/// One bar of the chart: a day, a week or a month.
struct StatBucket: Identifiable {
    let start: Date
    let label: String
    let minutes: Double
    let words: Int
    let current: Bool
    var finished = 0
    var id: Date { start }
    var pages: Double { Double(words) / ListeningLog.wordsPerPage }
    var pace: Double { minutes > 0.5 ? Double(words) / minutes : 0 }
}

@MainActor
struct StatsModel {
    let model: AppModel
    var cal: Calendar { var c = Calendar.current; c.firstWeekday = 2; return c }   // weeks start on Monday

    /// Books put into the library in the period.
    func added(_ s: StatSpan) -> Int {
        let (a, z) = range(s)
        let end = cal.date(byAdding: .day, value: 1, to: z) ?? z
        return model.store.documents.filter { $0.addedAt >= a && $0.addedAt < end }.count
    }

    /// The current period: today, this week, this month.
    func range(_ s: StatSpan, offset: Int = 0) -> (Date, Date) {
        let now = Date.now
        switch s {
        case .day:
            let d = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now)) ?? now
            return (d, d)
        case .week:
            let w = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            let a = cal.date(byAdding: .weekOfYear, value: offset, to: w) ?? w
            return (a, cal.date(byAdding: .day, value: 6, to: a) ?? a)
        case .month:
            let m = cal.dateInterval(of: .month, for: now)?.start ?? now
            let a = cal.date(byAdding: .month, value: offset, to: m) ?? m
            let z = cal.date(byAdding: DateComponents(month: 1, day: -1), to: a) ?? a
            return (a, z)
        }
    }

    func buckets(_ s: StatSpan) -> [StatBucket] {
        let count = s == .day ? 14 : s == .week ? 8 : 6
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = s == .month ? "MMM" : "d MMM"
        return (0..<count).reversed().map { i in
            let (a, z) = range(s, offset: -i)
            let t = model.listening.total(from: a, to: z)
            let label = s == .day ? (i == 0 ? "Bugün" : f.string(from: a)) : f.string(from: a)
            return StatBucket(start: a, label: label, minutes: t.seconds / 60, words: t.words, current: i == 0,
                              finished: finished(s, offset: -i).count)
        }
    }

    /// Days of the current period that have come (today included): 1, the days since Monday, the day of the month.
    func daysSoFar(_ s: StatSpan) -> Int {
        max(1, (cal.dateComponents([.day], from: range(s).0, to: cal.startOfDay(for: .now)).day ?? 0) + 1)
    }

    /// Days of the current period on which something was listened.
    func activeDays(_ s: StatSpan) -> Int {
        let a = range(s).0
        return (0..<daysSoFar(s)).filter { i in
            cal.date(byAdding: .day, value: i, to: a).map { model.listening.day($0).seconds / 60 >= Self.streakFloor } ?? false
        }.count
    }

    func total(_ s: StatSpan) -> ListeningDay {
        let (a, z) = range(s)
        return model.listening.total(from: a, to: z)
    }

    /// Daily, weekly and monthly averages over every day since the log began.
    var averages: (days: Int, perDay: ListeningDay)? {
        guard let first = model.listening.firstDay else { return nil }
        let n = max(1, (cal.dateComponents([.day], from: cal.startOfDay(for: first), to: cal.startOfDay(for: .now)).day ?? 0) + 1)
        return (n, model.listening.total(from: first, to: .now))
    }

    func marks(_ s: StatSpan) -> Int {
        let (a, z) = range(s)
        let end = cal.date(byAdding: .day, value: 1, to: z) ?? z
        return model.store.documents.reduce(0) { $0 + $1.highlights.filter { $0.createdAt >= a && $0.createdAt < end }.count }
    }

    func notes(_ s: StatSpan) -> (voice: Int, text: Int, seconds: Double) {
        let (a, z) = range(s)
        let end = cal.date(byAdding: .day, value: 1, to: z) ?? z
        let ns = model.notes.notes.filter { $0.date >= a && $0.date < end }
        return (ns.filter(\.hasVoice).count, ns.filter { !$0.hasVoice }.count, ns.compactMap(\.seconds).reduce(0, +))
    }

    /// Listening by folder (Felsefe, Bilimler…), minutes.
    func folders(_ t: ListeningDay) -> [(name: String, minutes: Double)] {
        var by: [String: Double] = [:]
        for (id, v) in t.docs {
            let doc = UUID(uuidString: id).flatMap { model.store.document($0) }
            by[doc == nil ? "Silinen" : (doc?.folder ?? "Klasörsüz"), default: 0] += v.seconds / 60
        }
        return by.map { ($0.key, $0.value) }.filter { $0.minutes >= 0.5 }.sorted { $0.minutes > $1.minutes }
    }

    func books(_ t: ListeningDay) -> [(doc: DocumentRecord?, title: String, minutes: Double, words: Int)] {
        t.docs.map { id, v in
            let d = UUID(uuidString: id).flatMap { model.store.document($0) }
            return (d, d?.title ?? "Silinen belge", v.seconds / 60, v.words)
        }
        .filter { $0.minutes >= 0.5 }
        .sorted { $0.minutes > $1.minutes }
    }
}

enum StatFormat {
    static func minutes(_ m: Double) -> String {
        let t = Int(m.rounded())
        if t < 60 { return "\(t) dk" }
        return t % 60 == 0 ? "\(t / 60) sa" : "\(t / 60) sa \(t % 60) dk"
    }
    static func number(_ n: Int) -> String { n.formatted(.number.locale(Locale(identifier: "tr_TR"))) }
    static func pages(_ words: Int) -> String {
        let p = Double(words) / ListeningLog.wordsPerPage
        if words == 0 { return "0" }
        return p < 10 ? String(format: "%.1f", p).replacingOccurrences(of: ".", with: ",") : number(Int(p.rounded()))
    }
    static func decimal(_ v: Double) -> String { String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",") }
}


// MARK: - the İstatistik page

/// İstatistik (2026-10-28: one page for everything measured): Okuma (listening, efficiency, production, books) and
/// Yol (the GPS record: maps, km, calories), each by day, week or month.
///
/// 2026-11-10: the page is laid out as the Health app lays out its summary: cards on a grouped ground, each with a
/// coloured title, one large number and a small chart; what was listened to is a large pie that answers a touch;
/// efficiency is three rings; the library is a pie of its shelves.
enum StatsTab: String, CaseIterable, Identifiable {
    case reading, road
    var id: String { rawValue }
    var name: String { self == .reading ? "Okuma" : "Yol" }
}

/// A card of the page: a coloured title with its symbol, a quiet note on the right, the content under them.
struct StatCard<Content: View>: View {
    let title: String
    let icon: String
    let tint: Color
    var note: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Label(title, systemImage: icon).font(.subheadline.weight(.bold)).foregroundStyle(tint)
                Spacer(minLength: 4)
                if let note { Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StatCardGround.color, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

enum StatCardGround {
    static let color = Color(uiColor: .secondarySystemGroupedBackground)
    static let page = Color(uiColor: .systemGroupedBackground)
}

/// A slice of a pie.
struct PieSlice: Identifiable {
    let name: String
    let value: Double
    let color: Color
    var key: String? = nil
    var id: String { name }
}

/// A large pie with its total in the middle. A touch on a slice puts that slice in the middle; the list under it
/// gives every slice its share.
struct PieCard: View {
    let slices: [PieSlice]
    let unit: (Double) -> String
    var centerTitle = "toplam"
    var onPick: ((PieSlice) -> Void)? = nil
    @State private var angle: Double?
    @State private var grown = false

    private var total: Double { slices.reduce(0) { $0 + $1.value } }

    private var picked: PieSlice? {
        guard let angle else { return nil }
        var run = 0.0
        for s in slices { run += s.value; if angle <= run { return s } }
        return slices.last
    }

    var body: some View {
        let sum = max(total, 0.0001)
        VStack(spacing: 16) {
            Chart(slices) { s in
                SectorMark(angle: .value("Pay", s.value), innerRadius: .ratio(0.62),
                           outerRadius: .ratio(picked?.id == s.id ? 1.0 : 0.94), angularInset: 2)
                    .foregroundStyle(s.color.gradient)
                    .cornerRadius(7)
                    .opacity(picked == nil || picked?.id == s.id ? 1 : 0.35)
            }
            .chartAngleSelection(value: $angle)
            .chartLegend(.hidden)
            .chartBackground { _ in
                VStack(spacing: 0) {
                    Text(picked.map { unit($0.value) } ?? unit(total))
                        .font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(picked.map { "\($0.name) · %\(Int(($0.value / sum * 100).rounded()))" } ?? centerTitle)
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .lineLimit(2).multilineTextAlignment(.center)
                }
                .frame(maxWidth: 120)
            }
            .frame(height: 216)
            .scaleEffect(grown ? 1 : 0.86).opacity(grown ? 1 : 0)
            .animation(.smooth(duration: 0.25), value: picked?.id)
            VStack(spacing: 0) {
                ForEach(Array(slices.enumerated()), id: \.element.id) { i, s in
                    Button { onPick?(s) } label: {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(s.color.gradient).frame(width: 14, height: 14)
                            Text(s.name).font(.subheadline).lineLimit(1)
                            Spacer(minLength: 6)
                            Text(unit(s.value)).font(.subheadline.monospacedDigit().weight(.semibold))
                            Text("%\(Int((s.value / sum * 100).rounded()))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                .frame(width: 38, alignment: .trailing)
                            if onPick != nil { Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary) }
                        }
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(onPick == nil)
                    if i < slices.count - 1 { Divider().opacity(0.5) }
                }
            }
        }
        .onAppear { withAnimation(.spring(duration: 0.7, bounce: 0.25)) { grown = true } }
    }
}

/// Rings one inside the other, each a share of its own whole (the outermost first).
struct RingStack: View {
    let rings: [(value: Double, color: Color)]
    var lineWidth: CGFloat = 13
    @State private var shown = 0.0

    var body: some View {
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.offset) { i, r in
                let inset = CGFloat(i) * (lineWidth + 4) + lineWidth / 2
                Circle().stroke(r.color.opacity(0.18), lineWidth: lineWidth).padding(inset)
                Circle().trim(from: 0, to: max(0.003, min(1, r.value) * shown))
                    .stroke(r.color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(inset)
            }
        }
        .onAppear { withAnimation(.spring(duration: 1.0, bounce: 0.2)) { shown = 1 } }
        .accessibilityHidden(true)
    }
}

struct StatsScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent
    @State private var span: StatSpan = .week
    @State private var tab: StatsTab
    @State private var pieByBook = false

    init(tab: StatsTab = .reading) { _tab = State(initialValue: tab) }

    private static let colors: [Color] = [StatTint.violet, StatTint.mint, StatTint.orange, StatTint.sky, StatTint.rose,
                                          .yellow, .indigo, .brown, .teal, .gray]

    var body: some View {
        let s = StatsModel(model: model)
        let t = s.total(span)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Bölüm", selection: $tab) {
                        ForEach(StatsTab.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if tab == .road {
                        Picker("Dönem", selection: $span) {
                            ForEach(StatSpan.allCases) { Text($0.name).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        RoadsPanel(span: $span)
                    } else {
                        StatsDashboard()
                        HStack {
                            Text("Dönem").font(.title3.weight(.bold))
                            Spacer()
                            Picker("Dönem", selection: $span) {
                                ForEach(StatSpan.allCases) { Text($0.name).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 220)
                        }
                        .padding(.top, 10)
                        let b = s.buckets(span)
                        highlights(b)
                        pie(s, t)
                        trend(b)
                        rings(s, t)
                        production(s, t)
                        averages(s)
                        books(s.books(t), total: t.seconds / 60)
                        library

                        Text("Dinleme süresi 22 Ekim 2026'dan beri tutuluyor; işaretler ve notlar eski tarihleriyle sayılır. 225 kelime = 1 sayfa. Seri: en az 5 dakika dinlenen günler.")
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            }
            .background(StatCardGround.page.ignoresSafeArea())
            .task {                                   // test hook: -statstest road opens on Yol
                if CommandLine.arguments.contains("road") { tab = .road }
            }
            .navigationTitle("İstatistik")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
            .animation(.smooth(duration: 0.25), value: span)
            .animation(.smooth(duration: 0.25), value: tab)
        }
    }

    private var periodName: String {
        switch span {
        case .day: "Bugün"
        case .week: "Bu hafta"
        case .month: "Bu ay"
        }
    }

    private var previousName: String {
        switch span {
        case .day: "dün"
        case .week: "geçen hafta"
        case .month: "geçen ay"
        }
    }

    // MARK: four numbers, each with its own small chart

    private func highlights(_ b: [StatBucket]) -> some View {
        let now = b.last, before = b.dropLast().last
        func change(_ v: (StatBucket) -> Double) -> Double? {
            guard let now, let before, v(before) > 0.01 else { return nil }
            return (v(now) - v(before)) / v(before)
        }
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            metricCard("Süre", "clock.fill", StatTint.orange, value: StatFormat.minutes(now?.minutes ?? 0), unit: nil,
                       series: b.map(\.minutes), change: change(\.minutes))
            metricCard("Sayfa", "doc.text.fill", StatTint.sky, value: StatFormat.pages(now?.words ?? 0), unit: "sayfa",
                       series: b.map(\.pages), change: change(\.pages))
            metricCard("Hız", "speedometer", StatTint.violet, value: (now?.pace ?? 0) > 0 ? "\(Int((now?.pace ?? 0).rounded()))" : "—", unit: "kelime/dk",
                       series: b.map(\.pace), change: change(\.pace))
            metricCard("Biten kitap", "checkmark.seal.fill", StatTint.mint, value: "\(now?.finished ?? 0)", unit: "kitap",
                       series: b.map { Double($0.finished) }, change: nil)
        }
    }

    private func metricCard(_ title: String, _ icon: String, _ tint: Color, value: String, unit: String?, series: [Double], change: Double?) -> some View {
        StatCard(title: title, icon: icon, tint: tint) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value).font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText()).lineLimit(1).minimumScaleFactor(0.55)
                    if let unit { Text(unit).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1) }
                }
                Chart(Array(series.enumerated()), id: \.offset) { i, v in
                    BarMark(x: .value("Dönem", String(i)), y: .value(title, v), width: .ratio(0.7))
                        .foregroundStyle(i == series.count - 1 ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color.primary.opacity(0.13)))
                        .cornerRadius(2.5)
                }
                .chartXAxis(.hidden).chartYAxis(.hidden)
                .frame(height: 38)
                .accessibilityHidden(true)
                HStack(spacing: 5) {
                    if let change { DeltaChip(change: change) }
                    Text(change == nil ? periodName.lowercased(with: Locale(identifier: "tr_TR")) : "· " + previousName)
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                }
                .frame(height: 20)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: what was listened to, as a pie

    @ViewBuilder private func pie(_ s: StatsModel, _ t: ListeningDay) -> some View {
        let byFolder = s.folders(t)
        let byBook = s.books(t)
        let slices: [PieSlice] = pieByBook
            ? Self.slices(byBook.map { ($0.title, $0.minutes) })
            : Self.slices(byFolder.map { ($0.name, $0.minutes) })
        StatCard(title: "Neyi dinledin", icon: "chart.pie.fill", tint: StatTint.violet, note: periodName) {
            if slices.isEmpty {
                Text("\(periodName) henüz dinleme yok.").font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Picker("Pay", selection: $pieByBook) {
                    Text("Klasör").tag(false)
                    Text("Kitap").tag(true)
                }
                .pickerStyle(.segmented)
                PieCard(slices: slices, unit: { StatFormat.minutes($0) }, centerTitle: "dinleme")
                    .id(pieByBook)
            }
        }
    }

    /// At most seven slices; the rest are gathered into "Öteki".
    private static func slices(_ items: [(String, Double)]) -> [PieSlice] {
        let sorted = items.filter { $0.1 >= 0.5 }.sorted { $0.1 > $1.1 }
        var out = sorted.prefix(7).enumerated().map { PieSlice(name: $1.0, value: $1.1, color: colors[$0 % colors.count]) }
        let rest = sorted.dropFirst(7).reduce(0) { $0 + $1.1 }
        if rest >= 0.5 { out.append(PieSlice(name: "Öteki", value: rest, color: .gray)) }
        // two books of the same name would share an id
        var seen: [String: Int] = [:]
        return out.map { s in
            seen[s.name, default: 0] += 1
            return seen[s.name]! > 1 ? PieSlice(name: "\(s.name) (\(seen[s.name]!))", value: s.value, color: s.color) : s
        }
    }

    // MARK: the run of periods

    private func trend(_ b: [StatBucket]) -> some View {
        let past = b.filter { !$0.current }
        let mean = past.isEmpty ? 0 : past.reduce(0) { $0 + $1.minutes } / Double(past.count)
        return StatCard(title: span == .day ? "Son 14 gün" : span == .week ? "Son 8 hafta" : "Son 6 ay", icon: "chart.bar.fill", tint: StatTint.orange,
                        note: mean > 0.5 ? "ortalama \(StatFormat.minutes(mean))" : nil) {
            Chart(b) { x in
                BarMark(x: .value("Dönem", x.label), y: .value("Dakika", x.minutes))
                    .foregroundStyle(x.current ? StatTint.hot : StatTint.cool)
                    .cornerRadius(5)
                if mean > 0.5 {
                    RuleMark(y: .value("Ortalama", mean))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        .foregroundStyle(Color.secondary.opacity(0.7))
                }
            }
            .chartYAxisLabel("dakika")
            .chartXAxis {
                AxisMarks { v in
                    AxisValueLabel { if let s = v.as(String.self) { Text(span == .day ? String(s.prefix(2)) : s).font(.system(size: 9)) } }
                }
            }
            .frame(height: 180)
        }
    }

    // MARK: efficiency, as three rings

    private func rings(_ s: StatsModel, _ t: ListeningDay) -> some View {
        let minutes = t.seconds / 60
        let days = s.daysSoFar(span), active = s.activeDays(span)
        let goal = Double(model.settings.dailyGoal * days)
        let goalShare = goal > 0 ? minutes / goal : 0
        let playShare = t.seconds + t.paused > 0 ? t.seconds / (t.seconds + t.paused) : 0
        let dayShare = Double(active) / Double(days)
        let wpm = minutes > 0.5 ? Double(t.words) / minutes : 0
        return StatCard(title: "Verim", icon: "bolt.heart.fill", tint: StatTint.rose, note: periodName) {
            HStack(spacing: 18) {
                RingStack(rings: [(goalShare, Palette.play), (dayShare, StatTint.mint), (playShare, StatTint.sky)])
                    .frame(width: 132, height: 132)
                VStack(alignment: .leading, spacing: 12) {
                    ringRow(Palette.play, "Hedef", "%\(Int((goalShare * 100).rounded()))", "\(StatFormat.minutes(minutes)) / \(StatFormat.minutes(goal))")
                    ringRow(StatTint.mint, "Düzen", "\(active)/\(days) gün", "dinlenen gün")
                    ringRow(StatTint.sky, "Çalma oranı", "%\(Int((playShare * 100).rounded()))", "oturum açıkken sesin çaldığı pay")
                }
            }
            Divider().opacity(0.5)
            HStack {
                fact("speedometer", StatTint.violet, wpm > 0 ? "\(Int(wpm.rounded())) kelime/dk" : "—", "gerçek hız")
                Spacer()
                fact("music.note", StatTint.orange, StatFormat.minutes(t.breaks / 60), "müzik arası")
                Spacer()
                fact("pause.fill", .gray, StatFormat.minutes(t.paused / 60), "duraklama")
            }
        }
    }

    private func ringRow(_ color: Color, _ title: String, _ value: String, _ hint: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(color.gradient).frame(width: 10, height: 10).padding(.top, 5)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value).font(.system(size: 18, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(color)
                    Text(title).font(.caption.weight(.semibold))
                }
                Text(hint).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func fact(_ icon: String, _ color: Color, _ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(value, systemImage: icon).font(.footnote.weight(.semibold).monospacedDigit()).labelStyle(TintedLabel(tint: color))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: production

    private func production(_ s: StatsModel, _ t: ListeningDay) -> some View {
        let marks = s.marks(span)
        let n = s.notes(span)
        let hours = t.seconds / 3600
        return StatCard(title: "Üretim", icon: "highlighter", tint: StatTint.amber, note: periodName) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 14) {
                made("highlighter", StatTint.amber, "\(marks)", "işaret")
                made("mic.fill", StatTint.rose, "\(n.voice)", n.seconds > 0 ? "sesli not · \(StatFormat.minutes(n.seconds / 60))" : "sesli not")
                made("square.and.pencil", StatTint.sky, "\(n.text)", "yazılı not")
                made("text.line.first.and.arrowtriangle.forward", StatTint.violet,
                     t.words > 0 ? StatFormat.decimal(Double(marks) / Double(t.words) * 1000) : "—", "işaret / 1000 kelime")
                made("waveform", StatTint.mint, hours > 0.05 ? StatFormat.decimal(Double(n.voice + n.text) / hours) : "—", "not / saat")
                made("plus.rectangle.on.folder.fill", StatTint.orange, "\(s.added(span))", "eklenen kitap")
            }
        }
    }

    private func made(_ icon: String, _ color: Color, _ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Image(systemName: icon).font(.footnote.weight(.bold)).foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(2).minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: averages

    @ViewBuilder private func averages(_ s: StatsModel) -> some View {
        if let a = s.averages {
            let n = Double(a.days), t = a.perDay
            let minutes = t.seconds / 60
            StatCard(title: "Ortalama", icon: "sum", tint: StatTint.sky, note: "\(a.days) günde") {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                    GridRow {
                        Text("").font(.caption)
                        Text("Günlük").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text("Haftalık").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text("Aylık").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    avgRow("Süre", minutes / n) { StatFormat.minutes($0) }
                    Divider().opacity(0.4)
                    avgRow("Kelime", Double(t.words) / n) { StatFormat.number(Int($0.rounded())) }
                    Divider().opacity(0.4)
                    avgRow("Sayfa", Double(t.words) / n / ListeningLog.wordsPerPage) { StatFormat.decimal($0) }
                    Divider().opacity(0.4)
                    avgRow("Kitap", Double(model.listening.firstDay.map { s.finished(from: $0, to: .now).count } ?? 0) / n) { StatFormat.decimal($0) }
                }
                .font(.subheadline.monospacedDigit())
            }
        }
    }

    private func avgRow(_ name: String, _ perDay: Double, _ f: @escaping (Double) -> String) -> some View {
        GridRow {
            Text(name).foregroundStyle(.secondary)
            Text(f(perDay)).fontWeight(.semibold)
            Text(f(perDay * 7))
            Text(f(perDay * 30.4))
        }
    }

    // MARK: the books of the period

    @ViewBuilder private func books(_ b: [(doc: DocumentRecord?, title: String, minutes: Double, words: Int)], total: Double) -> some View {
        if !b.isEmpty {
            StatCard(title: "Kitaplar", icon: "books.vertical.fill", tint: StatTint.mint, note: "\(b.count) kitap") {
                VStack(spacing: 0) {
                    ForEach(Array(b.enumerated()), id: \.offset) { i, x in
                        HStack(spacing: 12) {
                            if let d = x.doc { CoverView(doc: d, width: 34, showsPlaying: false) }
                            VStack(alignment: .leading, spacing: 5) {
                                Text(x.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                ProgressBar(value: x.doc?.progress ?? 0).frame(height: 4)
                                Text("\(StatFormat.pages(x.words)) sayfa · %\(Int((x.doc?.progress ?? 0) * 100))"
                                     + (x.doc?.isFinished == true ? " · bitti" : ""))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 6)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(StatFormat.minutes(x.minutes)).font(.subheadline.monospacedDigit().weight(.bold))
                                if total > 0.5 {
                                    Text("%\(Int((x.minutes / total * 100).rounded()))").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 10)
                        if i < b.count - 1 { Divider().opacity(0.5) }
                    }
                }
            }
        }
    }

    // MARK: the library, as a pie of its shelves

    private var library: some View {
        let all = model.store.documents
        let reading = all.filter { !$0.isUnread && !$0.isFinished }
        let unread = all.filter(\.isUnread)
        let finished = all.filter(\.isFinished)
        let left = all.filter { !$0.isFinished }.reduce(0.0) { $0 + model.duration(characters: $1.length - $1.position, speed: $1.speed) }
        let words = all.filter { !$0.isFinished }.reduce(0) { $0 + Int(Double($1.wordCount) * (1 - $1.progress)) }
        let slices = [PieSlice(name: "Süren", value: Double(reading.count), color: StatTint.orange, key: "reading"),
                      PieSlice(name: "Okunacak", value: Double(unread.count), color: StatTint.sky, key: "unread"),
                      PieSlice(name: "Bitti", value: Double(finished.count), color: StatTint.mint, key: "finished")].filter { $0.value > 0 }
        return StatCard(title: "Kütüphane", icon: "building.columns.fill", tint: StatTint.sky, note: "\(all.count) kitap") {
            if slices.isEmpty {
                Text("Kütüphane boş.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                PieCard(slices: slices, unit: { "\(Int($0)) kitap" }, centerTitle: "kütüphanede") { s in
                    if let k = s.key { model.settings.homeShelf = k }
                    dismiss()
                }
                HStack(spacing: 10) {
                    Image(systemName: "headphones").foregroundStyle(StatTint.violet)
                    (Text("Dinlenecek ").foregroundStyle(.secondary) + Text(InventoryStrip.hours(left)).fontWeight(.semibold)
                     + Text(" · ≈ \(StatFormat.pages(words)) sayfa").foregroundStyle(.secondary))
                        .font(.footnote)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(StatTint.violet.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}
