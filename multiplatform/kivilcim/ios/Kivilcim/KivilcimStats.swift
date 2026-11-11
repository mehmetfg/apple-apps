// Kıvılcım statistics (2026-11-10): how much was spoken, how many ideas came out of it and how many were carried
// out. Counted on the phone from dizin.json (depo.ogeler); nothing is stored. A recording = a spark or journal with
// sound (a long talk's later parts count as the same recording); an idea = a spark or an idea pulled out of a
// journal (extract); carried out = an idea marked done.
import SwiftUI
import Charts

private let statsColor = Color(hex: "#E0703A")

@MainActor struct KivilcimFacts {
    let items: [Oge]
    private let cal: Calendar = { var c = Calendar(identifier: .iso8601); c.timeZone = .autoupdatingCurrent; return c }()

    init(_ all: [Oge]) { items = all }

    private func day(_ o: Oge) -> Date? { Zaman.coz(o.tarih).map { cal.startOfDay(for: $0) } }
    var recordings: [Oge] { items.filter { ($0.kind == "spark" || $0.kind == "journal") && $0.sure > 0 } }
    var ideas: [Oge] { items.filter { $0.kind == "spark" || $0.kind == "extract" } }

    struct Totals { var recordings = 0; var minutes = 0.0; var ideas = 0; var done = 0
        var rate: Double { ideas == 0 ? 0 : Double(done) / Double(ideas) } }

    func totals(from start: Date? = nil) -> Totals {
        func inRange(_ o: Oge) -> Bool { guard let start else { return true }; return (Zaman.coz(o.tarih) ?? .distantPast) >= start }
        var t = Totals()
        for r in recordings where inRange(r) { t.minutes += r.sure / 60; if r.devam.isEmpty { t.recordings += 1 } }
        for i in ideas where inRange(i) { t.ideas += 1; if i.status == "done" { t.done += 1 } }
        return t
    }
    var today: Totals { totals(from: cal.startOfDay(for: Date())) }
    var thisWeek: Totals { totals(from: cal.dateInterval(of: .weekOfYear, for: Date())?.start) }
    var last30: Totals { totals(from: cal.date(byAdding: .day, value: -30, to: Date())) }

    struct DayBar: Identifiable { var id: String { "\(day.timeIntervalSince1970)-\(series)" }; let day: Date; let series: String; let value: Double }

    /// Last n days: recordings and ideas per day.
    func days(_ n: Int) -> [DayBar] {
        let first = cal.date(byAdding: .day, value: -(n - 1), to: cal.startOfDay(for: Date()))!
        var rec: [Date: Int] = [:], ide: [Date: Int] = [:]
        for r in recordings where r.devam.isEmpty { if let d = day(r), d >= first { rec[d, default: 0] += 1 } }
        for i in ideas { if let d = day(i), d >= first { ide[d, default: 0] += 1 } }
        return (0..<n).flatMap { k -> [DayBar] in
            let d = cal.date(byAdding: .day, value: k, to: first)!
            return [DayBar(day: d, series: "Kayıt", value: Double(rec[d] ?? 0)), DayBar(day: d, series: "Fikir", value: Double(ide[d] ?? 0))]
        }
    }

    /// Minutes spoken per day, last n days.
    func minutes(_ n: Int) -> [DayBar] {
        let first = cal.date(byAdding: .day, value: -(n - 1), to: cal.startOfDay(for: Date()))!
        var m: [Date: Double] = [:]
        for r in recordings { if let d = day(r), d >= first { m[d, default: 0] += r.sure / 60 } }
        return (0..<n).map { k in let d = cal.date(byAdding: .day, value: k, to: first)!; return DayBar(day: d, series: "dk", value: m[d] ?? 0) }
    }

    /// Last n weeks: ideas that came out and how many of them are done by now.
    func weeks(_ n: Int) -> [DayBar] {
        guard let thisStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start else { return [] }
        let first = cal.date(byAdding: .weekOfYear, value: -(n - 1), to: thisStart)!
        var ide: [Date: Int] = [:], done: [Date: Int] = [:]
        for i in ideas {
            guard let t = Zaman.coz(i.tarih), t >= first, let w = cal.dateInterval(of: .weekOfYear, for: t)?.start else { continue }
            ide[w, default: 0] += 1
            if i.status == "done" { done[w, default: 0] += 1 }
        }
        return (0..<n).flatMap { k -> [DayBar] in
            let w = cal.date(byAdding: .weekOfYear, value: k, to: first)!
            return [DayBar(day: w, series: "Fikir", value: Double(ide[w] ?? 0)), DayBar(day: w, series: "Hayata geçen", value: Double(done[w] ?? 0))]
        }
    }

    /// Open ideas per area, most first.
    var openByArea: [(String, Int)] {
        var c: [String: Int] = [:]
        for i in ideas where i.status != "done" { c[i.alan, default: 0] += 1 }
        return c.sorted { $0.value > $1.value }
    }

    var recentlyDone: [Oge] {
        ideas.filter { $0.status == "done" }.sorted { $0.done_at > $1.done_at }.prefix(8).map { $0 }
    }
}

private func minutesText(_ m: Double) -> String {
    m < 60 ? "\(Int(m.rounded())) dk" : "\(Int(m) / 60) sa \(Int(m) % 60) dk"
}

private struct Figure: View {
    let value: String, label: String
    var color: Color = .primary
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(.title2, design: .serif).weight(.bold)).monospacedDigit().foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct KivilcimIstatistikKarti: View {
    @EnvironmentObject var depo: TelefonDeposu
    var body: some View {
        let f = KivilcimFacts(depo.ogeler)
        let t = f.today, w = f.thisWeek, m = f.last30
        MCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Kıvılcım istatistikleri", systemImage: "waveform.badge.magnifyingglass").font(.headline).foregroundStyle(statsColor)
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                HStack(spacing: 8) {
                    Figure(value: "\(t.recordings)", label: "bugün kayıt")
                    Figure(value: minutesText(t.minutes), label: "bugün ses")
                    Figure(value: "\(t.ideas)", label: "bugün fikir", color: statsColor)
                }
                Chart(f.days(7)) { b in
                    BarMark(x: .value("Gün", b.day, unit: .day), y: .value("Adet", b.value))
                        .foregroundStyle(by: .value("Tür", b.series))
                        .position(by: .value("Tür", b.series))
                        .cornerRadius(3)
                }
                .chartForegroundStyleScale(["Kayıt": Color.secondary.opacity(0.5), "Fikir": statsColor])
                .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
                .frame(height: 70)
                HStack(spacing: 12) {
                    StatusRing(value: m.rate, color: .green, size: 40, line: 5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Son 30 günde \(m.ideas) fikrin \(m.done)'i hayata geçti").font(.subheadline)
                        Text("Bu hafta \(w.recordings) kayıt · \(minutesText(w.minutes)) · \(w.ideas) fikir").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct KivilcimIstatistikSayfasi: View {
    @EnvironmentObject var depo: TelefonDeposu
    var body: some View {
        let f = KivilcimFacts(depo.ogeler)
        let all = f.totals(), w = f.thisWeek
        List {
            Section("Bu hafta") {
                HStack {
                    Figure(value: "\(w.recordings)", label: "kayıt")
                    Figure(value: minutesText(w.minutes), label: "ses")
                    Figure(value: "\(w.ideas)", label: "fikir", color: statsColor)
                    Figure(value: "\(w.done)", label: "hayata geçen", color: .green)
                }
            }
            Section("Son 14 gün · konuşulan dakika") {
                Chart(f.minutes(14)) { b in
                    BarMark(x: .value("Gün", b.day, unit: .day), y: .value("Dakika", b.value))
                        .foregroundStyle(statsColor.gradient).cornerRadius(3)
                }
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: 2)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
                .frame(height: 160).padding(.vertical, 6)
            }
            Section("Son 8 hafta · fikir ve hayata geçen") {
                Chart(f.weeks(8)) { b in
                    BarMark(x: .value("Hafta", b.day, unit: .weekOfYear), y: .value("Adet", b.value))
                        .foregroundStyle(by: .value("Tür", b.series))
                        .position(by: .value("Tür", b.series))
                        .cornerRadius(3)
                }
                .chartForegroundStyleScale(["Fikir": statsColor, "Hayata geçen": Color.green])
                .frame(height: 170).padding(.vertical, 6)
            }
            if !f.openByArea.isEmpty {
                Section("Açık fikirler · alana göre") {
                    ForEach(f.openByArea, id: \.0) { id, n in
                        let a = depo.siniflar.alan(id)
                        HStack {
                            Label(a.ad, systemImage: a.simge).foregroundStyle(Color(hex: a.renk))
                            Spacer()
                            Text("\(n)").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !f.recentlyDone.isEmpty {
                Section("Son hayata geçenler") {
                    ForEach(f.recentlyDone) { o in
                        NavigationLink(value: o.id) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(o.baslik).lineLimit(2)
                                Text(String(o.done_at.prefix(10))).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section("Tümü") {
                LabeledContent("Kayıt", value: "\(all.recordings)")
                LabeledContent("Konuşulan", value: minutesText(all.minutes))
                LabeledContent("Fikir", value: "\(all.ideas)")
                LabeledContent("Hayata geçen", value: "\(all.done) · %\(Int((all.rate * 100).rounded()))")
            }
        }
        .navigationTitle("İstatistik")
    }
}
