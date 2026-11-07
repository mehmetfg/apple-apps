import Foundation

/// Learns which genres the user leans toward from their own library.
struct TasteProfile: Sendable {
    struct Signal: Sendable {
        let genres: [String]
        let weight: Double
    }

    /// Below this many saved titles there is too little to say anything useful.
    static let minimumSignals = 3

    private let weights: [String: Double]
    private let signalCount: Int

    init(signals: [Signal]) {
        var totals: [String: Double] = [:]
        for signal in signals {
            for token in Self.tokens(from: signal.genres) {
                totals[token, default: 0] += signal.weight
            }
        }
        weights = totals
        signalCount = signals.count
    }

    init(entries: [LibraryEntry]) {
        self.init(signals: entries.map { Signal(genres: $0.genreNames, weight: Self.weight(for: $0)) })
    }

    var isReady: Bool { signalCount >= Self.minimumSignals }

    /// 0–100, where 50 is neutral. Nil until the profile has enough signals or the title has no genres.
    func matchPercent(genres: [String]) -> Int? {
        guard isReady else { return nil }
        let tokens = Self.tokens(from: genres)
        let strongest = weights.values.map(abs).max() ?? 0
        guard !tokens.isEmpty, strongest > 0 else { return nil }
        let average = tokens.reduce(0) { $0 + (weights[$1] ?? 0) / strongest } / Double(tokens.count)
        return Int((50 + 50 * average).rounded())
    }

    private static func weight(for entry: LibraryEntry) -> Double {
        if let score = entry.personalScore {
            if score >= 8 { return 3 }
            if score >= 6 { return 1 }
            return -2
        }
        if entry.isPriority { return 2 }
        return 1
    }

    /// Film and series genre lists differ ("Aksiyon" and "Aksiyon & Macera"), so compound names are split.
    private static func tokens(from genres: [String]) -> Set<String> {
        var result = Set<String>()
        for genre in genres {
            for part in genre.split(separator: "&") {
                let token = part.trimmingCharacters(in: .whitespaces).lowercased()
                if !token.isEmpty { result.insert(token) }
            }
        }
        return result
    }
}
