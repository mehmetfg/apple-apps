// The app's side of the system surface (2026-11-06): the commands from ReadingSurface, the reading card on the lock
// screen, and the library in Spotlight. None of this moves the reading place on its own: play and mark act where the
// player already is, and a Spotlight result only shows the place.
import ActivityKit
import Foundation
import PDMBus

extension AppModel {
    /// Called once when the app starts, with or without a window.
    func installSystemSurface() {
        AppModel.current = self
        ReadingBridge.handler = { command in await AppModel.current?.run(command) }
        ReadingCard.shared.endLeftovers()
    }

    private func run(_ command: ReadingCommand) async {
        if player.documentID == nil { await restoreLastDocument() }
        guard player.documentID != nil else { return }
        switch command {
        case .toggle: player.toggle()
        case .mark: markSpokenSentence()
        case .voiceNote: toggleVoiceNote()
        }
        ReadingCard.shared.sync(self)
    }

    /// Books and marked sentences, in the system search. Runs after the library is there and when the app leaves
    /// the screen; only what changed is written.
    func indexForSpotlight() {
        let docs = store.documents
        Task.detached(priority: .utility) {
            var books: [PDMSpotlight.Item] = []
            var marks: [PDMSpotlight.Item] = []
            for d in docs {
                books.append(.init(id: "book/\(d.id.uuidString)", title: d.title, detail: d.author,
                                   thumbnail: WidgetShared.coverURL(d.id)))
                for h in d.highlights {
                    let text = h.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    marks.append(.init(id: "book/\(d.id.uuidString)?at=\(h.location)", title: text, detail: d.title))
                }
            }
            await PDMSpotlight.sync(books, scope: "books")
            await PDMSpotlight.sync(marks, scope: "marks")
        }
    }
}

/// The reading card on the lock screen: the book, the chapter, how far, and three keys. It follows the player and goes
/// away ten minutes after reading stops.
@MainActor
final class ReadingCard {
    static let shared = ReadingCard()
    private var activity: Activity<ReadingActivity>?
    private var watcher: Task<Void, Never>?
    private var pausedSince: Date?
    private var lastState: ReadingActivity.ContentState?

    static var enabled: Bool { UserDefaults.standard.object(forKey: "readingCard") as? Bool ?? true }

    func endLeftovers() {
        for a in Activity<ReadingActivity>.activities {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }

    func sync(_ model: AppModel) {
        guard Self.enabled, ActivityAuthorizationInfo().areActivitiesEnabled, let id = model.player.documentID else { end(); return }
        let playing = model.player.isPlaying, recording = model.recorder.isRecording
        pausedSince = playing || recording ? nil : (pausedSince ?? .now)
        if activity == nil, !playing, !recording { return }
        if let a = activity, a.attributes.documentID != id.uuidString { end() }

        let state = ReadingActivity.ContentState(
            chapter: model.player.chapterTitle(at: model.player.cursor) ?? "",
            progress: min(1, max(0, Double(model.player.cursor) / Double(max(1, model.player.length)))),
            playing: playing, marks: model.store.document(id)?.highlights.count ?? 0, recording: recording)
        if let a = activity {
            guard state != lastState else { return }
            lastState = state
            let stale = playing || recording ? nil : Date.now.addingTimeInterval(600)
            Task { await a.update(ActivityContent(state: state, staleDate: stale)) }
        } else {
            let attributes = ReadingActivity(documentID: id.uuidString, title: model.player.title)
            activity = try? Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: nil))
            lastState = state
            guard activity != nil else { return }
            watch(model)
        }
    }

    /// While the card is there: the chapter and the percentage every half minute, and the end after a long pause.
    private func watch(_ model: AppModel) {
        watcher?.cancel()
        watcher = Task { [weak self, weak model] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, let model, !Task.isCancelled else { return }
                if let p = self.pausedSince, Date.now.timeIntervalSince(p) > 600 { self.end(); return }
                self.sync(model)
            }
        }
    }

    func end() {
        watcher?.cancel(); watcher = nil
        pausedSince = nil; lastState = nil
        guard let a = activity else { return }
        activity = nil
        Task { await a.end(nil, dismissalPolicy: .immediate) }
    }
}
