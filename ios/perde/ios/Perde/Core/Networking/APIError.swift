import Foundation

enum APIError: LocalizedError, Equatable, Sendable {
    case missingKey(service: String)
    case invalidKey(service: String)
    case quotaReached(service: String)
    case network(String)
    case badResponse(service: String)
    case platformNotListed(String)

    var errorDescription: String? {
        switch self {
        case .missingKey(let service):
            "\(service) anahtarı girilmemiş. Ayarlar'dan ekleyebilirsin."
        case .invalidKey(let service):
            "\(service) anahtarı geçersiz. Ayarlar'dan kontrol et."
        case .quotaReached(let service):
            "\(service) istek sınırı doldu. Daha sonra yeniden dene."
        case .network(let message):
            "Bağlantı sorunu: \(message)"
        case .badResponse(let service):
            "\(service) beklenmeyen bir yanıt verdi."
        case .platformNotListed(let name):
            "\(name), TMDB'nin Türkiye platform listesinde bulunamadı."
        }
    }
}
