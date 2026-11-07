import Foundation

/// Decides whether text read from the camera really is a title from the search results.
/// It is strict on purpose: showing no score is better than showing the wrong film's score.
enum TitleMatcher {
    struct Match: Sendable {
        let title: CatalogTitle
        let confidence: Double
    }

    private static let minimumConfidence = 0.86
    private static let shortTitleLength = 5
    private static let shortTitleMinimumVotes = 50

    static func bestMatch(for query: String, in titles: [CatalogTitle]) -> Match? {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return nil }

        let scored = titles.compactMap { title -> Match? in
            let confidence = max(
                similarity(normalizedQuery, normalize(title.title)),
                similarity(normalizedQuery, normalize(title.originalTitle))
            )
            guard confidence >= minimumConfidence else { return nil }
            // A short word such as "Aile" matches countless obscure titles, so it must be exact and well known.
            if normalizedQuery.count < shortTitleLength,
               confidence < 1 || title.tmdbVotes < shortTitleMinimumVotes {
                return nil
            }
            return Match(title: title, confidence: confidence)
        }
        return scored.max { first, second in
            if first.confidence != second.confidence { return first.confidence < second.confidence }
            return first.title.tmdbVotes < second.title.tmdbVotes
        }
    }

    /// Lowercases, folds Turkish letters and accents, and keeps only letters, digits and single spaces.
    static func normalize(_ text: String) -> String {
        let folded = text
            .replacingOccurrences(of: "İ", with: "i")
            .replacingOccurrences(of: "I", with: "i")
            .replacingOccurrences(of: "ı", with: "i")
            .lowercased()
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let kept = folded.map { character -> Character in
            character.isLetter || character.isNumber ? character : " "
        }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    /// 1 for identical text, falling to 0 as more edits are needed.
    static func similarity(_ first: String, _ second: String) -> Double {
        if first == second { return first.isEmpty ? 0 : 1 }
        let longest = max(first.count, second.count)
        guard longest > 0 else { return 0 }
        return 1 - Double(editDistance(Array(first), Array(second))) / Double(longest)
    }

    private static func editDistance(_ first: [Character], _ second: [Character]) -> Int {
        guard !first.isEmpty else { return second.count }
        guard !second.isEmpty else { return first.count }
        var previous = Array(0...second.count)
        var current = [Int](repeating: 0, count: second.count + 1)
        for (row, firstCharacter) in first.enumerated() {
            current[0] = row + 1
            for (column, secondCharacter) in second.enumerated() {
                let cost = firstCharacter == secondCharacter ? 0 : 1
                current[column + 1] = min(previous[column + 1] + 1, current[column] + 1, previous[column] + cost)
            }
            swap(&previous, &current)
        }
        return previous[second.count]
    }
}
