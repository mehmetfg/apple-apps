import SwiftUI

struct TitleRow: View {
    let title: CatalogTitle
    let genreNames: [String]
    let rating: IMDbRating?
    let isRatingResolved: Bool
    let matchPercent: Int?
    let entry: LibraryEntry?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PosterImage(path: title.posterPath)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title.title)
                        .font(.headline)
                        .lineLimit(2)
                    stateIcons
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                RatingBadge(rating: rating, tmdbScore: title.tmdbScore, isResolved: isRatingResolved)
                if let matchPercent {
                    Text("Sana uygunluk %\(matchPercent)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(matchPercent >= 60 ? .green : .secondary)
                }
                if !title.overview.isEmpty {
                    Text(title.overview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts = [title.kind.label]
        if let year = title.releaseYear { parts.append(String(year)) }
        parts.append(contentsOf: genreNames.prefix(3))
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var stateIcons: some View {
        if entry?.isPriority == true {
            Image(systemName: "flag.fill")
                .foregroundStyle(.orange)
                .accessibilityLabel("Öncelikli")
        } else if entry?.isListed == true {
            Image(systemName: "bookmark.fill")
                .foregroundStyle(.tint)
                .accessibilityLabel("Listemde")
        }
        if entry?.isWatched == true {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("İzlendi")
        }
    }
}
