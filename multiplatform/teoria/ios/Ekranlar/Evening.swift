// Akşam tekrarı (2026-11-07): what you heard today, studied before bed, branch by branch.
//
// Not a general study: only the places heard that day. For each branch (Felsefe, Bilimler, Mühendislik, Diğer), in
// the order of the morning room, first a short showing of exactly the chapters heard — their point, two sentences that
// carry them, one that is easy to miss, and your own marks — then a short test from the same chapters. Then the next
// branch. Closing the evening tells Wise Path not to remind you again that day.
//
// Where it comes from:
//   phone  Wise Path writes the last three days of listening into the shared App Group (PDMBus › PDMListening):
//          per book the seconds, the heard spans in characters and the marks. Fresh the same evening, no Mac needed.
//   Mac    veri/evening.py (run with every Sabah plan) writes library/evening.json: for each book being read, where
//          its chapters begin in Wise Path's text (bounds), the chapters around the reading place with their
//          content, and the cards written for them (the same cards as Sabah, so the FSRS state is shared).
// The heard spans go through the bounds to chapters; chapters and cards come from the pool, else from Sabah's plan.
// A book the Mac has not prepared yet still shows its minutes and marks, and its marks become recall cards.
import CryptoKit
import SwiftUI
#if canImport(PDMBus)
import PDMBus
#endif

// MARK: - The Mac's pool

struct EveningPool: Codable {
    struct Doc: Codable, Hashable {
        var book: String?
        var title: String
        var branch: String
        var length: Int
        var bounds: [[Int]]       // [character offset, chapter index], by offset
    }
    struct Heard: Codable, Hashable {
        var seconds: Double
        var words: Int
        var ranges: [[Int]]
    }
    var v: Int = 1
    var built: String = ""
    var today: String = ""
    var docs: [String: Doc] = [:]
    var chapters: [String: MorningChapter] = [:]   // "book#ch"
    var cards: [MorningCard] = []
    var heard: [String: [String: Heard]] = [:]     // day → document → what the Mac last saw from the phone
}

// MARK: - The phone's listening (from Wise Path)

struct EveningListening: Equatable {
    struct Mark: Equatable { var at: Int; var length: Int; var text: String; var note: String?; var created: Date }
    struct Doc: Equatable { var title: String; var branch: String; var length: Int; var teoria: String?; var marks: [Mark] }
    var days: [String: [String: EveningPool.Heard]] = [:]
    var docs: [String: Doc] = [:]

    #if canImport(PDMBus)
    init(_ all: [PDMListening]) {
        for l in all.reversed() {                    // newest last, so it wins
            for (day, m) in l.days {
                for (id, h) in m {
                    days[day, default: [:]][id] = .init(seconds: h.seconds, words: h.words, ranges: h.ranges)
                }
            }
            for (id, d) in l.docs {
                docs[id] = .init(title: d.title, branch: d.branch, length: d.length, teoria: d.teoria,
                                 marks: d.marks.map { .init(at: $0.at, length: $0.length, text: $0.text, note: $0.note, created: $0.created) })
            }
        }
    }
    #endif

    init() {}
}

// MARK: - The session

struct EveningMark: Hashable {
    var quote: String
    var note: String?
    var ch: Int?
}

struct EveningBook: Identifiable, Hashable {
    var id: String               // Teoria's book id; a book the Mac does not know yet keeps the listening document's id
    var title: String
    var branch: String
    var minutes: Double
    var chapters: [MorningChapter]
    var waiting: Int             // chapters heard whose content is not prepared yet
    var marks: [EveningMark]
    var known: Bool              // the Mac knows where its chapters begin
}

struct EveningBranchPlan: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var minutes: Double
    var books: [EveningBook]
    var chapterKeys: [String] { books.flatMap { b in b.chapters.map { "\(b.id)#\($0.ch)" } } }
}

struct EveningSession: Hashable {
    var day: String
    var branches: [EveningBranchPlan]
    var minutes: Double { branches.reduce(0) { $0 + $1.minutes } }
    var chapterCount: Int { branches.reduce(0) { $0 + $1.books.reduce(0) { $0 + $1.chapters.count } } }
}

// MARK: - The store

@MainActor
final class EveningStore: ObservableObject {
    static let shared = EveningStore()
    @Published private(set) var pool = EveningPool()
    @Published private(set) var listening = EveningListening()
    @Published private(set) var preparing = false
    @Published private(set) var revision = 0

    /// A book counts from 20 seconds of listening; the session asks for at least a minute in all.
    static let minimumSeconds = 20.0

    private var local: URL { Paylasim.kapsayici.appendingPathComponent("bookshelf/evening.json") }

    private var candidates: [URL] {
        var c = [local]
        #if os(macOS)
        c.insert(Kasa.macYolu.appendingPathComponent("library/evening.json"), at: 0)
        #endif
        return c
    }

    init() {
        Task { await reload(); await refreshListening() }
    }

    /// Reads the pool off the main actor (about 0.3 MB).
    func reload() async {
        let files = candidates
        let fresh = await Task.detached { () -> EveningPool? in
            for u in files {
                if let v = try? Data(contentsOf: u), let p = try? JSONDecoder().decode(EveningPool.self, from: v) { return p }
            }
            return nil
        }.value
        if let fresh, fresh.built != pool.built {
            pool = fresh
            revision += 1
        }
    }

    /// iPhone: what Wise Path wrote into the App Group (the listening of the last three days).
    func refreshListening() async {
        #if canImport(PDMBus)
        let fresh = await Task.detached { EveningListening(PDMBus.allListening()) }.value
        if fresh != listening {
            listening = fresh
            revision += 1
        }
        #endif
    }

    /// Everything fresh: the phone's listening, the pool, and on the Mac the pool rebuilt (with the phone's log when it
    /// is connected) unless it was built in the last ten minutes.
    func refresh(force: Bool = false) async {
        await refreshListening()
        await reload()
        #if os(macOS)
        guard !preparing, ProcessInfo.processInfo.environment["TEORIA_VAULT"] == nil else { return }   // test vault: leave the real one alone
        if !force, let b = Tarih.coz(pool.built), Date().timeIntervalSince(b) < 600 { return }
        preparing = true
        defer { preparing = false }
        let teoria = Kasa.macYolu
        await Task.detached(priority: .userInitiated) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            p.arguments = [teoria.appendingPathComponent("veri/evening.py").path, "--telefon"]
            p.currentDirectoryURL = teoria.appendingPathComponent("veri")
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
        }.value
        await reload()
        #endif
    }

    // MARK: what was heard

    /// One day's listening per document: the phone's (fresh) joined with what the Mac saw.
    func heard(_ day: String) -> [String: EveningPool.Heard] {
        var out = pool.heard[day] ?? [:]
        for (id, h) in listening.days[day] ?? [:] {
            guard var o = out[id] else { out[id] = h; continue }
            o.seconds = max(o.seconds, h.seconds)
            o.words = max(o.words, h.words)
            o.ranges = Self.union(o.ranges + h.ranges)
            out[id] = o
        }
        return out
    }

    func minutes(_ day: String) -> Double {
        heard(day).values.filter { $0.seconds >= Self.minimumSeconds }.reduce(0) { $0 + $1.seconds } / 60
    }

    /// The day the evening is about: today when anything was heard today, else yesterday while it is not closed
    /// (opened after midnight, the evening before is still the one to study).
    func day(_ d: Durum, now: Date = Date()) -> String {
        let today = Tarih.gun(now), yesterday = Tarih.gun(now.gun(-1))
        if minutes(today) >= 1 { return today }
        if d.eveningDone[yesterday] == nil, minutes(yesterday) >= 1 { return yesterday }
        return today
    }

    func session(_ d: Durum, now: Date = Date()) -> EveningSession {
        let day = day(d, now: now)
        let plan = MorningStore.shared.plan
        var books: [String: EveningBook] = [:]
        var order: [String] = []
        for (id, h) in heard(day) where h.seconds >= Self.minimumSeconds {
            let doc = pool.docs[id]
            let phone = listening.docs[id]
            let bounds = doc?.bounds ?? []
            let key = doc?.book ?? phone?.teoria ?? id
            let heardChapters = Self.chapters(h.ranges, bounds: bounds)
            if books[key] == nil {
                order.append(key)
                books[key] = EveningBook(id: key, title: phone?.title ?? doc?.title ?? "Kitap",
                                         branch: doc?.branch ?? phone?.branch ?? "Diğer",
                                         minutes: 0, chapters: [], waiting: 0, marks: [], known: !bounds.isEmpty)
            }
            var b = books[key]!
            b.minutes += h.seconds / 60
            for ch in heardChapters where !b.chapters.contains(where: { $0.ch == ch }) {
                if let c = pool.chapters["\(key)#\(ch)"] ?? plan.chapters["\(key)#\(ch)"] { b.chapters.append(c) } else { b.waiting += 1 }
            }
            // your marks: the ones made that day, and the older ones that stand in what was heard again
            for m in phone?.marks ?? [] where Tarih.gun(m.created) == day || h.ranges.contains(where: { m.at < $0[1] && m.at + m.length > $0[0] }) {
                b.marks.append(EveningMark(quote: m.text, note: m.note, ch: bounds.isEmpty ? nil : Self.chapter(at: m.at, bounds)))
            }
            books[key] = b
        }
        let list = order.compactMap { books[$0] }.map { b -> EveningBook in
            var b = b
            b.chapters.sort { $0.ch < $1.ch }
            // the marks the Mac already knew in these chapters, made that day
            for c in b.chapters { for m in c.marks where m.date?.hasPrefix(day) == true { b.marks.append(.init(quote: m.quote, note: m.note, ch: c.ch)) } }
            var seen = Set<String>()
            b.marks = b.marks.filter { seen.insert(Self.fold($0.quote)).inserted }.sorted { ($0.ch ?? 0) < ($1.ch ?? 0) }
            return b
        }
        var branches: [String: EveningBranchPlan] = [:]
        for b in list { branches[b.branch, default: .init(name: b.branch, minutes: 0, books: [])].books.append(b) }
        for k in branches.keys {
            branches[k]!.minutes = branches[k]!.books.reduce(0) { $0 + $1.minutes }
            branches[k]!.books.sort { $0.minutes > $1.minutes }
        }
        let sorted = branches.values.sorted {
            (MorningBranch.order.firstIndex(of: $0.name) ?? 9, -$0.minutes) < (MorningBranch.order.firstIndex(of: $1.name) ?? 9, -$1.minutes)
        }
        return EveningSession(day: day, branches: sorted)
    }

    /// The test of one branch: at most 6 questions from its chapters (the questions written with the text first, books
    /// taking turns), then up to 3 of your marks there, the day's own first. A card answered today is not asked
    /// again; one seen before comes back only when FSRS says it is due. Marks the Mac has not seen yet become
    /// recall cards with the ids Sabah will give them, so their state carries over.
    func cards(for b: EveningBranchPlan, _ d: Durum, now: Date = Date()) -> [MorningCard] {
        let today = now.gunBasi
        func open(_ c: MorningCard) -> Bool {
            guard let s = d.morningCards[c.id] else { return true }
            return s.son.gunBasi != today && s.vade <= now
        }
        var all: [MorningCard] = []
        var ids = Set<String>()
        for c in pool.cards + MorningStore.shared.plan.cards where ids.insert(c.id).inserted { all.append(c) }
        let focus = Set(b.chapterKeys)
        let here = all.filter { focus.contains("\($0.book)#\($0.ch)") && open($0) }
        let rank = ["quiz": 0, "cross": 1, "cloze": 2, "edge": 3, "who": 4, "recall": 5]
        var perBook: [String: [MorningCard]] = [:]
        for c in here where rank[c.kind] != nil { perBook[c.book, default: []].append(c) }
        for k in perBook.keys {
            perBook[k]!.sort { (rank[$0.kind]!, -($0.weight ?? 2)) < (rank[$1.kind]!, -($1.weight ?? 2)) }
        }
        var main: [MorningCard] = []
        var i = 0
        while main.count < 6, perBook.values.contains(where: { $0.count > i }) {
            for book in b.books.map(\.id) where main.count < 6 { if let l = perBook[book], l.count > i { main.append(l[i]) } }
            i += 1
        }
        // marks: the day's own (already written by the Mac, else made here), then the others in these chapters
        var marks: [MorningCard] = []
        for book in b.books {
            for m in book.marks where m.quote.count >= 40 {
                let id = Self.cardID(book.id, "mark", m.quote)
                let c = all.first { $0.id == id }
                    ?? Self.markCard(id: id, book: book.id, ch: m.ch ?? book.chapters.first?.ch ?? 0, quote: m.quote)
                if open(c) { marks.append(c) }
            }
        }
        for c in here where c.kind == "mark" && !marks.contains(where: { $0.id == c.id }) { marks.append(c) }
        var seen = Set<String>()
        return main + marks.filter { seen.insert($0.id).inserted }.prefix(3)
    }

    // MARK: helpers

    /// The chapters a set of heard spans covers. A chapter counts when at least 400 characters of it were heard
    /// (or 30 % of all that was heard, for a short listening), so crossing into the next one for a sentence does not.
    static func chapters(_ ranges: [[Int]], bounds: [[Int]]) -> [Int] {
        guard !bounds.isEmpty else { return [] }
        var overlap: [Int: Int] = [:]
        for r in union(ranges) {
            for (i, b) in bounds.enumerated() {
                let start = b[0], end = i + 1 < bounds.count ? bounds[i + 1][0] : Int.max
                let o = min(r[1], end) - max(r[0], start)
                if o > 0 { overlap[b[1], default: 0] += o }
            }
        }
        let total = overlap.values.reduce(0, +)
        let floor = min(400, total * 3 / 10)
        return overlap.filter { $0.value >= max(floor, 1) }.keys.sorted()
    }

    /// The chapter at a character offset: the last bound at or before it.
    static func chapter(at pos: Int, _ bounds: [[Int]]) -> Int {
        var ch = bounds.first?[1] ?? 0
        for b in bounds where b[0] <= pos { ch = b[1] }
        return ch
    }

    /// Spans sorted and joined where they overlap or touch.
    static func union(_ ranges: [[Int]]) -> [[Int]] {
        var out: [[Int]] = []
        for r in ranges.filter({ $0.count == 2 && $0[1] > $0[0] }).sorted(by: { $0[0] < $1[0] }) {
            if let last = out.last, r[0] <= last[1] { out[out.count - 1][1] = max(last[1], r[1]) } else { out.append(r) }
        }
        return out
    }

    /// Sabah's card id: "m:" + the first 12 hex digits of SHA-1 over the parts joined with "|" (veri/sabah.py › sid).
    static func cardID(_ parts: String...) -> String {
        let h = Insecure.SHA1.hash(data: Data(parts.joined(separator: "|").utf8))
        return "m:" + h.map { String(format: "%02x", $0) }.joined().prefix(12)
    }

    /// A mark recalled from its opening words: the card Sabah writes for a mark without a concept to hide.
    static func markCard(id: String, book: String, ch: Int, quote: String) -> MorningCard {
        let head = quote.split(whereSeparator: \.isWhitespace).prefix(7).joined(separator: " ")
        return MorningCard(id: id, book: book, ch: ch, kind: "mark", prompt: "İşaretlediğin cümle: “\(head) …”\nDevamını hatırla.",
                           answer: quote, options: [], full: quote, why: "Bu cümleyi sen işaretledin.", weight: 3, lane: nil)
    }

    static func fold(_ s: String) -> String {
        String(s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
            .filter { $0.isLetter || $0.isNumber }.prefix(80))
    }

    /// "Bugün" · "Dün" · the weekday.
    static func dayWord(_ day: String, now: Date = Date()) -> String {
        if day == Tarih.gun(now) { return "Bugün" }
        if day == Tarih.gun(now.gun(-1)) { return "Dün" }
        guard let d = Tarih.coz(day) else { return day }
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "EEEE"
        let w = f.string(from: d)
        return w.prefix(1).uppercased(with: Locale(identifier: "tr_TR")) + w.dropFirst()
    }

    static func minutesText(_ m: Double) -> String { "\(max(1, Int(m.rounded()))) dk" }
}

// MARK: - The room

struct EveningView: View {
    @EnvironmentObject var depo: Depo
    @ObservedObject private var store = EveningStore.shared
    var wide = false
    var close: (() -> Void)?

    @State private var session = EveningSession(day: "", branches: [])
    @State private var started = false          // a branch was opened: the plan no longer changes under the hand
    @State private var index = 0
    @State private var testing = false
    @State private var queue: [MorningCard] = []
    @State private var branchFinished = false
    @State private var asked = 0
    @State private var kept = 0
    @State private var closed = false
    @State private var expanded: Set<String> = []
    @State private var place: BookPlace?

    private var d: Durum { depo.durum }
    private var dayDone: Bool { d.eveningDone[session.day] != nil }
    private var studied: Set<String> { d.eveningBranches[session.day] ?? [] }
    private var current: EveningBranchPlan? { session.branches.indices.contains(index) ? session.branches[index] : nil }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header.id("top")
                    if session.branches.isEmpty {
                        emptyState
                    } else if closed || (dayDone && !started) {
                        doneCard
                    } else {
                        branchBar
                        if let b = current {
                            Group {
                                if testing { test(b) } else { show(b) }
                            }
                            .id(b.name + (testing ? ".test" : ".show"))
                        }
                    }
                }
                .padding(.horizontal, wide ? 32 : 18).padding(.vertical, wide ? 24 : 12)
                .frame(maxWidth: wide ? 900 : .infinity, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: index) { _, _ in withAnimation { proxy.scrollTo("top", anchor: .top) } }
            .onChange(of: testing) { _, _ in withAnimation { proxy.scrollTo("top", anchor: .top) } }
        }
        .background(Tema.arka)
        .onAppear { rebuild() }
        .task { await store.refresh(); rebuild() }
        .onChange(of: store.revision) { _, _ in if !started { rebuild() } }
        .bookPlaceOpener($place)
    }

    private func rebuild() {
        session = store.session(depo.durum)
        if let i = session.branches.firstIndex(where: { !studied.contains($0.name) }), !started { index = i }
    }

    // MARK: parts

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Akşam tekrarı").font(Tema.serif(wide ? .largeTitle : .title, .semibold)).foregroundStyle(Tema.metin)
                Text(subtitle).font(.subheadline).foregroundStyle(Tema.ikincil)
            }
            Spacer()
            if store.preparing { ProgressView().controlSize(.small) }
            if let close {
                Button(action: close) { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(Tema.soluk) }
                    .buttonStyle(.plain).accessibilityLabel("Kapat").keyboardShortcut(.cancelAction)
            }
        }
    }

    private var subtitle: String {
        guard !session.branches.isEmpty else { return "Gün içinde dinlediklerin, yatmadan önce" }
        let books = session.branches.reduce(0) { $0 + $1.books.count }
        return "\(EveningStore.dayWord(session.day)) \(EveningStore.minutesText(session.minutes)) dinledin · \(books) kitap · önce kısa gösterim, sonra test"
    }

    private var branchBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(session.branches.enumerated()), id: \.element.id) { i, b in
                    Button {
                        withAnimation(.snappy) { index = i; testing = false; branchFinished = false; started = true }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: studied.contains(b.name) ? "checkmark.circle.fill" : "circle.fill")
                                .font(.system(size: studied.contains(b.name) ? 13 : 8))
                                .foregroundStyle(studied.contains(b.name) ? Tema.basari : MorningBranch.color(b.name))
                            Text(b.name).font(.subheadline.weight(i == index ? .semibold : .regular))
                                .foregroundStyle(i == index ? Tema.metin : Tema.ikincil)
                            Text(EveningStore.minutesText(b.minutes)).font(.caption).foregroundStyle(Tema.soluk).monospacedDigit()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Capsule().fill(i == index ? Tema.yuzey : .clear))
                        .overlay(Capsule().stroke(i == index ? Tema.cizgi : .clear))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: 1 · the short showing

    private func show(_ b: EveningBranchPlan) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Kısa gösterim · \(b.name)", systemImage: "eye").font(.caption.weight(.semibold))
                .foregroundStyle(MorningBranch.color(b.name))
            ForEach(b.books) { book in bookCard(book) }
            HStack {
                Spacer()
                Button { startTest(b) } label: { Label("Teste geç", systemImage: "arrow.right").padding(.horizontal, 8) }
                    .buttonStyle(AnaDugme(renk: Tema.vurgu))
                    .frame(maxWidth: 320)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    private func bookCard(_ book: EveningBook) -> some View {
        MorningCardBox {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(MorningBranch.color(book.branch)).frame(width: 8, height: 8)
                Text(book.title).font(Tema.serif(.title3, .semibold)).foregroundStyle(Tema.metin).lineLimit(2)
                Spacer()
                Text(EveningStore.minutesText(book.minutes) + (book.chapters.isEmpty ? "" : " · \(book.chapters.count) bölüm"))
                    .font(.caption).foregroundStyle(Tema.ikincil)
            }
            ForEach(book.chapters, id: \.ch) { c in
                chapterView(book, c)
                if c.ch != book.chapters.last?.ch { Divider().overlay(Tema.cizgi) }
            }
            if book.waiting > 0 || !book.known {
                Text(book.known
                     ? "\(book.waiting) bölüm daha dinledin; Mac onları hazırlayınca burada açılır."
                     : "Bu kitabın bölümlerini Mac henüz görmedi; bir sonraki Sabah planıyla gelir. İşaretlerin aşağıda.")
                    .font(.caption).foregroundStyle(Tema.soluk)
            }
            if !book.marks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("İşaretlediklerin", systemImage: "highlighter").font(.caption.weight(.semibold)).foregroundStyle(Tema.altin)
                    ForEach(Array(book.marks.prefix(8).enumerated()), id: \.offset) { _, m in
                        quoteRow(m.quote, m.note, tint: Tema.altin)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func chapterView(_ book: EveningBook, _ c: MorningChapter) -> some View {
        let id = "\(book.id)#\(c.ch)"
        let full = c.summary ?? ""
        let short = Self.short(full)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(c.title).font(.callout.weight(.semibold)).foregroundStyle(Tema.metin)
                Spacer()
                Button { place = BookPlace(book: book.id, ch: c.ch) } label: { Label("Kitapta aç", systemImage: "book") }
                    .font(.caption.weight(.semibold)).buttonStyle(.plain).foregroundStyle(Tema.vurgu)
            }
            if let k = c.key, !k.isEmpty { Text(k).font(.caption).foregroundStyle(Tema.ikincil) }
            if !full.isEmpty {
                Text(expanded.contains(id) ? full : short).font(.callout).foregroundStyle(Tema.metin)
                    .fixedSize(horizontal: false, vertical: true)
                if short != full {
                    Button(expanded.contains(id) ? "Kısalt" : "Devamı") {
                        withAnimation(.snappy) { if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) } }
                    }
                    .font(.caption).buttonStyle(.plain).foregroundStyle(Tema.vurgu)
                }
            }
            ForEach(Array(c.keys.prefix(2).enumerated()), id: \.offset) { _, q in
                quoteRow(q.quote, q.why, tint: MorningBranch.color(book.branch))
            }
            if let m = c.missed.first {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Kaçmış olabilir").font(.caption2.weight(.semibold)).foregroundStyle(Tema.uyari)
                    quoteRow(m.quote, m.why, tint: Tema.uyari)
                }
            }
        }
    }

    private func quoteRow(_ quote: String, _ note: String?, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1).fill(tint.opacity(0.6)).frame(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(quote).font(Tema.serif(.callout)).foregroundStyle(Tema.metin).fixedSize(horizontal: false, vertical: true)
                if let n = note, !n.isEmpty { Text(n).font(.caption).foregroundStyle(Tema.ikincil) }
            }
        }
    }

    /// The summary's first sentences, about two lines' worth.
    static func short(_ s: String) -> String {
        var out = ""
        for part in s.split(separator: ".", omittingEmptySubsequences: false) {
            out += (out.isEmpty ? "" : ".") + part
            if out.count >= 200 { break }
        }
        if out.count < s.count { out += "." }
        return out.count >= s.count - 1 ? s : out
    }

    // MARK: 2 · the test

    private func startTest(_ b: EveningBranchPlan) {
        queue = store.cards(for: b, depo.durum)
        branchFinished = false
        started = true
        withAnimation(.snappy) { testing = true }
    }

    private func test(_ b: EveningBranchPlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Test · \(b.name)", systemImage: "rectangle.stack").font(.caption.weight(.semibold))
                .foregroundStyle(MorningBranch.color(b.name))
            if queue.isEmpty {
                MorningCardBox {
                    Text("Bu dalda sorulacak kart yok").font(.headline).foregroundStyle(Tema.metin)
                    Text("Bu bölümlerin kartları ya bugün soruldu ya da Mac onları henüz yazmadı. Gösterim bu akşam için yeter.")
                        .font(.callout).foregroundStyle(Tema.ikincil)
                }
                .onAppear { finishBranch(b, right: 0) }
            } else {
                MorningReview(queue: queue, today: Tarih.gun(Date()),
                              openBook: { c in place = BookPlace(book: c.book, ch: c.ch) },
                              finish: { right in finishBranch(b, right: right) })
            }
            if branchFinished { nextButton }
        }
    }

    private var nextButton: some View {
        let last = index + 1 >= session.branches.count
        return HStack {
            Spacer()
            Button {
                if last { closeEvening() } else {
                    withAnimation(.snappy) { index += 1; testing = false; branchFinished = false }
                }
            } label: {
                Label(last ? "Akşamı kapat" : "Sıradaki: \(session.branches[index + 1].name)",
                      systemImage: last ? "moon.zzz.fill" : "arrow.right")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(AnaDugme(renk: last ? Tema.basari : Tema.vurgu))
            .frame(maxWidth: 320)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    private func finishBranch(_ b: EveningBranchPlan, right: Int) {
        guard !branchFinished else { return }
        branchFinished = true
        asked += queue.count
        kept += right
        if !studied.contains(b.name) {
            depo.ekle(Olay(tur: .eveningBranch, hedef: session.day, metin: b.chapterKeys.joined(separator: ","), rol: b.name))
        }
    }

    private func closeEvening() {
        let names = session.branches.map(\.name).filter { studied.contains($0) || $0 == current?.name }
        depo.ekle(Olay(tur: .eveningDone, hedef: session.day, puan: Double(kept), metin: names.joined(separator: ","),
                       sure: session.minutes))
        #if canImport(PDMBus)
        PDMEvening.closedDay = session.day       // Wise Path does not remind again for this day
        #endif
        withAnimation(.spring) { closed = true }
    }

    // MARK: done · empty

    private var doneCard: some View {
        MorningCardBox {
            VStack(spacing: 14) {
                Image(systemName: "moon.stars.fill").font(.system(size: 50)).foregroundStyle(Tema.basari)
                Text("Akşam tamam").font(Tema.serif(.largeTitle, .semibold)).foregroundStyle(Tema.metin)
                Text("\(EveningStore.dayWord(session.day)) dinlediklerin yatmadan önce bir kez daha geçti. Unuttukların sabah ve sonraki günlerde yeniden gelir.")
                    .font(.callout).foregroundStyle(Tema.ikincil).multilineTextAlignment(.center)
                HStack(spacing: 0) {
                    stat(EveningStore.minutesText(session.minutes), "dinleme")
                    stat("\(session.chapterCount)", "bölüm")
                    if asked > 0 { stat("\(kept)/\(asked)", "kart hatırlandı") }
                }
                .padding(.vertical, 6)
                ForEach(session.branches) { b in
                    HStack(spacing: 8) {
                        Circle().fill(MorningBranch.color(b.name)).frame(width: 8, height: 8)
                        Text(b.name).font(.caption).foregroundStyle(Tema.metin)
                        Text(EveningStore.minutesText(b.minutes)).font(.caption).foregroundStyle(Tema.soluk)
                        Spacer()
                        if studied.contains(b.name) { Image(systemName: "checkmark").font(.caption).foregroundStyle(Tema.basari) }
                    }
                }
                Button("Bir daha bak") {
                    withAnimation(.snappy) { closed = false; started = true; index = 0; testing = false; branchFinished = false }
                }
                .font(.caption).buttonStyle(.plain).foregroundStyle(Tema.vurgu)
                if let close { Button("Kapat", action: close).buttonStyle(IkinciDugme()).frame(maxWidth: 240) }
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

    private var emptyState: some View {
        MorningCardBox {
            Text("Bugün dinleme yok").font(.headline).foregroundStyle(Tema.metin)
            Text("Wise Path'te dinlediğin bölümler eve geldiğinde burada dal dal açılır: önce dinlediğin yerlerin kısa gösterimi, sonra test. Yatmadan önce bildirim gelir.")
                .font(.callout).foregroundStyle(Tema.ikincil)
        }
    }
}

// MARK: - Bugün's card

struct EveningEntryCard: View {
    @EnvironmentObject var depo: Depo
    @ObservedObject private var store = EveningStore.shared
    var open: () -> Void

    var body: some View {
        let s = store.session(depo.durum)
        let done = depo.durum.eveningDone[s.day] != nil
        let studied = depo.durum.eveningBranches[s.day] ?? []
        if s.minutes >= 1 {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Akşam tekrarı", systemImage: done ? "checkmark.seal.fill" : "moon.stars.fill")
                            .font(.caption.weight(.semibold)).foregroundStyle(done ? Tema.basari : Tema.vurgu)
                        Spacer()
                        Text(done ? "kapandı" : "\(studied.count)/\(s.branches.count) dal").font(.caption).foregroundStyle(Tema.soluk)
                    }
                    Text(done ? "Akşam tamam" : "\(EveningStore.dayWord(s.day)) \(EveningStore.minutesText(s.minutes)) dinledin")
                        .font(Tema.serif(.title3, .semibold)).foregroundStyle(Tema.metin)
                    HStack(spacing: 6) {
                        ForEach(s.branches) { b in
                            Text("\(b.name) \(EveningStore.minutesText(b.minutes))").font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(MorningBranch.color(b.name).opacity(0.15)))
                                .foregroundStyle(MorningBranch.color(b.name))
                        }
                        Spacer(minLength: 0)
                    }
                    if !done {
                        Label("Önce kısa gösterim, sonra test", systemImage: "play.fill")
                            .font(.callout.weight(.semibold)).foregroundStyle(Tema.vurgu)
                    }
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 18).fill(Tema.yuzey))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(done ? Tema.basari.opacity(0.4) : Tema.vurgu.opacity(0.35)))
            }
            .buttonStyle(.plain)
        }
    }
}
