import Foundation

struct CatalogPage: Sendable {
    let titles: [CatalogTitle]
    let page: Int
    let totalPages: Int
    let totalResults: Int
}
