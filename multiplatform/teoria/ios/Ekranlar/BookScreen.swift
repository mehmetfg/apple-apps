// Book home — İdrak's room inside Teoria (v10, 2026-10-17): the cover and Çekirdek (theme · claim · idea · place in the
// reading network), the chapter strip, two doors into the text (whole · only highlights), and the work around it:
// Can alıcı (key sentences chosen whether or not you marked them, plus what you missed → recall), Özet, Zincir
// (claim chain + fine distinctions), Harita, İşaretler, Kaynaklar (sources and the books this one talks to).
import SwiftUI

enum BookTab: String, CaseIterable, Identifiable {
    case keys, summary, chain, map, marks, sources
    var id: String { rawValue }
    var name: String {
        switch self {
        case .keys: "Can alıcı"; case .summary: "Özet"; case .chain: "Zincir"
        case .map: "Harita"; case .marks: "İşaretler"; case .sources: "Kaynaklar"
        }
    }
    var symbol: String {
        switch self {
        case .keys: "key.horizontal"; case .summary: "text.alignleft"; case .chain: "link"
        case .map: "point.3.connected.trianglepath.dotted"; case .marks: "highlighter"; case .sources: "books.vertical"
        }
    }
}

struct ReaderRequest: Identifiable, Hashable {
    let mode: ReaderMode
    var ch: Int? = nil
    var b: Int? = nil
    var id: String { "\(mode.rawValue).\(ch ?? -1).\(b ?? -1)" }
}

struct BookScreen: View {
    @EnvironmentObject var depo: Depo
    @ObservedObject private var library = LibraryStore.shared
    let entry: LibraryEntry

    @State private var book: Book?
    @State private var chosenTab: BookTab?
    @State private var reader: ReaderRequest?
    @State private var onlyChapters = false
    @State private var recall: Isaret?
    @State private var node: BookInsight.Node?

    private var insight: BookInsight? { library.insights[entry.id] }
    private var tint: Color { Tema.kitap(entry.id) }
    private var keys: [BookInsight.Key] { (insight?.keys ?? []).sorted { $0.weight > $1.weight } }
    /// Opens on the key sentences when Claude has chosen them, otherwise on the summary.
    private var tab: BookTab { chosenTab ?? (keys.isEmpty ? .summary : .keys) }
    private var tabs: [BookTab] { BookTab.allCases }

    #if os(macOS)
    private let wide = true
    #else
    private let wide = false
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                if wide, let c = insight?.concepts, !c.nodes.isEmpty {
                    HStack(alignment: .top, spacing: 16) {
                        coreCard.frame(maxWidth: .infinity)
                        miniMap(c).frame(width: 380)
                    }
                } else {
                    coreCard
                }
                BookRatingBar(book: entry.id)
                partsStrip
                doors
                #if os(iOS)
                outsideLinks
                #endif
                SimgeSecici(secenekler: tabs.map { .init(deger: $0, ad: $0.name, sembol: $0.symbol) },
                            secili: Binding(get: { tab }, set: { chosenTab = $0 }), sikisik: !wide)
                Group {
                    switch tab {
                    case .keys: keysTab
                    case .summary: summary
                    case .chain: chainTab
                    case .map: map
                    case .marks: marks
                    case .sources: sourcesTab
                    }
                }
                .transition(.opacity)
            }
            .padding(20)
            .frame(maxWidth: wide ? 1080 : 820).frame(maxWidth: .infinity)
        }
        .background(Tema.arka.ignoresSafeArea())
        .navigationTitle(entry.titleParts.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { book = await library.book(entry.id, kasa: depo.kasa) }
        #if os(iOS)
        .fullScreenCover(item: $reader) { r in readerView(r) }
        #else
        .sheet(item: $reader) { r in readerView(r).frame(minWidth: 900, minHeight: 700) }
        #endif
        .sheet(item: $recall) { RecallSayfasi(isaret: $0).environmentObject(depo) }
    }

    @ViewBuilder
    private func readerView(_ r: ReaderRequest) -> some View {
        if let book {
            ReaderView(book: book, mode: r.mode, jump: r.ch.map { ($0, r.b ?? 0) }).environmentObject(depo)
        }
    }

    private func card<C: View>(_ fill: Color = Tema.yuzey, @ViewBuilder _ c: () -> C) -> some View {
        c().padding(16).tamGenislik()
            .background { RoundedRectangle(cornerRadius: 22, style: .continuous).fill(fill) }
    }

    private func chapterTitle(_ ch: Int?) -> String {
        guard let ch else { return "" }
        return book?.chapters[safe: ch]?.title ?? "Bölüm \(ch + 1)"
    }

    // MARK: hero

    private var hero: some View {
        HStack(alignment: .bottom, spacing: 22) {
            KitapKapagi(id: entry.id, baslik: entry.titleParts.title, genislik: 132)
                .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
            VStack(alignment: .leading, spacing: 8) {
                if let a = entry.titleParts.author { Text(a).font(.subheadline).foregroundStyle(Tema.ikincil) }
                Text(entry.titleParts.title).font(Tema.serif(.title2, .semibold)).foregroundStyle(Tema.metin)
                    .fixedSize(horizontal: false, vertical: true)
                if let t = insight?.thesis, insight?.core?.claim != t {
                    Text(t).font(Tema.serif(.footnote)).italic().foregroundStyle(Tema.ikincil).lineLimit(4)
                }
                HStack(spacing: 12) {
                    ZStack {
                        Halka(oran: Double(entry.percent) / 100, renk: tint, kalinlik: 4)
                        Text("%\(entry.percent)").font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(entry.chapters) bölüm · \(entry.highlights) işaret\(keys.isEmpty ? "" : " · \(keys.count) can alıcı")")
                            .font(.footnote.weight(.medium))
                        Text("~\(max(1, entry.words / 250)) sayfa · \(entry.inVD ? (entry.claude ? "okuma baskısı" : "özgün metin") : "arşivde (Voice Dream'den silindi)")")
                            .font(.caption).foregroundStyle(Tema.soluk)
                    }
                    .foregroundStyle(Tema.ikincil)
                }
            }
        }
    }

    // MARK: Çekirdek — İdrak's core tile

    @ViewBuilder
    private var coreCard: some View {
        let c = insight?.core
        let cluster = library.network.books[entry.id].flatMap { library.network.clusters[$0.cluster] }
        let links = insight?.links ?? []
        let shared = sharedAuthors
        VStack(alignment: .leading, spacing: 14) {
            Bolumbasi(metin: "Çekirdek", sembol: "circle.hexagongrid", renk: tint)
            if let theme = c?.theme {
                Text(theme).font(Tema.serif(.title3, .semibold)).foregroundStyle(Tema.metin).fixedSize(horizontal: false, vertical: true)
            } else if c == nil {
                Text(entry.finished ? "Çekirdek henüz yazılmadı" : "Kitap sürüyor; çekirdek kitap bitince yazılır")
                    .font(Tema.serif(.headline)).foregroundStyle(Tema.ikincil)
            }
            if let claim = c?.claim ?? insight?.thesis { coreRow("İddia", claim, Tema.metin) }
            if let idea = c?.idea { coreRow("Ana fikir", idea, Tema.ikincil) }
            if cluster != nil || !links.isEmpty || !shared.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("AĞDAKİ YERİ").font(.system(size: 10.5, weight: .bold)).tracking(0.6).foregroundStyle(Tema.soluk)
                    AkanYerlesim(aralik: 6) {
                        if let cluster { Hap(metin: cluster.name, renk: tint) }
                        ForEach(Array(links.enumerated()), id: \.offset) { _, l in
                            if let e = library.entry(l.to) {
                                NavigationLink(value: e.id) {
                                    Hap(metin: "↔ \(l.kind ?? "bağlı") · \(e.titleParts.title)", renk: Tema.basari)
                                }
                                .buttonStyle(.plain).help(l.note ?? "")
                            }
                        }
                        ForEach(shared, id: \.self) { a in Hap(metin: "ortak kaynak · \(a)", renk: Tema.ikincil) }
                    }
                }
            }
        }
        .padding(18).tamGenislik()
        .background { RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Tema.yuzey) }
        .overlay(alignment: .topTrailing) {
            Circle().fill(tint.opacity(0.10)).frame(width: 120).blur(radius: 30).offset(x: 20, y: -20).allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func coreRow(_ k: String, _ v: String, _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(k.uppercased(with: Dil.tr)).font(.system(size: 10.5, weight: .bold)).tracking(0.6).foregroundStyle(Tema.soluk)
                .frame(width: 72, alignment: .leading)
            Text(v).font(Tema.serif(.body)).foregroundStyle(color).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Authors this book cites that another book on the shelf also cites (İdrak's "ortak kaynak").
    private var sharedAuthors: [String] {
        guard let mine = insight?.sources, !mine.isEmpty else { return [] }
        let names = Set(mine.compactMap { $0.author.map(Dil.normal) })
        var hit: [String: String] = [:]
        for (id, ins) in library.insights where id != entry.id {
            for s in ins.sources ?? [] { if let a = s.author, names.contains(Dil.normal(a)) { hit[Dil.normal(a)] = a } }
        }
        return hit.values.sorted()
    }

    /// The heaviest concepts only (and the edges between them), so the small map stays legible.
    static func core(of c: BookInsight.ConceptMap, limit: Int = 9) -> BookInsight.ConceptMap {
        guard c.nodes.count > limit else { return c }
        let degree = Dictionary(c.edges.flatMap { [($0.a, 1), ($0.b, 1)] }, uniquingKeysWith: +)
        let keep = c.nodes.sorted { (($0.weight ?? 1), degree[$0.id] ?? 0) > (($1.weight ?? 1), degree[$1.id] ?? 0) }.prefix(limit)
        let ids = Set(keep.map(\.id))
        return .init(nodes: Array(keep), edges: c.edges.filter { ids.contains($0.a) && ids.contains($0.b) })
    }

    private func miniMap(_ c: BookInsight.ConceptMap) -> some View {
        Button { withAnimation(.snappy) { chosenTab = .map } } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Bolumbasi(metin: "Kavram haritası · \(c.nodes.count)", sembol: "point.3.connected.trianglepath.dotted")
                    Spacer()
                    Text("Büyüt ↗").font(.caption.weight(.semibold)).foregroundStyle(tint)
                }
                ConceptMapView(map: Self.core(of: c), tint: tint, selected: .constant(nil)).allowsHitTesting(false)
                    .frame(height: 250)
            }
            .padding(16)
            .background { RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Tema.yuzey) }
        }
        .buttonStyle(.plain)
    }

    // MARK: Bölüm haritası — every chapter as a segment; marked ones lit, key sentences dotted

    @ViewBuilder
    private var partsStrip: some View {
        if let book, book.chapters.count > 1 {
            let marked = Dictionary(grouping: library.withMarks(book).highlights.compactMap { $0.at.first?.ch }, by: { $0 }).mapValues(\.count)
            let keyed = Set(keys.compactMap(\.ch))
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Bolumbasi(metin: "Bölüm haritası", sembol: "rectangle.split.3x1")
                    Spacer()
                    Text("\(book.chapters.count) bölüm · \(marked.count) işaretli\(keyed.isEmpty ? "" : " · \(keyed.count) can alıcı")")
                        .font(.caption).foregroundStyle(Tema.soluk)
                }
                HStack(spacing: 3) {
                    ForEach(Array(book.chapters.enumerated()), id: \.offset) { ci, ch in
                        Button { reader = ReaderRequest(mode: .full, ch: ci, b: 0) } label: {
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(marked[ci] != nil ? Marker.swatch(1) : tint.opacity(Double(ci) / Double(book.chapters.count) * 100 < Double(entry.percent) ? 0.30 : 0.10))
                                    .frame(height: 22)
                                Circle().fill(keyed.contains(ci) ? tint : .clear).frame(width: 5, height: 5)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("\(ci + 1) · \(ch.title)\(marked[ci].map { " · \($0) işaret" } ?? "")")
                        .accessibilityLabel("\(ci + 1). bölüm, \(ch.title)")
                    }
                }
                HStack(spacing: 14) {
                    legend(Marker.swatch(1), "işaretli")
                    legend(tint.opacity(0.30), "dinlendi")
                    legend(tint.opacity(0.10), "sırada")
                    if !keyed.isEmpty { HStack(spacing: 5) { Circle().fill(tint).frame(width: 6, height: 6); Text("can alıcı") } }
                }
                .font(.caption2).foregroundStyle(Tema.soluk)
            }
            .padding(16)
            .background { RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Tema.yuzey) }
        }
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 5) { RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 12, height: 8); Text(t) }
    }

    #if os(iOS)
    /// The same book in the other apps: listen in Wise Path (when it is there), talk about it in Kıvılcım.
    private var outsideLinks: some View {
        HStack(spacing: 18) {
            if entry.inVR == true || Network.isWisePathID(entry.id), let u = Network.wisePathLink(entry.id) {
                Button { UIApplication.shared.open(u) } label: { Label("Wise Path'te dinle", systemImage: "headphones") }
            }
            if let u = Network.talkLink(entry.id) {
                Button { UIApplication.shared.open(u) } label: { Label("Bu kitap üzerine konuş", systemImage: "mic") }
            }
            Spacer(minLength: 0)
        }
        .font(.footnote.weight(.semibold)).buttonStyle(.borderless).tint(tint)
        .lineLimit(1).minimumScaleFactor(0.8)
    }
    #endif

    private var doors: some View {
        HStack(spacing: 12) {
            Button { reader = ReaderRequest(mode: .full) } label: {
                Label(UserDefaults.standard.integer(forKey: "teoria.reader.pos.\(entry.id)") > 0 ? "Okumaya devam" : "Okumaya başla",
                      systemImage: "book.fill")
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent).tint(tint)
            Button { reader = ReaderRequest(mode: .marked) } label: {
                Label("Yalnız işaretler", systemImage: "highlighter").lineLimit(1).minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.bordered).tint(tint)
            .disabled(entry.highlights == 0)
        }
        .controlSize(.large)
        .disabled(book == nil)
        .overlay {
            if book == nil {
                if library.loading.contains(entry.id) { ProgressView() }
                else if let f = library.failed { Text(f).font(.caption).foregroundStyle(Tema.uyari).padding(6).background(.thinMaterial, in: Capsule()) }
            }
        }
    }

    // MARK: Can alıcı — chosen from the text, marked or not

    private func isMarked(_ k: BookInsight.Key) -> Bool {
        guard let book, let ch = k.ch, let b = k.b else { return false }
        return library.withMarks(book).highlights.contains { $0.at.contains { $0.ch == ch && $0.b == b } }
    }

    @ViewBuilder
    private var keysTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            if keys.isEmpty {
                pendingNote("Can alıcı cümleler henüz seçilmedi",
                            "Claude kitabı okurken, işaretlemiş olsan da olmasan da kitabı taşıyan cümleleri önem sırasıyla seçer. "
                            + (entry.claude ? "Sabah görevi sırayla yazıyor; beklemek istemezsen Claude'a \"Teoria kitap işle: \(entry.titleParts.title)\" de."
                                            : "Dış kitapta istekle: Claude'a \"Teoria kitap işle: \(entry.titleParts.title)\" de."))
            } else {
                Text("Kitabı taşıyan cümleler, önem sırasıyla. İşaretlediklerin ayrıca belirtilir. Önce kapalıyken hatırla, sonra kendi cümlenle yeniden kur.")
                    .font(.footnote).foregroundStyle(Tema.ikincil)
                ForEach(keys) { k in keyCard(k) }
            }
            if let missed = insight?.missed, !missed.isEmpty {
                Bolumbasi(metin: "Kaçırdıkların · işaretlemediğin taşıyıcı yerler", sembol: "eye.trianglebadge.exclamationmark").padding(.top, 10)
                ForEach(missed) { m in missedCard(m) }
            }
        }
    }

    private func keyCard(_ k: BookInsight.Key) -> some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        ForEach(0..<5, id: \.self) { i in Circle().fill(i < k.weight ? tint : Tema.cizgi).frame(width: 6, height: 6) }
                    }
                    .accessibilityLabel("Önem \(k.weight) / 5")
                    Text(chapterTitle(k.ch)).font(.caption.weight(.semibold)).foregroundStyle(Tema.soluk).lineLimit(1)
                    Spacer()
                    if isMarked(k) { Label("işaretledin", systemImage: "highlighter").font(.caption2.weight(.semibold)).foregroundStyle(Marker.swatch(1)) }
                }
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 2).fill(tint.opacity(0.6)).frame(width: 3)
                    Text(k.quote).font(Tema.serif(.body)).foregroundStyle(Tema.metin).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                }
                if !k.why.isEmpty { Text(k.why).font(.callout).foregroundStyle(Tema.ikincil).fixedSize(horizontal: false, vertical: true) }
                actions(id: "key:\(entry.id):\(k.id)", quote: k.quote, why: k.why, ch: k.ch, b: k.b)
            }
        }
    }

    private func missedCard(_ m: BookInsight.Missed) -> some View {
        card(Tema.yuzey) {
            VStack(alignment: .leading, spacing: 10) {
                if m.ch != nil { Text(chapterTitle(m.ch)).font(.caption.weight(.semibold)).foregroundStyle(tint) }
                Text(m.why).font(Tema.serif(.body)).foregroundStyle(Tema.metin).fixedSize(horizontal: false, vertical: true)
                actions(id: "oz:\(entry.id):\(m.ch ?? -1).\(m.b ?? -1)", quote: m.quote, why: m.why, ch: m.ch, b: m.b)
            }
        }
    }

    private func actions(id: String, quote: String, why: String, ch: Int?, b: Int?) -> some View {
        HStack {
            Button {
                recall = Isaret(id: id, kitap: entry.id, baslik: entry.title, metin: quote,
                                renk: 1, tarih: insight?.built ?? Tarih.gun(Date()), kaynak: "kitap-oz", baglam: why)
            } label: { Label("Kapat · hatırla", systemImage: "eye.slash") }
                .buttonStyle(.borderedProminent).tint(tint)
            if let ch {
                Button { reader = ReaderRequest(mode: .full, ch: ch, b: b ?? 0) } label: { Label("Metinde gör", systemImage: "book") }
                    .buttonStyle(.bordered)
            }
        }
        .controlSize(.small)
    }

    // MARK: Özet

    @ViewBuilder
    private var summary: some View {
        if let ins = insight, let book, !ins.verdicts.isEmpty || !ins.chapters.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                if !onlyChapters, !ins.verdicts.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Bolumbasi(metin: "Kitabın yargıları", sembol: "quote.opening")
                        ForEach(Array(ins.verdicts.enumerated()), id: \.offset) { i, v in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text("\(i + 1)").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(tint).frame(width: 18)
                                Text(v).font(Tema.serif(.body)).foregroundStyle(Tema.metin).lineSpacing(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(18).tamGenislik()
                    .background { RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Tema.yuzey) }
                }
                if !ins.chapters.isEmpty {
                    HStack {
                        Bolumbasi(metin: "Bölüm bölüm", sembol: "list.number")
                        Spacer()
                        Toggle("Yalnız bölüm özetleri", isOn: $onlyChapters.animation(.snappy)).toggleStyle(.switch).font(.caption).fixedSize()
                    }
                    VStack(spacing: 0) {
                        ForEach(ins.chapters, id: \.ch) { s in
                            Button { reader = ReaderRequest(mode: .full, ch: s.ch, b: 0) } label: { chapterRow(s, book) }
                                .buttonStyle(.plain)
                            Rectangle().fill(Tema.cizgi).frame(height: 0.5)
                        }
                    }
                    .background { RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Tema.yuzey) }
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                } else {
                    chapterList(book)
                }
            }
        } else {
            pendingNote("Özet henüz yazılmadı",
                        entry.claude ? (entry.finished ? "Kitap %90'ı geçti; sıradaki sabah görevinde Claude yazacak. Beklemek istemezsen Claude'a \"Teoria kitap işle\" de."
                                                      : "Kitap %90'a varınca Claude genel yargıları ve bölüm özetlerini yazar.")
                                     : "Dış kitaplarda özet istekle yazılır: Claude'a \"Teoria kitap işle: \(entry.titleParts.title)\" de.")
            if let book { chapterList(book) }
        }
    }

    private func chapterRow(_ s: BookInsight.ChapterSummary, _ book: Book) -> some View {
        let ch = book.chapters[safe: s.ch]
        let n = book.highlights.filter { $0.at.contains { $0.ch == s.ch } }.count
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(ch?.title ?? "Bölüm \(s.ch + 1)").font(Tema.serif(.headline)).foregroundStyle(Tema.metin)
                Spacer()
                if n > 0 { Label("\(n)", systemImage: "highlighter").font(.caption2).foregroundStyle(Marker.swatch(1)) }
            }
            if let k = s.key, !onlyChapters { Text(k).font(.subheadline.weight(.medium)).foregroundStyle(tint) }
            Text(s.summary).font(.callout).foregroundStyle(Tema.ikincil).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }

    private func chapterList(_ book: Book) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(book.chapters.enumerated()), id: \.offset) { ci, ch in
                Button { reader = ReaderRequest(mode: .full, ch: ci, b: 0) } label: {
                    HStack {
                        Text(ch.title).font(Tema.serif(.callout)).foregroundStyle(Tema.metin).lineLimit(2)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Tema.soluk)
                    }
                    .padding(.vertical, 11).padding(.horizontal, 16).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Rectangle().fill(Tema.cizgi).frame(height: 0.5).padding(.leading, 16)
            }
        }
        .background { RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Tema.yuzey) }
    }

    private func pendingNote(_ t: String, _ d: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(t, systemImage: "hourglass").font(.headline).foregroundStyle(Tema.metin)
            Text(d).font(.callout).foregroundStyle(Tema.ikincil)
        }
        .padding(16).tamGenislik()
        .background { RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Tema.yuzey2) }
    }

    // MARK: Zincir — the claim chain and the fine distinctions

    @ViewBuilder
    private var chainTab: some View {
        let chain = insight?.chain ?? []
        let nuances = insight?.nuances ?? []
        if chain.isEmpty && nuances.isEmpty {
            pendingNote("İddia zinciri henüz yok", "Claude kitabı işlerken iddiaların sırasını ve kaçırılması kolay ince ayrımları yazar.")
        } else {
            VStack(alignment: .leading, spacing: 16) {
                if !chain.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Bolumbasi(metin: "İddia zinciri", sembol: "link").padding(.bottom, 12)
                        ForEach(Array(chain.enumerated()), id: \.offset) { i, z in
                            HStack(alignment: .top, spacing: 14) {
                                VStack(spacing: 0) {
                                    Text("\(i + 1)").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                        .frame(width: 24, height: 24).background { Circle().fill(tint) }
                                    if i < chain.count - 1 { Rectangle().fill(tint.opacity(0.25)).frame(width: 2).frame(maxHeight: .infinity) }
                                }
                                Text(z).font(Tema.serif(.body)).foregroundStyle(Tema.metin).lineSpacing(3)
                                    .fixedSize(horizontal: false, vertical: true).padding(.bottom, 16).padding(.top, 2)
                            }
                        }
                    }
                    .padding(18).tamGenislik()
                    .background { RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Tema.yuzey) }
                }
                if !nuances.isEmpty {
                    Bolumbasi(metin: "Ayrımlar · ince noktalar", sembol: "scissors")
                    ForEach(Array(nuances.enumerated()), id: \.offset) { _, n in
                        card {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(n.title).font(Tema.serif(.headline)).foregroundStyle(Tema.metin).fixedSize(horizontal: false, vertical: true)
                                if let t = n.text { Text(t).font(.callout).foregroundStyle(Tema.ikincil).lineSpacing(2).fixedSize(horizontal: false, vertical: true) }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Kaynaklar — the books behind this one, and the shelf books it talks to

    @ViewBuilder
    private var sourcesTab: some View {
        let src = insight?.sources ?? []
        let links = insight?.links ?? []
        if src.isEmpty && links.isEmpty {
            pendingNote("Kaynakça henüz yok", "Claude kitabı işlerken metnin dayandığı eserleri (başvuru) ve sonra okunacakları (öneri) yazar; raftaki başka kitaplarla bağları da kurar.")
        } else {
            VStack(alignment: .leading, spacing: 16) {
                if !links.isEmpty {
                    Bolumbasi(metin: "Konuştuğu metinler", sembol: "arrow.left.arrow.right")
                    ForEach(Array(links.enumerated()), id: \.offset) { _, l in
                        if let e = library.entry(l.to) {
                            NavigationLink(value: e.id) {
                                HStack(spacing: 12) {
                                    KitapKapagi(id: e.id, baslik: e.titleParts.title, genislik: 40)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text((l.kind ?? "bağlı").uppercased(with: Dil.tr)).font(.system(size: 10, weight: .bold)).foregroundStyle(Tema.basari)
                                        Text(e.titleParts.title).font(Tema.serif(.headline)).foregroundStyle(Tema.metin)
                                        if let n = l.note { Text(n).font(.caption).foregroundStyle(Tema.ikincil).fixedSize(horizontal: false, vertical: true) }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Tema.soluk)
                                }
                                .padding(12).tamGenislik()
                                .background { RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Tema.yuzey) }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                ForEach([("Başvuru · metnin dayandığı", true), ("Öneri · sonra okunacak", false)], id: \.1) { title, ref in
                    let l = src.filter { $0.isReference == ref }
                    if !l.isEmpty {
                        Bolumbasi(metin: title, sembol: ref ? "text.book.closed" : "sparkles")
                        VStack(spacing: 0) {
                            ForEach(Array(l.enumerated()), id: \.offset) { _, s in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(s.work).font(Tema.serif(.headline)).foregroundStyle(Tema.metin)
                                    Text([s.author, s.year.map(String.init)].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(Tema.soluk)
                                    if let w = s.why { Text(w).font(.callout).foregroundStyle(Tema.ikincil).fixedSize(horizontal: false, vertical: true) }
                                }
                                .padding(14).tamGenislik()
                                Rectangle().fill(Tema.cizgi).frame(height: 0.5)
                            }
                        }
                        .background { RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Tema.yuzey) }
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }
            }
        }
    }

    // MARK: Harita

    @ViewBuilder
    private var map: some View {
        if let c = insight?.concepts, !c.nodes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ConceptMapView(map: c, tint: tint, selected: $node)
                    .frame(height: max(460, CGFloat(c.nodes.count) * 44))
                    .background { RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Tema.yuzey) }
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                if let n = node {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(n.label).font(Tema.serif(.title3, .semibold)).foregroundStyle(Tema.metin)
                        if let note = n.note { Text(note).font(.callout).foregroundStyle(Tema.ikincil) }
                        let rel = c.edges.filter { $0.a == n.id || $0.b == n.id }
                        ForEach(Array(rel.enumerated()), id: \.offset) { _, e in
                            let other = c.nodes.first { $0.id == (e.a == n.id ? e.b : e.a) }?.label ?? ""
                            Text("\(e.a == n.id ? "→" : "←") \(e.label ?? "bağlı") · \(other)").font(.footnote).foregroundStyle(Tema.ikincil)
                        }
                        if let chs = n.ch, !chs.isEmpty, let book {
                            AkanYerlesim(aralik: 6) {
                                ForEach(chs, id: \.self) { ci in
                                    Button { reader = ReaderRequest(mode: .full, ch: ci, b: 0) } label: {
                                        Text(book.chapters[safe: ci]?.title ?? "Bölüm \(ci + 1)").font(.caption.weight(.semibold)).lineLimit(1)
                                            .padding(.horizontal, 10).padding(.vertical, 6)
                                            .background { Capsule().fill(tint.opacity(0.14)) }.foregroundStyle(tint)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(16).tamGenislik()
                    .background { RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Tema.yuzey) }
                } else {
                    Text("Bir kavrama dokun: tanımı, bağları ve geçtiği bölümler açılır.").font(.caption).foregroundStyle(Tema.soluk)
                }
            }
        } else {
            pendingNote("Kavram haritası henüz yok", "Harita, özetle birlikte Claude tarafından kurulur: kitabın taşıyıcı kavramları ve aralarındaki ilişkiler.")
        }
    }

    // MARK: İşaretler

    @ViewBuilder
    private var marks: some View {
        if let book = book.map(library.withMarks) {
            if book.highlights.isEmpty {
                pendingNote("İşaret yok", "Voice Dream'de işaretlediğin cümleler burada, kitaptaki yerleriyle durur. İşaretlemediğin taşıyıcı cümleler Can alıcı'da.")
            } else {
                VStack(spacing: 10) {
                    ForEach(book.highlights.sorted { ($0.at.first?.ch ?? 0, $0.at.first?.b ?? 0) < ($1.at.first?.ch ?? 0, $1.at.first?.b ?? 0) }) { h in
                        Button { reader = ReaderRequest(mode: .marked, ch: h.at.first?.ch, b: h.at.first?.b) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                RoundedRectangle(cornerRadius: 2).fill(Marker.swatch(h.color)).frame(width: 4)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(book.chapters[safe: h.at.first?.ch ?? 0]?.title ?? "").font(.caption.weight(.semibold)).foregroundStyle(Tema.soluk)
                                    Text(h.quote).font(Tema.serif(.callout)).foregroundStyle(Tema.metin).lineSpacing(2)
                                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                    if let n = h.note { Label(n, systemImage: "note.text").font(.caption).foregroundStyle(Tema.ikincil) }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(14).contentShape(Rectangle())
                            .background { RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Tema.yuzey) }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Concept map

/// Force-directed concept map, laid out once per map (deterministic), drawn with Canvas; tap a node to select it.
struct ConceptMapView: View {
    let map: BookInsight.ConceptMap
    let tint: Color
    @Binding var selected: BookInsight.Node?
    @State private var positions: [String: CGPoint] = [:]     // in points, for `laidOutFor`
    @State private var laidOutFor: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Canvas { ctx, sz in
                    for e in map.edges {
                        guard let a = point(e.a, sz), let b = point(e.b, sz) else { continue }
                        let on = selected.map { $0.id == e.a || $0.id == e.b } ?? false
                        var path = Path(); path.move(to: a)
                        let mid = CGPoint(x: (a.x + b.x) / 2 + (b.y - a.y) * 0.08, y: (a.y + b.y) / 2 - (b.x - a.x) * 0.08)
                        path.addQuadCurve(to: b, control: mid)
                        ctx.stroke(path, with: .color(on ? tint : Tema.ikincil.opacity(0.28)), lineWidth: on ? 2 : 1)
                        if on, let l = e.label {
                            ctx.draw(Text(l).font(.system(size: 10, weight: .medium)).foregroundStyle(tint), at: mid)
                        }
                    }
                }
                ForEach(map.nodes) { n in
                    if let p = point(n.id, size) {
                        let w = n.weight ?? 1
                        let on = selected?.id == n.id
                        Text(n.label)
                            .font(.system(size: w >= 3 ? 14 : (w == 2 ? 12.5 : 11.5), weight: w >= 3 ? .bold : .semibold, design: .serif))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background { Capsule().fill(on ? tint : (w >= 3 ? tint.opacity(0.18) : Tema.yuzey2)) }
                            .overlay { Capsule().strokeBorder(tint.opacity(w >= 2 ? 0.45 : 0.18)) }
                            .foregroundStyle(on ? Color.white : Tema.metin)
                            .frame(maxWidth: 150)
                            .position(p)
                            .onTapGesture { Dokunus.secim(); withAnimation(.snappy) { selected = on ? nil : n } }.accessibilityAddTraits(.isButton)
                    }
                }
            }
            .onAppear { place(size) }
            .onChange(of: size) { _, s in place(s) }
        }
    }

    private func point(_ id: String, _ s: CGSize) -> CGPoint? { positions[id] }

    private static func box(_ n: BookInsight.Node) -> CGSize {
        let w = n.weight ?? 1
        let chars = CGFloat(min(n.label.count, 22))
        let lines: CGFloat = n.label.count > 22 ? 2 : 1
        return CGSize(width: min(150, chars * (w >= 3 ? 8.4 : 7.4) + 24), height: lines * 17 + 14)
    }

    /// Force layout scaled to the frame, then label boxes pushed apart until none overlap.
    private func place(_ size: CGSize) {
        guard size.width > 50, size != laidOutFor else { return }
        laidOutFor = size
        let unit = Self.layout(map)
        var p: [String: CGPoint] = [:]
        let boxes = Dictionary(map.nodes.map { ($0.id, Self.box($0)) }, uniquingKeysWith: { a, _ in a })   // a repeated id in the insight JSON must not crash
        for n in map.nodes {
            guard let b = boxes[n.id] else { continue }
            let u = unit[n.id] ?? CGPoint(x: 0.5, y: 0.5)
            p[n.id] = CGPoint(x: b.width / 2 + 8 + u.x * (size.width - b.width - 16), y: b.height / 2 + 8 + u.y * (size.height - b.height - 16))
        }
        let ids = map.nodes.map(\.id)
        for _ in 0..<300 {
            var moved = false
            for i in ids.indices { for j in ids.indices where j > i {
                let a = ids[i], c = ids[j]
                guard var A = p[a], var C = p[c] else { continue }
                guard let ba = boxes[a], let bc = boxes[c] else { continue }
                let ox = (ba.width + bc.width) / 2 + 6 - abs(A.x - C.x)
                let oy = (ba.height + bc.height) / 2 + 6 - abs(A.y - C.y)
                guard ox > 0, oy > 0 else { continue }
                moved = true
                if oy < ox * 1.6 {
                    let d = oy / 2 * (A.y < C.y ? -1 : 1); A.y += d; C.y -= d
                } else {
                    let d = ox / 2 * (A.x < C.x ? -1 : 1); A.x += d; C.x -= d
                }
                for (id, var q) in [(a, A), (c, C)] {
                    guard let b = boxes[id] else { continue }
                    q.x = min(max(q.x, b.width / 2 + 4), size.width - b.width / 2 - 4)
                    q.y = min(max(q.y, b.height / 2 + 4), size.height - b.height / 2 - 4)
                    p[id] = q
                }
            } }
            if !moved { break }
        }
        positions = p
    }

    /// Positions in 0…1. Heavier concepts start near the centre; springs pull related ones together.
    static func layout(_ m: BookInsight.ConceptMap) -> [String: CGPoint] {
        var p: [String: CGPoint] = [:]
        let nodes = m.nodes.sorted { ($0.weight ?? 1) > ($1.weight ?? 1) }
        for (i, n) in nodes.enumerated() {
            let a = Double(i) * 2.399963, r = 0.08 + 0.42 * sqrt(Double(i) / Double(max(nodes.count, 1)))
            p[n.id] = CGPoint(x: 0.5 + r * cos(a), y: 0.5 + r * sin(a))
        }
        let k = 0.9 / sqrt(Double(max(nodes.count, 1)))
        for step in 0..<260 {
            var d: [String: CGVector] = [:]
            for a in nodes { d[a.id] = .zero }
            for i in nodes.indices { for j in nodes.indices where j > i {
                let A = p[nodes[i].id]!, B = p[nodes[j].id]!
                var dx = A.x - B.x, dy = A.y - B.y
                let dist = max(sqrt(dx * dx + dy * dy), 0.01)
                let f = k * k / dist * 0.6
                dx /= dist; dy /= dist
                d[nodes[i].id]!.dx += dx * f; d[nodes[i].id]!.dy += dy * f
                d[nodes[j].id]!.dx -= dx * f; d[nodes[j].id]!.dy -= dy * f
            } }
            for e in m.edges {
                guard let A = p[e.a], let B = p[e.b] else { continue }
                let dx = A.x - B.x, dy = A.y - B.y
                let dist = max(sqrt(dx * dx + dy * dy), 0.01)
                let f = dist * dist / k * 0.5
                d[e.a]!.dx -= dx / dist * f; d[e.a]!.dy -= dy / dist * f
                d[e.b]!.dx += dx / dist * f; d[e.b]!.dy += dy / dist * f
            }
            let t = 0.05 * (1 - Double(step) / 260) + 0.002
            for n in nodes {
                var q = p[n.id]!
                let v = d[n.id]!
                let len = max(sqrt(v.dx * v.dx + v.dy * v.dy), 0.0001)
                q.x += v.dx / len * min(len, t); q.y += v.dy / len * min(len, t)
                q.x += (0.5 - q.x) * 0.01; q.y += (0.5 - q.y) * 0.01     // gentle gravity
                p[n.id] = CGPoint(x: min(max(q.x, 0), 1), y: min(max(q.y, 0), 1))
            }
        }
        // stretch to fill the frame
        let xs = p.values.map(\.x), ys = p.values.map(\.y)
        let (x0, x1, y0, y1) = (xs.min() ?? 0, xs.max() ?? 1, ys.min() ?? 0, ys.max() ?? 1)
        return p.mapValues { CGPoint(x: x1 > x0 ? ($0.x - x0) / (x1 - x0) : 0.5, y: y1 > y0 ? ($0.y - y0) / (y1 - y0) : 0.5) }
    }
}
