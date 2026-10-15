// Writing a new note and recording a voice idea.
import SwiftUI

struct ComposeSheet: View {
    @EnvironmentObject var store: VaultStore
    @EnvironmentObject var router: Router
    @Environment(\.dismiss) private var dismiss
    @State var kind: NoteKind
    @State private var title = ""
    @State private var text = ""
    @State private var folder = ""
    @State private var discipline = ""
    @State private var saving = false
    @FocusState private var bodyFocused: Bool

    static let disciplines = ["", "felsefe", "dil", "sistem", "edebiyat", "finans", "fizik"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(NoteKind.allCases) { k in
                                Button { withAnimation(.snappy) { kind = k } } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: k.symbol).font(.title3)
                                            .frame(width: 44, height: 44)
                                            .background(kind == k ? Palette.kind(k) : Palette.kind(k).opacity(0.13), in: RoundedRectangle(cornerRadius: 13))
                                            .foregroundStyle(kind == k ? .white : Palette.kind(k))
                                        Text(k.label).font(.caption2.weight(.semibold))
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    Text(kind.hint).font(.footnote).foregroundStyle(.secondary)
                }
                if kind != .journal {
                    Section("Başlık") {
                        TextField(kind == .idea ? "Boş bırakırsan ilk cümleden" : "Başlık", text: $title)
                    }
                }
                Section(kind == .journal ? "Bugünün günlüğüne eklenecek" : "Metin") {
                    TextEditor(text: $text)
                        .font(.system(.body, design: .serif))
                        .frame(minHeight: 220)
                        .focused($bodyFocused)
                }
                if kind == .note {
                    Section("Klasör") {
                        TextField("Inbox", text: $folder)
                        let suggestions = store.areas().map(\.name).filter { folder.isEmpty || $0.localizedCaseInsensitiveContains(folder) }.prefix(6)
                        ForEach(Array(suggestions), id: \.self) { s in
                            Button(s) { folder = s }.font(.footnote)
                        }
                    }
                }
                if kind != .journal && kind != .poem {
                    Section("Disiplin") {
                        Picker("Disiplin", selection: $discipline) {
                            ForEach(Self.disciplines, id: \.self) { Text($0.isEmpty ? "—" : $0).tag($0) }
                        }
                    }
                }
                Section {
                    Label(destination, systemImage: "folder").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(kind == .journal ? "Günlük" : "Yeni \(kind.label.lowercased())")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: { saving ? AnyView(ProgressView()) : AnyView(Text("Kaydet").bold()) }
                        .disabled(saving || (kind != .journal && title.isEmpty && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                }
            }
            .onAppear {
                if let f = UserDefaults.standard.string(forKey: "composeFolder") { folder = f; UserDefaults.standard.removeObject(forKey: "composeFolder") }
                bodyFocused = true
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 620)
        #endif
    }

    private var destination: String {
        if kind == .journal { return store.journalPath(for: Date()) }
        if kind == .note { return (folder.isEmpty ? "Inbox" : folder) + "/" }
        return store.folder(for: kind) + "/"
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            let path = try await store.create(kind: kind, title: title, body: text, folder: folder, discipline: discipline.isEmpty ? nil : discipline)
            dismiss()
            try? await Task.sleep(nanoseconds: 350_000_000)
            router.open(path)
        } catch {
            store.message = error.localizedDescription
        }
    }
}

struct VoiceSheet: View {
    @EnvironmentObject var store: VaultStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = VoiceRecorder()
    @State private var savedPath: String?
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 26) {
            Capsule().fill(.secondary.opacity(0.4)).frame(width: 40, height: 5).padding(.top, 10)
            Text(recorder.isRecording ? "Dinliyorum" : savedPath != nil ? "Kaydedildi" : "Sesli fikir")
                .font(.title2.weight(.bold)).fontDesign(.rounded)
            Text(timeText).font(.system(size: 48, weight: .light, design: .rounded).monospacedDigit())
            HStack(alignment: .center, spacing: 3) {
                ForEach(Array(paddedLevels.enumerated()), id: \.offset) { _, l in
                    Capsule().fill(Palette.rose.opacity(0.35 + Double(l) * 0.65)).frame(width: 4, height: 6 + CGFloat(l) * 60)
                }
            }
            .frame(height: 70)
            .animation(.linear(duration: 0.1), value: recorder.levels)

            Button {
                Task {
                    if recorder.isRecording {
                        savedPath = await recorder.stop(into: store)
                        if savedPath != nil {
                            store.message = "Ses Kıvılcım'a düştü; Mac yazıya dökecek."
                            try? await Task.sleep(nanoseconds: 900_000_000)
                            dismiss()
                        }
                    } else {
                        savedPath = nil
                        await recorder.start()
                    }
                }
            } label: {
                ZStack {
                    Circle().fill(Palette.rose.opacity(0.18)).frame(width: 120, height: 120).scaleEffect(pulse && recorder.isRecording ? 1.15 : 1)
                    Circle().fill(Palette.rose).frame(width: 88, height: 88).shadow(color: Palette.rose.opacity(0.45), radius: 12, y: 4)
                    Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill").font(.system(size: 32, weight: .bold)).foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever()) { pulse = true } }

            if let e = recorder.error { Text(e).font(.footnote).foregroundStyle(Palette.rose).multilineTextAlignment(.center) }
            Text("Kayıt vault'ta Kıvılcım'ın klasörüne düşer. Mac'teki Kıvılcım yerel Whisper ile yazıya döker ve sınıflar — token harcanmaz.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 24)
            if recorder.isRecording {
                Button("Kaydı at", role: .destructive) { recorder.cancel() }.font(.footnote)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
        .presentationDetents([.medium, .large])
        #if os(macOS)
        .frame(width: 440, height: 560)
        .overlay(alignment: .topTrailing) { Button("Kapat") { recorder.cancel(); dismiss() }.padding() }
        #endif
    }

    private var timeText: String {
        let s = Int(recorder.elapsed)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private var paddedLevels: [Float] {
        Array(repeating: 0, count: max(0, 40 - recorder.levels.count)) + recorder.levels.suffix(40)
    }
}
