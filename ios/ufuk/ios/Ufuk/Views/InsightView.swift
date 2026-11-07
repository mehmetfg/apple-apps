// Ben ve hava: the learned base layer threshold, what the weather does to the person's days, the record.
import Charts
import SwiftUI

struct InsightView: View {
    @EnvironmentObject var s: Store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    findingsCard.rise()
                    daysCard.rise(0.06)
                    historyCard.rise(0.12)
                    thresholdCard.rise(0.18)
                }
                .padding(.horizontal, 16).padding(.bottom, 30)
            }
            .scrollContentBackground(.hidden)
            .background(SkyBackground(state: s.skyState))
            .navigationTitle("Ben ve hava")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task { await s.loadInsights() }
            .refreshable { await s.loadInsights(force: true) }
        }
    }

    private var thresholdCard: some View {
        let th = s.thresholds
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "İçlik eşiğin", symbol: "tshirt")
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "%.1f°", th.baseLayer)).font(.system(size: 44, weight: .semibold, design: .rounded))
                Text("bisiklette hissedilen").foregroundStyle(Palette.soft)
            }
            Text(th.samples == 0 ? "Başlangıç değeri. Her yolculuktan sonra bir dokunuşla senin bedenine göre kayar."
                 : "\(th.samples) yolculuktan öğrenildi. Altında içlik, \(String(format: "%.1f°", th.windproof)) altında üstüne rüzgârlık.")
                .font(.footnote).foregroundStyle(Palette.soft)
            if !s.feedback.isEmpty {
                Chart {
                    ForEach(s.feedback) { f in
                        PointMark(x: .value("Hissedilen", f.rideFeel), y: .value("İçlik", f.baseLayer ? "içlikli" : "içliksiz"))
                            .foregroundStyle(by: .value("His", f.feel.label))
                            .symbolSize(90)
                    }
                    RuleMark(x: .value("Eşik", th.baseLayer)).foregroundStyle(.white).lineStyle(.init(lineWidth: 2, dash: [5, 3]))
                }
                .chartForegroundStyleScale(["Üşüdüm": Color.cyan, "Tam": Color.green, "Terledim": Color.orange])
                .chartXAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(.white.opacity(0.15)); AxisValueLabel().foregroundStyle(.white) } }
                .chartYAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(.white) } }
                .chartLegend(position: .bottom)
                .frame(height: 140)
            }
        }
        .foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }

    private var findingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Hava sende ne değiştiriyor", symbol: "waveform.path.ecg")
            if s.findings.isEmpty {
                Text(s.records.isEmpty
                     ? "Son 60 günün havası ve Apple Sağlık verin yükleniyor."
                     : "Henüz gürültüden ayrılan bir fark yok. Her iki tarafta en az \(Insights.minEach) gün gerekiyor; ruh hâli ve yolculuk kayıtları biriktikçe netleşir.")
                    .font(.callout).foregroundStyle(Palette.soft)
            }
            ForEach(s.findings.prefix(8)) { f in
                VStack(alignment: .leading, spacing: 4) {
                    Text(f.text).font(.callout)
                    Text("\(f.na) ve \(f.nb) gün").font(.caption2).foregroundStyle(Palette.soft)
                }
            }
            Text("Kaynak: Open-Meteo geçmiş günleri, Apple Sağlık (adım, yürüyüş, bisiklet, uyku), Tekne üretim dakikaları, senin ruh hâli kayıtların. Benzerlik neden değildir; yalnız örüntüyü gösterir.")
                .font(.caption2).foregroundStyle(Palette.soft)
        }
        .foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }

    private var daysCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Son günler", symbol: "calendar")
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow { Text("Gün"); Text("Yağış"); Text("°C"); Text("Adım"); Text("Bisiklet"); Text("His") }
                    .font(.caption.weight(.semibold)).foregroundStyle(Palette.soft)
                ForEach(s.records.prefix(14)) { r in
                    GridRow {
                        Text(Fmt.short.string(from: r.day))
                        Text(r.weather.map { $0.rainMM >= 0.1 ? String(format: "%.1f", $0.rainMM) : "—" } ?? "")
                        Text(r.weather.map { "\(Int($0.tMin))–\(Int($0.tMax))" } ?? "")
                        Text(r.health?.steps.map { Insights.fmt($0, "") } ?? "—")
                        Text(r.health?.cycleKm.map { String(format: "%.1f", $0) } ?? "—")
                        Text(r.mood.map { "\($0)/5" } ?? "—")
                    }
                    .font(.caption.monospacedDigit())
                }
            }
        }
        .foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Yolculuk kayıtların", symbol: "list.bullet")
            if s.feedback.isEmpty { Text("Henüz kayıt yok.").font(.callout).foregroundStyle(Palette.soft) }
            ForEach(s.feedback.sorted { $0.date > $1.date }.prefix(20)) { f in
                HStack {
                    Image(systemName: f.feel.symbol)
                    Text("\(Fmt.short.string(from: f.date)) \(f.leg == .morning ? "sabah" : "akşam")")
                    Spacer()
                    Text("\(Fmt.deg(f.rideFeel)) · \(f.baseLayer ? "içlikli" : "içliksiz")").foregroundStyle(Palette.soft)
                    Button(role: .destructive) { withAnimation { s.removeFeedback(f) } } label: { Image(systemName: "xmark.circle") }
                        .accessibilityLabel("Kaydı sil")
                }
                .font(.callout)
            }
        }
        .foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }
}
