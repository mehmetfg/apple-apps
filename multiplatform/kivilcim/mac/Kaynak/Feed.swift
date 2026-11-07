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

    @MainActor private static func missing(_ depo: Depo) -> [FeedItem] {
        depo.feed.isToday ? depo.feed.items.filter { $0.title_tr == nil && !$0.isSkipped } : []
    }
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
        var done: [String: [String: String]] = [:]
        var requests: [TranslationSession.Request] = []
        var parts: [String: [String]] = [:]
        for i in missing(depo) {
            let text = i.title + " " + (i.body ?? i.excerpt ?? "")
            let r = NLLanguageRecognizer()
            r.processString(String(text.prefix(1000)))
            guard r.dominantLanguage == .english else {       // a Turkish post on X needs no translation
                done[i.id] = ["title": i.title, "body": i.body ?? ""]
                continue
            }
            let paragraphs = (i.body ?? i.excerpt ?? "").split(separator: "\n").map(String.init)
            parts[i.id] = Array(repeating: "", count: paragraphs.count + 1)
            requests.append(.init(sourceText: i.title, clientIdentifier: "\(i.id)|0"))
            for (n, s) in paragraphs.enumerated() { requests.append(.init(sourceText: s, clientIdentifier: "\(i.id)|\(n + 1)")) }
        }
        do {
            for try await response in session.translate(batch: requests) {
                let key = (response.clientIdentifier ?? "").split(separator: "|").map(String.init)
                if key.count == 2, let n = Int(key[1]) { parts[key[0]]?[n] = response.targetText }
            }
        } catch {
            depo.gunluk("akış çevirisi: \(error)")
        }
        for (id, p) in parts where !(p.first ?? "").isEmpty && !p.contains("") {
            done[id] = ["title": p[0], "body": p.dropFirst().joined(separator: "\n")]
        }
        guard !done.isEmpty else { return }
        let u = depo.kok.appendingPathComponent("Feed/translations.json")
        var all = (try? JSONDecoder().decode([String: [String: String]].self, from: Data(contentsOf: u))) ?? [:]
        all.merge(done) { _, new in new }
        if let v = try? JSONEncoder().encode(all) { try? v.write(to: u, options: .atomic) }
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

struct FeedView: View {
    @EnvironmentObject var depo: Depo
    @Binding var selection: String?
    @State private var showSkipped = false

    private var issue: FeedIssue { depo.feed }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Akış").font(Ink.serif(.largeTitle, .bold))
                    HStack {
                        Text(subtitle).font(Ink.serif(.title3)).foregroundStyle(Ink.secondary)
                        Spacer()
                        Button { depo.feedRefresh() } label: {
                            if depo.isleniyor { ProgressView().controlSize(.small) } else { Label("Güncelle", systemImage: "arrow.clockwise") }
                        }
                        .disabled(depo.isleniyor)
                        .help("Baskıyı saatini beklemeden getirir, eksik görsel, ayrıntı ve konuları tamamlar. Baskıyı değiştirmez.")
                    }
                }
                if issue.isToday {
                    ForEach(issue.sections, id: \.topic.id) { s in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(s.topic.name).font(.headline)
                            ForEach(s.items) { row($0) }
                        }
                    }
                    ending
                    skipped
                    if let e = issue.errors, !e.isEmpty {
                        Text("Bugün alınamayan kaynak: " + e.joined(separator: " · "))
                            .font(.caption).foregroundStyle(Ink.faint)
                    }
                } else {
                    ContentUnavailableView("Bugünün baskısı \(issue.readyAt)'da", systemImage: "newspaper",
                                           description: Text("Hacker News, Reddit ve X'te beğendiklerinden en çok 10 madde. Kıvılcım açıkken hazırlanır."))
                        .padding(.top, 40)
                }
            }
            .padding(24)
        }
        .background(Ink.paper)
        .modifier(TranslateOnOpen(depo: depo))
    }

    private var subtitle: String {
        guard issue.isToday else { return "Sonu olan günlük seçki." }
        return "Bugünün seçkisi · \(issue.items.count) madde" + (issue.openCount > 0 ? " · \(issue.openCount) kaldı" : "")
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

    var body: some View {
        if let i = depo.feed.items.first(where: { $0.id == id }), depo.feed.isToday {
            ScrollView {
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .background(Ink.paper)
        } else {
            ContentUnavailableView("Bir madde seç", systemImage: "newspaper",
                                   description: Text("İşaretlediğin madde Dikkat'e not olarak geçer. Geçtiğin madde yarın kalkar."))
        }
    }
}
