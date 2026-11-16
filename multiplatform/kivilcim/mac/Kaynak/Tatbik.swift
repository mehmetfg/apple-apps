// Tatbik (2026-11-05): every Kıvılcım record split into items, items grouped by program, each with a status
// (açık · kısmen · tamamlandı · gerek görülmedi). Claude reviews ("Tatbik'i güncelle"), the user overrides here.
// 2026-11-11: larger type, a filter bar that stays on top while the list scrolls, saved views (Tatbik/views.json, so
// the other Mac sees them too), "next up" picks, keyboard (↑↓ · 1–3 · ↩ · Esc) and a ⌘K jump palette.
// The detail opens as an inspector only when an item is picked: until then the list has the whole width.
import SwiftUI
import AppKit

struct StatusRing: View {
    let value: Double
    var color: Color = Ink.ember
    var size: CGFloat = 44
    var line: CGFloat = 5
    var body: some View {
        ZStack {
            Circle().stroke(Ink.line, lineWidth: line)
            Circle().trim(from: 0, to: max(0.001, value)).stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((value * 100).rounded()))").font(.system(size: size * 0.28, weight: .semibold).monospacedDigit())
        }
        .frame(width: size, height: size)
        .animation(.snappy, value: value)
    }
}

extension TatbikStatus { var color: Color { Color(hex: hex) } }

// MARK: Item helpers

extension TatbikItem {
    private static let dayFormat = Zaman.formatter("yyyyMMdd", posix: true)
    /// Record ids start with the day they were made: 20261026-201346-iphone-93ca.
    var newestSource: Date? {
        sources.compactMap { s -> Date? in
            let p = String(s.prefix(8))
            return p.count == 8 && p.allSatisfy(\.isNumber) ? Self.dayFormat.date(from: p) : nil
        }.max()
    }
    var ageDays: Int? { newestSource.map { Int(Date().timeIntervalSince($0) / 86400) } }
    var doneDate: Date? { tarih.flatMap { Zaman.formatter("yyyy-MM-dd", posix: true).date(from: String($0.prefix(10))) } }
    var sizeRank: Int { ["kucuk": 0, "orta": 1, "buyuk": 2][buyukluk ?? ""] ?? 1 }
    var hasNotes: Bool { !(notlar ?? []).isEmpty }
    var searchText: String { Arama.katla([baslik, ayrinti, kanit, eksik, gerekce, id].compactMap { $0 }.joined(separator: " ")) }
}

// MARK: Filter and saved views

/// Everything the Tatbik list can be narrowed by. Codable: a saved view is a name plus one of these.
struct TatbikFilter: Codable, Equatable {
    var program: String?
    var statuses: Set<String> = []
    var priorities: Set<String> = []      // yuksek · normal · dusuk · "" (not set)
    var sizes: Set<String> = []           // kucuk · orta · buyuk
    var mine = false
    var noted = false
    var staleDays: Int?                   // open items whose newest record is older than this
    var doneWithinDays: Int?              // finished in the last n days
    var hideClosed = false
    var group = "program"                 // program · status · priority · none
    var sort = "smart"                    // smart · newest · oldest
    var limit: Int?

    init() {}

    /// The narrowing part only (grouping and order are how it looks, not what it shows).
    var isNarrowed: Bool {
        program != nil || !statuses.isEmpty || !priorities.isEmpty || !sizes.isEmpty || mine || noted
            || staleDays != nil || doneWithinDays != nil || hideClosed || limit != nil
    }

    func admits(_ m: TatbikItem, _ q: String) -> Bool {
        if let program, m.program != program { return false }
        if !statuses.isEmpty, !statuses.contains(m.status.rawValue) { return false }
        if !priorities.isEmpty, !priorities.contains(m.oncelik ?? "") { return false }
        if !sizes.isEmpty, !sizes.contains(m.buyukluk ?? "") { return false }
        if mine, !m.byUser { return false }
        if noted, !m.hasNotes { return false }
        if hideClosed, statuses.isEmpty, m.status.isClosed { return false }
        if let d = staleDays { guard !m.status.isClosed, let a = m.ageDays, a >= d else { return false } }
        if let d = doneWithinDays {
            guard m.status == .tamam, let t = m.doneDate, Date().timeIntervalSince(t) < Double(d + 1) * 86400 else { return false }
        }
        if !q.isEmpty {
            let s = m.searchText
            if !q.split(separator: " ").allSatisfy({ s.contains($0) }) { return false }
        }
        return true
    }

    enum CodingKeys: String, CodingKey {
        case program, statuses, priorities, sizes, mine, noted, staleDays, doneWithinDays, hideClosed, group, sort, limit
    }
    /// Lenient: views.json is a file people (and Claude) may edit by hand.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        program = try c.decodeIfPresent(String.self, forKey: .program)
        statuses = try c.decodeIfPresent(Set<String>.self, forKey: .statuses) ?? []
        priorities = try c.decodeIfPresent(Set<String>.self, forKey: .priorities) ?? []
        sizes = try c.decodeIfPresent(Set<String>.self, forKey: .sizes) ?? []
        mine = try c.decodeIfPresent(Bool.self, forKey: .mine) ?? false
        noted = try c.decodeIfPresent(Bool.self, forKey: .noted) ?? false
        staleDays = try c.decodeIfPresent(Int.self, forKey: .staleDays)
        doneWithinDays = try c.decodeIfPresent(Int.self, forKey: .doneWithinDays)
        hideClosed = try c.decodeIfPresent(Bool.self, forKey: .hideClosed) ?? false
        group = try c.decodeIfPresent(String.self, forKey: .group) ?? "program"
        sort = try c.decodeIfPresent(String.self, forKey: .sort) ?? "smart"
        limit = try c.decodeIfPresent(Int.self, forKey: .limit)
    }
}

struct TatbikSavedView: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var symbol: String
    var filter: TatbikFilter
    var note: String?

    static let builtIn: [TatbikSavedView] = {
        func make(_ id: String, _ name: String, _ symbol: String, _ note: String, _ f: (inout TatbikFilter) -> Void) -> TatbikSavedView {
            var x = TatbikFilter(); f(&x)
            return TatbikSavedView(id: id, name: name, symbol: symbol, filter: x, note: note)
        }
        return [
            make("next", "Sıradaki işler", "bolt.fill", "Açık ve yarım kalan, önce yüksek öncelik ve küçük iş") {
                $0.statuses = ["acik", "kismen"]; $0.group = "none"; $0.limit = 12
            },
            make("quick", "Hızlı kazançlar", "hare.fill", "Küçük işler: bir oturumda biter") {
                $0.statuses = ["acik", "kismen"]; $0.sizes = ["kucuk"]
            },
            make("half", "Yarım kalanlar", "circle.lefthalf.filled", "Başlanmış ama bitmemiş") { $0.statuses = ["kismen"] },
            make("high", "Yüksek öncelik", "flag.fill", "Kapanmamış yüksek öncelikliler") {
                $0.priorities = ["yuksek"]; $0.hideClosed = true; $0.group = "status"
            },
            make("stale", "Uzun süredir bekleyen", "hourglass", "Kaydı 14 günden eski, hâlâ açık") {
                $0.staleDays = 14; $0.sort = "oldest"; $0.group = "none"
            },
            make("week", "Bu hafta bitenler", "checkmark.seal.fill", "Son 7 günde tamamlanan") {
                $0.doneWithinDays = 7; $0.group = "none"; $0.sort = "newest"
            },
            make("mine", "Senin işaretlediklerin", "pencil", "Durumu senin değiştirdiğin maddeler") { $0.mine = true },
        ]
    }()
}

/// The user's own saved views live in the vault (Tatbik/views.json): iCloud carries them to the other Mac.
@MainActor final class TatbikViews: ObservableObject {
    static let shared = TatbikViews()
    @Published private(set) var custom: [TatbikSavedView] = []
    private var date: Date?

    private struct File: Codable { var views: [TatbikSavedView] }
    private func url(_ kok: URL) -> URL { kok.appendingPathComponent("Tatbik/views.json") }

    func load(_ kok: URL) {
        let u = url(kok)
        let t = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard t != date else { return }
        date = t
        if let v = try? Data(contentsOf: u), let f = try? JSONDecoder().decode(File.self, from: v) { custom = f.views }
    }

    func save(_ v: TatbikSavedView, _ kok: URL) { write(kok) { l in l.removeAll { $0.id == v.id }; l.append(v) } }
    func remove(_ id: String, _ kok: URL) { write(kok) { $0.removeAll { $0.id == id } } }

    /// Read again right before writing: the other Mac may have added one in between.
    private func write(_ kok: URL, _ change: (inout [TatbikSavedView]) -> Void) {
        date = nil
        load(kok)
        var l = custom
        change(&l)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(File(views: l)) {
            try? FileManager.default.createDirectory(at: url(kok).deletingLastPathComponent(), withIntermediateDirectories: true)
            try? d.write(to: url(kok), options: .atomic)
        }
        custom = l
        date = (try? url(kok).resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}

// MARK: Main view

struct TatbikView: View {
    @EnvironmentObject var depo: Depo
    @ObservedObject private var views = TatbikViews.shared
    @Binding var selection: String?
    let query: String
    @AppStorage("tatbikFilter") private var storedFilter = ""
    @AppStorage("tatbikShowOverview") private var showOverview = true
    @State private var showTable = false
    @State private var filter = TatbikFilter()
    @State private var activeView: String?
    @State private var showPalette = false
    @State private var saving = false
    @State private var newViewName = ""
    @State private var copiedAll = false
    @FocusState private var listFocused: Bool

    private var t: TatbikState { depo.tatbik }
    private var allViews: [TatbikSavedView] { TatbikSavedView.builtIn + views.custom }
    private var visiblePrograms: [TatbikProgram] { t.programlar.filter { !t.items(of: $0.id).isEmpty } }

    /// What the list shows, in order.
    private var shown: [TatbikItem] {
        let q = Arama.katla(query)
        let l = t.maddeler.filter { filter.admits($0, q) }.sorted(by: order)
        return filter.limit.map { Array(l.prefix($0)) } ?? l
    }

    private func order(_ a: TatbikItem, _ b: TatbikItem) -> Bool {
        switch filter.sort {
        case "newest":
            let x = a.doneDate ?? a.newestSource ?? .distantPast, y = b.doneDate ?? b.newestSource ?? .distantPast
            return x != y ? x > y : a.id < b.id
        case "oldest":
            let x = a.newestSource ?? .distantFuture, y = b.newestSource ?? .distantFuture
            return x != y ? x < y : a.id < b.id
        default:
            return Self.smart(a, b)
        }
    }

    /// Open before closed; then priority, then small jobs, then the longest waiting.
    static func smart(_ a: TatbikItem, _ b: TatbikItem) -> Bool {
        let ca = a.status.isClosed ? 1 : 0, cb = b.status.isClosed ? 1 : 0
        if ca != cb { return ca < cb }
        if a.status.isClosed { return statusOrder(a.status) != statusOrder(b.status) ? statusOrder(a.status) < statusOrder(b.status) : a.id < b.id }
        if a.priorityRank != b.priorityRank { return a.priorityRank < b.priorityRank }
        if a.sizeRank != b.sizeRank { return a.sizeRank < b.sizeRank }
        let x = a.newestSource ?? .distantFuture, y = b.newestSource ?? .distantFuture
        return x != y ? x < y : a.id < b.id
    }
    static func statusOrder(_ s: TatbikStatus) -> Int { [.acik: 0, .kismen: 1, .tamam: 2][s] ?? 0 }

    private var groups: [(key: String, title: String, color: Color?, items: [TatbikItem])] {
        let l = shown
        switch filter.group {
        case "program":
            return t.programlar.compactMap { p in
                let x = l.filter { $0.program == p.id }
                return x.isEmpty ? nil : (p.id, p.ad, Ink.topic(p.renk ?? ""), x)
            } + {
                let known = Set(t.programlar.map(\.id))
                let x = l.filter { !known.contains($0.program) }
                return x.isEmpty ? [] : [("?", "Programsız", nil, x)]
            }()
        case "status":
            return TatbikStatus.allCases.compactMap { s in
                let x = l.filter { $0.status == s }
                return x.isEmpty ? nil : (s.rawValue, s.name, s.color, x)
            }
        case "priority":
            return [("yuksek", "Yüksek öncelik"), ("normal", "Normal"), ("dusuk", "Düşük"), ("", "Öncelik verilmemiş")].compactMap { k, n in
                let x = l.filter { ($0.oncelik ?? "") == k }
                return x.isEmpty ? nil : (k, n, k == "yuksek" ? Ink.ember : nil, x)
            }
        default:
            return l.isEmpty ? [] : [("all", "", nil, l)]
        }
    }

    var body: some View {
        if t.maddeler.isEmpty {
            ContentUnavailableView("Henüz Tatbik yok", systemImage: "checklist",
                                   description: Text("Claude'a \"Tatbik'i güncelle\" de: kayıtları maddelere böler, programlara bağlar, yapılıp yapılmadığına bakar."))
        } else {
            // side by side (2026-11-11): the list never sits under the summary; each column scrolls on its own
            GeometryReader { g in
                VStack(spacing: 0) {
                    header.padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 16)
                    Rectangle().fill(Ink.line).frame(height: 1)
                    HStack(spacing: 0) {
                        if showOverview && g.size.width >= 760 {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 24) {
                                    statusGrid
                                    nextUp
                                    programs
                                }
                                .padding(20)
                            }
                            .frame(width: min(340, max(280, g.size.width * 0.32)))
                            .background(Ink.surface2.opacity(0.45))
                            Rectangle().fill(Ink.line).frame(width: 1)
                        }
                        VStack(spacing: 0) {
                            filterBar.padding(.horizontal, 22)
                            listScroll
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .background(Ink.paper)
            .sheet(isPresented: $showPalette) {
                TatbikPalette(views: allViews) { pick in
                    showPalette = false
                    switch pick {
                    case .view(let v): apply(v)
                    case .program(let p): withAnimation(.snappy) { filter.program = p; activeView = nil }
                    case .item(let id): selection = id
                    }
                    listFocused = true
                }
                .environmentObject(depo)
            }
            .background {
                Button("") { showPalette = true }.keyboardShortcut("k", modifiers: .command).hidden()
            }
            .onAppear {
                views.load(depo.kok)
                if let d = storedFilter.data(using: .utf8), let f = try? JSONDecoder().decode(TatbikFilter.self, from: d) { filter = f }
                listFocused = true
            }
            .onChange(of: filter) { _, f in
                if let d = try? JSONEncoder().encode(f) { storedFilter = String(decoding: d, as: UTF8.self) }
                if let a = activeView, allViews.first(where: { $0.id == a })?.filter != f { activeView = nil }
            }
        }
    }

    private var listScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                list.padding(.horizontal, 22).padding(.vertical, 16)
                    .frame(maxWidth: 980, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .focusable()
            .focusEffectDisabled()
            .focused($listFocused)
            .onKeyPress(keys: [.upArrow, .downArrow]) { k in move(k.key == .downArrow ? 1 : -1); return .handled }
            .onKeyPress(characters: CharacterSet(charactersIn: "jk123"), phases: .down) { k in
                switch k.characters {
                case "j": move(1)
                case "k": move(-1)
                default:
                    guard let id = selection, let n = Int(k.characters), n >= 1, n <= TatbikStatus.allCases.count else { return .ignored }
                    withAnimation(.snappy) { depo.tatbikDuzelt(id, "status", TatbikStatus.allCases[n - 1].rawValue) }
                }
                return .handled
            }
            .onKeyPress(.escape) {
                guard selection != nil else { return .ignored }
                selection = nil
                return .handled
            }
            .onChange(of: selection) { _, id in
                guard let id else { return }
                withAnimation(.snappy) { proxy.scrollTo(id, anchor: nil) }
            }
        }
    }

    private func move(_ step: Int) {
        let ids = groups.flatMap { $0.items.map(\.id) }
        guard !ids.isEmpty else { return }
        if let s = selection, let i = ids.firstIndex(of: s) {
            selection = ids[max(0, min(ids.count - 1, i + step))]
        } else {
            selection = step > 0 ? ids.first : ids.last
        }
    }

    private func apply(_ v: TatbikSavedView) {
        withAnimation(.snappy) { filter = v.filter; activeView = v.id }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tatbik").font(.system(size: 40, weight: .bold, design: .serif))
                Text("Kıvılcım'da söylediklerin, madde madde, program program. Yapıldıysa kanıtıyla.")
                    .font(Ink.serif(.title3)).foregroundStyle(Ink.secondary).lineLimit(1)
                HStack(spacing: 8) {
                    Text("Claude son baktı: \(String((t.guncelleme ?? "").prefix(16)).replacingOccurrences(of: "T", with: " "))")
                    if let n = t.incelenmemis?.count, n > 0 {
                        Text("· bakılmamış \(n) kayıt").foregroundStyle(Ink.ember)
                    }
                }
                .font(.callout).foregroundStyle(Ink.faint)
            }
            Spacer()
            Button { withAnimation(.snappy) { showOverview.toggle() } } label: {
                Label(showOverview ? "Özeti gizle" : "Özeti göster", systemImage: "sidebar.left")
            }
            .help("Soldaki özet sütununu aç/kapat: liste bütün genişliği alır")
            Button { showPalette = true } label: { Label("Git…", systemImage: "command") }
                .help("Bir maddeye, programa ya da görünüme atla (⌘K)")
            VStack(spacing: 3) {
                StatusRing(value: t.progress(), color: TatbikStatus.tamam.color, size: 74, line: 8)
                Text("tamamlandı").font(.caption).foregroundStyle(Ink.secondary)
            }
            .help("Tamamlanan maddelerin payı")
        }
    }

    // MARK: Status cards (big numbers), 2 × 2 in the summary column

    private var statusGrid: some View {
        let scope = filter.program.map { t.items(of: $0) }
        let total = max(1, (scope ?? t.maddeler).count)
        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Durum", filter.program.flatMap { t.program($0)?.ad })
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(TatbikStatus.allCases) { s in
                    let on = filter.statuses == [s.rawValue]
                    let n = t.count(s, in: scope)
                    Button {
                        withAnimation(.snappy) { filter.statuses = on ? [] : [s.rawValue]; filter.hideClosed = false }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(s.short, systemImage: s.symbol).font(.headline).foregroundStyle(s.color).lineLimit(1)
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("\(n)").font(.system(size: 36, weight: .bold, design: .serif)).monospacedDigit()
                                Text("%\(Int((Double(n) / Double(total) * 100).rounded()))").font(.callout.monospacedDigit()).foregroundStyle(Ink.secondary)
                            }
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(on ? s.color.opacity(0.14) : Ink.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? s.color : Ink.line, lineWidth: on ? 2 : 1) }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Yalnız \(s.name.lowercased()) maddeleri göster")
                }
            }
            StackedBar(items: scope ?? t.maddeler).frame(height: 8)
        }
    }

    private func sectionTitle(_ s: String, _ extra: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(s).font(Ink.serif(.title2, .bold))
            if let extra { Text(extra).font(.callout).foregroundStyle(Ink.secondary).lineLimit(1) }
        }
    }

    // MARK: Next up

    /// Three items worth doing now, without opening any filter.
    private var nextUp: some View {
        let l = Array(t.maddeler.filter { !$0.status.isClosed }.sorted(by: Self.smart).prefix(3))
        return Group {
            if !l.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Sıradaki", systemImage: "bolt.fill").font(Ink.serif(.title2, .bold)).foregroundStyle(Ink.ember)
                        Spacer()
                        if let v = TatbikSavedView.builtIn.first(where: { $0.id == "next" }) {
                            Button("Hepsi") { apply(v) }.buttonStyle(.link)
                        }
                    }
                    ForEach(l) { m in nextCard(m) }
                }
            }
        }
    }

    private func nextCard(_ m: TatbikItem) -> some View {
        let p = t.program(m.program)
        let on = selection == m.id
        return Button { selection = m.id; listFocused = true } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: m.status.symbol).foregroundStyle(m.status.color)
                    Text(p?.ad ?? m.program).font(.caption.weight(.semibold)).foregroundStyle(Ink.topic(p?.renk ?? "")).lineLimit(1)
                    Spacer(minLength: 0)
                    if let a = m.ageDays { Text("\(a) gün").font(.caption).foregroundStyle(Ink.faint) }
                }
                Text(m.baslik).font(.system(size: 14, weight: .semibold)).multilineTextAlignment(.leading)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if let x = m.priorityName { Text(x).foregroundStyle(m.oncelik == "yuksek" ? Ink.ember : Ink.secondary) }
                    if let x = m.sizeName { Text(x) }
                }
                .font(.caption).foregroundStyle(Ink.faint)
            }
            .padding(11).frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? Ink.ember.opacity(0.10) : Ink.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? Ink.ember : Ink.line, lineWidth: on ? 1.5 : 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { TatbikMenu(m: m) }
    }

    // MARK: Programs (a column of rows; the program × status table opens as a popover)

    private var programs: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle("Programlar", "\(visiblePrograms.count)")
                Spacer()
                Button { showTable = true } label: { Image(systemName: "tablecells") }
                    .buttonStyle(.borderless).help("Program × durum tablosu")
                    .popover(isPresented: $showTable, arrowEdge: .trailing) { matrix.padding(6).frame(minWidth: 640) }
            }
            ForEach(visiblePrograms) { p in programRow(p) }
        }
    }

    private func programRow(_ p: TatbikProgram) -> some View {
        let items = t.items(of: p.id)
        let on = filter.program == p.id
        let c = Ink.topic(p.renk ?? "")
        let open = items.filter { !$0.status.isClosed }.count
        return Button { withAnimation(.snappy) { filter.program = on ? nil : p.id } } label: {
            HStack(spacing: 11) {
                StatusRing(value: t.progress(items), color: c, size: 44, line: 5)
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.ad).font(.system(size: 15, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                    HStack(spacing: 8) {
                        ForEach(TatbikStatus.allCases) { s in
                            let n = t.count(s, in: items)
                            if n > 0 {
                                HStack(spacing: 2) { Image(systemName: s.symbol); Text("\(n)") }
                                    .font(.callout.monospacedDigit().weight(.medium)).foregroundStyle(s.color)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                if open > 0 {
                    Text("\(open)").font(.system(size: 20, weight: .bold, design: .serif)).monospacedDigit()
                        .foregroundStyle(c).help("\(open) açık madde")
                }
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? c.opacity(0.13) : Ink.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? c : Ink.line, lineWidth: on ? 2 : 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(p.aciklama ?? p.ad)
    }

    /// Program × status: every cell a count you can click into.
    private var matrix: some View {
        Card(padding: 16) {
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    Text("").gridColumnAlignment(.leading)
                    ForEach(TatbikStatus.allCases) { s in
                        Label(s.short, systemImage: s.symbol).font(.callout.weight(.semibold)).foregroundStyle(s.color).frame(width: 96)
                    }
                }
                ForEach(visiblePrograms) { p in
                    let items = t.items(of: p.id)
                    GridRow {
                        Text(p.ad).font(.body.weight(.medium)).lineLimit(1).frame(maxWidth: 320, alignment: .leading)
                        ForEach(TatbikStatus.allCases) { s in
                            let n = t.count(s, in: items)
                            let on = filter.program == p.id && filter.statuses == [s.rawValue]
                            Button {
                                withAnimation(.snappy) {
                                    if on { filter.program = nil; filter.statuses = [] } else { filter.program = p.id; filter.statuses = [s.rawValue] }
                                }
                                showTable = false
                            } label: {
                                Text(n == 0 ? "·" : "\(n)").font(.body.monospacedDigit().weight(n > 0 ? .semibold : .regular))
                                    .frame(width: 96, height: 30)
                                    .foregroundStyle(n == 0 ? Ink.faint : on ? .white : s.color)
                                    .background(RoundedRectangle(cornerRadius: 7)
                                        .fill(on ? s.color : s.color.opacity(n == 0 ? 0 : min(0.32, 0.06 + Double(n) * 0.012))))
                            }
                            .buttonStyle(.plain).disabled(n == 0)
                        }
                    }
                }
            }
        }
    }

    // MARK: Filter bar (above the list)

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(listTitle).font(Ink.serif(.title, .bold)).lineLimit(1)
                Text("\(shown.count)").font(.title2.monospacedDigit()).foregroundStyle(Ink.faint)
                Spacer()
                viewsMenu
                Button { copyAll() } label: {
                    Label(copiedAll ? "Kopyalandı" : "Claude'a götür", systemImage: copiedAll ? "checkmark" : "doc.on.clipboard")
                }
                .disabled(shown.filter { !$0.status.isClosed }.isEmpty)
                .help("Listedeki açık maddelerin “bunu yap” istemlerini birlikte kopyalar (en çok 15)")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chipMenu("Durum", filter.statuses, TatbikStatus.allCases.map { ($0.rawValue, $0.name) }) { filter.statuses = $0 }
                    chipMenu("Öncelik", filter.priorities, [("yuksek", "Yüksek"), ("normal", "Normal"), ("dusuk", "Düşük"), ("", "Verilmemiş")]) { filter.priorities = $0 }
                    chipMenu("İş", filter.sizes, [("kucuk", "Küçük iş"), ("orta", "Orta iş"), ("buyuk", "Büyük iş")]) { filter.sizes = $0 }
                    Menu {
                        Button("Hepsi") { filter.program = nil }
                        Divider()
                        ForEach(visiblePrograms) { p in
                            Button { filter.program = p.id } label: {
                                if filter.program == p.id { Label(p.ad, systemImage: "checkmark") } else { Text(p.ad) }
                            }
                        }
                    } label: { chipLabel(filter.program.flatMap { t.program($0)?.ad } ?? "Program", on: filter.program != nil) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    toggleChip("Senin işaretin", "pencil", $filter.mine)
                    toggleChip("Notlu", "text.bubble", $filter.noted)
                    toggleChip("14+ gün", "hourglass", Binding(get: { filter.staleDays != nil }, set: { filter.staleDays = $0 ? 14 : nil }))
                    toggleChip("Kapananları gizle", "eye.slash", $filter.hideClosed)
                }
                .padding(.vertical, 1)
            }
            HStack(spacing: 10) {
                Picker("Grupla", selection: $filter.group) {
                    Text("Programa göre").tag("program"); Text("Duruma göre").tag("status"); Text("Önceliğe göre").tag("priority"); Text("Gruplama yok").tag("none")
                }
                .fixedSize()
                Picker("Sıra", selection: $filter.sort) {
                    Text("Akıllı sıra").tag("smart"); Text("En yeni önce").tag("newest"); Text("En eski önce").tag("oldest")
                }
                .fixedSize()
                if filter.isNarrowed {
                    Button("Süzgeçleri temizle") { withAnimation(.snappy) { let g = filter.group, s = filter.sort; filter = TatbikFilter(); filter.group = g; filter.sort = s } }
                }
                Spacer()
            }
            .controlSize(.small)
            .labelsHidden()
        }
        .padding(.vertical, 12)
        .background(Ink.paper)
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.line).frame(height: 1) }
        .popover(isPresented: $saving, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Bu süzgeci görünüm olarak kaydet").font(.headline)
                TextField("Ad (ör. Wise Path küçük işler)", text: $newViewName).textFieldStyle(.roundedBorder).frame(width: 280)
                    .onSubmit(saveView)
                Text("Görünümler vault'ta durur: öteki Mac'te de çıkar.").font(.caption).foregroundStyle(Ink.secondary)
                HStack { Spacer(); Button("Vazgeç") { saving = false }; Button("Kaydet", action: saveView).keyboardShortcut(.defaultAction) }
            }
            .padding(16)
        }
    }

    private var viewsMenu: some View {
        Menu {
            Section("Hazır görünümler") {
                ForEach(TatbikSavedView.builtIn) { v in viewButton(v) }
            }
            if !views.custom.isEmpty {
                Section("Senin görünümlerin") {
                    ForEach(views.custom) { v in viewButton(v) }
                }
                Menu("Görünüm sil") {
                    ForEach(views.custom) { v in Button(v.name) { views.remove(v.id, depo.kok) } }
                }
            }
            Divider()
            Button("Bu süzgeci kaydet…") { newViewName = ""; saving = true }.disabled(!filter.isNarrowed)
        } label: {
            Label(allViews.first { $0.id == activeView }?.name ?? "Görünümler", systemImage: "line.3.horizontal.decrease.circle")
        }
        .fixedSize()
    }

    private func viewButton(_ v: TatbikSavedView) -> some View {
        Button { apply(v) } label: { Label(v.name, systemImage: activeView == v.id ? "checkmark" : v.symbol) }
            .help(v.note ?? "")
    }

    private func saveView() {
        let n = newViewName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        let id = "u-" + String(Int(Date().timeIntervalSince1970))
        views.save(TatbikSavedView(id: id, name: n, symbol: "line.3.horizontal.decrease", filter: filter, note: nil), depo.kok)
        activeView = id
        saving = false
    }

    private func copyAll() {
        let l = shown.filter { !$0.status.isClosed }.prefix(15)
        let text = l.map { m in
            m.prompt(t.program(m.program), m.sources.compactMap { id in depo.ogeler.first { $0.id == id } })
        }.joined(separator: "\n\n———\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("Kıvılcım › Tatbik · \(l.count) madde. Sırayla ele al.\n\n" + text, forType: .string)
        copiedAll = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedAll = false }
    }

    private func chipLabel(_ text: String, on: Bool) -> some View {
        HStack(spacing: 4) {
            Text(text).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
        }
        .font(.callout.weight(on ? .semibold : .regular))
        .padding(.horizontal, 10).padding(.vertical, 5)
        .foregroundStyle(on ? Ink.ember : Ink.text)
        .background(Capsule().fill(on ? Ink.ember.opacity(0.13) : Ink.surface))
        .overlay { Capsule().strokeBorder(on ? Ink.ember.opacity(0.6) : Ink.line) }
    }

    private func chipMenu(_ title: String, _ value: Set<String>, _ options: [(String, String)], _ set: @escaping (Set<String>) -> Void) -> some View {
        let names = options.filter { value.contains($0.0) }.map(\.1)
        return Menu {
            ForEach(options, id: \.0) { k, n in
                Button {
                    var v = value
                    if v.contains(k) { v.remove(k) } else { v.insert(k) }
                    withAnimation(.snappy) { set(v) }
                } label: {
                    if value.contains(k) { Label(n, systemImage: "checkmark") } else { Text(n) }
                }
            }
            if !value.isEmpty { Divider(); Button("Hepsi") { withAnimation(.snappy) { set([]) } } }
        } label: {
            chipLabel(names.isEmpty ? title : names.joined(separator: " · "), on: !value.isEmpty)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }

    private func toggleChip(_ title: String, _ symbol: String, _ on: Binding<Bool>) -> some View {
        Button { withAnimation(.snappy) { on.wrappedValue.toggle() } } label: {
            Label(title, systemImage: symbol)
                .font(.callout.weight(on.wrappedValue ? .semibold : .regular))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .foregroundStyle(on.wrappedValue ? Ink.ember : Ink.text)
                .background(Capsule().fill(on.wrappedValue ? Ink.ember.opacity(0.13) : Ink.surface))
                .overlay { Capsule().strokeBorder(on.wrappedValue ? Ink.ember.opacity(0.6) : Ink.line) }
        }
        .buttonStyle(.plain)
    }

    // MARK: List

    private var list: some View {
        VStack(alignment: .leading, spacing: 18) {
            if shown.isEmpty {
                ContentUnavailableView("Bu süzgeçte madde yok", systemImage: "line.3.horizontal.decrease",
                                       description: Text("Süzgeçleri gevşet ya da Temizle'ye bas."))
            }
            ForEach(groups, id: \.key) { g in
                VStack(alignment: .leading, spacing: 8) {
                    if !g.title.isEmpty {
                        HStack(spacing: 8) {
                            if let c = g.color { Circle().fill(c).frame(width: 10, height: 10) }
                            Text(g.title).font(Ink.serif(.title3, .bold))
                            Text("\(g.items.count)").font(.callout.monospacedDigit()).foregroundStyle(Ink.faint)
                        }
                        .padding(.top, 4)
                    }
                    ForEach(g.items) { m in
                        TatbikRow(m: m, program: t.program(m.program), selected: selection == m.id, showProgram: filter.group != "program")
                            .id(m.id)
                            .onTapGesture { selection = m.id; listFocused = true }
                            .contextMenu { TatbikMenu(m: m) }
                    }
                }
            }
            if !shown.isEmpty {
                Text("↑↓ ya da j k: madde değiştir · 1 2 3: durum · Esc: paneli kapat · ⌘K: git")
                    .font(.caption).foregroundStyle(Ink.faint).padding(.top, 6)
            }
        }
    }

    private var listTitle: String {
        if let v = allViews.first(where: { $0.id == activeView }) { return v.name }
        var s = filter.program.flatMap { t.program($0)?.ad } ?? "Bütün maddeler"
        if filter.statuses.count == 1, let st = TatbikStatus(rawValue: filter.statuses.first!) { s += " · \(st.name)" }
        return s
    }
}

/// Status shares of a set of items as one bar.
struct StackedBar: View {
    let items: [TatbikItem]
    var body: some View {
        GeometryReader { g in
            HStack(spacing: 2) {
                ForEach(TatbikStatus.allCases) { s in
                    let n = items.filter { $0.status == s }.count
                    if n > 0 {
                        Capsule().fill(s.color).frame(width: max(3, (g.size.width - 6) * Double(n) / Double(max(1, items.count))))
                    }
                }
            }
        }
    }
}

struct TatbikRow: View {
    let m: TatbikItem
    let program: TatbikProgram?
    var selected = false
    var showProgram = true
    @State private var hover = false
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: m.status.symbol).foregroundStyle(m.status.color).font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text(m.baslik).font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(m.status.isClosed ? Ink.secondary : Ink.text)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    if showProgram, let p = program {
                        Text(p.ad).font(.caption.weight(.semibold)).foregroundStyle(Ink.topic(p.renk ?? "")).lineLimit(1)
                    }
                    if !m.status.isClosed {
                        if let p = m.priorityName { Label(p, systemImage: "flag").font(.caption).foregroundStyle(m.oncelik == "yuksek" ? Ink.ember : Ink.secondary) }
                        if let s = m.sizeName { Text(s).font(.caption).foregroundStyle(Ink.secondary) }
                        if let a = m.ageDays { Text("\(a) gündür").font(.caption).foregroundStyle(a >= 14 ? Ink.gold : Ink.faint) }
                    }
                    if m.status == .tamam, let d = m.tarih { Text(d).font(.caption.monospacedDigit()).foregroundStyle(Ink.faint) }
                    if m.byUser { Label("senin işaretin", systemImage: "pencil").font(.caption).foregroundStyle(Ink.faint) }
                    if m.hasNotes { Label("\(m.notlar!.count)", systemImage: "text.bubble").font(.caption).foregroundStyle(Ink.faint) }
                }
            }
            Spacer(minLength: 0)
            Text(m.id).font(.caption.monospaced()).foregroundStyle(Ink.faint)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(selected ? Ink.ember.opacity(0.10) : hover ? Ink.surface2 : Ink.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? Ink.ember.opacity(0.7) : Ink.line, lineWidth: selected ? 1.5 : 1) }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

struct TatbikMenu: View {
    @EnvironmentObject var depo: Depo
    let m: TatbikItem
    var body: some View {
        ForEach(TatbikStatus.allCases) { s in
            Button { depo.tatbikDuzelt(m.id, "status", s.rawValue) } label: { Label(s.name, systemImage: s.symbol) }
                .disabled(m.status == s)
        }
        Divider()
        Button("“Bunu yap” istemini kopyala") { copyPrompt(m, depo) }
    }
}

@MainActor func copyPrompt(_ m: TatbikItem, _ depo: Depo) {
    let recs = m.sources.compactMap { id in depo.ogeler.first { $0.id == id } }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(m.prompt(depo.tatbik.program(m.program), recs), forType: .string)
}

// MARK: ⌘K palette

enum TatbikPick { case view(TatbikSavedView), program(String), item(String) }

struct TatbikPalette: View {
    @EnvironmentObject var depo: Depo
    let views: [TatbikSavedView]
    let pick: (TatbikPick) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var index = 0
    @FocusState private var focused: Bool

    private struct Row: Identifiable { let id: String; let symbol: String; let title: String; let detail: String; let color: Color; let pick: TatbikPick }

    private var rows: [Row] {
        let q = Arama.katla(text).split(separator: " ").map(String.init)
        func ok(_ s: String) -> Bool { let k = Arama.katla(s); return q.allSatisfy { k.contains($0) } }
        let t = depo.tatbik
        var r: [Row] = []
        r += views.filter { ok($0.name) }.map { Row(id: "v" + $0.id, symbol: $0.symbol, title: $0.name, detail: "görünüm", color: Ink.ember, pick: .view($0)) }
        r += t.programlar.filter { ok($0.ad) && !t.items(of: $0.id).isEmpty }.map { p in
            Row(id: "p" + p.id, symbol: "folder", title: p.ad, detail: "program · \(t.items(of: p.id).filter { !$0.status.isClosed }.count) açık",
                color: Ink.topic(p.renk ?? ""), pick: .program(p.id))
        }
        if !q.isEmpty {
            r += t.maddeler.filter { m in q.allSatisfy { m.searchText.contains($0) } }.sorted(by: TatbikView.smart).prefix(30).map { m in
                Row(id: "m" + m.id, symbol: m.status.symbol, title: m.baslik, detail: "\(t.program(m.program)?.ad ?? m.program) · \(m.id)",
                    color: m.status.color, pick: .item(m.id))
            }
        }
        return r
    }

    var body: some View {
        let l = rows
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.title3).foregroundStyle(Ink.secondary)
                TextField("Madde, program ya da görünüm…", text: $text).textFieldStyle(.plain).font(.title2)
                    .focused($focused)
                    .onSubmit { if l.indices.contains(index) { pick(l[index].pick) } }
                    .onKeyPress(.downArrow) { index = min(l.count - 1, index + 1); return .handled }
                    .onKeyPress(.upArrow) { index = max(0, index - 1); return .handled }
                    .onKeyPress(.escape) { dismiss(); return .handled }
            }
            .padding(16)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(l.enumerated()), id: \.element.id) { i, r in
                            HStack(spacing: 10) {
                                Image(systemName: r.symbol).foregroundStyle(r.color).frame(width: 20)
                                Text(r.title).font(.body.weight(.medium)).lineLimit(1)
                                Spacer()
                                Text(r.detail).font(.caption).foregroundStyle(Ink.secondary).lineLimit(1)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(i == index ? Ink.ember.opacity(0.14) : .clear))
                            .contentShape(Rectangle())
                            .onTapGesture { pick(r.pick) }
                            .id(r.id)
                        }
                        if l.isEmpty { Text("Bulunamadı.").foregroundStyle(Ink.secondary).padding(20) }
                    }
                    .padding(8)
                }
                .onChange(of: index) { _, i in if l.indices.contains(i) { proxy.scrollTo(l[i].id) } }
            }
            .frame(height: 380)
        }
        .frame(width: 620)
        .background(Ink.paper)
        .onAppear { focused = true }
        .onChange(of: text) { _, _ in index = 0 }
    }
}

// MARK: Detail (inspector)

struct TatbikDetail: View {
    @EnvironmentObject var depo: Depo
    @ObservedObject var player = Oynatici.shared
    let id: String
    @Binding var goRecord: String?
    var close: (() -> Void)?
    @State private var note = ""
    @State private var copied = false

    var body: some View {
        if let m = depo.tatbik.maddeler.first(where: { $0.id == id }) {
            let p = depo.tatbik.program(m.program)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(p?.ad ?? m.program) · \(m.id)").font(.callout.weight(.semibold)).foregroundStyle(Ink.topic(p?.renk ?? ""))
                            Spacer()
                            if let close {
                                Button(action: close) { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(Ink.faint) }
                                    .buttonStyle(.plain).help("Paneli kapat (Esc)")
                            }
                        }
                        Text(m.baslik).font(Ink.serif(.title, .bold)).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            if let x = m.priorityName { chip("öncelik \(x)") }
                            if let x = m.sizeName { chip(x) }
                            if let a = m.ageDays, !m.status.isClosed { chip("\(a) gündür bekliyor") }
                            chip(m.byUser ? "durum: senin işaretin" : "durum: Claude'un hükmü")
                        }
                    }
                    HStack(spacing: 6) {
                        ForEach(Array(TatbikStatus.allCases.enumerated()), id: \.element) { i, s in
                            let on = m.status == s
                            Button { withAnimation(.snappy) { depo.tatbikDuzelt(m.id, "status", s.rawValue) } } label: {
                                Label(s.short, systemImage: s.symbol).font(.callout.weight(.semibold))
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .foregroundStyle(on ? .white : s.color)
                                    .background(Capsule().fill(s.color.opacity(on ? 1 : 0.13)))
                            }
                            .buttonStyle(.plain)
                            .help("\(s.name) (\(i + 1))")
                        }
                    }
                    field("Ayrıntı", m.ayrinti)
                    field(m.status == .tamam ? "Kanıt" : "Şu an var olan", m.kanit)
                    field("Eksik", m.eksik)
                    field("Claude'un notu", m.gerekce)
                    if m.status == .tamam, let d = m.tarih { field("Tarih", d) }

                    Card(padding: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notların").font(.headline)
                            ForEach(m.notlar ?? [], id: \.self) { n in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(n.text).fixedSize(horizontal: false, vertical: true)
                                    Text("\(n.t.prefix(16).replacingOccurrences(of: "T", with: " ")) · \(n.device ?? "")").font(.caption2).foregroundStyle(Ink.faint)
                                }
                            }
                            HStack {
                                TextField("Not ekle (Claude bir sonraki incelemede okur)", text: $note).textFieldStyle(.roundedBorder)
                                    .onSubmit(addNote)
                                Button("Ekle", action: addNote).disabled(note.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                    }

                    Card(padding: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Kaynak kayıtlar").font(.headline)
                            ForEach(m.sources, id: \.self) { rid in
                                if let o = depo.ogeler.first(where: { $0.id == rid }) {
                                    HStack(spacing: 8) {
                                        Button { player.degistir(o) } label: {
                                            Image(systemName: player.calan == o.id ? "pause.circle.fill" : "play.circle")
                                        }.buttonStyle(.plain).font(.title3).help("Kaydı dinle")
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(o.baslik).lineLimit(2)
                                            Text("\(o.tarih.prefix(16).replacingOccurrences(of: "T", with: " ")) · \(minutesText(Int(o.sure)))\(o.isDone ? " · yapıldı" : "")")
                                                .font(.caption2).foregroundStyle(Ink.faint)
                                        }
                                        Spacer()
                                        Button("Kayda git") { goRecord = o.id }.controlSize(.small)
                                    }
                                } else {
                                    Text(rid).font(.caption.monospaced()).foregroundStyle(Ink.faint)
                                }
                            }
                        }
                    }

                    HStack {
                        Button { copyPrompt(m, depo); copied = true } label: {
                            Label(copied ? "Kopyalandı" : "“Bunu yap” istemini kopyala", systemImage: copied ? "checkmark" : "doc.on.clipboard")
                        }
                        .help("Claude Code'a yapıştır: iş, kanıt, eksik ve kaynak kayıtlar")
                        Button { KurultayBag.send(m.sources) } label: { Label("Kurultay'a sor", systemImage: "person.3.sequence") }
                        Spacer()
                        Button { obsidianAc(depo.kok.appendingPathComponent("Tatbik/TATBİK.md"), depo.vault) } label: {
                            Label("Obsidian'da aç", systemImage: "arrow.up.forward.app")
                        }
                    }
                }
                .padding(22)
            }
            .background(Ink.paper)
            .onChange(of: id) { _, _ in copied = false; note = "" }
        } else {
            ContentUnavailableView("Bir madde seç", systemImage: "checklist",
                                   description: Text("Durumunu değiştir, not düş, kaynak kaydı dinle ya da işi Claude'a götür."))
        }
    }

    private func addNote() {
        let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        depo.tatbikDuzelt(id, "note", n)
        note = ""
    }

    private func chip(_ s: String) -> some View {
        Text(s).font(.caption).padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Ink.surface2)).foregroundStyle(Ink.secondary)
    }

    @ViewBuilder private func field(_ title: String, _ v: String?) -> some View {
        if let v, !v.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.semibold)).foregroundStyle(Ink.secondary)
                Text(v).font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Under a record's detail: the Tatbik items made from it.
struct TatbikForRecord: View {
    @EnvironmentObject var depo: Depo
    let o: Oge
    var open: (String) -> Void = { _ in }
    var body: some View {
        let items = depo.tatbik.items(for: o.id)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("Tatbik · \(items.filter { $0.status.isClosed }.count)/\(items.count) tamamlandı", systemImage: "checklist").font(.headline)
                ForEach(items) { m in
                    HStack(spacing: 8) {
                        Image(systemName: m.status.symbol).foregroundStyle(m.status.color)
                        Text(m.baslik).lineLimit(2)
                        Spacer()
                        Text(depo.tatbik.program(m.program)?.ad ?? "").font(.caption2).foregroundStyle(Ink.faint).lineLimit(1)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { open(m.id) }
                    .contextMenu { TatbikMenu(m: m) }
                }
            }
            .padding(12)
            .background { RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)) }
        }
    }
}
