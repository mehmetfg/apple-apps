// Göstergeler: the list of lab markers by area, and one marker with its history against the reference range.
import Charts
import SwiftUI

struct MarkerCard: View {
    var marker: Marker
    var state: SBSState

    var body: some View {
        NavigationLink { MarkerDetail(marker: marker, state: state) } label: {
            Card(padding: 14) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(marker.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        HStack(spacing: 6) {
                            ToneDot(tone: Tone(status: marker.status))
                            Text(marker.stale ? "Eski ölçüm" : Tone(status: marker.status).label).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    let nums = marker.numericPoints.compactMap(\.value)
                    if nums.count > 1 {
                        Sparkline(values: nums, low: marker.refLow, high: marker.refHigh, color: Tone(status: marker.status).color)
                            .frame(width: 64, height: 30)
                    }
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(marker.lastShown).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(.primary)
                        Text(marker.unit.isEmpty ? " " : marker.unit).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 62, alignment: .trailing)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct MarkerList: View {
    var state: SBSState
    var area: String?
    @State private var onlyOut = false
    @State private var query = ""

    var body: some View {
        let order = ["heart", "metabolism", "liver", "kidney", "blood", "immune", "thyroid", "muscle", "infection", "other"]
        let names = ["heart": "Kalp ve damar", "metabolism": "Metabolizma", "liver": "Karaciğer", "kidney": "Böbrek ve mineraller", "blood": "Kan",
                     "immune": "Bağışıklık ve iltihap", "thyroid": "Tiroid", "muscle": "Kas", "infection": "Enfeksiyon ve bağışıklık kaydı", "other": "Diğer"]
        let shown = state.markers.filter { m in
            (area == nil || m.area == area) && (!onlyOut || ["watch", "attention"].contains(m.status))
                && (query.isEmpty || m.name.localizedCaseInsensitiveContains(query))
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Süz", selection: $onlyOut) { Text("Tümü").tag(false); Text("Aralık dışı").tag(true) }
                    .pickerStyle(.segmented)
                ForEach(order.filter { a in shown.contains { $0.area == a } }, id: \.self) { a in
                    SectionTitle(text: names[a] ?? a, trailing: "\(shown.filter { $0.area == a }.count)")
                    ForEach(shown.filter { $0.area == a }) { MarkerCard(marker: $0, state: state) }
                }
                if shown.isEmpty { Text("Eşleşen gösterge yok.").foregroundStyle(.secondary).padding(.top, 30).frame(maxWidth: .infinity) }
            }
            .padding(.horizontal, 18).padding(.bottom, 100)
        }
        .sbsGround()
        .searchable(text: $query, prompt: "Gösterge ara")
        .navigationTitle(area.flatMap { names[$0] } ?? "Göstergeler")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MarkerDetail: View {
    var marker: Marker
    var state: SBSState

    var body: some View {
        let tone = Tone(status: marker.status)
        let pts = marker.numericPoints
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(marker.lastShown).font(.system(size: 54, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(tone.color)
                        Text(marker.unit).font(.title3).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Text(marker.stale ? "Eski ölçüm" : tone.label).font(.footnote.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 4).background(tone.color.opacity(0.16), in: Capsule()).foregroundStyle(tone.color)
                        Text(Day.short(marker.lastDate)).font(.footnote).foregroundStyle(.secondary)
                    }
                    if !marker.refText.isEmpty { Text("Laboratuvar aralığı: \(marker.refText)").font(.subheadline).foregroundStyle(.secondary).padding(.top, 2) }
                }
                if pts.count > 1 {
                    Card {
                        Chart {
                            if marker.refLow != nil || marker.refHigh != nil {
                                RectangleMark(yStart: .value("Alt", marker.refLow ?? 0), yEnd: .value("Üst", marker.refHigh ?? (pts.compactMap(\.value).max() ?? 0) * 1.1))
                                    .foregroundStyle(Color.good.opacity(0.13))
                            }
                            ForEach(pts) { p in
                                LineMark(x: .value("Tarih", p.day), y: .value(marker.name, p.value ?? 0))
                                    .foregroundStyle(tone.color).lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round)).interpolationMethod(.monotone)
                                PointMark(x: .value("Tarih", p.day), y: .value(marker.name, p.value ?? 0))
                                    .foregroundStyle(tone.color).symbolSize(90)
                                    .annotation(position: .top, spacing: 6) { Text(p.shown).font(.caption2.weight(.semibold)).foregroundStyle(.secondary) }
                            }
                        }
                        .chartXAxis { AxisMarks(values: pts.map(\.day)) { AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits)) } }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 220)
                        .padding(.top, 14)
                    }
                }
                SectionTitle(text: "Bütün ölçümler")
                Card(padding: 4) {
                    VStack(spacing: 0) {
                        ForEach(marker.points.reversed()) { p in
                            HStack {
                                Text(Day.short(p.date)).font(.subheadline)
                                Spacer()
                                Text(p.shown + (marker.unit.isEmpty ? "" : " " + marker.unit)).font(.subheadline.weight(.semibold)).monospacedDigit()
                                if p.flag == "H" { Image(systemName: "arrow.up").font(.caption.weight(.bold)).foregroundStyle(Color.attention) }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                        }
                    }
                }
                let related = state.conditions.filter { $0.markers.contains(marker.id) }
                if !related.isEmpty {
                    SectionTitle(text: "Bağlı rahatsızlıklar")
                    ForEach(related) { ConditionRow(condition: $0, state: state) }
                }
                Text("Bu ekran ölçümleri anlaşılır kılar; teşhis koymaz. Aralık dışındaki değer hekime sorulacak bir bulgudur.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18).padding(.bottom, 100)
        }
        .sbsGround()
        .navigationTitle(marker.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
