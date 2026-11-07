import CoreGraphics
import Testing
@testable import Perde

struct ScanTextFilterTests {
    private func text(_ value: String, y: CGFloat, height: CGFloat = 30) -> ScannedText {
        ScannedText(id: value, text: value, frame: CGRect(x: 20, y: y, width: 200, height: height))
    }

    @Test func dropsInterfaceWordsNumbersAndSentences() {
        #expect(!ScanTextFilter.isPlausibleTitle("Fragmanı İzle"))
        #expect(!ScanTextFilter.isPlausibleTitle("Ana Sayfa"))
        #expect(!ScanTextFilter.isPlausibleTitle("2024"))
        #expect(!ScanTextFilter.isPlausibleTitle("16+"))
        #expect(!ScanTextFilter.isPlausibleTitle("Genç bir adam babasının ölümünden sonra köyüne dönerek eski bir sırrı öğrenir"))
    }

    @Test func keepsRealTitles() {
        #expect(ScanTextFilter.isPlausibleTitle("Kış Uykusu"))
        #expect(ScanTextFilter.isPlausibleTitle("Se7en"))
        #expect(ScanTextFilter.isPlausibleTitle("Blade Runner 2049"))
    }

    @Test func joinsATitleWrappedOverTwoLines() {
        let queries = ScanTextFilter.candidates(from: [text("THE LAST", y: 100), text("OF US", y: 134)]).map(\.query)
        #expect(queries.contains("THE LAST OF US"))
    }

    @Test func doesNotJoinDistantLines() {
        let queries = ScanTextFilter.candidates(from: [text("Dune", y: 100), text("Arrival", y: 400)]).map(\.query)
        #expect(!queries.contains("Dune Arrival"))
    }

    @Test func mergedCandidateCoversBothLines() {
        let candidates = ScanTextFilter.candidates(from: [text("THE LAST", y: 100), text("OF US", y: 134)])
        let merged = candidates.first { $0.query == "THE LAST OF US" }
        #expect(merged?.frame.minY == 100)
        #expect(merged?.frame.maxY == 164)
    }
}
