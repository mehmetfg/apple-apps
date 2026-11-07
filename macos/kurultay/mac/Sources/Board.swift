import AppKit
import SwiftUI

/// Pano: every answer on one screen. Each question is a heading; under it Claude's arrangement
/// (common · divergent · advice) and then every model's answer, folded to its one-line gist.
struct BoardView: View {
    @EnvironmentObject var council: Council
    let session: Session
    @State private var all = false
    @State private var query = ""
    @State private var openAll = false

    private var shown: [Session] { all ? council.sessions : [session] }

    var body: some View {
        HStack(spacing: 0) {
            outline.frame(width: 250)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 34) {
                        ForEach(shown) { s in BoardSession(session: s, query: query, openAll: openAll).id(s.id) }
                    }
                    .padding(.horizontal, 36).padding(.vertical, 28)
                    .frame(maxWidth: 940, alignment: .leading).frame(maxWidth: .infinity)
                }
                .onReceive(NotificationCenter.default.publisher(for: .boardJump)) { n in
                    if let k = n.object as? String { withAnimation { proxy.scrollTo(k, anchor: .top) } }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Picker("", selection: $all) { Text("Bu oturum").tag(false); Text("Tümü").tag(true) }.pickerStyle(.segmented).frame(width: 170)
                TextField("Cevaplarda ara", text: $query).textFieldStyle(.roundedBorder).frame(width: 180)
                Button { openAll.toggle() } label: { Image(systemName: openAll ? "rectangle.compress.vertical" : "rectangle.expand.vertical") }
                    .help(openAll ? "Hepsini daralt" : "Hepsini aç")
            }
        }
    }

    private var outline: some View {
        List {
            ForEach(shown) { s in
                let arr = SessionFiles.arrangement(s.id)
                Section(s.title) {
                    ForEach(s.rounds) { r in
                        Button { NotificationCenter.default.post(name: .boardJump, object: "\(s.id)#\(r.id)") } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("\(r.id).").foregroundStyle(.secondary).monospacedDigit()
                                Text(arr?.round(r.id)?.baslik ?? firstLine(r.shownText)).lineLimit(2)
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

extension Notification.Name { static let boardJump = Notification.Name("kurultay.boardJump") }

func firstLine(_ s: String) -> String {
    let l = s.split(separator: "\n").first.map(String.init) ?? s
    return l.count > 90 ? String(l.prefix(88)) + "…" : l
}

struct BoardSession: View {
    @EnvironmentObject var council: Council
    let session: Session
    let query: String
    let openAll: Bool

    var body: some View {
        let arr = SessionFiles.arrangement(session.id)
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(session.title).font(.system(size: 30, weight: .bold, design: .serif))
                HStack(spacing: 8) {
                    Text(session.created.formatted(date: .long, time: .shortened)).foregroundStyle(.secondary)
                    Text("· \(session.rounds.count) soru · \(session.seats.count) model").foregroundStyle(.secondary)
                    FollowBadge(session: session)
                }.font(.callout)
                if let src = session.sources, !src.isEmpty {
                    FlowChips(items: src.map { "🎙 " + $0.title })
                }
                if let o = arr?.ozet, !o.isEmpty {
                    Text(o).font(.title3).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.purple.opacity(0.07)))
                }
            }
            ForEach(session.rounds) { r in
                BoardRound(session: session, round: r, note: arr?.round(r.id), query: query, openAll: openAll).id("\(session.id)#\(r.id)")
            }
        }
    }
}

struct BoardRound: View {
    @EnvironmentObject var council: Council
    let session: Session
    let round: Round
    let note: Arrangement.RoundNote?
    let query: String
    let openAll: Bool
    @State private var showQuestion = false

    private var seats: [String] {
        session.seats.filter { seat in
            guard let a = round.answers[seat] else { return false }
            return query.isEmpty || a.text.localizedCaseInsensitiveContains(query) || (note?.modeller?[seat]?.oz ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(round.id)").font(.title2.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 34, height: 34).background(Circle().fill(Color.accentColor))
                Text(note?.baslik ?? firstLine(round.shownText)).font(.system(size: 22, weight: .semibold, design: .serif))
                Spacer()
                Text("\(round.doneCount)/\(round.answers.count) ✓").font(.caption).foregroundStyle(round.done ? .green : .secondary)
            }
            DisclosureGroup(isExpanded: $showQuestion) {
                Text(round.shownText).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
            } label: {
                Text(note?.soru_ozeti ?? "Soru").font(.callout).foregroundStyle(.secondary).lineLimit(showQuestion ? nil : 2)
            }
            if let n = note { ArrangementBlock(note: n) }
            VStack(spacing: 8) {
                ForEach(seats, id: \.self) { seat in
                    BoardAnswer(seat: council.seats.first { $0.id == seat }, answer: round.answers[seat]!, gist: note?.modeller?[seat], openAll: openAll)
                }
            }
        }
    }
}

struct ArrangementBlock: View {
    let note: Arrangement.RoundNote

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                column("Ortak", "checkmark.circle", .green, note.ortak)
                column("Ayrışan", "arrow.triangle.branch", .orange, note.ayrisan)
                column("Öneriler", "lightbulb", .blue, note.oneriler)
            }
            if let c = note.claude, !c.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkle").foregroundStyle(.purple)
                    Text(c).font(.callout).textSelection(.enabled)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
    }

    @ViewBuilder func column(_ title: String, _ icon: String, _ color: Color, _ items: [String]?) -> some View {
        if let items, !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(color)
                ForEach(items, id: \.self) { i in
                    HStack(alignment: .firstTextBaseline, spacing: 6) { Text("•").foregroundStyle(.secondary); Text(i).font(.callout) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

struct BoardAnswer: View {
    let seat: SeatConfig?
    let answer: Answer
    let gist: Arrangement.ModelNote?
    let openAll: Bool
    @State private var open = false

    var body: some View {
        let isOpen = open || openAll
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.easeInOut(duration: 0.18)) { open.toggle() } } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle().fill(Color(hex: seat?.color)).frame(width: 10, height: 10)
                    Text(seat?.name ?? answer.seat).font(.headline).frame(width: 110, alignment: .leading)
                    Text(gist?.oz ?? (answer.text.isEmpty ? (answer.error ?? answer.state.label) : firstLine(answer.text)))
                        .font(.callout).foregroundStyle(gist?.oz == nil ? .secondary : .primary).lineLimit(isOpen ? nil : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let h = gist?.hukum, !h.isEmpty { Badge(h) }
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down").foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
            if isOpen && !answer.text.isEmpty {
                Text(answer.text).font(.callout).lineSpacing(3).textSelection(.enabled)
                    .padding(.leading, 20).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor).opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(hex: seat?.color).opacity(0.3)))
    }
}

struct FollowBadge: View {
    let session: Session
    var body: some View {
        if session.follow == true {
            let st = SessionFiles.followState(session.id)
            let ready = st?.state == "hazir" || SessionFiles.arrangement(session.id) != nil
            Label(ready ? "Claude raporu yazdı" : (st?.label ?? "Claude takipte"), systemImage: ready ? "checkmark.seal" : "eye")
                .font(.caption).padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill((ready ? Color.green : Color.purple).opacity(0.12)))
                .foregroundStyle(ready ? .green : .purple)
        }
    }
}

struct FlowChips: View {
    let items: [String]
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { t in
                    Text(t).font(.caption).lineLimit(1).padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Color.secondary.opacity(0.1)))
                }
            }
        }.scrollIndicators(.hidden)
    }
}
