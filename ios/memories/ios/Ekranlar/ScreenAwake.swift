// Keeps the screen on while something on it is in use (listening, recording).
// Only works while the app is in the foreground; iOS restores auto-lock when the app goes to the background.
import UIKit

@MainActor
enum ScreenAwake {
    static let settingKey = "memories.keepScreenOn"
    private static var reasons: Set<String> = []

    static var enabled: Bool { UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true }

    static func set(_ reason: String, _ on: Bool) {
        if on { reasons.insert(reason) } else { reasons.remove(reason) }
        apply()
    }

    static func apply() {
        let keep = enabled && !reasons.isEmpty
        if UIApplication.shared.isIdleTimerDisabled != keep { UIApplication.shared.isIdleTimerDisabled = keep }
    }
}
