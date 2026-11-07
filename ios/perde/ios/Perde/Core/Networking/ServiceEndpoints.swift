import Foundation

enum ServiceEndpoints {
    static var tmdb: URL { url(environmentName: "TMDB_BASE_URL", fallback: "https://api.themoviedb.org/3") }
    static var omdb: URL { url(environmentName: "OMDB_BASE_URL", fallback: "https://www.omdbapi.com") }
    static var tmdbImages: URL { url(environmentName: "TMDB_IMAGE_BASE_URL", fallback: "https://image.tmdb.org/t/p") }

    static func poster(path: String?, width: Int = 342) -> URL? {
        guard let path else { return nil }
        return tmdbImages.appending(path: "w\(width)").appending(path: path)
    }

    private static func url(environmentName: String, fallback: String) -> URL {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment[environmentName], let url = URL(string: override) {
            return url
        }
        #endif
        return URL(string: fallback)!
    }
}
