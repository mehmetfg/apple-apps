import SwiftUI

/// Titles found so far, so one that has left the frame can still be opened.
struct ScanTray: View {
    let titles: [CatalogTitle]
    let ratings: [String: IMDbRating]
    let onSelect: (CatalogTitle) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(titles) { title in
                    Button {
                        onSelect(title)
                    } label: {
                        HStack(spacing: 8) {
                            PosterImage(path: title.posterPath, width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title.title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Text(scoreText(for: title))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: 130, alignment: .leading)
                        }
                        .padding(6)
                        .background(.regularMaterial, in: .rect(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
        }
        .scrollIndicators(.hidden)
    }

    private func scoreText(for title: CatalogTitle) -> String {
        guard let rating = ratings[title.id] else { return "IMDb —" }
        return "IMDb \(rating.score.formatted(.number.precision(.fractionLength(1))))"
    }
}
