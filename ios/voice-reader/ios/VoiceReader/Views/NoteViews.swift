// The reader's note parts: the microphone button (always at hand), the recording strip, the "saved" toast, the note
// sheet (listen, read, write), and the bicycle bar (three big buttons).
import SwiftUI
import AVFoundation

/// How long a microphone key is held before a recording starts, on every screen: long enough that a brush of the
/// thumb does nothing, short enough not to keep a riding hand off the bar (2026-10-26: 1 s was too long).
enum MicHold { static let seconds = 0.5 }

/// One tap: record a voice note about the sentence being read. Tap again: stop and save.
struct MicButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accent) private var accent
    var size: CGFloat = 58
    /// A brush of the thumb must not start a recording: it starts only after a short hold (`MicHold`) (a ring fills while
    /// the finger is down). While recording, one tap ends it.
    @State private var pressing = false
    @State private var hint = false

    var body: some View {
        let rec = model.recorder
        let on = rec.isRecording
        ZStack {
            if on {
                Circle().fill(Color.red.opacity(0.25))
                    .scaleEffect(1 + CGFloat(rec.level) * 0.45)
                    .animation(.easeOut(duration: 0.12), value: rec.level)
            }
            Circle().fill(on ? Color.red : accent.solid)
            Circle().trim(from: 0, to: pressing && !on ? 1 : 0)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(3)
                .animation(pressing ? .linear(duration: MicHold.seconds) : .easeOut(duration: 0.15), value: pressing)
            Image(systemName: on ? "stop.fill" : "mic.fill")
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        .contentShape(Circle())
        .onTapGesture {
            if on { model.toggleVoiceNote() } else { hint = true }
        }
        .onLongPressGesture(minimumDuration: MicHold.seconds, maximumDistance: 30) {
            if !model.recorder.isRecording { model.toggleVoiceNote() }
        } onPressingChanged: { pressing = $0 }
        .overlay(alignment: .top) {
            if hint {
                Text("Kayıt için basılı tut")
                    .font(.caption.weight(.semibold)).fixedSize()
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .modifier(GlassCapsule(interactive: false, fallback: Color(uiColor: .secondarySystemBackground)))
                    .offset(x: 50, y: -40)
                    .transition(.opacity)
                    .task { try? await Task.sleep(for: .seconds(1.6)); withAnimation { hint = false } }
            }
        }
        .animation(.smooth(duration: 0.2), value: hint)
        .sensoryFeedback(.impact(weight: .medium), trigger: on)
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(on ? "Sesli notu bitir" : "Sesli not")
        .accessibilityHint(on ? "" : "Kayıt için yarım saniye basılı tutun")
        .accessibilityAction { model.toggleVoiceNote() }
    }
}

/// While recording: what the note belongs to and how long it has run.
struct RecordingStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.recorder.isRecording, let start = model.recorder.startedAt {
            Button { model.finishVoiceNote() } label: {
                HStack(spacing: 10) {
                    Circle().fill(.red).frame(width: 10, height: 10)
                    TimelineView(.periodic(from: start, by: 1)) { ctx in
                        Text(Format.clock(ctx.date.timeIntervalSince(start))).monospacedDigit()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    Label(model.recorder.inputName ?? "Mikrofon",
                          systemImage: model.recorder.headsetInput ? "headphones" : "iphone")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(model.recorder.headsetInput ? Color.green : Color.orange)
                        .lineLimit(1)
                    Text("bitirmek için dokun").font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                    Button { model.cancelVoiceNote() } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).frame(width: 28, height: 28)
                            .background(Color.primary.opacity(0.08), in: Circle())
                    }
                    .accessibilityLabel("Kaydı at")
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .modifier(GlassPanel(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

/// "Saved": length and, once written, the note's text. Tap to open it.
struct NoteToastView: View {
    @Environment(AppModel.self) private var model
    var onOpen: (String) -> Void

    var body: some View {
        if let t = model.noteToast {
            Button { onOpen(t.id); model.noteToast = nil } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 20))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Not kaydedildi" + (t.seconds.map { " · " + Format.clock($0) } ?? ""))
                            .font(.system(size: 14, weight: .semibold))
                        Text(t.text.isEmpty ? "Yazıya dökülüyor…" : t.text)
                            .font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .modifier(GlassPanel(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: t) {
                try? await Task.sleep(for: .seconds(t.text.isEmpty ? 6 : 4))
                if !Task.isCancelled, model.noteToast == t { withAnimation(.smooth) { model.noteToast = nil } }
            }
        }
    }
}

/// What the note sheet shows: a new written note on a range, or a note that exists.
enum NoteSheetItem: Identifiable {
    case new(range: NSRange, quote: String)
    case existing(String)
    var id: String {
        switch self {
        case .new(let r, _): "new-\(r.location)-\(r.length)"
        case .existing(let i): i
        }
    }
}

struct NoteSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent
    let item: NoteSheetItem
    @State private var text = ""
    @State private var audio: AVAudioPlayer?
    @State private var playing = false
    @FocusState private var focused: Bool

    private var note: ReaderNote? { if case .existing(let i) = item { model.notes.note(i) } else { nil } }
    private var quote: String {
        switch item {
        case .new(_, let q): q
        case .existing: note?.quote ?? ""
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("“\(quote.prefix(400))”")
                        .font(.system(size: 16, design: .serif)).italic()
                        .foregroundStyle(.secondary)
                    if let n = note, n.hasVoice {
                        HStack(spacing: 12) {
                            Button { togglePlay(n) } label: {
                                Image(systemName: playing ? "pause.fill" : "play.fill")
                                    .font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                                    .frame(width: 46, height: 46).background(Palette.play, in: Circle())
                            }
                            .buttonStyle(.plain)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sesli not · " + Format.clock(n.seconds ?? 0)).font(.subheadline.weight(.semibold))
                                Text(n.transcript == "device" ? "Telefonda yazıya döküldü; Mac'te Whisper düzeltir."
                                     : n.text.isEmpty ? "Henüz yazıya dökülmedi." : "")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    TextField(note?.hasVoice == true ? "Dökümü düzelt ya da ekle" : "Aklına geleni yaz", text: $text, axis: .vertical)
                        .lineLimit(4...14)
                        .focused($focused)
                        .padding(12)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                    if case .new(let r, _) = item {
                        Button {
                            dismiss()
                            Task { try? await Task.sleep(for: .milliseconds(350)); model.startVoiceNote(anchor: r) }
                        } label: {
                            Label("Sesle söyle", systemImage: "mic.fill").font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .foregroundStyle(.white)
                                .background(accent.ink, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                    if let n = note {
                        Text(n.date.formatted(date: .abbreviated, time: .shortened) + (n.chapterTitle.map { " · " + $0 } ?? ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(18)
            }
            .navigationTitle(note == nil ? "Not" : (note?.hasVoice == true ? "Sesli not" : "Not"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Kaydet") { save(); dismiss() }.bold() }
                if let n = note {
                    ToolbarItem(placement: .bottomBar) {
                        Button(role: .destructive) { model.notes.delete(n.id); dismiss() } label: { Label("Notu sil", systemImage: "trash") }
                            .tint(.red)
                    }
                }
            }
            .onAppear {
                text = note?.text ?? ""
                if note == nil { focused = true }
            }
            .onDisappear { audio?.stop() }
        }
    }

    private func save() {
        switch item {
        case .new(let r, let q):
            model.addTextNote(r, quote: q, text: text)
        case .existing(let i):
            if let n = note, text.trimmingCharacters(in: .whitespacesAndNewlines) != n.text {
                model.notes.setText(i, text, transcript: n.hasVoice ? "edited" : nil)
            }
        }
    }

    private func togglePlay(_ n: ReaderNote) {
        if playing { audio?.pause(); playing = false; return }
        if audio == nil, let u = model.notes.audioURL(n) {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try? AVAudioSession.sharedInstance().setActive(true)
            audio = try? AVAudioPlayer(contentsOf: u)
        }
        playing = audio?.play() ?? false
        if playing, let d = audio?.duration {
            Task { try? await Task.sleep(for: .seconds(d + 0.2)); if audio?.isPlaying == false { playing = false } }
        }
    }
}
