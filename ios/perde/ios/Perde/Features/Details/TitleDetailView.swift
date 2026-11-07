import SwiftData
import SwiftUI

struct TitleDetailView: View {
    let title: CatalogTitle

    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Query private var matchingEntries: [LibraryEntry]
    @State private var model = TitleDetailModel()

    init(title: CatalogTitle) {
        self.title = title
        let key = title.id
        _matchingEntries = Query(filter: #Predicate<LibraryEntry> { $0.key == key })
    }

    private var entry: LibraryEntry? { matchingEntries.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                actionButtons
                if let entry, entry.isWatched {
                    PersonalScorePicker(entry: entry)
                }
                if let message = model.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                overviewSection
                availabilitySection
                tagsSection
                reviewsSection
            }
            .padding()
        }
        .navigationTitle(title.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load(title: title, services: services) }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            PosterImage(path: title.posterPath, width: 120)
            VStack(alignment: .leading, spacing: 8) {
                Text(title.title)
                    .font(.title2.bold())
                if title.originalTitle != title.title {
                    Text(title.originalTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(factsLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                RatingBadge(rating: model.rating, tmdbScore: title.tmdbScore, isResolved: model.isRatingResolved)
                criticScores
            }
        }
    }

    @ViewBuilder
    private var criticScores: some View {
        if let rating = model.rating {
            VStack(alignment: .leading, spacing: 2) {
                if let tomatoes = rating.rottenTomatoes {
                    Text("Rotten Tomatoes \(tomatoes)")
                }
                if let metascore = rating.metascore {
                    Text("Metacritic \(metascore)")
                }
                if let awards = rating.awards {
                    Text(awards)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            actionButton(
                entry?.isListed == true ? "Listemde" : "Listeme ekle",
                systemImage: entry?.isListed == true ? "bookmark.fill" : "bookmark",
                isActive: entry?.isListed == true
            ) {
                actions.toggleListed(title: title, entry: entry)
            }
            actionButton(
                "Öncelikli",
                systemImage: entry?.isPriority == true ? "flag.fill" : "flag",
                isActive: entry?.isPriority == true
            ) {
                actions.togglePriority(title: title, entry: entry)
            }
            actionButton(
                "İzledim",
                systemImage: entry?.isWatched == true ? "checkmark.circle.fill" : "checkmark.circle",
                isActive: entry?.isWatched == true
            ) {
                actions.toggleWatched(title: title, entry: entry)
            }
        }
    }

    private func actionButton(
        _ label: String,
        systemImage: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(label)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .tint(isActive ? .accentColor : .secondary)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    @ViewBuilder
    private var overviewSection: some View {
        if let tagline = model.details?.tagline {
            Text(tagline)
                .font(.callout.italic())
                .foregroundStyle(.secondary)
        }
        let overview = model.details?.overview ?? title.overview
        if !overview.isEmpty {
            DetailSection(title: "Konu") {
                Text(overview)
            }
        }
    }

    @ViewBuilder
    private var availabilitySection: some View {
        if let details = model.details {
            DetailSection(title: "Türkiye'de nerede") {
                VStack(alignment: .leading, spacing: 4) {
                    if details.streamingProviders.isEmpty && details.rentalProviders.isEmpty {
                        Text("Platform bilgisi yok")
                            .foregroundStyle(.secondary)
                    }
                    if !details.streamingProviders.isEmpty {
                        Text("Abonelikle: \(details.streamingProviders.joined(separator: ", "))")
                    }
                    if !details.rentalProviders.isEmpty {
                        Text("Kirala veya satın al: \(details.rentalProviders.joined(separator: ", "))")
                    }
                }
                .font(.subheadline)
            }
        }
    }

    @ViewBuilder
    private var tagsSection: some View {
        if let details = model.details {
            if !details.genreNames.isEmpty {
                DetailSection(title: "Tür") { Text(details.genreNames.joined(separator: " · ")) }
            }
            if !details.keywords.isEmpty {
                DetailSection(title: "Temalar") {
                    Text(details.keywords.prefix(12).joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if !details.cast.isEmpty {
                DetailSection(title: "Oyuncular") {
                    Text(details.cast.joined(separator: ", "))
                        .font(.subheadline)
                }
            }
        }
    }

    @ViewBuilder
    private var reviewsSection: some View {
        if let reviews = model.details?.reviews {
            DetailSection(title: "Yorumlar") {
                if reviews.isEmpty {
                    Text("Bu yapım için henüz yorum yok.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(reviews.prefix(8)) { ReviewCard(review: $0) }
                    }
                }
            }
        }
    }

    private var factsLine: String {
        var parts = [title.kind.label]
        if let year = title.releaseYear { parts.append(String(year)) }
        if let minutes = model.details?.runtimeMinutes { parts.append("\(minutes) dk") }
        if let seasons = model.details?.seasonCount { parts.append("\(seasons) sezon") }
        return parts.joined(separator: " · ")
    }

    private var actions: LibraryActions {
        LibraryActions(
            context: modelContext,
            genreNames: model.details?.genreNames ?? services.genres.names(for: title)
        )
    }
}
