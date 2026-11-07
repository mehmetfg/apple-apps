// The top of Bugün: when to leave (big), the next six hours, when light comes and when dark falls,
// where to go today, and the clothing ledger in one quiet line.
import SwiftUI

/// The departure time is the largest thing on the screen.
struct DepartureHero: View {
    @EnvironmentObject var s: Store

    var body: some View {
        let leg = s.nextLeg
        let c = s.forecast?.current
        let night = s.skyState.elevation < -0.8
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            VStack(spacing: 6) {
                if let leg {
                    let go = leg.best
                    Text((leg.title + (Calendar.current.isDateInTomorrow(leg.day) ? " · yarın" : "")).uppercased())
                        .font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(Palette.soft)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(Fmt.t(go)).font(.system(size: 84, weight: .semibold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText())
                        Text("çık").font(.title.weight(.medium)).foregroundStyle(Palette.soft)
                    }
                    HStack(spacing: 8) {
                        Tag(text: "yağış \(Fmt.pct(leg.bestMax))", symbol: leg.bestMax >= 0.4 ? "cloud.rain.fill" : "drop",
                            tint: leg.bestMax >= 0.4 ? .orange : nil)
                        if go > ctx.date {
                            Tag(text: Fmt.span(go.timeIntervalSince(ctx.date)) + " sonra", symbol: "timer")
                        } else if ctx.date < leg.windowEnd {
                            Tag(text: "çıkış zamanı", symbol: "bicycle", tint: .green)
                        }
                    }
                    if leg.best != leg.planned {
                        Text("Planın \(Fmt.t(leg.planned)) · o saatte yağış \(Fmt.pct(leg.plannedMax))")
                            .font(.footnote).foregroundStyle(Palette.soft)
                    }
                    ForEach(leg.hazards.filter { $0.level >= .caution }, id: \.self) { h in
                        Label(h.text, systemImage: h.symbol).font(.callout.weight(.medium))
                            .foregroundStyle(h.level == .danger ? Color(red: 1, green: 0.75, blue: 0.75) : .white)
                    }
                } else {
                    Text("Tahmin bekleniyor").font(.title2).foregroundStyle(Palette.soft)
                }
                HStack(spacing: 6) {
                    Image(systemName: WMO.symbol(c?.code, night: night)).symbolRenderingMode(.multicolor)
                    Text("Şimdi \(Fmt.deg(s.appleNow?.temperature ?? c?.temp)) · \(WMO.word(c?.code)) · hissedilen \(Fmt.deg(c?.feels)) · rüzgâr \(Int(c?.wind ?? 0))")
                }
                .font(.footnote).foregroundStyle(Palette.soft).padding(.top, 4)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .glassCard(tint: leg.map { $0.bestMax >= 0.45 ? Color.orange : ($0.hazards.contains { $0.level == .danger } ? .red : nil) } ?? nil)
        }
    }
}

/// Hour by hour: weather, rain chance, temperature, wind; dark hours shaded; the departure hour marked.
struct HoursCard: View {
    var hours: [HourSummary]
    var departure: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Önümüzdeki 6 saat", symbol: "clock")
            if hours.isEmpty {
                Text("Tahmin bekleniyor").foregroundStyle(Palette.soft)
            } else {
                HStack(spacing: 4) {
                    ForEach(hours, id: \.time) { h in column(h) }
                }
            }
        }
        .foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }

    private func column(_ h: HourSummary) -> some View {
        let isGo = departure.map { $0 >= h.time && $0 < h.time.addingTimeInterval(3600) } ?? false
        return VStack(spacing: 6) {
            Text(Fmt.t(h.time)).font(.caption.weight(isGo ? .bold : .regular).monospacedDigit())
            Image(systemName: WMO.symbol(h.code, night: h.dark)).symbolRenderingMode(.multicolor).font(.title3).frame(height: 24)
            Text(Fmt.deg(h.temp)).font(.callout.weight(.semibold))
            RoundedRectangle(cornerRadius: 3).fill(Palette.rain(h.prob).gradient)
                .frame(width: 8, height: max(4, 34 * h.prob)).frame(height: 34, alignment: .bottom)
            Text(Fmt.pct(h.prob)).font(.caption2.monospacedDigit()).foregroundStyle(h.prob >= 0.4 ? .white : Palette.soft)
            Label("\(Int(h.wind))", systemImage: "wind").labelStyle(.titleAndIcon).font(.caption2.monospacedDigit()).foregroundStyle(Palette.soft)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14).fill(.black.opacity(h.dark ? 0.28 : 0)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(isGo ? 0.85 : 0), lineWidth: 1.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Fmt.t(h.time)): \(WMO.word(h.code)), \(Fmt.deg(h.temp)), yağış \(Fmt.pct(h.prob))\(h.dark ? ", karanlık" : "")\(isGo ? ", çıkış saati" : "")")
    }
}

/// Aydınlanma and kararma side by side, with whichever comes first counting down.
struct LightCard: View {
    @EnvironmentObject var s: Store

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let now = ctx.date, t = s.sunToday, m = s.sunTomorrow
            let light = (t.dawn.map { now < $0 } ?? false) ? t.dawn : m.dawn
            let dark = (t.dusk.map { now < $0 } ?? false) ? t.dusk : m.dusk
            let lightFirst = (light ?? .distantFuture) < (dark ?? .distantFuture)
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: "Işık", symbol: "sun.horizon.fill")
                HStack(alignment: .top) {
                    side("Aydınlanma", light, "sunrise.fill", next: lightFirst, now: now,
                         sub: "doğuş \(Fmt.t((t.sunrise.map { now < $0 } ?? false) ? t.sunrise : m.sunrise))")
                    Divider().overlay(.white.opacity(0.3)).frame(height: 70)
                    side("Kararma", dark, "moon.haze.fill", next: !lightFirst, now: now,
                         sub: "batış \(Fmt.t((t.sunset.map { now < $0 } ?? false) ? t.sunset : m.sunset))")
                }
                Text("Gün ışığı \(Fmt.span(t.daylight)) · yarın \(dayDelta(t, m))")
                    .font(.caption).foregroundStyle(Palette.soft)
            }
            .foregroundStyle(.white).glassCard()
        }
    }

    private func side(_ name: String, _ d: Date?, _ sym: String, next: Bool, now: Date, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(name, systemImage: sym).symbolRenderingMode(.multicolor).font(.footnote.weight(.semibold)).foregroundStyle(Palette.soft)
            Text(Fmt.t(d)).font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
            if next, let d { Text(Fmt.span(d.timeIntervalSince(now)) + " sonra").font(.caption.weight(.semibold)) }
            Text(sub + ((d.map { Calendar.current.isDateInTomorrow($0) } ?? false) ? " · yarın" : "")).font(.caption2).foregroundStyle(Palette.soft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dayDelta(_ a: SunDay, _ b: SunDay) -> String {
        let d = Int(((b.daylight - a.daylight) / 60).rounded())
        return d == 0 ? "aynı" : (d < 0 ? "\(-d) dk kısa" : "\(d) dk uzun")
    }
}

/// Today's first place from the weekly plan, with the week's progress.
struct OutingTodayCard: View {
    @EnvironmentObject var s: Store

    var body: some View {
        let opts = s.outings
        let target = s.spots.map(\.weeklyTarget).reduce(0, +)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(text: "Bugün dışarı", symbol: "figure.walk.motion")
                Spacer()
                Text("bu hafta \(min(s.weekVisits.count, target))/\(target)").font(.caption.monospacedDigit()).foregroundStyle(Palette.soft)
            }
            if let o = opts.first(where: { !$0.visitedToday }) ?? opts.first {
                HStack(spacing: 12) {
                    Image(systemName: o.spot.symbol).font(.title2).frame(width: 40, height: 40).glassPill(tint: .green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(o.spot.name).font(.title3.weight(.semibold))
                        Text("bu hafta \(o.progress) · \(o.reason)").font(.caption).foregroundStyle(Palette.soft)
                    }
                }
                let rest = opts.filter { $0.id != o.id && !$0.visitedToday && $0.done < $0.spot.weeklyTarget }.prefix(2)
                if !rest.isEmpty {
                    Text("Sonra: " + rest.map { "\($0.spot.name) \($0.progress)" }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(Palette.soft)
                }
            }
        }
        .foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }
}

/// One line: what is worn now, and what last year says. The full ledger is one tap away.
struct WardrobeCard: View {
    @EnvironmentObject var s: Store

    var body: some View {
        NavigationLink { WardrobeView() } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    SectionTitle(text: "Giyim Defteri", symbol: "tshirt")
                    Spacer()
                    Text(s.currentGarment?.label ?? "kayıt yok").font(.callout.weight(.semibold))
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.soft)
                }
                if let h = s.wardrobeHint {
                    Text(h.title).font(.callout)
                    Text(h.reached ?? h.detail).font(.caption).foregroundStyle(Palette.soft)
                } else if s.wardrobe.isEmpty {
                    Text("Kısa koldan uzun kola geçtiğin günü kaydet; gelecek yıl o gün yaklaşınca burada görünür.")
                        .font(.caption).foregroundStyle(Palette.soft).multilineTextAlignment(.leading)
                }
            }
            .foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .glassCard()
    }
}
