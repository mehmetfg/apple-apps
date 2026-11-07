import Foundation
import Testing
@testable import Perde

struct TasteAndParsingTests {
    @Test func tasteStaysSilentUntilThereIsEnoughData() {
        let profile = TasteProfile(signals: [.init(genres: ["Dram"], weight: 3)])
        #expect(profile.matchPercent(genres: ["Dram"]) == nil)
    }

    @Test func tasteFavoursLikedGenresAndTreatsCompoundNamesAsOne() {
        let profile = TasteProfile(signals: [
            .init(genres: ["Aksiyon & Macera"], weight: 3),
            .init(genres: ["Aksiyon"], weight: 3),
            .init(genres: ["Korku"], weight: -2),
        ])
        let action = profile.matchPercent(genres: ["Aksiyon"])
        let horror = profile.matchPercent(genres: ["Korku"])
        #expect(action == 100)
        #expect((horror ?? 100) < 50)
    }

    @Test func parsesOMDbResponse() throws {
        let json = """
        {"Response":"True","imdbRating":"8.7","imdbVotes":"1,234,567","Metascore":"74",
         "Awards":"Won 3 Oscars","Ratings":[{"Source":"Rotten Tomatoes","Value":"93%"}]}
        """
        let rating = try OMDbClient.parse(data: Data(json.utf8), imdbId: "tt1")
        #expect(rating?.score == 8.7)
        #expect(rating?.votes == 1_234_567)
        #expect(rating?.metascore == 74)
        #expect(rating?.rottenTomatoes == "93%")
    }

    @Test func missingOMDbValuesMeanNoRating() throws {
        let json = #"{"Response":"True","imdbRating":"N/A","imdbVotes":"N/A","Metascore":"N/A"}"#
        #expect(try OMDbClient.parse(data: Data(json.utf8), imdbId: "tt1") == nil)
    }

    @Test func recognisesOMDbQuotaAndKeyErrors() {
        let quota = #"{"Response":"False","Error":"Request limit reached!"}"#
        #expect(throws: APIError.quotaReached(service: "OMDb")) {
            try OMDbClient.parse(data: Data(quota.utf8), imdbId: "tt1")
        }
        let key = #"{"Response":"False","Error":"Invalid API key!"}"#
        #expect(throws: APIError.invalidKey(service: "OMDb")) {
            try OMDbClient.parse(data: Data(key.utf8), imdbId: "tt1")
        }
    }

    @Test func findsTurkcellTVPlusButNotAppleTVPlus() {
        let platform = StreamingPlatform.turkcellTVPlus
        #expect(platform.matches(providerName: "TV+"))
        #expect(platform.matches(providerName: "Turkcell TV Plus"))
        #expect(!platform.matches(providerName: "Apple TV+"))
        #expect(!platform.matches(providerName: "Apple TV"))
    }
}
