// Merkez — iPhone (2026-11-07): the Mac's Merkez on the phone. One dashboard page with four cards (Tatbik · Akış ·
// Yön · Konular), each opening its full page: Tatbik with the ring, status counters, program cards and the
// program × status grid; Akış = today's issue; Yön = spoken minutes and where the mind goes; Konular = one page per
// book or topic. Same files as the Mac (Tatbik/tatbik.json, Feed/feed.json, links.json); touches go the usual way.
import SwiftUI
import Charts

enum MerkezRota: Hashable {
    case tatbik, akis, yon, konular, uygulamalar, istatistik, yeniModel
    case konu(String)
    case uygulama(String)
}

// MARK: Small pieces

struct StatusRing: View {
    let value: Double
    var color: Color = .kivilcim
    var size: CGFloat = 44
    var line: CGFloat = 5
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.10), lineWidth: line)
            Circle().trim(from: 0, to: max(0.001, value)).stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((value * 100).rounded()))").font(.system(size: size * 0.28, weight: .semibold).monospacedDigit())
        }
        .frame(width: size, height: size)
        .animation(.snappy, value: value)
        .accessibilityElement()
        .accessibilityLabel("Yüzde \(Int((value * 100).rounded()))")
    }
}

/// A rounded card on the grouped background.
struct MCard<C: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: C
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private func topicColor(_ hex: String) -> Color { hex.isEmpty ? Color(hex: "#B4892F") : Color(hex: hex) }
private func serif(_ s: Font.TextStyle, _ w: Font.Weight = .regular) -> Font { .system(s, design: .serif).weight(w) }
private func mmss(_ t: Double) -> String { let s = Int(t); return "\(s / 60):\(String(format: "%02d", s % 60))" }

/// Weeks and days of spoken production, shared by the dashboard card and the Yön page.
@MainActor struct DirectionFacts {
    let depo: TelefonDeposu
    var weeks: [DirectionWeek] { depo.links.direction.weeks }
    var thisWeek: DirectionWeek? { weeks.last }
    var lastWeek: DirectionWeek? { weeks.count > 1 ? weeks[weeks.count - 2] : nil }

    var delta: String {
        guard let a = thisWeek?.seconds, let b = lastWeek?.seconds, b > 0 else { return "geçen hafta yok" }
        let d = a - b
        return (d >= 0 ? "+" : "−") + minutesText(abs(d)) + " geçen haftaya göre"
    }

    /// The five topics with most speech in 28 days get a colour; the rest is "Diğer", untied speech "Genel".
    var top: [String] {
        var sum: [String: Int] = [:]
        for d in depo.links.direction.days { for (t, s) in d.topics where !t.hasPrefix("genel:") { sum[t, default: 0] += s } }
        return sum.sorted { $0.value > $1.value }.prefix(5).map(\.key)
    }

    struct Bar: Identifiable { let id = UUID(); let day: Date; let group: String; let minutes: Double }
    func bars(last n: Int = 28) -> [Bar] {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        let top = self.top
        var r: [Bar] = []
        for d in depo.links.direction.days.suffix(n) {
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
    var domain: [String] { top.map { depo.topicName($0) } + ["Diğer kitaplar", "Genel"] }
    var colors: [Color] {
        let pal: [Color] = [.kivilcim, Color(hex: "#2F6FEB"), Color(hex: "#23915E"), Color(hex: "#B4892F"), Color(hex: "#C2416B")]
        return top.indices.map { pal[$0 % pal.count] } + [Color(hex: "#8E8C86"), Color(hex: "#C9C5BB")]
    }

    var weekTopics: [(LinkTopic, Int)] {
        guard let w = thisWeek else { return [] }
        return w.topics.compactMap { id, s in depo.links.topic(id).map { ($0, s) } }.sorted { $0.1 > $1.1 }
    }
    var weekGeneral: [(String, Int)] {
        guard let w = thisWeek else { return [] }
        return w.topics.filter { $0.key.hasPrefix("genel:") }
            .map { (depo.siniflar.alan(String($0.key.dropFirst(6))).ad, $0.value) }.sorted { $0.1 > $1.1 }
    }
    /// Books read in the last two weeks that nothing was said about in the same time. Shown, never counted as debt.
    var silent: [RecentBook] {
        let cut = Calendar.current.date(byAdding: .day, value: -14, to: Date())!
        return depo.links.recent_books.filter { b in
            guard let d = Zaman.coz(b.last + "T00:00:00"), d > cut else { return false }
            return !(depo.links.topic(b.id)?.entries.contains { $0.when > cut } ?? false)
        }.prefix(5).map { $0 }
    }
}

/// kivilcim://kaydet?topic=… — the app's own address starts a recording on the Kaydet tab.
func talkURL(_ topic: String) -> URL? {
    var c = URLComponents(string: "kivilcim://kaydet")
    c?.queryItems = [URLQueryItem(name: "topic", value: topic)]
    return c?.url
}

// MARK: Dashboard

/// Merkez's navigation path, so kivilcim://merkez/<tatbik|akis|yon|konular> opens a page directly.
@MainActor final class MerkezNav: ObservableObject {
    static let shared = MerkezNav()
    @Published var path = NavigationPath()

    func open(_ name: String?) {
        var p = NavigationPath()
        switch name {
        case "tatbik": p.append(MerkezRota.tatbik)
        case "akis": p.append(MerkezRota.akis)
        case "yon": p.append(MerkezRota.yon)
        case "konular": p.append(MerkezRota.konular)
        case "uygulamalar": p.append(MerkezRota.uygulamalar)
        case "istatistik": p.append(MerkezRota.istatistik)
        case "yeni-model": p.append(MerkezRota.yeniModel)
        default: break
        }
        path = p
    }
}

struct MerkezEkrani: View {
    @EnvironmentObject var depo: TelefonDeposu
    @ObservedObject private var nav = MerkezNav.shared
    @State private var ayarlar = false

    var body: some View {
        NavigationStack(path: $nav.path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Söylediklerin, ne oldukları ve zihnin nereye gidiyor.")
                        .font(serif(.subheadline)).foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                    NavigationLink(value: MerkezRota.istatistik) { KivilcimIstatistikKarti() }.buttonStyle(.plain)
                    NavigationLink(value: MerkezRota.yeniModel) { NewModelKarti() }.buttonStyle(.plain)
                    NavigationLink(value: MerkezRota.tatbik) { TatbikKarti() }.buttonStyle(.plain)
                    NavigationLink(value: MerkezRota.akis) { AkisKarti() }.buttonStyle(.plain)
                    NavigationLink(value: MerkezRota.yon) { YonKarti() }.buttonStyle(.plain)
                    NavigationLink(value: MerkezRota.konular) { KonularKarti() }.buttonStyle(.plain)
                    NavigationLink(value: MerkezRota.uygulamalar) { UygulamalarKarti() }.buttonStyle(.plain)
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Merkez")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { ayarlar = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Ayarlar")
                }
            }
            .sheet(isPresented: $ayarlar) { AyarlarEkrani() }
            .refreshable { await depo.gonder() }
            .merkezRotalari()
        }
    }
}

extension View {
    /// Every page Merkez can push: its own pages, a Tatbik item, a feed item, a record.
    func merkezRotalari() -> some View {
        self
            .navigationDestination(for: MerkezRota.self) { r in
                switch r {
                case .tatbik: TatbikPano()
                case .akis: AkisSayfasi()
                case .yon: YonSayfasi()
                case .konular: KonularSayfasi()
                case .konu(let id): KonuSayfasi(id: id)
                case .uygulamalar: UygulamalarSayfasi()
                case .uygulama(let id): UygulamaSayfasi(id: id)
                case .istatistik: KivilcimIstatistikSayfasi()
                case .yeniModel: NewModelSayfasi()
                }
            }
            .navigationDestination(for: TatbikItem.self) { TatbikPhoneDetail(id: $0.id) }
            .navigationDestination(for: FeedItem.self) { FeedPhoneDetail(id: $0.id) }
            .navigationDestination(for: String.self) { DetayEkrani(id: $0) }
    }
}

private struct CardHead: View {
    let title: String
    let symbol: String
    var color: Color = .kivilcim
    var body: some View {
        HStack {
            Label(title, systemImage: symbol).font(.headline).foregroundStyle(color)
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
    }
}

struct TatbikKarti: View {
    @EnvironmentObject var depo: TelefonDeposu
    var body: some View {
        let t = depo.tatbik
        MCard {
            VStack(alignment: .leading, spacing: 14) {
                CardHead(title: "Tatbik", symbol: "checklist", color: TatbikStatus.tamam.color)
                if t.maddeler.isEmpty {
                    Text("Mac'te Claude kayıtları maddelere böler; eşitlenince burada görünür.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 16) {
                        StatusRing(value: t.progress(), color: TatbikStatus.tamam.color, size: 78, line: 8)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(t.maddeler.filter { $0.status.isClosed }.count) / \(t.maddeler.count) madde karara bağlandı")
                                .font(serif(.body, .semibold))
                            Text("\(t.programlar.filter { !t.items(of: $0.id).isEmpty }.count) program")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 8) {
                        ForEach(TatbikStatus.allCases) { s in
                            VStack(spacing: 2) {
                                Image(systemName: s.symbol).foregroundStyle(s.color)
                                Text("\(t.count(s))").font(.headline.monospacedDigit())
                                Text(s.short).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(s.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    let busy = t.programlar
                        .map { p in (p, t.items(of: p.id)) }
                        .filter { !$0.1.isEmpty && $0.1.contains { !$0.status.isClosed } }
                        .sorted { $0.1.filter { !$0.status.isClosed }.count > $1.1.filter { !$0.status.isClosed }.count }
                        .prefix(3)
                    if !busy.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("En çok açık iş").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            ForEach(Array(busy), id: \.0.id) { p, items in
                                HStack(spacing: 10) {
                                    StatusRing(value: t.progress(items), color: topicColor(p.renk ?? ""), size: 30, line: 3)
                                    Text(p.ad).font(.subheadline.weight(.medium)).lineLimit(1)
                                    Spacer()
                                    Text("\(items.filter { !$0.status.isClosed }.count) açık").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct AkisKarti: View {
    @EnvironmentObject var depo: TelefonDeposu
    var body: some View {
        let f = depo.feed
        MCard {
            VStack(alignment: .leading, spacing: 10) {
                CardHead(title: "Akış", symbol: "newspaper", color: .orange)
                if f.isToday {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(f.openCount)").font(serif(.largeTitle, .bold)).monospacedDigit()
                        Text("açık · \(f.items.count) maddelik baskı").font(.footnote).foregroundStyle(.secondary)
                    }
                    let open = f.items.filter { !$0.isMarked && !$0.isSkipped }.prefix(3)
                    ForEach(Array(open)) { i in
                        Text("• " + i.shownTitle).font(.subheadline).lineLimit(2)
                    }
                    if f.openCount == 0 { Text("Bugünlük bu kadar.").font(.footnote).foregroundStyle(.secondary) }
                } else {
                    Text("Bugünün baskısı \(f.readyAt)'da.").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct YonKarti: View {
    @EnvironmentObject var depo: TelefonDeposu
    var body: some View {
        let y = DirectionFacts(depo: depo)
        MCard {
            VStack(alignment: .leading, spacing: 10) {
                CardHead(title: "Yön", symbol: "safari", color: Color(hex: "#4B3FD6"))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(minutesText(y.thisWeek?.seconds ?? 0)).font(serif(.largeTitle, .bold)).monospacedDigit()
                    Text("bu hafta konuştun").font(.footnote).foregroundStyle(.secondary)
                }
                Text(y.delta).font(.caption).foregroundStyle(.secondary)
                let bars = y.bars(last: 14)
                if !bars.isEmpty {
                    Chart(bars) { b in
                        BarMark(x: .value("Gün", b.day, unit: .day), y: .value("dk", b.minutes))
                            .foregroundStyle(by: .value("Konu", b.group)).cornerRadius(2)
                    }
                    .chartForegroundStyleScale(domain: y.domain, range: y.colors)
                    .chartLegend(.hidden)
                    .chartYAxis(.hidden)
                    .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
                    .frame(height: 70)
                }
                if let t = y.weekTopics.first {
                    Text("En çok: \(t.0.short) · \(minutesText(t.1))").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct KonularKarti: View {
    @EnvironmentObject var depo: TelefonDeposu
    var body: some View {
        let ts = depo.links.topics.sorted { $0.latestDate > $1.latestDate }
        MCard {
            VStack(alignment: .leading, spacing: 10) {
                CardHead(title: "Konular", symbol: "books.vertical", color: Color(hex: "#2E8B57"))
                Text("\(ts.count) konu · \(ts.reduce(0) { $0 + $1.count }) kayıt").font(.footnote).foregroundStyle(.secondary)
                ForEach(ts.prefix(3)) { t in
                    HStack(spacing: 10) {
                        Capsule().fill(topicColor(t.color)).frame(width: 4, height: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.short).font(serif(.subheadline, .semibold))
                            Text("\(t.count) kayıt · \(Zaman.goreli(t.latestDate))").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if t.teoria { Text("%\(t.percent)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                    }
                }
                if ts.isEmpty { Text("Kaydetmeden önce bir kitap seç ya da konuşurken adını söyle.").font(.footnote).foregroundStyle(.secondary) }
            }
        }
    }
}

// MARK: Tatbik (full page)

struct TatbikPano: View {
    @EnvironmentObject var depo: TelefonDeposu
    @State private var program: String?
    @State private var status: TatbikStatus?
    @State private var query = ""
    @AppStorage("tatbikKapaliGizle") private var hideClosed = true

    private var t: TatbikState { depo.tatbik }
    private var programs: [TatbikProgram] { t.programlar.filter { !t.items(of: $0.id).isEmpty } }

    private var shown: [TatbikItem] {
        let q = Arama.katla(query)
        return t.maddeler.filter { m in
            (program == nil || m.program == program) && (status == nil || m.status == status)
                && (!hideClosed || status != nil || !m.status.isClosed)
                && (q.isEmpty || Arama.katla(m.baslik + " " + (m.ayrinti ?? "") + " " + (m.kanit ?? "")).contains(q))
        }
        .sorted { a, b in
            let oa = order(a.status), ob = order(b.status)
            return oa != ob ? oa < ob : a.priorityRank != b.priorityRank ? a.priorityRank < b.priorityRank : a.id < b.id
        }
    }
    private func order(_ s: TatbikStatus) -> Int { [.acik: 0, .kismen: 1, .tamam: 2, .gerekYok: 3][s] ?? 0 }

    var body: some View {
        List {
            if t.maddeler.isEmpty {
                ContentUnavailableView("Henüz Tatbik yok", systemImage: "checklist",
                                       description: Text("Mac'te Claude'a \"Tatbik'i güncelle\" de: kayıtları maddelere böler, programlara bağlar, yapılıp yapılmadığına bakar."))
            } else {
                Section { header.plainRow() }
                Section { statusRow.plainRow() }
                Section("Programlar") { programGrid.plainRow() }
                Section { matrix } header: { Text("Program × durum") }
                Section {
                    if status == nil {
                        Toggle("Kapananları gizle", isOn: $hideClosed)
                    }
                    if program != nil || status != nil {
                        Button("Süzgeci kaldır") { withAnimation(.snappy) { program = nil; status = nil } }
                    }
                } header: { Text(listTitle) }
                if program == nil && status == nil && query.isEmpty {
                    ForEach(programs) { p in
                        let rows = shown.filter { $0.program == p.id }
                        if !rows.isEmpty {
                            Section { ForEach(rows) { row($0) } } header: {
                                Text(p.ad).foregroundStyle(topicColor(p.renk ?? ""))
                            }
                        }
                    }
                } else {
                    Section {
                        ForEach(shown) { row($0) }
                        if shown.isEmpty { Text("Bu süzgeçte madde yok.").foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query, prompt: "Maddelerde ara")
        .navigationTitle("Tatbik")
        .refreshable { await depo.gonder() }
        .animation(.snappy, value: program)
        .animation(.snappy, value: status)
    }

    private var listTitle: String {
        var s = program.flatMap { t.program($0)?.ad } ?? "Bütün maddeler"
        if let st = status { s += " · \(st.name)" }
        return s + " · \(shown.count)"
    }

    private func row(_ m: TatbikItem) -> some View {
        NavigationLink(value: m) {
            VStack(alignment: .leading, spacing: 3) {
                TatbikPhoneRow(m: m)
                if program == nil, (status != nil || !query.isEmpty), let p = t.program(m.program) {
                    Text(p.ad).font(.caption2.weight(.medium)).foregroundStyle(topicColor(p.renk ?? "")).padding(.leading, 34)
                }
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { depo.tatbikDuzelt(m.id, "status", m.status == .tamam ? "acik" : "tamam") } label: {
                Label(m.status == .tamam ? "Aç" : "Tamam", systemImage: m.status == .tamam ? "arrow.uturn.backward" : "checkmark")
            }.tint(.green)
        }
        .swipeActions(edge: .trailing) {
            Button { depo.tatbikDuzelt(m.id, "status", "gerek-yok") } label: { Label("Gerek yok", systemImage: "minus.circle") }.tint(.gray)
            Button { depo.tatbikDuzelt(m.id, "status", "kismen") } label: { Label("Kısmen", systemImage: "circle.lefthalf.filled") }
                .tint(TatbikStatus.kismen.color)
        }
        .contextMenu {
            ForEach(TatbikStatus.allCases) { s in
                Button { depo.tatbikDuzelt(m.id, "status", s.rawValue) } label: { Label(s.name, systemImage: s.symbol) }
                    .disabled(m.status == s)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Kıvılcım'da söylediklerin, madde madde, program program. Yapıldıysa kanıtıyla.")
                    .font(serif(.subheadline)).foregroundStyle(.secondary)
                Text("Claude son baktı: \(String((t.guncelleme ?? "").prefix(16)).replacingOccurrences(of: "T", with: " "))"
                     + ((t.incelenmemis?.isEmpty ?? true) ? "" : " · bakılmamış \(t.incelenmemis!.count) kayıt"))
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            StatusRing(value: t.progress(program.map { t.items(of: $0) }), color: TatbikStatus.tamam.color, size: 74, line: 8)
        }
        .padding(.horizontal, 4)
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            ForEach(TatbikStatus.allCases) { s in
                let on = status == s
                Button { status = on ? nil : s } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Image(systemName: s.symbol).foregroundStyle(on ? .white : s.color)
                        Text("\(t.count(s, in: program.map { t.items(of: $0) }))").font(serif(.title2, .bold)).monospacedDigit()
                            .foregroundStyle(on ? .white : .primary)
                        Text(s.short).font(.caption2).foregroundStyle(on ? .white.opacity(0.85) : .secondary).lineLimit(1)
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(on ? s.color : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: on)
                .accessibilityLabel("\(s.name), \(t.count(s))")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private var programGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(programs) { p in
                let items = t.items(of: p.id)
                let on = program == p.id
                let c = topicColor(p.renk ?? "")
                Button { program = on ? nil : p.id } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            StatusRing(value: t.progress(items), color: c, size: 38, line: 4)
                            Spacer()
                            Text("\(items.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Text(p.ad).font(.footnote.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
                        HStack(spacing: 6) {
                            ForEach(TatbikStatus.allCases) { s in
                                let n = t.count(s, in: items)
                                if n > 0 {
                                    HStack(spacing: 2) { Image(systemName: s.symbol); Text("\(n)") }
                                        .font(.caption2.monospacedDigit()).foregroundStyle(s.color)
                                }
                            }
                        }
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(on ? c.opacity(0.16) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? c : .clear, lineWidth: 1.5) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    /// Program × status: every cell a count you can tap into.
    private var matrix: some View {
        Grid(alignment: .leading, horizontalSpacing: 4, verticalSpacing: 4) {
            GridRow {
                Text("")
                ForEach(TatbikStatus.allCases) { s in
                    Image(systemName: s.symbol).foregroundStyle(s.color).frame(width: 40).accessibilityLabel(s.name)
                }
            }
            ForEach(programs) { p in
                let items = t.items(of: p.id)
                GridRow {
                    Text(p.ad).font(.caption).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(TatbikStatus.allCases) { s in
                        let n = t.count(s, in: items)
                        let on = program == p.id && status == s
                        Button { if on { program = nil; status = nil } else { program = p.id; status = s } } label: {
                            Text(n == 0 ? "·" : "\(n)").font(.caption.monospacedDigit().weight(n > 0 ? .semibold : .regular))
                                .frame(width: 40, height: 24)
                                .foregroundStyle(n == 0 ? Color.secondary.opacity(0.5) : on ? .white : s.color)
                                .background(RoundedRectangle(cornerRadius: 6)
                                    .fill(on ? s.color : s.color.opacity(n == 0 ? 0 : min(0.32, 0.06 + Double(n) * 0.012))))
                        }
                        .buttonStyle(.plain).disabled(n == 0)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private extension View {
    func plainRow() -> some View {
        listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }
}

// MARK: Akış (full page)

struct AkisSayfasi: View {
    @EnvironmentObject var depo: TelefonDeposu
    var body: some View {
        List { FeedSections() }
            .navigationTitle("Akış")
            .refreshable { await depo.gonder() }
    }
}

// MARK: Yön (full page)

struct YonSayfasi: View {
    @EnvironmentObject var depo: TelefonDeposu
    @Environment(\.openURL) private var openURL

    var body: some View {
        let y = DirectionFacts(depo: depo)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Sesle ve yazıyla ne ürettin, zihnin nereye gidiyor. Kıvılcım, Teoria ve Wise Path birlikte.")
                    .font(serif(.subheadline)).foregroundStyle(.secondary).padding(.horizontal, 4)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    stat("Bu hafta", minutesText(y.thisWeek?.seconds ?? 0), y.delta)
                    stat("Kitap ve konu", "\(y.weekTopics.count)", y.weekTopics.first.map { "en çok \($0.0.short)" } ?? "henüz bağ yok")
                    stat("Uzun konuşma", "\(depo.ogeler.filter { $0.isJournal && Date().timeIntervalSince($0.zaman) < 7 * 86400 }.count)", "son 7 gün")
                    stat("Bütün üretim", "\(depo.links.topics.reduce(0) { $0 + $1.count })", "\(depo.links.topics.count) konuya bağlı")
                }
                MCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Son 28 gün · dakika").font(.headline)
                        let bars = y.bars()
                        if bars.isEmpty {
                            Text("Henüz konuşma yok.").foregroundStyle(.secondary)
                        } else {
                            Chart(bars) { b in
                                BarMark(x: .value("Gün", b.day, unit: .day), y: .value("dk", b.minutes))
                                    .foregroundStyle(by: .value("Konu", b.group)).cornerRadius(2)
                            }
                            .chartForegroundStyleScale(domain: y.domain, range: y.colors)
                            .chartLegend(position: .bottom, alignment: .leading)
                            .frame(height: 210)
                        }
                    }
                }
                MCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Bu hafta zihnin").font(.headline)
                        if y.weekTopics.isEmpty && y.weekGeneral.isEmpty {
                            Text("Bu hafta konuşma yok.").foregroundStyle(.secondary)
                        }
                        let maxS = max(1, (y.weekTopics.map(\.1) + y.weekGeneral.map(\.1)).max() ?? 1)
                        ForEach(y.weekTopics, id: \.0.id) { t, s in
                            NavigationLink(value: MerkezRota.konu(t.id)) {
                                row(t.short, t.name, s, maxS, topicColor(t.color))
                            }.buttonStyle(.plain)
                        }
                        ForEach(y.weekGeneral, id: \.0) { n, s in row(n, "kitaba bağlanmamış", s, maxS, .secondary) }
                    }
                }
                if !y.silent.isEmpty {
                    MCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Okudun, henüz konuşmadın").font(.headline)
                            Text("Son iki haftada okuduğun ama üzerine bir şey söylemediğin kitaplar.").font(.caption).foregroundStyle(.secondary)
                            ForEach(y.silent) { b in
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(b.short).font(serif(.body, .semibold))
                                        if b.name != b.short { Text(b.name).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                    }
                                    Spacer()
                                    Button { talkURL(b.id).map { openURL($0) } } label: { Label("Konuş", systemImage: "mic.fill") }
                                        .buttonStyle(.bordered).tint(.kivilcim).controlSize(.small)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Yön")
        .refreshable { await depo.gonder() }
    }

    private func stat(_ title: String, _ value: String, _ sub: String) -> some View {
        MCard(padding: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Text(value).font(serif(.title2, .bold)).monospacedDigit()
                Text(sub).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
    }

    private func row(_ title: String, _ sub: String, _ s: Int, _ maxS: Int, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(serif(.body, .semibold))
                Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Text(minutesText(s)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            GeometryReader { g in
                Capsule().fill(c.opacity(0.85)).frame(width: max(4, g.size.width * CGFloat(s) / CGFloat(maxS)), height: 6)
            }.frame(height: 6)
        }
        .contentShape(Rectangle())
    }
}

// MARK: Konular (list and one topic)

struct KonularSayfasi: View {
    @EnvironmentObject var depo: TelefonDeposu
    @State private var query = ""

    private var shown: [LinkTopic] {
        let q = Arama.katla(query)
        return depo.links.topics.filter {
            q.isEmpty || Arama.katla($0.name).contains(q) || $0.entries.contains { Arama.katla($0.text).contains(q) }
        }
    }

    var body: some View {
        List {
            let books = shown.filter(\.teoria), own = shown.filter { !$0.teoria }
            if !books.isEmpty {
                Section("Kitaplar · \(books.count)") { ForEach(books) { t in NavigationLink(value: MerkezRota.konu(t.id)) { TopicPhoneRow(t: t) } } }
            }
            if !own.isEmpty {
                Section("Kendi konuların · \(own.count)") { ForEach(own) { t in NavigationLink(value: MerkezRota.konu(t.id)) { TopicPhoneRow(t: t) } } }
            }
        }
        .overlay {
            if shown.isEmpty {
                ContentUnavailableView("Henüz konu yok", systemImage: "books.vertical",
                                       description: Text("Kaydetmeden önce bir kitap seç ya da konuşurken adını söyle: “Bilimler 1 üzerine…”"))
            }
        }
        .searchable(text: $query, prompt: "Konularda ve sözlerinde ara")
        .navigationTitle("Konular")
        .refreshable { await depo.gonder() }
    }
}

struct TopicPhoneRow: View {
    let t: LinkTopic
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(topicColor(t.color)).frame(width: 4).padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(t.short).font(serif(.body, .semibold))
                if t.name != t.short { Text(t.name).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                HStack(spacing: 8) {
                    Label("\(t.count)", systemImage: "waveform")
                    if t.seconds > 0 { Text(minutesText(t.seconds)) }
                    if t.teoria { Text("okuma %\(t.percent)") }
                    Spacer()
                    Text(Zaman.goreli(t.latestDate))
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct KonuSayfasi: View {
    @EnvironmentObject var depo: TelefonDeposu
    @Environment(\.openURL) private var openURL
    let id: String

    var body: some View {
        if let t = depo.links.topic(id) {
            let c = topicColor(t.color)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Capsule().fill(c).frame(width: 28, height: 5)
                            Text(t.teoria ? (t.series.isEmpty ? "Kitap" : t.series) : "Konu").font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary).textCase(.uppercase)
                        }
                        Text(t.short).font(serif(.largeTitle, .bold))
                        if t.name != t.short { Text(t.name).font(serif(.title3)).foregroundStyle(.secondary) }
                        Text("\(t.count) kayıt · \(minutesText(t.seconds)) konuşma" + (t.teoria ? " · okuma %\(t.percent)" : ""))
                            .font(.footnote).foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Button { talkURL(t.id).map { openURL($0) } } label: { Label("Üzerine konuş", systemImage: "mic.fill") }
                                .buttonStyle(.borderedProminent).tint(.kivilcim)
                            if t.teoria, let u = URL(string: "teoria://kitap/\(t.id)") {
                                Button { openURL(u) } label: { Label("Teoria'da aç", systemImage: "text.book.closed") }.buttonStyle(.bordered)
                            }
                        }
                        .controlSize(.small)
                    }
                    ForEach(byDay(t), id: \.0) { day, es in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(day).font(serif(.headline)).foregroundStyle(.secondary)
                            ForEach(es, id: \.rowID) { EntryPhoneCard(e: $0, color: c) }
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Konu bulunamadı", systemImage: "books.vertical")
        }
    }

    private func byDay(_ t: LinkTopic) -> [(String, [LinkEntry])] {
        var d: [(String, [LinkEntry])] = []
        for e in t.entries {
            let g = Zaman.gunBasligi(e.when)
            if d.last?.0 == g { d[d.count - 1].1.append(e) } else { d.append((g, [e])) }
        }
        return d
    }
}

struct EntryPhoneCard: View {
    @EnvironmentObject var depo: TelefonDeposu
    @EnvironmentObject var oy: TelefonOynatici
    let e: LinkEntry
    let color: Color
    @State private var open = false

    private var record: Oge? { e.item.isEmpty ? nil : depo.oge(e.item) }
    private var key: String { record.map { $0.parent.isEmpty ? $0.id : $0.parent } ?? e.rowID }
    private var playing: Bool { oy.calan == key && oy.caliyor }
    private var canPlay: Bool { record != nil || !e.audio.isEmpty }

    var body: some View {
        MCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: e.sourceSymbol).foregroundStyle(color)
                    Text(e.sourceName).font(.caption.weight(.semibold))
                    Text("· \(Zaman.saat(e.when))").font(.caption).foregroundStyle(.secondary)
                    if e.seconds > 0 { Text("· \(Zaman.sure(Double(e.seconds)))").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                    if e.how == "soz" { Text("· adı geçti").font(.caption2).foregroundStyle(.tertiary) }
                    Spacer()
                    if canPlay {
                        Button { play(from: e.parts.isEmpty ? 0 : e.offset) } label: {
                            Group {
                                if oy.yukleniyor == record?.id { ProgressView().controlSize(.mini) }
                                else { Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: 11, weight: .bold)) }
                            }
                            .foregroundStyle(.white).frame(width: 30, height: 30).background { Circle().fill(color) }
                        }
                        .buttonStyle(.plain).accessibilityLabel(playing ? "Duraklat" : "Dinle")
                    }
                }
                if let o = record {
                    NavigationLink(value: o.id) {
                        HStack { Text(e.title).font(serif(.headline)).multilineTextAlignment(.leading); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
                    }.buttonStyle(.plain)
                } else {
                    Text(e.title).font(serif(.headline))
                }
                if !e.quote.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Rectangle().fill(color.opacity(0.6)).frame(width: 3)
                        Text(e.quote).font(serif(.subheadline)).italic().foregroundStyle(.secondary)
                    }
                }
                if !e.parts.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(e.parts, id: \.self) { p in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Button(mmss(p.t)) { play(from: p.t) }
                                    .buttonStyle(.plain).font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(color)
                                Text(p.x).font(.subheadline).lineLimit(open ? nil : 3)
                            }
                        }
                    }
                } else if !e.text.isEmpty {
                    Text(e.text).font(.subheadline).lineSpacing(2).lineLimit(open ? nil : 5).textSelection(.enabled)
                }
                if (e.text.count > 260 || e.parts.count > 2) {
                    Button(open ? "Daha az" : "Devamı") { withAnimation(.snappy) { open.toggle() } }.font(.caption.weight(.medium)).tint(color)
                }
                if oy.calan == key {
                    Slider(value: Binding(get: { oy.konum }, set: { oy.atla($0) }), in: 0...max(0.1, oy.uzunluk)).tint(color)
                }
            }
        }
    }

    private func play(from t: Double) {
        Task {
            if let o = record {
                if oy.calan == key, t == 0 { await oy.degistir(o) } else { await oy.degistir(o, baslangic: max(0.01, t)) }
            } else if let u = await depo.vaultSes(e.audio) {
                oy.calURL(key, u, baslangic: t)
            }
        }
    }
}
