// One night: pain check and red flags → the five stops, timed, one after another → pain again → the night card.
// In the recall phase every stop first asks "which move?"; the answer is graded by the person and kept.
import SwiftUI

struct SessionView: View {
    let plan: NightPlan
    var onClose: () -> Void

    enum Phase: Equatable { case check, stop, moves, after, card }
    @State private var phase: Phase = .check
    @State private var before = Pain.zero
    @State private var after = Pain.zero
    @State private var flags: Set<String> = []
    @State private var results: [StepResult] = []
    @State private var index = 0
    @State private var remaining = 0
    @State private var paused = false
    @State private var started = Date()
    @State private var record: NightRecord?
    @State private var steps: [PlannedStep] = []
    @State private var showHelp = false
    @State private var asking = false
    @State private var recalled: Bool?
    @State private var checkItems = [4, 4, 4, 4]
    @State private var checkSaved = false

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Theme.night.ignoresSafeArea()
            switch phase {
            case .check: checkView
            case .stop: stopView
            case .moves: movesView
            case .after: afterView
            case .card: cardView
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            steps = plan.steps
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            Voice.shared.stop()
        }
        .onReceive(tick) { _ in step() }
        .sheet(isPresented: $showHelp) {
            if index < steps.count { MoveDetail(move: steps[index].move, mirrored: steps[index].mirrored) }
        }
    }

    // MARK: before

    private var checkView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header("Önce bir bakalım", "Şu an ağrın ne kadar? 0 yok, 10 dayanılmaz.")
                PainPicker(pain: $before)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Bugün bunlardan biri var mı?").font(.headline).foregroundStyle(Theme.ink)
                    ForEach(Catalog.shared.redFlags, id: \.self) { f in
                        Button {
                            if flags.contains(f) { flags.remove(f) } else { flags.insert(f) }
                            Voice.tap()
                        } label: {
                            HStack(alignment: .top) {
                                Image(systemName: flags.contains(f) ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(flags.contains(f) ? Theme.rose : Theme.soft)
                                Text(f).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
                                Spacer()
                            }
                        }
                        .accessibilityAddTraits(flags.contains(f) ? .isSelected : [])
                    }
                }
                .card()
                Button { begin() } label: {
                    Text(flags.isEmpty ? "Başla · \(plan.set.title) · \(plan.totalSeconds.minutesText)" : "Devam")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Theme.amber, in: Capsule()).foregroundStyle(Theme.night)
                }
                Button("Vazgeç", action: onClose).frame(maxWidth: .infinity).foregroundStyle(Theme.soft)
            }
            .padding(20)
        }
    }

    private func begin() {
        started = Date()
        if !flags.isEmpty {
            phase = .stop
            finish(saveAfter: false)
            return
        }
        // a strong pain tonight: only the gentle part (core + breath), no module
        if before.max >= 7 && !plan.short {
            steps = Catalog.shared.plan(set: plan.set.key, short: true, avoid: Store.shared.avoidMoves).steps
        }
        phase = .moves
        startStep(0)
    }

    private var stopView: some View {
        VStack(spacing: 18) {
            Image(systemName: "stethoscope").font(.system(size: 44)).foregroundStyle(Theme.rose)
            Text("Bu gece rutini yapma").font(.title2.bold()).foregroundStyle(Theme.ink)
            Text("İşaretlediğin belirti bir hekime danışılacak bir durum. Hareket bunu çözmez, saklayabilir. Not alındı; haftalık raporda görünecek.")
                .multilineTextAlignment(.center).foregroundStyle(Theme.soft)
            Text("Acil: idrar ya da dışkı kontrolünü kaybettiysen, kasıkta uyuşma varsa 112.")
                .font(.footnote).multilineTextAlignment(.center).foregroundStyle(Theme.rose.opacity(0.9))
            Button("Kapat", action: onClose).font(.headline).padding(.horizontal, 40).padding(.vertical, 14)
                .background(Theme.card, in: Capsule()).foregroundStyle(Theme.ink)
        }
        .padding(28)
    }

    // MARK: moves

    private var movesView: some View {
        let s = steps[min(index, steps.count - 1)]
        return VStack(spacing: 14) {
            HStack {
                Button { stopEarly() } label: { Image(systemName: "xmark").padding(10) }
                    .accessibilityLabel("Rutini bitir")
                Spacer()
                ProgressDots(count: steps.count, index: index)
                Spacer()
                Button { showHelp = true; paused = true } label: { Image(systemName: "info.circle").padding(10) }
                    .accessibilityLabel("Nasıl yapılır")
            }
            .foregroundStyle(Theme.soft)

            if asking {
                recallView(s)
            } else {
                movePanel(s)
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 12)
    }

    private func stopLabel(_ m: Move) -> String {
        "DURAK \(m.slot) · \((Catalog.shared.slot(m.slot)?.name ?? m.area).uppercased())"
    }

    /// Recall phase: the stop is named, the move is not. Remember, then look, then say honestly.
    private func recallView(_ s: PlannedStep) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Text(plan.set.title).font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(Theme.amber)
            Text(stopLabel(s.move)).font(.title3.bold()).foregroundStyle(Theme.ink)
            if recalled == nil && !revealed {
                Text("Sıradaki hareket ne? Önce aklından söyle.").foregroundStyle(Theme.soft).multilineTextAlignment(.center)
                Button { revealed = true; Voice.tap() } label: {
                    Label("Göster", systemImage: "eye").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Theme.amber, in: Capsule()).foregroundStyle(Theme.night)
                }
            } else {
                FigureView(move: s.move).frame(height: 160)
                Text(s.move.name).font(.title.bold()).foregroundStyle(Theme.ink)
                HStack(spacing: 14) {
                    Button { answer(true) } label: { Label("Bildim", systemImage: "checkmark") }.buttonStyle(Pill(color: Theme.sage.opacity(0.3)))
                    Button { answer(false) } label: { Label("Bilemedim", systemImage: "xmark") }.buttonStyle(Pill(color: Theme.card))
                }
            }
            Spacer()
        }
    }

    @State private var revealed = false

    private func answer(_ ok: Bool) {
        recalled = ok
        asking = false
        revealed = false
        Voice.tap(.medium)
        speak(steps[index])
    }

    private func movePanel(_ s: PlannedStep) -> some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Text(stopLabel(s.move)).font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(Theme.amber)
                Text(s.move.name + (s.side.map { " · " + $0.rawValue } ?? "")).font(.title.bold()).foregroundStyle(Theme.ink)
                Text(s.move.dose).font(.subheadline).foregroundStyle(Theme.soft)
            }
            .multilineTextAlignment(.center)

            ZStack {
                FigureView(move: s.move, mirrored: s.mirrored, paused: paused)
                    .padding(.horizontal, 8)
                if let b = s.move.breath { BreathRing(breath: b, paused: paused) }
            }
            .frame(maxHeight: .infinity)

            Text(s.move.steps[min(1, s.move.steps.count - 1)])
                .font(.callout).foregroundStyle(Theme.ink.opacity(0.85)).multilineTextAlignment(.center)
                .frame(minHeight: 44)

            TimerRing(total: s.seconds, remaining: remaining)

            HStack(spacing: 14) {
                Button { markPainful() } label: { Label("Ağrıttı", systemImage: "bolt.heart") }
                    .buttonStyle(Pill(color: Theme.rose.opacity(0.25)))
                Button { paused.toggle(); Voice.tap() } label: { Image(systemName: paused ? "play.fill" : "pause.fill").frame(width: 30) }
                    .buttonStyle(Pill(color: Theme.card))
                    .accessibilityLabel(paused ? "Sürdür" : "Duraklat")
                Button { next(done: false) } label: { Label("Geç", systemImage: "forward.end.fill") }
                    .buttonStyle(Pill(color: Theme.card))
            }
            if index + 1 < steps.count, plan.phase == .learn || steps[index + 1].side == .left {
                Text("Sırada: \(steps[index + 1].move.name)" + (steps[index + 1].side.map { " · " + $0.rawValue } ?? ""))
                    .font(.footnote).foregroundStyle(Theme.soft)
            }
        }
    }

    private func startStep(_ i: Int) {
        index = i
        remaining = steps[i].seconds
        paused = false
        recalled = nil
        let s = steps[i]
        // the second side of a move is not asked again
        if plan.phase == .recall && s.side != .left {
            asking = true
            Voice.shared.say("Durak \(s.move.slot). Hangisi?")
            Voice.tap(.medium)
            return
        }
        speak(s)
        Voice.tap(.medium)
    }

    /// How much the voice says falls with the phase: everything, then the name, then only the stop number.
    private func speak(_ s: PlannedStep) {
        let sideText = s.side.map { ", \($0.rawValue.lowercased()) taraf" } ?? ""
        switch plan.phase {
        case .learn: Voice.shared.say("\(s.move.name)\(sideText). \(s.move.steps[min(1, s.move.steps.count - 1)])")
        case .recall: Voice.shared.say("\(s.move.name)\(sideText).")
        case .settle, .settled: Voice.shared.say(s.side == .left ? "Öteki taraf." : "Durak \(s.move.slot)\(sideText).")
        }
    }

    private func step() {
        guard phase == .moves, !paused, !showHelp, !asking else { return }
        remaining -= 1
        if remaining == 3, index + 1 < steps.count { Voice.tap(.light) }
        if remaining <= 0 { next(done: true) }
    }

    private func next(done: Bool, painful: Bool = false) {
        let s = steps[index]
        results.append(StepResult(move: s.move.id, side: s.side?.key, done: done, painful: painful, recalled: s.side == .left ? nil : recalled))
        if index + 1 < steps.count {
            startStep(index + 1)
        } else {
            Voice.shared.say("Bitti. Son bir kez ağrına bak.")
            phase = .after
            after = before
        }
    }

    private func markPainful() {
        Voice.shared.say("Tamam, bu hareketi geçiyoruz.")
        next(done: false, painful: true)
    }

    private func stopEarly() {
        Voice.shared.stop()
        asking = false
        if results.isEmpty { onClose(); return }
        for s in steps[index...] { results.append(StepResult(move: s.move.id, side: s.side?.key, done: false, painful: false)) }
        index = steps.count - 1
        phase = .after
        after = before
    }

    // MARK: after

    private var afterView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header("Şimdi nasıl?", "Aynı ölçü: 0 yok, 10 dayanılmaz.")
                PainPicker(pain: $after)
                Button { finish(saveAfter: true) } label: {
                    Text("Kaydet").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Theme.amber, in: Capsule()).foregroundStyle(Theme.night)
                }
            }
            .padding(20)
        }
    }

    private func finish(saveAfter: Bool) {
        let end = Date()
        let n = NightRecord(start: started, end: end, module: plan.set.key, short: plan.short || steps.count < plan.steps.count,
                            phase: plan.phase.rawValue, nightNo: plan.nightNo,
                            steps: results, before: before, after: saveAfter ? after : nil, redFlags: Array(flags).sorted())
        Store.shared.save(n)
        record = n
        if saveAfter {
            Task { await Health.shared.saveRoutine(start: started, end: end) }
            Task { await Health.shared.refreshToday() }
            phase = .card
        }
    }

    private var cardView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "moon.stars.fill").font(.system(size: 48)).foregroundStyle(Theme.amber)
            Text("İyi uykular").font(.largeTitle.bold()).foregroundStyle(Theme.ink)
            if let r = record { NightCard(record: r, day: Health.shared.today).padding(.horizontal, 20) }
            if Store.shared.checkDue || checkSaved { habitCheck.padding(.horizontal, 20) }
            Text("Telefonu bırak. Işık kapalı, nefes uzun.").font(.callout).foregroundStyle(Theme.soft)
            Spacer()
            Button("Kapat", action: onClose).font(.headline).padding(.horizontal, 48).padding(.vertical, 14)
                .background(Theme.card, in: Capsule()).foregroundStyle(Theme.ink)
        }
        .padding(.bottom, 20)
        .onAppear { Voice.shared.say("İyi uykular.") }
    }

    /// Once a week after the first seven nights: SRBAI, four items, 1 (hiç katılmıyorum) – 7 (tamamen katılıyorum).
    private var habitCheck: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HAFTALIK · NE KADAR OTOMATİK?").font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(Theme.amber)
            if checkSaved {
                Text("Kaydedildi. Ortalama \(String(format: "%.1f", Store.shared.checks.last?.score ?? 0)) / 7 (yerleşik eşik 5,5).")
                    .foregroundStyle(Theme.ink)
            } else {
                ForEach(0..<4, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(HabitCheck.questions[i]).font(.footnote).foregroundStyle(Theme.ink)
                        HStack(spacing: 4) {
                            ForEach(1...7, id: \.self) { v in
                                Button { checkItems[i] = v; Voice.tap(.light) } label: {
                                    Text("\(v)").font(.caption.bold()).frame(maxWidth: .infinity).frame(height: 26)
                                        .background(v == checkItems[i] ? Theme.amber : Theme.line, in: RoundedRectangle(cornerRadius: 6))
                                        .foregroundStyle(v == checkItems[i] ? Theme.night : Theme.soft)
                                }
                                .accessibilityLabel("\(i + 1). soru, \(v)")
                            }
                        }
                    }
                }
                Text("1 hiç katılmıyorum · 7 tamamen katılıyorum").font(.caption2).foregroundStyle(Theme.soft)
                Button("Kaydet") { Store.shared.saveCheck(checkItems); checkSaved = true }.font(.headline)
            }
        }
        .card()
    }

    private func header(_ t: String, _ s: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(t).font(.largeTitle.bold()).foregroundStyle(Theme.ink)
            Text(s).foregroundStyle(Theme.soft)
        }
        .padding(.top, 12)
    }
}

// MARK: parts

struct PainPicker: View {
    @Binding var pain: Pain

    var body: some View {
        VStack(spacing: 14) {
            row("Bel", $pain.lowBack)
            row("Boyun", $pain.neck)
            row("Diz", $pain.knee)
        }
        .card()
    }

    private func row(_ name: String, _ v: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(name).font(.headline).foregroundStyle(Theme.ink)
                Spacer()
                Text("\(v.wrappedValue)").font(.title3.monospacedDigit().bold()).foregroundStyle(Theme.painColor(v.wrappedValue))
            }
            HStack(spacing: 4) {
                ForEach(0...10, id: \.self) { i in
                    Button {
                        v.wrappedValue = i; Voice.tap(.light)
                    } label: {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(i <= v.wrappedValue ? Theme.painColor(v.wrappedValue) : Theme.line)
                            .frame(height: 30)
                            .overlay(Text("\(i)").font(.caption2).foregroundStyle(i <= v.wrappedValue ? Theme.night : Theme.soft))
                    }
                    .accessibilityLabel("\(name) \(i)")
                }
            }
        }
    }
}

struct TimerRing: View {
    let total: Int
    let remaining: Int

    var body: some View {
        ZStack {
            Circle().stroke(Theme.line, lineWidth: 6)
            Circle().trim(from: 0, to: total > 0 ? CGFloat(max(0, remaining)) / CGFloat(total) : 0)
                .stroke(Theme.amber, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: remaining)
            Text("\(max(0, remaining))").font(.title2.monospacedDigit().bold()).foregroundStyle(Theme.ink)
        }
        .frame(width: 74, height: 74)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(max(0, remaining)) saniye kaldı")
    }
}

struct BreathRing: View {
    let breath: Breath
    var paused: Bool
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: paused)) { tl in
            let cycle = breath.in + breath.out
            let t = tl.date.timeIntervalSince(start).truncatingRemainder(dividingBy: cycle)
            let inhale = t < breath.in
            let u = inhale ? t / breath.in : 1 - (t - breath.in) / breath.out
            let e = u * u * (3 - 2 * u)
            VStack {
                ZStack {
                    Circle().fill(Theme.amber.opacity(0.10 + 0.12 * e))
                    Circle().stroke(Theme.amber.opacity(0.6), lineWidth: 2)
                }
                .frame(width: 60 + 70 * e, height: 60 + 70 * e)
                Text(inhale ? "Al" : "Ver").font(.headline).foregroundStyle(Theme.amber)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(8)
        }
    }
}

struct ProgressDots: View {
    let count: Int
    let index: Int
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { i in
                Capsule().fill(i < index ? Theme.amber : i == index ? Theme.ink : Theme.line)
                    .frame(width: i == index ? 16 : 6, height: 6)
            }
        }
        .accessibilityLabel("\(count) adımdan \(index + 1).")
    }
}

struct Pill: ButtonStyle {
    var color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(color, in: Capsule())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

struct NightCard: View {
    let record: NightRecord
    let day: DaySummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            line("timer", "\(record.seconds.minutesText) · \(record.doneCount)/\(record.steps.count) hareket")
            if let a = record.after {
                line("waveform.path.ecg", "Bel \(record.before.lowBack)→\(a.lowBack) · Boyun \(record.before.neck)→\(a.neck) · Diz \(record.before.knee)→\(a.knee)")
            }
            if let d = day {
                line("figure.walk", Self.activityText(d))
                if let h = d.sleepHours { line("bed.double", "Dün gece \(Int(h)) sa \(Int((h - Double(Int(h))) * 60)) dk uyku") }
                ForEach(d.workouts, id: \.self) { w in
                    line("dumbbell", "\(w.kind) \(w.minutes) dk · \(w.source)")
                }
            }
        }
        .font(.callout)
        .card()
    }

    static func activityText(_ d: DaySummary) -> String {
        var parts = ["\(d.steps.formatted()) adım"]
        if d.walkKm >= 0.1 { parts.append(String(format: "%.1f km yürüyüş", d.walkKm)) }
        if d.cycleKm >= 0.1 { parts.append(String(format: "%.1f km bisiklet", d.cycleKm)) }
        return parts.joined(separator: " · ")
    }

    private func line(_ icon: String, _ text: String) -> some View {
        Label { Text(text).foregroundStyle(Theme.ink) } icon: { Image(systemName: icon).foregroundStyle(Theme.amber) }
    }
}
