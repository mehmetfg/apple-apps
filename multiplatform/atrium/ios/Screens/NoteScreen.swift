// One note: rendered reading view, raw editing, conflict handling, links and backlinks.
import SwiftUI

struct NoteScreen: View {
    @EnvironmentObject var store: VaultStore
    var path: String

    @State private var loaded: LoadedNote?
    @State private var draft = ""
    @State private var editing = false
    @State private var saving = false
    @State private var error: String?
    @State private var conflict: (text: String, modified: Date)?
    @FocusState private var editorFocused: Bool

    var body: some View {
        let record = store.record(path)
        Group {
            if let loaded {
                if editing {
                    editor
                } else {
                    reader(loaded, record: record)
                }
            } else if let error {
                ContentUnavailableView("Açılamadı", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("iCloud'dan getiriliyor…").font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Palette.page)
        .navigationTitle(record?.name ?? (path as NSString).lastPathComponent)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if editing {
                    Button { Task { await save(force: false) } } label: {
                        if saving { ProgressView() } else { Text("Kaydet").bold() }
                    }
                    .disabled(saving)
                } else {
                    Button { startEditing() } label: { Image(systemName: "pencil") }.disabled(loaded == nil)
                }
            }
            if editing {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { editing = false; draft = loaded?.text ?? "" }
                }
            }
        }
        .task(id: path) { await load() }
        .alert("Dosya başka yerde değişti", isPresented: Binding(get: { conflict != nil }, set: { if !$0 { conflict = nil } })) {
            Button("Benimkini yaz", role: .destructive) { Task { await save(force: true) } }
            Button("Onlarınkini al") {
                if let c = conflict { loaded = LoadedNote(text: c.text, modified: c.modified); draft = c.text }
                conflict = nil
            }
            Button("Vazgeç", role: .cancel) { conflict = nil }
        } message: {
            Text("Obsidian ya da öteki cihaz bu notu sen düzenlerken değiştirdi. Hangisi kalsın?")
        }
    }

    // MARK: Reader

    private func reader(_ note: LoadedNote, record: NoteRecord?) -> some View {
        let fm = Frontmatter.split(note.text)
        let backlinks = store.backlinks(to: path)
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                metaHeader(fm: fm, record: record, modified: note.modified)
                MarkdownView(text: fm.body, accent: record.map { Palette.kind($0.kind) } ?? Palette.accent)
                    .padding(.horizontal, 2)
                if !backlinks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(title: "Buraya bağlananlar", detail: "\(backlinks.count)")
                        NoteList(notes: Array(backlinks.prefix(30)), showFolder: true)
                    }
                    .padding(.top, 12)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .noteLinks(source: path)
        .onTapGesture(count: 2) { startEditing() }
    }

    private func metaHeader(fm: Frontmatter, record: NoteRecord?, modified: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(path.split(separator: "/").dropLast().joined(separator: " › ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            HStack(spacing: 6) {
                if let r = record {
                    Pill(text: r.kind.label, color: Palette.kind(r.kind), symbol: r.kind.symbol)
                    Pill(text: r.origin.label, color: Palette.origin(r.origin))
                    if let w = r.words { Pill(text: "\(Format.number(w)) kelime", color: .secondary) }
                }
                Spacer(minLength: 0)
            }
            Text("Son değişiklik \(TurkishCalendar.relative(modified)) · \(TurkishCalendar.journalTitle(modified)) \(Format.time(modified))")
                .font(.caption).foregroundStyle(.secondary)
            let visible = fm.fields.filter { !["yazan", "tür", "journal", "Günlük Tarihi"].contains($0.key) && !$0.value.list.isEmpty }
            if !visible.isEmpty {
                DisclosureGroup("Künye · \(visible.count) alan") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(visible.enumerated()), id: \.offset) { _, f in
                            HStack(alignment: .top) {
                                Text(f.key).font(.caption.weight(.semibold)).frame(width: 110, alignment: .leading)
                                Text(f.value.list.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.top, 6)
                }
                .font(.caption.weight(.semibold))
                .tint(.secondary)
            }
            Divider()
        }
    }

    // MARK: Editor

    private var editor: some View {
        VStack(spacing: 0) {
            TextEditor(text: $draft)
                .font(.system(.body, design: .serif))
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .focused($editorFocused)
            HStack {
                Text("\(TextTools.wordCount(Frontmatter.split(draft).body)) kelime").font(.caption.monospacedDigit())
                Spacer()
                if draft != loaded?.text { Text("kaydedilmedi").font(.caption).foregroundStyle(Palette.rose) }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(.bar)
        }
        .frame(maxWidth: 820)
        .frame(maxWidth: .infinity)
        .background(Palette.card)
    }

    private func startEditing() {
        guard let loaded else { return }
        draft = loaded.text
        editing = true
        editorFocused = true
    }

    // MARK: IO

    private func load() async {
        error = nil
        for attempt in 0..<20 {
            do {
                loaded = try await store.read(path)
                draft = loaded?.text ?? ""
                return
            } catch {
                if attempt == 19 { self.error = error.localizedDescription }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    private func save(force: Bool) async {
        guard let loaded else { return }
        saving = true
        defer { saving = false }
        do {
            let m = try await store.write(path, text: draft, expected: loaded.modified, force: force)
            self.loaded = LoadedNote(text: draft, modified: m)
            editing = false
            conflict = nil
        } catch VaultError.conflict(let current, let modified) {
            conflict = (current, modified)
        } catch {
            store.message = error.localizedDescription
        }
    }
}
