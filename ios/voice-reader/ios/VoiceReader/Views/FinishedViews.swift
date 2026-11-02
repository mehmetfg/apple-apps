// A finished book stays finished: play or a jump on it asks first, and a new reading is the reader's own choice.
// The automation's question when a step's book is finished lives here too.
import SwiftUI

/// The two questions, attached once at the root so they show over the reader and the bicycle screen as well.
struct FinishedAlerts: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content
            .alert(finishedTitle, isPresented: Binding(get: { model.finishedPrompt != nil },
                                                       set: { if !$0 { model.finishedPrompt = nil } })) {
                if let p = model.finishedPrompt {
                    Button("Baştan başla · \(p.times + 1). okuma") { model.startReadingAgain(p.id, play: true) }
                    if let t = p.target {
                        Button("Buradan başla · \(p.times + 1). okuma") { model.startReadingAgain(p.id, at: t, play: true) }
                    }
                    Button("Bitti olarak kalsın", role: .cancel) {}
                }
            } message: { Text(finishedMessage) }
            .alert(choiceTitle, isPresented: Binding(get: { model.automationChoice != nil }, set: { _ in })) {
                if let c = model.automationChoice {
                    if let n = c.nextTitle { Button("Sıradakine geç: \(n)") { model.answerAutomationChoice(key: 1) } }
                    if let t = c.currentTitle { Button("Bu kitaptan sür: \(t)") { model.answerAutomationChoice(key: -1) } }
                    Button("Otomasyonu durdur", role: .destructive) { model.answerAutomationChoice(key: 0) }
                }
            } message: { Text("Kulaklıkta: ⏭ sıradaki · ⏮ bu kitap · ⏯ durdur") }
    }

    private var finishedTitle: String { "Bu kitap bitti" }

    private var finishedMessage: String {
        guard let p = model.finishedPrompt else { return "" }
        let when = p.finishedAt.formatted(.dateTime.day().month(.wide).year())
        let times = p.times >= 2 ? " Bu kitabı \(p.times) kez bitirdin." : ""
        return "\(p.title)\n\(when) tarihinde bitirdin.\(times) Yer sonda duruyor; yeni bir okuma başlatmadıkça değişmez."
    }

    private var choiceTitle: String {
        guard let c = model.automationChoice else { return "" }
        return c.finishedTitle.map { "Sıradaki kitap bitmiş: \($0)" } ?? "\(c.folder) klasöründe bitmemiş kitap yok"
    }
}

/// Over the reader's page while the open book is finished: a quiet band with the date and the one way to start again.
struct FinishedBand: View {
    @Environment(AppModel.self) private var model
    let doc: DocumentRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill").font(.title3).foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(doc.finishes.count >= 2 ? "Bitti · \(doc.finishes.count) kez" : "Bitti").font(.subheadline.weight(.semibold))
                if let f = doc.finishedAt {
                    Text(f.formatted(.dateTime.day().month(.wide).year())).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Button { model.startReadingAgain(doc.id, play: false) } label: {
                Label("Başa dön", systemImage: "arrow.counterclockwise").font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .accessibilityHint("\(doc.finishes.count + 1). okumayı başlatır")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .modifier(GlassPanel(cornerRadius: 16))
        .padding(.horizontal, 12)
    }
}

// MARK: - Aktif bekleme

/// The waits offered when the play button is held, and in the settings.
struct ActivePauseChoice {
    var seconds: Double                 // 0 = until the music stops
    var name: String
    static let all: [ActivePauseChoice] = [
        .init(seconds: 60, name: "1 dakika"), .init(seconds: 90, name: "1,5 dakika"), .init(seconds: 120, name: "2 dakika"),
        .init(seconds: 180, name: "3 dakika"), .init(seconds: 300, name: "5 dakika"), .init(seconds: 0, name: "Müzik durunca"),
    ]
}

/// Held play button: wait so long, then go on by itself (from the start of the sentence it stopped in).
struct ActivePauseMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let p = model.player
        Section("Bekle, sonra kendin sür") {
            ForEach(ActivePauseChoice.all, id: \.seconds) { c in
                Button { p.activePause(seconds: c.seconds > 0 ? c.seconds : nil) } label: {
                    Label(c.name, systemImage: c.seconds > 0 ? "hourglass" : "music.note")
                }
            }
        }
        if p.breakEnds != nil {
            Button(role: .destructive) { p.cancelWait() } label: { Label("Beklemeyi kaldır", systemImage: "xmark") }
        }
    }
}
