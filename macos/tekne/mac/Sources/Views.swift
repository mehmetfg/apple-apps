import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: Store
    @EnvironmentObject var tracker: Tracker

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ProductionBand()
                    if let a = model.selected, let roof = store.roofs[a] {
                        RoofView(area: a, roof: roof)
                    } else {
                        HStack(alignment: .top, spacing: 18) {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 215), spacing: 14)], spacing: 14) {
                                ForEach(store.cards) { AreaCardView(card: $0) }
                            }
                            .frame(maxWidth: .infinity)
                            QueueView().frame(width: 250)
                        }
                    }
                }
                .padding(20)
            }
        }
        .background(Theme.paper)
        .foregroundStyle(Theme.ink)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Tekne").font(Theme.serif(26))
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "tr_TR"))))
                .foregroundStyle(Theme.muted)
            Spacer()
            if model.selected != nil {
                Button { model.selected = nil } label: { Label("Pano", systemImage: "square.grid.2x2") }
            }
            Button { model.runHub() } label: { Image(systemName: "arrow.clockwise") }
                .help("PDM Ağı'nı yeniden koştur ve tazele")
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 6)
    }
}

// MARK: - Production

struct ProductionBand: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var tracker: Tracker

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("BUGÜN ÜRETİM").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(model.today?.production ?? 0)").font(Theme.serif(48, .bold))
                        Text("dk").font(Theme.serif(20)).foregroundStyle(Theme.muted)
                    }
                    Text("günün %\(fmt(model.percentOfDay)) · şu ana dek %\(fmt(model.percentSoFar))")
                        .font(.callout).foregroundStyle(Theme.muted)
                    Text("yazılı \(model.today?.written ?? 0) · sesli \(model.today?.spoken ?? 0) dk · pencere \(model.windowStart):00–\(model.windowEnd):00")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                VStack(alignment: .leading, spacing: 8) {
                    DayStrip()
                    MorningLine()
                    HStack(spacing: 12) {
                        ForEach(AreaID.allCases) { a in
                            HStack(spacing: 4) {
                                Circle().fill(Theme.area(a)).frame(width: 8, height: 8)
                                Text("\(a.title) \(model.minutes(a))").font(.caption)
                            }
                        }
                        Spacer()
                        Text("Yapım \(model.today?.build ?? 0) dk").font(.caption).foregroundStyle(Theme.muted)
                            .help("Claude ile uygulama yapımı — üretim yüzdesine girmez")
                    }
                }
                .frame(maxWidth: .infinity)
                ManualControl().frame(width: 220)
            }
            FortnightBars()
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
    }

    private func fmt(_ v: Double) -> String { v < 10 ? String(format: "%.1f", v) : String(Int(v.rounded())) }
}

/// The waking window as a line; production sessions on top, Yapım (build) below.
struct DayStrip: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        GeometryReader { g in
            let start = Day.cal.date(bySettingHour: model.windowStart, minute: 0, second: 0, of: .now)!
            let span = Double(model.windowMinutes * 60)
            let x = { (d: Date) -> CGFloat in CGFloat(min(max(d.timeIntervalSince(start) / span, 0), 1)) * g.size.width }
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 5).fill(Theme.track).frame(height: 26)
                ForEach(Array(model.todaySessions.enumerated()), id: \.offset) { _, s in
                    let w = max(2, x(s.end) - x(s.start))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(s.build ? Theme.muted.opacity(0.55) : Theme.area(s.area))
                        .frame(width: w, height: s.build ? 6 : 26)
                        .offset(x: x(s.start), y: s.build ? 30 : 0)
                        .help("\(s.app) · \(Int(s.seconds / 60)) dk · \(s.source)")
                }
                // planned morning blocks: dashed frame at the planned time, the real box as a line above it
                ForEach(model.morningPlan.blocks, id: \.id) { b in
                    if let ps = MorningMath.plannedStart(b) {
                        let pe = ps.addingTimeInterval(Double(b.minutes) * 60)
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Theme.muted.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                            .frame(width: max(2, x(pe) - x(ps)), height: 26)
                            .offset(x: x(ps))
                            .help("Plan: \(b.title) \(b.start) · \(b.minutes) dk")
                        if let st = model.morningState[b.id], let s = st.started {
                            let e = st.finished ?? Date()
                            Capsule().fill(MorningMath.color(b, st))
                                .frame(width: max(3, x(e) - x(s)), height: 4)
                                .offset(x: x(s), y: -7)
                                .help(MorningMath.summary(b, st))
                        }
                    }
                }
                Rectangle().fill(Theme.ink).frame(width: 1.5, height: 38).offset(x: x(.now), y: -2)
                HStack {
                    Text("\(model.windowStart):00"); Spacer(); Text("\((model.windowStart + model.windowEnd) / 2):00"); Spacer(); Text("\(model.windowEnd):00")
                }
                .font(.caption2).foregroundStyle(Theme.muted).offset(y: 40)
            }
        }
        .frame(height: 54)
    }
}

struct ManualControl: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var tracker: Tracker

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let m = tracker.manual {
                Text("Elle sayaç · \(m.area.title) · \(m.kind == .spoken ? "sesli" : "yazılı")").font(.caption).foregroundStyle(Theme.muted)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(Duration.seconds(ctx.date.timeIntervalSince(m.start)).formatted(.time(pattern: .hourMinuteSecond)))
                        .font(Theme.serif(26, .bold)).monospacedDigit()
                }
                Button { tracker.stopManual() } label: { Label("Durdur", systemImage: "stop.fill").frame(maxWidth: .infinity) }
                    .controlSize(.large).buttonStyle(.borderedProminent).tint(Theme.status(.late))
            } else {
                Picker("Alan", selection: Binding(get: { model.lastArea }, set: { model.lastArea = $0 })) {
                    ForEach(AreaID.allCases) { Text($0.title).tag($0) }
                }
                Picker("", selection: Binding(get: { model.lastKind }, set: { model.lastKind = $0 })) {
                    Text("Yazılı").tag(ProductionKind.written); Text("Sesli").tag(ProductionKind.spoken)
                }.pickerStyle(.segmented).labelsHidden()
                Button { model.toggleManual() } label: { Label("Üretime başla", systemImage: "play.fill").frame(maxWidth: .infinity) }
                    .controlSize(.large).buttonStyle(.borderedProminent).tint(Theme.status(.done))
                    .help("⌃⌥T ile her yerden başlat/durdur")
            }
            if let a = tracker.auto {
                Label("\(a.build ? "Yapım" : "Otomatik"): \(a.app) · \(Int(a.seconds / 60)) dk", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption).foregroundStyle(a.build ? Theme.muted : Theme.area(a.area))
            } else {
                Label("Otomatik sayaç bekliyor", systemImage: "pause.circle").font(.caption).foregroundStyle(Theme.muted)
            }
        }
    }
}

struct FortnightBars: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let maxV = max(60, model.days.map { $0.production + $0.build }.max() ?? 60)
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(model.days) { d in
                VStack(spacing: 3) {
                    VStack(spacing: 1) {
                        Spacer(minLength: 0)
                        ForEach(AreaID.allCases.reversed()) { a in
                            if let m = d.byArea[a] {
                                Rectangle().fill(Theme.area(a)).frame(height: CGFloat(m) / CGFloat(maxV) * 46)
                            }
                        }
                        Rectangle().fill(Theme.muted.opacity(0.35)).frame(height: CGFloat(d.build) / CGFloat(maxV) * 46)
                    }
                    .frame(height: 48)
                    .help("\(d.id) · üretim \(d.production) dk · yapım \(d.build) dk")
                    Text(d.date.formatted(.dateTime.day())).font(.system(size: 9)).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Cards

struct AreaCardView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: Store
    let card: AreaCard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: Theme.areaSymbol(card.id)).foregroundStyle(Theme.area(card.id))
                Text(card.id.title).font(Theme.serif(19))
                Spacer()
                Label(card.status.label, systemImage: Theme.symbol(card.status))
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.status(card.status))
            }
            Text(card.headline).font(.callout.weight(.medium))
            VStack(alignment: .leading, spacing: 5) {
                ForEach(card.items) { i in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: Theme.symbol(i.status)).font(.system(size: 9)).foregroundStyle(Theme.status(i.status)).padding(.top, 4)
                        Text(i.text).font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if card.id == .body { BodyTicks() }
            Spacer(minLength: 0)
            HStack {
                Text("bugün \(model.minutes(card.id)) dk üretim").font(.caption).foregroundStyle(Theme.muted)
                Spacer()
                Button("Çatı") { model.selected = card.id }
                Button("Aç") { model.open(card.id) }.buttonStyle(.borderedProminent).tint(Theme.area(card.id))
            }
        }
        .padding(16)
        .frame(minHeight: 230, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 14).fill(Theme.status(card.status)).frame(width: 5)
        }
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(card.status >= .due ? Theme.status(card.status).opacity(0.6) : Theme.line,
                                                         lineWidth: card.status >= .due ? 1.5 : 1))
    }
}

/// One tap writes the key into today's journal front matter (the single source the hub reads).
struct BodyTicks: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let f = store.journalFields
        let tr = Journal.training(for: .now)
        VStack(alignment: .leading, spacing: 6) {
            chip("antrenman", tr.code == "Y" ? "Yürüdüm" : "Antrenman \(tr.code)", on: f["antrenman"] == "true")
            FlowChips(items: Journal.routine.map { ($0.key, $0.name, f[$0.key] == "true") }) { key, on in
                store.toggle(key, on: !on)
            }
        }
        .disabled(store.journalURL == nil)
    }

    private func chip(_ key: String, _ title: String, on: Bool) -> some View {
        Button { store.toggle(key, on: !on) } label: {
            Label(title, systemImage: on ? "checkmark.circle.fill" : "circle")
                .font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(on ? Theme.status(.done).opacity(0.18) : Theme.track))
        }.buttonStyle(.plain)
    }
}

struct FlowChips: View {
    let items: [(String, String, Bool)]
    let tap: (String, Bool) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 5)], alignment: .leading, spacing: 5) {
            ForEach(items, id: \.0) { key, name, on in
                Button { tap(key, on) } label: {
                    Text(name).font(.caption2.weight(.medium)).lineLimit(1)
                        .padding(.horizontal, 6).padding(.vertical, 3).frame(maxWidth: .infinity)
                        .background(Capsule().fill(on ? Theme.status(.done).opacity(0.22) : Theme.track))
                        .overlay(Capsule().stroke(on ? Theme.status(.done) : .clear))
                }.buttonStyle(.plain)
            }
        }
    }
}

struct QueueView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: Store

    var body: some View {
        let queue = store.cards.flatMap { c in c.items.filter { $0.status >= .due }.map { (c.id, $0) } }
            .sorted { $0.1.status > $1.1.status }
        VStack(alignment: .leading, spacing: 10) {
            Text("SIRADA").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
            if queue.isEmpty {
                Text("Bugün sırası gelen her şey tamam.").font(.callout)
            }
            ForEach(Array(queue.prefix(7).enumerated()), id: \.offset) { n, pair in
                Button { model.open(pair.0) } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(n + 1)").font(Theme.serif(15, .bold)).foregroundStyle(Theme.status(pair.1.status)).frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pair.0.title).font(.caption).foregroundStyle(Theme.area(pair.0))
                            Text(pair.1.text).font(.callout).multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: Theme.symbol(pair.1.status)).foregroundStyle(Theme.status(pair.1.status))
                    }
                }.buttonStyle(.plain)
            }
            Divider().padding(.vertical, 4)
            Text("Yeşil ✓ tamam · turuncu ● sırası geldi · kırmızı ▲ gecikti · gri ○ veri yok")
                .font(.caption2).foregroundStyle(Theme.muted)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
    }
}

// MARK: - Roof

struct RoofView: View {
    @EnvironmentObject var model: AppModel
    let area: AreaID
    let roof: Roof

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: Theme.areaSymbol(area)).foregroundStyle(Theme.area(area))
                Text("\(area.title) · çatı").font(Theme.serif(24))
                Spacer()
                Button("Aç") { model.open(area) }.buttonStyle(.borderedProminent).tint(Theme.area(area))
            }
            Text(roof.summary).foregroundStyle(Theme.muted)
            let done = roof.rows.flatMap(\.cells).filter { $0.status == .done }.count
            let all = roof.rows.flatMap(\.cells).count
            ProgressView(value: Double(done), total: Double(max(1, all))) {
                Text("\(done) / \(all) tamam").font(.caption)
            }.tint(Theme.status(.done))
            VStack(alignment: .leading, spacing: 6) {
                ForEach(roof.rows) { row in
                    HStack(spacing: 10) {
                        Text(row.title).font(.callout).lineLimit(1).frame(width: 230, alignment: .leading)
                        HStack(spacing: 3) {
                            ForEach(row.cells) { c in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Theme.status(c.status))
                                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.line, lineWidth: c.status == nil ? 1 : 0))
                                    .overlay(Text(c.label).font(.system(size: 8, weight: .semibold))
                                        .foregroundStyle(c.status == nil || c.status == .idle ? Theme.muted : .white))
                                    .frame(width: 20, height: 20)
                                    .help(c.hint)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            if !roof.notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(roof.notes, id: \.self) { Text("• " + $0).font(.callout).foregroundStyle(Theme.muted) }
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
    }
}

// MARK: - Menu bar

struct MenuContent: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: Store
    @EnvironmentObject var tracker: Tracker
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("Bugün \(model.today?.production ?? 0) dk üretim · günün %\(Int(model.percentOfDay.rounded()))")
        Text("Yapım \(model.today?.build ?? 0) dk")
        Divider()
        ForEach(store.cards) { c in Text("\(c.status == .done ? "✓" : c.status == .late ? "▲" : c.status == .due ? "●" : "○")  \(c.id.title) — \(c.headline)") }
        Divider()
        Button(tracker.manual == nil ? "Üretime başla (\(model.lastArea.title))" : "Durdur") { model.toggleManual() }
            .keyboardShortcut("t", modifiers: [.control, .option])
        Button("Tekne'yi aç") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Divider()
        Button("Çık") { NSApp.terminate(nil) }
    }
}

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Stepper("Uyanık pencere başı: \(model.windowStart):00", value: $model.windowStart, in: 4...12)
            Stepper("Uyanık pencere sonu: \(model.windowEnd):00", value: $model.windowEnd, in: 18...24)
            Text("Yüzde bu pencereye göre hesaplanır (\(model.windowMinutes) dk).").foregroundStyle(.secondary)
        }
        .padding(20).frame(width: 380)
    }
}


// MARK: - Morning time boxes (Kurultay decision 2026-11-05)

enum MorningMath {
    static func plannedStart(_ b: TimeBoxBlock) -> Date? {
        let p = b.start.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2 else { return nil }
        return Day.cal.date(bySettingHour: p[0], minute: p[1], second: 0, of: .now)
    }

    static func minutes(_ st: TimeBoxState) -> Int {
        guard let s = st.started else { return 0 }
        return Int(((st.finished ?? Date()).timeIntervalSince(s) / 60).rounded())
    }

    static func color(_ b: TimeBoxBlock, _ st: TimeBoxState) -> Color {
        if st.finished == nil { return minutes(st) > b.minutes ? .red : .accentColor }
        return st.extendedMinutes > 0 ? .orange : .green
    }

    static func summary(_ b: TimeBoxBlock, _ st: TimeBoxState) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        var t = "\(b.title): \(st.started.map(f.string) ?? "—")"
        if let e = st.finished { t += "–\(f.string(from: e)) · \(minutes(st)) dk ✓" } else { t += " · sürüyor \(minutes(st)) dk" }
        if st.extendedMinutes > 0 { t += " · +\(st.extendedMinutes) dk uzatıldı" }
        return t
    }
}

/// One line under the day strip: how the morning blocks went today.
struct MorningLine: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            Label("Sabah", systemImage: "sunrise").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
            ForEach(model.morningPlan.blocks, id: \.id) { b in
                let st = model.morningState[b.id]
                HStack(spacing: 4) {
                    Image(systemName: st?.finished != nil ? "checkmark.circle.fill" : st?.started != nil ? "timer" : "circle")
                        .foregroundStyle(st.map { MorningMath.color(b, $0) } ?? Theme.muted)
                    Text(st.map { MorningMath.summary(b, $0) } ?? "\(b.title) \(b.start) · başlamadı")
                        .font(.caption).monospacedDigit()
                }
            }
            Spacer()
        }
    }
}
