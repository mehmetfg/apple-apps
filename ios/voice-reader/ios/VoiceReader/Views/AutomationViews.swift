// Otomasyon: the card on the library's home (start, go on from where it was left, stop), the Otomasyon sheet the
// gear menu's Otomasyon opens (the list of automations, the editor of one), and the line the mini player shows while
// one runs.
import SwiftUI

// MARK: - the library card

/// Under the strip: which step, which book, how much is left in it.
private struct AutomationStatusLine: View {
    @Environment(AppModel.self) private var model
    let automation: Automation
    let step: Int
    let running: Bool
    var listened: Double = 0

    var body: some View {
        if automation.steps.indices.contains(step) {
            let s = automation.steps[step]
            let run = model.automationRun
            let book = running && run?.phase != .thinking ? run?.documentTitle : s.folder.flatMap { model.automationDocument(in: $0)?.title }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 0) {
                    Text(running ? "Şimdi" : "Kaldığı yer").foregroundStyle(running ? Palette.play : .secondary)
                    Text(" · \(step + 1)/\(automation.steps.count) · \(running ? run?.stepTitle ?? "" : s.folder ?? "")")
                        .foregroundStyle(.primary)
                    Spacer(minLength: 4)
                    if running { AutomationClock() }
                    else { Text(Format.clock(max(0, s.seconds - Int(listened.rounded()))) + " kaldı").monospacedDigit().foregroundStyle(.secondary) }
                }
                .font(.footnote.weight(.semibold)).lineLimit(1)
                if let book { Text(book).font(.footnote).foregroundStyle(.secondary).lineLimit(1) }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// The automation's steps as one strip: a reading step is a bar as long as its minutes, in its folder's colour; a
/// break is a dot. Steps before `current` are full, `current` fills with the seconds heard in it.
struct AutomationTrack: View {
    let automation: Automation
    var current: Int?
    var heard: Double = 0

    var body: some View {
        GeometryReader { g in
            let steps = automation.steps
            let gap: CGFloat = 5, dot: CGFloat = 7
            let dots = steps.filter { $0.kind == .pause }.count
            let room = max(0, g.size.width - CGFloat(dots) * dot - gap * CGFloat(max(0, steps.count - 1)))
            let total = CGFloat(max(1, automation.readingSeconds))
            HStack(spacing: gap) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { i, s in
                    let f = fill(i, s)
                    if s.kind == .read {
                        let tint = s.folder.map { FolderScope.named($0).tint } ?? .secondary
                        let w = room * CGFloat(s.seconds) / total
                        Capsule().fill(tint.opacity(0.22))
                            .overlay(alignment: .leading) { Capsule().fill(tint).frame(width: f > 0 ? max(8, w * f) : 0) }
                            .clipShape(Capsule())
                            .frame(width: w)
                    } else {
                        Circle().fill(Color.secondary.opacity(f > 0 ? 0.8 : 0.25)).frame(width: dot, height: dot)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }

    private func fill(_ i: Int, _ s: AutomationStep) -> Double {
        guard let current else { return 0 }
        if i < current { return 1 }
        if i > current { return 0 }
        return s.kind == .pause ? 1 : min(1, heard / Double(max(1, s.seconds)))
    }
}

// MARK: - the Otomasyon sheet

struct AutomationSheet: View {
    var body: some View {
        NavigationStack { AutomationListView() }
    }
}

struct AutomationListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Automation?
    @State private var choosing: Automation?        // play pressed on one that was left midway: go on, or start over

    var body: some View {
        List {
            if model.automationRun != nil {
                Section("Şu an") { AutomationNowCard() }
            }
            Section {
                ForEach(model.automations.list) { a in
                    AutomationRow(automation: a, running: model.automationRun?.automation.id == a.id) {
                        if model.automations.resumePoint(for: a) != nil { choosing = a } else { model.startAutomation(a) }
                    } edit: { editing = a }
                }
                .onDelete { model.automations.delete($0.map { model.automations.list[$0].id }) }
                .onMove { model.automations.move(from: $0, to: $1) }
                Button { editing = Automation(name: "Yeni otomasyon", steps: [.read(model.store.folders.first ?? "Felsefe", minutes: 15)]) } label: {
                    Label("Yeni otomasyon", systemImage: "plus")
                }
            } footer: {
                Text("Her okuma adımı klasörün güncel kitabını (en son dinlediğin, bitmemiş olanı) kaldığı yerden okur; süre yalnız ses duyulurken sayılır. Süre dolunca cümlenin sonunda durur, ara ve sıradaki adım kendiliğinden gelir; telefona dokunman gerekmez. Durdurursan ya da başka bir kitap açarsan otomasyon kaldığı adımı hatırlar: Kütüphane'deki Otomasyon kartından ya da burada ▶ ile kaldığı yerden sürdürürsün. Baştan, ilk adımdan tam sürelerle başlar; kitaplar yine kaldıkları yerden okunur.")
            }
        }
        .navigationTitle("Otomasyon")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { EditButton() }
            ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } }
        }
        .sheet(item: $editing) { a in
            NavigationStack { AutomationEditor(automation: a) }
        }
        .confirmationDialog(choosing?.name ?? "", isPresented: Binding(get: { choosing != nil }, set: { if !$0 { choosing = nil } }),
                            titleVisibility: .visible, presenting: choosing) { a in
            if let p = model.automations.resumePoint(for: a) {
                let s = a.steps[p.step]
                Button("Kaldığı yerden · \(s.folder ?? "") · \(Format.clock(max(0, s.seconds - Int(p.listened.rounded())))) kaldı") {
                    model.startAutomation(a, resume: true)
                }
            }
            Button("Baştan başlat") { model.startAutomation(a) }
            Button("Vazgeç", role: .cancel) {}
        }
    }
}

private struct AutomationRow: View {
    @Environment(AppModel.self) private var model
    let automation: Automation
    let running: Bool
    var start: () -> Void
    var edit: () -> Void

    var body: some View {
        let resume = running ? nil : model.automations.resumePoint(for: automation)
        HStack(spacing: 12) {
            Button(action: edit) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(automation.name).font(.body.weight(.semibold))
                    Text(automation.steps.map { $0.kind == .read ? "\($0.folder ?? "?") \($0.seconds / 60)" : "ara" }.joined(separator: " → "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Text("Okuma \(Format.minutes(automation.readingSeconds)) · toplam \(Format.minutes(automation.totalSeconds))")
                        .font(.caption2).foregroundStyle(.tertiary)
                    if let resume {
                        let s = automation.steps[resume.step]
                        Label("Kaldığı yer: \(resume.step + 1)/\(automation.steps.count) · \(s.folder ?? "") · \(Format.clock(max(0, s.seconds - Int(resume.listened.rounded())))) kaldı",
                              systemImage: "bookmark.fill")
                            .font(.caption2.weight(.semibold)).foregroundStyle(Palette.play)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                if running { model.stopAutomation() } else { start() }
            } label: {
                Image(systemName: running ? "stop.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(running ? Color.secondary : Palette.playFill, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(running ? "Otomasyonu durdur" : resume != nil ? "Otomasyonu sürdür ya da baştan başlat: \(automation.name)" : "Otomasyonu başlat: \(automation.name)")
        }
        .padding(.vertical, 2)
    }
}

/// The running automation: step, book, time left, stop.
struct AutomationNowCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let run = model.automationRun {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(run.automation.steps.enumerated()), id: \.element.id) { i, s in
                    HStack(spacing: 10) {
                        Image(systemName: i < run.step ? "checkmark.circle.fill" : i == run.step ? "play.circle.fill" : "circle")
                            .foregroundStyle(i == run.step ? Palette.playFill : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.title).font(.subheadline.weight(i == run.step ? .semibold : .regular))
                            if s.kind == .read, let f = s.folder {
                                let doc = i == run.step ? run.documentTitle : model.automationDocument(in: f)?.title
                                Text(doc ?? "Okunacak kitap yok").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer()
                        if i == run.step { AutomationClock() }
                    }
                }
                Button(role: .destructive) { model.stopAutomation() } label: {
                    Label("Durdur", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 4)
        }
    }
}

/// Time left in the current step (reading: listening time left; pause: the countdown).
struct AutomationClock: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            Text(text(at: ctx.date)).font(.caption.weight(.medium)).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private func text(at date: Date) -> String {
        guard let run = model.automationRun else { return "" }
        switch run.phase {
        case .thinking:
            return Format.clock(max(0, Int((run.phaseEnds ?? date).timeIntervalSince(date).rounded())))
        case .reading:
            let left = run.stepSeconds - run.listenedBefore - model.player.segmentListened
            return Format.clock(max(0, Int(left.rounded()))) + " kaldı"
        case .announcing:
            return "duyuru"
        }
    }
}

/// Under the title in the mini player while an automation runs.
struct AutomationBadge: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let run = model.automationRun {
            HStack(spacing: 5) {
                Image(systemName: run.phase == .thinking ? "brain.head.profile" : "list.bullet.rectangle")
                Text("\(run.position) · \(run.stepTitle)")
                AutomationClock()
            }
            .font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
            .accessibilityElement(children: .combine)
        }
    }
}

struct AutomationEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var automation: Automation

    var body: some View {
        Form {
            Section("Ad") { TextField("Ad", text: $automation.name) }
            Section {
                ForEach($automation.steps) { $step in
                    StepEditor(step: $step)
                }
                .onDelete { automation.steps.remove(atOffsets: $0) }
                .onMove { automation.steps.move(fromOffsets: $0, toOffset: $1) }
                Menu {
                    ForEach(model.store.folders, id: \.self) { f in
                        Button(f) { automation.steps.append(.read(f, minutes: 15)) }
                    }
                } label: { Label("Okuma ekle", systemImage: "book") }
                Button { automation.steps.append(.pause(seconds: 60)) } label: { Label("Ara ekle", systemImage: "brain.head.profile") }
            } header: { Text("Adımlar") } footer: {
                Text("Okuma \(Format.minutes(automation.readingSeconds)) · toplam \(Format.minutes(automation.totalSeconds)). Sırayı değiştirmek için Düzenle.")
            }
        }
        .navigationTitle(automation.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Kaydet") { model.automations.upsert(automation); dismiss() }.disabled(automation.steps.isEmpty)
            }
            ToolbarItem(placement: .bottomBar) { EditButton() }
        }
    }
}

private struct StepEditor: View {
    @Environment(AppModel.self) private var model
    @Binding var step: AutomationStep

    var body: some View {
        switch step.kind {
        case .read:
            VStack(alignment: .leading, spacing: 6) {
                Picker(selection: Binding(get: { step.folder ?? "" }, set: { step.folder = $0 })) {
                    ForEach(model.store.folders, id: \.self) { Text($0).tag($0) }
                } label: { Label("Klasör", systemImage: "book") }
                Stepper(value: Binding(get: { step.seconds / 60 }, set: { step.seconds = $0 * 60 }), in: 1...120) {
                    Text("Süre: \(step.seconds / 60) dk").monospacedDigit()
                }
                if let f = step.folder {
                    let doc = model.automationDocument(in: f)
                    Text(doc.map { "Güncel kitap: \($0.title) · %\(Int($0.progress * 100))" } ?? "Bu klasörde okunacak kitap yok")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        case .pause:
            Stepper(value: $step.seconds, in: 15...600, step: 15) {
                Label("Düşünme arası: \(Format.clock(step.seconds))", systemImage: "brain.head.profile").monospacedDigit()
            }
        }
    }
}
