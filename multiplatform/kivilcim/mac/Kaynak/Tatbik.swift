// Tatbik (2026-11-05): every Kıvılcım record split into items, items grouped by program, each with a status
// (açık · kısmen · tamamlandı · gerek görülmedi). Claude reviews ("Tatbik'i güncelle"), the user overrides here.
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

struct TatbikView: View {
    @EnvironmentObject var depo: Depo
    @Binding var selection: String?
    let query: String
    @State private var program: String?
    @State private var status: TatbikStatus?
    @AppStorage("tatbikKapaliGizle") private var hideClosed = false

    private var t: TatbikState { depo.tatbik }

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
        if t.maddeler.isEmpty {
            ContentUnavailableView("Henüz Tatbik yok", systemImage: "checklist",
                                   description: Text("Claude'a \"Tatbik'i güncelle\" de: kayıtları maddelere böler, programlara bağlar, yapılıp yapılmadığına bakar."))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    statusRow
                    programGrid
                    matrix
                    list
                }
                .padding(24).frame(maxWidth: 980, alignment: .leading)
            }
            .background(Ink.paper)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tatbik").font(Ink.serif(.largeTitle, .bold))
                Text("Kıvılcım'da söylediklerin, madde madde, program program. Yapıldıysa kanıtıyla.")
                    .font(Ink.serif(.title3)).foregroundStyle(Ink.secondary)
                Text("Claude son baktı: \(String((t.guncelleme ?? "").prefix(16)).replacingOccurrences(of: "T", with: " "))"
                     + ((t.incelenmemis?.isEmpty ?? true) ? "" : " · bakılmamış \(t.incelenmemis!.count) kayıt"))
                    .font(.caption).foregroundStyle(Ink.faint)
            }
            Spacer()
            StatusRing(value: t.progress(), color: TatbikStatus.tamam.color, size: 74, line: 8)
                .help("Karara bağlanan maddeler (tamam + gerek görülmedi)")
        }
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            ForEach(TatbikStatus.allCases) { s in
                let on = status == s
                Button { withAnimation(.snappy) { status = on ? nil : s } } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(s.name, systemImage: s.symbol).font(.caption.weight(.medium)).foregroundStyle(s.color)
                        Text("\(t.count(s, in: program.map { t.items(of: $0) }))").font(Ink.serif(.title, .bold)).monospacedDigit()
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(on ? s.color.opacity(0.14) : Ink.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? s.color : Ink.line) }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var programGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)], spacing: 10) {
            ForEach(t.programlar.filter { !t.items(of: $0.id).isEmpty }) { p in
                let items = t.items(of: p.id)
                let on = program == p.id
                let c = Ink.topic(p.renk ?? "")
                Button { withAnimation(.snappy) { program = on ? nil : p.id } } label: {
                    HStack(spacing: 12) {
                        StatusRing(value: t.progress(items), color: c, size: 40, line: 4)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.ad).font(.callout.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
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
                        Spacer(minLength: 0)
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(on ? c.opacity(0.12) : Ink.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? c : Ink.line) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(p.aciklama ?? p.ad)
            }
        }
    }

    /// Program × status: every cell a count you can click into.
    private var matrix: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Program × durum").font(.headline)
                Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
                    GridRow {
                        Text("").gridColumnAlignment(.leading)
                        ForEach(TatbikStatus.allCases) { s in
                            Image(systemName: s.symbol).foregroundStyle(s.color).frame(width: 54).help(s.name)
                        }
                    }
                    ForEach(t.programlar.filter { !t.items(of: $0.id).isEmpty }) { p in
                        let items = t.items(of: p.id)
                        GridRow {
                            Text(p.ad).font(.caption).lineLimit(1).frame(maxWidth: 260, alignment: .leading)
                            ForEach(TatbikStatus.allCases) { s in
                                let n = t.count(s, in: items)
                                let on = program == p.id && status == s
                                Button { withAnimation(.snappy) { if on { program = nil; status = nil } else { program = p.id; status = s } } } label: {
                                    Text(n == 0 ? "·" : "\(n)").font(.caption.monospacedDigit().weight(n > 0 ? .semibold : .regular))
                                        .frame(width: 54, height: 22)
                                        .foregroundStyle(n == 0 ? Ink.faint : on ? .white : s.color)
                                        .background(RoundedRectangle(cornerRadius: 5)
                                            .fill(on ? s.color : s.color.opacity(n == 0 ? 0 : min(0.32, 0.06 + Double(n) * 0.012))))
                                }
                                .buttonStyle(.plain).disabled(n == 0)
                            }
                        }
                    }
                }
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(listTitle).font(.headline)
                Spacer()
                if status == nil { Toggle("Kapananları gizle", isOn: $hideClosed).toggleStyle(.checkbox).font(.caption) }
                if program != nil || status != nil {
                    Button("Süzgeci kaldır") { withAnimation(.snappy) { program = nil; status = nil } }.controlSize(.small)
                }
            }
            if shown.isEmpty {
                Text("Bu süzgeçte madde yok.").foregroundStyle(Ink.secondary).padding(.vertical, 8)
            }
            ForEach(shown) { m in
                TatbikRow(m: m, program: t.program(m.program), selected: selection == m.id, showProgram: program == nil)
                    .onTapGesture { selection = m.id }
                    .contextMenu { TatbikMenu(m: m) }
            }
        }
    }

    private var listTitle: String {
        var s = program.flatMap { t.program($0)?.ad } ?? "Bütün maddeler"
        if let st = status { s += " · \(st.name)" }
        return s + " · \(shown.count)"
    }
}

struct TatbikRow: View {
    let m: TatbikItem
    let program: TatbikProgram?
    var selected = false
    var showProgram = true
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: m.status.symbol).foregroundStyle(m.status.color).font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(m.baslik).font(.body.weight(.medium))
                    .foregroundStyle(m.status.isClosed ? Ink.secondary : Ink.text)
                    .strikethrough(m.status == .gerekYok, color: Ink.faint)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if showProgram, let p = program {
                        Text(p.ad).font(.caption2.weight(.medium)).foregroundStyle(Ink.topic(p.renk ?? "")).lineLimit(1)
                    }
                    if !m.status.isClosed {
                        if let p = m.priorityName { Text(p).font(.caption2).foregroundStyle(m.oncelik == "yuksek" ? Ink.ember : Ink.secondary) }
                        if let s = m.sizeName { Text(s).font(.caption2).foregroundStyle(Ink.faint) }
                    }
                    if m.status == .tamam, let d = m.tarih { Text(d).font(.caption2.monospacedDigit()).foregroundStyle(Ink.faint) }
                    if m.byUser { Label("senin işaretin", systemImage: "pencil").font(.caption2).foregroundStyle(Ink.faint) }
                    if !(m.notlar ?? []).isEmpty { Label("\(m.notlar!.count)", systemImage: "text.bubble").font(.caption2).foregroundStyle(Ink.faint) }
                }
            }
            Spacer(minLength: 0)
            Text(m.id).font(.caption2.monospaced()).foregroundStyle(Ink.faint)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(selected ? Ink.ember.opacity(0.10) : Ink.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(selected ? Ink.ember.opacity(0.6) : Ink.line) }
        .contentShape(Rectangle())
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

struct TatbikDetail: View {
    @EnvironmentObject var depo: Depo
    @ObservedObject var player = Oynatici.shared
    let id: String
    @Binding var goRecord: String?
    @State private var note = ""
    @State private var copied = false

    var body: some View {
        if let m = depo.tatbik.maddeler.first(where: { $0.id == id }) {
            let p = depo.tatbik.program(m.program)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(p?.ad ?? m.program) · \(m.id)").font(.caption.weight(.medium)).foregroundStyle(Ink.topic(p?.renk ?? ""))
                        Text(m.baslik).font(Ink.serif(.title2, .bold)).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            if let x = m.priorityName { chip("öncelik \(x)") }
                            if let x = m.sizeName { chip(x) }
                            chip(m.byUser ? "durum: senin işaretin" : "durum: Claude'un hükmü")
                        }
                    }
                    HStack(spacing: 6) {
                        ForEach(TatbikStatus.allCases) { s in
                            let on = m.status == s
                            Button { withAnimation(.snappy) { depo.tatbikDuzelt(m.id, "status", s.rawValue) } } label: {
                                Label(s.short, systemImage: s.symbol).font(.callout.weight(.semibold))
                                    .frame(maxWidth: .infinity).padding(.vertical, 7)
                                    .foregroundStyle(on ? .white : s.color)
                                    .background(Capsule().fill(s.color.opacity(on ? 1 : 0.13)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    field("Ayrıntı", m.ayrinti)
                    field(m.status == .tamam ? "Kanıt" : "Şu an var olan", m.kanit)
                    field("Eksik", m.eksik)
                    field("Gerekçe", m.gerekce)
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
        Text(s).font(.caption2).padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(Ink.surface2)).foregroundStyle(Ink.secondary)
    }

    @ViewBuilder private func field(_ title: String, _ v: String?) -> some View {
        if let v, !v.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(Ink.secondary)
                Text(v).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
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
                Label("Tatbik · \(items.filter { $0.status.isClosed }.count)/\(items.count) karara bağlandı", systemImage: "checklist").font(.headline)
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
