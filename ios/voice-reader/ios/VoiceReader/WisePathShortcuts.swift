// Siri, Shortcuts and the Action Button (2026-11-06). A book is a parameter: "Wise Path'te Felsefe 6'yı aç".
import AppIntents
import Foundation

struct BookEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Kitap"
    static let defaultQuery = BookQuery()
    var id: UUID
    var title: String
    var author: String?
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: author.map { "\($0)" })
    }
}

struct BookQuery: EntityStringQuery {
    @MainActor private func all() -> [BookEntity] {
        (AppModel.current?.store.documents ?? [])
            .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
            .map { BookEntity(id: $0.id, title: $0.title, author: $0.author) }
    }
    func entities(for identifiers: [UUID]) async throws -> [BookEntity] {
        await all().filter { identifiers.contains($0.id) }
    }
    func entities(matching string: String) async throws -> [BookEntity] {
        await all().filter { $0.title.localizedCaseInsensitiveContains(string) }
    }
    func suggestedEntities() async throws -> [BookEntity] { Array(await all().prefix(20)) }
}

/// Opens a book at its place. Reading does not start.
struct OpenBookIntent: AppIntent {
    static let title: LocalizedStringResource = "Kitabı aç"
    static let openAppWhenRun = true
    @Parameter(title: "Kitap") var book: BookEntity
    static var parameterSummary: some ParameterSummary { Summary("\(\.$book) kitabını aç") }
    init() {}
    @MainActor func perform() async throws -> some IntentResult {
        QuickActions.shared.pending = "book/\(book.id.uuidString)"
        return .result()
    }
}

/// Opens the app in one of its modes, or at the book to go on with.
struct StartReadingModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Wise Path'i başlat"
    static let openAppWhenRun = true
    @Parameter(title: "Kip", default: .resume) var mode: ReadingMode
    init() {}
    init(_ m: ReadingMode) { mode = m }
    @MainActor func perform() async throws -> some IntentResult {
        QuickActions.shared.pending = mode.rawValue
        return .result()
    }
}

enum ReadingMode: String, AppEnum {
    case resume, bike, walk, music
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Kip"
    static let caseDisplayRepresentations: [ReadingMode: DisplayRepresentation] = [
        .resume: "Kaldığın yerden dinle", .bike: "Bisiklet", .walk: "Yürüyüş", .music: "Müzik",
    ]
}

struct WisePathShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ToggleReadingIntent(), phrases: ["\(.applicationName) oku", "\(.applicationName) dur", "\(.applicationName) ile okumaya devam et"],
                    shortTitle: "Oku / Durdur", systemImageName: "playpause.fill")
        AppShortcut(intent: MarkSentenceIntent(), phrases: ["\(.applicationName) işaretle", "\(.applicationName) cümleyi işaretle"],
                    shortTitle: "Cümleyi işaretle", systemImageName: "highlighter")
        AppShortcut(intent: VoiceNoteIntent(), phrases: ["\(.applicationName) sesli not", "\(.applicationName) not al"],
                    shortTitle: "Sesli not", systemImageName: "mic.fill")
        AppShortcut(intent: OpenBookIntent(), phrases: ["\(.applicationName) kitap aç", "\(.applicationName) \(\.$book) aç"],
                    shortTitle: "Kitabı aç", systemImageName: "book")
        AppShortcut(intent: StartReadingModeIntent(.bike), phrases: ["\(.applicationName) bisiklet modu"],
                    shortTitle: "Bisiklet modu", systemImageName: "bicycle")
        AppShortcut(intent: StartReadingModeIntent(.walk), phrases: ["\(.applicationName) yürüyüş modu"],
                    shortTitle: "Yürüyüş modu", systemImageName: "figure.walk")
    }
}
