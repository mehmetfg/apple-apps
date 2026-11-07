import SwiftUI

struct LibraryRow: View {
    @Environment(AppServices.self) private var services
    let entry: LibraryEntry
    @State private var rating: IMDbRating?
    @State private var isResolved = false

    var body: some View {
        HStack(spacing: 12) {
            PosterImage(path: entry.posterPath, width: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                RatingBadge(rating: rating, tmdbScore: entry.tmdbScore, isResolved: isResolved)
                if let score = entry.personalScore {
                    Label("Benim puanım \(score)", systemImage: "person.fill")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .task(id: entry.key) {
            if case .found(let found) = await services.ratings.rating(kind: entry.kind, tmdbId: entry.tmdbId) {
                rating = found
            }
            isResolved = true
        }
    }

    private var subtitle: String {
        var parts = [entry.kind.label]
        if let year = entry.releaseYear { parts.append(String(year)) }
        parts.append(contentsOf: entry.genreNames.prefix(2))
        return parts.joined(separator: " · ")
    }
}
