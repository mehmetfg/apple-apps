import Foundation
import SwiftData

/// Creates, changes and removes library entries, so screens share one set of rules.
@MainActor
struct LibraryActions {
    let context: ModelContext
    let genreNames: [String]

    func toggleListed(title: CatalogTitle, entry: LibraryEntry?) {
        let target = entry ?? insert(title)
        target.setListed(!target.isListed)
        removeIfEmpty(target)
    }

    func togglePriority(title: CatalogTitle, entry: LibraryEntry?) {
        let target = entry ?? insert(title)
        target.setPriority(!target.isPriority, rank: nextPriorityRank())
        removeIfEmpty(target)
    }

    func toggleWatched(title: CatalogTitle, entry: LibraryEntry?) {
        let target = entry ?? insert(title)
        if target.isWatched {
            target.markUnwatched()
        } else {
            target.markWatched()
        }
        removeIfEmpty(target)
    }

    private func insert(_ title: CatalogTitle) -> LibraryEntry {
        let entry = LibraryEntry(title: title, genreNames: genreNames)
        context.insert(entry)
        return entry
    }

    private func removeIfEmpty(_ entry: LibraryEntry) {
        if entry.isEmpty { context.delete(entry) }
    }

    /// New priorities go to the end of the queue.
    private func nextPriorityRank() -> Int {
        let descriptor = FetchDescriptor<LibraryEntry>(predicate: #Predicate { $0.isPriority })
        let ranks = (try? context.fetch(descriptor))?.map(\.priorityRank) ?? []
        return (ranks.max() ?? 0) + 1
    }
}
