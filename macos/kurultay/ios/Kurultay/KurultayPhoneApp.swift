import SwiftUI

@main
struct KurultayPhoneApp: App {
    @StateObject private var store = PhoneStore()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .task { await store.refresh() }
                .onChange(of: phase) { _, p in if p == .active { Task { await store.refresh() } } }
        }
    }
}

extension Color {
    init(hex: String?) {
        var v: UInt64 = 0x6B7280
        if let h = hex?.trimmingCharacters(in: CharacterSet(charactersIn: "#")) { Scanner(string: h).scanHexInt64(&v) }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

struct RootView: View {
    @EnvironmentObject var store: PhoneStore
    @State private var picking = false
    @State private var composing = false

    var body: some View {
        NavigationStack {
            Group {
                if store.root == nil {
                    ContentUnavailableView {
                        Label("Vault'u seç", systemImage: "folder.badge.questionmark")
                    } description: {
                        Text("Kurultay raporları iCloud'daki vault'ta durur. Bir kez \"Personel Data Management\" klasörünü seç.")
                    } actions: {
                        Button("Klasörü seç") { picking = true }.buttonStyle(.borderedProminent)
                    }
                } else {
                    SessionList()
                }
            }
            .navigationTitle("Kurultay")
            .toolbar {
                if store.root != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { composing = true } label: { Image(systemName: "square.and.pencil") }
                            .accessibilityLabel("Yeni kurultay")
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button("Vault klasörünü değiştir") { picking = true }
                        } label: { Image(systemName: "gearshape") }.accessibilityLabel("Ayarlar")
                    }
                }
            }
            .sheet(isPresented: $composing) { ComposeSheet(session: nil) }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { r in
                if case let .success(u) = r { store.choose(u) }
            }
        }
    }
}

struct SessionList: View {
    @EnvironmentObject var store: PhoneStore

    var body: some View {
        List {
            if store.pendingRequests > 0 {
                Label("\(store.pendingRequests) soru Mac'e iletilmeyi bekliyor (Kurultay.app açık olmalı)", systemImage: "hourglass")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let e = store.error { Text(e).font(.footnote).foregroundStyle(.orange) }
            ForEach(store.sessions) { s in
                NavigationLink { SessionDetail(sessionId: s.id) } label: { SessionRow(session: s) }
            }
        }
        .refreshable { await store.refresh() }
        .overlay { if store.loading && store.sessions.isEmpty { ProgressView() } }
    }
}

struct SessionRow: View {
    @EnvironmentObject var store: PhoneStore
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title).font(.headline).lineLimit(2)
            HStack(spacing: 8) {
                Text(session.created, format: .dateTime.day().month().hour().minute())
                Text("\(session.rounds.count) soru")
                if let last = session.rounds.last, !last.done { Label("sürüyor", systemImage: "ellipsis").labelStyle(.titleAndIcon) }
                Spacer()
                if let d = store.decisions[session.id] {
                    Text(d.label).foregroundStyle(d.state == "onaylandi" || d.state == "uygulandi" ? .green : .orange)
                } else if store.reports[session.id] != nil {
                    Text("Rapor hazır").foregroundStyle(.blue)
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct SessionDetail: View {
    @EnvironmentObject var store: PhoneStore
    let sessionId: String
    @State private var tab = 0
    @State private var composing = false

    var body: some View {
        if let s = store.sessions.first(where: { $0.id == sessionId }) {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("Meclis").tag(0)
                    Text("Rapor").tag(1)
                }
                .pickerStyle(.segmented).padding(.horizontal).padding(.top, 6)
                if tab == 0 { RoundsView(session: s) } else { ReportPane(session: s) }
            }
            .navigationTitle(s.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { composing = true } label: { Image(systemName: "arrowshape.turn.up.right") }
                        .accessibilityLabel("Ardışık soru")
                }
            }
            .sheet(isPresented: $composing) { ComposeSheet(session: s) }
            .refreshable { await store.refresh() }
        }
    }
}

struct RoundsView: View {
    @EnvironmentObject var store: PhoneStore
    let session: Session

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(session.rounds) { r in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Soru \(r.id)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text("\(r.doneCount)/\(r.answers.count) ✓").font(.caption).foregroundStyle(r.done ? .green : .secondary)
                        }
                        Text(r.text).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.1)))
                        ForEach(session.seats.filter { r.answers[$0] != nil }, id: \.self) { seat in
                            PhoneAnswerCard(seat: store.seats.first { $0.id == seat }, answer: r.answers[seat]!)
                        }
                    }
                }
            }
            .padding()
        }
    }
}

struct PhoneAnswerCard: View {
    let seat: SeatConfig?
    let answer: Answer
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(Color(hex: seat?.color)).frame(width: 9, height: 9)
                Text(seat?.name ?? answer.seat).font(.subheadline.weight(.semibold))
                if answer.via == "api" { Text("API").font(.caption2).foregroundStyle(.secondary) }
                Spacer()
                switch answer.state {
                case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .timeout: Image(systemName: "clock.badge.exclamationmark").foregroundStyle(.orange)
                case .failed: Image(systemName: "xmark.octagon").foregroundStyle(.red)
                default: ProgressView()
                }
            }
            Text(answer.text.isEmpty ? (answer.error ?? answer.state.label) : answer.text)
                .font(.callout).foregroundStyle(answer.text.isEmpty ? .secondary : .primary)
                .lineLimit(open ? nil : 8).textSelection(.enabled)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        .onTapGesture { withAnimation { open.toggle() } }
        .accessibilityAddTraits(.isButton)
    }
}

struct ReportPane: View {
    @EnvironmentObject var store: PhoneStore
    let session: Session
    @State private var note = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                if let rep = store.reports[session.id] {
                    PhoneMarkdown(text: rep).padding()
                } else {
                    ContentUnavailableView("Rapor henüz yok", systemImage: "doc.text.magnifyingglass",
                                           description: Text("Mac'te Claude'a \"Kurultay'ı değerlendir\" de."))
                        .padding(.top, 60)
                }
            }
            if store.reports[session.id] != nil {
                VStack(spacing: 8) {
                    if let d = store.decisions[session.id] {
                        Text(d.label + (d.note.map { " · \($0)" } ?? "")).font(.footnote.weight(.semibold))
                            .foregroundStyle(d.state == "onaylandi" ? .green : .orange)
                    }
                    TextField("Not (düzeltme için)", text: $note, axis: .vertical).textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Reddet", role: .destructive) { store.decide(session.id, state: "reddedildi", note: note) }
                        Spacer()
                        Button("Düzelt") { store.decide(session.id, state: "duzelt", note: note) }.disabled(note.isEmpty)
                        Button { store.decide(session.id, state: "onaylandi", note: note) } label: {
                            Label("Onayla", systemImage: "checkmark.seal.fill")
                        }.buttonStyle(.borderedProminent).tint(.green)
                    }
                }
                .padding()
                .background(.bar)
            }
        }
    }
}

struct PhoneMarkdown: View {
    let text: String
    var body: some View {
        let body = text.hasPrefix("---") ? text.components(separatedBy: "\n---").dropFirst().joined(separator: "\n---") : text
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(body.components(separatedBy: "\n").enumerated()), id: \.offset) { _, l in
                let t = l.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("# ") { md(String(t.dropFirst(2))).font(.title2.bold()) }
                else if t.hasPrefix("## ") { md(String(t.dropFirst(3))).font(.title3.weight(.semibold)).padding(.top, 8) }
                else if t.hasPrefix("### ") { md(String(t.dropFirst(4))).font(.headline) }
                else if t.hasPrefix("- ") { HStack(alignment: .firstTextBaseline) { Text("•"); md(String(t.dropFirst(2))) } }
                else if t.hasPrefix("|") {
                    let cells = t.trimmingCharacters(in: CharacterSet(charactersIn: "| ")).components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                    if cells.allSatisfy({ $0.allSatisfy { "-: ".contains($0) } }) { Divider() }
                    else { HStack(alignment: .top) { ForEach(Array(cells.enumerated()), id: \.offset) { _, c in md(c).frame(maxWidth: .infinity, alignment: .leading) } }.font(.footnote) }
                }
                else if !t.isEmpty && t != "---" { md(t) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
    func md(_ s: String) -> Text {
        Text((try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s))
    }
}

struct ComposeSheet: View {
    @EnvironmentObject var store: PhoneStore
    @Environment(\.dismiss) private var dismiss
    let session: Session?
    @State private var text = ""
    @State private var chosen: Set<String> = []

    var body: some View {
        NavigationStack {
            Form {
                Section(session == nil ? "Meclise soru" : "Ardışık soru · \(session!.title)") {
                    TextField("Ne soralım?", text: $text, axis: .vertical).lineLimit(4...12)
                }
                Section("Meclis") {
                    ForEach(store.seats.filter { $0.enabled ?? true }) { s in
                        Button {
                            if chosen.contains(s.id) { chosen.remove(s.id) } else { chosen.insert(s.id) }
                        } label: {
                            HStack {
                                Circle().fill(Color(hex: s.color)).frame(width: 9, height: 9)
                                Text(s.name).foregroundStyle(.primary)
                                Spacer()
                                if chosen.contains(s.id) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                    }
                }
                Section {
                    Text("Soru Mac'teki Kurultay'a iletilir (uygulama açık olmalı, ~15 sn). Cevaplar geldikçe burada görünür.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(session == nil ? "Yeni kurultay" : "Ardışık soru")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gönder") {
                        store.ask(text, seats: store.seats.map(\.id).filter(chosen.contains), session: session?.id)
                        dismiss()
                    }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chosen.isEmpty)
                }
            }
            .onAppear { chosen = Set(session?.seats ?? store.seats.filter { $0.enabled ?? true }.map(\.id)) }
        }
    }
}
