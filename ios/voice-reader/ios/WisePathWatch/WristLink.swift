import Observation
import WatchConnectivity
import WatchKit

/// The watch's side: the last state the phone sent, and the keys sent back to it.
@MainActor
@Observable
final class WristLink: NSObject, WCSessionDelegate {
    private(set) var state: WristState?
    private(set) var isReachable = false

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ command: WristState.Command) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            WKInterfaceDevice.current().play(.failure)
            return
        }
        WKInterfaceDevice.current().play(.click)
        if command == .toggle, var shown = state {
            // Shown at once; the phone's answer confirms it.
            shown.isPlaying.toggle()
            state = shown
        }
        session.sendMessage([WristState.commandKey: command.rawValue], replyHandler: { [weak self] reply in
            let answer = WristState(reply)
            Task { @MainActor in if let answer { self?.state = answer } }
        }, errorHandler: { _ in
            Task { @MainActor in WKInterfaceDevice.current().play(.failure) }
        })
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let received = WristState(session.receivedApplicationContext)
        let reachable = session.isReachable
        Task { @MainActor in
            if let received { state = received }
            isReachable = reachable
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let received = WristState(applicationContext)
        Task { @MainActor in if let received { state = received } }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in isReachable = reachable }
    }
}
