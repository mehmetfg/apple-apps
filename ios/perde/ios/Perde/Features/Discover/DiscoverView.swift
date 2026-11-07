import SwiftData
import SwiftUI

struct DiscoverView: View {
    @Environment(AppServices.self) private var services
    @Query private var entries: [LibraryEntry]
    @State private var model = DiscoverModel()
    @State private var searchText = ""
    @State private var searchResults: [CatalogTitle] = []
    @State private var isShowingFilters = false
    @State private var isShowingSettings = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("TV+")
                .navigationDestination(for: CatalogTitle.self) { TitleDetailView(title: $0) }
                .searchable(text: $searchText, prompt: "Bütün film ve dizilerde ara")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Ayarlar", systemImage: "gearshape") { isShowingSettings = true }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(filterButtonLabel, systemImage: "line.3.horizontal.decrease.circle") {
                            isShowingFilters = true
                        }
                    }
                }
                .sheet(isPresented: $isShowingFilters) {
                    DiscoverFilterSheet(filter: $model.filter, genres: services.genres)
                }
                .sheet(isPresented: $isShowingSettings) {
                    SettingsView()
                }
        }
        .task(id: LoadKey(query: model.filter.query, keyRevision: services.keyRevision)) {
            guard services.hasTMDBKey else { return }
            await model.reload(services: services)
            await model.fillIfNeeded(visibleCount: visibleTitles.count, services: services)
        }
        .task(id: searchText) {
            await runSearch()
        }
    }

    @ViewBuilder
    private var content: some View {
        if !services.hasTMDBKey {
            ContentUnavailableView {
                Label("Anahtarlar gerekli", systemImage: "key")
            } description: {
                Text("Katalog için TMDB, IMDb puanları için OMDb anahtarı gerekiyor. İkisi de ücretsiz.")
            } actions: {
                Button("Ayarları aç") { isShowingSettings = true }
                    .buttonStyle(.borderedProminent)
            }
        } else if !searchText.isEmpty {
            searchList
        } else {
            catalogList
        }
    }

    private var catalogList: some View {
        List {
            Section {
                Picker("Tür", selection: $model.filter.query.kind) {
                    ForEach(MediaKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)
                CategoryChips(selection: $model.filter.query.category)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                Picker("Sıralama", selection: $model.filter.query.sort) {
                    ForEach(DiscoverSort.allCases) { Text($0.label).tag($0) }
                }
            }
            if let issue = model.ratingIssue {
                Section {
                    Label(issue, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            catalogSection
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private var catalogSection: some View {
        switch model.phase {
        case .idle, .loading:
            HStack {
                Spacer()
                ProgressView("TV+ kataloğu yükleniyor")
                Spacer()
            }
            .padding(.vertical, 40)
            .listRowSeparator(.hidden)
        case .failed(let message):
            ContentUnavailableView {
                Label("Katalog yüklenemedi", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Yeniden dene") {
                    Task { await model.reload(services: services) }
                }
            }
            .listRowSeparator(.hidden)
        case .loaded:
            let titles = visibleTitles
            Section {
                ForEach(titles) { title in
                    row(for: title)
                        .onAppear {
                            if title.id == titles.last?.id {
                                Task { await model.loadMore(services: services) }
                            }
                        }
                }
                if model.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
                if titles.isEmpty && !model.isLoadingMore {
                    ContentUnavailableView(
                        "Bu tasnifte içerik yok",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Filtreleri genişletmeyi dene.")
                    )
                }
            } header: {
                Text("\(titles.count) gösteriliyor · TV+'ta toplam \(model.totalResults)")
                    .font(.caption)
            }
        }
    }

    private var searchList: some View {
        List(searchResults) { title in
            row(for: title)
                .task { await model.loadRatings(for: [title], services: services) }
        }
        .listStyle(.plain)
        .overlay {
            if searchResults.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    private func row(for title: CatalogTitle) -> some View {
        let genreNames = services.genres.names(for: title)
        return NavigationLink(value: title) {
            TitleRow(
                title: title,
                genreNames: genreNames,
                rating: model.ratings[title.id],
                isRatingResolved: model.resolvedIds.contains(title.id),
                matchPercent: tasteProfile.matchPercent(genres: genreNames),
                entry: entriesByKey[title.id]
            )
        }
    }

    private var visibleTitles: [CatalogTitle] {
        let profile = tasteProfile
        let genres = services.genres
        let watched = Set(entries.filter(\.isWatched).map(\.key))
        return DiscoverRanker.rank(model.rankerInput(watchedIds: watched) { title in
            profile.matchPercent(genres: genres.names(for: title))
        })
    }

    private var tasteProfile: TasteProfile { TasteProfile(entries: entries) }

    private var entriesByKey: [String: LibraryEntry] {
        Dictionary(entries.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var filterButtonLabel: String {
        let count = model.filter.activeFilterCount
        return count > 0 ? "Filtreler (\(count))" : "Filtreler"
    }

    private func runSearch() async {
        let text = searchText.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else {
            searchResults = []
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        searchResults = (try? await services.tmdb.search(text: text)) ?? []
    }
}

private struct LoadKey: Hashable {
    let query: DiscoverQuery
    let keyRevision: Int
}
