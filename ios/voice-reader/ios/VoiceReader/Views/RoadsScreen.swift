// İstatistik › Yol (Yollarım, 2026-10-28): the GPS record on its own, apart from the books. A day, a week or a month, stepped back
// with ‹ › as far as the record goes: where you went (every way of the period on one map), km, time in motion,
// calories, steps and climb, a bar for each day, and the ways grouped by day; a way opens with its own map, its
// numbers and the books heard on it. Read from the recorded ways only; no goals, nothing to fill in.
import SwiftUI
import Charts
import MapKit

struct RoadsPanel: View {
    @Environment(AppModel.self) private var model
    @Binding var span: StatSpan
    @State private var offset = 0                     // 0: this day / week / month, -1 the one before…
    @State private var kind: MoveKind?                // nil: both
    @State private var open: Workout?

    private let cal = Calendar.current

    private var all: [Workout] {
        var l = model.workout.history
        if let c = model.workout.current, !l.contains(where: { $0.id == c.id }) { l.insert(c, at: 0) }
        return l.filter { kind == nil || $0.kind == kind }.sorted { $0.start > $1.start }
    }

    private func ways(_ from: Date, _ to: Date) -> [Workout] {
        let end = cal.date(byAdding: .day, value: 1, to: to) ?? to
        return all.filter { $0.start >= from && $0.start < end }
    }

    /// How far back ‹ can go: to the period of the first recorded way.
    private var earliest: Int {
        guard let first = all.last?.start else { return 0 }
        let s = StatsModel(model: model)
        var n = 0
        while n > -400 {
            let (a, _) = s.range(span, offset: n)
            if a <= first { return n }
            n -= 1
        }
        return n
    }

    var body: some View {
        let s = StatsModel(model: model)
        let (a, z) = s.range(span, offset: offset)
        let now = ways(a, z)
        VStack(alignment: .leading, spacing: 16) {
            stepper(a, z)
            if all.isEmpty {
                ContentUnavailableView("Henüz yol yok", systemImage: "map",
                                       description: Text("Bisiklet ya da yürüyüş modunda dinlediğinde yolun burada görünür: harita, km, süre, kalori."))
            } else if now.isEmpty {
                Text("Bu dönemde yol yok.").font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                RoutesMap(ways: now)
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                totals(now)
                if span != .day { chart(a, z) }
                days(now)
            }
        }
        .sheet(item: $open) { WayDetail(way: $0) }
        .onChange(of: span) { _, _ in offset = 0 }
    }

    // MARK: pieces

    /// ‹ 28 Ekim Salı › — back as far as the record goes, forward up to now.
    private func stepper(_ a: Date, _ z: Date) -> some View {
        HStack {
            Button { withAnimation(.smooth) { offset -= 1 } } label: { Image(systemName: "chevron.left").frame(width: 44, height: 36) }
                .disabled(offset <= earliest)
                .accessibilityLabel("Önceki")
            Spacer()
            VStack(spacing: 1) {
                Text(title(a, z)).font(.headline)
                if offset == 0 { Text(span == .day ? "bugün" : span == .week ? "bu hafta" : "bu ay").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Button { withAnimation(.smooth) { offset += 1 } } label: { Image(systemName: "chevron.right").frame(width: 44, height: 36) }
                .disabled(offset >= 0)
                .accessibilityLabel("Sonraki")
            Menu {
                Picker("Tür", selection: $kind) {
                    Text("Hepsi").tag(MoveKind?.none)
                    Label("Bisiklet", systemImage: "bicycle").tag(MoveKind?.some(.bike))
                    Label("Yürüyüş", systemImage: "figure.walk").tag(MoveKind?.some(.walk))
                }
            } label: { Image(systemName: kind?.symbol ?? "line.3.horizontal.decrease.circle").frame(width: 36, height: 36) }
            .accessibilityLabel("Tür: \(kind?.name ?? "hepsi")")
        }
        .font(.system(size: 17, weight: .semibold))
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            if v.translation.width > 0, offset > earliest { withAnimation(.smooth) { offset -= 1 } }
            if v.translation.width < 0, offset < 0 { withAnimation(.smooth) { offset += 1 } }
        })
    }

    private func title(_ a: Date, _ z: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        switch span {
        case .day: f.dateFormat = "d MMMM EEEE"; return f.string(from: a)
        case .week:
            f.dateFormat = "d MMM"
            return "\(f.string(from: a)) – \(f.string(from: z))"
        case .month: f.dateFormat = "LLLL yyyy"; return f.string(from: a)
        }
    }

    private func totals(_ w: [Workout]) -> some View {
        let km = w.reduce(0) { $0 + $1.distance } / 1000
        let moving = w.reduce(0) { $0 + $1.moving }
        let kcal = w.reduce(0) { $0 + $1.calories }
        let steps = w.reduce(0) { $0 + $1.steps }
        let climb = w.reduce(0) { $0 + $1.climb }
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            tile("km", String(format: "%.1f", km).replacingOccurrences(of: ".", with: ","), "point.topleft.down.to.point.bottomright.curvepath", .orange)
            tile("hareket", StatFormat.minutes(moving / 60), "timer", .teal)
            tile("kcal", "\(Int(kcal.rounded()))", "flame.fill", .red)
            tile("adım", StatFormat.number(steps), "shoeprints.fill", .green)
            tile("tırmanış", "\(Int(climb.rounded())) m", "mountain.2.fill", .brown)
            tile("yol", "\(w.count)", "map.fill", .indigo)
        }
    }

    private func tile(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon).font(.caption2.weight(.semibold)).foregroundStyle(color).lineLimit(1)
            Text(value).font(.system(size: 19, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    private struct Bar: Identifiable { var id: String { "\(day)\(kind)" }; var day: Date; var kind: String; var km: Double }

    /// km on each day of the week or month, bicycle and walking stacked.
    private func chart(_ a: Date, _ z: Date) -> some View {
        var bars: [Bar] = []
        var d = a
        while d <= z {
            let w = ways(d, d)
            for k in MoveKind.allCases {
                bars.append(Bar(day: d, kind: k.name, km: w.filter { $0.kind == k }.reduce(0) { $0 + $1.distance } / 1000))
            }
            d = cal.date(byAdding: .day, value: 1, to: d) ?? z.addingTimeInterval(86400)
        }
        return Chart(bars) { b in
            BarMark(x: .value("Gün", b.day, unit: .day), y: .value("km", b.km))
                .foregroundStyle(by: .value("Tür", b.kind))
                .cornerRadius(3)
        }
        .chartForegroundStyleScale(["Bisiklet": Color.orange, "Yürüyüş": Color.green])
        .chartYAxisLabel("km")
        .frame(height: 150)
    }

    /// The ways of the period, under a heading for each day.
    private func days(_ w: [Workout]) -> some View {
        let groups = Dictionary(grouping: w) { cal.startOfDay(for: $0.start) }.sorted { $0.key > $1.key }
        return VStack(alignment: .leading, spacing: 14) {
            ForEach(groups, id: \.key) { day, list in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(String(format: "%.1f km", list.reduce(0) { $0 + $1.distance } / 1000).replacingOccurrences(of: ".", with: ","))
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    ForEach(list) { x in
                        Button { open = x } label: { WayRow(way: x) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - the map of a period

/// Every way of the period on one map, each in its kind's colour, with its start (green) and end (red).
struct RoutesMap: View {
    let ways: [Workout]

    var body: some View {
        Map(initialPosition: .automatic, interactionModes: [.zoom, .pan]) {
            ForEach(ways.filter { $0.route.count >= 2 }) { w in
                let pts = w.route.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) }
                MapPolyline(coordinates: pts).stroke(w.kind == .bike ? Color.orange : Color.green, lineWidth: 4)
                if let a = pts.first { Annotation("", coordinate: a) { dot(.green) } }
                if let z = pts.last { Annotation("", coordinate: z) { dot(.red) } }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .id(ways.map(\.id))                     // a new period: the map frames its own ways
    }

    private func dot(_ c: Color) -> some View {
        Circle().fill(c).frame(width: 10, height: 10).overlay(Circle().stroke(.white, lineWidth: 2))
    }
}

// MARK: - one way

private struct WayRow: View {
    @Environment(AppModel.self) private var model
    let way: Workout

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: way.kind.symbol).font(.system(size: 16, weight: .semibold))
                .foregroundStyle(way.kind == .bike ? Color.orange : Color.green).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(way.start.formatted(date: .omitted, time: .shortened)) · \(way.kind.name)").font(.subheadline.weight(.medium))
                Text(WayDetail.summary(way)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                let titles = way.documents.compactMap { model.store.document($0)?.title }
                if !titles.isEmpty {
                    Label(titles.joined(separator: " · "), systemImage: "headphones").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if way.end == nil { Text("sürüyor").font(.caption2.weight(.bold)).foregroundStyle(.orange) }
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
    }
}

/// A way on its own: its map, its numbers and the books heard on it.
struct WayDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let way: Workout

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if way.route.count >= 2 {
                        RoutesMap(ways: [way]).frame(height: 320).clipShape(RoundedRectangle(cornerRadius: 18))
                    } else {
                        Text("Bu yolun rotası yok (konum alınamamış).").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                        row("Başlangıç", way.start.formatted(date: .abbreviated, time: .shortened))
                        row("Süre", MoveStrip.clock(way.duration) + " · hareket " + StatFormat.minutes(way.moving / 60))
                        row("Mesafe", MoveStrip.km(way.distance) + " km")
                        row("Kalori", "\(Int(way.calories.rounded())) kcal")
                        if way.kind == .bike {
                            row("Hız", "ort. \(Int(way.averageSpeed.rounded())) · en çok \(Int(way.maxSpeed.rounded())) km/sa")
                        } else {
                            row("Adım", "\(way.steps)")
                        }
                        row("Tırmanış", "↑\(Int(way.climb.rounded())) m · ↓\(Int(way.descent.rounded())) m")
                    }
                    let titles = way.documents.compactMap { model.store.document($0)?.title }
                    if !titles.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Yolda dinlenenler").font(.subheadline.weight(.semibold))
                            ForEach(titles, id: \.self) { Label($0, systemImage: "headphones").font(.subheadline) }
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("\(way.kind.name) · \(way.start.formatted(.dateTime.day().month(.abbreviated)))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Kapat") { dismiss() } } }
        }
        .presentationDetents([.large])
    }

    private func row(_ k: String, _ v: String) -> some View {
        GridRow {
            Text(k).foregroundStyle(.secondary)
            Text(v).monospacedDigit()
        }
        .font(.subheadline)
    }

    static func summary(_ x: Workout) -> String {
        var p = [String(format: "%.2f km", x.distance / 1000).replacingOccurrences(of: ".", with: ","),
                 StatFormat.minutes(x.moving / 60), "\(Int(x.calories.rounded())) kcal"]
        if x.kind == .walk, x.steps > 0 { p.append("\(x.steps) adım") }
        if x.kind == .bike, x.averageSpeed > 0 { p.append("ort. \(Int(x.averageSpeed.rounded())) km/sa") }
        if x.climb >= 1 { p.append("↑\(Int(x.climb.rounded())) m") }
        return p.joined(separator: " · ")
    }
}
