import Foundation

/// A streaming service, found by name in the provider list because provider ids are TMDB's own.
/// Adding a platform later means adding one value to `all` and a platform picker in Discover.
struct StreamingPlatform: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let region: String
    private let matchingNames: Set<String>
    private let matchingFragments: [String]

    init(id: String, displayName: String, region: String, matchingNames: Set<String>, matchingFragments: [String]) {
        self.id = id
        self.displayName = displayName
        self.region = region
        self.matchingNames = matchingNames
        self.matchingFragments = matchingFragments
    }

    func matches(providerName: String) -> Bool {
        let name = providerName.lowercased().trimmingCharacters(in: .whitespaces)
        return matchingNames.contains(name) || matchingFragments.contains { name.contains($0) }
    }

    static let turkcellTVPlus = StreamingPlatform(
        id: "turkcell-tv-plus",
        displayName: "TV+",
        region: "TR",
        matchingNames: ["tv+", "tv plus", "tvplus"],
        matchingFragments: ["turkcell"]
    )

    static let all: [StreamingPlatform] = [.turkcellTVPlus]
}
