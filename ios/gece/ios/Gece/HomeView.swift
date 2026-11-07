// Home: tonight's set and start, the habit ladder, the three sets to memorise, the moves library, the last nights, settings.
import Charts
import PDMBus
import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var health: Health
    @Binding var startNow: Bool
    @State private var running: NightPlan?
    @State private var settings = false
    @State private var detail: Move?

    private var plan: NightPlan {
        store.tonightPlan(legHeavy: health.today?.legHeavy ?? false)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    tonight
                    habitCard
                    setsCard
                    if let d = health.today { todayCard(d) }
                    if store.nights.count >= 2 { trend }
                    library
                    Text("Hareketler fizyoterapide yaygın kabul gören temel hareketlerdir; kişisel bir değerlendirmenin yerini tutmaz. Hareket sırasında ağrı 10 üzerinden 5'i geçerse o hareketi bırak.")
                        .font(.footnote).foregroundStyle(Theme.soft).padding(.top, 4)
                }
                .padding(20)
            }
            .background(Theme.night.ignoresSafeArea())
            .navigationTitle("Gece")
            .toolbar {
                Button { settings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Ayarlar")
            }
            .sheet(isPresented: $settings) { SettingsView() }
            .sheet(item: $detail) { MoveDetail(move: $0) }
            .fullScreenCover(item: $running) { p in
                SessionView(plan: p) { running = nil }
            }
            .onChange(of: startNow) { _, v in
                if v { running = plan; startNow = false }
            }
            .onAppear { if startNow { running = plan; startNow = false } }
        }
        .tint(Theme.amber)
    }

    private var tonight: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.tonightDone == nil ? "BU GECE · KÜLTÜR FİZİK" : "BU GECE · YAPILDI").font(.caption.weight(.semibold)).tracking(1.2)
                        .foregroundStyle(Theme.amber)
                    Text(plan.short ? "Mini gece · \(plan.set.title)" : "Beşli \(plan.set.title)").font(.title2.bold()).foregroundStyle(Theme.ink)
                    Text("\(plan.totalSeconds.minutesText) · \(plan.nightNo). gece · yatış \(store.bedtimeText)").foregroundStyle(Theme.soft)
                }
                Spacer()
                Image(systemName: store.tonightDone == nil ? "moon.stars" : "moon.zzz.fill").font(.system(size: 34)).foregroundStyle(Theme.amber)
            }
            Text(plan.reason).font(.footnote).foregroundStyle(Theme.soft)
            if !store.anchor.isEmpty {
                Label("\(store.anchor) → beşli", systemImage: "link").font(.footnote).foregroundStyle(Theme.ink)
            }
            if store.missedYesterday {
                Label("Dün kaçtı. Bu gece en az mini gece (2 dk): iki gece üst üste kaçırma.", systemImage: "exclamationmark.arrow.circlepath")
                    .font(.footnote).foregroundStyle(Theme.rose)
            }
            ForEach(plan.swaps.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                Text("\(Catalog.shared.move(k)?.name ?? k) son gecelerde ağrıttı; yerine \(Catalog.shared.move(v)?.name ?? v).")
                    .font(.footnote).foregroundStyle(Theme.soft)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(uniqueMoves(plan), id: \.id) { m in
                        Button { detail = m } label: {
                            VStack(spacing: 6) {
                                MoveThumb(move: m).frame(width: 92, height: 66)
                                    .overlay(alignment: .topLeading) {
                                        Text("\(m.slot)").font(.caption2.bold()).frame(width: 18, height: 18)
                                            .background(Theme.amber, in: Circle()).foregroundStyle(Theme.night)
                                    }
                                Text(m.name).font(.caption2).foregroundStyle(Theme.ink).lineLimit(2).multilineTextAlignment(.center).frame(width: 92)
                            }
                            .padding(8).background(Theme.night.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            Button { running = plan } label: {
                Label(store.tonightDone == nil ? "Başla" : "Yeniden yap", systemImage: "play.fill")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Theme.amber, in: Capsule()).foregroundStyle(Theme.night)
            }
        }
        .card()
    }

    private func uniqueMoves(_ p: NightPlan) -> [Move] {
        var seen = Set<String>()
        return p.steps.map(\.move).filter { seen.insert($0.id).inserted }
    }

    /// Where the habit is: the four phases, practised nights, streak, last automaticity score.
    private var habitCard: some View {
        let done = store.practiceDays.count
        let ph = store.phase
        return VStack(alignment: .leading, spacing: 12) {
            Text("ALIŞKANLIK").font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(Theme.amber)
            HStack(spacing: 6) {
                ForEach(HabitPhase.allCases, id: \.self) { p in
                    VStack(spacing: 4) {
                        Capsule().fill(p == ph ? Theme.amber : phaseIndex(p) < phaseIndex(ph) ? Theme.sage : Theme.line).frame(height: 6)
                        Text(p.title).font(.caption2.weight(p == ph ? .bold : .regular)).foregroundStyle(p == ph ? Theme.ink : Theme.soft)
                    }
                }
            }
            Text("\(ph.title) · \(ph.range)").font(.headline).foregroundStyle(Theme.ink)
            Text(ph.summary).font(.footnote).foregroundStyle(Theme.soft)
            ProgressView(value: Double(min(done, HabitPhase.settleUntil)), total: Double(HabitPhase.settleUntil)).tint(Theme.amber)
            HStack {
                Text("\(done)/\(HabitPhase.settleUntil) gece").font(.caption.monospacedDigit())
                Spacer()
                Text("Seri \(store.streak)").font(.caption.monospacedDigit())
                if let c = store.checks.last {
                    Spacer()
                    Text("Otomatiklik \(String(format: "%.1f", c.score))/7").font(.caption.monospacedDigit())
                }
            }
            .foregroundStyle(Theme.soft)
            let recall = store.nights.suffix(9).flatMap(\.steps).compactMap(\.recalled)
            if !recall.isEmpty {
                Text("Ezber, son geceler: \(recall.filter { $0 }.count)/\(recall.count) hareket hatırlandı.").font(.caption).foregroundStyle(Theme.soft)
            }
        }
        .card()
    }

    private func phaseIndex(_ p: HabitPhase) -> Int { HabitPhase.allCases.firstIndex(of: p) ?? 0 }

    /// The memory aid: three sets, same five stops. First two on the bed edge, last three on the floor, the fifth is breath.
    private var setsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ÜÇ BEŞLİ · EZBER KARTI").font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(Theme.amber)
            Text("Baştan ayağa aynı beş durak: 1 boyun · 2 omuz · 3 omurga · 4 kalça-bacak · 5 nefes. İlk ikisi yatağın kenarında oturarak, son üçü yerde, her hareket 1 dakika. TEMEL en önemli beş hareket; ilk geceler onunla başlar.")
                .font(.footnote).foregroundStyle(Theme.soft)
            ForEach(Catalog.shared.orderedSets, id: \.key) { set in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(set.title).font(.headline).foregroundStyle(set.key == plan.set.key ? Theme.amber : Theme.ink)
                        Text(set.theme).font(.caption).foregroundStyle(Theme.soft)
                    }
                    ForEach(Array(set.moves.enumerated()), id: \.offset) { i, id in
                        if let m = Catalog.shared.move(id) {
                            Button { detail = m } label: {
                                HStack(spacing: 8) {
                                    Text("\(i + 1)").font(.caption.bold()).frame(width: 20, height: 20)
                                        .background(Theme.amber.opacity(0.2), in: Circle()).foregroundStyle(Theme.amber)
                                    Text(m.name).font(.callout).foregroundStyle(Theme.ink)
                                    Spacer()
                                    Text(m.sides ? "sağ · sol" : "").font(.caption2).foregroundStyle(Theme.soft)
                                }
                            }
                        }
                    }
                }
                if set.key != "C" { Divider().overlay(Theme.line) }
            }
        }
        .card()
    }

    private func todayCard(_ d: DaySummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BUGÜN").font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(Theme.amber)
            Label(NightCard.activityText(d), systemImage: "figure.walk").foregroundStyle(Theme.ink)
            if let h = d.sleepHours {
                Label("Dün gece \(String(format: "%.1f", h)) saat uyku", systemImage: "bed.double").foregroundStyle(Theme.ink)
            }
            ForEach(d.workouts, id: \.self) { w in
                Label("\(w.kind) · \(w.minutes) dk · \(w.source)", systemImage: "dumbbell").foregroundStyle(Theme.ink)
            }
        }
        .font(.callout)
        .card()
    }

    private var trend: some View {
        let recent = store.nights.filter { $0.redFlags.isEmpty }.suffix(14)
        return VStack(alignment: .leading, spacing: 10) {
            Text("SON GECELER · AĞRI").font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(Theme.amber)
            Chart {
                ForEach(Array(recent), id: \.id) { n in
                    LineMark(x: .value("Gece", n.start, unit: .day), y: .value("Ağrı", n.before.lowBack), series: .value("Bölge", "Bel"))
                        .foregroundStyle(Theme.amber)
                    LineMark(x: .value("Gece", n.start, unit: .day), y: .value("Ağrı", n.before.neck), series: .value("Bölge", "Boyun"))
                        .foregroundStyle(Theme.sage)
                    LineMark(x: .value("Gece", n.start, unit: .day), y: .value("Ağrı", n.before.knee), series: .value("Bölge", "Diz"))
                        .foregroundStyle(Theme.rose)
                }
            }
            .chartYScale(domain: 0...10)
            .frame(height: 140)
            HStack(spacing: 14) {
                legend("Bel", Theme.amber); legend("Boyun", Theme.sage); legend("Diz", Theme.rose)
            }
            .font(.caption)
        }
        .card()
    }

    private func legend(_ t: String, _ c: Color) -> some View {
        HStack(spacing: 4) { Circle().fill(c).frame(width: 8, height: 8); Text(t).foregroundStyle(Theme.soft) }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BÜTÜN HAREKETLER · ÖNEM SIRASI").font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(Theme.amber)
            Text("Fizyoterapi ve uyku kaynaklarına göre yatmadan önce en çok işe yarayandan aza: önce yavaş nefes, sonra boyun ve bel; kası uyandıran hareketler sonda.")
                .font(.footnote).foregroundStyle(Theme.soft)
            ForEach(Catalog.shared.byPriority) { m in
                Button { detail = m } label: {
                    HStack(spacing: 12) {
                        Text("\(m.rank)").font(.callout.bold().monospacedDigit()).foregroundStyle(m.rank <= 5 ? Theme.amber : Theme.soft).frame(width: 22)
                        MoveThumb(move: m).frame(width: 78, height: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.name).font(.headline).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
                            Text("Durak \(m.slot) · \(m.area)").font(.caption).foregroundStyle(Theme.soft)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.soft)
                    }
                }
                if m.id != Catalog.shared.byPriority.last?.id { Divider().overlay(Theme.line) }
            }
        }
        .card()
    }

}

/// One move: animation, video, how, why, the source.
struct MoveDetail: View {
    let move: Move
    var mirrored = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PhotoGallery(move: move, mirrored: mirrored)
                    if let y = move.youtube, let u = URL(string: y.url) {
                        Link(destination: u) {
                            HStack(spacing: 12) {
                                Image(systemName: "play.rectangle.fill").font(.title2).foregroundStyle(.red)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("YouTube'da izle").font(.headline).foregroundStyle(Theme.ink)
                                    Text("\(y.channel) · \(y.length)").font(.caption).foregroundStyle(Theme.soft)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right").foregroundStyle(Theme.soft)
                            }
                            .padding(14).background(Theme.night, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    Text(move.dose).font(.headline).foregroundStyle(Theme.amber)
                    if !move.priority.isEmpty {
                        Label("Önem sırası \(move.rank): \(move.priority)", systemImage: "list.number").font(.footnote).foregroundStyle(Theme.soft)
                    }
                    Text(move.why).foregroundStyle(Theme.ink)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Nasıl").font(.headline).foregroundStyle(Theme.ink)
                        ForEach(Array(move.steps.enumerated()), id: \.offset) { i, s in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(i + 1)").font(.caption.bold()).frame(width: 22, height: 22)
                                    .background(Theme.amber.opacity(0.2), in: Circle()).foregroundStyle(Theme.amber)
                                Text(s).foregroundStyle(Theme.ink)
                            }
                        }
                    }
                    .card()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Dikkat").font(.headline).foregroundStyle(Theme.ink)
                        ForEach(move.cues, id: \.self) { Label($0, systemImage: "exclamationmark.circle").foregroundStyle(Theme.soft) }
                    }
                    .card()
                    if let u = URL(string: move.video.url) {
                        Link(destination: u) {
                            Label(move.video.title, systemImage: "doc.text").font(.callout.weight(.semibold))
                        }
                        Text("Hareketin yazılı kaynağı. Sayfa İngilizce.")
                            .font(.caption).foregroundStyle(Theme.soft)
                    }
                }
                .padding(20)
            }
            .background(Theme.card.ignoresSafeArea())
            .navigationTitle(move.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Kapat") { dismiss() } }
        }
        .preferredColorScheme(.dark)
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var health: Health
    @Environment(\.dismiss) private var dismiss

    private var bedtime: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: store.bedtimeMinutes / 60, minute: store.bedtimeMinutes % 60, second: 0, of: .now) ?? .now
        } set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            store.bedtimeMinutes = (c.hour ?? 23) * 60 + (c.minute ?? 30)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Yatış saati", selection: bedtime, displayedComponents: .hourAndMinute)
                    Stepper("Hatırlatma: \(store.leadMinutes) dk önce", value: $store.leadMinutes, in: 10...90, step: 5)
                    Button("Bildirim iznini ver") { Task { await store.requestNotifications() } }
                } header: { Text("Hatırlatma") }
                Section {
                    Toggle("Sesli yönlendirme", isOn: $store.voice)
                    Toggle("Mini gece (omurga + nefes, 2 dk)", isOn: $store.shortNights)
                } header: { Text("Rutin") }
                Section {
                    TextField("Örn. Dişlerimi fırçaladıktan sonra", text: $store.anchor)
                } header: { Text("Çapa") } footer: {
                    Text("Beşliyi her gece aynı şeyin hemen ardından yap. Sabit bir çapa, alışkanlığı saatten daha hızlı oturtur; hatırlatmada da bu cümle görünür.")
                }
                Section {
                    if health.authorized {
                        Label("Sağlık bağlı", systemImage: "checkmark.circle").foregroundStyle(Theme.sage)
                    }
                    Button(health.authorized ? "İzinleri yeniden sor" : "Apple Sağlık'ı bağla") { Task { await health.requestAccess(); await health.refreshToday() } }
                } header: { Text("Apple Sağlık") } footer: {
                    Text("Uyku, adım, yürüyüş ve bisiklet (Wise Path), antrenmanlar (Demir Sağlık'a yazıyorsa) okunur. Rutin Sağlık'a esneme antrenmanı olarak yazılır.")
                }
                PDMSettingsSection(bus: store.bus)
            }
            .navigationTitle("Ayarlar")
            .toolbar { Button("Tamam") { dismiss() } }
        }
        .preferredColorScheme(.dark)
    }
}
