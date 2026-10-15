// Book home — the cover, two doors into the text (whole · only highlights) and the work around it:
// Özet (the book's judgments, chapter by chapter), Harita (concept map), İşaretler, Pekiştir (what you missed → recall).
import SwiftUI

enum BookTab: String, CaseIterable, Identifiable {
    case summary, map, marks, practice
    var id: String { rawValue }
    var name: String { switch self { case .summary: "Özet"; case .map: "Harita"; case .marks: "İşaretler"; case .practice: "Pekiştir" } }
    var symbol: String { switch self { case .summary: "text.alignleft"; case .map: "point.3.connected.trianglepath.dotted"; case .marks: "highlighter"; case .practice: "brain.head.profile" } }
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
    @State private var tab: BookTab = .summary
    @State private var reader: ReaderRequest?
    @State private var onlyChapters = false
    @State private var recall: Isaret?
    @State private var node: BookInsight.Node?

    private var insight: BookInsight? { library.insights[entry.id] }
    private var tint: Color { Tema.kitap(entry.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                doors
                SimgeSecici(secenekler: BookTab.allCases.map { .init(deger: $0, ad: $0.name, sembol: $0.symbol) },
                            secili: $tab, sikisik: false)
                Group {
                    switch tab {
                    case .summary: summary
                    case .map: map
                    case .marks: marks
                    case .practice: practice
                    }
                }
                .transition(.opacity)
            }
            .padding(20)
            .frame(maxWidth: 820).frame(maxWidth: .infinity)
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

    // MARK: hero

    private var hero: some View {
        HStack(alignment: .bottom, spacing: 22) {
            KitapKapagi(id: entry.id, baslik: entry.titleParts.title, genislik: 132)
                .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
            VStack(alignment: .leading, spacing: 8) {
                if let a = entry.titleParts.author { Text(a).font(.subheadline).foregroundStyle(Tema.ikincil) }
                Text(entry.titleParts.title).font(Tema.serif(.title2, .semibold)).foregroundStyle(Tema.metin)
                    .fixedSize(horizontal: false, vertical: true)
                if let t = insight?.thesis { Text(t).font(Tema.serif(.footnote)).italic().foregroundStyle(Tema.ikincil).lineLimit(4) }
                HStack(spacing: 12) {
                    ZStack {
                        Halka(oran: Double(entry.percent) / 100, renk: tint, kalinlik: 4)
                        Text("%\(entry.percent)").font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(entry.chapters) bölüm · \(entry.highlights) işaret").font(.footnote.weight(.medium))
                        Text("~\(max(1, entry.words / 250)) sayfa · \(entry.inVD ? (entry.claude ? "okuma baskısı" : "özgün metin") : "arşivde (Voice Dream'den silindi)")")
                            .font(.caption).foregroundStyle(Tema.soluk)
                    }
                    .foregroundStyle(Tema.ikincil)
                }
            }
        }
    }

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

    // MARK: Özet

    @ViewBuilder
    private var summary: some View {
        if let ins = insight, let book {
            VStack(alignment: .leading, spacing: 18) {
                if !onlyChapters {
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
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Tema.yuzey))
                }
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
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Tema.yuzey))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
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
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Tema.yuzey))
    }

    private func pendingNote(_ t: String, _ d: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(t, systemImage: "hourglass").font(.headline).foregroundStyle(Tema.metin)
            Text(d).font(.callout).foregroundStyle(Tema.ikincil)
        }
        .padding(16).tamGenislik()
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Tema.yuzey2))
    }

    // MARK: Harita

    @ViewBuilder
    private var map: some View {
        if let c = insight?.concepts, !c.nodes.isEmpty, let book {
            VStack(alignment: .leading, spacing: 12) {
                ConceptMapView(map: c, tint: tint, selected: $node)
                    .frame(height: max(460, CGFloat(c.nodes.count) * 44))
                    .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Tema.yuzey))
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
                        if let chs = n.ch, !chs.isEmpty {
                            AkanYerlesim(aralik: 6) {
                                ForEach(chs, id: \.self) { ci in
                                    Button { reader = ReaderRequest(mode: .full, ch: ci, b: 0) } label: {
                                        Text(book.chapters[safe: ci]?.title ?? "Bölüm \(ci + 1)").font(.caption.weight(.semibold)).lineLimit(1)
                                            .padding(.horizontal, 10).padding(.vertical, 6)
                                            .background(Capsule().fill(tint.opacity(0.14))).foregroundStyle(tint)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(16).tamGenislik()
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Tema.yuzey))
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
                pendingNote("İşaret yok", "Voice Dream'de işaretlediğin cümleler burada, kitaptaki yerleriyle durur.")
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
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Tema.yuzey))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Pekiştir — the essence you did not mark

    @ViewBuilder
    private var practice: some View {
        if let missed = insight?.missed, !missed.isEmpty, let book {
            VStack(alignment: .leading, spacing: 12) {
                Text("İşaretlemediğin ama kitabı taşıyan yerler. Önce kapalıyken hatırla, sonra kendi cümlenle yeniden kur.")
                    .font(.footnote).foregroundStyle(Tema.ikincil)
                ForEach(missed) { m in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(book.chapters[safe: m.ch]?.title ?? "").font(.caption.weight(.semibold)).foregroundStyle(tint)
                        Text(m.why).font(Tema.serif(.body)).foregroundStyle(Tema.metin).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button {
                                recall = Isaret(id: "oz:\(entry.id):\(m.ch).\(m.b)", kitap: entry.id, baslik: entry.title, metin: m.quote,
                                                renk: 1, tarih: insight?.built ?? Tarih.gun(Date()), kaynak: "kitap-oz", baglam: m.why)
                            } label: { Label("Kapat · hatırla", systemImage: "eye.slash") }
                                .buttonStyle(.borderedProminent).tint(tint)
                            Button { reader = ReaderRequest(mode: .full, ch: m.ch, b: m.b) } label: { Label("Metinde gör", systemImage: "book") }
                                .buttonStyle(.bordered)
                        }
                        .controlSize(.small)
                    }
                    .padding(16).tamGenislik()
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Tema.yuzey))
                }
            }
        } else {
            pendingNote("Pekiştirme henüz yok", "Claude özeti yazarken işaretlemediğin taşıyıcı cümleleri de seçer; burada kapat-hatırla kartı olurlar.")
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
                            ctx.draw(Text(l).font(.system(size: 10, weight: .medium)).foregroundColor(tint), at: mid)
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
                            .background(Capsule().fill(on ? tint : (w >= 3 ? tint.opacity(0.18) : Tema.yuzey2)))
                            .overlay(Capsule().strokeBorder(tint.opacity(w >= 2 ? 0.45 : 0.18)))
                            .foregroundStyle(on ? Color.white : Tema.metin)
                            .frame(maxWidth: 150)
                            .position(p)
                            .onTapGesture { Dokunus.secim(); withAnimation(.snappy) { selected = on ? nil : n } }
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
