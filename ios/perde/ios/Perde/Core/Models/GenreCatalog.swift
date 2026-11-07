import Foundation

struct GenreCatalog: Sendable {
    var movie: [Int: String] = [:]
    var tv: [Int: String] = [:]

    func names(for title: CatalogTitle) -> [String] {
        let lookup = title.kind == .movie ? movie : tv
        return title.genreIds.compactMap { lookup[$0] }
    }

    func sortedGenres(for kind: MediaKind) -> [(id: Int, name: String)] {
        let lookup = kind == .movie ? movie : tv
        return lookup
            .map { (id: $0.key, name: $0.value) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }
}
