// What the phone tells the watch (2026-11-17): the book in the player, whether it plays, and today's and the week's
// listening. Sent as WatchConnectivity application context, so the watch has the latest state whenever it wakes;
// the watch answers with a command (toggle · forward · back) as a message. Compiled into the app and the watch app.
import Foundation

struct WristState: Codable, Equatable {
    struct Day: Codable, Equatable, Hashable {
        var label: String
        var minutes: Double
        var today: Bool
    }

    var title: String?
    var author: String?
    var progress: Double
    var isPlaying: Bool
    var todayMinutes: Double
    var week: [Day]
    var updated: Date

    static let contextKey = "state"
    static let commandKey = "command"

    enum Command: String {
        case toggle, forward, back
    }

    var encoded: [String: Any] {
        guard let data = try? JSONEncoder().encode(self) else { return [:] }
        return [Self.contextKey: data]
    }

    init?(_ context: [String: Any]) {
        guard let data = context[Self.contextKey] as? Data,
              let state = try? JSONDecoder().decode(WristState.self, from: data) else { return nil }
        self = state
    }

    init(title: String?, author: String?, progress: Double, isPlaying: Bool, todayMinutes: Double, week: [Day], updated: Date) {
        self.title = title
        self.author = author
        self.progress = progress
        self.isPlaying = isPlaying
        self.todayMinutes = todayMinutes
        self.week = week
        self.updated = updated
    }
}
