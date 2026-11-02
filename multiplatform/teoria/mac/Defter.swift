// Defter — quick notes from anywhere in the Mac app (2026-10-23).
// A panel on the right side of the window, over every tab (Kür included): type a line, press Return, it is saved
// and the field is empty for the next one. Notes are not tied to a book or a place; they go into the same notes log
// as the reader's notes (book id "genel"), so they also show on Notlarım and reach the vault the same way.
import SwiftUI

enum Defter {
    static let bookID = "genel"
    static let bookTitle = "Defter"
}

struct DefterPanel: View {
    @EnvironmentObject var depo: Depo
    @ObservedObject private var store = NotesStore.shared
    @State private var text = ""
    @FocusState private var focused: Bool
    var focusRequest: Int

    private var notes: [TeoriaNote] {
        store.notes.filter { $0.book == Defter.bookID }.sorted { $0.date < $1.date }
    }

    private var todayCount: Int {
        notes.filter { Tarih.takvim.isDateInToday($0.created) }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Defter").font(Tema.serif(.title3, .semibold))
                Spacer()
                Text(todayCount == 0 ? "bugün boş" : "bugün \(todayCount)")
                    .font(.caption).foregroundStyle(Tema.soluk).monospacedDigit()
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
            Divider()
            list
            Divider()
            field
        }
        .background(Tema.yuzey)
        .onAppear { focused = true }
        .onChange(of: focusRequest) { _, _ in focused = true }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if notes.isEmpty {
                        Text("Gördüğün bir cümle, aklına gelen bir kavram: yaz, ↩ ile kaydet.")
                            .font(Tema.serif(.callout)).foregroundStyle(Tema.soluk)
                            .padding(16)
                    }
                    ForEach(Array(notes.enumerated()), id: \.element.id) { i, n in
                        if i == 0 || !Tarih.takvim.isDate(n.created, inSameDayAs: notes[i - 1].created) {
                            Text(n.created.formatted(.dateTime.day().month(.wide).weekday(.wide)).localizedCapitalized)
                                .font(.caption.weight(.semibold)).foregroundStyle(Tema.soluk)
                                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 4)
                        }
                        DefterRow(note: n)
                            .id(n.id)
                    }
                }
                .padding(.bottom, 8)
            }
            .onAppear { if let l = notes.last { proxy.scrollTo(l.id, anchor: .bottom) } }
            .onChange(of: notes.last?.id) { _, id in
                if let id { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) } }
            }
        }
    }

    private var field: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Not yaz…", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Tema.serif(.body))
                .lineLimit(1...6)
                .focused($focused)
                .onSubmit(save)
                // A line break that arrives any other way (paste, dictation) also closes the note.
                .onChange(of: text) { _, t in if t.contains(where: \.isNewline) { save() } }
            Text("↩ kaydet · ⇧⌘N aç/kapa")
                .font(.caption2).foregroundStyle(Tema.soluk)
        }
        .padding(14)
        .background(Tema.yuzey2.opacity(0.5))
    }

    private func save() {
        let t = text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        store.add(book: Defter.bookID, title: Defter.bookTitle, anchor: nil, text: t, recording: nil)
        store.scheduleSync(depo.kasa)
        text = ""
        focused = true
    }
}

private struct DefterRow: View {
    @EnvironmentObject var depo: Depo
    @ObservedObject private var store = NotesStore.shared
    let note: TeoriaNote
    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(note.text)
                .font(Tema.serif(.body))
                .foregroundStyle(Tema.metin)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(note.created.formatted(.dateTime.hour().minute()))
                .font(.caption2).foregroundStyle(Tema.soluk).monospacedDigit()
                .opacity(hover ? 1 : 0.6)
        }
        .padding(.horizontal, 16).padding(.vertical, 7)
        .background(hover ? Tema.yuzey2.opacity(0.6) : .clear)
        .onHover { hover = $0 }
        .contextMenu {
            Button("Kopyala") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(note.text, forType: .string)
            }
            Button("Sil", role: .destructive) {
                store.delete(note)
                store.scheduleSync(depo.kasa)
            }
        }
    }
}
