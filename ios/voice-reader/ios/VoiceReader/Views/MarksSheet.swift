// A book's marks without opening it: from the library card (the ✎ chip, or the card's menu). In book order, under
// their chapters, with the date and any note; "Kitapta göster" opens the book on the mark without moving the reading
// place.
import SwiftUI

struct MarksSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let documentID: UUID
    var onShow: (UUID, Int) -> Void
    @State private var chapters: [Chapter] = []
    @State private var query = ""

    private var doc: DocumentRecord? { model.store.document(documentID) }

    private var groups: [(chapter: String, marks: [Highlight])] {
        let marks = (doc?.highlights ?? []).sorted { $0.location < $1.location }
            .filter { query.isEmpty || $0.text.localizedStandardContains(query) || ($0.note ?? "").localizedStandardContains(query) }
        var out: [(chapter: String, marks: [Highlight])] = []
        for h in marks {
            let ch = chapters.last { $0.offset <= h.location }?.title ?? "Başlangıç"
            if out.last?.chapter == ch { out[out.count - 1].marks.append(h) } else { out.append((ch, [h])) }
        }
        return out
    }

    var body: some View {
        NavigationStack {
            List {
                if let d = doc {
                    Section {
                        HStack(spacing: 12) {
                            CoverView(doc: d, width: 44, showsPlaying: false)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(d.title).font(.headline).lineLimit(2)
                                Text("\(d.highlights.count) işaret · \(model.statusText(d))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if groups.isEmpty {
                    Text(query.isEmpty ? "Bu kitapta henüz işaret yok." : "Aramaya uyan işaret yok.").foregroundStyle(.secondary)
                }
                ForEach(groups, id: \.chapter) { g in
                    Section(g.chapter) {
                        ForEach(g.marks) { h in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .top, spacing: 10) {
                                    Capsule().fill(h.color.color).frame(width: 3)
                                    Text(h.text).font(.system(.body, design: .serif)).lineSpacing(3)
                                }
                                if let n = h.note, !n.isEmpty {
                                    Label(n, systemImage: "note.text").font(.footnote).foregroundStyle(.secondary).padding(.leading, 13)
                                }
                                Text(h.createdAt.formatted(.dateTime.day().month(.abbreviated).year()))
                                    .font(.caption2).foregroundStyle(.tertiary).padding(.leading, 13)
                            }
                            .padding(.vertical, 4)
                            .swipeActions(edge: .trailing) {
                                Button { dismiss(); onShow(documentID, h.location) } label: { Label("Kitapta göster", systemImage: "book") }
                                    .tint(.blue)
                            }
                            .contextMenu {
                                Button { dismiss(); onShow(documentID, h.location) } label: { Label("Kitapta göster", systemImage: "book") }
                                Button { UIPasteboard.general.string = h.text } label: { Label("Kopyala", systemImage: "doc.on.doc") }
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "İşaretlerde ara")
            .navigationTitle("İşaretler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } }
                if let d = doc, !d.highlights.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        ShareLink(item: model.highlightsExport(d)) { Image(systemName: "square.and.arrow.up") }
                    }
                }
            }
            .task { chapters = await model.store.content(for: documentID)?.chapters ?? [] }
        }
    }
}

/// "✎ 12" on a cover: the book's marks at a glance.
struct MarksChip: View {
    @Environment(AppModel.self) private var model
    let doc: DocumentRecord

    var body: some View {
        if !doc.highlights.isEmpty {
            Button { model.marksSheetDoc = doc.id } label: {
                Label("\(doc.highlights.count)", systemImage: "highlighter")
                    .font(.caption2.weight(.bold)).foregroundStyle(.black.opacity(0.8))
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(Color.yellow, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(doc.highlights.count) işaret: kitaba girmeden bak")
        }
    }
}
