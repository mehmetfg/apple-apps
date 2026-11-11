// The day measured against a goal (2026-11-10: "günlük okuma miktarı; bu hafta günlük barlar; geçen haftayla
// karşılaştırma; geçen hafta üç kitap bitirdim desin; daha renkli, hareketli").
//
//   TodayCard        the library's home, on top: today's ring, the week's seven bars, the run of days, the week so far
//   StatsDashboard   the head of İstatistik: today, this week against last week, records, finished books, 17 weeks
//
// Everything is derived from ListeningLog (minutes, words per day) and from the books' own `finishes` dates; the only
// new stored value is the goal (Settings.dailyGoal, minutes a day).
import SwiftUI
import Charts

struct DayStat: Identifiable, Equatable {
    let date: Date
    let minutes: Double
    let words: Int
    var id: Date { date }
    var pages: Double { Double(words) / ListeningLog.wordsPerPage }
}

struct FinishedBook: Identifiable {
    let doc: DocumentRecord
    let at: Date
    var id: String { "\(doc.id.uuidString)-\(at.timeIntervalSince1970)" }
}

extension StatsModel {
    /// A day counts towards the run of days once this much was listened.
    static let streakFloor = 5.0

    /// Monday … Sunday of the week `offset` weeks from this one.
    func week(_ offset: Int = 0) -> [DayStat] {
        let (a, _) = range(.week, offset: offset)
        return (0..<7).map { i in
            let d = cal.date(byAdding: .day, value: i, to: a) ?? a
            let x = model.listening.day(d)
            return DayStat(date: d, minutes: x.seconds / 60, words: x.words)
        }
    }

    var today: DayStat {
        let x = model.listening.day(.now)
        return DayStat(date: cal.startOfDay(for: .now), minutes: x.seconds / 60, words: x.words)
    }

    /// The run of days (today not yet reached does not break it), the longest run, and the best day.
    var records: (streak: Int, best: Int, top: DayStat?) {
        guard let first = model.listening.firstDay else { return (0, 0, nil) }
        var run = 0, best = 0
        var top: DayStat?
        var d = cal.startOfDay(for: first)
        let end = cal.startOfDay(for: .now)
        while d <= end {
            let x = model.listening.day(d)
            let m = x.seconds / 60
            if m >= Self.streakFloor { run += 1; best = max(best, run) } else if d < end { run = 0 }
            if m > (top?.minutes ?? 0) { top = DayStat(date: d, minutes: m, words: x.words) }
            guard let n = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = n
        }
        return (run, best, top)
    }

    /// This week up to today against the same days of last week: minutes, and the change as a share (nil when last
    /// week had nothing to compare with).
    var weekDelta: (now: Double, before: Double, change: Double?) {
        let n = (cal.dateComponents([.day], from: range(.week).0, to: cal.startOfDay(for: .now)).day ?? 0) + 1
        let now = week(0).prefix(n).reduce(0) { $0 + $1.minutes }
        let before = week(-1).prefix(n).reduce(0) { $0 + $1.minutes }
        return (now, before, before >= 1 ? (now - before) / before : nil)
    }

    /// Books heard to their end between two days (both included), newest first. A book read twice counts twice.
    func finished(from a: Date, to z: Date) -> [FinishedBook] {
        let start = cal.startOfDay(for: a)
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: z)) ?? z
        return model.store.documents
            .flatMap { d in d.finishes.filter { $0 >= start && $0 < end }.map { FinishedBook(doc: d, at: $0) } }
            .sorted { $0.at > $1.at }
    }

    func finished(_ s: StatSpan, offset: Int = 0) -> [FinishedBook] {
        let (a, z) = range(s, offset: offset)
        return finished(from: a, to: z)
    }

    /// The unfinished book nearest its end, and the listening left in it.
    var nearest: (doc: DocumentRecord, left: TimeInterval)? {
        model.store.documents.filter { !$0.isFinished && !$0.isUnread && $0.length > 0 }
            .max { $0.progress < $1.progress }
            .map { ($0, model.duration(characters: max(0, $0.length - $0.position), speed: $0.speed)) }
    }
}

enum StatTint {
    static let orange = Color(red: 1.0, green: 0.62, blue: 0.20)
    static let sky = Color(red: 0.30, green: 0.70, blue: 1.0)
    static let violet = Color(red: 0.52, green: 0.42, blue: 0.98)
    static let mint = Color(red: 0.20, green: 0.80, blue: 0.62)
    static let rose = Color(red: 1.0, green: 0.40, blue: 0.56)
    static let amber = Color(red: 0.98, green: 0.70, blue: 0.10)
    static let hot = LinearGradient(colors: [orange, Palette.play], startPoint: .top, endPoint: .bottom)
    static let cool = LinearGradient(colors: [sky, violet], startPoint: .top, endPoint: .bottom)
    static let done = LinearGradient(colors: [mint, Color(red: 0.10, green: 0.62, blue: 0.50)], startPoint: .top, endPoint: .bottom)

    /// A bar's colour: today warm, a day that reached the goal green, the others cool.
    static func bar(today: Bool, reached: Bool) -> LinearGradient { today ? hot : reached ? done : cool }

    static let weekdays = ["Pzt", "Sal", "Çar", "Per", "Cum", "Cmt", "Paz"]
    static let dayMonth: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMM"
        return f
    }()
}

/// The day's ring: how much of the goal is heard. It fills from empty when it appears; at the goal it turns green.
struct GoalRing<Center: View>: View {
    let progress: Double
    var lineWidth: CGFloat = 9
    @ViewBuilder var center: () -> Center
    @State private var shown = 0.0

    var body: some View {
        let reached = progress >= 1
        ZStack {
            Circle().stroke(Color.primary.opacity(0.09), lineWidth: lineWidth)
            Circle().trim(from: 0, to: min(1, max(0.002, shown)))
                .stroke(reached ? AnyShapeStyle(AngularGradient(colors: [StatTint.mint, .green, StatTint.mint], center: .center))
                                : AnyShapeStyle(AngularGradient(colors: [StatTint.orange, Palette.play, StatTint.rose, StatTint.orange], center: .center)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: (reached ? Color.green : Palette.play).opacity(0.35), radius: 5)
            center()
        }
        .padding(lineWidth / 2)
        .onAppear { withAnimation(.spring(duration: 0.9, bounce: 0.2)) { shown = progress } }
        .onChange(of: progress) { _, p in withAnimation(.smooth(duration: 0.5)) { shown = p } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Günlük hedefin yüzde \(Int((min(progress, 9.99) * 100).rounded()))")
    }
}

/// "▲ %18" against last week, green up, orange down.
struct DeltaChip: View {
    let change: Double?

    var body: some View {
        if let c = change {
            let up = c >= 0
            Label("%\(Int((abs(c) * 100).rounded()))", systemImage: up ? "arrow.up.right" : "arrow.down.right")
                .font(.caption2.weight(.bold)).monospacedDigit()
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .foregroundStyle(up ? Color.green : StatTint.orange)
                .background((up ? Color.green : StatTint.orange).opacity(0.15), in: Capsule())
                .accessibilityLabel("Geçen haftanın aynı günlerine göre yüzde \(Int((abs(c) * 100).rounded())) \(up ? "fazla" : "az")")
        }
    }
}

/// "5 gün": the run of days, a small flame.
struct StreakChip: View {
    let days: Int

    var body: some View {
        if days >= 2 {
            Label("\(days) gün", systemImage: "flame.fill")
                .font(.caption2.weight(.bold)).monospacedDigit()
                .padding(.horizontal, 7).padding(.vertical, 3)
                .foregroundStyle(StatTint.orange)
                .background(StatTint.orange.opacity(0.15), in: Capsule())
                .accessibilityLabel("\(days) gündür aralıksız dinliyorsun")
        }
    }
}

/// Seven small bars, Monday to Sunday, measured against the goal; they grow when they appear.
struct WeekBars: View {
    let days: [DayStat]
    let goal: Double
    @State private var grown = false

    var body: some View {
        let top = max(goal, days.map(\.minutes).max() ?? 0, 1)
        let today = Calendar.current.startOfDay(for: .now)
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(days.enumerated()), id: \.element.id) { i, d in
                let isToday = d.date == today, future = d.date > today
                VStack(spacing: 3) {
                    GeometryReader { g in
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                .fill(future || d.minutes < 0.5 ? AnyShapeStyle(Color.primary.opacity(0.10))
                                      : AnyShapeStyle(StatTint.bar(today: isToday, reached: d.minutes >= goal)))
                                .frame(width: min(g.size.width, 18), height: max(4, g.size.height * (grown ? d.minutes / top : 0)))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    Text(String(StatTint.weekdays[i % 7].prefix(1)))
                        .font(.system(size: 9, weight: isToday ? .heavy : .medium))
                        .foregroundStyle(isToday ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)
                .animation(.spring(duration: 0.6, bounce: 0.25).delay(Double(i) * 0.04), value: grown)
            }
        }
        .onAppear { grown = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bu haftanın günleri: " + zip(StatTint.weekdays, days).map { "\($0) \(Int($1.minutes.rounded())) dakika" }.joined(separator: ", "))
    }
}

// MARK: - the home card

/// Today on the library's home: the ring, what is left to the goal, the week's bars, and the week so far against the
/// last one. A tap opens İstatistik.
struct TodayCard: View {
    @Environment(AppModel.self) private var model
    var onStats: () -> Void

    var body: some View {
        let s = StatsModel(model: model)
        let goal = Double(model.settings.dailyGoal)
        let today = s.today
        let rec = s.records
        let delta = s.weekDelta
        let done = s.finished(.week).count
        let left = goal - today.minutes
        Button(action: onStats) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 16) {
                    GoalRing(progress: today.minutes / goal) {
                        VStack(spacing: -3) {
                            Text("\(Int(today.minutes.rounded()))")
                                .font(.system(size: 27, weight: .bold, design: .rounded)).monospacedDigit()
                                .contentTransition(.numericText(value: today.minutes))
                            Text("dk").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 88, height: 88)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Text("Bugün").font(.caption.weight(.bold)).foregroundStyle(.secondary).textCase(.uppercase)
                            Spacer(minLength: 0)
                            StreakChip(days: rec.streak)
                        }
                        Text(left > 0.5 ? "Hedefe \(StatFormat.minutes(left)) kaldı" : "Hedef tamam" + (left < -0.5 ? " · +\(StatFormat.minutes(-left))" : ""))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(left > 0.5 ? Color.primary : Color.green)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text("\(StatFormat.pages(today.words)) sayfa · hedef \(StatFormat.minutes(goal))")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        WeekBars(days: s.week(0), goal: goal).frame(height: 40)
                    }
                }
                Divider().opacity(0.35)
                HStack(spacing: 8) {
                    (Text("Bu hafta ").foregroundStyle(.secondary) + Text(StatFormat.minutes(delta.now)).fontWeight(.bold))
                        .font(.footnote).lineLimit(1)
                    DeltaChip(change: delta.change)
                    Spacer(minLength: 0)
                    if done > 0 {
                        Label("\(done) kitap bitti", systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.semibold)).foregroundStyle(StatTint.violet).lineLimit(1)
                    }
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(GlassPanel(cornerRadius: 20))
        .padding(.horizontal, 14)
        .animation(.smooth(duration: 0.3), value: Int(today.minutes))
        .accessibilityHint("İstatistiği açar")
    }
}

// MARK: - the head of İstatistik

struct StatsDashboard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accent) private var accent
    @State private var weekOffset = 0
    @State private var pages = false                // the week's bars in pages instead of minutes
    @State private var picked: String?
    @State private var grown = false

    var body: some View {
        let s = StatsModel(model: model)
        VStack(alignment: .leading, spacing: 16) {
            hero(s)
            weekCard(s)
            recordTiles(s)
            finishedBooks(s)
            heat(s)
        }
        .onAppear { withAnimation(.spring(duration: 0.8, bounce: 0.2).delay(0.1)) { grown = true } }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(StatCardGround.color, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // today: the ring, the numbers, the goal
    private func hero(_ s: StatsModel) -> some View {
        let goal = Double(model.settings.dailyGoal)
        let t = s.today
        let left = goal - t.minutes
        let day = model.listening.day(.now)
        let wpm = t.minutes > 0.5 ? Int((Double(t.words) / t.minutes).rounded()) : 0
        return card {
            HStack(spacing: 18) {
                GoalRing(progress: t.minutes / goal, lineWidth: 13) {
                    VStack(spacing: -2) {
                        Text("\(Int(t.minutes.rounded()))")
                            .font(.system(size: 38, weight: .bold, design: .rounded)).monospacedDigit()
                            .contentTransition(.numericText(value: t.minutes))
                        Text("/ \(model.settings.dailyGoal) dk").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 132, height: 132)
                VStack(alignment: .leading, spacing: 8) {
                    Text(left > 0.5 ? "Hedefe \(StatFormat.minutes(left)) kaldı" : "Bugünün hedefi tamam")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(left > 0.5 ? Color.primary : Color.green)
                        .lineLimit(2).minimumScaleFactor(0.8)
                    fact("doc.text.fill", StatTint.sky, "\(StatFormat.pages(t.words)) sayfa")
                    fact("text.word.spacing", StatTint.violet, "\(StatFormat.number(t.words)) kelime")
                    if wpm > 0 { fact("speedometer", StatTint.orange, "\(wpm) kelime/dk") }
                    if !day.docs.isEmpty { fact("books.vertical.fill", StatTint.mint, "\(day.docs.count) kitaptan") }
                    Menu {
                        Picker("Günlük hedef", selection: Binding(get: { model.settings.dailyGoal }, set: { model.settings.dailyGoal = $0 })) {
                            ForEach([15, 20, 30, 45, 60, 75, 90, 120, 150, 180, 240], id: \.self) { Text(StatFormat.minutes(Double($0))).tag($0) }
                        }
                    } label: {
                        Label("Hedef \(StatFormat.minutes(goal))", systemImage: "target")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).frame(height: 28)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }
                    .accessibilityLabel("Günlük hedef: \(StatFormat.minutes(goal)). Değiştir")
                }
            }
        }
    }

    private func fact(_ icon: String, _ color: Color, _ text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.caption).foregroundStyle(color).frame(width: 16)
            Text(text).font(.subheadline.monospacedDigit()).lineLimit(1)
        }
    }

    // a week, day by day, over the week before it
    private func weekCard(_ s: StatsModel) -> some View {
        let goal = Double(model.settings.dailyGoal)
        let this = s.week(weekOffset), last = s.week(weekOffset - 1)
        let today = Calendar.current.startOfDay(for: .now)
        let total = this.reduce(0) { $0 + $1.minutes }, before = last.reduce(0) { $0 + $1.minutes }
        let delta = weekOffset == 0 ? s.weekDelta.change : (before >= 1 ? (total - before) / before : nil)
        let value: (DayStat) -> Double = { pages ? $0.pages : $0.minutes }
        let reachedDays = this.filter { $0.minutes >= goal }.count
        return card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Button { withAnimation(.smooth(duration: 0.3)) { weekOffset -= 1; picked = nil } } label: {
                        Image(systemName: "chevron.left").font(.subheadline.weight(.bold)).frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("Önceki hafta")
                    VStack(alignment: .leading, spacing: 1) {
                        Text(weekName(this)).font(.caption.weight(.bold)).foregroundStyle(.secondary).textCase(.uppercase)
                        HStack(spacing: 8) {
                            Text(pages ? "\(StatFormat.pages(this.reduce(0) { $0 + $1.words })) sayfa" : StatFormat.minutes(total))
                                .font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit()
                                .contentTransition(.numericText())
                            DeltaChip(change: delta)
                        }
                    }
                    Spacer(minLength: 0)
                    Button { withAnimation(.smooth(duration: 0.3)) { weekOffset += 1; picked = nil } } label: {
                        Image(systemName: "chevron.right").font(.subheadline.weight(.bold)).frame(width: 32, height: 32)
                    }
                    .disabled(weekOffset >= 0).opacity(weekOffset >= 0 ? 0.25 : 1)
                    .accessibilityLabel("Sonraki hafta")
                }
                .buttonStyle(.plain)

                Chart {
                    ForEach(Array(last.enumerated()), id: \.offset) { i, d in
                        BarMark(x: .value("Gün", StatTint.weekdays[i]), y: .value("Önceki hafta", value(d) * (grown ? 1 : 0)),
                                width: .ratio(0.82), stacking: .unstacked)
                            .foregroundStyle(Color.primary.opacity(0.11))
                            .cornerRadius(6)
                    }
                    ForEach(Array(this.enumerated()), id: \.offset) { i, d in
                        BarMark(x: .value("Gün", StatTint.weekdays[i]), y: .value("Bu hafta", value(d) * (grown ? 1 : 0)),
                                width: .ratio(0.46), stacking: .unstacked)
                            .foregroundStyle(StatTint.bar(today: d.date == today, reached: d.minutes >= goal))
                            .cornerRadius(6)
                            .opacity(picked == nil || picked == StatTint.weekdays[i] ? 1 : 0.4)
                    }
                    if !pages {
                        RuleMark(y: .value("Hedef", goal))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(Color.green.opacity(0.75))
                            .annotation(position: .top, alignment: .trailing, spacing: 2) {
                                Text("hedef").font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.green)
                            }
                    }
                }
                .chartXSelection(value: $picked)
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
                .frame(height: 170)
                .animation(.smooth(duration: 0.35), value: pages)
                .animation(.smooth(duration: 0.35), value: weekOffset)

                if let p = picked, let i = StatTint.weekdays.firstIndex(of: p) {
                    let d = this[i], b = last[i]
                    Text("\(StatTint.dayMonth.string(from: d.date)): \(StatFormat.minutes(d.minutes)) · \(StatFormat.pages(d.words)) sayfa   ·   önceki \(p): \(StatFormat.minutes(b.minutes))")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                } else {
                    HStack(spacing: 12) {
                        legend(AnyShapeStyle(StatTint.cool), weekOffset == 0 ? "bu hafta" : "seçili hafta")
                        legend(AnyShapeStyle(Color.primary.opacity(0.2)), "önceki: \(StatFormat.minutes(before))")
                        Spacer(minLength: 0)
                        Text("\(reachedDays)/7 gün hedefte").font(.caption2.weight(.semibold)).foregroundStyle(reachedDays > 0 ? Color.green : .secondary)
                    }
                }
                Picker("Ölçü", selection: $pages) {
                    Text("Dakika").tag(false)
                    Text("Sayfa").tag(true)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private func legend(_ style: AnyShapeStyle, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(style).frame(width: 10, height: 10)
            Text(text).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func weekName(_ days: [DayStat]) -> String {
        switch weekOffset {
        case 0: return "Bu hafta"
        case -1: return "Geçen hafta"
        default:
            guard let a = days.first?.date, let z = days.last?.date else { return "" }
            return "\(StatTint.dayMonth.string(from: a)) – \(StatTint.dayMonth.string(from: z))"
        }
    }

    // the run of days, the longest run, the best day
    private func recordTiles(_ s: StatsModel) -> some View {
        let r = s.records
        return HStack(spacing: 10) {
            record("flame.fill", "\(r.streak)", "gün seri", [StatTint.orange, Palette.play])
            record("trophy.fill", "\(r.best)", "en uzun seri", [StatTint.violet, StatTint.rose])
            record("bolt.fill", r.top.map { StatFormat.minutes($0.minutes) } ?? "—",
                   r.top.map { "en iyi gün · " + StatTint.dayMonth.string(from: $0.date) } ?? "en iyi gün", [StatTint.sky, StatTint.mint])
        }
    }

    private func record(_ icon: String, _ value: String, _ label: String, _ colors: [Color]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).font(.subheadline.weight(.bold))
                .symbolEffect(.bounce, value: grown)
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption2.weight(.semibold)).opacity(0.9).lineLimit(2).minimumScaleFactor(0.8)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .padding(12)
        .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // finished books, week by week, by name
    private func finishedBooks(_ s: StatsModel) -> some View {
        let this = s.finished(.week), last = s.finished(.week, offset: -1)
        let month = s.finished(.month)
        let earlier = month.filter { m in !this.contains { $0.id == m.id } && !last.contains { $0.id == m.id } }
        return card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Biten kitaplar", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(StatTint.violet)
                    Spacer()
                    Text("bu ay \(month.count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                if this.isEmpty && last.isEmpty && earlier.isEmpty {
                    Text("Bu ay henüz biten kitap yok.").font(.subheadline).foregroundStyle(.secondary)
                }
                finishedRow("Bu hafta", this)
                finishedRow("Geçen hafta", last)
                finishedRow("Bu ay, daha önce", earlier)
                if let n = s.nearest {
                    HStack(spacing: 10) {
                        Image(systemName: "flag.checkered").foregroundStyle(StatTint.orange)
                        (Text("Bitişe en yakın: ").foregroundStyle(.secondary) + Text(n.doc.title).fontWeight(.semibold)
                         + Text(" · %\(Int(n.doc.progress * 100)) · \(Format.duration(n.left)) kaldı").foregroundStyle(.secondary))
                            .font(.footnote).lineLimit(2)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(StatTint.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    @ViewBuilder private func finishedRow(_ title: String, _ books: [FinishedBook]) -> some View {
        if !books.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(title) · \(books.count) kitap bitirdin").font(.subheadline.weight(.semibold))
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(books) { b in
                            VStack(alignment: .leading, spacing: 4) {
                                CoverView(doc: b.doc, width: 62, showsPlaying: false)
                                Text(b.doc.title).font(.caption2.weight(.semibold)).lineLimit(2)
                                Text(StatTint.dayMonth.string(from: b.at)).font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                            .frame(width: 62, alignment: .leading)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    // seventeen weeks, a square a day
    private func heat(_ s: StatsModel) -> some View {
        let goal = Double(model.settings.dailyGoal)
        let weeks = (0..<17).reversed().map { s.week(-$0) }
        let today = Calendar.current.startOfDay(for: .now)
        let active = weeks.joined().filter { $0.minutes >= StatsModel.streakFloor }.count
        return card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Son 17 hafta").font(.headline)
                    Spacer()
                    Text("\(active) gün dinledin").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                HStack(spacing: 3) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { _, w in
                        VStack(spacing: 3) {
                            ForEach(w) { d in
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(heatColor(d, goal: goal, future: d.date > today))
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay {
                                        if d.date == today { RoundedRectangle(cornerRadius: 3).strokeBorder(Color.primary.opacity(0.6), lineWidth: 1) }
                                    }
                            }
                        }
                    }
                }
                .opacity(grown ? 1 : 0)
                HStack(spacing: 4) {
                    Text("az").font(.system(size: 9)).foregroundStyle(.secondary)
                    ForEach([0.2, 0.4, 0.7, 1.0], id: \.self) { o in
                        RoundedRectangle(cornerRadius: 2).fill(StatTint.mint.opacity(o)).frame(width: 10, height: 10)
                    }
                    Text("hedef").font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Son 17 haftada \(active) gün dinledin")
    }

    private func heatColor(_ d: DayStat, goal: Double, future: Bool) -> Color {
        if future { return .clear }
        if d.minutes < 0.5 { return Color.primary.opacity(0.07) }
        let r = d.minutes / goal
        return StatTint.mint.opacity(r >= 1 ? 1 : r >= 0.6 ? 0.7 : r >= 0.3 ? 0.4 : 0.2)
    }
}
