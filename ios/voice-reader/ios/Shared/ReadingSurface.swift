// What Wise Path shows outside the app (2026-11-06): the actions for the lock screen, Control Center, the Action
// Button and Siri, and the reading card on the lock screen. Compiled into the app and the widget extension. The
// extension only needs the types: LiveActivityIntent and AudioPlaybackIntent run in the app's process, which sets
// `ReadingBridge.handler`.
import ActivityKit
import AppIntents
import Foundation

enum ReadingCommand: Sendable { case toggle, mark, voiceNote }

enum ReadingBridge {
    nonisolated(unsafe) static var handler: (@Sendable (ReadingCommand) async -> Void)?
}

struct ReadingActivity: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var chapter: String
        var progress: Double
        var playing: Bool
        var marks: Int
        var recording: Bool
    }
    var documentID: String
    var title: String
}

/// Reads on, or stops, without opening the app.
struct ToggleReadingIntent: AudioPlaybackIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Okumayı başlat ya da durdur"
    static let description = IntentDescription("Wise Path okumayı kaldığın yerden sürdürür ya da durdurur. Uygulama açılmaz.")
    static let openAppWhenRun = false
    func perform() async throws -> some IntentResult {
        await ReadingBridge.handler?(.toggle)
        return .result()
    }
}

/// Marks the sentence being read. A second time on the same sentence takes the mark away.
struct MarkSentenceIntent: AudioPlaybackIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Okunan cümleyi işaretle"
    static let description = IntentDescription("Wise Path'te o an okunan cümleyi işaretler. Uygulama açılmaz.")
    static let openAppWhenRun = false
    func perform() async throws -> some IntentResult {
        await ReadingBridge.handler?(.mark)
        return .result()
    }
}

/// A spoken note on the sentence being read. iOS allows the microphone here only while the reading card is on the
/// lock screen; without the card the app opens.
struct VoiceNoteIntent: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Sesli not al"
    static let description = IntentDescription("Wise Path'te okunan cümleye sesli not alır. İkinci basış notu bitirir.")
    static let openAppWhenRun = false
    func perform() async throws -> some IntentResult {
        await ReadingBridge.handler?(.voiceNote)
        return .result()
    }
}
