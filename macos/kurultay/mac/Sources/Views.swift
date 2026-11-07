import AppKit
import SwiftUI
import WebKit

extension Color {
    init(hex: String?) {
        var v: UInt64 = 0x6B7280
        if let h = hex?.trimmingCharacters(in: CharacterSet(charactersIn: "#")) { Scanner(string: h).scanHexInt64(&v) }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

enum Pane: String, CaseIterable { case meclis = "Meclis", pano = "Pano", rapor = "Rapor", kivilcim = "Kıvılcım", tarayici = "Tarayıcı" }

struct MainView: View {
    @EnvironmentObject var council: Council
    @State private var pane: Pane = .meclis
    @State private var browserSeat: String?
    @State private var composing = false

    var body: some View {
        NavigationSplitView {
            Sidebar(pane: $pane, browserSeat: $browserSeat)
                .navigationSplitViewColumnWidth(min: 230, ideal: 260)
        } detail: {
            ZStack {
                // every tab stays alive and laid out; it is only shown in the browser pane
                if council.engine == "chrome" {
                    if pane == .tarayici { ChromePane(selected: browserSeat ?? council.activeSeats.first?.id) }
                } else {
                    WebDeck(selected: browserSeat ?? council.activeSeats.first?.id)
                        .opacity(pane == .tarayici ? 1 : 0.001)
                        .allowsHitTesting(pane == .tarayici)
                }
                if pane == .kivilcim {
                    SparkPane(library: council.library) { id in council.selectedSession = id; pane = .pano }
                        .background(Color(nsColor: .windowBackgroundColor))
                } else if pane != .tarayici {
                    Group {
                        if let s = council.session(council.selectedSession) {
                            switch pane {
                            case .meclis: SessionView(session: s)
                            case .pano: BoardView(session: s)
                            default: ReportView(session: s)
                            }
                        } else {
                            NewSessionView()
                        }
                    }
                    .background(Color(nsColor: .windowBackgroundColor))
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("", selection: $pane) { ForEach(Pane.allCases, id: \.self) { Text($0.rawValue) } }
                        .pickerStyle(.segmented).frame(width: 430)
                }
                if pane == .tarayici, let id = browserSeat ?? council.activeSeats.first?.id, let w = council.web[id] {
                    ToolbarItemGroup {
                        Button { Task { await w.goBack() } } label: { Image(systemName: "chevron.left") }.help("Geri")
                        Button { Task { await w.reload() } } label: { Image(systemName: "arrow.clockwise") }.help("Yenile")
                        Button { Task { await w.loadNewChat() } } label: { Image(systemName: "square.and.pencil") }.help("Yeni sohbet")
                        Button { Task { await w.refreshState() } } label: { Image(systemName: "stethoscope") }.help("Seçicileri sına")
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newSession)) { _ in pane = .meclis }
        .onOpenURL { url in open(url) }
    }

    /// kurultay://kivilcim?ids=a,b  → adds the records to the selection and opens the Kıvılcım pane
    /// kurultay://oturum?id=X       → opens that session's Pano
    private func open(_ url: URL) {
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func v(_ k: String) -> String? { q.first { $0.name == k }?.value }
        switch url.host {
        case "kivilcim":
            council.library.load()
            council.addToBasket((v("ids") ?? "").split(separator: ",").map(String.init).filter { !$0.isEmpty })
            pane = .kivilcim
        case "oturum":
            if let id = v("id"), council.session(id) != nil { council.selectedSession = id; pane = .pano }
        default: break
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct Sidebar: View {
    @EnvironmentObject var council: Council
    @Binding var pane: Pane
    @Binding var browserSeat: String?

    var body: some View {
        List(selection: Binding(get: { council.selectedSession }, set: { council.selectedSession = $0; if pane == .tarayici || pane == .kivilcim { pane = .pano } })) {
            Section("Kurultaylar") {
                Button { council.selectedSession = nil; pane = .meclis } label: {
                    Label("Yeni kurultay", systemImage: "plus.bubble")
                }.buttonStyle(.plain).foregroundStyle(.tint)
                ForEach(council.sessions) { s in
                    SessionRow(session: s).tag(s.id)
                }
            }
            Section("Meclis") {
                ForEach(council.seats) { seat in
                    SeatRow(seat: seat) { browserSeat = seat.id; pane = .tarayici }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            if let e = council.adapterError { Text(e).font(.caption).foregroundStyle(.red).padding(8) }
        }
    }
}

struct SessionRow: View {
    let session: Session
    var body: some View {
        let dec = SessionFiles.decision(session.id)
        VStack(alignment: .leading, spacing: 2) {
            Text(session.title).lineLimit(1)
            HStack(spacing: 6) {
                Text("\(session.rounds.count) soru").foregroundStyle(.secondary)
                if session.rounds.last.map({ !$0.done }) ?? false { ProgressView().controlSize(.mini) }
                if let d = dec { Text(d.label).foregroundStyle(d.state == "onaylandi" || d.state == "uygulandi" ? .green : .orange) }
                else if SessionFiles.report(session.id) != nil { Text("Rapor hazır").foregroundStyle(.blue) }
            }.font(.caption)
        }
    }
}

struct SeatRow: View {
    @EnvironmentObject var council: Council
    let seat: SeatConfig
    let open: () -> Void

    var body: some View {
        let w = council.web[seat.id]
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { seat.enabled ?? true }, set: { council.setEnabled(seat.id, $0) }))
                .toggleStyle(.checkbox).labelsHidden()
            Circle().fill(Color(hex: seat.color)).frame(width: 9, height: 9)
            Button(action: open) {
                HStack {
                    Text(seat.name)
                    Spacer()
                    if let w { SeatStatus(seat: w) }
                }
            }.buttonStyle(.plain)
        }
    }
}

struct SeatStatus: View {
    @ObservedObject var seat: WebSeat
    var body: some View {
        if seat.busyAsking { ProgressView().controlSize(.mini) }
        else if seat.page.login { Text("giriş").font(.caption2).foregroundStyle(.orange) }
        else if !seat.page.input { Image(systemName: "questionmark.circle").foregroundStyle(.secondary).help("Yazı kutusu bulunamadı") }
        else { Image(systemName: "checkmark.circle").foregroundStyle(.green).help("Hazır") }
    }
}

// MARK: - New session

struct NewSessionView: View {
    @EnvironmentObject var council: Council
    @State private var title = ""
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Kurultay").font(.system(size: 34, weight: .bold, design: .serif))
                Text("Bir meseleyi meclise sor. Her model kendi sekmesinde, düşünme modunda cevaplar; bitenler işaretlenir. Değerlendirmeyi ve ortak kararı Claude yazar, onayı sen verirsin.")
                    .foregroundStyle(.secondary).frame(maxWidth: 620, alignment: .leading)
            }
            TextField("Başlık (isteğe bağlı)", text: $title).textFieldStyle(.roundedBorder).frame(maxWidth: 620)
            Composer(text: $text, placeholder: "Meclise ilk soru…") { seats in
                let s = council.newSession(title: title.isEmpty ? String(text.prefix(60)) : title, seats: seats)
                council.ask(session: s.id, text: text, seats: seats)
                text = ""; title = ""
            }.frame(maxWidth: 820)
            Spacer()
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Session

struct SessionView: View {
    @EnvironmentObject var council: Council
    let session: Session
    @State private var text = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        Text(session.title).font(.system(size: 26, weight: .bold, design: .serif))
                        if session.follow == true || !(session.sources ?? []).isEmpty {
                            HStack(spacing: 8) {
                                FollowBadge(session: session)
                                if let src = session.sources, !src.isEmpty { FlowChips(items: src.map { "🎙 " + $0.title }) }
                            }
                        }
                        ForEach(session.rounds) { r in RoundView(session: session, round: r).id(r.id) }
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: session.rounds.count) { _, _ in withAnimation { proxy.scrollTo(session.rounds.last?.id, anchor: .top) } }
            }
            Divider()
            Composer(text: $text, placeholder: "Ardışık soru (aynı sohbette sürer)…", preselected: session.seats) { seats in
                council.ask(session: session.id, text: text, seats: seats)
                text = ""
            }
            .padding(14)
        }
    }
}

struct RoundView: View {
    @EnvironmentObject var council: Council
    let session: Session
    let round: Round

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Soru \(round.id)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("\(round.doneCount)/\(round.answers.count) ✓").font(.caption).foregroundStyle(round.done ? .green : .secondary)
                Spacer()
                if round.done && round.doneCount < round.answers.count {
                    Button { council.retry(session: session.id, round: round.id) } label: {
                        Label("Bitmeyenleri yeniden sor", systemImage: "arrow.clockwise")
                    }.buttonStyle(.borderless).font(.caption)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(round.shownText).font(.body)
                if round.question != nil, let n = session.sources?.count, n > 0 {
                    Text("+ \(n) Kıvılcım kaydının dökümü").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.08)))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 12)], spacing: 12) {
                ForEach(session.seats.filter { round.answers[$0] != nil }, id: \.self) { seat in
                    AnswerCard(seat: council.seats.first { $0.id == seat }, answer: round.answers[seat]!)
                }
            }
        }
    }
}

struct AnswerCard: View {
    let seat: SeatConfig?
    let answer: Answer
    @State private var expanded = false

    var icon: some View {
        Group {
            switch answer.state {
            case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .timeout: Image(systemName: "clock.badge.exclamationmark").foregroundStyle(.orange)
            case .failed: Image(systemName: "xmark.octagon").foregroundStyle(.red)
            case .skipped: Image(systemName: "minus.circle").foregroundStyle(.secondary)
            default: ProgressView().controlSize(.small)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: seat?.color)).frame(width: 10, height: 10)
                Text(seat?.name ?? answer.seat).font(.headline)
                if answer.via == "api" { Badge("API") }
                if answer.thinking == "on" { Badge("düşünme") }
                Spacer()
                if let s = answer.seconds { Text("\(s) sn").font(.caption).foregroundStyle(.secondary).monospacedDigit() }
                icon
            }
            if answer.text.isEmpty {
                Text(answer.error ?? answer.state.label).font(.callout).foregroundStyle(.secondary)
            } else {
                Text(answer.text).font(.callout).textSelection(.enabled)
                    .lineLimit(expanded ? nil : 12)
                if answer.text.count > 600 {
                    Button(expanded ? "Daralt" : "Tamamını göster") { withAnimation { expanded.toggle() } }
                        .buttonStyle(.link).font(.caption)
                }
            }
            if let e = answer.error, !answer.text.isEmpty { Text(e).font(.caption2).foregroundStyle(.orange) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(hex: seat?.color).opacity(answer.state == .done ? 0.55 : 0.18)))
    }
}

struct Badge: View {
    let t: String
    init(_ t: String) { self.t = t }
    var body: some View {
        Text(t).font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
    }
}

struct Composer: View {
    @EnvironmentObject var council: Council
    @Binding var text: String
    var placeholder: String
    var preselected: [String]? = nil
    let submit: ([String]) -> Void
    @State private var chosen: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text).font(.body).frame(minHeight: 70, maxHeight: 160).scrollContentBackground(.hidden)
                    .padding(6).background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
                if text.isEmpty { Text(placeholder).foregroundStyle(.tertiary).padding(12).allowsHitTesting(false) }
            }
            HStack(spacing: 6) {
                ForEach(council.activeSeats) { s in
                    let on = chosen.contains(s.id)
                    Button { if on { chosen.remove(s.id) } else { chosen.insert(s.id) } } label: {
                        Text(s.name).font(.caption).padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(on ? Color(hex: s.color).opacity(0.22) : Color.secondary.opacity(0.08)))
                            .overlay(Capsule().strokeBorder(on ? Color(hex: s.color) : .clear))
                    }.buttonStyle(.plain)
                }
                Spacer()
                Button {
                    submit(council.activeSeats.map(\.id).filter(chosen.contains))
                } label: { Label("Kurultaya sor", systemImage: "paperplane.fill") }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chosen.isEmpty)
            }
        }
        .onAppear { chosen = Set(preselected ?? council.activeSeats.map(\.id)) }
    }
}

// MARK: - Report + decision

struct ReportView: View {
    @EnvironmentObject var council: Council
    let session: Session
    @State private var note = ""

    var body: some View {
        let rep = SessionFiles.report(session.id)
        let dec = SessionFiles.decision(session.id)
        VStack(spacing: 0) {
            ScrollView {
                if let rep {
                    MarkdownBlocks(text: rep.text).padding(32).frame(maxWidth: 860, alignment: .leading)
                        .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "doc.text.magnifyingglass").font(.system(size: 40)).foregroundStyle(.tertiary)
                        Text("Rapor henüz yazılmadı").font(.title3)
                        Text(session.follow == true ? (SessionFiles.followState(session.id)?.label ?? "Claude takipte") : "Claude'a \"Kurultay'ı değerlendir\" de. Oturum BEKLEYEN.md'de sırada.").foregroundStyle(.secondary)
                    }.padding(80)
                }
            }
            if rep != nil {
                Divider()
                HStack(spacing: 10) {
                    if let dec { Text(dec.label).font(.callout.weight(.semibold)).foregroundStyle(dec.state == "onaylandi" ? .green : .orange) }
                    TextField("Not (düzeltme için ne değişsin?)", text: $note).textFieldStyle(.roundedBorder)
                    Button("Reddet", role: .destructive) { council.decide(session.id, state: "reddedildi", note: note) }
                    Button("Düzelt") { council.decide(session.id, state: "duzelt", note: note) }.disabled(note.isEmpty)
                    Button { council.decide(session.id, state: "onaylandi", note: note) } label: { Label("Onayla", systemImage: "checkmark.seal.fill") }
                        .buttonStyle(.borderedProminent).tint(.green)
                    Button { NSWorkspace.shared.open(rep!.url) } label: { Image(systemName: "arrow.up.forward.app") }.help("Obsidian'da aç")
                }
                .padding(14)
            }
        }
    }
}

/// Small markdown renderer: headings, bullets, quotes, tables as text, inline styles.
struct MarkdownBlocks: View {
    let text: String

    var body: some View {
        let body = text.hasPrefix("---") ? (text.components(separatedBy: "\n---").dropFirst().joined(separator: "\n---")) : text
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(body.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                row(line)
            }
        }
        .textSelection(.enabled)
    }

    func inline(_ s: String) -> Text {
        Text((try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s))
    }

    @ViewBuilder func row(_ l: String) -> some View {
        let t = l.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("# ") { inline(String(t.dropFirst(2))).font(.system(size: 28, weight: .bold, design: .serif)).padding(.top, 6) }
        else if t.hasPrefix("## ") { inline(String(t.dropFirst(3))).font(.system(size: 20, weight: .semibold, design: .serif)).padding(.top, 12) }
        else if t.hasPrefix("### ") { inline(String(t.dropFirst(4))).font(.headline).padding(.top, 6) }
        else if t.hasPrefix("- ") || t.hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline, spacing: 8) { Text("•").foregroundStyle(.secondary); inline(String(t.dropFirst(2))) }
        } else if t.hasPrefix(">") {
            inline(String(t.drop { $0 == ">" || $0 == " " })).foregroundStyle(.secondary).padding(.leading, 10)
                .overlay(Rectangle().fill(.quaternary).frame(width: 3), alignment: .leading)
        } else if t == "---" { Divider() }
        else if t.isEmpty { Spacer().frame(height: 2) }
        else if t.hasPrefix("|") { TableRow(line: t, inline: inline) }
        else { inline(t).fixedSize(horizontal: false, vertical: true) }
    }
}

// MARK: - Browser deck

struct WebDeck: NSViewRepresentable {
    @EnvironmentObject var council: Council
    let selected: String?

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {
        for (id, w) in council.web {
            guard let wv = w.webView else { continue }
            if wv.superview !== v {
                wv.translatesAutoresizingMaskIntoConstraints = true
                wv.frame = v.bounds
                wv.autoresizingMask = [.width, .height]
                v.addSubview(wv)
            }
            // the others stay in the window (laid out, not throttled) underneath the selected one
            wv.alphaValue = id == selected ? 1 : 0.01
            if id == selected, v.subviews.last !== wv {
                v.addSubview(wv, positioned: .above, relativeTo: nil)
                wv.frame = v.bounds
            }
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var council: Council
    @State private var keys: [String: String] = [:]

    var body: some View {
        Form {
            Section {
                Text("Tarayıcı bir modele ulaşamazsa (giriş yok, site değişti) o model ücretsiz API'den sorulur. Anahtarı kendin alıp buraya yapıştır; Mac'in anahtar zincirinde durur.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(council.providers.keys.sorted(), id: \.self) { p in
                let prov = council.providers[p]!
                Section(prov.name ?? p) {
                    SecureField("API anahtarı", text: Binding(get: { keys[p] ?? "" }, set: { keys[p] = $0 }))
                    HStack {
                        Text("Kullanan: " + council.seats.filter { $0.api?.provider == p }.map(\.name).joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if let u = prov.keyUrl.flatMap(URL.init) { Link("Anahtar al", destination: u).font(.caption) }
                        Button("Kaydet") { Keychain.set(p, keys[p] ?? "") }
                    }
                }
            }
            Section("Claude köprüsü") {
                Text("127.0.0.1:\(BridgeServer.port) · token: ~/Library/Application Support/Kurultay/token").font(.caption).textSelection(.enabled)
                Button("adapters.json'ı yeniden yükle") { council.reloadAdapters() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 560)
        .onAppear { for p in council.providers.keys { keys[p] = Keychain.get(p) ?? "" } }
    }
}

/// One markdown table line as aligned cells; the |---| separator line draws as a rule.
struct TableRow: View {
    let line: String
    let inline: (String) -> Text
    var body: some View {
        let cells = line.trimmingCharacters(in: CharacterSet(charactersIn: "| ")).components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        if cells.allSatisfy({ $0.allSatisfy { "-: ".contains($0) } }) { Divider() }
        else {
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, c in inline(c).frame(maxWidth: .infinity, alignment: .leading) }
            }.font(.callout)
        }
    }
}

/// With the Chrome engine the tabs live in the Kurultay Chrome window; this pane opens them and shows their state.
struct ChromePane: View {
    @EnvironmentObject var council: Council
    let selected: String?
    @State private var checking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Tarayıcı: Kurultay Chrome").font(.system(size: 24, weight: .bold, design: .serif))
                Text("Modeller ayrı bir Chrome penceresinde açılır (kendi Chrome'undan ayrı bir profil). Giriş orada yapılır: Google, Apple ve doğrulama sayfaları gerçek Chrome'da sorunsuz çalışır. Bir kez giriş yapman yeter; oturum bu profilde kalır. Pencereyi kapatma; arka planda durabilir.")
                    .foregroundStyle(.secondary).frame(maxWidth: 680, alignment: .leading)
                HStack {
                    Button { Task { checking = true; for w in council.web.values { await w.refreshState() }; checking = false } } label: {
                        Label("Durumu yenile", systemImage: "arrow.clockwise")
                    }
                    if checking { ProgressView().controlSize(.small) }
                }
                VStack(spacing: 0) {
                    ForEach(council.seats) { s in
                        if let w = council.web[s.id] { ChromeSeatRow(seat: s, web: w, highlighted: s.id == selected) }
                        Divider()
                    }
                }
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: selected) { if let id = selected { await council.web[id]?.show() } }
    }
}

struct ChromeSeatRow: View {
    let seat: SeatConfig
    @ObservedObject var web: WebSeat
    let highlighted: Bool

    var status: (String, Color) {
        if let e = web.engineError { return (e, .red) }
        if web.page.login { return ("Giriş gerekli", .orange) }
        if web.page.input { return ("Hazır", .green) }
        return ("Yazı kutusu bulunamadı (giriş ya da sayfa yükleniyor)", .secondary)
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(Color(hex: seat.color)).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(seat.name).font(.headline)
                Text(status.0).font(.caption).foregroundStyle(status.1)
            }
            Spacer()
            Button("Chrome'da aç") { Task { await web.show() } }
            Button { Task { await web.loadNewChat() } } label: { Image(systemName: "square.and.pencil") }.help("Yeni sohbet")
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(highlighted ? Color.accentColor.opacity(0.08) : .clear)
    }
}
