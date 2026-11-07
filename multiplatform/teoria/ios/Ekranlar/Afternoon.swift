// İkinci dikkat (Kurultay decision 2026-11-05, step 2): at 14:00, 20 minutes on what the morning marked.
// The list is library/ikinci.json (veri/ikinci.py on the Mac): Cümle stumbles, Sabah cards that did not hold,
// sentences marked today. What was looked at lives in the event log (afternoonItem · afternoonDone), shared by
// the Mac and the iPhone. Items not looked at simply drop: tomorrow brings only tomorrow's morning (no debt).
import SwiftUI

struct AfternoonItem: Codable, Identifiable, Hashable {
    var id: String
    var kind: String            // english · card · mark
    var source: String
    var text: String
    var tr: String?
    var wrote: String?
    var percent: Int?
    var book: String?
    var ch: Int?
    var question: String?
    var answer: String?
    var why: String?

    var label: String {
        switch kind {
        case "english": "İngilizce"
        case "card": "Tutmayan kart"
        default: "İşaretin"
        }
    }
    var symbol: String {
        switch kind {
        case "english": "character.bubble"
        case "card": "rectangle.stack.badge.minus"
        default: "highlighter"
        }
    }
}

struct AfternoonPlan: Codable {
    var v = 1
    var day = ""
    var built = ""
    var minutes = 20
    var items: [AfternoonItem] = []
}

@MainActor
final class AfternoonStore: ObservableObject {
    static let shared = AfternoonStore()
    @Published private(set) var plan = AfternoonPlan()
    private var timer: Timer?

    private var local: URL { Paylasim.kapsayici.appendingPathComponent("bookshelf/ikinci.json") }

    init() {
        load()
        #if os(macOS)
        // the Mac rebuilds the list every 30 minutes while Teoria is open (Cümle and the morning feed it)
        timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.prepare() }
        }
        Task { await prepare() }
        #endif
    }

    var today: [AfternoonItem] { plan.day == Tarih.gun(Date()) ? plan.items : [] }

    func load() {
        var candidates = [local]
        #if os(macOS)
        candidates.insert(Kasa.macYolu.appendingPathComponent("library/ikinci.json"), at: 0)
        #endif
        for u in candidates {
            if let v = try? Data(contentsOf: u), let p = try? JSONDecoder().decode(AfternoonPlan.self, from: v) {
                plan = p
                return
            }
        }
    }

    func prepare() async {
        #if os(macOS)
        let teoria = Kasa.macYolu
        await Task.detached(priority: .utility) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            p.arguments = [teoria.appendingPathComponent("veri/ikinci.py").path]
            p.currentDirectoryURL = teoria.appendingPathComponent("veri")
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
        }.value
        #endif
        load()
    }
}

/// The 20-minute box for the afternoon block, shared through the event log like the morning one.
@MainActor
enum AfternoonBox {
    static let plan: TimeBoxPlan = {
        #if os(macOS)
        return TimeBoxPlan.load(vault: MorningBox.vault)
        #else
        return .standard
        #endif
    }()
    static let block = plan.block("second") ?? TimeBoxBlock(id: "second", title: "İkinci dikkat", app: "teoria", start: "14:00", minutes: 20)
    static let clock = TimeBoxClock(block: block, plan: plan)
    static var key: String { MorningStore.todayKey + "#second" }
    private static weak var depo: Depo?

    static func connect(_ d: Depo) {
        guard depo == nil else { return }
        depo = d
        clock.onChange = { s, type in
            switch type {
            case "timebox.started": depo?.ekle(Olay(tur: .zamanBasla, hedef: key))
            case "timebox.extended": depo?.ekle(Olay(tur: .zamanUzat, hedef: key, sure: Double(s.extendedMinutes)))
            default: break   // finish = afternoonDone
            }
            if let v = MorningBox.vault {
                if s.started != nil { TimeBoxDay.write(vault: v, id: block.id, s) }
                TimeBoxBus.emit(vault: v, app: "teoria", device: Cihaz.ad, type: type, block: block, state: s)
            }
        }
    }
}

struct AfternoonView: View {
    @EnvironmentObject var depo: Depo
    @ObservedObject private var store = AfternoonStore.shared
    // only the bar and the cards watch the clock's seconds; this screen follows `glance` (see timeBoxGlance)
    private var box: TimeBoxClock { AfternoonBox.clock }
    @State private var glance = TimeBoxGlance(AfternoonBox.clock)
    var wide = false
    var close: (() -> Void)?

    private var d: Durum { depo.durum }
    private var today: String { MorningStore.todayKey }
    private var items: [AfternoonItem] { store.today }
    private var seen: Set<String> { d.afternoonItems[today] ?? [] }
    private var dayDone: Bool { d.afternoonDone[today] != nil }

    var body: some View {
        VStack(spacing: 0) {
            if !items.isEmpty && !glance.done { TimeBoxBar(clock: box) }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if glance.done || dayDone { TimeBoxDoneCard(clock: box) }
                    if items.isEmpty {
                        empty
                    } else {
                        ForEach(items) { item in
                            AfternoonCard(item: item, done: seen.contains(item.id)) { touch() } onDone: {
                                touch()
                                depo.ekle(Olay(tur: .afternoonItem, hedef: item.id, metin: today))
                            }
                        }
                        if !dayDone {
                            Button { finish() } label: {
                                Label(seen.count >= items.count ? "İkinci dikkati kapat" : "Bugünlük yeter, kapat", systemImage: "checkmark.seal")
                                    .padding(.horizontal, 8)
                            }
                            .buttonStyle(AnaDugme(renk: seen.count >= items.count ? Tema.basari : Tema.vurgu))
                            .frame(maxWidth: 360)
                            .keyboardShortcut(.return, modifiers: .command)
                        }
                    }
                }
                .padding(.horizontal, wide ? 32 : 18).padding(.vertical, wide ? 24 : 12)
                .frame(maxWidth: wide ? 900 : .infinity, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Tema.arka)
        .overlay {
            if glance.over && !dayDone {
                ZStack {
                    Color.black.opacity(0.18).ignoresSafeArea()
                    TimeBoxOverCard(clock: box, finishLabel: "Kapat") { finish() }
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: glance.over)
        .timeBoxGlance(box, $glance)
        .task { await store.prepare() }
        .onAppear { AfternoonBox.connect(depo); sync() }
        .onChange(of: depo.durum.zamanKutusu[AfternoonBox.key]) { _, _ in sync() }
        .onChange(of: dayDone) { _, _ in sync() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("İKİNCİ DİKKAT · 14:00").font(.caption.weight(.semibold)).tracking(0.6).foregroundStyle(Tema.vurgu)
                Text(items.isEmpty ? "Bugün sabahtan kalan yok" : "Sabahın \(items.count) öğesi · \(seen.count) bakıldı")
                    .font(Tema.serif(.title2)).foregroundStyle(Tema.metin)
                Text("Önce hatırla, sonra bak. Bakılmayan öğe yarına kalmaz.").font(.subheadline).foregroundStyle(Tema.ikincil)
            }
            Spacer()
            if let close {
                Button("Kapat", action: close).buttonStyle(.bordered)
            }
        }
    }

    private var empty: some View {
        Text("İkinci dikkatin malzemesi sabahın işleridir: Cümle'de takıldığın cümleler, Sabah'ta tutmayan kartlar, bugün işaretlediğin cümleler. Bunlar olunca liste kendiliğinden dolar.")
            .font(.subheadline).foregroundStyle(Tema.ikincil)
    }

    private func touch() { if !dayDone { box.touch() } }

    private func finish() {
        guard !dayDone else { return }
        depo.ekle(Olay(tur: .afternoonDone, hedef: today, puan: Double(seen.count), metin: "\(seen.count)/\(items.count)"))
        box.finish()
    }

    private func sync() {
        var s = d.zamanKutusu[AfternoonBox.key] ?? TimeBoxState()
        if let done = d.afternoonDone[today] { s.finished = done.t; if s.started == nil { s.started = done.t } }
        box.adopt(s)
        if let v = MorningBox.vault, s.started != nil { TimeBoxDay.write(vault: v, id: AfternoonBox.block.id, box.state) }
    }
}

/// One item: recall first (the answer/the right sentence is hidden until asked), then explain in one sentence.
struct AfternoonCard: View {
    let item: AfternoonItem
    let done: Bool
    var onTouch: () -> Void
    var onDone: () -> Void
    @State private var open = false
    @State private var writing = false
    @State private var note = ""
    @State private var saved = false

    var body: some View {
        Yuzey {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Label(item.label, systemImage: item.symbol).font(.caption.weight(.semibold)).foregroundStyle(Tema.vurgu)
                    Text(item.source).font(.caption).foregroundStyle(Tema.ikincil).lineLimit(1)
                    Spacer()
                    if done { Image(systemName: "checkmark.circle.fill").foregroundStyle(Tema.basari) }
                }
                content
                if writing {
                    TextField(item.kind == "english" ? "Yapıyı kendi cümlenle açıkla…" : "Bu cümle ne diyor? Tek cümle…", text: $note, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(2...5)
                        .onSubmit(save)
                }
                HStack(spacing: 10) {
                    if !open {
                        Button { onTouch(); withAnimation { open = true } } label: { Label(item.kind == "mark" ? "Bağlamıyla aç" : "Göster", systemImage: "eye") }
                    }
                    Button { onTouch(); if writing { save() } else { withAnimation { writing = true } } } label: {
                        Label(writing ? "Kaydet" : (saved ? "Açıklandı" : "Açıkla"), systemImage: saved ? "checkmark" : "pencil")
                    }
                    .disabled(saved && !writing)
                    if let b = item.book {
                        Button { NotificationCenter.default.post(name: .init("teoria.rota"), object: "kitap:" + b) } label: {
                            Label("Kitapta aç", systemImage: "book")
                        }
                    }
                    Spacer()
                    if !done {
                        Button { onDone() } label: { Label("Tamam", systemImage: "checkmark") }.buttonStyle(.borderedProminent)
                    }
                }
                .buttonStyle(.bordered).font(.callout)
                .labelStyle(CompactLabel())
                .lineLimit(1)
            }
        }
        .opacity(done ? 0.7 : 1)
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case "english":
            VStack(alignment: .leading, spacing: 6) {
                if let tr = item.tr { Text(tr).font(Tema.serif(.body)).foregroundStyle(Tema.metin) }
                if let w = item.wrote {
                    Text("Yazdığın: \(w)").font(.callout).foregroundStyle(Tema.ikincil)
                }
                if open {
                    Text("Doğrusu: \(item.text)").font(.callout.weight(.semibold)).foregroundStyle(Tema.basari)
                        .transition(.opacity)
                } else {
                    Text("Önce doğrusunu kendin kur, sonra Göster.").font(.caption).foregroundStyle(Tema.ikincil)
                }
            }
        case "card":
            VStack(alignment: .leading, spacing: 6) {
                Text(item.question ?? item.text).font(Tema.serif(.body)).foregroundStyle(Tema.metin)
                if open {
                    if let a = item.answer { Text(a).font(.callout.weight(.semibold)).foregroundStyle(Tema.basari) }
                    if let w = item.why { Text(w).font(.callout).foregroundStyle(Tema.ikincil) }
                }
            }
        default:
            Text(item.text).font(Tema.serif(.body)).foregroundStyle(Tema.metin)
                .lineLimit(open ? nil : 4)
        }
    }

    private func save() {
        let t = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { writing = false; return }
        NotesStore.shared.add(book: item.book ?? "genel", title: item.source,
                              anchor: item.ch.map { NoteAnchor(ch: $0, b: 0, s: 0, e: 0, quote: item.text, chapterTitle: nil) },
                              text: t, recording: nil)
        withAnimation { writing = false; saved = true }
        onDone()
    }
}

/// Icon + one-line title that never wraps (narrow phones shorten the title instead of breaking it).
struct CompactLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.icon; configuration.title.lineLimit(1).minimumScaleFactor(0.75) }
    }
}

/// Bugün's entry to the afternoon block (iPhone opens it over everything, the Mac switches tab).
struct AfternoonEntryCard: View {
    @EnvironmentObject var depo: Depo
    @ObservedObject private var store = AfternoonStore.shared
    let open: () -> Void

    var body: some View {
        let items = store.today
        let today = MorningStore.todayKey
        let seen = depo.durum.afternoonItems[today]?.count ?? 0
        let done = depo.durum.afternoonDone[today] != nil
        if !items.isEmpty {
            Button(action: open) {
                Yuzey {
                    HStack(spacing: 12) {
                        Image(systemName: done ? "checkmark.seal.fill" : "eye").font(.title2)
                            .foregroundStyle(done ? Tema.basari : Tema.vurgu)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("İkinci dikkat · 14:00").font(.headline).foregroundStyle(Tema.metin)
                            Text(done ? "Bugün kapandı · \(seen)/\(items.count)" : "\(items.count) öğe · 20 dk · \(seen) bakıldı")
                                .font(.subheadline).foregroundStyle(Tema.ikincil)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Tema.ikincil)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}
