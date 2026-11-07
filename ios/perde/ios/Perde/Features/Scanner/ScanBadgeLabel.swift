import SwiftUI

struct ScanBadgeLabel: View {
    let badge: ScanBadge

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text("IMDb")
                    .font(.caption2.weight(.heavy))
                if let rating = badge.rating {
                    Text(rating.score, format: .number.precision(.fractionLength(1)))
                        .font(.headline.weight(.bold))
                } else if badge.isRatingResolved {
                    Text("yok")
                        .font(.subheadline)
                } else {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            Text(badge.title.title)
                .font(.caption2)
                .lineLimit(1)
                .frame(maxWidth: 160, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.yellow, in: .rect(cornerRadius: 8))
        .foregroundStyle(.black)
        .shadow(radius: 3)
    }
}
