import SwiftUI

struct DiscoverFilterSheet: View {
    @Binding var filter: DiscoverFilter
    let genres: GenreCatalog
    @Environment(\.dismiss) private var dismiss

    private static let yearOptions = [2024, 2020, 2015, 2010, 2000]
    private static let voteOptions = [1_000, 10_000, 50_000, 100_000]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("En az puan", selection: $filter.minimumIMDbScore) {
                        Text("Sınır yok").tag(0.0)
                        ForEach([6.0, 6.5, 7.0, 7.5, 8.0, 8.5], id: \.self) { score in
                            Text(score, format: .number.precision(.fractionLength(1))).tag(score)
                        }
                    }
                    Picker("En az oy", selection: $filter.minimumIMDbVotes) {
                        ForEach(Self.voteOptions, id: \.self) { votes in
                            Text(VoteCountFormatter.text(votes)).tag(votes)
                        }
                    }
                    .disabled(filter.minimumIMDbScore == 0)
                } header: {
                    Text("IMDb")
                } footer: {
                    Text("Az oyla alınmış yüksek puanları eler. Sınır seçilince IMDb puanı olmayan yapımlar gizlenir.")
                }

                Section("Yapım") {
                    Picker("Köken", selection: $filter.query.origin) {
                        ForEach(TitleOrigin.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Çıkış yılı", selection: $filter.query.minimumYear) {
                        Text("Hepsi").tag(Int?.none)
                        ForEach(Self.yearOptions, id: \.self) { year in
                            Text("\(String(year)) ve sonrası").tag(Int?.some(year))
                        }
                    }
                    Toggle("İzlediklerimi gizle", isOn: $filter.hidesWatched)
                }

                Section {
                    ForEach(genres.sortedGenres(for: filter.query.kind), id: \.id) { genre in
                        Toggle(genre.name, isOn: genreBinding(genre.id))
                    }
                } header: {
                    Text("Tür")
                } footer: {
                    Text("Birden çok tür seçersen yalnız hepsini taşıyan yapımlar gelir.")
                }
            }
            .navigationTitle("Filtreler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Sıfırla") {
                        let kind = filter.query.kind
                        filter = DiscoverFilter()
                        filter.query.kind = kind
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") { dismiss() }
                }
            }
            .onChange(of: filter.query.kind) {
                filter.query.genreIds = []
            }
        }
    }

    private func genreBinding(_ id: Int) -> Binding<Bool> {
        Binding {
            filter.query.genreIds.contains(id)
        } set: { isOn in
            if isOn {
                filter.query.genreIds.insert(id)
            } else {
                filter.query.genreIds.remove(id)
            }
        }
    }
}
