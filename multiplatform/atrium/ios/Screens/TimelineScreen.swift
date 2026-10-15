// Timeline: half a year as a heat map, a 14-day chart, and every active day as a calendar page.
import Charts
import SwiftUI

struct TimelineScreen: View {
    @EnvironmentObject var store: VaultStore
    @State private var selected: String?
    @State private var mineOnly = false

    var body: some View {
        let activity = store.activity(days: 190)
        let counts = activity.mapValues { mineOnly ? $0.mine : $0.all }
        let days = counts.filter { $0.value > 0 }.keys.sorted(by: >)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Picker("", selection: $mineOnly) {
                    Text("Bütün vault").tag(false)
                    Text("Yalnız senin yazdıkların").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.top, 8)

                Card {
                    HStack {
                        Text("Son 26 hafta").font(.headline)
                        Spacer()
                        Text("\(days.count) etkin gün").font(.subheadline).foregroundStyle(.secondary)
                    }
                    HeatMap(counts: counts, weeks: 26, color: mineOnly ? Palette.amber : Palette.accent, selected: selected) { selected = $0 }
                        .padding(.top, 4)
                    if let selected {
                        NavigationLink(value: DayRoute(day: selected)) {
                            HStack {
                                Text(dayTitle(selected)).font(.subheadline.weight(.semibold))
                                Text("· \(counts[selected] ?? 0) not").foregroundStyle(.secondary)
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .font(.subheadline)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 6)
                    } else {
                        Text("Bir güne dokun: o gün ne yaptın.").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                    }
                }
                .appear()

                fortnightChart.appear(0.05)

                SectionTitle(title: "Günler")
                ForEach(days.prefix(60), id: \.self) { day in
                    NavigationLink(value: DayRoute(day: day)) { DayCard(day: day, count: counts[day] ?? 0) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.page)
        .refreshable { await store.refresh() }
    }

    private var fortnightChart: some View {
        struct Bar: Identifiable { var id: String { day + origin.rawValue }; var day: String; var date: Date; var origin: Origin; var n: Int }
        let cal = TurkishCalendar.calendar
        var bars: [Bar] = []
        for back in (0..<14).reversed() {
            let date = cal.date(byAdding: .day, value: -back, to: cal.startOfDay(for: Date()))!
            let key = TurkishCalendar.dayKey(date)
            var by: [Origin: Int] = [:]
            for n in store.touched(on: key) { by[n.origin, default: 0] += 1 }
            for o in Origin.allCases where (by[o] ?? 0) > 0 && (!mineOnly || o == .me || o == .shared) {
                bars.append(Bar(day: key, date: date, origin: o, n: by[o]!))
            }
        }
        return Card {
            Text("Son 14 gün · kim yazdı").font(.headline)
            Chart(bars) { b in
                BarMark(x: .value("Gün", b.date, unit: .day), y: .value("Not", b.n))
                    .foregroundStyle(Palette.origin(b.origin))
                    .cornerRadius(3)
            }
            .chartForegroundStyleScale(domain: Origin.allCases.map(\.label), range: Origin.allCases.map(Palette.origin))
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: 2)) { _ in AxisValueLabel(format: .dateTime.day()) } }
            .frame(height: 150)
        }
    }

    private func dayTitle(_ key: String) -> String {
        guard let d = TurkishCalendar.date(fromKey: key) else { return key }
        return TurkishCalendar.journalTitle(d)
    }
}

struct DayCard: View {
    @EnvironmentObject var store: VaultStore
    var day: String
    var count: Int

    var body: some View {
        let date = TurkishCalendar.date(fromKey: day) ?? Date()
        let notes = store.touched(on: day)
        let created = store.created(on: day).count
        let journal = store.journal(for: day)
        let areas = Dictionary(grouping: notes, by: \.area).map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }
        HStack(alignment: .top, spacing: 14) {
            CalendarPage(date: date, size: 0.72)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("\(notes.count) not").font(.headline)
                    if created > 0 { Pill(text: "+\(created) yeni", color: Palette.teal) }
                    if journal != nil { Pill(text: "günlük", color: Palette.amber, symbol: "book.closed.fill") }
                }
                ForEach(notes.prefix(3)) { n in
                    HStack(spacing: 6) {
                        Circle().fill(Palette.origin(n.origin)).frame(width: 6, height: 6)
                        Text(n.name).font(.subheadline).lineLimit(1)
                    }
                }
                HStack(spacing: 4) {
                    ForEach(areas.prefix(4), id: \.0) { a in
                        Capsule().fill(Palette.area(a.0)).frame(width: max(10, CGFloat(a.1) / CGFloat(max(1, notes.count)) * 120), height: 5)
                    }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct DayScreen: View {
    @EnvironmentObject var store: VaultStore
    @EnvironmentObject var router: Router
    var day: String
    @State private var journalText: String?

    var body: some View {
        let date = TurkishCalendar.date(fromKey: day) ?? Date()
        let notes = store.touched(on: day)
        let created = Set(store.created(on: day).map(\.path))
        let groups = Dictionary(grouping: notes, by: \.area).sorted { $0.value.count > $1.value.count }
        let ledger = store.ledger[day]
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 18) {
                    CalendarPage(date: date, size: 1.15)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(notes.count) not").font(.title2.weight(.bold)).fontDesign(.rounded)
                        Text("\(created.count) yeni · \(notes.filter { $0.origin == .me || $0.origin == .shared }.count) senin").foregroundStyle(.secondary)
                        if let ledger, ledger.wordsAddedMine > 0 { Text("+\(Format.number(ledger.wordsAddedMine)) kelime yazdın").foregroundStyle(Palette.amber) }
                    }
                }
                .padding(.top, 8)

                if let j = store.journal(for: day) {
                    NavigationLink(value: NoteRoute(path: j.path)) {
                        Card {
                            Label("Günlük", systemImage: "book.closed.fill").font(.headline).foregroundStyle(Palette.amber)
                            Text(journalText ?? "…").font(.callout).fontDesign(.serif).lineLimit(6).foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                    .task {
                        if let t = try? await store.read(j.path).text {
                            journalText = Frontmatter.split(t).body.trimmingCharacters(in: .whitespacesAndNewlines)
                                .replacingOccurrences(of: "![[🔁 Günlük Rutin#Bugün]]", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                } else if day == TurkishCalendar.dayKey(Date()) {
                    Button {
                        Task { if let p = try? await store.ensureJournal() { router.open(p) } }
                    } label: {
                        Card { Label("Bugünün günlüğünü aç", systemImage: "plus.circle.fill").font(.headline).foregroundStyle(Palette.amber) }
                    }
                    .buttonStyle(.plain)
                }

                ForEach(groups, id: \.key) { area, list in
                    SectionTitle(title: area, detail: "\(list.count)")
                    Card(padding: 6) {
                        VStack(spacing: 0) {
                            ForEach(list) { n in
                                NavigationLink(value: NoteRoute(path: n.path)) {
                                    NoteRow(note: n).padding(10).overlay(alignment: .topLeading) {
                                        if created.contains(n.path) { Circle().fill(Palette.teal).frame(width: 8, height: 8).offset(x: 6, y: 6) }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.page)
        .navigationTitle(TurkishCalendar.journalTitle(date))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
