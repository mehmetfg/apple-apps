// Mac library views carried over from İdrak Tezgâhı (v10, 2026-10-17): Ağ (which book talks to which, by cluster
// question), Kavramlar (the concepts of every book's room, A–Z), Kaynakça (the works the books rest on) and
// İstatistik (18 weeks of listening and study). Data: LibraryStore.insights + LibraryStore.network (veri/rooms.py).
// A book opens with NavigationLink(value: id) — KitaplarEkrani's stack shows its BookScreen.
import SwiftUI

/// The books that have a room (an insight) and are on the shelf, newest first.
@MainActor
private func roomBooks(_ library: LibraryStore) -> [LibraryEntry] {
    library.index.books.filter { library.insights[$0.id] != nil }
}

private func pane<C: View>(@ViewBuilder _ c: () -> C) -> some View {
    c().padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Tema.yuzey) }
        .overlay { RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Tema.cizgi.opacity(0.6), lineWidth: 0.5) }
}

private func eyebrow(_ t: String) -> some View {
    Text(t.uppercased(with: Dil.tr)).font(.system(size: 11, weight: .bold)).tracking(0.7).foregroundStyle(Tema.vurgu)
}

private struct BookChip: View {
    let entry: LibraryEntry
    var line: String?
    var body: some View {
        NavigationLink(value: entry.id) {
            HStack(spacing: 10) {
                KitapKapagi(id: entry.id, baslik: entry.titleParts.title, genislik: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.titleParts.title).font(.callout.weight(.semibold)).foregroundStyle(Tema.metin).lineLimit(2)
                    if let line { Text(line).font(.caption).foregroundStyle(Tema.ikincil).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 0)
            }
            .padding(10).tamGenislik()
            .background { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Tema.yuzey2) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Ağ

struct ReadingNetworkView: View {
    @ObservedObject private var library = LibraryStore.shared
    @State private var cluster: String?
    @State private var selected: String?

    private var books: [LibraryEntry] { roomBooks(library) }
    private func clusterOf(_ id: String) -> String { library.network.books[id]?.cluster ?? "diger" }
    private func members(_ c: String) -> [LibraryEntry] { books.filter { clusterOf($0.id) == c } }
    private var clusters: [String] { library.network.clusterIds }
    private var current: String { cluster ?? clusters.first { !members($0).isEmpty } ?? clusters.first ?? "diger" }
    private var linkCount: Int { books.reduce(0) { $0 + (library.insights[$1.id]?.links?.count ?? 0) } }

    var body: some View {
        HStack(spacing: 16) {
            pane { board }
            pane { ScrollView { detail } }.frame(width: 360)
        }
        .padding(.horizontal, 18).padding(.bottom, 18)
    }

    // the board: orb → cluster cards → fan of the cluster's books, wired with curves (İdrak's Ağ)
    private var board: some View {
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height
            let ids = clusters
            let cardX: CGFloat = 250, cardW: CGFloat = 220, cardH: CGFloat = 64, gap: CGFloat = 14
            let total = CGFloat(ids.count) * cardH + CGFloat(max(ids.count - 1, 0)) * gap
            let top0 = max(86, H / 2 + 20 - total / 2)
            let cy: (Int) -> CGFloat = { top0 + CGFloat($0) * (cardH + gap) + cardH / 2 }
            let orb = CGPoint(x: 110, y: H / 2 + 10)
            let ci = ids.firstIndex(of: current) ?? 0
            let list = members(current)
            let sp: CGFloat = 74
            let fanX0 = cardX + cardW + max(70, (W - cardX - cardW) * 0.14)
            let center = min(max(cy(ci), 60 + CGFloat(max(list.count - 1, 0)) * sp / 2), H - 60 - CGFloat(max(list.count - 1, 0)) * sp / 2)
            let half = max(CGFloat(max(list.count - 1, 0)) * sp / 2, 1) + 80
            let fan: [(LibraryEntry, CGPoint)] = list.enumerated().map { j, e in
                let y = center + (CGFloat(j) - CGFloat(list.count - 1) / 2) * sp
                let dy = (y - center) / half
                return (e, CGPoint(x: fanX0 + 50 * (1 - dy * dy), y: y))
            }
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    func curve(_ a: CGPoint, _ b: CGPoint) -> Path {
                        var p = Path(); p.move(to: a)
                        let m = (a.x + b.x) / 2
                        p.addCurve(to: b, control1: CGPoint(x: m, y: a.y), control2: CGPoint(x: m, y: b.y))
                        return p
                    }
                    for (i, id) in ids.enumerated() {
                        let on = id == current
                        ctx.stroke(curve(CGPoint(x: orb.x + 70, y: orb.y), CGPoint(x: cardX, y: cy(i))),
                                   with: .color(on ? Tema.vurgu.opacity(0.7) : Tema.ikincil.opacity(0.18)), lineWidth: on ? 1.6 : 1)
                    }
                    for (e, p) in fan {
                        let on = e.id == selected
                        ctx.stroke(curve(CGPoint(x: cardX + cardW, y: cy(ci)), CGPoint(x: p.x - 6, y: p.y)),
                                   with: .color(on ? Tema.vurgu : Tema.vurgu.opacity(0.35)), lineWidth: on ? 2 : 1.1)
                    }
                    // cross links of the selected book: to a book in this fan, or to another cluster card
                    if let s = selected, let sp = fan.first(where: { $0.0.id == s })?.1 {
                        for l in library.insights[s]?.links ?? [] {
                            if let tp = fan.first(where: { $0.0.id == l.to })?.1 {
                                var p = Path(); p.move(to: CGPoint(x: sp.x + 30, y: sp.y + 24))
                                p.addCurve(to: CGPoint(x: tp.x + 30, y: tp.y - 24), control1: CGPoint(x: sp.x + 110, y: (sp.y + tp.y) / 2),
                                           control2: CGPoint(x: tp.x + 110, y: (sp.y + tp.y) / 2))
                                ctx.stroke(p, with: .color(Tema.basari), style: StrokeStyle(lineWidth: 1.6, dash: [5, 4]))
                            } else if let ti = ids.firstIndex(of: clusterOf(l.to)), ti != ci {
                                ctx.stroke(curve(CGPoint(x: sp.x - 6, y: sp.y), CGPoint(x: cardX + cardW, y: cy(ti))),
                                           with: .color(Tema.basari), style: StrokeStyle(lineWidth: 1.6, dash: [5, 4]))
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    eyebrow("Okuma ağı · \(books.count) metin · \(linkCount) bağ")
                    Text("Hangi metin neyle konuşuyor?").font(Tema.serif(.title2, .semibold)).foregroundStyle(Tema.metin)
                }
                .padding(.leading, 4)
                VStack(spacing: 4) {
                    OrbView().frame(width: 150, height: 150)
                    Text("Okuma ağın").font(Tema.serif(.headline)).foregroundStyle(Tema.metin)
                    Text("\(ids.filter { !members($0).isEmpty }.count) / \(ids.count) küme dolu").font(.caption).foregroundStyle(Tema.soluk)
                }
                .frame(width: 160).position(x: orb.x, y: orb.y)
                ForEach(Array(ids.enumerated()), id: \.element) { i, id in
                    clusterCard(id).frame(width: cardW, height: cardH).position(x: cardX + cardW / 2, y: cy(i))
                }
                if fan.isEmpty, let q = library.network.clusters[current]?.question {
                    Text("“\(q)” — bu soruya henüz bir metinle girmedin.").font(Tema.serif(.callout)).italic().foregroundStyle(Tema.ikincil)
                        .frame(width: max(160, W - fanX0 - 20), alignment: .leading).position(x: fanX0 + max(160, W - fanX0 - 20) / 2, y: cy(ci))
                }
                ForEach(fan, id: \.0.id) { e, p in
                    let w = min(W - p.x - 8, 360)
                    fanRow(e).frame(width: max(w, 120), height: 58).position(x: p.x + max(w, 120) / 2, y: p.y)
                }
            }
            .animation(.snappy, value: current)
            .animation(.snappy, value: selected)
        }
    }

    private func clusterCard(_ id: String) -> some View {
        let m = members(id)
        let on = id == current
        let pr = m.isEmpty ? 0 : m.reduce(0) { $0 + $1.percent } / m.count
        let linked = selected.map { s in (library.insights[s]?.links ?? []).filter { clusterOf($0.to) == id }.count } ?? 0
        return Button { cluster = id; selected = members(id).first?.id } label: {
            HStack(spacing: 10) {
                Text(String(library.network.clusters[id]?.name.prefix(1) ?? "?")).font(.system(size: 15, weight: .bold, design: .serif))
                    .frame(width: 32, height: 32).background { RoundedRectangle(cornerRadius: 9).fill(on ? Color.white.opacity(0.2) : Tema.yuzey2) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(library.network.clusters[id]?.name ?? id).font(.callout.weight(.semibold)).lineLimit(1)
                    Text("\(m.count) metin · %\(pr)").font(.caption2).opacity(0.75)
                }
                Spacer(minLength: 0)
                if linked > 0 && !on { Text("↔ \(linked)").font(.caption2.weight(.bold)).foregroundStyle(Tema.basari) }
            }
            .foregroundStyle(on ? Color.white : Tema.metin)
            .padding(.horizontal, 12).frame(maxHeight: .infinity)
            .background { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(on ? Tema.vurgu : Tema.yuzey2) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(library.network.clusters[id]?.question ?? "")
    }

    private func fanRow(_ e: LibraryEntry) -> some View {
        let on = e.id == selected
        return Button { selected = e.id } label: {
            HStack(spacing: 10) {
                Circle().fill(Tema.vurgu).frame(width: 7, height: 7)
                KitapKapagi(id: e.id, baslik: e.titleParts.title, genislik: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.titleParts.title).font(.callout.weight(.semibold)).foregroundStyle(Tema.metin).lineLimit(1)
                    Text(library.insights[e.id]?.core?.theme ?? library.insights[e.id]?.thesis ?? "").font(.caption2).foregroundStyle(Tema.ikincil).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).frame(maxHeight: .infinity)
            .background { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(on ? Tema.vurgu.opacity(0.14) : Tema.yuzey) }
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? Tema.vurgu : Tema.cizgi, lineWidth: on ? 1.4 : 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var detail: some View {
        if let id = selected ?? members(current).first?.id, let e = library.entry(id), let ins = library.insights[id] {
            let links = ins.links ?? []
            let mine = Set((ins.sources ?? []).compactMap { $0.author.map(Dil.normal) })
            let sharedSrc: [(String, [LibraryEntry])] = mine.compactMap { a in
                let others = books.filter { $0.id != id && (library.insights[$0.id]?.sources ?? []).contains { $0.author.map(Dil.normal) == a } }
                let name = (ins.sources ?? []).first { $0.author.map(Dil.normal) == a }?.author ?? a
                return others.isEmpty ? nil : (name, others)
            }.sorted { $0.0 < $1.0 }
            let concepts = Set((ins.concepts?.nodes ?? []).map { Dil.normal($0.label) })
            let sharedCon: [(String, LibraryEntry)] = books.filter { $0.id != id }.flatMap { o in
                (library.insights[o.id]?.concepts?.nodes ?? []).filter { concepts.contains(Dil.normal($0.label)) }.map { ($0.label, o) }
            }
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    KitapKapagi(id: e.id, baslik: e.titleParts.title, genislik: 54)
                    VStack(alignment: .leading, spacing: 4) {
                        eyebrow(library.network.clusters[clusterOf(id)]?.name ?? "")
                        Text(e.titleParts.title).font(Tema.serif(.title3, .semibold)).foregroundStyle(Tema.metin)
                    }
                }
                if let c = ins.core?.claim ?? ins.thesis {
                    Text(c).font(Tema.serif(.body)).italic().foregroundStyle(Tema.ikincil).fixedSize(horizontal: false, vertical: true)
                }
                section("Doğrudan bağlar") {
                    if links.isEmpty { empty("Başka bir metne tanımlı bağ yok.") }
                    ForEach(Array(links.enumerated()), id: \.offset) { _, l in
                        if let t = library.entry(l.to) {
                            Button { cluster = clusterOf(t.id); selected = t.id } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text((l.kind ?? "bağlı").uppercased(with: Dil.tr)).font(.system(size: 10, weight: .bold)).foregroundStyle(Tema.basari)
                                    Text(t.titleParts.title).font(.callout.weight(.semibold)).foregroundStyle(Tema.metin)
                                    if let n = l.note { Text(n).font(.caption).foregroundStyle(Tema.ikincil).fixedSize(horizontal: false, vertical: true) }
                                }
                                .padding(10).tamGenislik()
                                .background { RoundedRectangle(cornerRadius: 12).fill(Tema.yuzey2) }
                            }.buttonStyle(.plain)
                        }
                    }
                }
                section("Ortak kaynak") {
                    if sharedSrc.isEmpty { empty("Kaynakçası başka bir metinle kesişmiyor.") }
                    ForEach(sharedSrc, id: \.0) { a, others in
                        Text("**\(a)** · \(others.map(\.titleParts.title).joined(separator: ", ")) ile").font(.caption).foregroundStyle(Tema.ikincil)
                    }
                }
                section("Ortak kavram") {
                    if sharedCon.isEmpty { empty("Kavramları başka metinle çakışmıyor.") }
                    AkanYerlesim(aralik: 6) {
                        ForEach(Array(sharedCon.enumerated()), id: \.offset) { _, x in Hap(metin: "\(x.0) · \(x.1.titleParts.title)", renk: Tema.ikincil) }
                    }
                }
                NavigationLink(value: e.id) { Label("Kitabı aç", systemImage: "arrow.right.circle.fill") }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
        } else {
            empty("Bir küme ve bir metin seç.")
        }
    }

    private func section<C: View>(_ t: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t.uppercased(with: Dil.tr)).font(.system(size: 10.5, weight: .bold)).tracking(0.6).foregroundStyle(Tema.soluk)
            c()
        }
    }
    private func empty(_ t: String) -> some View { Text(t).font(.caption).foregroundStyle(Tema.soluk) }
}

/// İdrak's orb: a golden-angle sphere of points turning slowly, two bands lit. Still when Reduce Motion is on.
struct OrbView: View {
    @Environment(\.accessibilityReduceMotion) private var reduce
    private static let points: [(Double, Double, Double)] = (0..<420).map { i in
        let y = 1 - Double(i) / 419 * 2, r = (1 - y * y).squareRoot(), th = Double.pi * (3 - 5.0.squareRoot()) * Double(i)
        return (cos(th) * r, y, sin(th) * r)
    }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduce)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate * 1000
                let R = size.width * 0.44, a = t * 0.00022, band = sin(t * 0.0008), band2 = cos(t * 0.0006) * 0.8
                let ca = cos(a), sa = sin(a), tilt = 0.38, ct = cos(tilt), st = sin(tilt)
                for (x, y, z) in Self.points {
                    let x1 = x * ca + z * sa, z1 = -x * sa + z * ca, y2 = y * ct - z1 * st, z2 = y * st + z1 * ct, dp = (z2 + 1) / 2
                    let n1 = abs(y - band) < 0.08, n2 = abs(x - band2) < 0.06
                    let r = ((n1 || n2) ? 1.7 : 1.1) * (0.6 + dp) * 1.3
                    let c: Color = n1 ? Tema.vurgu : (n2 ? Tema.basari : Tema.ikincil)
                    ctx.opacity = (n1 || n2) ? 0.35 + 0.65 * dp : 0.08 + 0.5 * dp
                    ctx.fill(Path(ellipseIn: CGRect(x: size.width / 2 + x1 * R - r, y: size.height / 2 + y2 * R - r, width: 2 * r, height: 2 * r)), with: .color(c))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Kavramlar

struct ConceptIndexView: View {
    @ObservedObject private var library = LibraryStore.shared
    @State private var query = ""
    @State private var selected: String?

    struct Use: Identifiable { let entry: LibraryEntry; let node: BookInsight.Node; let edges: [(String, String, String)]; var id: String { entry.id + node.id } }
    struct Item: Identifiable { let key: String; let name: String; var uses: [Use]; var id: String { key } }

    private var items: [Item] {
        var m: [String: Item] = [:]
        for e in roomBooks(library) {
            guard let c = library.insights[e.id]?.concepts else { continue }
            for n in c.nodes {
                let edges = c.edges.filter { $0.a == n.id || $0.b == n.id }.map { x -> (String, String, String) in
                    let o = c.nodes.first { $0.id == (x.a == n.id ? x.b : x.a) }?.label ?? ""
                    return (x.a == n.id ? "→" : "←", x.label ?? "bağlı", o)
                }
                let k = Dil.normal(n.label)
                m[k, default: Item(key: k, name: n.label, uses: [])].uses.append(Use(entry: e, node: n, edges: edges))
            }
        }
        return m.values.sorted { $0.name.compare($1.name, locale: Dil.tr) == .orderedAscending }
    }

    var body: some View {
        let all = items
        let q = Dil.normal(query)
        let list = q.isEmpty ? all : all.filter { Dil.normal($0.name + " " + $0.uses.compactMap(\.node.note).joined(separator: " ")).contains(q) }
        let current = all.first { $0.key == selected } ?? list.first
        HStack(spacing: 16) {
            pane {
                VStack(alignment: .leading, spacing: 12) {
                    eyebrow("\(all.count) kavram · \(roomBooks(library).count) metin")
                    Text("Kavram sözlüğü").font(Tema.serif(.title2, .semibold)).foregroundStyle(Tema.metin)
                    TextField("Kavram ya da tanım ara", text: $query).textFieldStyle(.roundedBorder)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(list.enumerated()), id: \.element.id) { i, x in
                                let l = String(x.name.prefix(1)).uppercased(with: Dil.tr)
                                if i == 0 || String(list[i - 1].name.prefix(1)).uppercased(with: Dil.tr) != l {
                                    Text(l).font(.system(size: 13, weight: .bold, design: .serif)).foregroundStyle(Tema.vurgu).padding(.top, 10).padding(.leading, 6)
                                }
                                Button { selected = x.key } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(x.name).font(.callout.weight(.semibold)).foregroundStyle(Tema.metin)
                                        Text(x.uses.map(\.entry.titleParts.title).joined(separator: " · ")).font(.caption2).foregroundStyle(Tema.soluk).lineLimit(1)
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 7).tamGenislik()
                                    .background { RoundedRectangle(cornerRadius: 10).fill(x.key == current?.key ? Tema.vurgu.opacity(0.12) : .clear) }
                                    .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                            if list.isEmpty { Text("Eşleşen kavram yok.").font(.caption).foregroundStyle(Tema.soluk) }
                        }
                    }
                }
            }
            .frame(width: 360)
            pane {
                ScrollView {
                    if let x = current {
                        VStack(alignment: .leading, spacing: 14) {
                            eyebrow("\(x.uses.count) metinde")
                            Text(x.name).font(Tema.serif(.largeTitle, .semibold)).foregroundStyle(Tema.metin)
                            ForEach(x.uses) { u in
                                VStack(alignment: .leading, spacing: 10) {
                                    if let n = u.node.note { Text(n).font(Tema.serif(.title3)).foregroundStyle(Tema.metin).fixedSize(horizontal: false, vertical: true) }
                                    if !u.edges.isEmpty {
                                        Text("BU METİNDEKİ BAĞLARI").font(.system(size: 10.5, weight: .bold)).tracking(0.6).foregroundStyle(Tema.soluk)
                                        ForEach(Array(u.edges.enumerated()), id: \.offset) { _, e in
                                            Button { selected = Dil.normal(e.2) } label: {
                                                Text(e.0 == "→" ? "**\(x.name)** \(e.1) **\(e.2)**" : "**\(e.2)** \(e.1) **\(x.name)**")
                                                    .font(.callout).foregroundStyle(Tema.ikincil)
                                            }.buttonStyle(.plain)
                                        }
                                    }
                                    BookChip(entry: u.entry, line: library.network.books[u.entry.id].flatMap { library.network.clusters[$0.cluster]?.name })
                                }
                                .padding(16).tamGenislik()
                                .background { RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Tema.arka.opacity(0.6)) }
                            }
                        }
                    } else {
                        Text("Henüz kavram haritası olan bir kitap yok.").foregroundStyle(Tema.soluk)
                    }
                }
            }
        }
        .padding(.horizontal, 18).padding(.bottom, 18)
    }
}

// MARK: - Kaynakça

struct SourcesIndexView: View {
    @ObservedObject private var library = LibraryStore.shared
    @State private var filter = "all"
    @State private var query = ""
    @State private var selected: String?

    struct Ref: Identifiable {
        let key: String; let work: String; let author: String; let year: Int?
        var kinds: Set<String>; var cites: [(LibraryEntry, String)]
        var id: String { key }
    }

    private var refs: [Ref] {
        var m: [String: Ref] = [:]
        for e in roomBooks(library) {
            for s in library.insights[e.id]?.sources ?? [] {
                let k = Dil.normal(s.work + " " + (s.author ?? ""))
                var r = m[k] ?? Ref(key: k, work: s.work, author: s.author ?? "", year: s.year, kinds: [], cites: [])
                r.kinds.insert(s.isReference ? "ref" : "read")
                if !r.cites.contains(where: { $0.0.id == e.id }) { r.cites.append((e, s.why ?? "")) }
                m[k] = r
            }
        }
        return m.values.sorted { ($0.cites.count, $1.author) > ($1.cites.count, $0.author) }
    }

    var body: some View {
        let all = refs
        let q = Dil.normal(query)
        let list = all.filter { (filter == "all" || $0.kinds.contains(filter)) && (q.isEmpty || Dil.normal($0.work + " " + $0.author).contains(q)) }
        let current = all.first { $0.key == selected } ?? list.first
        var authors: [String: Set<String>] = [:]
        for r in all { for a in r.author.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !a.isEmpty {
            authors[a, default: []].formUnion(r.cites.map(\.0.id)) } }
        let multi = authors.filter { $0.value.count > 1 }.sorted { $0.value.count > $1.value.count }
        return HStack(spacing: 16) {
            pane {
                VStack(alignment: .leading, spacing: 12) {
                    eyebrow("\(all.count) eser · \(roomBooks(library).count) metin")
                    HStack {
                        Text("Kaynakça").font(Tema.serif(.title2, .semibold)).foregroundStyle(Tema.metin)
                        Spacer()
                        Picker("", selection: $filter) { Text("Tümü").tag("all"); Text("Başvuru").tag("ref"); Text("Öneri").tag("read") }
                            .pickerStyle(.segmented).fixedSize()
                    }
                    TextField("Eser ya da yazar ara", text: $query).textFieldStyle(.roundedBorder)
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(list) { r in
                                Button { selected = r.key } label: {
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(r.work).font(Tema.serif(.callout, .semibold)).foregroundStyle(Tema.metin).multilineTextAlignment(.leading)
                                            Text([r.author, r.year.map(String.init) ?? "", r.kinds.sorted().map { $0 == "ref" ? "başvuru" : "öneri" }.joined(separator: " + ")]
                                                .filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption2).foregroundStyle(Tema.soluk)
                                        }
                                        Spacer()
                                        if r.cites.count > 1 { Text("\(r.cites.count)").font(.caption.weight(.bold)).foregroundStyle(Tema.vurgu) }
                                    }
                                    .padding(10).tamGenislik()
                                    .background { RoundedRectangle(cornerRadius: 12).fill(r.key == current?.key ? Tema.vurgu.opacity(0.12) : .clear) }
                                    .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                            if list.isEmpty { Text("Kaynakçası olan kitap yok ya da arama eşleşmedi.").font(.caption).foregroundStyle(Tema.soluk) }
                        }
                    }
                }
            }
            .frame(minWidth: 380)
            pane {
                ScrollView {
                    if let r = current {
                        VStack(alignment: .leading, spacing: 14) {
                            eyebrow([r.author, r.year.map(String.init) ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                            Text(r.work).font(Tema.serif(.title, .semibold)).foregroundStyle(Tema.metin)
                            Text("ATIF YAPAN METİNLER · \(r.cites.count)").font(.system(size: 10.5, weight: .bold)).tracking(0.6).foregroundStyle(Tema.soluk)
                            ForEach(r.cites, id: \.0.id) { e, why in BookChip(entry: e, line: why) }
                            Text("BİRDEN ÇOK METİNDE GEÇEN YAZARLAR").font(.system(size: 10.5, weight: .bold)).tracking(0.6).foregroundStyle(Tema.soluk).padding(.top, 8)
                            if multi.isEmpty { Text("Henüz yok.").font(.caption).foregroundStyle(Tema.soluk) }
                            AkanYerlesim(aralik: 6) { ForEach(multi, id: \.key) { a, s in Hap(metin: "\(a) · \(s.count)", renk: Tema.ikincil) } }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 18).padding(.bottom, 18)
    }
}

// MARK: - İstatistik

struct ShelfStatsView: View {
    @EnvironmentObject var depo: Depo
    @ObservedObject private var library = LibraryStore.shared
    private let weeks = 18

    var body: some View {
        let books = library.index.books
        let rooms = roomBooks(library)
        var listened: [String: [LibraryEntry]] = [:]
        for e in books {
            let days = library.network.books[e.id]?.reads.map(\.date) ?? [String((e.last ?? e.added ?? "").prefix(10))]
            for d in Set(days) where !d.isEmpty { listened[d, default: []].append(e) }
        }
        let studied = Set(depo.olaylar.map(\.gun))
        let words = books.filter { $0.percent > 0 }.reduce(0) { $0 + $1.words * $1.percent / 100 }
        let minutes = words / 130
        let keyCount = rooms.reduce(0) { $0 + (library.insights[$1.id]?.keys?.count ?? 0) }
        let today = Tarih.takvim.startOfDay(for: Date())
        let weekday = (Tarih.takvim.component(.weekday, from: today) + 5) % 7      // Monday = 0
        let start = today.gun(-weekday - (weeks - 1) * 7)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    kpi("\(books.count)", "kitap rafta")
                    kpi("\(minutes / 60) sa \(minutes % 60) dk", "dinleme (≈130 k/dk)")
                    kpi("\(books.reduce(0) { $0 + $1.highlights })", "işaret")
                    kpi("\(keyCount)", "can alıcı cümle")
                    kpi("\(studied.count)", "Teoria'da çalışma günü")
                }
                pane {
                    VStack(alignment: .leading, spacing: 14) {
                        eyebrow("Son \(weeks) hafta")
                        Text("Hangi gün ne dinlendi, ne çalışıldı").font(Tema.serif(.title3, .semibold)).foregroundStyle(Tema.metin)
                        LazyHGrid(rows: Array(repeating: GridItem(.fixed(15), spacing: 4), count: 7), spacing: 4) {
                            ForEach(0..<(weeks * 7), id: \.self) { i in
                                let d = start.gun(i)
                                let k = Tarih.gun(d)
                                let n = listened[k]?.count ?? 0
                                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                    .fill(d > today ? Color.clear : studied.contains(k) ? Tema.basari : n > 1 ? Tema.vurgu : n == 1 ? Tema.vurgu.opacity(0.35) : Tema.cizgi)
                                    .frame(width: 15, height: 15)
                                    .help("\(k)\(n > 0 ? " · dinlendi: " + (listened[k] ?? []).map(\.titleParts.title).joined(separator: ", ") : "")\(studied.contains(k) ? " · Teoria'da çalışıldı" : "")")
                            }
                        }
                        .frame(height: 7 * 19)
                        HStack(spacing: 14) {
                            legend(Tema.cizgi, "boş"); legend(Tema.vurgu.opacity(0.35), "dinleme"); legend(Tema.vurgu, "2+ metin"); legend(Tema.basari, "Teoria'da çalışma")
                        }
                        .font(.caption).foregroundStyle(Tema.soluk)
                    }
                }
                HStack(alignment: .top, spacing: 16) {
                    pane {
                        VStack(alignment: .leading, spacing: 10) {
                            eyebrow("Metin başına · odası olanlar")
                            ForEach(rooms) { e in
                                NavigationLink(value: e.id) {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(e.titleParts.title).font(.callout.weight(.semibold)).foregroundStyle(Tema.metin).lineLimit(1)
                                            Text("\(e.words.formatted()) kelime · \(e.highlights) işaret · \(library.insights[e.id]?.keys?.count ?? 0) can alıcı")
                                                .font(.caption2).foregroundStyle(Tema.soluk)
                                        }
                                        Spacer()
                                        Capsule().fill(Tema.cizgi).frame(width: 120, height: 6)
                                            .overlay(alignment: .leading) { Capsule().fill(Tema.vurgu).frame(width: 120 * CGFloat(min(e.percent, 100)) / 100, height: 6) }
                                        Text("%\(e.percent)").font(.caption.monospacedDigit()).foregroundStyle(Tema.ikincil).frame(width: 36, alignment: .trailing)
                                    }
                                    .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    pane {
                        let ids = library.network.clusterIds
                        let counts = ids.map { id in rooms.filter { library.network.books[$0.id]?.cluster == id }.count }
                        let total = max(counts.reduce(0, +), 1)
                        let colors: [Color] = [Tema.vurgu, Tema.basari, Tema.uyari, Tema.altin, Tema.ikincil, Tema.soluk]
                        VStack(alignment: .leading, spacing: 12) {
                            eyebrow("Kümelere dağılım")
                            GeometryReader { g in
                                HStack(spacing: 2) {
                                    ForEach(Array(ids.enumerated()), id: \.offset) { i, _ in
                                        if counts[i] > 0 { RoundedRectangle(cornerRadius: 4).fill(colors[i % colors.count]).frame(width: g.size.width * CGFloat(counts[i]) / CGFloat(total) - 2) }
                                    }
                                }
                            }
                            .frame(height: 16)
                            ForEach(Array(ids.enumerated()), id: \.offset) { i, id in
                                HStack(spacing: 8) {
                                    Circle().fill(colors[i % colors.count]).frame(width: 8, height: 8)
                                    Text(library.network.clusters[id]?.name ?? id).font(.callout)
                                    Text("\(counts[i])").font(.callout.weight(.bold))
                                    if counts[i] == 0 { Text("— boş, keşfedilmemiş").font(.caption).foregroundStyle(Tema.soluk) }
                                }
                            }
                        }
                    }
                    .frame(width: 340)
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 18)
        }
    }

    private func kpi(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(v).font(.system(.title2, design: .rounded).weight(.bold)).foregroundStyle(Tema.metin)
            Text(l).font(.caption).foregroundStyle(Tema.ikincil)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background { RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Tema.yuzey) }
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 5) { RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 11, height: 11); Text(t) }
    }
}
