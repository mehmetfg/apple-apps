import Foundation
import Security

/// Stores API keys in the Keychain. In debug builds, environment variables win so the app can
/// be pointed at a local fixture server.
enum APIKeyStore {
    enum Key: String, Sendable {
        case tmdb = "tmdb-api-key"
        case omdb = "omdb-api-key"

        fileprivate var environmentName: String {
            switch self {
            case .tmdb: "TMDB_API_KEY"
            case .omdb: "OMDB_API_KEY"
            }
        }
    }

    private static let service = "com.fatihgocgun.perde.keys"

    static func value(for key: Key) -> String? {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment[key.environmentName], !override.isEmpty {
            return override
        }
        #endif
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty else { return nil }
        return text
    }

    static func set(_ value: String, for key: Key) {
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        SecItemDelete(identity as CFDictionary)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var attributes = identity
        attributes[kSecValueData as String] = Data(trimmed.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
