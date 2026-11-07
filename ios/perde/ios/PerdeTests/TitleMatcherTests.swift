import Testing
@testable import Perde

struct TitleMatcherTests {
    private func title(_ name: String, original: String? = nil, votes: Int = 1_000) -> CatalogTitle {
        CatalogTitle(
            kind: .movie,
            tmdbId: abs(name.hashValue),
            title: name,
            originalTitle: original ?? name,
            overview: "",
            posterPath: nil,
            releaseYear: 2020,
            genreIds: [],
            originalLanguage: nil,
            tmdbScore: 7,
            tmdbVotes: votes,
            popularity: 1
        )
    }

    @Test func foldsTurkishLettersAndPunctuation() {
        #expect(TitleMatcher.normalize("  KIŞ UYKUSU: İlk Bölüm! ") == "kis uykusu ilk bolum")
    }

    @Test func matchesExactTitleCaseInsensitively() {
        let match = TitleMatcher.bestMatch(for: "KIŞ UYKUSU", in: [title("Kış Uykusu"), title("Yaz Gülü")])
        #expect(match?.title.title == "Kış Uykusu")
        #expect(match?.confidence == 1)
    }

    @Test func toleratesSmallCameraReadingErrors() {
        let match = TitleMatcher.bestMatch(for: "The Godfathcr", in: [title("The Godfather")])
        #expect(match?.title.title == "The Godfather")
    }

    @Test func matchesOriginalTitle() {
        let match = TitleMatcher.bestMatch(for: "The Godfather", in: [title("Baba", original: "The Godfather")])
        #expect(match?.title.title == "Baba")
    }

    @Test func rejectsTextThatOnlyResemblesATitle() {
        #expect(TitleMatcher.bestMatch(for: "The Father", in: [title("The Godfather")]) == nil)
    }

    @Test func shortWordsNeedAnExactWellKnownTitle() {
        #expect(TitleMatcher.bestMatch(for: "Aile", in: [title("Aile", votes: 3)]) == nil)
        #expect(TitleMatcher.bestMatch(for: "Aile", in: [title("Aile", votes: 300)]) != nil)
    }

    @Test func prefersTheBetterKnownTitleWhenTied() {
        let match = TitleMatcher.bestMatch(for: "Dune", in: [title("Dune", votes: 100), title("Dune", votes: 9_000)])
        #expect(match?.title.tmdbVotes == 9_000)
    }
}
