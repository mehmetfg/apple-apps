// Program · Durum board (2026-11-14): the program × status table, until now a popover inside Tatbik, becomes its own
// page in the sidebar. Programs sit in four groups (apps · app building · production · life); a group opens and closes
// on a click, a program opens to its items, a count cell opens the program at that status. The apps group stays
// closed by default: the app list grows, and the Uygulamalar page holds it in full.
import SwiftUI

enum BoardCategory: String, CaseIterable, Identifiable {
    case apps, building, production, life, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .apps: "Uygulamalar"
        case .building: "Uygulama süreci"
        case .production: "Üretim"
        case .life: "Yaşam"
        case .other: "Diğer"
        }
    }
    var subtitle: String {
        switch self {
        case .apps: "Her uygulamanın kendi maddeleri"
        case .building: "Yeni fikirler ve var olanların bakımı"
        case .production: "Metin üretimi ve mühendislik"
        case .life: "Uygulama dışı: rutin, yöntem, sağlık"
        case .other: "Gruba bağlanmamış programlar"
        }
    }
    var symbol: String {
        switch self {
        case .apps: "app.badge"
        case .building: "hammer"
        case .production: "text.book.closed"
        case .life: "leaf"
        case .other: "folder"
        }
    }
}

extension TatbikProgram {
    /// Tatbik program → app ids in the Uygulamalar registry (apps.json).
    static let appIDs: [String: [String]] = [
        "wise-path": ["voice-reader"], "kivilcim": ["kivilcim"], "teoria": ["teoria"],
        "ingilizce": ["cumle", "memories", "disli", "kursu", "asina"], "gun": ["tekne"], "ufuk": ["ufuk"],
        "gece": ["gece"], "kurultay": ["kurultay"], "orkestra": ["orkestra"], "muhendislik": ["engineering"],
    ]
    private static let fallbackCategory: [String: BoardCategory] = [
        "yeni": .building, "bakim": .building,
        "bir-yone": .production, "muhendislik": .production,
        "hayat": .life, "saglik": .life,
    ]
    /// Short, uniform names for the board (the data keeps its own).
    private static let boardNames: [String: String] = [
        "bir-yone": "Bir Yöne · metin üretimi", "muhendislik": "Mühendislik", "yeni": "Yeni uygulama fikirleri",
        "bakim": "Uygulama bakımı", "hayat": "Rutin ve yöntem", "saglik": "Sağlık sistemi",
        "ingilizce": "İngilizce uygulamaları", "gun": "Gün düzeni · Tekne",
    ]

    var boardCategory: BoardCategory {
        if let c = category.flatMap(BoardCategory.init(rawValue:)) { return c }
        if let c = Self.fallbackCategory[id] { return c }
        return Self.appIDs[id] != nil ? .apps : .other
    }
    var boardName: String { Self.boardNames[id] ?? ad }
    var apps: [String] { Self.appIDs[id] ?? [] }
}

struct ProgramBoardView: View {
    @EnvironmentObject var depo: Depo
    @Binding var selection: String?
    var openApps: () -> Void = {}
    /// Preview mode only: a program shown open.
    var previewOpen: String?
    /// Closed groups, kept between launches. Apps start closed.
    @AppStorage("boardClosed") private var closedRaw = "apps"
    @State private var openProgram: String?
    @State private var programStatus: TatbikStatus?

    private var t: TatbikState { depo.tatbik }
    private var closed: Set<String> { Set(closedRaw.split(separator: ",").map(String.init)) }

    private func programs(_ c: BoardCategory) -> [TatbikProgram] {
        t.programlar.filter { $0.boardCategory == c && !t.items(of: $0.id).isEmpty }
    }
    private func items(_ c: BoardCategory) -> [TatbikItem] {
        let ids = Set(programs(c).map(\.id))
        return t.maddeler.filter { ids.contains($0.program) }
    }

    var body: some View {
        if t.maddeler.isEmpty {
            ContentUnavailableView("Henüz Tatbik yok", systemImage: "tablecells",
                                   description: Text("Claude'a \"Tatbik'i güncelle\" de: kayıtları maddelere böler, programlara bağlar."))
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        VStack(spacing: 14) {
                            columnHeader
                            ForEach(BoardCategory.allCases) { c in
                                if !programs(c).isEmpty { category(c) }
                            }
                        }
                        Text("Bir gruba tıkla: açılır ya da kapanır. Programa tıkla: maddeleri altında açılır. Sayıya tıkla: o durumdaki maddeler.")
                            .font(.caption).foregroundStyle(Ink.faint)
                    }
                    .padding(.horizontal, 28).padding(.vertical, 24)
                    .frame(maxWidth: 1100, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: openProgram) { _, id in
                    guard let id else { return }
                    withAnimation(.snappy) { proxy.scrollTo("p-" + id, anchor: .top) }
                }
            }
            .background(Ink.paper)
            .onAppear { if let previewOpen { openProgram = previewOpen } }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Program ve Durum").font(.system(size: 40, weight: .bold, design: .serif))
                Text("Bütün programlar, gruplarıyla. Neyin açık, neyin yarım, neyin bittiği tek bakışta.")
                    .font(Ink.serif(.title3)).foregroundStyle(Ink.secondary).lineLimit(2)
                Text("Claude son baktı: \(String((t.guncelleme ?? "").prefix(16)).replacingOccurrences(of: "T", with: " "))")
                    .font(.callout).foregroundStyle(Ink.faint)
            }
            Spacer()
            HStack(spacing: 16) {
                ForEach(TatbikStatus.allCases) { s in
                    VStack(spacing: 2) {
                        Text("\(t.count(s))").font(.system(size: 30, weight: .bold, design: .serif)).monospacedDigit()
                            .foregroundStyle(s.color)
                        Label(s.short, systemImage: s.symbol).font(.caption.weight(.semibold)).foregroundStyle(s.color)
                    }
                }
            }
            VStack(spacing: 3) {
                StatusRing(value: t.progress(), color: TatbikStatus.tamam.color, size: 74, line: 8)
                Text("tamamlandı").font(.caption).foregroundStyle(Ink.secondary)
            }
        }
    }

    // MARK: Table

    private static let countWidth: CGFloat = 78
    private static let barWidth: CGFloat = 150

    private var columnHeader: some View {
        HStack(spacing: 8) {
            Text("Program").font(.callout.weight(.semibold)).foregroundStyle(Ink.secondary)
            Spacer()
            ForEach(TatbikStatus.allCases) { s in
                Label(s.short, systemImage: s.symbol).font(.callout.weight(.semibold)).foregroundStyle(s.color)
                    .frame(width: Self.countWidth)
            }
            Text("Toplam").font(.callout.weight(.semibold)).foregroundStyle(Ink.secondary).frame(width: 60)
            Text("İlerleme").font(.callout.weight(.semibold)).foregroundStyle(Ink.secondary).frame(width: Self.barWidth, alignment: .leading)
        }
        .padding(.horizontal, 16)
    }

    private func toggle(_ c: BoardCategory) {
        var s = closed
        if s.contains(c.rawValue) { s.remove(c.rawValue) } else { s.insert(c.rawValue) }
        withAnimation(.snappy) { closedRaw = s.sorted().joined(separator: ",") }
    }

    private func category(_ c: BoardCategory) -> some View {
        let isOpen = !closed.contains(c.rawValue)
        let list = items(c)
        let progs = programs(c)
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Ink.secondary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                    Image(systemName: c.symbol).font(.title3).foregroundStyle(Ink.ember).frame(width: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(c.title).font(Ink.serif(.title2, .bold))
                            Text("\(progs.count) program").font(.callout).foregroundStyle(Ink.faint)
                        }
                        Text(c.subtitle).font(.callout).foregroundStyle(Ink.secondary).lineLimit(1)
                    }
                    if c == .apps {
                        Button { openApps() } label: { Label("Uygulamalar sayfası", systemImage: "arrow.right.circle") }
                            .buttonStyle(.link).padding(.leading, 6)
                            .help("Bütün uygulamalar: devam edenler, bekleyenler, Apple ve Android tarafı")
                    }
                }
                Spacer(minLength: 8)
                countCells(list, emphasised: true, tap: nil)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .contentShape(Rectangle())
            .onTapGesture { toggle(c) }

            if isOpen {
                Rectangle().fill(Ink.line).frame(height: 1)
                VStack(spacing: 0) {
                    ForEach(Array(progs.enumerated()), id: \.element.id) { i, p in
                        if i > 0 { Rectangle().fill(Ink.line.opacity(0.6)).frame(height: 1).padding(.leading, 52) }
                        programRow(p)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(Ink.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Ink.line) }
    }

    @ViewBuilder private func programRow(_ p: TatbikProgram) -> some View {
        let list = t.items(of: p.id)
        let isOpen = openProgram == p.id
        let c = Ink.topic(p.renk ?? "")
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Ink.faint)
                        .rotationEffect(.degrees(isOpen ? 90 : 0)).frame(width: 12)
                    Circle().fill(c).frame(width: 11, height: 11)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.boardName).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        if let a = p.aciklama, !a.isEmpty {
                            Text(a).font(.caption).foregroundStyle(Ink.faint).lineLimit(1)
                        }
                    }
                }
                .padding(.leading, 22)
                Spacer(minLength: 8)
                countCells(list, emphasised: false) { s in
                    withAnimation(.snappy) {
                        if openProgram == p.id && programStatus == s { openProgram = nil; programStatus = nil }
                        else { openProgram = p.id; programStatus = s }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(isOpen ? c.opacity(0.07) : .clear)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.snappy) {
                    if isOpen { openProgram = nil; programStatus = nil } else { openProgram = p.id; programStatus = nil }
                }
            }
            .help(p.ad)
            .id("p-" + p.id)

            if isOpen { programItems(p, list) }
        }
    }

    /// The program's items under its row: open first, the picked status only when a count was clicked.
    private func programItems(_ p: TatbikProgram, _ list: [TatbikItem]) -> some View {
        let shown = list.filter { programStatus == nil || $0.status == programStatus }.sorted(by: TatbikView.smart)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(programStatus.map { "\($0.name) · \(shown.count)" } ?? "Bütün maddeler · \(shown.count)")
                    .font(.callout.weight(.semibold)).foregroundStyle(programStatus?.color ?? Ink.secondary)
                if programStatus != nil {
                    Button("Hepsini göster") { withAnimation(.snappy) { programStatus = nil } }.buttonStyle(.link).font(.callout)
                }
                Spacer()
            }
            ForEach(shown) { m in
                HStack(spacing: 10) {
                    Image(systemName: m.status.symbol).foregroundStyle(m.status.color).font(.title3)
                    Text(m.baslik).font(.system(size: 14, weight: .medium))
                        .foregroundStyle(m.status.isClosed ? Ink.secondary : Ink.text)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if !m.status.isClosed {
                        if let x = m.priorityName { Text(x).font(.caption).foregroundStyle(m.oncelik == "yuksek" ? Ink.ember : Ink.faint) }
                        if let x = m.sizeName { Text(x).font(.caption).foregroundStyle(Ink.faint) }
                        if let a = m.ageDays { Text("\(a) gün").font(.caption.monospacedDigit()).foregroundStyle(a >= 14 ? Ink.gold : Ink.faint) }
                    } else if let d = m.tarih {
                        Text(d).font(.caption.monospacedDigit()).foregroundStyle(Ink.faint)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(selection == m.id ? Ink.ember.opacity(0.12) : Ink.paper.opacity(0.6),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(selection == m.id ? Ink.ember.opacity(0.7) : Ink.line) }
                .contentShape(Rectangle())
                .onTapGesture { selection = m.id }
                .contextMenu { TatbikMenu(m: m) }
            }
            if shown.isEmpty { Text("Bu durumda madde yok.").font(.callout).foregroundStyle(Ink.faint) }
        }
        .padding(.leading, 74).padding(.trailing, 16).padding(.top, 4).padding(.bottom, 12)
    }

    /// Açık · Kısmen · Tamam · Toplam · bar. With `tap` the counts are buttons.
    private func countCells(_ list: [TatbikItem], emphasised: Bool, tap: ((TatbikStatus) -> Void)?) -> some View {
        HStack(spacing: 8) {
            ForEach(TatbikStatus.allCases) { s in
                let n = t.count(s, in: list)
                let label = Text(n == 0 ? "·" : "\(n)")
                    .font(emphasised ? .system(size: 20, weight: .bold, design: .serif).monospacedDigit()
                                     : .body.monospacedDigit().weight(n > 0 ? .semibold : .regular))
                    .foregroundStyle(n == 0 ? Ink.faint : s.color)
                    .frame(width: Self.countWidth, height: emphasised ? 34 : 28)
                    .background(RoundedRectangle(cornerRadius: 7)
                        .fill(s.color.opacity(n == 0 ? 0 : min(0.26, 0.05 + Double(n) * 0.012))))
                if let tap, n > 0 {
                    Button { tap(s) } label: { label }.buttonStyle(.plain).help("\(s.name) maddeleri")
                } else {
                    label
                }
            }
            Text("\(list.count)").font(.body.monospacedDigit().weight(.medium)).foregroundStyle(Ink.secondary).frame(width: 60)
            HStack(spacing: 8) {
                StackedBar(items: list).frame(height: emphasised ? 9 : 7)
                Text("%\(Int((t.progress(list) * 100).rounded()))").font(.caption.monospacedDigit()).foregroundStyle(Ink.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
            .frame(width: Self.barWidth)
        }
    }
}
