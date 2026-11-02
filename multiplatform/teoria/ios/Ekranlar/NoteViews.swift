// Note screens (2026-10-21): the editor that opens from the reader, the notes of one book, and "Notlarım" —
// every note on its own, with counts of what was produced (notes, sentences, words, minutes spoken).
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A request to open the editor from a reader, with the places it can offer.
struct NoteRequest: Identifiable {
    let id = UUID()
    var options: [(label: String, anchor: NoteAnchor)]
}

// MARK: editor

/// Write or say a note. The place it hangs on is chosen in the sheet: the whole book, or one of the places the
/// reader offers (the sentence just marked, the sentence being heard, this page).
struct NoteEditor: View {
    @EnvironmentObject var depo: Depo
    @ObservedObject private var store = NotesStore.shared
    @Environment(\.dismiss) private var dismiss
    @StateObject private var player = SesKayit()

    let bookID: String
    let bookTitle: String
    var options: [(label: String, anchor: NoteAnchor)] = []
    var existing: TeoriaNote?

    @State private var choice = -1                 // -1 = the whole book
    @State private var text = ""
    @State private var recording: URL?
    @State private var saved = false
    @FocusState private var focus: Bool

    private var all: [(label: String, anchor: NoteAnchor)] {
        var o = options
        if let a = existing?.anchor, !o.contains(where: { $0.anchor == a }) { o.insert(("Bağlı olduğu yer", a), at: 0) }
        return o
    }
    private var anchor: NoteAnchor? { all.indices.contains(choice) ? all[choice].anchor : nil }
    private var canSave: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || recording != nil || existing?.audio != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(bookTitle.kodsuz).font(.footnote.weight(.semibold)).foregroundStyle(Tema.ikincil).lineLimit(1)
                    placePicker
                    if let a = anchor { quoteCard(a) }
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $text)
                            .focused($focus)
                            .font(.system(size: 17, design: .serif))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 170)
                            .padding(10)
                            .background { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Tema.yuzey) }
                            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Tema.cizgi.opacity(0.7), lineWidth: 0.5) }
                        if text.isEmpty {
                            Text(anchor == nil ? "Kitap hakkında ne düşünüyorsun?" : "Bu yer sana ne söylüyor?")
                                .font(.system(size: 17, design: .serif)).foregroundStyle(Tema.soluk)
                                .padding(.horizontal, 16).padding(.vertical, 18).allowsHitTesting(false)
                        }
                    }
                    SesleYaz(metin: $text, dosya: $recording)
                    if let old = existing, let url = store.audioURL(old), recording == nil {
                        Button { player.cal(url, kimlik: old.id) } label: {
                            Label(player.calan == old.id ? "Durdur" : "Kayıtlı sesi dinle · \(SesKayit.sureYazi(old.seconds ?? 0))",
                                  systemImage: player.calan == old.id ? "stop.fill" : "play.fill")
                        }
                        .buttonStyle(.bordered)
                    }
                    HStack(spacing: 14) {
                        Label("\(NoteText.words(text)) kelime", systemImage: "textformat")
                        Label("\(NoteText.sentences(text)) cümle", systemImage: "text.alignleft")
                    }
                    .font(.caption).foregroundStyle(Tema.ikincil).monospacedDigit()
                }
                .padding(20)
                .frame(maxWidth: 720).frame(maxWidth: .infinity)
            }
            .background(Tema.arka.ignoresSafeArea())
            .navigationTitle(existing == nil ? "Yeni not" : "Notu düzenle")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Kaydet") { save() }.disabled(!canSave).fontWeight(.semibold) }
            }
        }
        .onAppear {
            if let old = existing {
                text = old.text
                if let a = old.anchor, let i = all.firstIndex(where: { $0.anchor == a }) { choice = i }
            } else if !options.isEmpty { choice = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focus = existing == nil }
        }
        .onDisappear { if !saved, let r = recording { try? FileManager.default.removeItem(at: r) } }
        #if os(macOS)
        .frame(minWidth: 540, minHeight: 600)
        #else
        .presentationDetents([.large])
        #endif
    }

    @ViewBuilder
    private var placePicker: some View {
        Menu {
            Button { choice = -1 } label: { Label("Kitaba (bir yere bağlı değil)", systemImage: choice == -1 ? "checkmark" : "book") }
            ForEach(Array(all.enumerated()), id: \.offset) { i, o in
                Button { choice = i } label: { Label(o.label, systemImage: choice == i ? "checkmark" : "text.quote") }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: anchor == nil ? "book.closed" : "text.quote")
                Text(anchor == nil ? "Kitaba bağlı" : (all.indices.contains(choice) ? all[choice].label : "Bir yere bağlı"))
                    .font(.system(size: 14, weight: .semibold))
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(Tema.vurgu)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background { Capsule().fill(Tema.vurgu.opacity(0.12)) }
        }
    }

    private func quoteCard(_ a: NoteAnchor) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let t = a.chapterTitle, !t.isEmpty {
                Text(t.kodsuz).font(.system(size: 11, weight: .bold)).tracking(0.6).foregroundStyle(Tema.soluk).lineLimit(1)
            }
            Text("“\(a.quote)”").font(.system(size: 15, design: .serif)).italic().foregroundStyle(Tema.ikincil).lineLimit(7)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Tema.yuzey2) }
    }

    private func save() {
        if let old = existing { store.update(old, anchor: anchor, text: text, recording: recording) }
        else { store.add(book: bookID, title: bookTitle, anchor: anchor, text: text, recording: recording) }
        saved = true
        Dokunus.basari()
        store.scheduleSync(depo.kasa)
        dismiss()
    }
}

// MARK: one note

struct NoteRow: View {
    @ObservedObject private var store = NotesStore.shared
    @ObservedObject var player: SesKayit
    let note: TeoriaNote
    var showBook = false
    var onEdit: () -> Void
    var onJump: (() -> Void)?
    var onOpenBook: (() -> Void)?

    var body: some View {
        Yuzey(dolgu: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: note.hasVoice ? "waveform" : (note.anchored ? "text.quote" : "book.closed"))
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(Tema.vurgu)
                    Text(showBook ? note.bookTitle.kodsuz : (note.chapterTitle?.kodsuz ?? "Kitaba"))
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Tema.ikincil).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(note.created.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(Dil.tr)))
                        .font(.caption2).foregroundStyle(Tema.soluk)
                }
                if let q = note.quote {
                    Text("“\(q)”").font(.system(size: 13.5, design: .serif)).italic().foregroundStyle(Tema.ikincil).lineLimit(3)
                        .padding(.leading, 10)
                        .overlay(alignment: .leading) { Capsule().fill(Tema.vurgu.opacity(0.5)).frame(width: 2.5) }
                }
                if !note.text.isEmpty {
                    Text(note.text).font(.system(size: 16, design: .serif)).foregroundStyle(Tema.metin).lineSpacing(3)
                        .textSelection(.enabled)
                }
                HStack(spacing: 12) {
                    if note.hasVoice {
                        if let url = store.audioURL(note) {
                            Button { player.cal(url, kimlik: note.id) } label: {
                                Label(player.calan == note.id ? "Durdur" : SesKayit.sureYazi(note.seconds ?? 0),
                                      systemImage: player.calan == note.id ? "stop.fill" : "play.fill").monospacedDigit()
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                        } else {
                            Label("ses iniyor…", systemImage: "icloud.and.arrow.down").font(.caption).foregroundStyle(Tema.soluk)
                        }
                    }
                    Text("\(note.words) kelime · \(note.sentences) cümle").font(.caption2).foregroundStyle(Tema.soluk).monospacedDigit()
                    Spacer(minLength: 0)
                    if let onJump { Button(action: onJump) { Label("Yere git", systemImage: "arrow.turn.down.right") }.buttonStyle(.borderless).font(.caption) }
                    if let onOpenBook { Button(action: onOpenBook) { Label("Kitabı aç", systemImage: "book") }.buttonStyle(.borderless).font(.caption) }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
        .contextMenu {
            Button { onEdit() } label: { Label("Düzenle", systemImage: "pencil") }
            if !note.text.isEmpty {
                Button {
                    #if os(iOS)
                    UIPasteboard.general.string = note.text
                    #else
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(note.text, forType: .string)
                    #endif
                } label: { Label("Kopyala", systemImage: "doc.on.doc") }
            }
            Button(role: .destructive) {
                NotesStore.shared.delete(note)
            } label: { Label("Sil", systemImage: "trash") }
        }
    }
}

// MARK: the notes of one book

struct BookNotesView: View {
    @EnvironmentObject var depo: Depo
    @ObservedObject private var store = NotesStore.shared
    @StateObject private var player = SesKayit()
    @Environment(\.dismiss) private var dismiss
    let bookID: String
    let bookTitle: String
    /// Places the reader can offer for a new note (evaluated when the editor opens).
    var options: () -> [(label: String, anchor: NoteAnchor)] = { [] }
    var onJump: ((NoteAnchor) -> Void)?
    var showsClose = true

    @State private var creating = false
    @State private var editing: TeoriaNote?

    private var mine: [TeoriaNote] { store.notes(of: bookID) }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if mine.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "square.and.pencil").font(.system(size: 34)).foregroundStyle(Tema.soluk)
                            Text("Bu kitapta henüz notun yok").font(.headline).foregroundStyle(Tema.metin)
                            Text("Bir yere bağlı ya da kitabın tamamı hakkında yaz; istersen sesinle anlat.")
                                .font(.footnote).foregroundStyle(Tema.ikincil).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 50)
                    } else {
                        Text("\(mine.count) not · \(mine.reduce(0) { $0 + $1.sentences }) cümle · \(mine.reduce(0) { $0 + $1.words }) kelime")
                            .font(.caption.weight(.semibold)).foregroundStyle(Tema.ikincil).monospacedDigit()
                    }
                    ForEach(mine) { n in
                        NoteRow(player: player, note: n, onEdit: { editing = n },
                                onJump: n.anchor.flatMap { a in onJump.map { j in { j(a); dismiss() } } })
                    }
                }
                .padding(18)
                .frame(maxWidth: 720).frame(maxWidth: .infinity)
            }
            .background(Tema.arka.ignoresSafeArea())
            .navigationTitle("Notlar")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if showsClose { ToolbarItem(placement: .cancellationAction) { Button("Bitti") { dismiss() } } }
                ToolbarItem(placement: .primaryAction) { Button { creating = true } label: { Label("Yeni not", systemImage: "plus") } }
            }
        }
        .sheet(isPresented: $creating) {
            NoteEditor(bookID: bookID, bookTitle: bookTitle, options: options()).environmentObject(depo)
        }
        .sheet(item: $editing) { n in
            NoteEditor(bookID: bookID, bookTitle: bookTitle, options: options(), existing: n).environmentObject(depo)
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #else
        .presentationDetents([.medium, .large])
        #endif
    }
}

// MARK: Notlarım — every note, and what they add up to

struct NotlarimEkrani: View {
    @EnvironmentObject var depo: Depo
    @ObservedObject private var store = NotesStore.shared
    @ObservedObject private var library = LibraryStore.shared
    @StateObject private var player = SesKayit()

    enum Filter: String, CaseIterable, Identifiable {
        case all = "Hepsi", text = "Yazılı", voice = "Sesli", anchored = "Yere bağlı", book = "Kitaba"
        var id: String { rawValue }
    }

    var genis = false
    @State private var filter = Filter.all
    @State private var bookFilter: String?
    @State private var query = ""
    @State private var editing: TeoriaNote?
    @State private var opening: LibraryEntry?

    private var stats: NoteStats { store.stats }

    private var shown: [TeoriaNote] {
        store.notes.filter { n in
            switch filter {
            case .all: true
            case .text: !n.text.isEmpty
            case .voice: n.hasVoice
            case .anchored: n.anchored
            case .book: !n.anchored
            }
        }
        .filter { bookFilter == nil || $0.book == bookFilter }
        .filter { query.isEmpty || Dil.normal($0.text + " " + ($0.quote ?? "") + " " + $0.bookTitle).contains(Dil.normal(query)) }
    }

    private var grouped: [(Date, [TeoriaNote])] {
        Dictionary(grouping: shown, by: { $0.created.gunBasi }).map { ($0.key, $0.value) }.sorted { $0.0 > $1.0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    summary
                    chart
                    if stats.perBook.count > 1 { books }
                    filters
                    if shown.isEmpty { empty } else { list }
                }
                .padding(18)
                .frame(maxWidth: genis ? 980 : 760).frame(maxWidth: .infinity)
            }
            .background(Tema.arka.ignoresSafeArea())
            .navigationTitle("Notlarım")
            .searchable(text: $query, prompt: "Notlarda ara")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: markdown(shown), subject: Text("Teoria notlarım")) { Label("Dışa aktar", systemImage: "square.and.arrow.up") }
                        .disabled(shown.isEmpty)
                }
            }
        }
        .sheet(item: $editing) { n in
            NoteEditor(bookID: n.book, bookTitle: n.bookTitle, existing: n).environmentObject(depo)
        }
        .sheet(item: $opening) { e in
            #if os(iOS)
            NavigationStack { BookScreen(entry: e) }.environmentObject(depo)
            #else
            VStack(spacing: 0) {
                HStack { Spacer(); Button("Kapat") { opening = nil }.keyboardShortcut(.cancelAction).padding(10) }
                BookStudio(entry: e).environmentObject(depo)
            }
            .frame(minWidth: 1280, minHeight: 800)
            #endif
        }
        .task { await store.sync(depo.kasa) }
    }

    // MARK: pieces

    private var summary: some View {
        let s = stats
        return VStack(alignment: .leading, spacing: 10) {
            Bolumbasi(metin: "Ürettiklerin", sembol: "pencil.line")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: genis ? 170 : 150), spacing: 10)], spacing: 10) {
                tile("\(s.notes)", "not", "bugün \(s.today.notes) · hafta \(s.week.notes)")
                tile("\(s.sentences)", "cümle", "\(s.words) kelime")
                tile("\(Int((s.seconds / 60).rounded()))", "dk sesle", "\(s.voice) sesli not")
                tile("\(s.anchored)", "yere bağlı", "\(s.notes - s.anchored) kitaba · \(s.books) kitap")
                tile("\(depo.durum.kendiCumleler.count)", "kürde yazdığın", "yorum · alıntı · cümle")
            }
        }
    }

    private func tile(_ big: String, _ label: String, _ small: String) -> some View {
        Yuzey(dolgu: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(big).font(.system(size: 30, weight: .bold, design: .serif)).foregroundStyle(Tema.metin).monospacedDigit()
                Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.vurgu)
                Text(small).font(.caption2).foregroundStyle(Tema.soluk).lineLimit(1)
            }
        }
    }

    private var chart: some View {
        let days = stats.days
        let top = max(days.map(\.notes).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 8) {
            Bolumbasi(metin: "Son 14 gün", sembol: "chart.bar")
            Yuzey(dolgu: 14) {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(days) { d in
                        VStack(spacing: 4) {
                            Text(d.notes > 0 ? "\(d.notes)" : "").font(.system(size: 10, weight: .semibold)).foregroundStyle(Tema.ikincil).frame(height: 12)
                            Capsule().fill(d.notes > 0 ? Tema.vurgu : Tema.cizgi)
                                .frame(height: max(4, 70 * CGFloat(d.notes) / CGFloat(top)))
                            Text(d.day.formatted(.dateTime.weekday(.narrow).locale(Dil.tr))).font(.system(size: 10)).foregroundStyle(Tema.soluk)
                        }
                        .frame(maxWidth: .infinity)
                        .help("\(Tarih.kisa(d.day)) · \(d.notes) not · \(d.words) kelime")
                    }
                }
                .frame(height: 104, alignment: .bottom)
            }
        }
    }

    private var books: some View {
        VStack(alignment: .leading, spacing: 8) {
            Bolumbasi(metin: "Kitaplara göre", sembol: "books.vertical")
            Yuzey(dolgu: 14) {
                VStack(spacing: 8) {
                    let top = max(stats.perBook.first?.notes ?? 1, 1)
                    ForEach(stats.perBook.prefix(6), id: \.id) { b in
                        Button { bookFilter = bookFilter == b.id ? nil : b.id } label: {
                            HStack(spacing: 10) {
                                Text(b.title.kodsuz).font(.system(size: 13, weight: bookFilter == b.id ? .bold : .regular))
                                    .foregroundStyle(Tema.metin).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                Capsule().fill(Tema.vurgu.opacity(bookFilter == b.id ? 1 : 0.55))
                                    .frame(width: 90 * CGFloat(b.notes) / CGFloat(top), height: 6)
                                Text("\(b.notes)").font(.caption.monospacedDigit()).foregroundStyle(Tema.ikincil).frame(width: 26, alignment: .trailing)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Filter.allCases) { f in
                        Button { filter = f } label: {
                            Text(f.rawValue).font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .foregroundStyle(filter == f ? Color.white : Tema.ikincil)
                                .background { Capsule().fill(filter == f ? Tema.vurgu : Tema.yuzey2) }
                        }
                        .buttonStyle(.plain)
                    }
                    if let b = bookFilter, let t = stats.perBook.first(where: { $0.id == b })?.title {
                        Button { bookFilter = nil } label: {
                            Label(t.kodsuz, systemImage: "xmark.circle.fill").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background { Capsule().fill(Tema.vurgu.opacity(0.14)) }
                        }
                        .buttonStyle(.plain).foregroundStyle(Tema.vurgu)
                    }
                }
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.and.pencil").font(.system(size: 34)).foregroundStyle(Tema.soluk)
            Text(store.notes.isEmpty ? "Henüz not yok" : "Bu süzgeçte not yok").font(.headline).foregroundStyle(Tema.metin)
            Text("Bir kitabı açınca ✎ düğmesiyle yaz ya da sesinle anlat; notların burada toplanır.")
                .font(.footnote).foregroundStyle(Tema.ikincil).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    private var list: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(grouped, id: \.0) { day, notes in
                Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Dil.tr)).uppercased(with: Dil.tr))
                    .font(.system(size: 11, weight: .bold)).tracking(0.7).foregroundStyle(Tema.soluk).padding(.top, 6)
                ForEach(notes) { n in
                    NoteRow(player: player, note: n, showBook: true, onEdit: { editing = n },
                            onOpenBook: library.entry(n.book).map { e in { opening = e } })
                }
            }
        }
    }

    private func markdown(_ notes: [TeoriaNote]) -> String {
        var out = "# Teoria notlarım\n"
        for (book, list) in Dictionary(grouping: notes, by: \.bookTitle).sorted(by: { $0.key < $1.key }) {
            out += "\n## \(book.kodsuz)\n"
            for n in list.sorted(by: { $0.created < $1.created }) {
                out += "\n"
                if let q = n.quote { out += "> \(q)\n\n" }
                out += n.text.isEmpty ? "_(sesli not)_\n" : n.text + "\n"
            }
        }
        return out
    }
}
