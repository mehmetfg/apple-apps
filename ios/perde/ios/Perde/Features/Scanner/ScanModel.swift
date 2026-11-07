import Foundation
import Observation

/// Connects camera text to titles and ratings. Every lookup is remembered, so holding the
/// camera still costs no further requests.
@MainActor
@Observable
final class ScanModel {
    private static let maximumConcurrentLookups = 2
    private static let trayLimit = 20

    private(set) var badges: [ScanBadge] = []
    /// Titles found since the scanner opened, newest first.
    private(set) var foundTitles: [CatalogTitle] = []
    private(set) var ratings: [String: IMDbRating] = [:]
    private(set) var resolvedRatingIds: Set<String> = []
    private(set) var issue: String?

    @ObservationIgnored private var services: AppServices?
    @ObservationIgnored private var currentCandidates: [ScanCandidate] = []
    /// Normalized query → match. A nil value means it was checked and nothing matched.
    @ObservationIgnored private var lookups: [String: TitleMatcher.Match?] = [:]
    @ObservationIgnored private var pendingQueries: [String] = []
    @ObservationIgnored private var activeLookupCount = 0

    func attach(services: AppServices) {
        self.services = services
    }

    func receive(items: [ScannedText]) {
        currentCandidates = ScanTextFilter.candidates(from: items)
        for candidate in currentCandidates {
            let key = TitleMatcher.normalize(candidate.query)
            if lookups[key] == nil, !pendingQueries.contains(candidate.query) {
                pendingQueries.append(candidate.query)
            }
        }
        // Only what is on screen right now matters; text the camera has moved away from is dropped.
        let visible = Set(currentCandidates.map(\.query))
        pendingQueries.removeAll { !visible.contains($0) }
        startLookups()
        rebuildBadges()
    }

    private func startLookups() {
        while activeLookupCount < Self.maximumConcurrentLookups, !pendingQueries.isEmpty {
            let query = pendingQueries.removeFirst()
            activeLookupCount += 1
            Task { await lookUp(query) }
        }
    }

    private func lookUp(_ query: String) async {
        defer {
            activeLookupCount -= 1
            startLookups()
        }
        guard let services else { return }
        let key = TitleMatcher.normalize(query)
        do {
            let results = try await services.tmdb.search(text: query)
            let match = TitleMatcher.bestMatch(for: query, in: results)
            lookups[key] = .some(match)
            issue = nil
            if let match { await register(match.title, services: services) }
            rebuildBadges()
        } catch let error as APIError {
            issue = error.localizedDescription
        } catch {
            issue = error.localizedDescription
        }
    }

    private func register(_ title: CatalogTitle, services: AppServices) async {
        foundTitles.removeAll { $0.id == title.id }
        foundTitles.insert(title, at: 0)
        if foundTitles.count > Self.trayLimit { foundTitles.removeLast() }
        guard !resolvedRatingIds.contains(title.id) else { return }

        let outcome = await services.ratings.rating(kind: title.kind, tmdbId: title.tmdbId)
        resolvedRatingIds.insert(title.id)
        switch outcome {
        case .found(let rating): ratings[title.id] = rating
        case .unavailable: break
        case .failed(let error): issue = error.localizedDescription
        }
    }

    private func rebuildBadges() {
        var strongest: [String: (match: TitleMatcher.Match, frame: CGRect)] = [:]
        for candidate in currentCandidates {
            guard let stored = lookups[TitleMatcher.normalize(candidate.query)], let match = stored else { continue }
            if let existing = strongest[match.title.id], existing.match.confidence >= match.confidence { continue }
            strongest[match.title.id] = (match, candidate.frame)
        }
        badges = strongest.values.map { entry in
            ScanBadge(
                title: entry.match.title,
                frame: entry.frame,
                rating: ratings[entry.match.title.id],
                isRatingResolved: resolvedRatingIds.contains(entry.match.title.id)
            )
        }
    }
}
