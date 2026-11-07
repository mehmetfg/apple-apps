// Takvim: a month grid with a dot for each bill, payment, income and end; the chosen day's list under it.
import SwiftUI

struct CalendarView: View {
    @EnvironmentObject private var store: Store
    @State private var month = Derived.monthStart(.now)
    @State private var picked: Date?

    var body: some View {
        let d = Derived(store)
        let events = d.monthEvents(month)
        let byDay = Dictionary(grouping: events) { Day.cal.startOfDay(for: $0.date) }
        let out = events.filter { $0.type == .bill || $0.type == .payment }.compactMap(\.amount).reduce(0, +)
        let inc = events.filter { $0.type == .income }.compactMap(\.amount).reduce(0, +)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TabHeader(title: "Takvim")
                    HStack {
                        Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 34, height: 34) }
                            .buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel("Önceki ay")
                        Spacer()
                        VStack(spacing: 1) {
                            Text(Day.month(month).capitalized(with: Day.tr)).font(.headline)
                            Text("giden \(TL.compact(out)) · gelen \(TL.compact(inc))").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 34, height: 34) }
                            .buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel("Sonraki ay")
                    }
                    Card(padding: 12) { grid(byDay) }
                    legend
                    let list = picked.map { byDay[$0] ?? [] } ?? events
                    SectionTitle(text: picked.map { Day.dayMonth($0) } ?? "Bu ayın hepsi", trailing: picked == nil ? "\(events.count)" : "Tümü")
                        .onTapGesture { picked = nil }
                    if list.isEmpty { Text("Bu gün için kayıt yok.").foregroundStyle(.secondary).padding(.vertical, 8) }
                    VStack(spacing: 10) { ForEach(list) { EventRow(event: $0) } }
                }
                .padding(.horizontal, 18).padding(.bottom, 100)
            }
            .scrollIndicators(.hidden)
            .sbsGround()
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func shift(_ n: Int) {
        month = Day.cal.date(byAdding: .month, value: n, to: month)!
        picked = nil
    }

    private func grid(_ byDay: [Date: [FinEvent]]) -> some View {
        let cal = Day.cal
        let days = cal.range(of: .day, in: .month, for: month)!.count
        let lead = (cal.component(.weekday, from: month) - cal.firstWeekday + 7) % 7
        let cells: [Date?] = Array(repeating: nil, count: lead) + (0..<days).map { cal.date(byAdding: .day, value: $0, to: month) }
        let names = ["Pt", "Sa", "Ça", "Pe", "Cu", "Ct", "Pz"]
        return VStack(spacing: 6) {
            HStack(spacing: 0) { ForEach(names, id: \.self) { Text($0).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).frame(maxWidth: .infinity) } }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        let evs = byDay[day] ?? []
                        let today = cal.isDateInToday(day)
                        let on = picked == day
                        VStack(spacing: 3) {
                            Text("\(cal.component(.day, from: day))").font(.subheadline.weight(today ? .bold : .regular)).monospacedDigit()
                                .foregroundStyle(on ? Color.white : (today ? Color.money : .primary))
                                .frame(width: 32, height: 32)
                                .background { if on { Circle().fill(Color.money) } else if today { Circle().stroke(Color.money, lineWidth: 1.5) } }
                            HStack(spacing: 2) {
                                ForEach(Array(evs.prefix(4).enumerated()), id: \.offset) { _, e in dot(e) }
                            }
                            .frame(height: 6)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 2)
                        .contentShape(Rectangle())
                        .onTapGesture { picked = on ? nil : day }
                        .accessibilityElement()
                        .accessibilityLabel("\(Day.dayMonth(day)): \(evs.count) kayıt")
                        .accessibilityAddTraits(.isButton)
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
        }
    }

    @ViewBuilder private func dot(_ e: FinEvent) -> some View {
        switch e.type {
        case .commitmentEnd: Circle().stroke(Color.attention, lineWidth: 1.5).frame(width: 6, height: 6)
        case .warrantyEnd: Circle().stroke(Color.watch, lineWidth: 1.5).frame(width: 6, height: 6)
        case .income: Circle().fill(Color.money).frame(width: 6, height: 6)
        case .bill where !e.paid: Circle().fill(Catalog.category(e.category).color.opacity(0.35)).frame(width: 6, height: 6)
        default: Circle().fill(Catalog.category(e.category).color).frame(width: 6, height: 6)
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            item(AnyView(Circle().fill(Color.secondary).frame(width: 7, height: 7)), "ödendi")
            item(AnyView(Circle().fill(Color.secondary.opacity(0.35)).frame(width: 7, height: 7)), "bekliyor")
            item(AnyView(Circle().fill(Color.money).frame(width: 7, height: 7)), "gelir")
            item(AnyView(Circle().stroke(Color.attention, lineWidth: 1.5).frame(width: 7, height: 7)), "taahhüt sonu")
            item(AnyView(Circle().stroke(Color.watch, lineWidth: 1.5).frame(width: 7, height: 7)), "garanti sonu")
        }
        .font(.caption2).foregroundStyle(.secondary)
    }

    private func item(_ v: AnyView, _ t: String) -> some View { HStack(spacing: 4) { v; Text(t) } }
}
