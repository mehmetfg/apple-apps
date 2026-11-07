// İçgörüler: a row of glass chips on top; each chip opens one large graphic and the story under it.
import SwiftUI

enum Chip: String, CaseIterable, Identifiable {
    case markers, sleep, move, heart, body, food
    var id: String { rawValue }

    var name: String {
        switch self {
        case .markers: return "Göstergeler"
        case .sleep: return "Uyku"
        case .move: return "Hareket"
        case .heart: return "Kalp"
        case .body: return "Beden"
        case .food: return "Beslenme"
        }
    }

    var symbol: String {
        switch self {
        case .markers: return "testtube.2"
        case .sleep: return "bed.double.fill"
        case .move: return "figure.walk"
        case .heart: return "heart.fill"
        case .body: return "figure.arms.open"
        case .food: return "leaf.fill"
        }
    }

    var color: Color {
        switch self {
        case .markers: return .calm
        case .sleep: return .sleep
        case .move: return .move
        case .heart: return .heart
        case .body: return .attention
        case .food: return .food
        }
    }
}

struct InsightsView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var health: Health
    @State private var chip = Chip(rawValue: ProcessInfo.processInfo.environment["SBS_CHIP"] ?? "") ?? .markers
    @State private var region: String?

    var body: some View {
        let d = Derived(store, health)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    chips(d)
                    switch chip {
                    case .markers: markers(d)
                    case .sleep: sleep(d)
                    case .move: move(d)
                    case .heart: heart(d)
                    case .body: bodyTab(d)
                    case .food: food(d)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 100)
            }
            .scrollIndicators(.hidden)
            .sbsGround()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: Binding(get: { region.map(RegionRef.init) }, set: { region = $0?.id })) { r in
                RegionSheet(region: r.id, state: d.state)
            }
        }
    }

    // MARK: chips

    private func chips(_ d: Derived) -> some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    ForEach(Chip.allCases) { c in
                        Button { withAnimation(.snappy) { chip = c } } label: {
                            HStack(spacing: 9) {
                                Image(systemName: c.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                                    .frame(width: 30, height: 30).background(c.color.gradient, in: Circle())
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(c.name).font(.caption2).foregroundStyle(.secondary)
                                    Text(value(c, d)).font(.footnote.weight(.semibold)).foregroundStyle(.primary)
                                }
                            }
                            .padding(.leading, 8).padding(.trailing, 14).padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(chip == c ? .regular.tint(c.color.opacity(0.28)).interactive() : .regular.interactive(), in: .capsule)
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 6)
            }
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -18)
    }

    private func value(_ c: Chip, _ d: Derived) -> String {
        switch c {
        case .markers: return d.outOfRange.isEmpty ? "Hepsi aralıkta" : "\(d.outOfRange.count) dışında"
        case .sleep: return health.lastNight?.sleepH.map(Derived.hours) ?? "Veri yok"
        case .move: return health.today?.steps.map { "\(Int($0).formatted()) adım" } ?? "Veri yok"
        case .heart: return d.resting7.map { "\(Int($0)) atım" } ?? (d.state.areas.first { $0.id == "heart" }.map { Tone(status: $0.state).areaLabel } ?? "—")
        case .body: return "\(d.state.episodes.filter { (Day.daysAgo($0.date) ?? 99) < 30 }.count) olay"
        case .food:
            let last = d.state.days.last { ($0.planned ?? 0) > 0 }
            return last.map { "\($0.supplements ?? 0)/\($0.planned ?? 0)" } ?? "Kayıt yok"
        }
    }

    private func headline(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title2.bold())
            Text(text).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func empty(_ symbol: String, _ title: String, _ text: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol).font(.title).foregroundStyle(.secondary)
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: markers

    @ViewBuilder private func markers(_ d: Derived) -> some View {
        let cur = d.current
        let good = cur.filter { $0.status == "in" }.count
        AnalysisCards(d: d).padding(.top, 8)
        headline(d.outOfRange.isEmpty ? "Bütün değerlerin aralıkta" : "\(d.outOfRange.count) değer aralık dışında",
                 "Son tahlil \(Day.short(d.lastLab)). \(cur.count) değerden \(good) tanesi laboratuvar aralığında. Aşağıdakiler hekime sorulacak bulgular; teşhis değil.")
        SectionTitle(text: "Öne çıkanlar")
        VStack(spacing: 10) {
            ForEach(d.state.highlights) { h in
                NavigationLink {
                    if let m = d.state.marker(h.marker ?? "") { MarkerDetail(marker: m, state: d.state) }
                } label: {
                    Card(padding: 14) {
                        HStack(alignment: .top, spacing: 12) {
                            ToneDot(tone: Tone(status: h.tone), size: 11).padding(.top, 5)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(h.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                                Text(h.detail).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary).padding(.top, 4)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        NavigationLink { MarkerList(state: d.state) } label: {
            Label("Bütün göstergeler", systemImage: "list.bullet").frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(.glass)
    }

    private func legend(_ tone: Tone, _ text: String) -> some View {
        HStack(spacing: 6) { ToneDot(tone: tone); Text(text).font(.footnote.weight(.medium)).foregroundStyle(.secondary) }
    }

    // MARK: sleep

    @ViewBuilder private func sleep(_ d: Derived) -> some View {
        if let night = health.lastNight, let h = night.sleepH {
            ArcGauge(fraction: h / 10, band: 0.7...0.9, value: h.clean, caption: "saat · \(Day.dayMonth(night.date)) sabahı", color: .sleep)
                .padding(.horizontal, 24).padding(.top, 8)
            let item = d.sleepArea
            headline(item.tone == .good ? "Uykun yeterli" : item.tone == .watch ? "Uykun sınırda" : "Uykun kısa", item.detail)
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(d.last7) { day in
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 6).fill(day.sleepH == nil ? Color.track : Color.sleep)
                                    .frame(height: CGFloat((day.sleepH ?? 0.3) / 10) * 110)
                                Text((Day.parse(day.date) ?? .now).formatted(.dateTime.weekday(.narrow).locale(Locale(identifier: "tr_TR"))))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 130, alignment: .bottom)
                    Divider()
                    statGrid([("Yatış", night.bed ?? "—"), ("Kalkış", night.wake ?? "—"),
                              ("Derin", night.deepMin.map { "\(Int($0)) dk" } ?? "—"), ("REM", night.remMin.map { "\(Int($0)) dk" } ?? "—")])
                    if night.inBedOnly == true {
                        Text("Yalnız 'yatakta' verisi var; gerçek uyku daha kısa olabilir.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            ArcGauge(fraction: 0, band: 0.7...0.9, value: "—", caption: "uyku verisi yok", color: .sleep).padding(.horizontal, 24).padding(.top, 8)
            empty("bed.double", "Uyku verisi yok", "SBS uykuyu Apple Sağlık'tan okur. Saat uygulamasında Uyku programını açarsan telefon yatış ve kalkışını yazar; saat takarsan evreler de gelir.")
        }
        episodes(d, title: "Uykuyla ilgili kayıtların", filter: { $0.condition == "poor_sleep" })
    }

    // MARK: movement

    @ViewBuilder private func move(_ d: Derived) -> some View {
        let dots = d.dots(\.steps)
        if dots.contains(where: { $0.value != nil }) {
            let typical = Derived.typical(d.before.compactMap(\.steps))
            Card { TypicalBand(dots: dots, typical: typical, color: .move) }.padding(.top, 8)
            headline(d.moveArea.tone == .good ? "Hareketin tipik" : "Hareketin tipiğinin altında", d.moveArea.detail)
            Card {
                statGrid([("Bugün", health.today?.steps.map { "\(Int($0).formatted()) adım" } ?? "—"),
                          ("Yürüme", health.today?.walkKm.map { "\($0.clean) km" } ?? "—"),
                          ("Bisiklet", health.today?.cycleKm.map { "\($0.clean) km" } ?? "—"),
                          ("Aktif enerji", health.today?.activeKcal.map { "\(Int($0)) kcal" } ?? "—")])
            }
        } else {
            empty("figure.walk", "Adım verisi yok", "SBS adımı, mesafeyi ve antrenmanları Apple Sağlık'tan okur. Göz At › Ayarlar'dan Apple Sağlık iznini ver.")
        }
        let work = d.state.ledger.filter { ["workout", "walk", "ride", "stretch"].contains($0.type) }.prefix(6)
        if !work.isEmpty {
            SectionTitle(text: "Son antrenmanlar")
            Card(padding: 4) { VStack(spacing: 0) { ForEach(Array(work)) { LedgerRow(record: $0) } } }
        }
    }

    // MARK: heart

    @ViewBuilder private func heart(_ d: Derived) -> some View {
        let dots = d.dots(\.restingHr)
        if dots.contains(where: { $0.value != nil }) {
            Card { TypicalBand(dots: dots, typical: Derived.typical(d.before.compactMap(\.restingHr)), color: .heart) }.padding(.top, 8)
            headline("Dinlenik nabzın", d.resting7.map { "Son 7 günde ortalama \(Int($0)) atım/dk." } ?? "")
        } else if let area = d.state.areas.first(where: { $0.id == "heart" }) {
            let ms = area.markers.compactMap { d.state.marker($0) }
            SegmentRing(parts: [.init(value: Double(ms.filter { $0.status == "in" }.count), color: .good),
                                .init(value: Double(ms.filter { $0.status == "attention" }.count), color: .attention),
                                .init(value: Double(ms.filter { $0.status == "watch" }.count), color: .watch)],
                        center: "\(area.inRange)", caption: "/ \(area.total) aralıkta")
                .frame(maxWidth: 260).frame(maxWidth: .infinity).padding(.top, 8)
            headline("Kalp ve damar: \(Tone(status: area.state).areaLabel.lowercased(with: Locale(identifier: "tr_TR")))",
                     area.detail + " Nabız ve tansiyon verisi yok; nabız için saat gerekir, tansiyonu Sağlık uygulamasına elle girebilirsin.")
        }
        if let area = d.state.areas.first(where: { $0.id == "heart" }) {
            SectionTitle(text: "Kalp ve damar göstergeleri", trailing: Day.short(area.lastDate))
            VStack(spacing: 10) { ForEach(area.markers.compactMap { d.state.marker($0) }) { MarkerCard(marker: $0, state: d.state) } }
        }
        if let s = d.systolic.last, let dia = health.diastolic.last {
            Card { statGrid([("Tansiyon", "\(Int(s.value))/\(Int(dia.value))"), ("Ölçüm", s.date.formatted(.dateTime.day().month(.abbreviated)))]) }
        }
    }

    // MARK: body

    @ViewBuilder private func bodyTab(_ d: Derived) -> some View {
        let recent = d.state.episodes.filter { (Day.daysAgo($0.date) ?? 999) < 90 }
        let marks = Dictionary(grouping: recent.filter { $0.region != "mind" }, by: { $0.region ?? "whole" }).mapValues(\.count)
        HStack(alignment: .top, spacing: 14) {
            BodyFigure(marks: marks, selected: region) { region = $0 }.frame(maxWidth: 190)
            VStack(alignment: .leading, spacing: 10) {
                Text("Son 90 gün").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(marks.sorted { $0.value > $1.value }, id: \.key) { key, n in
                    Button { region = key } label: {
                        HStack { ToneDot(tone: .attention); Text(Region.name(key)).font(.subheadline.weight(.medium)); Spacer(); Text("\(n)").font(.subheadline).foregroundStyle(.secondary) }
                    }
                    .buttonStyle(.plain)
                }
                let mind = recent.filter { $0.region == "mind" }.count
                Button { region = "mind" } label: {
                    HStack { Image(systemName: "brain.head.profile").font(.caption).foregroundStyle(Color.mind); Text("Zihin").font(.subheadline.weight(.medium)); Spacer(); Text("\(mind)").font(.subheadline).foregroundStyle(.secondary) }
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                Text("Bir bölgeye dokun: rahatsızlıklar ve ne yapılacağı açılır.").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.top, 10)
        }
        .padding(.top, 8)
        headline(recent.isEmpty ? "Kayıtlı olay yok" : "Son 90 günde \(recent.count) olay",
                 "Bir şey olduğunda Kıvılcım'a sesle söyle: ne oldu, öncesinde ne vardı, ne yaptın, ne zaman geçti. Olay buraya düşer.")
        Button {
            if let u = URL(string: "kivilcim://kaydet?topic=Sa%C4%9Fl%C4%B1k") { UIApplication.shared.open(u) }
        } label: {
            Label("Sesle kaydet", systemImage: "mic.fill").frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
        episodes(d, title: "Olaylar", filter: { _ in true })
    }

    // MARK: food

    @ViewBuilder private func food(_ d: Derived) -> some View {
        let rows = (0..<14).reversed().map { i -> (String, DayRow?) in
            let key = Day.key(Calendar.current.date(byAdding: .day, value: -i, to: .now)!)
            return (key, d.state.days.first { $0.date == key })
        }
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Rutin · son 14 gün").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(rows, id: \.0) { key, row in
                        let share = row.flatMap { r in (r.planned ?? 0) > 0 ? Double(r.supplements ?? 0) / Double(r.planned!) : nil }
                        VStack(spacing: 4) {
                            ZStack {
                                Circle().stroke(Color.track, lineWidth: 4)
                                if let share { Circle().trim(from: 0, to: share).stroke(Color.food, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90)) }
                            }
                            .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                            Text(String(key.suffix(2))).font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.top, 8)
        headline("Beslenme ve takviye", d.foodArea.detail + " Kayıt Özen uygulamasından gelir; SBS yalnız okur.")
        if let last = d.state.days.last(where: { ($0.proteinG ?? 0) > 0 || ($0.waterMl ?? 0) > 0 }) {
            Card {
                statGrid([("Protein", "\((last.proteinG ?? 0).clean) / \((last.proteinGoal ?? 0).clean) g"),
                          ("Su", "\(Int(last.waterMl ?? 0)) / \(Int(last.waterGoal ?? 0)) ml"), ("Gün", Day.dayMonth(last.date))])
            }
        }
        SectionTitle(text: "Rutindeki kalemler")
        Card(padding: 4) {
            VStack(spacing: 0) {
                ForEach(d.state.supplements) { s in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.name).font(.subheadline.weight(.medium))
                        if let dose = s.dose { Text(dose).font(.footnote).foregroundStyle(.secondary) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 9)
                }
            }
        }
    }

    // MARK: shared

    @ViewBuilder private func episodes(_ d: Derived, title: String, filter: (Episode) -> Bool) -> some View {
        let list = d.state.episodes.filter(filter)
        if !list.isEmpty {
            SectionTitle(text: title)
            VStack(spacing: 10) { ForEach(list) { EpisodeCard(episode: $0, state: d.state) } }
        }
    }

    private func statGrid(_ items: [(String, String)]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 12) {
            ForEach(items, id: \.0) { k, v in
                VStack(alignment: .leading, spacing: 1) {
                    Text(k).font(.caption).foregroundStyle(.secondary)
                    Text(v).font(.title3.weight(.semibold)).monospacedDigit()
                }
            }
        }
    }
}

struct RegionRef: Identifiable { var id: String }
