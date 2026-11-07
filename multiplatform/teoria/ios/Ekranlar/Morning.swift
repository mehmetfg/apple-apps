// Sabah — the morning room (2026-10-26). What you heard in Voice Reader yesterday, on the weekend, this morning on the
// way, brought back in four steps: contact (summary + concept map), marks (yours, the key sentences, the ones you
// missed), close · recall · write (or say, on the phone), review (active-recall cards on FSRS). Then the day closes.
//
// The plan is library/sabah.json (veri/sabah.py on the Mac). Which day was studied and every card's state live in the
// event log (morningStep · morningCard · morningDone), so the Mac and the iPhone see each other's work.
// No debt: nothing says "N cards waiting"; a day not studied is shown as an open circle, never red.
import SwiftUI

// MARK: - The plan

struct MorningPlan: Codable {
    var v: Int = 1
    var built: String = ""
    var today: String = ""
    var days: [MorningDay] = []
    var chapters: [String: MorningChapter] = [:]
    var cards: [MorningCard] = []
}

struct MorningDay: Codable, Identifiable, Hashable {
    var date: String
    var weekday: String
    var minutes: Double
    var words: Int
    var items: [MorningItem]
    var id: String { date }
}

struct MorningItem: Codable, Hashable {
    var doc: String
    var book: String?
    var title: String
    var branch: String
    var minutes: Double
    var words: Int
    var chapters: [Int]
    var estimated: Bool
    var dayLabel: String?
}

struct MorningChapter: Codable, Hashable {
    struct Quote: Codable, Hashable { var quote: String; var why: String? }
    struct Node: Codable, Hashable { var id: String; var label: String; var note: String?; var here: Bool }
    struct Edge: Codable, Hashable { var a: String; var b: String; var label: String }
    struct Mark: Codable, Hashable { var quote: String; var date: String?; var note: String? }
    var book: String
    var ch: Int
    var title: String
    var part: String?
    var key: String?
    var summary: String?
    var keys: [Quote]
    var missed: [Quote]
    var nodes: [Node]
    var edges: [Edge]
    var marks: [Mark]
    var thesis: String?
}

struct MorningCard: Codable, Identifiable, Hashable {
    var id: String
    var book: String
    var ch: Int
    var kind: String          // quiz · cross · mark · cloze · who · edge · recall
    var prompt: String
    var answer: String
    var options: [String]
    var full: String
    var why: String?
    var weight: Int?
    var lane: String?         // "cross": asked to tie today's reading to an earlier one
}

/// One book of the focus days, its chapters merged across those days.
struct MorningBook: Identifiable, Hashable {
    var id: String
    var title: String
    var branch: String
    var minutes: Double
    var chapters: [MorningChapter]
    var estimated: Bool
    var days: [String]

    var nodes: [MorningChapter.Node] {
        var seen = Set<String>(), out: [MorningChapter.Node] = []
        for n in chapters.flatMap(\.nodes) where n.here && seen.insert(n.id).inserted { out.append(n) }
        return Array(out.prefix(10))
    }
    var edges: [MorningChapter.Edge] {
        let ids = Set(nodes.map(\.id))
        var seen = Set<String>()
        return chapters.flatMap(\.edges).filter { ids.contains($0.a) && ids.contains($0.b) && seen.insert($0.a + ">" + $0.b).inserted }
    }
    var keys: [MorningChapter.Quote] { Array(chapters.compactMap(\.keys.first).prefix(6)) }
    var missed: [MorningChapter.Quote] { Array(chapters.flatMap(\.missed).prefix(4)) }
    var marks: [MorningChapter.Mark] {
        var seen = Set<String>()
        return chapters.flatMap(\.marks).filter { seen.insert($0.quote).inserted }
    }
}

enum MorningStep: String, CaseIterable, Identifiable {
    case contact, marks, recall, review
    var id: String { rawValue }
    var title: String {
        switch self {
        case .contact: "Temas"
        case .marks: "İşaretler"
        case .recall: "Kapat · hatırla"
        case .review: "Tekrar"
        }
    }
    var symbol: String {
        switch self {
        case .contact: "point.3.connected.trianglepath.dotted"
        case .marks: "highlighter"
        case .recall: "eye.slash"
        case .review: "rectangle.stack"
        }
    }
}

enum MorningBranch {
    static func color(_ b: String) -> Color {
        switch b {
        case "Felsefe": Color.dinamik(0x5B5BD6, 0x8E8EFF)
        case "Bilimler": Color.dinamik(0x17907A, 0x3CD3B4)
        case "Mühendislik": Color.dinamik(0xC9711B, 0xFFAD47)
        default: Tema.soluk
        }
    }
    static let order = ["Felsefe", "Bilimler", "Mühendislik", "Diğer"]
}

// MARK: - The store

@MainActor
final class MorningStore: ObservableObject {
    static let shared = MorningStore()
    @Published private(set) var plan = MorningPlan()
    @Published private(set) var preparing = false

    private var local: URL { Paylasim.kapsayici.appendingPathComponent("bookshelf/sabah.json") }

    init() { load() }

    private var candidates: [URL] {
        var c = [local]
        #if os(macOS)
        c.insert(Kasa.macYolu.appendingPathComponent("library/sabah.json"), at: 0)
        #endif
        return c
    }

    func load() {
        for u in candidates {
            if let v = try? Data(contentsOf: u), let p = try? JSONDecoder().decode(MorningPlan.self, from: v) {
                plan = p
                return
            }
        }
    }

    /// After a sync brought a new plan: read and decoded off the main actor (the file is about 0.6 MB).
    func reload() async {
        let files = candidates
        let fresh = await Task.detached { () -> MorningPlan? in
            for u in files {
                if let v = try? Data(contentsOf: u), let p = try? JSONDecoder().decode(MorningPlan.self, from: v) { return p }
            }
            return nil
        }.value
        if let fresh { plan = fresh }
    }

    /// Mac: rebuilds the plan from Voice Reader (phone over devicectl when paired) unless it was built in the last hour.
    func prepare(force: Bool = false) async {
        #if os(macOS)
        guard !preparing else { return }
        if !force, plan.today == Tarih.gun(Date()), let b = Tarih.coz(plan.built), Date().timeIntervalSince(b) < 3600 { return }
        preparing = true
        defer { preparing = false }
        let teoria = Kasa.macYolu
        await Task.detached(priority: .userInitiated) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            p.arguments = [teoria.appendingPathComponent("veri/sabah.py").path, "--telefon"]
            p.currentDirectoryURL = teoria
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
        }.value
        load()
        #endif
    }

    // MARK: derived

    static var todayKey: String { Tarih.gun(Date()) }

    func covered(_ d: Durum) -> Set<String> {
        Set(d.morningDone.values.flatMap { ($0.metin ?? "").split(separator: ",").map { String($0) } })
    }

    /// The listening days the session is about: chosen day, else the not-yet-studied days of the last week (newest
    /// three), else the newest day that has listening.
    func focusDays(_ d: Durum, chosen: String?) -> [MorningDay] {
        let heard = plan.days.filter { !$0.items.isEmpty }
        if let c = chosen, let day = heard.first(where: { $0.date == c }) { return [day] }
        let done = covered(d)
        let weekAgo = Tarih.gun(Date().gun(-7))
        let open = heard.filter { $0.date >= weekAgo && !done.contains($0.date) }.suffix(3)
        if !open.isEmpty { return Array(open) }
        return heard.last.map { [$0] } ?? []
    }

    func books(for days: [MorningDay]) -> [MorningBook] {
        var out: [String: MorningBook] = [:]
        var order: [String] = []
        for day in days {
            for it in day.items {
                let key = it.book ?? it.doc
                if out[key] == nil {
                    order.append(key)
                    out[key] = MorningBook(id: key, title: it.title, branch: it.branch, minutes: 0, chapters: [], estimated: false, days: [])
                }
                out[key]!.minutes += it.minutes
                out[key]!.estimated = out[key]!.estimated || it.estimated
                if !out[key]!.days.contains(day.date) { out[key]!.days.append(day.date) }
                for c in it.chapters {
                    guard let b = it.book, let ch = plan.chapters["\(b)#\(c)"],
                          !out[key]!.chapters.contains(where: { $0.ch == c }) else { continue }
                    out[key]!.chapters.append(ch)
                }
            }
        }
        return order.compactMap { out[$0] }
            .map { var b = $0; b.chapters.sort { $0.ch < $1.ch }; return b }
            .sorted { (MorningBranch.order.firstIndex(of: $0.branch) ?? 9) < (MorningBranch.order.firstIndex(of: $1.branch) ?? 9) }
    }

    /// Today's review: cards that are due first, then new ones from the focus chapters (heaviest first, books taking
    /// turns). At most 12, at most 8 new.
    func reviewQueue(_ d: Durum, books: [MorningBook]) -> [MorningCard] {
        let now = Date()
        let due = plan.cards.filter { d.morningCards[$0.id].map { $0.vade <= now } ?? false }
            .sorted { (d.morningCards[$0.id]?.vade ?? now) < (d.morningCards[$1.id]?.vade ?? now) }
        let focus = Set(books.flatMap { b in b.chapters.map { "\(b.id)#\($0.ch)" } })
        var perBook: [String: [MorningCard]] = [:]
        for c in plan.cards where d.morningCards[c.id] == nil && focus.contains("\(c.book)#\(c.ch)") {
            perBook[c.book, default: []].append(c)
        }
        for k in perBook.keys { perBook[k]!.sort { ($0.weight ?? 2) > ($1.weight ?? 2) } }
        var fresh: [MorningCard] = []
        let room = min(8, max(0, 12 - min(due.count, 12)))
        var i = 0
        while fresh.count < room, perBook.values.contains(where: { $0.count > i }) {
            for b in books.map(\.id) where fresh.count < room { if let l = perBook[b], l.count > i { fresh.append(l[i]) } }
            i += 1
        }
        return Array(due.prefix(12)) + fresh
    }

    /// The day the Kür is about: today's listening, else the newest day that has listening.
    func quizDay() -> MorningDay? { plan.days.last { !$0.items.isEmpty } }

    /// The Kür (2026-11-03): short and about today. At most 6 questions from the chapters of the quiz day (the questions
    /// written with the text first, books taking turns), 2 of your own marks there, 2 that tie it to earlier readings.
    /// A card answered today is not asked again; one seen before comes back only when FSRS says it is due.
    func quizQueue(_ d: Durum) -> [MorningCard] {
        let now = Date(), today = now.gunBasi
        func open(_ c: MorningCard) -> Bool {
            guard let s = d.morningCards[c.id] else { return true }
            return s.son.gunBasi != today && s.vade <= now
        }
        guard let day = quizDay() else {
            return Array(plan.cards.filter { d.morningCards[$0.id] != nil && open($0) }.prefix(10))
        }
        let books = books(for: [day])
        let focus = Set(books.flatMap { b in b.chapters.map { "\(b.id)#\($0.ch)" } })
        let here = plan.cards.filter { focus.contains("\($0.book)#\($0.ch)") && open($0) }
        let rank = ["quiz": 0, "cloze": 1, "edge": 2, "who": 3, "recall": 4]
        var perBook: [String: [MorningCard]] = [:]
        for c in here where rank[c.kind] != nil { perBook[c.book, default: []].append(c) }
        for k in perBook.keys {
            perBook[k]!.sort { (rank[$0.kind]!, -($0.weight ?? 2)) < (rank[$1.kind]!, -($1.weight ?? 2)) }
        }
        var main: [MorningCard] = []
        var i = 0
        while main.count < 6, perBook.values.contains(where: { $0.count > i }) {
            for b in books.map(\.id) where main.count < 6 { if let l = perBook[b], l.count > i { main.append(l[i]) } }
            i += 1
        }
        let marks = Array(here.filter { $0.kind == "mark" }.prefix(2))
        var cross = Array(here.filter { $0.kind == "cross" }.prefix(2))
        if cross.count < 2 {
            // earlier readings: cards already met and due first, then the heaviest of the days before
            let earlier = plan.cards.filter { !focus.contains("\($0.book)#\($0.ch)") && $0.kind != "mark" && open($0) }
                .sorted { (d.morningCards[$0.id] == nil ? 1 : 0, -($0.weight ?? 2)) < (d.morningCards[$1.id] == nil ? 1 : 0, -($1.weight ?? 2)) }
            for var c in earlier where cross.count < 2 && !cross.contains(where: { $0.book == c.book }) {
                c.lane = "cross"
                cross.append(c)
            }
        }
        return Array((main + marks + cross).prefix(10))
    }

    func nextReview(_ d: Durum) -> Date? {
        d.morningCards.values.map(\.vade).filter { $0 > Date() }.min()
    }
}

// MARK: - The room

struct MorningView: View {
    @EnvironmentObject var depo: Depo
    @ObservedObject private var store = MorningStore.shared
    var wide = false
    var close: (() -> Void)?

    @State private var chosenDay: String?
    @State private var step: MorningStep = .contact
    @State private var queue: [MorningCard] = []
    @State private var finished = false

    private var d: Durum { depo.durum }
    private var today: String { MorningStore.todayKey }
    private var days: [MorningDay] { store.focusDays(d, chosen: chosenDay) }
    private var books: [MorningBook] { store.books(for: days) }
    private var doneSteps: Set<String> { d.morningSteps[today] ?? [] }
    private var dayDone: Bool { d.morningDone[today] != nil }

    // The clock ticks once a second; only the bar and the cards watch it. The room itself follows `glance`.
    private var box: TimeBoxClock { MorningBox.clock }
    @State private var glance = TimeBoxGlance(MorningBox.clock)

    var body: some View {
        VStack(spacing: 0) {
            if !store.plan.days.allSatisfy({ $0.items.isEmpty }) && !glance.done { TimeBoxBar(clock: box) }
            content
        }
        .timeBoxGlance(box, $glance)
        .overlay {
            if glance.over && !dayDone {
                ZStack {
                    Color.black.opacity(0.18).ignoresSafeArea()
                    TimeBoxOverCard(clock: box, finishLabel: "Günü kapat") { closeDay() }
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: glance.over)
        .onAppear {
            MorningBox.connect(depo)
            syncBox()
        }
        // The box starts on the first real touch inside Sabah, not when the screen appears: the Mac opens
        // on this tab every morning, so starting on appear would run the clock during the English block.
        .simultaneousGesture(TapGesture().onEnded { startBox() })
        .onChange(of: doneSteps) { _, _ in startBox() }
        .onChange(of: depo.durum.zamanKutusu[today]) { _, _ in syncBox() }
        .onChange(of: dayDone) { _, _ in syncBox() }
    }

    private func startBox() {
        if !dayDone && !store.plan.days.allSatisfy({ $0.items.isEmpty }) { box.touch() }
    }

    /// Adopts what the other device wrote (start, extension) and the day's close as the finish.
    private func syncBox() {
        var s = d.zamanKutusu[today] ?? TimeBoxState()
        if let done = d.morningDone[today] { s.finished = done.t; if s.started == nil { s.started = done.t } }
        box.adopt(s)
        MorningBox.mirror(box.state)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if glance.done { TimeBoxDoneCard(clock: box) }
                header
                MorningStrip(days: store.plan.days, covered: store.covered(d), focus: Set(days.map(\.date)), chosen: $chosenDay)
                if store.plan.days.allSatisfy({ $0.items.isEmpty }) {
                    emptyState
                } else if finished || (dayDone && chosenDay == nil && step == .contact && doneSteps.count == 4) {
                    MorningDoneCard(days: days, books: books, store: store, durum: d) { finished = false; step = .review }
                } else {
                    stepBar
                    Group {
                        switch step {
                        case .contact: MorningContact(books: books, wide: wide)
                        case .marks: MorningMarks(books: books, wide: wide)
                        case .recall: MorningRecall(books: books, today: today)
                        case .review: MorningReview(queue: queue, today: today)
                        }
                    }
                    .id(step.rawValue + (chosenDay ?? ""))
                    footer
                }
            }
            .padding(.horizontal, wide ? 32 : 18).padding(.vertical, wide ? 24 : 12)
            .frame(maxWidth: wide ? 1180 : .infinity, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Tema.arka)
        .task { await store.prepare() }
        .onChange(of: store.plan.built) { _, _ in
            if !dayDone && !store.plan.days.allSatisfy({ $0.items.isEmpty }) { box.touch() }
        }
        .onAppear { queue = store.reviewQueue(d, books: books) }
        .onChange(of: chosenDay) { _, _ in queue = store.reviewQueue(d, books: books); step = .contact }
        .onChange(of: store.plan.built) { _, _ in queue = store.reviewQueue(d, books: books) }
    }

    // MARK: parts

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting).font(Tema.serif(wide ? .largeTitle : .title, .semibold)).foregroundStyle(Tema.metin)
                Text(subtitle).font(.subheadline).foregroundStyle(Tema.ikincil)
            }
            Spacer()
            if store.preparing { ProgressView().controlSize(.small) }
            ring
            if let close {
                Button(action: close) { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(Tema.soluk) }
                    .buttonStyle(.plain).accessibilityLabel("Kapat")
            }
        }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "Günaydın" : (h < 18 ? "Sabah odası" : "Günün odası")
    }

    private var subtitle: String {
        guard !days.isEmpty else { return "Voice Reader'da dinlediğin bölümler burada belirir" }
        let names = days.map { $0.date == today ? "bugün" : ($0.date == Tarih.gun(Date().gun(-1)) ? "dün" : $0.weekday) }
        let mins = Int(days.reduce(0) { $0 + $1.minutes }.rounded())
        return "\(MorningView.join(names).capitalizedFirst) dinlediklerin · \(books.count) kitap · \(mins) dk"
    }

    static func join(_ l: [String]) -> String {
        l.count < 2 ? (l.first ?? "") : l.dropLast().joined(separator: ", ") + " ve " + l[l.count - 1]
    }

    private var ring: some View {
        let p = Double(doneSteps.count) / 4
        return ZStack {
            Circle().stroke(Tema.cizgi, lineWidth: 5)
            Circle().trim(from: 0, to: dayDone ? 1 : p).stroke(Tema.basari, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: dayDone ? "checkmark" : "sunrise").font(.system(size: 14, weight: .semibold))
                .foregroundStyle(dayDone ? Tema.basari : Tema.ikincil)
        }
        .frame(width: 40, height: 40)
        .accessibilityLabel(dayDone ? "Gün tamamlandı" : "\(doneSteps.count) / 4 adım")
    }

    private var stepBar: some View {
        ScrollView(.horizontal) { stepButtons }.scrollIndicators(.hidden)
    }

    private var stepButtons: some View {
        HStack(spacing: 8) {
            ForEach(MorningStep.allCases) { s in
                Button { withAnimation(.snappy) { step = s } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: doneSteps.contains(s.rawValue) ? "checkmark.circle.fill" : s.symbol)
                            .foregroundStyle(doneSteps.contains(s.rawValue) ? Tema.basari : (step == s ? Tema.vurgu : Tema.ikincil))
                        Text(s.title).font(.subheadline.weight(step == s ? .semibold : .regular))
                            .foregroundStyle(step == s ? Tema.metin : Tema.ikincil)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().fill(step == s ? Tema.yuzey : .clear))
                    .overlay(Capsule().stroke(step == s ? Tema.cizgi : .clear))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var footer: some View {
        let last = step == MorningStep.allCases.last
        return HStack {
            Spacer()
            Button {
                if !doneSteps.contains(step.rawValue) {
                    depo.ekle(Olay(tur: .morningStep, hedef: today, rol: step.rawValue))
                }
                if last || MorningStep.allCases.allSatisfy({ doneSteps.contains($0.rawValue) || $0 == step }) {
                    closeDay()
                } else if let i = MorningStep.allCases.firstIndex(of: step) {
                    withAnimation(.snappy) { step = MorningStep.allCases[i + 1] }
                }
            } label: {
                Label(last ? "Günü tamamla" : "Tamam, sıradaki", systemImage: last ? "checkmark.seal" : "arrow.right")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(AnaDugme(renk: last ? Tema.basari : Tema.vurgu))
            .frame(maxWidth: 320)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    private func closeDay() {
        let covered = days.map(\.date).joined(separator: ",")
        let answered = d.morningCards.values.filter { $0.son.gunBasi == Date().gunBasi }.count
        depo.ekle(Olay(tur: .morningDone, hedef: today, puan: Double(answered), metin: covered,
                       sure: days.reduce(0) { $0 + $1.minutes }))
        box.finish()
        withAnimation(.spring) { finished = true }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Henüz dinleme kaydı yok").font(.headline).foregroundStyle(Tema.metin)
            Text("Voice Reader'da bir Bir Yöne kitabı dinlediğinde, o günün bölümleri burada kavram haritası ve tekrar kartlarıyla açılır. Mac, telefon bağlıyken kaydı kendisi alır.")
                .font(.subheadline).foregroundStyle(Tema.ikincil)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Tema.yuzey))
    }
}

// MARK: - The day strip: 14 days, stacked by branch, ✓ studied · ○ heard but not studied

struct MorningStrip: View {
    var days: [MorningDay]
    var covered: Set<String>
    var focus: Set<String>
    @Binding var chosen: String?

    var body: some View {
        let top = max(days.map(\.minutes).max() ?? 0, 30)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(days) { day in
                    Button { chosen = (chosen == day.date || day.items.isEmpty) ? nil : day.date } label: {
                        VStack(spacing: 4) {
                            bar(day, top: top)
                            Text(MorningStrip.short(day.weekday)).font(.system(size: 10, weight: focus.contains(day.date) ? .bold : .regular))
                                .lineLimit(1).fixedSize()
                                .foregroundStyle(focus.contains(day.date) ? Tema.metin : Tema.soluk)
                            marker(day)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 8).fill(focus.contains(day.date) ? Tema.vurgu.opacity(0.08) : .clear))
                    }
                    .buttonStyle(.plain)
                    .help(help(day))
                    .accessibilityLabel(help(day))
                }
            }
            HStack(spacing: 14) {
                ForEach(MorningBranch.order.dropLast(), id: \.self) { b in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(MorningBranch.color(b)).frame(width: 9, height: 9)
                        Text(b).font(.caption2).foregroundStyle(Tema.ikincil)
                    }
                }
                Spacer()
                if chosen != nil {
                    Button("Bütün açık günler") { chosen = nil }.font(.caption).buttonStyle(.plain).foregroundStyle(Tema.vurgu)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Tema.yuzey))
    }

    static func short(_ w: String) -> String {
        ["Pazartesi": "Pzt", "Salı": "Sal", "Çarşamba": "Çar", "Perşembe": "Per", "Cuma": "Cum", "Cumartesi": "Cmt", "Pazar": "Paz"][w] ?? String(w.prefix(3))
    }

    private func bar(_ day: MorningDay, top: Double) -> some View {
        let h: CGFloat = 64
        return VStack(spacing: 1) {
            Spacer(minLength: 0)
            ForEach(MorningBranch.order.reversed(), id: \.self) { b in
                let m = day.items.filter { $0.branch == b }.reduce(0) { $0 + $1.minutes }
                if m > 0 {
                    RoundedRectangle(cornerRadius: 2).fill(MorningBranch.color(b))
                        .frame(height: max(3, h * CGFloat(m / top)))
                }
            }
            if day.items.isEmpty {
                RoundedRectangle(cornerRadius: 2).fill(Tema.cizgi).frame(height: 3)
            }
        }
        .frame(height: h)
        .frame(maxWidth: 26)
    }

    @ViewBuilder private func marker(_ day: MorningDay) -> some View {
        if covered.contains(day.date) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(Tema.basari)
        } else if !day.items.isEmpty {
            Image(systemName: "circle").font(.system(size: 11)).foregroundStyle(Tema.soluk)
        } else {
            Color.clear.frame(width: 11, height: 11)
        }
    }

    private func help(_ day: MorningDay) -> String {
        if day.items.isEmpty { return "\(day.weekday) \(day.date.suffix(5)): dinleme yok" }
        let parts = day.items.map { "\($0.branch) \(Int($0.minutes.rounded())) dk" }.joined(separator: ", ")
        return "\(day.weekday) \(day.date.suffix(5)): \(parts)" + (covered.contains(day.date) ? " · çalışıldı" : "")
    }
}

// MARK: - Step 1 · contact

struct MorningContact: View {
    var books: [MorningBook]
    var wide: Bool
    @State private var open: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(books) { b in
                MorningCardBox {
                    MorningBookHeader(book: b)
                    if wide {
                        HStack(alignment: .top, spacing: 20) {
                            chapterList(b).frame(maxWidth: .infinity, alignment: .leading)
                            if !b.nodes.isEmpty { MorningConceptMap(nodes: b.nodes, edges: b.edges, color: MorningBranch.color(b.branch)).frame(width: 420) }
                        }
                    } else {
                        if !b.nodes.isEmpty { MorningConceptMap(nodes: b.nodes, edges: b.edges, color: MorningBranch.color(b.branch)) }
                        chapterList(b)
                    }
                }
            }
        }
    }

    private func chapterList(_ b: MorningBook) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let t = b.chapters.first?.thesis {
                Text(t).font(Tema.serif(.callout)).italic().foregroundStyle(Tema.ikincil)
            }
            ForEach(open.contains(b.id) ? b.chapters : Array(b.chapters.prefix(6)), id: \.ch) { c in
                DisclosureGroup {
                    Text(c.summary ?? "").font(.callout).foregroundStyle(Tema.metin).fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.title).font(.callout.weight(.semibold)).foregroundStyle(Tema.metin)
                        if let k = c.key { Text(k).font(.caption).foregroundStyle(Tema.ikincil) }
                    }
                }
                .tint(Tema.ikincil)
            }
            if b.chapters.count > 6 {
                Button(open.contains(b.id) ? "Daha az" : "Bütün bölümler (\(b.chapters.count))") {
                    withAnimation(.snappy) { if open.contains(b.id) { open.remove(b.id) } else { open.insert(b.id) } }
                }
                .font(.caption).buttonStyle(.plain).foregroundStyle(Tema.vurgu)
            }
        }
    }
}

struct MorningBookHeader: View {
    var book: MorningBook
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(MorningBranch.color(book.branch)).frame(width: 8, height: 8)
            Text(book.title).font(Tema.serif(.title3, .semibold)).foregroundStyle(Tema.metin).lineLimit(2)
            Spacer()
            Text("\(Int(book.minutes.rounded())) dk · \(book.chapters.count) bölüm" + (book.estimated ? " · tahmini" : ""))
                .font(.caption).foregroundStyle(Tema.ikincil)
        }
    }
}

/// The book's concept map for these chapters: nodes on an ellipse, relations as lines; tap a node for its note.
struct MorningConceptMap: View {
    var nodes: [MorningChapter.Node]
    var edges: [MorningChapter.Edge]
    var color: Color
    @State private var picked: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { g in
                let pos = positions(in: g.size)
                ZStack {
                    Canvas { ctx, _ in
                        for e in edges {
                            guard let a = pos[e.a], let b = pos[e.b] else { continue }
                            var p = Path(); p.move(to: a); p.addLine(to: b)
                            let lit = picked == nil || picked == e.a || picked == e.b
                            ctx.stroke(p, with: .color(color.opacity(lit ? 0.55 : 0.12)), lineWidth: lit ? 1.6 : 1)
                        }
                    }
                    ForEach(nodes, id: \.id) { n in
                        Text(n.label).font(.system(size: 11, weight: picked == n.id ? .bold : .medium))
                            .multilineTextAlignment(.center).lineLimit(2)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .frame(maxWidth: 140)
                            .background(Capsule().fill(picked == n.id ? color.opacity(0.25) : Tema.yuzey2))
                            .overlay(Capsule().stroke(color.opacity(0.4)))
                            .foregroundStyle(Tema.metin)
                            .position(pos[n.id] ?? .zero)
                            .onTapGesture { withAnimation(.snappy) { picked = picked == n.id ? nil : n.id } }
                            .accessibilityAddTraits(.isButton)
                    }
                }
            }
            .frame(height: 290)
            if let p = picked, let n = nodes.first(where: { $0.id == p }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(n.label).font(.caption.weight(.semibold))
                    if let note = n.note { Text(note).font(.caption).foregroundStyle(Tema.ikincil) }
                    ForEach(edges.filter { $0.a == p || $0.b == p }, id: \.self) { e in
                        Text("→ \(label(e.a == p ? e.b : e.a)): \(e.label)").font(.caption).foregroundStyle(Tema.ikincil)
                    }
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Tema.yuzey2))
            } else if !edges.isEmpty {
                Text("Bir kavrama dokun: notu ve bağları açılır.").font(.caption2).foregroundStyle(Tema.soluk)
            }
        }
    }

    private func label(_ id: String) -> String { nodes.first { $0.id == id }?.label ?? id }

    /// Two columns facing each other: the relations run across the middle, the labels never collide.
    private func positions(in s: CGSize) -> [String: CGPoint] {
        let left = Int((Double(nodes.count) / 2).rounded(.up))
        let inset = min(78, s.width / 4)
        var out: [String: CGPoint] = [:]
        for (i, node) in nodes.enumerated() {
            let col = i < left ? 0 : 1
            let row = col == 0 ? i : i - left
            let rows = col == 0 ? left : nodes.count - left
            let y = s.height * (CGFloat(row) + 0.5) / CGFloat(max(rows, 1))
            out[node.id] = CGPoint(x: col == 0 ? inset : s.width - inset, y: y)
        }
        return out
    }
}

// MARK: - Step 2 · marks

struct MorningMarks: View {
    var books: [MorningBook]
    var wide: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(books) { b in
                MorningCardBox {
                    MorningBookHeader(book: b)
                    section("İşaretlediklerin", symbol: "highlighter", tint: Tema.altin,
                            rows: b.marks.prefix(6).map { ($0.quote, $0.note) }, empty: "Bu bölümlerde işaretin yok.")
                    section("Can alıcı cümleler", symbol: "quote.opening", tint: MorningBranch.color(b.branch),
                            rows: b.keys.map { ($0.quote, $0.why) }, empty: nil)
                    section("Kaçırdıkların", symbol: "eye", tint: Tema.uyari,
                            rows: b.missed.map { ($0.quote, $0.why) }, empty: nil)
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, symbol: String, tint: Color, rows: [(String, String?)], empty: String?) -> some View {
        if !rows.isEmpty || empty != nil {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: symbol).font(.caption.weight(.semibold)).foregroundStyle(tint)
                if rows.isEmpty, let empty { Text(empty).font(.caption).foregroundStyle(Tema.soluk) }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 1).fill(tint.opacity(0.6)).frame(width: 3)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(r.0).font(Tema.serif(.callout)).foregroundStyle(Tema.metin).fixedSize(horizontal: false, vertical: true)
                            if let w = r.1, !w.isEmpty { Text(w).font(.caption).foregroundStyle(Tema.ikincil) }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Step 3 · close, recall, write (Mac) / say (iPhone)

struct MorningRecall: View {
    @EnvironmentObject var depo: Depo
    var books: [MorningBook]
    var today: String

    @State private var texts: [String: String] = [:]
    @State private var revealed: Set<String> = []
    #if os(iOS)
    @StateObject private var recorder = SesKayit()
    @State private var recordingFor: String?
    @State private var saved: Set<String> = []
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Metni kapat. Her kitaptan aklında kalanı kendi cümlelerinle kur: ana iddia, ona karşı duran, aradaki bağ. Sonra karşılaştır.")
                .font(.callout).foregroundStyle(Tema.ikincil)
            ForEach(books) { b in
                MorningCardBox {
                    MorningBookHeader(book: b)
                    Text(b.chapters.map(\.title).prefix(4).joined(separator: " · ") + (b.chapters.count > 4 ? " …" : ""))
                        .font(.caption).foregroundStyle(Tema.soluk).lineLimit(2)
                    #if os(iOS)
                    voice(b)
                    #endif
                    TextEditor(text: Binding(get: { texts[b.id] ?? "" }, set: { texts[b.id] = $0 }))
                        .font(Tema.serif(.body))
                        .frame(minHeight: 110)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Tema.yuzey2))
                        .overlay(alignment: .topLeading) {
                            if (texts[b.id] ?? "").isEmpty {
                                Text("Hatırladığın üç cümle…").font(Tema.serif(.body)).foregroundStyle(Tema.soluk)
                                    .padding(14).allowsHitTesting(false)
                            }
                        }
                    if revealed.contains(b.id) {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Kitabın kendi cümleleri", systemImage: "eye").font(.caption.weight(.semibold)).foregroundStyle(MorningBranch.color(b.branch))
                            ForEach(b.keys, id: \.self) { k in
                                Text("• " + k.quote).font(Tema.serif(.callout)).foregroundStyle(Tema.metin).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .transition(.opacity)
                    } else {
                        Button {
                            withAnimation(.snappy) { _ = revealed.insert(b.id) }
                            let t = (texts[b.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                            depo.ekle(Olay(tur: .kendiCumle, hedef: "sabah:" + b.id, deger: false, metin: t.isEmpty ? nil : t, rol: "sabah"))
                        } label: { Label("Karşılaştır", systemImage: "rectangle.on.rectangle") }
                            .buttonStyle(IkinciDugme())
                            .frame(maxWidth: 260)
                    }
                }
            }
        }
    }

    #if os(iOS)
    @ViewBuilder private func voice(_ b: MorningBook) -> some View {
        HStack(spacing: 12) {
            if recordingFor == b.id, recorder.hal == .kayit {
                Button {
                    recorder.durdur()
                    if let u = recorder.dosya {
                        depo.ekle(Olay(tur: .sesNot, hedef: "sabah:" + b.id, deger: false, metin: u.lastPathComponent, sure: recorder.sure, rol: "sabah"))
                        depo.esitle(gecikme: 1)
                        saved.insert(b.id)
                    }
                    recordingFor = nil
                } label: { Label("Bitir · \(Int(recorder.sure)) sn", systemImage: "stop.circle.fill") }
                    .buttonStyle(IkinciDugme(renk: Tema.uyari))
            } else {
                Button {
                    recorder.sifirla()
                    recordingFor = b.id
                    Task { await recorder.baslat(klasor: depo.sesKlasoru) }
                } label: { Label(saved.contains(b.id) ? "Yeniden anlat" : "Sesle anlat", systemImage: "mic.fill") }
                    .buttonStyle(IkinciDugme())
                    .disabled(recordingFor != nil)
            }
            if saved.contains(b.id) { Image(systemName: "checkmark.circle.fill").foregroundStyle(Tema.basari) }
        }
    }
    #endif
}

// MARK: - Step 4 · review (active recall, FSRS)

struct MorningReview: View {
    @EnvironmentObject var depo: Depo
    var queue: [MorningCard]
    var today: String
    var openBook: ((MorningCard) -> Void)? = nil
    var finish: ((Int) -> Void)? = nil

    @State private var index = 0
    @State private var shown = false
    @State private var picked: String?
    @State private var right = 0

    var body: some View {
        if queue.isEmpty {
            MorningCardBox {
                Text("Bugün tekrar edilecek kart yok.").font(.headline).foregroundStyle(Tema.metin)
                Text("Kartlar dinlediğin bölümlerin can alıcı cümlelerinden, kavram bağlarından ve kaçırdıklarından kurulur.")
                    .font(.callout).foregroundStyle(Tema.ikincil)
            }
        } else if index >= queue.count {
            MorningCardBox {
                Label("\(queue.count) karttan \(right) tanesini hatırladın", systemImage: "checkmark.seal.fill")
                    .font(.headline).foregroundStyle(Tema.basari)
                Text("Unuttukların yarın yeniden gelir, hatırladıkların daha uzun aralıkla.").font(.callout).foregroundStyle(Tema.ikincil)
            }
            .onAppear { finish?(right) }
        } else {
            card(queue[index])
        }
    }

    private func card(_ c: MorningCard) -> some View {
        MorningCardBox {
            HStack {
                Text(c.lane == "cross" ? "Önceki okumadan · " + kindName(c.kind) : kindName(c.kind))
                    .font(.caption.weight(.semibold)).foregroundStyle(c.lane == "cross" ? Tema.altin : Tema.vurgu)
                Spacer()
                Text("\(index + 1) / \(queue.count)").font(.caption).foregroundStyle(Tema.soluk).monospacedDigit()
            }
            ProgressView(value: Double(index), total: Double(queue.count)).tint(Tema.vurgu)
            Text(c.prompt).font(Tema.serif(.title3)).foregroundStyle(Tema.metin).fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 6)
            if !c.options.isEmpty && !shown {
                VStack(spacing: 8) {
                    ForEach(c.options, id: \.self) { o in
                        Button { pick(o, c) } label: {
                            Text(o).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14).padding(.vertical, 11)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Tema.yuzey2))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button("Seçeneksiz hatırladım, göster") { withAnimation(.snappy) { shown = true } }
                    .font(.caption).buttonStyle(.plain).foregroundStyle(Tema.ikincil)
                    .keyboardShortcut(.space, modifiers: [])
            } else if !shown {
                Button { withAnimation(.snappy) { shown = true } } label: { Label("Zihninde cevapla, sonra göster", systemImage: "eye") }
                    .buttonStyle(IkinciDugme()).frame(maxWidth: 320)
                    .keyboardShortcut(.space, modifiers: [])
            }
            if shown {
                VStack(alignment: .leading, spacing: 6) {
                    if let p = picked {
                        Label(p == c.answer ? "Doğru" : "Doğrusu: \(c.answer)", systemImage: p == c.answer ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.callout.weight(.semibold)).foregroundStyle(p == c.answer ? Tema.basari : Tema.uyari)
                    } else {
                        Text(c.answer).font(.callout.weight(.semibold)).foregroundStyle(Tema.basari)
                    }
                    Text(c.full).font(Tema.serif(.callout)).foregroundStyle(Tema.metin).fixedSize(horizontal: false, vertical: true)
                    if let w = c.why { Text(w).font(.caption).foregroundStyle(Tema.ikincil) }
                    if let openBook {
                        Button { openBook(c) } label: { Label("Kitapta aç", systemImage: "book") }
                            .font(.caption.weight(.semibold)).buttonStyle(.plain).foregroundStyle(Tema.vurgu)
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Tema.yuzey2))
                grades(c)
            }
        }
    }

    private func grades(_ c: MorningCard) -> some View {
        HStack(spacing: 8) {
            gradeButton("Unuttum", .unuttum, "1", Tema.uyari, c)
            gradeButton("Zor", .zor, "2", Tema.altin, c)
            gradeButton("İyi", .iyi, "3", Tema.vurgu, c)
            gradeButton("Kolay", .kolay, "4", Tema.basari, c)
        }
    }

    private func gradeButton(_ t: String, _ n: Not, _ key: Character, _ color: Color, _ c: MorningCard) -> some View {
        Button { grade(n, c) } label: {
            VStack(spacing: 2) {
                Text(t).font(.callout.weight(.semibold))
                #if os(macOS)
                Text(String(key)).font(.caption2).foregroundStyle(Tema.soluk)
                #endif
            }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.14)))
            .foregroundStyle(color)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(key), modifiers: [])
    }

    private func pick(_ o: String, _ c: MorningCard) {
        picked = o
        withAnimation(.snappy) { shown = true }
    }

    private func grade(_ n: Not, _ c: MorningCard) {
        // metin "book#ch": veri/feedback.py lists the chapters that did not stay (Unuttum · Zor) for Claude
        depo.ekle(Olay(tur: .morningCard, hedef: c.id, not: n.rawValue, metin: "\(c.book)#\(c.ch)", rol: c.kind))
        if n != .unuttum { right += 1 }
        withAnimation(.snappy) {
            index += 1
            shown = false
            picked = nil
        }
    }

    private func kindName(_ k: String) -> String {
        switch k {
        case "quiz": "Bölümden soru"
        case "cross": "Çapraz bağ"
        case "mark": "İşaretin"
        case "cloze": "Boşluğu hatırla"
        case "who": "Kim söyledi?"
        case "edge": "Kavramlar arası bağ"
        default: "Kaçırdığın cümle"
        }
    }
}

// MARK: - The day is done

struct MorningDoneCard: View {
    var days: [MorningDay]
    var books: [MorningBook]
    var store: MorningStore
    var durum: Durum
    var again: () -> Void

    var body: some View {
        let today = Date().gunBasi
        let answered = durum.morningCards.values.filter { $0.son.gunBasi == today }
        let kept = answered.filter { $0.hata == 0 || $0.tekrar > $0.hata }.count
        MorningCardBox {
            VStack(spacing: 14) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 54)).foregroundStyle(Tema.basari)
                    .symbolEffect(.bounce, value: answered.count)
                Text("Günü tamamladın").font(Tema.serif(.largeTitle, .semibold)).foregroundStyle(Tema.metin)
                Text(days.map(\.weekday).joined(separator: " · ") + " dinlediklerin artık senin cümlelerinde de duruyor.")
                    .font(.callout).foregroundStyle(Tema.ikincil).multilineTextAlignment(.center)
                HStack(spacing: 0) {
                    stat("\(Int(days.reduce(0) { $0 + $1.minutes }.rounded())) dk", "dinleme")
                    stat("\(books.reduce(0) { $0 + $1.chapters.count })", "bölüme temas")
                    stat("\(kept)/\(answered.count)", "kart hatırlandı")
                    if let n = store.nextReview(durum) { stat(Tarih.goreli(n), "sıradaki tekrar") }
                }
                .padding(.vertical, 8)
                ForEach(books) { b in
                    HStack(spacing: 8) {
                        Circle().fill(MorningBranch.color(b.branch)).frame(width: 8, height: 8)
                        Text(b.title).font(.caption).foregroundStyle(Tema.metin).lineLimit(1)
                        Spacer()
                        Image(systemName: "checkmark").font(.caption).foregroundStyle(Tema.basari)
                    }
                }
                Button("Kartlara bir daha bak", action: again).font(.caption).buttonStyle(.plain).foregroundStyle(Tema.vurgu)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func stat(_ v: String, _ t: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.title3.weight(.semibold)).foregroundStyle(Tema.metin).monospacedDigit()
            Text(t).font(.caption2).foregroundStyle(Tema.ikincil)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Small pieces

struct MorningCardBox<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(Tema.yuzey))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Tema.cizgi))
    }
}

/// The card on the Today screen (iPhone, and the Mac's Bugün): what the morning is about, one tap away.
struct MorningEntryCard: View {
    @EnvironmentObject var depo: Depo
    @ObservedObject private var store = MorningStore.shared
    var open: () -> Void

    var body: some View {
        let d = depo.durum
        let days = store.focusDays(d, chosen: nil)
        let books = store.books(for: days)
        let done = d.morningDone[MorningStore.todayKey] != nil
        Button(action: open) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Sabah odası", systemImage: done ? "checkmark.seal.fill" : "sunrise.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(done ? Tema.basari : Tema.altin)
                    Spacer()
                    Text("\(d.morningSteps[MorningStore.todayKey]?.count ?? 0)/4").font(.caption).foregroundStyle(Tema.soluk)
                }
                if days.isEmpty {
                    Text("Voice Reader'da dinlediğin bölümler burada açılır.").font(.callout).foregroundStyle(Tema.ikincil)
                } else {
                    Text(done ? "Bugün tamamlandı" : days.map { $0.weekday }.joined(separator: " · ") + " dinlediklerin")
                        .font(Tema.serif(.title3, .semibold)).foregroundStyle(Tema.metin)
                    HStack(spacing: 6) {
                        ForEach(books.prefix(3)) { b in
                            Text(b.branch).font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(MorningBranch.color(b.branch).opacity(0.15)))
                                .foregroundStyle(MorningBranch.color(b.branch))
                        }
                        Spacer()
                        Text("\(Int(days.reduce(0) { $0 + $1.minutes }.rounded())) dk").font(.caption).foregroundStyle(Tema.ikincil)
                    }
                }
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(Tema.yuzey))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(done ? Tema.basari.opacity(0.4) : Tema.altin.opacity(0.35)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Kür (2026-11-03)

/// The Kür: the morning room's last step on its own, every day, ~4 minutes. Questions come from what you heard today
/// (written with the text), two of your marks, two ties to earlier readings. Every answer can open the book at its
/// chapter. The old Kür (three lines × six levels) lives on only in the Mac's Atölye.
struct DailyQuizView: View {
    @EnvironmentObject var depo: Depo
    @ObservedObject private var store = MorningStore.shared
    var wide = false
    var close: (() -> Void)?

    @State private var queue: [MorningCard] = []
    @State private var built = false
    @State private var place: BookPlace?
    @State private var done = false

    private var today: String { MorningStore.todayKey }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if queue.isEmpty {
                    MorningCardBox {
                        Text(built ? "Bugün sorulacak kart yok." : "Hazırlanıyor…").font(.headline).foregroundStyle(Tema.metin)
                        Text("Kür, Voice Reader'da dinlediğin bölümlerden kurulur: metinle birlikte yazılan sorular, senin işaretlerin ve önceki okumalara bağlar.")
                            .font(.callout).foregroundStyle(Tema.ikincil)
                    }
                } else if done {
                    finished
                } else {
                    MorningReview(queue: queue, today: today,
                                  openBook: { c in place = BookPlace(book: c.book, ch: c.ch) },
                                  finish: { _ in complete() })
                }
            }
            .padding(.horizontal, wide ? 32 : 18).padding(.vertical, wide ? 24 : 12)
            .frame(maxWidth: wide ? 820 : .infinity, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Tema.arka)
        .onAppear { rebuild() }
        .task { await store.prepare(); if queue.isEmpty { rebuild() } }
        .bookPlaceOpener($place)
    }

    private func rebuild() {
        queue = store.quizQueue(depo.durum)
        built = true
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Günün kürü").font(Tema.serif(wide ? .largeTitle : .title, .semibold)).foregroundStyle(Tema.metin)
                Text(DailyQuizView.subtitle(store, queue)).font(.subheadline).foregroundStyle(Tema.ikincil)
            }
            Spacer()
            if store.preparing { ProgressView().controlSize(.small) }
            if let close {
                Button(action: close) { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(Tema.soluk) }
                    .buttonStyle(.plain).accessibilityLabel("Kapat").keyboardShortcut(.cancelAction)
            }
        }
    }

    static func subtitle(_ store: MorningStore, _ queue: [MorningCard]) -> String {
        guard let day = store.quizDay() else { return "Dinlediğin bölümlerden kısa bir quiz" }
        let when = day.date == MorningStore.todayKey ? "Bugün" : (day.date == Tarih.gun(Date().gun(-1)) ? "Dün" : day.weekday)
        let mins = max(1, Int((Double(queue.count) * 25 / 60).rounded()))
        return "\(when) dinlediğin bölümler · \(queue.count) kart · ~\(mins) dk"
    }

    private func complete() {
        if !(depo.durum.morningSteps[today] ?? []).contains(MorningStep.review.rawValue) {
            depo.ekle(Olay(tur: .morningStep, hedef: today, rol: MorningStep.review.rawValue))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation(.spring) { done = true } }
    }

    private var finished: some View {
        MorningCardBox {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 50)).foregroundStyle(Tema.basari)
                Text("Günü tamamladın").font(Tema.serif(.largeTitle, .semibold)).foregroundStyle(Tema.metin)
                Text("Unuttukların yarın yeniden gelir; tutmayan bölümler sıradaki metinde başka bir açıdan kurulur.")
                    .font(.callout).foregroundStyle(Tema.ikincil).multilineTextAlignment(.center)
                if let close { Button("Kapat", action: close).buttonStyle(IkinciDugme()).frame(maxWidth: 240) }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// Bugün's card for the Kür.
struct DailyQuizCard: View {
    @EnvironmentObject var depo: Depo
    @ObservedObject private var store = MorningStore.shared
    var start: () -> Void

    var body: some View {
        let q = store.quizQueue(depo.durum)
        let done = (depo.durum.morningSteps[MorningStore.todayKey] ?? []).contains(MorningStep.review.rawValue)
        Button(action: start) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Kür", systemImage: done ? "checkmark.seal.fill" : "rectangle.stack.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(done ? Tema.basari : Tema.vurgu)
                    Spacer()
                    Text(done ? "bugün yapıldı" : "\(q.count) kart").font(.caption).foregroundStyle(Tema.soluk)
                }
                Text(done && q.isEmpty ? "Bugünün kürü tamam" : "Günün kürü").font(Tema.serif(.title3, .semibold)).foregroundStyle(Tema.metin)
                Text(DailyQuizView.subtitle(store, q)).font(.callout).foregroundStyle(Tema.ikincil)
                Label(done ? "Bir daha bak" : "Kürü başlat", systemImage: "play.fill")
                    .font(.callout.weight(.semibold)).foregroundStyle(Tema.vurgu)
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(Tema.yuzey))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(done ? Tema.basari.opacity(0.4) : Tema.vurgu.opacity(0.3)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - A chapter of a book, opened in the reader

struct BookPlace: Identifiable {
    let book: String
    let ch: Int
    var b = 0
    var id: String { "\(book).\(ch).\(b)" }
}

struct BookPlaceOpener: ViewModifier {
    @EnvironmentObject var depo: Depo
    @Binding var place: BookPlace?
    @State private var konum: KitapKonumu?

    func body(content: Content) -> some View {
        content
            .task(id: place?.id) {
                guard let p = place else { return }
                let lib = LibraryStore.shared
                let raw = await lib.book(p.book, kasa: depo.kasa)
                place = nil
                guard let raw else { depo.bildirim = "Bu kitap kütüphanede yok"; return }
                konum = KitapKonumu(book: lib.withMarks(raw), yer: (p.ch, p.b))
            }
            #if os(iOS)
            .fullScreenCover(item: $konum) { reader($0) }
            #else
            .sheet(item: $konum) { reader($0).frame(minWidth: 900, minHeight: 700) }
            #endif
    }

    private func reader(_ k: KitapKonumu) -> some View {
        ReaderView(book: k.book, mode: .full, jump: k.yer.map { ($0.ch, $0.b) }).environmentObject(depo)
    }
}

extension View {
    func bookPlaceOpener(_ place: Binding<BookPlace?>) -> some View { modifier(BookPlaceOpener(place: place)) }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased(with: Locale(identifier: "tr_TR")) + dropFirst() }
}


// MARK: - Sabah time box (Kurultay decision 2026-11-05)

/// What a screen needs from a time box without rebuilding itself every second: is the block done, is the limit card
/// up. The clock publishes its time once a second; `timeBoxGlance` turns that into a value that changes only when
/// one of the two does.
struct TimeBoxGlance: Equatable {
    var done = false
    var over = false
    @MainActor init(_ clock: TimeBoxClock) { done = clock.phase == .done; over = clock.showOver }
}

extension View {
    func timeBoxGlance(_ clock: TimeBoxClock, _ glance: Binding<TimeBoxGlance>) -> some View {
        func refresh() {
            let g = TimeBoxGlance(clock)
            if g != glance.wrappedValue { glance.wrappedValue = g }
        }
        return onReceive(clock.objectWillChange.receive(on: DispatchQueue.main)) { _ in refresh() }
            .onAppear { refresh() }
    }
}

/// One 60-minute "Mütalaa" clock for the day, shared by the Mac and the iPhone through the event log
/// (zamanBasla · zamanUzat; the finish is the day's morningDone). On the Mac it is also mirrored to
/// vault/_bus/plan/durum/<day>.json and the PDM bus, where Tekne draws it on the day strip.
@MainActor
enum MorningBox {
    static let plan: TimeBoxPlan = {
        #if os(macOS)
        return TimeBoxPlan.load(vault: vault)
        #else
        return .standard
        #endif
    }()
    static let clock = TimeBoxClock(block: plan.block("review") ?? TimeBoxPlan.standard.blocks[1], plan: plan)
    private static weak var depo: Depo?

    static var vault: URL? {
        #if os(macOS)
        let u = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/iCloud~md~obsidian/Documents/Personel Data Management")
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
        #else
        return nil
        #endif
    }

    static func connect(_ d: Depo) {
        guard depo == nil else { return }
        depo = d
        clock.onChange = { s, type in
            let day = MorningStore.todayKey
            switch type {
            case "timebox.started": depo?.ekle(Olay(tur: .zamanBasla, hedef: day))
            case "timebox.extended": depo?.ekle(Olay(tur: .zamanUzat, hedef: day, sure: Double(s.extendedMinutes)))
            default: break   // finish = morningDone, already in the log
            }
            mirror(s)
            if let v = vault {
                TimeBoxBus.emit(vault: v, app: "teoria", device: Cihaz.ad, type: type, block: clock.block, state: s)
            }
        }
    }

    /// Mac only: keep the shared day file in step (also with what the iPhone did).
    static func mirror(_ s: TimeBoxState) {
        guard let v = vault, s.started != nil else { return }
        TimeBoxDay.write(vault: v, id: clock.block.id, s)
    }
}
