// Giyim Defteri: tap what you wear from today on. Each change keeps the weather of that day; the
// years sit on one line so the same change can be seen coming next year.
import Charts
import SwiftUI

struct WardrobeView: View {
    @EnvironmentObject var s: Store
    @State private var past = false
    @State private var pastDate = Date.now
    @State private var pastGarment: Garment = .longSleeve

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                nowCard
                if let h = s.wardrobeHint { hintCard(h) }
                if Set(s.wardrobe.map { Calendar.current.component(.year, from: $0.date) }).count >= 1, !s.wardrobe.isEmpty { yearsChart }
                ForEach(Wardrobe.byYear(s.wardrobe), id: \.year) { y in yearCard(y.year, y.items) }
            }
            .padding(.horizontal, 16).padding(.bottom, 30)
        }
        .scrollContentBackground(.hidden)
        .background(SkyBackground(state: s.skyState))
        .navigationTitle("Giyim Defteri")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $past) { pastSheet }
    }

    private var nowCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Bugünden itibaren", symbol: "tshirt")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(Garment.allCases, id: \.self) { g in
                    let on = s.currentGarment == g
                    Button { withAnimation(.spring) { s.recordGarment(g) } } label: {
                        VStack(spacing: 6) {
                            Image(systemName: g.symbol).font(.title2)
                            Text(g.label).font(.callout.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 74)
                        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(on ? 0.28 : 0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(on ? 0.9 : 0), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .sensoryFeedback(.selection, trigger: s.currentGarment)
            Text("Dokunduğun an bugünün sıcaklığı, hissedileni, rüzgârı ve gün uzunluğuyla birlikte yazılır. Geri dönüş de (uzun koldan kısaya) kayıttır.")
                .font(.caption).foregroundStyle(Palette.soft)
            Button("Daha önceki bir günü ekle") { past = true }.font(.footnote.weight(.semibold))
        }
        .foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }

    private func hintCard(_ h: WardrobeHint) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: "Geçen yıldan", symbol: "calendar.badge.clock")
            Text(h.title).font(.title3.weight(.semibold))
            Text(h.detail).font(.callout).foregroundStyle(Palette.soft)
            if let r = h.reached { Label(r, systemImage: "thermometer.low").font(.callout.weight(.medium)) }
        }
        .foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).glassCard(tint: h.reached != nil ? .blue : nil)
    }

    /// Every change on a January–December axis, one row per year.
    private var yearsChart: some View {
        let ref = Calendar.current.component(.year, from: .now)
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Yıllar yan yana", symbol: "chart.dots.scatter")
            Chart(s.wardrobe) { c in
                let y = Calendar.current.component(.year, from: c.date)
                let md = Calendar.current.dateComponents([.month, .day], from: c.date)
                let onRef = Calendar.current.date(from: DateComponents(year: ref, month: md.month, day: md.day, hour: 12)) ?? c.date
                PointMark(x: .value("Gün", onRef), y: .value("Yıl", String(y)))
                    .symbol { Image(systemName: c.to.symbol).font(.caption) }
                    .foregroundStyle(.white)
                    .annotation(position: .top) { Text(Fmt.deg(c.feels)).font(.system(size: 9)).foregroundStyle(Palette.soft) }
            }
            .chartXScale(domain: (Calendar.current.date(from: DateComponents(year: ref, month: 1, day: 1)) ?? .now)...(Calendar.current.date(from: DateComponents(year: ref, month: 12, day: 31)) ?? .now))
            .chartXAxis { AxisMarks(values: .stride(by: .month, count: 2)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)).foregroundStyle(Palette.soft) } }
            .chartYAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(Palette.soft) } }
            .frame(height: CGFloat(60 + 34 * Set(s.wardrobe.map { Calendar.current.component(.year, from: $0.date) }).count))
        }
        .foregroundStyle(.white).glassCard()
    }

    private func yearCard(_ year: Int, _ items: [GarmentChange]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: String(year), symbol: "calendar")
            ForEach(items) { c in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: c.to.symbol).font(.title3).frame(width: 34, height: 34).glassPill(tint: c.warmer ? .orange : .blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Wardrobe.dm.string(from: c.date)) · \(c.from.map { "\($0.label) → " } ?? "")\(c.to.label)").font(.callout.weight(.semibold))
                        Text(detail(c)).font(.caption).foregroundStyle(Palette.soft)
                    }
                    Spacer()
                }
                .contextMenu { Button("Sil", systemImage: "trash", role: .destructive) { s.removeGarment(c) } }
            }
        }
        .foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }

    private func detail(_ c: GarmentChange) -> String {
        var p: [String] = []
        if let t = c.temp { p.append("hava \(Fmt.deg(t))") }
        if let f = c.feels { p.append("hissedilen \(Fmt.deg(f))") }
        if let lo = c.tMin, let hi = c.tMax { p.append("gün \(Fmt.deg(lo))–\(Fmt.deg(hi))") }
        if let w = c.wind { p.append("rüzgâr \(Int(w))") }
        p.append("ışık \(Fmt.span(TimeInterval(c.daylightMin * 60)))")
        return p.joined(separator: " · ")
    }

    private var pastSheet: some View {
        NavigationStack {
            Form {
                DatePicker("Gün", selection: $pastDate, in: ...Date.now, displayedComponents: .date)
                Picker("Geçtiğin", selection: $pastGarment) { ForEach(Garment.allCases, id: \.self) { Text($0.label).tag($0) } }
                Text("Geçmiş günün havası tahminde yoksa yalnız gün uzunluğu yazılır.").font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("Önceki bir gün")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { past = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ekle") { s.recordGarment(pastGarment, date: Decision.at(pastDate, 8 * 60)); past = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
