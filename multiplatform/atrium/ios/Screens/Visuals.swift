// The visual vocabulary: tear-off calendar pages, activity rings, heat map, origin donut, note rows.
import Charts
import SwiftUI

/// A classic tear-off calendar page.
struct CalendarPage: View {
    var date: Date
    var size: CGFloat = 1
    var badge: Int? = nil

    var body: some View {
        let cal = TurkishCalendar.calendar
        VStack(spacing: 0) {
            ZStack {
                Palette.calendarRed
                HStack(spacing: 10 * size) {
                    ForEach(0..<2) { _ in Circle().fill(.black.opacity(0.25)).frame(width: 5 * size, height: 5 * size) }
                }
                .offset(y: -9 * size)
                Text(TurkishCalendar.monthName(date).uppercased())
                    .font(.system(size: 11 * size, weight: .heavy, design: .rounded)).tracking(1.5 * size)
                    .foregroundStyle(.white)
                    .offset(y: 3 * size)
            }
            .frame(height: 30 * size)
            VStack(spacing: -2 * size) {
                Text("\(cal.component(.day, from: date))")
                    .font(.system(size: 46 * size, weight: .bold, design: .serif))
                    .foregroundStyle(Color(white: 0.12))
                Text(TurkishCalendar.weekdayName(date))
                    .font(.system(size: 11 * size, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.calendarRed)
            }
            .padding(.vertical, 8 * size)
            .frame(maxWidth: .infinity)
            .background(Color(white: 0.985))
        }
        .frame(width: 92 * size)
        .clipShape(RoundedRectangle(cornerRadius: 12 * size, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 12 * size, style: .continuous).fill(Color(white: 0.9)).offset(y: 3 * size)
                .shadow(color: .black.opacity(0.18), radius: 6 * size, y: 4 * size)
        )
        .overlay(alignment: .topTrailing) {
            if let badge, badge > 0 {
                Text("\(badge)").font(.system(size: 11 * size, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    .padding(.horizontal, 6 * size).padding(.vertical, 2 * size)
                    .background(Palette.accent, in: Capsule())
                    .offset(x: 6 * size, y: -6 * size)
            }
        }
    }
}

/// Three concentric rings, Apple-Watch style. Each value is a ratio where 1 = a full lap.
struct ActivityRings: View {
    struct Ring: Identifiable {
        var id: String { label }
        var label: String
        var value: Double
        var color: Color
    }
    var rings: [Ring]
    var lineWidth: CGFloat = 14
    @State private var progress: Double = 0

    var body: some View {
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.offset) { i, ring in
                let inset = CGFloat(i) * (lineWidth + 4)
                Circle().stroke(ring.color.opacity(0.18), lineWidth: lineWidth).padding(inset)
                Circle()
                    .trim(from: 0, to: min(1, ring.value * progress))
                    .stroke(AngularGradient(colors: [ring.color.opacity(0.75), ring.color], center: .center),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(inset)
                if ring.value > 1 {
                    Circle()
                        .trim(from: 0, to: min(1, (ring.value - 1) * progress))
                        .stroke(ring.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(inset)
                        .shadow(color: .black.opacity(0.3), radius: 2)
                }
            }
        }
        .padding(lineWidth / 2)
        .onAppear { withAnimation(.easeOut(duration: 1.1)) { progress = 1 } }
    }
}

/// GitHub-style heat map: columns are weeks, rows are weekdays.
struct HeatMap: View {
    var counts: [String: Int]
    var weeks: Int = 26
    var color: Color = Palette.accent
    var selected: String?
    var onSelect: (String) -> Void = { _ in }

    var body: some View {
        let cal = TurkishCalendar.calendar
        let today = cal.startOfDay(for: Date())
        let thisMonday = cal.date(byAdding: .day, value: -TurkishCalendar.weekdayIndex(today), to: today)!
        let start = cal.date(byAdding: .day, value: -7 * (weeks - 1), to: thisMonday)!
        let peak = max(1, counts.values.sorted().dropLast(max(0, counts.count / 20)).last ?? 1)
        GeometryReader { geo in
            let cell = min(18, (geo.size.width - CGFloat(weeks - 1) * 3) / CGFloat(weeks))
            HStack(alignment: .top, spacing: 3) {
                ForEach(0..<weeks, id: \.self) { w in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { d in
                            let date = cal.date(byAdding: .day, value: w * 7 + d, to: start)!
                            let key = TurkishCalendar.dayKey(date)
                            let n = counts[key] ?? 0
                            RoundedRectangle(cornerRadius: cell * 0.28, style: .continuous)
                                .fill(date > today ? Color.clear : (n == 0 ? Color.primary.opacity(0.07) : color.opacity(0.25 + 0.75 * min(1, Double(n) / Double(peak)))))
                                .frame(width: cell, height: cell)
                                .overlay {
                                    if key == selected { RoundedRectangle(cornerRadius: cell * 0.28).stroke(Color.primary, lineWidth: 1.5) }
                                }
                                .onTapGesture { if date <= today { onSelect(key) } }
                        }
                    }
                }
            }
        }
        .frame(height: 7 * 18 + 6 * 3)
    }
}

struct OriginDonut: View {
    var counts: [Origin: Int]
    var size: CGFloat = 120
    @State private var drawn = false

    var body: some View {
        let slices = Origin.allCases.map { ($0, counts[$0] ?? 0) }.filter { $0.1 > 0 }
        let total = max(1, slices.reduce(0) { $0 + $1.1 })
        let mine = (counts[.me] ?? 0) + (counts[.shared] ?? 0)
        ZStack {
            Chart(slices, id: \.0) { s in
                SectorMark(angle: .value("n", drawn ? s.1 : (s.0 == slices.first?.0 ? 1 : 0)), innerRadius: .ratio(0.64), angularInset: 1.5)
                    .foregroundStyle(Palette.origin(s.0)).cornerRadius(4)
            }
            .chartLegend(.hidden)
            VStack(spacing: 0) {
                Text("%\(Int((Double(mine) / Double(total) * 100).rounded()))").font(.system(.title3, design: .rounded).weight(.bold))
                Text("senin").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .onAppear { withAnimation(.easeOut(duration: 0.9)) { drawn = true } }
    }
}

struct WeekStrip: View {
    var counts: [String: Int]
    var body: some View {
        let cal = TurkishCalendar.calendar
        let today = cal.startOfDay(for: Date())
        let peak = max(1, counts.values.max() ?? 1)
        HStack(spacing: 6) {
            ForEach((0..<7).reversed(), id: \.self) { back in
                let date = cal.date(byAdding: .day, value: -back, to: today)!
                let n = counts[TurkishCalendar.dayKey(date)] ?? 0
                VStack(spacing: 5) {
                    Text(String(TurkishCalendar.weekdayName(date).prefix(2))).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    ZStack(alignment: .bottom) {
                        Capsule().fill(Color.primary.opacity(0.07)).frame(width: 14, height: 46)
                        Capsule().fill(back == 0 ? Palette.accent : Palette.accent.opacity(0.55))
                            .frame(width: 14, height: max(6, 46 * CGFloat(n) / CGFloat(peak)))
                    }
                    Text("\(cal.component(.day, from: date))").font(.caption2.weight(back == 0 ? .bold : .regular))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct NoteRow: View {
    var note: NoteRecord
    var showFolder = true
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.kind(note.kind).opacity(0.16))
                Image(systemName: note.kind.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.kind(note.kind))
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(note.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                HStack(spacing: 6) {
                    Circle().fill(Palette.origin(note.origin)).frame(width: 7, height: 7)
                    if showFolder { Text(note.folder.isEmpty ? "Kök" : note.folder).lineLimit(1).truncationMode(.head) }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(TurkishCalendar.relative(note.modified)).font(.caption2).foregroundStyle(.secondary)
                if let w = note.words { Text("\(Format.compact(w)) k").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary) }
                else { Image(systemName: "icloud.and.arrow.down").font(.caption2).foregroundStyle(.tertiary) }
            }
        }
        .contentShape(Rectangle())
    }
}

struct OriginLegend: View {
    var counts: [Origin: Int]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Origin.allCases.filter { (counts[$0] ?? 0) > 0 }) { o in
                HStack(spacing: 8) {
                    Circle().fill(Palette.origin(o)).frame(width: 9, height: 9)
                    Text(o.label).font(.subheadline)
                    Spacer()
                    Text(Format.number(counts[o] ?? 0)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
    }
}
