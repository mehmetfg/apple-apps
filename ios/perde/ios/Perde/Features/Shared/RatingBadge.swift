import SwiftUI

/// Shows the IMDb score. A TMDB score is shown only when IMDb has none, and is always labelled as TMDB.
struct RatingBadge: View {
    let rating: IMDbRating?
    let tmdbScore: Double
    let isResolved: Bool

    var body: some View {
        HStack(spacing: 6) {
            if let rating {
                Text("IMDb")
                    .font(.caption2.weight(.heavy))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.yellow, in: .rect(cornerRadius: 3))
                    .foregroundStyle(.black)
                Text(rating.score, format: .number.precision(.fractionLength(1)))
                    .font(.subheadline.weight(.bold))
                Text(VoteCountFormatter.text(rating.votes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !isResolved {
                ProgressView()
                    .controlSize(.mini)
                Text("IMDb aranıyor")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if tmdbScore > 0 {
                Text("IMDb puanı yok · TMDB \(tmdbScore.formatted(.number.precision(.fractionLength(1))))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Puan yok")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
