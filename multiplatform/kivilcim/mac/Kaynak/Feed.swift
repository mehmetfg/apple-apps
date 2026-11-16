// Merkez › Akış (2026-11-06): the day's chosen items, with an end. Each one is marked (it becomes a Dikkat mark) or passed.
// Nothing here counts, carries over or asks to be finished; an issue from another day is simply not shown.
import SwiftUI
import AppKit
import NaturalLanguage
import Translation

/// Turkish for the feed, with Apple's on-device translation: no Claude, no network once the language is installed.
/// Only the Mac translates; feed.py merges the result, so the phone gets Turkish without translating anything.
enum FeedTranslator {
    @MainActor private static var running = false

    /// Something to translate: the daily issue's items go to translations.json (feed.py merges them), the radar's
    /// stories and posts to radar-translations.json (radar.py merges them).
    private struct Job { let id: String; let title: String; let body: String; let radar: Bool }

    @MainActor private static func missing(_ depo: Depo) -> [Job] {
        var l: [Job] = depo.feed.isToday
            ? depo.feed.items.filter { $0.title_tr == nil && !$0.isSkipped }.map { Job(id: $0.id, title: $0.title, body: $0.body ?? $0.excerpt ?? "", radar: false) }
            : []
        l += depo.radar.stories.filter { $0.title_tr == nil && !done.contains($0.id) }.map { Job(id: $0.id, title: $0.title, body: $0.summary ?? "", radar: true) }
        l += depo.radar.posts.filter { $0.text_tr == nil && !done.contains($0.id) }.map { Job(id: $0.id, title: $0.text, body: "", radar: true) }
        return l
    }
    /// Radar items already handed over (a Turkish post stays untranslated and must not be asked again every tick).
    @MainActor private static var done = Set<String>()
    @MainActor static func hasWork(_ depo: Depo) -> Bool { !missing(depo).isEmpty }

    /// macOS 26: runs from the app's idle tick, window closed or not, once the Turkish package is installed.
    @available(macOS 26.0, *)
    @MainActor static func inBackground(_ depo: Depo) async {
        guard hasWork(depo), !running else { return }
        let en = Locale.Language(identifier: "en"), tr = Locale.Language(identifier: "tr")
        guard await LanguageAvailability().status(from: en, to: tr) == .installed else { return }
        await translate(TranslationSession(installedSource: en, target: tr), depo)
    }

    @available(macOS 15.0, *)
    @MainActor static func translate(_ session: TranslationSession, _ depo: Depo) async {
        guard !running else { return }
        running = true
        defer { running = false }
        var finished: [String: [String: String]] = [:]
        var requests: [TranslationSession.Request] = []
        var parts: [String: [String]] = [:]
        let jobs = missing(depo)
        let isRadar = Dictionary(jobs.map { ($0.id, $0.radar) }, uniquingKeysWith: { a, _ in a })
        for j in jobs {
            if j.radar { done.insert(j.id) }
            let r = NLLanguageRecognizer()
            r.processString(String((j.title + " " + j.body).prefix(1000)))
            guard r.dominantLanguage == .english else {       // a Turkish post on X needs no translation
                finished[j.id] = ["title": j.title, "body": j.body]
                continue
            }
            let paragraphs = j.body.split(separator: "\n").map(String.init)
            parts[j.id] = Array(repeating: "", count: paragraphs.count + 1)
            requests.append(.init(sourceText: j.title, clientIdentifier: "\(j.id)|0"))
            for (n, s) in paragraphs.enumerated() { requests.append(.init(sourceText: s, clientIdentifier: "\(j.id)|\(n + 1)")) }
        }
        do {
            if !requests.isEmpty {
                for try await response in session.translate(batch: requests) {
                    let key = (response.clientIdentifier ?? "").split(separator: "|").map(String.init)
                    if key.count == 2, let n = Int(key[1]) { parts[key[0]]?[n] = response.targetText }
                }
            }
        } catch {
            depo.gunluk("akış çevirisi: \(error)")
        }
        for (id, p) in parts where !(p.first ?? "").isEmpty && !p.contains("") {
            finished[id] = ["title": p[0], "body": p.dropFirst().joined(separator: "\n")]
        }
        guard !finished.isEmpty else { return }
        for radar in [false, true] {
            let mine = finished.filter { (isRadar[$0.key] ?? false) == radar }
            guard !mine.isEmpty else { continue }
            let u = depo.kok.appendingPathComponent(radar ? "Feed/radar-translations.json" : "Feed/translations.json")
            var all = (try? JSONDecoder().decode([String: [String: String]].self, from: Data(contentsOf: u))) ?? [:]
            all.merge(mine) { _, new in new }
            if radar {
                // only what is still on the page: the file does not grow without end
                let live = Set(depo.radar.stories.map(\.id) + depo.radar.posts.map(\.id))
                all = all.filter { live.contains($0.key) }
            }
            if let v = try? JSONEncoder().encode(all) { try? v.write(to: u, options: .atomic) }
        }
        depo.isle(hizli: true)
    }
}

/// The first time, this asks macOS to download Turkish (its own sheet); afterwards the idle tick does the work.
private struct TranslateOnOpen: ViewModifier {
    @ObservedObject var depo: Depo
    @State private var ticket = 0
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.modifier(Inner(depo: depo))
        } else {
            content
        }
    }
    @available(macOS 15.0, *)
    private struct Inner: ViewModifier {
        @ObservedObject var depo: Depo
        @State private var config: TranslationSession.Configuration?
        func body(content: Content) -> some View {
            content
                .onAppear { start() }
                .onChange(of: depo.feed.items.count) { _, _ in start() }
                .onChange(of: depo.radar.updated) { _, _ in start() }
                .translationTask(config) { session in
                    try? await session.prepareTranslation()
                    await FeedTranslator.translate(session, depo)
                }
        }
        @MainActor private func start() {
            guard FeedTranslator.hasWork(depo) else { return }
            if config == nil {
                config = .init(source: Locale.Language(identifier: "en"), target: Locale.Language(identifier: "tr"))
            } else {
                config?.invalidate()
            }
        }
    }
}

/// The picture of an item; a hairline of nothing when there is none or it does not load.
struct FeedPicture: View {
    let item: FeedItem
    var height: CGFloat = 170
    @State private var image: NSImage?

    var body: some View {
        // always a real view, even before the picture arrives: an empty one would never start its task
        Color.clear
            .frame(height: image == nil ? 1 : height).frame(maxWidth: .infinity)
            .overlay {
                if let image { Image(nsImage: image).resizable().scaledToFill() }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .task(id: item.image) {
                guard let u = item.imageLink, image == nil,
                      let (d, _) = try? await URLSession.shared.data(from: u) else { return }
                image = NSImage(data: d)
            }
    }
}

/// Akış (2026-11-11): three tabs on one finite page. Gündem = the day's important tech news, X = the posts worth seeing
/// from the people you follow, Seçki = the daily issue from Hacker News, Reddit and your likes.
enum FeedTab: String, CaseIterable, Identifiable {
    case radar, x, issue
    var id: String { rawValue }
    var name: String { switch self { case .radar: "Gündem"; case .x: "X'te takip ettiklerin"; case .issue: "Günün seçkisi" } }
    var symbol: String { switch self { case .radar: "globe"; case .x: "person.2.wave.2"; case .issue: "newspaper" } }
}

struct FeedView: View {
    @EnvironmentObject var depo: Depo
    @Binding var selection: String?
    @AppStorage("feedTab") private var tabRaw = FeedTab.radar.rawValue
    @AppStorage("feedTopic") private var topic = ""
    @State private var showSkipped = false
    @State private var showAccounts = false

    private var issue: FeedIssue { depo.feed }
    private var radar: RadarPage { depo.radar }
    private var tab: FeedTab { FeedTab(rawValue: tabRaw) ?? .radar }

    private var topicNames: [String: String] {
        var d = Dictionary((radar.topics + issue.topics).map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        d["tech"] = d["tech"] ?? "Teknoloji"
        return d
    }
    private var stories: [RadarStory] { radar.stories.filter { topic.isEmpty || $0.topic == topic } }
    private var posts: [RadarPost] { radar.posts.filter { topic.isEmpty || $0.topic == topic } }

    var body: some View {
        VStack(spacing: 0) {
            top.padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 12)
            Rectangle().fill(Ink.line).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch tab {
                    case .radar: radarTab
                    case .x: xTab
                    case .issue: issueTab
                    }
                }
                .padding(.horizontal, 28).padding(.vertical, 18)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Ink.paper)
        .modifier(TranslateOnOpen(depo: depo))
        .sheet(isPresented: $showAccounts) { RadarAccounts().environmentObject(depo) }
        .onKeyPress(.escape) { guard selection != nil else { return .ignored }; selection = nil; return .handled }
    }

    // MARK: Top: title, tabs, topic chips

    private var top: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Akış").font(.system(size: 40, weight: .bold, design: .serif))
                Text(subtitle).font(Ink.serif(.title3)).foregroundStyle(Ink.secondary).lineLimit(1)
                Spacer()
                Button { depo.radarScanX() } label: { Label("X'i tara", systemImage: "binoculars") }
                    .help("Chrome'da X'in Takip edilenler sekmesini açar; Kıvılcım eklentisi bir dakika okuyup öne çıkanları buraya getirir.")
                Button { depo.feedRefresh() } label: {
                    if depo.isleniyor { ProgressView().controlSize(.small) } else { Label("Güncelle", systemImage: "arrow.clockwise") }
                }
                .disabled(depo.isleniyor)
                .help("Gündem kaynaklarını ve günün seçkisini saatini beklemeden yeniden getirir.")
            }
            HStack(spacing: 8) {
                ForEach(FeedTab.allCases) { t in
                    let on = tab == t
                    Button { withAnimation(.snappy) { tabRaw = t.rawValue; selection = nil } } label: {
                        HStack(spacing: 6) {
                            Image(systemName: t.symbol)
                            Text(t.name)
                            Text("\(count(t))").monospacedDigit().foregroundStyle(on ? .white.opacity(0.85) : Ink.faint)
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .foregroundStyle(on ? .white : Ink.text)
                        .background(Capsule().fill(on ? Ink.ember : Ink.surface))
                        .overlay { Capsule().strokeBorder(on ? .clear : Ink.line) }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            if tab != .issue {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        topicChip("", "Hepsi")
                        ForEach(radar.topics, id: \.id) { t in topicChip(t.id, t.name) }
                        if radar.stories.contains(where: { $0.topic == "tech" }) && !radar.topics.contains(where: { $0.id == "tech" }) {
                            topicChip("tech", "Teknoloji")
                        }
                    }
                }
            }
        }
    }

    private func count(_ t: FeedTab) -> Int {
        switch t { case .radar: stories.count; case .x: posts.count; case .issue: issue.isToday ? issue.openCount : 0 }
    }

    private func topicChip(_ id: String, _ name: String) -> some View {
        let on = topic == id
        return Button { withAnimation(.snappy) { topic = id } } label: {
            Text(name).font(.callout.weight(on ? .semibold : .regular))
                .padding(.horizontal, 11).padding(.vertical, 5)
                .foregroundStyle(on ? Ink.ember : Ink.secondary)
                .background(Capsule().fill(on ? Ink.ember.opacity(0.13) : .clear))
                .overlay { Capsule().strokeBorder(on ? Ink.ember.opacity(0.6) : Ink.line) }
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        switch tab {
        case .radar:
            let t = radar.fetched.flatMap { ISO8601DateFormatter().date(from: $0) }
            return t.map { "kaynaklar \(agoText($0)) okundu" } ?? "yazılım ve teknolojide bugün"
        case .x:
            let t = radar.x_last_seen.flatMap { Zaman.coz($0) ?? ISO8601DateFormatter().date(from: $0) }
            return "\(radar.x_followed_count ?? 0) takip edilen hesap" + (t.map { " · X en son \(agoText($0)) okundu" } ?? "")
        case .issue:
            guard issue.isToday else { return "Sonu olan günlük seçki." }
            return "\(issue.items.count) madde" + (issue.openCount > 0 ? " · \(issue.openCount) kaldı" : "")
        }
    }

    // MARK: Gündem

    @ViewBuilder private var radarTab: some View {
        if radar.stories.isEmpty {
            ContentUnavailableView("Gündem henüz hazır değil", systemImage: "globe",
                                   description: Text("Kıvılcım bir sonraki tam işlemede kaynakları okur (2 saatte bir). Hemen istersen Güncelle'ye bas."))
                .padding(.top, 40)
        } else {
            let followed = stories.filter { !$0.followedShares.isEmpty }
            if !followed.isEmpty {
                sectionTitle("Takip ettiklerinin konuştuğu", "bubble.left.and.bubble.right.fill", Color(hex: "#1D9BF0"))
                ForEach(followed) { storyRow($0) }
                sectionTitle("Gündemin geri kalanı", "globe", Ink.secondary)
            }
            ForEach(stories.filter { $0.followedShares.isEmpty }) { storyRow($0) }
            if stories.isEmpty { Text("Bu konuda bugün haber yok.").foregroundStyle(Ink.secondary) }
            footer("Kaynak listesi Kıvılcım/Feed/radar-sources.json; istediğini ekle ya da kapat (\"off\": true).", radar.errors)
        }
    }

    private func storyRow(_ s: RadarStory) -> some View {
        RadarStoryCard(s: s, topicName: topicNames[s.topic] ?? s.topic, selected: selection == s.id)
            .onTapGesture { selection = s.id }
    }

    // MARK: X

    @ViewBuilder private var xTab: some View {
        if radar.posts.isEmpty {
            Card(padding: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("X'ten henüz bir şey gelmedi", systemImage: "person.2.wave.2").font(Ink.serif(.title2, .bold))
                    Text("Kıvılcım X'ten hiçbir şey çekmez: Chrome'daki Kıvılcım eklentisi, X'i okurken ekranından geçen postları not eder; takip ettiklerinin yazılım ve teknoloji postlarını burada sıralar.")
                        .fixedSize(horizontal: false, vertical: true)
                    Text("1. Chrome'da chrome://extensions › Kıvılcım › yeniden yükle (sürüm 1.2).\n2. Bu Mac'te bir kez: zsh …/kivilcim/chrome/host/kur.sh\n3. “X'i tara”ya bas: Takip edilenler bir dakika okunur, sonuç buraya düşer.")
                        .font(.callout).foregroundStyle(Ink.secondary).fixedSize(horizontal: false, vertical: true)
                    Button { depo.radarScanX() } label: { Label("X'i tara", systemImage: "binoculars") }.buttonStyle(.borderedProminent)
                }
            }
        } else {
            HStack {
                Text("Önce sabitlediklerin ve takip ettiklerin; konu sözcükleri ve etkileşime göre.").font(.callout).foregroundStyle(Ink.secondary)
                Spacer()
                Button { showAccounts = true } label: { Label("Hesaplar", systemImage: "person.crop.circle.badge.checkmark") }
            }
            ForEach(posts) { p in
                RadarPostCard(p: p, topicName: topicNames[p.topic] ?? p.topic, selected: selection == p.id)
                    .onTapGesture { selection = p.id }
            }
            if posts.isEmpty { Text("Bu konuda bugün post yok.").foregroundStyle(Ink.secondary) }
            footer("Liste son üç günde gördüklerinden yapılır; X'te ne kadar gezinirsen o kadar dolar.", nil)
        }
    }

    // MARK: Günün seçkisi (feed.py, unchanged in spirit)

    @ViewBuilder private var issueTab: some View {
        if issue.isToday {
            ForEach(issue.sections, id: \.topic.id) { s in
                VStack(alignment: .leading, spacing: 8) {
                    Text(s.topic.name).font(Ink.serif(.title3, .bold))
                    ForEach(s.items) { row($0) }
                }
            }
            ending
            skipped
            if let e = issue.errors, !e.isEmpty {
                Text("Bugün alınamayan kaynak: " + e.joined(separator: " · ")).font(.caption).foregroundStyle(Ink.faint)
            }
        } else {
            ContentUnavailableView("Bugünün baskısı \(issue.readyAt)'da", systemImage: "newspaper",
                                   description: Text("Hacker News, Reddit ve X'te beğendiklerinden en çok 10 madde. Kıvılcım açıkken hazırlanır."))
                .padding(.top, 40)
        }
    }

    private func sectionTitle(_ s: String, _ symbol: String, _ c: Color) -> some View {
        Label(s, systemImage: symbol).font(Ink.serif(.title3, .bold)).foregroundStyle(c).padding(.top, 6)
    }

    private func footer(_ s: String, _ errors: [String]?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(s)
            if let e = errors, !e.isEmpty { Text("Bu sefer alınamayan: " + e.joined(separator: " · ")) }
        }
        .font(.caption).foregroundStyle(Ink.faint).padding(.top, 8)
    }

    @ViewBuilder private var ending: some View {
        if issue.openCount == 0 && !issue.items.isEmpty {
            Card {
                Label("Bugünlük bu kadar. Yeni baskı yarın \(issue.readyAt)'da.", systemImage: "checkmark.seal")
                    .font(Ink.serif(.title3))
            }
        } else {
            Text("Listenin sonu burası. Yeni baskı yarın \(issue.readyAt)'da.")
                .font(.callout).foregroundStyle(Ink.faint)
        }
    }

    @ViewBuilder private var skipped: some View {
        if !issue.skipped.isEmpty {
            DisclosureGroup("Geçilenler · \(issue.skipped.count)", isExpanded: $showSkipped) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(issue.skipped) { i in
                        HStack {
                            Text(i.title).lineLimit(1).foregroundStyle(Ink.secondary)
                            Spacer()
                            Button("Geri al") { depo.feedTouch(i.id, "open") }.buttonStyle(.link)
                        }
                    }
                }
                .padding(.top, 6)
            }
            .font(.callout)
        }
    }

    private func row(_ i: FeedItem) -> some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(i.community + (i.numbers.map { " · " + $0 } ?? ""))
                    .font(.caption).foregroundStyle(Ink.secondary)
                FeedPicture(item: i)
                Text(i.shownTitle).font(Ink.serif(.title3, .semibold)).fixedSize(horizontal: false, vertical: true)
                if let o = i.originalTitle { Text(o).font(.caption).foregroundStyle(Ink.faint).lineLimit(2) }
                if !i.shownBody.isEmpty, i.shownBody != i.shownTitle {
                    Text(i.shownBody).font(.callout).foregroundStyle(Ink.secondary).lineLimit(3)
                }
                HStack(spacing: 10) {
                    Button("Aç") { i.link.map { _ = NSWorkspace.shared.open($0) } }
                    if i.isMarked {
                        Label("İşaretlendi", systemImage: "checkmark").font(.callout).foregroundStyle(Ink.gold)
                    } else {
                        Button("İşaretle") { depo.feedTouch(i.id, "marked") }
                        Button("Geç") { depo.feedTouch(i.id, "skipped") }
                    }
                }
                .padding(.top, 2)
            }
        }
        .overlay {
            if selection == i.id { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Ink.ember, lineWidth: 1.5) }
        }
        .contentShape(Rectangle())
        .onTapGesture { selection = i.id }
    }
}

struct FeedDetail: View {
    @EnvironmentObject var depo: Depo
    let id: String
    var close: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let close {
                    HStack {
                        Spacer()
                        Button(action: close) { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(Ink.faint) }
                            .buttonStyle(.plain).help("Paneli kapat (Esc)")
                    }
                }
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
        }
        .background(Ink.paper)
    }

    @ViewBuilder private var content: some View {
        if let s = depo.radar.stories.first(where: { $0.id == id }) {
            RadarStoryDetail(s: s)
        } else if let p = depo.radar.posts.first(where: { $0.id == id }) {
            RadarPostDetail(p: p)
        } else if let i = depo.feed.items.first(where: { $0.id == id }), depo.feed.isToday {
            VStack(alignment: .leading, spacing: 14) {
                Text(i.community + (i.author.map { $0.isEmpty ? "" : " · " + $0 } ?? ""))
                    .font(.callout).foregroundStyle(Ink.secondary)
                FeedPicture(item: i, height: 260)
                Text(i.shownTitle).font(Ink.serif(.title, .bold)).textSelection(.enabled)
                if let o = i.originalTitle { Text(o).font(.callout).foregroundStyle(Ink.secondary).textSelection(.enabled) }
                if let n = i.numbers { Text(n).font(.callout).foregroundStyle(Ink.secondary) }
                if !i.shownBody.isEmpty { Text(i.shownBody).font(Ink.serif(.body)).textSelection(.enabled) }
                if i.hasTurkishBody, let b = i.body {
                    DisclosureGroup("Özgün metin") { Text(b).font(.callout).foregroundStyle(Ink.secondary).textSelection(.enabled).padding(.top, 6) }
                        .font(.callout)
                }
                HStack(spacing: 10) {
                    Button("Bağlantıyı aç") { i.link.map { _ = NSWorkspace.shared.open($0) } }
                        .buttonStyle(.borderedProminent)
                    if let d = i.discussionLink {
                        Button("Tartışmayı aç") { NSWorkspace.shared.open(d) }
                    }
                }
                if i.isMarked {
                    Label("İşaretlendi: notu Dikkat'te.", systemImage: "checkmark").foregroundStyle(Ink.gold)
                } else {
                    HStack(spacing: 10) {
                        Button("İşaretle") { depo.feedTouch(i.id, "marked") }
                        Button(i.isSkipped ? "Geri al" : "Geç") { depo.feedTouch(i.id, i.isSkipped ? "open" : "skipped") }
                    }
                }
            }
        } else {
            ContentUnavailableView("Bir madde seç", systemImage: "newspaper",
                                   description: Text("İşaretlediğin madde Dikkat'e not olarak geçer. Geçtiğin madde yarın kalkar."))
        }
    }
}
