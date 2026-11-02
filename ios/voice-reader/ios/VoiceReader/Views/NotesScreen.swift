// Notlarım: every note in one place, apart from the books, each one showing the book and the sentence it belongs to.
// Listen in the row, read the text, open the note, or go to its place in the book. Going there only brings the
// sentence on screen; the place you stopped reading stays where it is (it changes only by ▶ or a double tap).
import SwiftUI
import AVFoundation

struct NotesCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accent) private var accent

    var body: some View {
        let all = model.notes.notes
        let voice = all.filter(\.hasVoice)
        NavigationLink(value: Route.notes) {
            HStack(spacing: 14) {
                Image(systemName: "waveform")
                    .font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(accent.ink, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Notlarım").font(.headline)
                    Text(all.isEmpty ? "Okurken 🎙 ile söylediklerin burada toplanır"
                         : "\(voice.count) sesli · \(all.count - voice.count) yazılı" + (all.first.map { " · son: " + $0.bookTitle } ?? ""))
                        .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.tertiary)
            }
            .padding(16)
            .modifier(GlassPanel(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .accessibilityLabel("Notlarım: \(all.count) not, \(voice.count) sesli")
    }
}

struct NotesScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accent) private var accent
    var onOpenBook: (UUID, Int) -> Void

    enum Kind: String, CaseIterable { case all = "Hepsi", voice = "Sesli", text = "Yazılı" }
    enum Order: String, CaseIterable { case date = "Tarih", book = "Kitap" }
    @State private var kind: Kind = .all
    @State private var order: Order = .date
    @State private var query = ""
    @State private var sheet: NoteSheetItem?
    @State private var audio = NoteAudio()

    private var shown: [ReaderNote] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return model.notes.notes.filter { n in
            switch kind {
            case .all: true
            case .voice: n.hasVoice
            case .text: !n.hasVoice
            }
        }.filter { n in
            q.isEmpty || [n.text, n.quote, n.bookTitle, n.chapterTitle ?? ""].contains { $0.localizedStandardContains(q) }
        }
    }

    var body: some View {
        ZStack {
            InkBackground()
            List {
                Section {
                    Picker("Tür", selection: $kind) { ForEach(Kind.allCases, id: \.self) { Text($0.rawValue) } }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
                let notes = shown
                if notes.isEmpty {
                    ContentUnavailableView(query.isEmpty ? "Not yok" : "Bulunamadı", systemImage: "mic",
                                           description: Text(query.isEmpty ? "Okurken 🎙 düğmesini basılı tut ya da bisiklette ⏮'e bas: not, okunan cümleye bağlanır." : ""))
                        .listRowBackground(Color.clear)
                } else if order == .book {
                    let groups = Dictionary(grouping: notes, by: \.doc)
                        .sorted { ($0.value.first?.stamp ?? .distantPast) > ($1.value.first?.stamp ?? .distantPast) }
                    ForEach(groups, id: \.key) { doc, ns in
                        Section {
                            ForEach(ns.sorted { $0.location < $1.location }) { n in row(n, showsBook: false) }
                        } header: { bookHeader(doc, title: ns.first?.bookTitle ?? "", count: ns.count) }
                    }
                } else {
                    let days = Dictionary(grouping: notes) { Calendar.current.startOfDay(for: $0.date) }.sorted { $0.key > $1.key }
                    ForEach(days, id: \.key) { day, ns in
                        Section(day.formatted(.dateTime.weekday(.wide).day().month(.wide))) {
                            ForEach(ns.sorted { $0.date > $1.date }) { n in row(n, showsBook: true) }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
        }
        .navigationTitle("Notlarım")
        .searchable(text: $query, prompt: "Notta, cümlede ya da kitapta ara")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sırala", selection: $order) {
                        ForEach(Order.allCases, id: \.self) { o in
                            Label(o == .date ? "Tarihe göre" : "Kitaba göre", systemImage: o == .date ? "calendar" : "books.vertical").tag(o)
                        }
                    }
                } label: { Image(systemName: order == .date ? "calendar" : "books.vertical") }
                .accessibilityLabel("Sırala")
            }
        }
        .sheet(item: $sheet) { NoteSheet(item: $0).presentationDetents([.medium, .large]) }
        .onDisappear { audio.stop() }
    }

    private func bookHeader(_ doc: UUID, title: String, count: Int) -> some View {
        let record = model.store.document(doc)
        return HStack(spacing: 10) {
            if let record { CoverView(doc: record, width: 28, showsPlaying: false) }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                Text("\(count) not" + (record == nil ? " · kitap kütüphanede yok" : "")).font(.caption)
            }
            .textCase(nil)
        }
        .padding(.vertical, 4)
    }

    private func row(_ n: ReaderNote, showsBook: Bool) -> some View {
        let book = model.store.document(n.doc)
        let playing = audio.playingID == n.id
        return HStack(alignment: .top, spacing: 12) {
            if n.hasVoice {
                Button {
                    if model.player.isPlaying { model.player.pause() }
                    audio.toggle(n, url: model.notes.audioURL(n))
                } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 40, height: 40).background(Palette.play, in: Circle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(playing ? "Duraklat" : "Sesli notu dinle")
            } else {
                Image(systemName: "note.text").font(.system(size: 17, weight: .semibold)).foregroundStyle(accent.ink)
                    .frame(width: 40, height: 40)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(n.text.isEmpty ? "Yazıya dökülmedi" : n.text)
                    .font(.subheadline).foregroundStyle(n.text.isEmpty ? .secondary : .primary).lineLimit(4)
                Text("“\(n.quote)”").font(.system(size: 13, design: .serif)).italic().foregroundStyle(.secondary).lineLimit(2)
                Button { if book != nil { onOpenBook(n.doc, n.location) } } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "book.closed").font(.caption2)
                        Text(showsBook ? n.bookTitle : (n.chapterTitle ?? "Kitaptaki yeri")).lineLimit(1)
                        if book != nil { Image(systemName: "arrow.up.right").font(.caption2.weight(.bold)) }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(book != nil ? accent.ink : Color.secondary)
                }
                .buttonStyle(.borderless)
                .disabled(book == nil)
                .accessibilityLabel(book != nil ? "Kitapta, bu cümlede aç: \(n.bookTitle)" : n.bookTitle)
                Text((n.hasVoice ? Format.clock(n.seconds ?? 0) + " · " : "") + n.date.formatted(date: .omitted, time: .shortened))
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { sheet = .existing(n.id) }
        .swipeActions(edge: .leading) {
            if book != nil {
                Button { onOpenBook(n.doc, n.location) } label: { Label("Kitapta aç", systemImage: "book") }.tint(accent.ink)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { model.notes.delete(n.id) } label: { Label("Sil", systemImage: "trash") }
        }
        .contextMenu {
            if book != nil {
                Button { onOpenBook(n.doc, n.location) } label: { Label("Kitapta, bu cümlede aç", systemImage: "book") }
            }
            Button { sheet = .existing(n.id) } label: { Label("Notu aç", systemImage: "square.and.pencil") }
            Button(role: .destructive) { model.notes.delete(n.id) } label: { Label("Sil", systemImage: "trash") }
        }
    }
}

/// One note plays at a time, in the list.
@MainActor
@Observable
final class NoteAudio: NSObject, AVAudioPlayerDelegate {
    private(set) var playingID: String?
    @ObservationIgnored private var player: AVAudioPlayer?

    func toggle(_ n: ReaderNote, url: URL?) {
        if playingID == n.id { stop(); return }
        stop()
        guard let url else { return }
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .spokenAudio)
        try? s.setActive(true)
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.delegate = self
        if p.play() { player = p; playingID = n.id }
    }

    func stop() {
        player?.stop()
        player = nil
        playingID = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}
