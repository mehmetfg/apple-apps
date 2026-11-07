// Bugün: the two commute decisions, what to wear, what can hurt, lunch and the light, on one screen.
import SwiftUI

struct TodayView: View {
    @EnvironmentObject var s: Store
    @State private var settings = false
    @State private var feedbackLeg: LegKind?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    DepartureHero().rise()
                    if s.home == nil || s.work == nil { setupCard.rise(0.04) }
                    if let e = s.error { Text(e).font(.footnote).foregroundStyle(.white).glassCard(18, tint: .red) }
                    HoursCard(hours: s.hours, departure: s.nextLeg?.best).rise(0.06)
                    LightCard().rise(0.09)
                    OutingTodayCard().rise(0.12)
                    ForEach(orderedLegs) { leg in LegCard(leg: leg, ask: { feedbackLeg = leg.kind }).rise(0.15) }
                    if let l = s.lunch { lunchCard(l).rise(0.18) }
                    WardrobeCard().rise(0.2)
                    MoodRow().rise(0.22)
                    sources
                }
                .padding(.horizontal, 16).padding(.bottom, 30)
            }
            .scrollContentBackground(.hidden)
            .refreshable { await s.refresh() }
            .background(SkyBackground(state: s.skyState))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { settings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Ayarlar")
                }
                ToolbarItem(placement: .topBarLeading) {
                    if s.loading { ProgressView().tint(.white) }
                }
            }
            .sheet(isPresented: $settings) { SettingsView() }
            .sheet(item: $feedbackLeg) { FeedbackSheet(kind: $0) }
        }
    }

    /// The leg that comes next goes first.
    private var orderedLegs: [Leg] {
        [s.morning, s.evening].compactMap { $0 }.sorted { $0.windowStart < $1.windowStart }
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Ev ve işini işaretle", systemImage: "mappin.and.ellipse").font(.headline)
            Text("Tahmin iki nokta arasındaki yol için alınır; öğle yerleri işin, akşam rotası evin çevresinden gelir.")
                .font(.footnote).foregroundStyle(Palette.soft)
            Button("Haritadan seç") { settings = true }.buttonStyle(.borderedProminent).tint(.white.opacity(0.25))
        }
        .foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).glassCard(tint: .orange)
    }

    private func lunchCard(_ l: Lunch) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(text: "Öğle arası" + (l.slots.first.map { Calendar.current.isDateInTomorrow($0.time) } == true ? " · yarın" : ""), symbol: "figure.walk")
                Spacer()
                if let st = l.start { Text("\(Fmt.t(st))'dan").font(.caption).foregroundStyle(Palette.soft) }
            }
            Text(l.verdict).font(.title3.weight(.semibold))
            if !l.slots.isEmpty { RainStrip(slots: l.slots, planned: nil, best: nil, height: 28) }
        }
        .foregroundStyle(.white).glassCard()
    }

    private var sources: some View {
        VStack(spacing: 4) {
            if let f = s.forecast {
                Text("\(f.models.joined(separator: " · ")) · \(f.members) senaryoluk topluluk\(s.appleStatus == .ok ? " · Apple Hava" : "")")
                Text("Güncellendi \(Fmt.t(f.fetched))")
            }
        }
        .font(.caption2).foregroundStyle(Palette.soft).frame(maxWidth: .infinity).padding(.top, 4)
    }
}

extension LegKind: Identifiable { var id: String { rawValue } }

struct LegCard: View {
    @EnvironmentObject var s: Store
    var leg: Leg
    var ask: () -> Void
    @State private var open = false

    var tint: Color? {
        if leg.hazards.contains(where: { $0.level == .danger }) { return .red }
        return leg.plannedMax >= 0.45 ? .orange : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle(text: leg.title + (Calendar.current.isDateInTomorrow(leg.day) ? " · yarın" : ""),
                             symbol: leg.kind == .morning ? "sunrise" : "sunset")
                Spacer()
                Text("güven \(Fmt.pct(leg.confidence))").font(.caption2).foregroundStyle(Palette.soft)
            }
            Text(leg.verdict).font(.title2.weight(.semibold)).contentTransition(.opacity)
            Text(leg.detail).font(.callout).foregroundStyle(Palette.soft)
            RainStrip(slots: leg.slots, planned: leg.planned, best: leg.best, rideMinutes: leg.rideMinutes)
            HStack(spacing: 8) {
                if let f = leg.feel { Tag(text: "Bisiklette \(Fmt.deg(f))", symbol: "bicycle") }
            }
            ForEach(leg.hazards, id: \.self) { h in
                Label(h.text, systemImage: h.symbol).font(.callout.weight(.medium))
                    .foregroundStyle(h.level == .danger ? Color(red: 1, green: 0.75, blue: 0.75) : .white)
            }
            HStack {
                Button { RideActivity.start(s, kind: leg.kind) } label: { Label("Yola çıkıyorum", systemImage: "bicycle") }
                Spacer()
                Button(action: ask) { Label("Nasıldı?", systemImage: "hand.raised") }
            }
            .font(.callout.weight(.semibold)).buttonStyle(.bordered).tint(.white)
        }
        .foregroundStyle(.white)
        .glassCard(tint: tint)
    }
}

struct MoodRow: View {
    @EnvironmentObject var s: Store
    private let faces = ["cloud.heavyrain", "cloud", "cloud.sun", "sun.min", "sun.max"]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Bugün nasılsın", symbol: "heart.text.square")
            HStack {
                ForEach(1...5, id: \.self) { i in
                    let on = s.mood(on: .now) == i
                    Button { withAnimation(.spring) { s.setMood(i) } } label: {
                        Image(systemName: faces[i - 1] + (on ? ".fill" : "")).font(.title2)
                            .symbolRenderingMode(on ? .multicolor : .monochrome)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .scaleEffect(on ? 1.15 : 1)
                    }
                    .accessibilityLabel("Ruh hâli \(i)")
                }
            }
            .sensoryFeedback(.selection, trigger: s.mood(on: .now))
        }
        .foregroundStyle(.white).glassCard()
    }
}
