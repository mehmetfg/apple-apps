// The phone's side of the watch (2026-11-17): hands the watch what is playing and today's listening, and carries out
// the watch's play/pause and skip keys on the same player the lock screen drives.
import WatchConnectivity

@MainActor
final class WatchLink: NSObject, WCSessionDelegate {
    static let shared = WatchLink()
    private weak var model: AppModel?
    private var last: WristState?

    func start(_ model: AppModel) {
        self.model = model
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Called with each widget snapshot (the snapshot is what the watch shows too) and when playing starts or stops.
    func publish(_ snap: WidgetSnapshot?) {
        guard let model, WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let book = snap?.current
        let state = WristState(title: book?.title, author: book?.author, progress: book?.progress ?? 0,
                               isPlaying: model.player.isPlaying,
                               todayMinutes: snap?.todayMinutes ?? last?.todayMinutes ?? 0,
                               week: snap?.week.map { .init(label: $0.label, minutes: $0.minutes, today: $0.today) } ?? last?.week ?? [],
                               updated: .now)
        last = state
        try? session.updateApplicationContext(state.encoded)
    }

    private func perform(_ command: WristState.Command) {
        guard let model else { return }
        switch command {
        case .toggle: model.player.toggle()
        case .forward: model.player.skip(forward: true, unit: model.settings.navigationUnit)
        case .back: model.player.skip(forward: false, unit: model.settings.navigationUnit)
        }
        publish(WidgetShared.load())
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let command = (message[WristState.commandKey] as? String).flatMap(WristState.Command.init)
        Task { @MainActor in
            if let command { perform(command) }
            replyHandler(last?.encoded ?? [:])
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in publish(WidgetShared.load()) }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
