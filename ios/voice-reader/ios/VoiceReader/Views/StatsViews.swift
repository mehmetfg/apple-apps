// Listening statistics: a small card on the library's home and, behind it, the İstatistik page (Gün / Hafta / Ay).
// Everything is derived: listening from ListeningLog, marks from the highlights' dates, notes from NoteStore.
// 225 words = 1 page. No goals, no streaks.
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
    var id: Date { start }
}

@MainActor
struct StatsModel {
    let model: AppModel
    private var cal: Calendar { var c = Calendar.current; c.firstWeekday = 2; return c }   // weeks start on Monday

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
            return StatBucket(start: a, label: label, minutes: t.seconds / 60, words: t.words, current: i == 0)
        }
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
        return p < 10 ? String(format: "%.1f", p).replacingOccurrences(of: ".", with: ",") : number(Int(p.rounded()))
    }
    static func decimal(_ v: Double) -> String { String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",") }
}


// MARK: - the İstatistik page

/// İstatistik (2026-10-28: one page for everything measured): Okuma (listening, efficiency, production, books) and
/// Yol (the GPS record: maps, km, calories), each by day, week or month.
enum StatsTab: String, CaseIterable, Identifiable {
    case reading, road
    var id: String { rawValue }
    var name: String { self == .reading ? "Okuma" : "Yol" }
}

struct StatsScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent
    @State private var span: StatSpan = .day
    @State private var tab: StatsTab

    init(tab: StatsTab = .reading) { _tab = State(initialValue: tab) }

    private static let colors: [Color] = [.purple, .teal, .orange, .blue, .pink, .green, .indigo, .brown]

    var body: some View {
        let s = StatsModel(model: model)
        let t = s.total(span)
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Picker("Bölüm", selection: $tab) {
                        ForEach(StatsTab.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Dönem", selection: $span) {
                        ForEach(StatSpan.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if tab == .road {
                        RoadsPanel(span: $span)
                    } else {
                    tiles(t)
                    chart(s.buckets(span))
                    donut(s.folders(t))
                    averages(s)
                    efficiency(t)
                    production(s, t)
                    books(s.books(t))

                    Text("Dinleme süresi 22 Ekim 2026'dan beri tutuluyor; işaretler ve notlar eski tarihleriyle sayılır. 225 kelime = 1 sayfa.")
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(18)
            }
            .task {                                   // test hook: -statstest road opens on Yol
                if CommandLine.arguments.contains("road") { tab = .road }
            }
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

    // four numbers for the period
    private func tiles(_ t: ListeningDay) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            tile(periodName, StatFormat.minutes(t.seconds / 60), "clock.fill", Palette.play)
            tile("Kelime", StatFormat.number(t.words), "text.word.spacing", accent.ink)
            tile("Sayfa", StatFormat.pages(t.words), "doc.text.fill", .teal)
            tile("Biten kitap", "\(t.finished.count)", "books.vertical.fill", .purple)
        }
    }

    private func tile(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(color)
            Text(value).font(.system(size: 24, weight: .bold, design: .rounded)).contentTransition(.numericText())
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }

    private func chart(_ b: [StatBucket]) -> some View {
        section(span == .day ? "Son 14 gün" : span == .week ? "Son 8 hafta" : "Son 6 ay") {
            Chart(b) { x in
                BarMark(x: .value("Dönem", x.label), y: .value("Dakika", x.minutes))
                    .foregroundStyle(x.current ? Palette.play : accent.fill)
                    .cornerRadius(4)
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

    @ViewBuilder private func donut(_ f: [(name: String, minutes: Double)]) -> some View {
        if !f.isEmpty {
            section("Neyi dinledin") {
                HStack(spacing: 18) {
                    Chart(Array(f.enumerated()), id: \.offset) { i, x in
                        SectorMark(angle: .value("Dakika", x.minutes), innerRadius: .ratio(0.62), angularInset: 1.5)
                            .foregroundStyle(Self.colors[i % Self.colors.count])
                            .cornerRadius(3)
                    }
                    .frame(width: 130, height: 130)
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(f.enumerated()), id: \.offset) { i, x in
                            HStack(spacing: 7) {
                                Circle().fill(Self.colors[i % Self.colors.count]).frame(width: 9, height: 9)
                                Text(x.name).font(.subheadline).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(StatFormat.minutes(x.minutes)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func averages(_ s: StatsModel) -> some View {
        if let a = s.averages {
            let n = Double(a.days), t = a.perDay
            let minutes = t.seconds / 60
            section("Ortalama (\(a.days) günde)") {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 9) {
                    GridRow {
                        Text("").font(.caption)
                        Text("Günlük").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text("Haftalık").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text("Aylık").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    avgRow("Süre", minutes / n) { StatFormat.minutes($0) }
                    avgRow("Kelime", Double(t.words) / n) { StatFormat.number(Int($0.rounded())) }
                    avgRow("Sayfa", Double(t.words) / n / ListeningLog.wordsPerPage) { StatFormat.decimal($0) }
                    avgRow("Kitap", Double(t.finished.count) / n) { StatFormat.decimal($0) }
                }
                .font(.subheadline.monospacedDigit())
            }
        }
    }

    private func avgRow(_ name: String, _ perDay: Double, _ f: @escaping (Double) -> String) -> some View {
        GridRow {
            Text(name).foregroundStyle(.secondary)
            Text(f(perDay))
            Text(f(perDay * 7))
            Text(f(perDay * 30.4))
        }
    }

    private func efficiency(_ t: ListeningDay) -> some View {
        let minutes = t.seconds / 60
        let wpm = minutes > 0.5 ? Double(t.words) / minutes : 0
        let share = t.seconds + t.paused > 0 ? t.seconds / (t.seconds + t.paused) : 0
        return section("Verim") {
            HStack(spacing: 10) {
                gauge(share, "Çalma oranı", "%\(Int((share * 100).rounded()))", "Oturum açıkken sesin çaldığı pay")
                metric(wpm > 0 ? "\(Int(wpm.rounded()))" : "—", "kelime/dk", "Gerçek hız")
                metric(StatFormat.minutes(t.breaks / 60), "müzik arası", "Ara")
            }
        }
    }

    private func gauge(_ v: Double, _ title: String, _ value: String, _ hint: String) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.1), lineWidth: 7)
                Circle().trim(from: 0, to: v).stroke(accent.fill, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(value).font(.system(size: 15, weight: .bold, design: .rounded))
            }
            .frame(width: 66, height: 66)
            Text(title).font(.caption2.weight(.semibold)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityHint(hint)
    }

    private func metric(_ value: String, _ unit: String, _ title: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
            Text(unit).font(.caption2).foregroundStyle(.secondary)
            Text(title).font(.caption2.weight(.semibold))
        }
        .frame(maxWidth: .infinity, minHeight: 90)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    private func production(_ s: StatsModel, _ t: ListeningDay) -> some View {
        let marks = s.marks(span)
        let n = s.notes(span)
        let hours = t.seconds / 3600
        return section("Üretim") {
            HStack(spacing: 10) {
                metric("\(marks)", "işaret", "İşaretler")
                metric("\(n.voice)", n.seconds > 0 ? StatFormat.minutes(n.seconds / 60) + " ses" : "sesli", "Sesli not")
                metric("\(n.text)", "yazılı", "Yazılı not")
            }
            HStack(spacing: 10) {
                metric(t.words > 0 ? StatFormat.decimal(Double(marks) / Double(t.words) * 1000) : "—", "her 1000 kelimede", "İşaret sıklığı")
                metric(hours > 0.05 ? StatFormat.decimal(Double(n.voice + n.text) / hours) : "—", "saat başına", "Not sıklığı")
            }
        }
    }

    @ViewBuilder private func books(_ b: [(doc: DocumentRecord?, title: String, minutes: Double, words: Int)]) -> some View {
        if !b.isEmpty {
            section("Kitaplar") {
                VStack(spacing: 0) {
                    ForEach(Array(b.enumerated()), id: \.offset) { _, x in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(x.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                ProgressBar(value: x.doc?.progress ?? 0).frame(height: 3)
                                Text("\(StatFormat.number(x.words)) kelime · %\(Int(((x.doc?.progress ?? 0) * 100).rounded()))"
                                     + (x.doc?.isFinished == true ? " · bitti" : ""))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(StatFormat.minutes(x.minutes)).font(.subheadline.monospacedDigit().weight(.semibold))
                        }
                        .padding(.vertical, 10)
                        Divider().opacity(0.4)
                    }
                }
            }
        }
    }
}
