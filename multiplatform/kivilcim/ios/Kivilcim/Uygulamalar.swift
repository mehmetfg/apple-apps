// Uygulamalar (2026-11-08): every app the user built, one by one and all together — what it is for, what is still
// open, what was said about it — and how many there are. The Mac builds it (apps.py → Uygulamalar/apps.json, the
// registry Uygulamalar/kayit.json is hand-editable); the phone reads it, records a voice note for an app, and ties a
// record to an app with an "app" event like every other edit.
import SwiftUI

// MARK: Model

struct AppsFile: Decodable, Sendable {
    var generated: String = ""
    var summary = AppsSummary()
    var apps: [AppEntry] = []
    static let empty = AppsFile()

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        generated = (try? c.decode(String.self, forKey: .generated)) ?? ""
        summary = (try? c.decode(AppsSummary.self, forKey: .summary)) ?? AppsSummary()
        apps = (try? c.decode([AppEntry].self, forKey: .apps)) ?? []
    }
    enum CodingKeys: String, CodingKey { case generated, summary, apps }

    func app(_ id: String) -> AppEntry? { apps.first { $0.id == id } }
}

struct AppsSummary: Decodable, Sendable {
    var total = 0, active = 0, retired = 0, paid = 0, ideas = 0, open_items = 0, unlinked_mentions = 0
    var by_platform: [String: Int] = [:]
    var by_month: [MonthCount] = []
    var first = ""

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        func i(_ k: CodingKeys) -> Int { (try? c.decode(Int.self, forKey: k)) ?? 0 }
        total = i(.total); active = i(.active); retired = i(.retired); paid = i(.paid); ideas = i(.ideas)
        open_items = i(.open_items); unlinked_mentions = i(.unlinked_mentions)
        by_platform = (try? c.decode([String: Int].self, forKey: .by_platform)) ?? [:]
        by_month = (try? c.decode([MonthCount].self, forKey: .by_month)) ?? []
        first = (try? c.decode(String.self, forKey: .first)) ?? ""
    }
    enum CodingKeys: String, CodingKey { case total, active, retired, paid, ideas, open_items, unlinked_mentions, by_platform, by_month, first }
}

struct MonthCount: Decodable, Hashable, Sendable { var month: String; var count: Int }

/// An app idea heard in a recording (fikirler.py): a new app's idea, or a feature for an app that exists.
struct AppIdea: Decodable, Hashable, Sendable, Identifiable {
    var title = "", text = "", quote = "", record = "", date = ""
    var id: String { record + "|" + text }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        func s(_ k: CodingKeys) -> String { (try? c.decode(String.self, forKey: k)) ?? "" }
        title = s(.title); text = s(.text); quote = s(.quote); record = s(.record); date = s(.date)
    }
    enum CodingKeys: String, CodingKey { case title, text, quote, record, date }
}

struct AppEntry: Decodable, Identifiable, Hashable, Sendable {
    var id: String
    var name = "", platform = "", purpose = "", status = "active", commercial = "", store_note = "", note = ""
    var path = "", started = "", last_activity = ""
    var files = 0, worklog = 0
    var doc_gaps: [String] = []
    var open: [String] = []
    var done: [String] = []
    var talk: [String] = []
    var ideas: [AppIdea] = []

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        func s(_ k: CodingKeys) -> String { (try? c.decode(String.self, forKey: k)) ?? "" }
        func a(_ k: CodingKeys) -> [String] { (try? c.decode([String].self, forKey: k)) ?? [] }
        id = try c.decode(String.self, forKey: .id)
        name = s(.name); platform = s(.platform); purpose = s(.purpose); commercial = s(.commercial)
        store_note = s(.store_note); note = s(.note); path = s(.path); started = s(.started); last_activity = s(.last_activity)
        status = (try? c.decode(String.self, forKey: .status)) ?? "active"
        files = (try? c.decode(Int.self, forKey: .files)) ?? 0
        worklog = (try? c.decode(Int.self, forKey: .worklog)) ?? 0
        doc_gaps = a(.doc_gaps); open = a(.open); done = a(.done); talk = a(.talk)
        ideas = (try? c.decode([AppIdea].self, forKey: .ideas)) ?? []
    }
    enum CodingKeys: String, CodingKey {
        case id, name, platform, purpose, status, commercial, store_note, note, path, started, last_activity, files, worklog
        case doc_gaps, open, done, talk, ideas
    }

    var isPaid: Bool { commercial == "paid" }
    var statusName: String {
        switch status { case "paused": "Beklemede"; case "retired": "Emekli"; case "idea": "Fikir"; default: "Aktif" }
    }
    var statusColor: Color {
        switch status { case "paused": .orange; case "retired": .gray; case "idea": .purple; default: .green }
    }
    var symbol: String {
        if platform.contains("Android") { return "tv" }
        if platform.hasPrefix("Web") { return "globe" }
        if platform == "macOS" { return "laptopcomputer" }
        if platform.contains("macOS") { return "laptopcomputer.and.iphone" }
        return "iphone"
    }
    /// The short name before a bracketed alias: "VocuTeach (Aşina)" → "VocuTeach".
    var short: String { name.components(separatedBy: " (").first ?? name }
}

/// kivilcim://kaydet?app=<id> — a voice note about an app, recorded from its page.
func appTalkURL(_ app: String) -> URL? {
    var c = URLComponents(string: "kivilcim://kaydet")
    c?.queryItems = [URLQueryItem(name: "app", value: app)]
    return c?.url
}

private func serif(_ s: Font.TextStyle, _ w: Font.Weight = .regular) -> Font { .system(s, design: .serif).weight(w) }
private let appsColor = Color(hex: "#2F6FEB")

extension TelefonDeposu {
    /// Records tied to an app: the Mac's lists, plus this phone's own "app" edits it has not merged yet.
    func appItems(_ a: AppEntry) -> (open: [Oge], done: [Oge], talk: [Oge]) {
        let mac = Set(a.open + a.done + a.talk)
        var mine = ogeler.filter { $0.app == a.id || (mac.contains($0.id) && !($0.app_source == "elle" && $0.app != a.id)) }
        mine.sort { $0.zaman > $1.zaman }
        let work = mine.filter { !$0.isJournal && $0.kind != "isaret" && ($0.app == a.id) }
        let open = work.filter { !$0.isDone }.sorted { ($0.priority, $0.zaman) > ($1.priority, $1.zaman) }
        let done = work.filter(\.isDone)
        let talk = mine.filter { !work.contains($0) }
        return (open, done, talk)
    }
    func appName(_ id: String) -> String { apps.app(id)?.short ?? id }
}

// MARK: Merkez card

struct UygulamalarKarti: View {
    @EnvironmentObject var depo: TelefonDeposu
    var body: some View {
        let s = depo.apps.summary
        let busy = depo.apps.apps.map { ($0, depo.appItems($0).open.count) }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(3)
        MCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Uygulamalar", systemImage: "app.badge").font(.headline).foregroundStyle(appsColor)
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                if depo.apps.apps.isEmpty {
                    Text("Mac'te Kıvılcım işleyince uygulamaların listesi burada görünür.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(s.total)").font(serif(.largeTitle, .bold)).monospacedDigit()
                        Text("uygulama").font(serif(.title3))
                        Spacer()
                        if !s.first.isEmpty { Text("ilk iz \(dayText(s.first))").font(.caption).foregroundStyle(.secondary) }
                    }
                    HStack(spacing: 8) {
                        stat("\(s.active)", "aktif", .green)
                        stat("\(s.paid)", "ücretli", .orange)
                        stat("\(s.open_items)", "açık iş", .kivilcim)
                        stat("\(s.ideas)", "yeni fikir", .purple)
                    }
                    if !busy.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("En çok açık işi olan").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            ForEach(Array(busy), id: \.0.id) { a, n in
                                HStack(spacing: 8) {
                                    Image(systemName: a.symbol).foregroundStyle(appsColor).frame(width: 18)
                                    Text(a.short).font(.subheadline.weight(.medium)).lineLimit(1)
                                    Spacer()
                                    Text("\(n) açık").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func stat(_ v: String, _ t: String, _ c: Color) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.headline.monospacedDigit())
            Text(t).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(c.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// "2026-10-02" → "2 Eki 2026"
func dayText(_ iso: String) -> String {
    guard let d = Zaman.coz(iso + "T00:00:00") else { return iso }
    return d.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "tr_TR")))
}

// MARK: All apps

struct UygulamalarSayfasi: View {
    @EnvironmentObject var depo: TelefonDeposu
    enum Filter: String, CaseIterable, Identifiable {
        case all = "Hepsi", open = "Açık işi var", ideas = "Fikirler", paid = "Ücretli", retired = "Emekli"
        var id: String { rawValue }
    }
    enum Order: String, CaseIterable, Identifiable {
        case recent = "Son çalışılan", started = "Başlangıç", open = "Açık iş", name = "Ad"
        var id: String { rawValue }
    }
    @State private var filter = Filter.all
    @State private var order = Order.recent
    @State private var query = ""

    var body: some View {
        let s = depo.apps.summary
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(s.total)").font(serif(.largeTitle, .bold)).monospacedDigit()
                        Text("uygulama yaptın").font(serif(.title3))
                    }
                    if !s.first.isEmpty {
                        Text("İlk iz \(dayText(s.first)) · \(s.active) aktif · \(s.paid) ücretli · \(s.retired) emekli")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    MonthBars(months: s.by_month)
                    FlowChips(items: s.by_platform.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" })
                    if s.unlinked_mentions > 0 {
                        Text("\(s.unlinked_mentions) kayıtta “uygulama” geçiyor ama hiçbir uygulamaya bağlı değil; kaydın sayfasında Uygulama menüsünden bağlayabilirsin.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                Picker("Süzgeç", selection: $filter) { ForEach(Filter.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }
            Section {
                ForEach(list) { a in
                    NavigationLink(value: MerkezRota.uygulama(a.id)) { AppRow(a: a, open: depo.appItems(a).open.count) }
                }
            } header: {
                HStack {
                    Text("\(list.count) uygulama")
                    Spacer()
                    Menu { Picker("Sıra", selection: $order) { ForEach(Order.allCases) { Text($0.rawValue).tag($0) } } }
                        label: { Label(order.rawValue, systemImage: "arrow.up.arrow.down").font(.caption) }
                }
            }
        }
        .searchable(text: $query, prompt: "Uygulama ara")
        .navigationTitle("Uygulamalar")
        .refreshable { await depo.gonder() }
    }

    private var list: [AppEntry] {
        var l = depo.apps.apps
        switch filter {
        case .all: break
        case .open: l = l.filter { !depo.appItems($0).open.isEmpty }
        case .paid: l = l.filter(\.isPaid)
        case .retired: l = l.filter { $0.status == "retired" }
        case .ideas: l = l.filter { $0.status == "idea" || !$0.ideas.isEmpty }
        }
        let q = Arama.katla(query)
        if !q.isEmpty { l = l.filter { Arama.katla($0.name + " " + $0.purpose + " " + $0.platform).contains(q) } }
        switch order {
        case .recent: l.sort { $0.last_activity > $1.last_activity }
        case .started: l.sort { $0.started < $1.started }
        case .open: l.sort { depo.appItems($0).open.count > depo.appItems($1).open.count }
        case .name: l.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        }
        return l
    }
}

struct AppRow: View {
    let a: AppEntry
    let open: Int
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: a.symbol).font(.title3).foregroundStyle(appsColor).frame(width: 28).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(a.name).font(serif(.body, .semibold)).lineLimit(1)
                    if a.isPaid { Image(systemName: "dollarsign.circle.fill").foregroundStyle(.orange).font(.caption) }
                    if a.status != "active" { Text(a.statusName).font(.caption2.weight(.semibold)).foregroundStyle(a.statusColor) }
                }
                if !a.purpose.isEmpty { Text(a.purpose).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                HStack(spacing: 8) {
                    Text(a.platform)
                    if !a.last_activity.isEmpty { Text("son \(dayText(a.last_activity))") }
                }
                .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            if open > 0 {
                Text("\(open)").font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 2).background(Color.kivilcim, in: Capsule())
            }
        }
        .padding(.vertical, 2)
    }
}

/// How many apps were started each month: one bar per month.
struct MonthBars: View {
    let months: [MonthCount]
    var body: some View {
        let top = max(1, months.map(\.count).max() ?? 1)
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(months, id: \.month) { m in
                VStack(spacing: 4) {
                    Text("\(m.count)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 4).fill(appsColor.gradient)
                        .frame(width: 34, height: max(6, 70 * CGFloat(m.count) / CGFloat(top)))
                    Text(monthName(m.month)).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
    private func monthName(_ ym: String) -> String {
        guard let d = Zaman.coz(ym + "-01T00:00:00") else { return ym }
        return d.formatted(.dateTime.month(.abbreviated).locale(Locale(identifier: "tr_TR")))
    }
}

struct FlowChips: View {
    let items: [String]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { t in
                    Text(t).font(.caption).padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                }
            }
        }
    }
}

// MARK: One app

struct UygulamaSayfasi: View {
    @EnvironmentObject var depo: TelefonDeposu
    @Environment(\.openURL) private var openURL
    let id: String
    @State private var showDone = false

    var body: some View {
        if let a = depo.apps.app(id) {
            let items = depo.appItems(a)
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: a.symbol).foregroundStyle(appsColor)
                            Text(a.platform).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(a.statusName).font(.caption.weight(.semibold)).foregroundStyle(a.statusColor)
                            if a.isPaid { Label("Ücretli", systemImage: "dollarsign.circle").font(.caption.weight(.semibold)).foregroundStyle(.orange) }
                        }
                        Text(a.name).font(serif(.largeTitle, .bold))
                        if !a.purpose.isEmpty { Text(a.purpose).font(serif(.body)) }
                        Text(facts(a, items.open.count, items.done.count)).font(.footnote).foregroundStyle(.secondary)
                        Button { appTalkURL(a.id).map { openURL($0) } } label: {
                            Label("Bu uygulama için sesli not", systemImage: "mic.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(.kivilcim).padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                }
                if !a.store_note.isEmpty || !a.note.isEmpty {
                    Section("Durum") {
                        if !a.store_note.isEmpty { Label(a.store_note, systemImage: "bag").font(.subheadline) }
                        if !a.note.isEmpty { Text(a.note).font(.subheadline) }
                    }
                }
                Section {
                    if items.open.isEmpty {
                        Text("Söylenmiş açık iş yok. Eksik ya da istek aklına gelince yukarıdaki düğmeyle söyle.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(items.open) { o in NavigationLink(value: o.id) { ItemRow(o: o) } }
                } header: { Text("Yapılacaklar · eksikler (\(items.open.count))") }
                if !a.ideas.isEmpty {
                    Section {
                        ForEach(a.ideas) { x in
                            NavigationLink(value: x.record) {
                                VStack(alignment: .leading, spacing: 3) {
                                    if !x.title.isEmpty && a.status != "idea" {
                                        Text(x.title).font(.subheadline.weight(.semibold))
                                    }
                                    Text(x.text).font(.subheadline)
                                    Text(dayText(x.date)).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: { Text("Kayıtlarda geçen fikirler (\(a.ideas.count))") }
                    footer: { Text("Mac, sesli kayıtlardan uygulama fikirlerini kendiliğinden ayıklar; dokununca kayıt açılır.") }
                }
                if !a.doc_gaps.isEmpty {
                    Section {
                        ForEach(a.doc_gaps, id: \.self) { g in
                            Label(g, systemImage: "doc.text.magnifyingglass").font(.subheadline)
                        }
                    } header: { Text("Belgelerinde açık kalan") } footer: { Text("Projenin README, brief ve seyir notlarından.") }
                }
                if !items.done.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $showDone) {
                            ForEach(items.done) { o in NavigationLink(value: o.id) { ItemRow(o: o) } }
                        } label: { Text("Yapıldı (\(items.done.count))").font(.subheadline.weight(.semibold)) }
                    }
                }
                if !items.talk.isEmpty {
                    Section("Hakkında konuştukların (\(items.talk.count))") {
                        ForEach(items.talk) { o in
                            NavigationLink(value: o.id) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(o.baslik).font(.subheadline.weight(.medium)).lineLimit(2)
                                    Text("\(o.isJournal ? "Sesli günlük" : "Kıvılcım") · \(Zaman.gunBasligi(o.zaman))")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Uygulama bulunamadı", systemImage: "app.dashed")
        }
    }

    private func facts(_ a: AppEntry, _ open: Int, _ done: Int) -> String {
        var p: [String] = []
        if !a.started.isEmpty { p.append("ilk iz \(dayText(a.started))") }
        if !a.last_activity.isEmpty { p.append("son \(dayText(a.last_activity))") }
        if a.worklog > 0 { p.append("\(a.worklog) çalışma kaydı") }
        p.append("\(open) açık · \(done) yapıldı")
        return p.joined(separator: " · ")
    }
}

// MARK: Tie a record to an app (record page)

struct AppLinkMenu: View {
    @EnvironmentObject var depo: TelefonDeposu
    let o: Oge
    var body: some View {
        let current = o.app.isEmpty ? nil : depo.apps.app(o.app)
        Menu {
            if !o.app.isEmpty {
                Button(role: .destructive) { depo.duzelt(o, "app", "-") } label: { Label("Uygulamadan ayır", systemImage: "xmark.circle") }
            }
            ForEach(depo.apps.apps.sorted { $0.last_activity > $1.last_activity }) { a in
                Button { depo.duzelt(o, "app", a.id) } label: {
                    Label(a.name, systemImage: a.id == o.app ? "checkmark" : a.symbol)
                }
            }
        } label: {
            Label(current.map { "Uygulama: \($0.short)" } ?? (o.app.isEmpty ? "Uygulamaya bağla" : "Uygulama: \(o.app)"),
                  systemImage: "app.badge")
                .font(.subheadline.weight(.medium))
        }
        .buttonStyle(.bordered).tint(appsColor)
        .disabled(depo.apps.apps.isEmpty)
    }
}
