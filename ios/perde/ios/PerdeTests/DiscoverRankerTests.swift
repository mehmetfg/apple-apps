import Testing
@testable import Perde

struct DiscoverRankerTests {
    private func title(_ id: Int, language: String = "en", popularity: Double = 1, year: Int = 2020) -> CatalogTitle {
        CatalogTitle(
            kind: .movie,
            tmdbId: id,
            title: "Title \(id)",
            originalTitle: "Title \(id)",
            overview: "",
            posterPath: nil,
            releaseYear: year,
            genreIds: [],
            originalLanguage: language,
            tmdbScore: 7,
            tmdbVotes: 100,
            popularity: popularity
        )
    }

    private func rating(_ score: Double, votes: Int) -> IMDbRating {
        IMDbRating(imdbId: "tt1", score: score, votes: votes, metascore: nil, rottenTomatoes: nil, awards: nil)
    }

    private func rank(
        _ titles: [CatalogTitle],
        ratings: [String: IMDbRating] = [:],
        watched: Set<String> = [],
        configure: (inout DiscoverFilter) -> Void = { _ in },
        match: @escaping (CatalogTitle) -> Int? = { _ in nil }
    ) -> [Int] {
        var filter = DiscoverFilter()
        configure(&filter)
        return DiscoverRanker.rank(.init(
            titles: titles,
            ratings: ratings,
            watchedIds: watched,
            filter: filter,
            matchPercent: match
        )).map(\.tmdbId)
    }

    @Test func imdbOrderDoesNotReward9WithAHandfulOfVotes() {
        let obscure = title(1)
        let classic = title(2)
        let order = rank(
            [obscure, classic],
            ratings: [obscure.id: rating(9.4, votes: 150), classic.id: rating(8.5, votes: 500_000)]
        ) { $0.query.sort = .imdb }
        #expect(order == [2, 1])
    }

    @Test func minimumScoreAndVotesBothApply() {
        let good = title(1)
        let fewVotes = title(2)
        let lowScore = title(3)
        let unrated = title(4)
        let order = rank(
            [good, fewVotes, lowScore, unrated],
            ratings: [
                good.id: rating(8.1, votes: 20_000),
                fewVotes.id: rating(9.0, votes: 300),
                lowScore.id: rating(6.0, votes: 90_000),
            ]
        ) {
            $0.minimumIMDbScore = 7.5
            $0.minimumIMDbVotes = 1_000
        }
        #expect(order == [1])
    }

    @Test func hidesWatchedUnlessAskedToShow() {
        let watched = title(1)
        let unseen = title(2)
        #expect(rank([watched, unseen], watched: [watched.id]) == [2])
        #expect(rank([watched, unseen], watched: [watched.id]) { $0.hidesWatched = false }.count == 2)
    }

    @Test func foreignOriginDropsTurkishTitles() {
        let order = rank([title(1, language: "tr"), title(2, language: "en")]) { $0.query.origin = .foreign }
        #expect(order == [2])
    }

    @Test func personalMatchOutranksScore() {
        let liked = title(1)
        let acclaimed = title(2)
        let order = rank(
            [acclaimed, liked],
            ratings: [acclaimed.id: rating(9.0, votes: 900_000), liked.id: rating(7.0, votes: 20_000)],
            configure: { $0.query.sort = .personalMatch },
            match: { $0.tmdbId == 1 ? 90 : 30 }
        )
        #expect(order == [1, 2])
    }

    @Test func categoryParametersDifferBetweenFilmsAndSeries() {
        var query = DiscoverFilter().query
        query.category = .action
        #expect(query.parameters["with_genres"] == "28|12")
        query.kind = .tv
        #expect(query.parameters["with_genres"] == "10759")
    }
}
