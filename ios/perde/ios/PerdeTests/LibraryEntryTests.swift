import Testing
@testable import Perde

@MainActor
struct LibraryEntryTests {
    private func makeEntry() -> LibraryEntry {
        LibraryEntry(
            title: CatalogTitle(
                kind: .tv,
                tmdbId: 7,
                title: "Örnek",
                originalTitle: "Sample",
                overview: "",
                posterPath: nil,
                releaseYear: 2021,
                genreIds: [18],
                originalLanguage: "tr",
                tmdbScore: 7,
                tmdbVotes: 100,
                popularity: 1
            ),
            genreNames: ["Dram"]
        )
    }

    @Test func priorityAlsoPutsTitleOnTheList() {
        let entry = makeEntry()
        entry.setPriority(true, rank: 3)
        #expect(entry.isListed)
        #expect(entry.isPriority)
        #expect(entry.priorityRank == 3)
    }

    @Test func removingPriorityKeepsTitleOnTheList() {
        let entry = makeEntry()
        entry.setPriority(true, rank: 1)
        entry.setPriority(false, rank: 1)
        #expect(entry.isListed)
        #expect(!entry.isPriority)
    }

    @Test func removingFromListAlsoRemovesPriority() {
        let entry = makeEntry()
        entry.setPriority(true, rank: 1)
        entry.setListed(false)
        #expect(!entry.isPriority)
        #expect(entry.isEmpty)
    }

    @Test func watchingTakesTitleOffBothLists() {
        let entry = makeEntry()
        entry.setPriority(true, rank: 1)
        entry.markWatched()
        #expect(entry.isWatched)
        #expect(!entry.isListed)
        #expect(!entry.isPriority)
        #expect(!entry.isEmpty)
    }

    @Test func unwatchingClearsPersonalScore() {
        let entry = makeEntry()
        entry.markWatched()
        entry.personalScore = 9
        entry.markUnwatched()
        #expect(entry.personalScore == nil)
        #expect(entry.isEmpty)
    }
}
