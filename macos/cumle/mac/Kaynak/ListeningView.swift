// Dinleme (⌘3, kenar çubuğu › Arşiv): telefonda (Memories) neyi ne kadar dinledin.
// Kaynak: oncalisma/ilerleme/*.jsonl — yeni `listened` parçaları (yarım dinleme dahil, saniye + duyulan cümleler)
// ve eski `dinledi` olayları (yalnız ≥ %80 dinleme; süre tahmini, "≈" ile gösterilir). Salt okur.
import SwiftUI
import Charts

struct ListeningView: View {
    @EnvironmentObject var t: Tezgah
    var compact = false            // Genel bakış'ın içinde: yalnız özet + grafik

    var body: some View {
        let rows = Listening.build(t.events)
        let daily = Listening.daily(rows, events: t.events, days: 14)
        let total = rows.reduce(0) { $0 + $1.seconds }
        let week = daily.suffix(7).reduce(0) { $0 + $1.1 }
        let activeDays = daily.filter { $0.1 > 0 }.count
        let content = VStack(alignment: .leading, spacing: 18) {
            if !compact {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dinleme").font(.largeTitle.bold())
                    Text("Telefonda (Memories) dinlediklerin — yarım dinlemeler de sayılır. Telefon her dinleme parçasını vault'a yazar; burası birkaç saniyede bir tazelenir.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 10) {
                Kutu(k: "toplam dinleme", v: Listening.minutes(total), renk: Renk.vurgu)
                Kutu(k: "son 7 gün", v: Listening.minutes(week))
                Kutu(k: "dinlenen paket", v: "\(rows.count) gün")
                Kutu(k: "tam dinleme (≥%80)", v: "\(rows.reduce(0) { $0 + $1.fullPlays })×")
                Kutu(k: "14 günde dinlediğin gün", v: "\(activeDays)")
            }
            Kart {
                Baslik(metin: "Son 14 gün", alt: "dakika · takvim günü")
                Chart {
                    ForEach(daily, id: \.0) { d, s in
                        BarMark(x: .value("Gün", d, unit: .day), y: .value("dk", s / 60))
                            .foregroundStyle(Calendar.current.isDateInToday(d) ? Renk.vurgu.gradient : Renk.vurgu.opacity(0.55).gradient)
                            .cornerRadius(4)
                    }
                }
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: 2)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
                .frame(height: compact ? 140 : 190)
                if rows.contains(where: \.estimated) {
                    Text("≈ eski olaylar: telefon eskiden yalnız sesin %80'i dinlenince yazıyordu; o günlerin süresi tahmindir.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !compact {
                Kart {
                    Baslik(metin: "Paket paket", alt: "en yeni önce · şerit = metnin cümleleri, koyuluk = kaç kez duyuldu")
                    if rows.isEmpty {
                        Text("Henüz telefondan dinleme gelmedi. Memories'te bir paketi dinle; birkaç saniye sonra burada görünür.").foregroundStyle(.secondary)
                    }
                    ForEach(rows) { r in
                        VStack(spacing: 8) { DayListeningRow(r: r); if r.id != rows.last?.id { Divider() } }
                    }
                }
            }
        }
        if compact { content } else { Sutun(genislik: 900) { content } }
    }
}

struct DayListeningRow: View {
    var r: DayListening
    @EnvironmentObject var t: Tezgah
    var body: some View {
        let g = t.tumGunler.first { $0.no == r.day }
        let a = t.arsiv.gunler.first { $0.gun == r.day }
        let count = g?.cumleler.count ?? a?.cumleler.count ?? 0
        let heard = r.sentenceHits.keys.filter { $0 < max(count, 1) }.count
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Gün \(r.day)").font(.headline).foregroundStyle(Renk.vurgu)
                Text(g?.ad ?? a?.baslik ?? "—").font(.body.weight(.medium)).lineLimit(1)
                Spacer()
                Text((r.estimated ? "≈ " : "") + Listening.minutes(r.seconds)).font(.body.monospacedDigit().weight(.semibold))
            }
            HStack(spacing: 14) {
                Label("\(r.fullPlays)× tam", systemImage: "checkmark.circle").foregroundStyle(r.fullPlays > 0 ? Renk.yesil : .secondary)
                if !r.stretches.isEmpty { Label("\(r.stretches.count) parça", systemImage: "waveform") }
                if let l = r.audioLength, l > 0 { Label("ses \(Listening.minutes(l))", systemImage: "clock") }
                if count > 0, !r.sentenceHits.isEmpty { Label("cümlelerin %\(Int((Double(heard) / Double(count) * 100).rounded()))'ı duyuldu", systemImage: "text.alignleft") }
                if let l = r.last { Text("son: " + l.formatted(.dateTime.day().month(.abbreviated).hour().minute())).foregroundStyle(.tertiary) }
            }
            .font(.caption).foregroundStyle(.secondary)
            if count > 0 && !r.sentenceHits.isEmpty {
                let top = max(r.sentenceHits.values.max() ?? 1, 1)
                HStack(spacing: 3) {
                    ForEach(0..<count, id: \.self) { i in
                        let n = r.sentenceHits[i] ?? 0
                        RoundedRectangle(cornerRadius: 3)
                            .fill(n == 0 ? Color.secondary.opacity(0.15) : Renk.vurgu.opacity(0.3 + 0.7 * Double(n) / Double(top)))
                            .frame(height: 16)
                            .help("Cümle \(i + 1): \(n == 0 ? "duyulmadı" : "\(n)×")" + ((g?.cumleler[safe: i]?.en).map { " — " + $0 } ?? ""))
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
