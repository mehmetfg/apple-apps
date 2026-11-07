// The system surface of Teoria (2026-11-06): the books and your notes in Spotlight, and a book as a Siri parameter.
import AppIntents
import Foundation
import PDMBus

@MainActor
enum TeoriaSpotlight {
    static func refresh() {
        let books = LibraryStore.shared.index.books
        let notes = NotesStore.shared.notes
        Task.detached(priority: .utility) {
            let bookItems = books.map { b in
                let parts = b.titleParts
                return PDMSpotlight.Item(id: "kitap:\(b.id)", title: parts.title, detail: parts.author)
            }
            let noteItems = notes.compactMap { n -> PDMSpotlight.Item? in
                let text = n.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty, !n.book.isEmpty else { return nil }
                return PDMSpotlight.Item(id: "kitap:\(n.book)|not:\(n.id)", title: text, detail: n.bookTitle)
            }
            await PDMSpotlight.sync(bookItems, scope: "books")
            await PDMSpotlight.sync(noteItems, scope: "notes")
        }
    }
}

struct TeoriaBookEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Kitap"
    static let defaultQuery = TeoriaBookQuery()
    var id: String
    var title: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct TeoriaBookQuery: EntityStringQuery {
    @MainActor private func all() -> [TeoriaBookEntity] {
        LibraryStore.shared.index.books.sorted { $0.lastDate > $1.lastDate }
            .map { TeoriaBookEntity(id: $0.id, title: $0.titleParts.title) }
    }
    func entities(for identifiers: [String]) async throws -> [TeoriaBookEntity] {
        await all().filter { identifiers.contains($0.id) }
    }
    func entities(matching string: String) async throws -> [TeoriaBookEntity] {
        await all().filter { $0.title.localizedCaseInsensitiveContains(string) }
    }
    func suggestedEntities() async throws -> [TeoriaBookEntity] { Array(await all().prefix(20)) }
}

struct OpenTeoriaBookIntent: AppIntent {
    static let title: LocalizedStringResource = "Teoria'da kitabı aç"
    static let openAppWhenRun = true
    @Parameter(title: "Kitap") var book: TeoriaBookEntity
    static var parameterSummary: some ParameterSummary { Summary("\(\.$book) kitabını aç") }
    init() {}
    func perform() async throws -> some IntentResult {
        Paylasim.ayar.set("kitap:\(book.id)", forKey: "w.ac")
        return .result()
    }
}
