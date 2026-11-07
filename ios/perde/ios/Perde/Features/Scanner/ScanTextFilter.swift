import CoreGraphics
import Foundation

/// Turns raw camera text into title candidates: drops interface words and joins titles split across lines.
enum ScanTextFilter {
    private static let interfaceWords: Set<String> = [
        "izle", "izlemeye devam et", "devam et", "fragman", "fragmani izle", "yeni", "yeni eklenenler",
        "filmler", "film", "diziler", "dizi", "kategoriler", "ana sayfa", "anasayfa", "listem", "listeme ekle",
        "populer", "en cok izlenenler", "sana ozel", "arama", "ara", "ayarlar", "profil", "sezon", "bolum",
        "tumu", "tumunu gor", "canli tv", "kirala", "satin al", "ucretsiz", "abone ol", "hemen izle",
        "my list", "home", "movies", "series", "search", "play", "watch now", "trailer", "new", "trending",
        "continue watching", "top 10", "tv", "tv+",
    ]

    private static let maximumLength = 60
    private static let minimumLength = 2

    static func candidates(from items: [ScannedText]) -> [ScanCandidate] {
        var result: [ScanCandidate] = []
        var seenQueries = Set<String>()

        func add(_ text: String, frame: CGRect) {
            guard isPlausibleTitle(text) else { return }
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard seenQueries.insert(TitleMatcher.normalize(cleaned)).inserted else { return }
            result.append(ScanCandidate(query: cleaned, frame: frame))
        }

        for item in items {
            add(item.text.replacingOccurrences(of: "\n", with: " "), frame: item.frame)
        }
        for (upper, lower) in stackedPairs(in: items) {
            add("\(upper.text) \(lower.text)", frame: upper.frame.union(lower.frame))
        }
        return result
    }

    static func isPlausibleTitle(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (minimumLength...maximumLength).contains(cleaned.count) else { return false }
        let normalized = TitleMatcher.normalize(cleaned)
        guard normalized.count >= minimumLength, !interfaceWords.contains(normalized) else { return false }
        // Durations, years and counters such as "1 s 52 dk", "2024" or "16+" are not titles.
        let letters = cleaned.unicodeScalars.filter(CharacterSet.letters.contains).count
        guard letters >= 2, Double(letters) / Double(cleaned.count) >= 0.5 else { return false }
        // Sentences are descriptions, not titles.
        return cleaned.split(separator: " ").count <= 8
    }

    /// Poster titles often wrap, so lines of similar size stacked closely are tried together as well.
    private static func stackedPairs(in items: [ScannedText]) -> [(ScannedText, ScannedText)] {
        let sorted = items.sorted { $0.frame.minY < $1.frame.minY }
        var pairs: [(ScannedText, ScannedText)] = []
        for (index, upper) in sorted.enumerated() {
            for lower in sorted[(index + 1)...] {
                let gap = lower.frame.minY - upper.frame.maxY
                if gap > upper.frame.height { break }
                let isSimilarSize = abs(upper.frame.height - lower.frame.height) < upper.frame.height * 0.5
                let overlapsHorizontally = upper.frame.intersection(
                    CGRect(x: lower.frame.minX, y: upper.frame.minY, width: lower.frame.width, height: upper.frame.height)
                ).width > min(upper.frame.width, lower.frame.width) * 0.5
                if gap >= -upper.frame.height * 0.3 && isSimilarSize && overlapsHorizontally {
                    pairs.append((upper, lower))
                }
            }
        }
        return pairs
    }
}
