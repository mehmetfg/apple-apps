import SwiftUI

struct ReviewCard: View {
    let review: TitleReview
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(review.author)
                    .font(.subheadline.weight(.semibold))
                if let score = review.authorScore {
                    Label(score.formatted(.number.precision(.fractionLength(0...1))), systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                if let date = review.createdAt {
                    Text(date, format: .dateTime.month(.abbreviated).year())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(review.content)
                .font(.subheadline)
                .lineLimit(isExpanded ? nil : 5)
            Button(isExpanded ? "Daralt" : "Devamını oku") {
                isExpanded.toggle()
            }
            .font(.caption)
        }
    }
}
