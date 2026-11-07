// Kıvılcım as the centre of spoken production (2026-11-04): Yön (what did I talk about, where is my mind going),
// Konular (one page per book/topic: every voice note from Kıvılcım, Teoria and Wise Path with its context),
// Günlük (long talks day by day, transcript with minute stamps, jump to any minute).
import SwiftUI
import AppKit
import Charts

// MARK: Yön

struct DirectionView: View {
    @EnvironmentObject var depo: Depo
    @EnvironmentObject var k: Kaydedici
    @Binding var topic: String?
    @Binding var filter: Suzgec?

    private var weeks: [DirectionWeek] { depo.links.direction.weeks }
    private var thisWeek: DirectionWeek? { weeks.last }
    private var lastWeek: DirectionWeek? { weeks.count > 1 ? weeks[weeks.count - 2] : nil }

    /// The five topics with most speech in 28 days get a colour; the rest is "Diğer", untied speech "Genel".
    private var top: [String] {
        var sum: [String: Int] = [:]
        for d in depo.links.direction.days { for (t, s) in d.topics where !t.hasPrefix("genel:") { sum[t, default: 0] += s } }
        return sum.sorted { $0.value > $1.value }.prefix(5).map(\.key)
    }

    private struct Bar: Identifiable { let id = UUID(); let day: Date; let group: String; let minutes: Double }
    private var bars: [Bar] {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        var r: [Bar] = []
        for d in depo.links.direction.days {
            guard let day = f.date(from: d.day) else { continue }
            var g: [String: Int] = [:]
            for (t, s) in d.topics {
                let name = t.hasPrefix("genel:") ? "Genel" : top.contains(t) ? depo.topicName(t) : "Diğer kitaplar"
                g[name, default: 0] += s
            }
            for (n, s) in g where s > 0 { r.append(Bar(day: day, group: n, minutes: Double(s) / 60)) }
        }
        return r
    }

    private var weekTopics: [(LinkTopic, Int)] {
        guard let w = thisWeek else { return [] }
        return w.topics.compactMap { id, s in depo.links.topic(id).map { ($0, s) } }.sorted { $0.1 > $1.1 }
    }

    private var weekGeneral: [(String, Int)] {
        guard let w = thisWeek else { return [] }
        return w.topics.filter { $0.key.hasPrefix("genel:") }
            .map { (depo.siniflar.alan(String($0.key.dropFirst(6))).ad, $0.value) }.sorted { $0.1 > $1.1 }
    }

    /// Books read in the last two weeks that nothing was said about in the same time. Shown, never counted as debt.
    private var silent: [RecentBook] {
        let cut = Calendar.current.date(byAdding: .day, value: -14, to: Date())!
        return depo.links.recent_books.filter { b in
            guard let d = Zaman.coz(b.last + "T00:00:00"), d > cut else { return false }
            return !(depo.links.topic(b.id)?.entries.contains { $0.when > cut } ?? false)
        }.prefix(5).map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Yön").font(Ink.serif(.largeTitle, .bold))
                    Text("Sesle ve yazıyla ne ürettin, zihnin nereye gidiyor. Kıvılcım, Teoria ve Wise Path birlikte.")
                        .font(Ink.serif(.title3)).foregroundStyle(Ink.secondary)
                }
                HStack(spacing: 12) {
                    stat("Bu hafta", minutesText(thisWeek?.seconds ?? 0), delta)
                    stat("Kitap ve konu", "\(weekTopics.count)", weekTopics.first.map { "en çok \($0.0.short)" } ?? "henüz bağ yok")
                    stat("Uzun konuşma", "\(depo.ogeler.filter { $0.isJournal && Date().timeIntervalSince($0.zaman) < 7 * 86400 }.count)",
                         "son 7 gün")
                    stat("Bütün üretim", "\(depo.links.topics.reduce(0) { $0 + $1.count })", "\(depo.links.topics.count) konuya bağlı")
                }
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Son 28 gün · dakika").font(.headline)
                        if bars.isEmpty {
                            Text("Henüz konuşma yok.").foregroundStyle(Ink.secondary)
                        } else {
                            Chart(bars) { b in
                                BarMark(x: .value("Gün", b.day, unit: .day), y: .value("dk", b.minutes))
                                    .foregroundStyle(by: .value("Konu", b.group))
                                    .cornerRadius(2)
                            }
                            .chartForegroundStyleScale(domain: groupDomain, range: groupColors)
                            .chartLegend(position: .bottom, alignment: .leading)
                            .frame(height: 190)
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Bu hafta zihnin").font(.headline)
                        if weekTopics.isEmpty && weekGeneral.isEmpty {
                            Text("Bu hafta konuşma yok. \(KisayolSecenegi.secili.ad) fikir, ⌃⌥G uzun konuşma.").foregroundStyle(Ink.secondary)
                        }
                        let maxS = max(1, (weekTopics.map(\.1) + weekGeneral.map(\.1)).max() ?? 1)
                        ForEach(weekTopics, id: \.0.id) { t, s in
                            Button { topic = t.id; filter = .konular } label: {
                                row(t.short, t.name, s, maxS, Ink.topic(t.color))
                            }.buttonStyle(.plain)
                        }
                        ForEach(weekGeneral, id: \.0) { n, s in row(n, "kitaba bağlanmamış konuşma", s, maxS, Ink.faint) }
                    }
                }
                if !silent.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Okudun, henüz konuşmadın").font(.headline)
                            Text("Son iki haftada okuduğun ama üzerine bir şey söylemediğin kitaplar.").font(.caption).foregroundStyle(Ink.secondary)
                            ForEach(silent) { b in
                                HStack {
                                    Text(b.short).font(Ink.serif(.body, .semibold))
                                    if b.name != b.short { Text(b.name).font(.caption).foregroundStyle(Ink.secondary).lineLimit(1) }
                                    Spacer()
                                    Button { k.topic = b.id; k.baslat(.spark) } label: { Label("Konuş", systemImage: "mic.fill") }
                                        .controlSize(.small).disabled(k.kayitta)
                                }
                            }
                        }
                    }
                }
            }
            .padding(28).frame(maxWidth: 900, alignment: .leading)
        }
        .background(Ink.paper)
    }

    private var groupDomain: [String] { top.map { depo.topicName($0) } + ["Diğer kitaplar", "Genel"] }
    private var groupColors: [Color] {
        let pal: [Color] = [Ink.ember, Color(hex: "#2F6FEB"), Color(hex: "#23915E"), Ink.gold, Color(hex: "#C2416B")]
        return top.indices.map { pal[$0 % pal.count] } + [Color(hex: "#8E8C86"), Color(hex: "#C9C5BB")]
    }

    private var delta: String {
        guard let a = thisWeek?.seconds, let b = lastWeek?.seconds, b > 0 else { return "geçen hafta yok" }
        let d = a - b
        return (d >= 0 ? "+" : "−") + minutesText(abs(d)) + " geçen haftaya göre"
    }

    private func stat(_ title: String, _ value: String, _ sub: String) -> some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption.weight(.medium)).foregroundStyle(Ink.secondary)
                Text(value).font(Ink.serif(.title, .bold)).monospacedDigit()
                Text(sub).font(.caption2).foregroundStyle(Ink.faint).lineLimit(1)
            }
        }
    }

    private func row(_ title: String, _ sub: String, _ s: Int, _ maxS: Int, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(Ink.serif(.body, .semibold))
                Text(sub).font(.caption).foregroundStyle(Ink.secondary).lineLimit(1)
                Spacer()
                Text(minutesText(s)).font(.callout.monospacedDigit()).foregroundStyle(Ink.secondary)
            }
            GeometryReader { g in
                Capsule().fill(c.opacity(0.85)).frame(width: max(4, g.size.width * CGFloat(s) / CGFloat(maxS)), height: 6)
            }.frame(height: 6)
        }
        .contentShape(Rectangle())
    }
}

// MARK: Konular

struct TopicList: View {
    @EnvironmentObject var depo: Depo
    @Binding var selection: String?
    let query: String

    private var shown: [LinkTopic] {
        let q = Arama.katla(query)
        return depo.links.topics.filter {
            q.isEmpty || Arama.katla($0.name).contains(q) || $0.entries.contains { Arama.katla($0.text).contains(q) }
        }
    }

    var body: some View {
        List(selection: $selection) {
            let books = shown.filter(\.teoria), own = shown.filter { !$0.teoria }
            if !books.isEmpty {
                Section("Kitaplar · \(books.count)") { ForEach(books) { TopicRow(t: $0).tag($0.id) } }
            }
            if !own.isEmpty {
                Section("Kendi konuların · \(own.count)") { ForEach(own) { TopicRow(t: $0).tag($0.id) } }
            }
        }
        .overlay {
            if shown.isEmpty {
                ContentUnavailableView("Henüz konu yok", systemImage: "books.vertical",
                                       description: Text("Kaydetmeden önce bir kitap seç ya da konuşurken adını söyle: “Bilimler 1 üzerine…”"))
            }
        }
    }
}

struct TopicRow: View {
    let t: LinkTopic
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(Ink.topic(t.color)).frame(width: 4).padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(t.short).font(Ink.serif(.body, .semibold))
                if t.name != t.short { Text(t.name).font(.caption).foregroundStyle(Ink.secondary).lineLimit(1) }
                HStack(spacing: 8) {
                    Label("\(t.count)", systemImage: "waveform").labelStyle(.titleAndIcon)
                    if t.seconds > 0 { Text(minutesText(t.seconds)) }
                    if t.teoria { Text("okuma %\(t.percent)") }
                    Spacer()
                    Text(Zaman.goreli(t.latestDate))
                }
                .font(.caption2).foregroundStyle(Ink.faint)
            }
        }
        .padding(.vertical, 3)
    }
}

struct TopicPage: View {
    @EnvironmentObject var depo: Depo
    @EnvironmentObject var k: Kaydedici
    let t: LinkTopic

    private var byDay: [(String, [LinkEntry])] {
        var d: [(String, [LinkEntry])] = []
        for e in t.entries {
            let g = Zaman.gunBasligi(e.when)
            if d.last?.0 == g { d[d.count - 1].1.append(e) } else { d.append((g, [e])) }
        }
        return d
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Capsule().fill(Ink.topic(t.color)).frame(width: 28, height: 5)
                        Text(t.teoria ? (t.series.isEmpty ? "Kitap" : t.series) : "Konu").font(.caption.weight(.semibold))
                            .foregroundStyle(Ink.secondary).textCase(.uppercase)
                    }
                    Text(t.short).font(Ink.serif(.largeTitle, .bold))
                    if t.name != t.short { Text(t.name).font(Ink.serif(.title3)).foregroundStyle(Ink.secondary) }
                    HStack(spacing: 14) {
                        Text("\(t.count) kayıt · \(minutesText(t.seconds)) konuşma")
                        if t.teoria { Text("okuma %\(t.percent) · son \(t.last_read)") }
                    }.font(.callout).foregroundStyle(Ink.secondary)
                    HStack(spacing: 8) {
                        Button { k.topic = t.id; k.baslat(.spark) } label: { Label("Bu kitap üzerine konuş", systemImage: "mic.fill") }
                            .buttonStyle(.borderedProminent).tint(Ink.ember).disabled(k.kayitta)
                        Button { k.topic = t.id; k.baslat(.journal) } label: { Label("Uzun konuşma", systemImage: "book.pages") }
                            .disabled(k.kayitta)
                        if t.teoria, let u = URL(string: "teoria://kitap/\(t.id)") {
                            Button { NSWorkspace.shared.open(u) } label: { Label("Teoria'da aç", systemImage: "text.book.closed") }
                        }
                        Button { obsidianAc(depo.kok.appendingPathComponent(t.page), depo.vault) } label: {
                            Label("Obsidian", systemImage: "arrow.up.forward.app")
                        }
                    }.controlSize(.regular)
                }
                ForEach(byDay, id: \.0) { day, es in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(day).font(Ink.serif(.title3, .semibold)).foregroundStyle(Ink.secondary)
                        ForEach(es, id: \.rowID) { EntryCard(e: $0, color: Ink.topic(t.color)) }
                    }
                }
            }
            .padding(28).frame(maxWidth: 820, alignment: .leading)
        }
        .background(Ink.paper)
    }
}

struct EntryCard: View {
    @EnvironmentObject var depo: Depo
    @EnvironmentObject var oy: Oynatici
    let e: LinkEntry
    let color: Color

    private var url: URL? {
        if !e.item.isEmpty, let o = depo.ogeler.first(where: { $0.id == e.item }) { return depo.sesURL(o) }
        return depo.vaultURL(e.audio)
    }
    private var playing: Bool { oy.calan == e.rowID && oy.caliyor }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: e.sourceSymbol).foregroundStyle(color)
                    Text(e.sourceName).font(.caption.weight(.semibold))
                    Text("· \(Zaman.saat(e.when))").font(.caption).foregroundStyle(Ink.secondary)
                    if e.seconds > 0 { Text("· \(Zaman.sure(Double(e.seconds)))").font(.caption.monospacedDigit()).foregroundStyle(Ink.secondary) }
                    if e.how == "soz" { Text("· adı geçti").font(.caption2).foregroundStyle(Ink.faint) }
                    Spacer()
                    if let u = url {
                        Button { oy.play(id: e.rowID, url: u, from: e.parts.isEmpty ? nil : e.offset) } label: {
                            Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white).frame(width: 26, height: 26).background { Circle().fill(color) }
                        }.buttonStyle(.plain).accessibilityLabel(playing ? "Duraklat" : "Dinle")
                    }
                }
                Text(e.title).font(Ink.serif(.headline))
                if !e.quote.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Rectangle().fill(color.opacity(0.6)).frame(width: 3)
                        Text(e.quote).font(Ink.serif(.body)).italic().foregroundStyle(Ink.secondary)
                    }
                }
                if !e.parts.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(e.parts, id: \.self) { p in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Button(mmss(p.t)) { if let u = url { oy.play(id: e.rowID, url: u, from: p.t) } }
                                    .buttonStyle(.plain).font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(color)
                                Text(p.x).font(.callout).textSelection(.enabled)
                            }
                        }
                    }
                } else if !e.text.isEmpty {
                    Text(e.text).font(.callout).lineSpacing(3).textSelection(.enabled)
                }
                if playing || oy.calan == e.rowID {
                    Slider(value: Binding(get: { oy.konum }, set: { oy.atla($0) }), in: 0...max(0.1, oy.uzunluk)).controlSize(.small)
                }
            }
        }
    }
}

func mmss(_ t: Double) -> String { let s = Int(t); return "\(s / 60):\(String(format: "%02d", s % 60))" }

// MARK: Günlük (long talks)

struct JournalList: View {
    @EnvironmentObject var depo: Depo
    let query: String
    private var items: [Oge] { depo.ogeler.filter { $0.isJournal && Arama.eslesir($0, query, depo.siniflar) } }

    var body: some View {
        List(selection: $depo.secili) {
            ForEach(items.gunlere(), id: \.0) { day, os in
                Section(day) {
                    ForEach(os) { o in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(Zaman.saat(o.zaman)).font(.callout.monospacedDigit().weight(.semibold))
                                Text(o.sureMetni).font(.caption.monospacedDigit()).foregroundStyle(Ink.secondary)
                                Spacer()
                                if !o.islendi { Image(systemName: "hourglass").foregroundStyle(.orange).font(.caption) }
                                Image(systemName: o.cihaz == "mac" ? "laptopcomputer" : "iphone").font(.caption2).foregroundStyle(Ink.faint)
                            }
                            Text(o.baslik).font(Ink.serif(.body, .semibold)).lineLimit(1)
                            Text(o.metin.isEmpty ? "Yazıya dökülmeyi bekliyor…" : o.metin).font(.caption).foregroundStyle(Ink.secondary).lineLimit(2)
                            if !o.topics.isEmpty { TopicChips(topics: o.topics) }
                        }
                        .padding(.vertical, 3).tag(o.id)
                        .contextMenu { BaglamMenusu(o: o) }
                    }
                }
            }
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("Uzun konuşma yok", systemImage: "book.pages",
                                       description: Text("⌃⌥G ile başlat: konuştukça kaydeder, 60 dakikada bir kesintisiz yeni parçaya geçer, o günün günlüğüne yazılır."))
            }
        }
    }
}

struct TopicChips: View {
    @EnvironmentObject var depo: Depo
    let topics: [TopicShare]
    var body: some View {
        HStack(spacing: 5) {
            ForEach(topics, id: \.id) { t in
                let c = Ink.topic(depo.links.topic(t.id)?.color ?? "")
                Text("\(t.name) · \(minutesText(t.seconds))").font(.caption2.weight(.medium))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background { Capsule().fill(c.opacity(0.14)) }.foregroundStyle(c)
            }
        }
    }
}

struct JournalDetail: View {
    @EnvironmentObject var depo: Depo
    @EnvironmentObject var oy: Oynatici
    let o: Oge
    @State private var segs: [Segment] = []

    private var current: Int? {
        guard oy.calan == o.id else { return nil }
        return segs.lastIndex { $0.t <= oy.konum + 0.2 }
    }
    private var extracts: [Oge] { depo.ogeler.filter { $0.parent == o.id }.sorted { $0.offset < $1.offset } }
    private var chain: [Oge] {
        // parts of the same talk: follow devam back and forth (journal parts are separate records)
        var r = [o]
        var p = o
        while let prev = depo.ogeler.first(where: { $0.id == p.devam }) { r.insert(prev, at: 0); p = prev }
        p = o
        while let next = depo.ogeler.first(where: { $0.devam == p.id }) { r.append(next); p = next }
        return r
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Uzun konuşma · \(Zaman.gunBasligi(o.zaman)) · \(Zaman.saat(o.zaman)) · \(o.sureMetni)")
                        .font(.caption).foregroundStyle(Ink.secondary)
                    Text(o.baslik).font(Ink.serif(.largeTitle, .bold))
                    HStack(spacing: 8) {
                        TopicMenu(o: o)
                        if !o.topics.isEmpty { TopicChips(topics: o.topics) }
                        Spacer()
                        if !o.journal_note.isEmpty {
                            Button { obsidianAc(depo.vault.appendingPathComponent(o.journal_note), depo.vault) } label: {
                                Label("Günlükte aç", systemImage: "book.closed")
                            }
                        }
                    }
                    if chain.count > 1 {
                        HStack(spacing: 6) {
                            Text("Parçalar:").font(.caption).foregroundStyle(Ink.secondary)
                            ForEach(Array(chain.enumerated()), id: \.1.id) { i, p in
                                Button("\(i + 1). \(Zaman.saat(p.zaman))") { depo.secili = p.id }
                                    .controlSize(.small).buttonStyle(.bordered).tint(p.id == o.id ? Ink.journal : .gray)
                            }
                        }
                    }
                }
                CalarSerit(o: o, renk: Ink.journal)
                if !o.ozet.isEmpty {
                    Text(o.ozet).font(Ink.serif(.title3)).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Ink.journal.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
                if !extracts.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Ayıklanan kıvılcımlar").font(.headline)
                            ForEach(extracts) { x in
                                HStack(alignment: .firstTextBaseline) {
                                    Button(mmss(x.offset)) { seek(x.offset) }.buttonStyle(.plain)
                                        .font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(Ink.journal)
                                    Text(x.baslik).font(.callout.weight(.medium))
                                    Spacer()
                                    Button("Aç") { depo.secili = x.id }.controlSize(.small)
                                }
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    if segs.isEmpty {
                        Text(o.islendi ? "Konuşma duyulmadı." : "Sırada — Mac Whisper ile birazdan yazıya döker.").foregroundStyle(Ink.secondary)
                    }
                    ForEach(Array(segs.enumerated()), id: \.offset) { i, sg in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Button(mmss(sg.t)) { seek(sg.t) }.buttonStyle(.plain)
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(current == i ? Ink.ember : Ink.faint)
                                .frame(width: 44, alignment: .trailing)
                            Text(sg.x).font(.system(size: 15)).lineSpacing(4).textSelection(.enabled)
                                .foregroundStyle(current == i ? Ink.text : Ink.text.opacity(0.85))
                        }
                        .padding(.vertical, 4).padding(.horizontal, 6)
                        .background(current == i ? Ink.ember.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .padding(28).frame(maxWidth: 820, alignment: .leading)
        }
        .background(Ink.paper)
        .task(id: o.id + o.durum) { segs = depo.segments(o) }
    }

    private func seek(_ t: Double) {
        guard let u = depo.sesURL(o) else { return }
        oy.play(id: o.id, url: u, from: t)
    }
}

// MARK: Topic menu (choose / change the book a record belongs to)

struct TopicMenu: View {
    @EnvironmentObject var depo: Depo
    let o: Oge
    @State private var asking = false
    @State private var name = ""

    var body: some View {
        Menu {
            TopicChoices(current: o.topic) { depo.duzelt(o, "topic", $0) } custom: { asking = true }
        } label: {
            Label(o.topic.isEmpty ? "Konu seç" : o.topic_name, systemImage: "books.vertical")
        }
        .menuStyle(.button).buttonStyle(.bordered).fixedSize()
        .tint(o.topic.isEmpty ? .gray : Ink.topic(depo.links.topic(o.topic)?.color ?? ""))
        .help(o.topic_source == "soz" ? "Konuşmada adı geçtiği için bağlandı" : o.topic_source == "elle" ? "Sen seçtin" : "Konusuz")
        .alert("Yeni konu", isPresented: $asking) {
            TextField("Konu adı", text: $name)
            Button("Bağla") { let n = name.trimmingCharacters(in: .whitespaces); if !n.isEmpty { depo.duzelt(o, "topic", "k:" + n) }; name = "" }
            Button("Vazgeç", role: .cancel) { name = "" }
        }
    }
}

/// Menu items: recent Teoria books, topics already used, none, a new free topic.
struct TopicChoices: View {
    @EnvironmentObject var depo: Depo
    let current: String?
    let pick: (String) -> Void
    var custom: (() -> Void)? = nil

    var body: some View {
        Section("Son okunan kitaplar") {
            ForEach(depo.links.recent_books.prefix(10)) { b in
                Button { pick(b.id) } label: { check(b.id, "\(b.short) — \(b.name.components(separatedBy: " — ").dropFirst().joined())") }
            }
        }
        let own = depo.links.topics.filter { !$0.teoria }
        if !own.isEmpty {
            Section("Kendi konuların") { ForEach(own) { t in Button { pick(t.id) } label: { check(t.id, t.short) } } }
        }
        Divider()
        if let custom { Button("Yeni konu…", action: custom) }
        Button { pick("-") } label: { check("-", "Konusuz") }
    }

    private func check(_ id: String, _ text: String) -> some View {
        Label(text.hasSuffix("— ") ? String(text.dropLast(3)) : text, systemImage: current == id ? "checkmark" : "")
    }
}

// MARK: Recording dock (window sidebar) and the next-topic picker

/// Topic for the next recording, chosen before speaking. Survives until changed (and shows while recording).
struct NextTopicMenu: View {
    @EnvironmentObject var depo: Depo
    @EnvironmentObject var k: Kaydedici
    @State private var asking = false
    @State private var name = ""
    var body: some View {
        Menu {
            TopicChoices(current: k.topic ?? "-") { k.topic = $0 == "-" ? nil : $0 } custom: { asking = true }
        } label: {
            Label(k.topic == nil ? "Konu: kendisi bulsun" : depo.topicName(k.topic), systemImage: "books.vertical")
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton).fixedSize()
        .help("Kaydedeceğin şey hangi kitap ya da konu üzerine? Seçmezsen konuşmadan çıkarılır.")
        .alert("Yeni konu", isPresented: $asking) {
            TextField("Konu adı", text: $name)
            Button("Seç") { let n = name.trimmingCharacters(in: .whitespaces); if !n.isEmpty { k.topic = "k:" + n }; name = "" }
            Button("Vazgeç", role: .cancel) { name = "" }
        }
    }
}

struct RecordDock: View {
    @EnvironmentObject var k: Kaydedici
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NextTopicMenu().font(.caption)
            if k.kayitta {
                Button { k.bitir() } label: {
                    Label("Bitir · \(Zaman.sure(k.sure))\(k.part > 1 ? " · \(k.part). parça" : "")", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .controlSize(.large).buttonStyle(.borderedProminent).tint(k.mode == .journal ? Ink.journal : .kivilcim)
            } else {
                HStack(spacing: 6) {
                    Button { k.baslat(.spark) } label: { Label("Fikir", systemImage: "mic.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(.kivilcim)
                    Button { k.baslat(.journal) } label: { Label("Uzun", systemImage: "book.pages").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered).tint(Ink.journal)
                }.controlSize(.large)
            }
        }
        .padding(10)
    }
}

extension Suzgec {
    var key: String {
        switch self {
        case .yon: "yon"; case .akis: "akis"; case .konular: "konular"; case .tatbik: "tatbik"; case .gunluk: "gunluk"; case .acik: "acik"; case .biten: "biten"
        default: "acik"
        }
    }
    static func from(_ k: String) -> Suzgec {
        switch k { case "akis": .akis; case "konular": .konular; case "tatbik": .tatbik; case "gunluk": .gunluk; case "acik": .acik; case "biten": .biten; default: .yon }
    }
}
