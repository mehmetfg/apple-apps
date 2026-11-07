import CryptoKit
import Foundation

/// Keeps the model sign-ins alive.
/// Chrome loses cookies when it crashes (session cookies) or when a site's tab is left stale;
/// this keeps an encrypted copy of the seats' cookies outside Chrome and puts missing ones back
/// when the Kurultay Chrome starts. The key lives in the Keychain, the file in Application Support (never iCloud).
@MainActor
enum AccountKeeper {
    static var file: URL { Paths.support.appendingPathComponent("accounts.vault") }
    /// Registrable domains of the seats (kimi.ai, chatgpt.com, ...); set by Council from adapters.json.
    static var domains: Set<String> = []
    /// Sign-in providers and old addresses the seats also need.
    static let extra: Set<String> = ["openai.com", "x.ai", "google.com.tr", "kimi.com", "moonshot.cn", "alibaba.com", "aliyun.com"]
    private(set) static var lastBackup: Date?
    private(set) static var lastRestore = 0

    static func setSeats(_ urls: [String]) {
        domains = Set(urls.compactMap { URL(string: $0)?.host.map(registrable) }).union(extra)
    }

    static func registrable(_ host: String) -> String {
        let p = host.lowercased().split(separator: ".")
        return p.count >= 2 ? p.suffix(2).joined(separator: ".") : host.lowercased()
    }

    static func relevant(_ domain: String) -> Bool {
        let d = domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        return domains.contains { d == $0 || d.hasSuffix("." + $0) }
    }

    private static func key() -> SymmetricKey {
        if let s = Keychain.get("account-vault-key"), let d = Data(base64Encoded: s), d.count == 32 { return SymmetricKey(data: d) }
        let k = SymmetricKey(size: .bits256)
        Keychain.set("account-vault-key", k.withUnsafeBytes { Data($0) }.base64EncodedString())
        return k
    }

    static func load() -> [[String: Any]] {
        guard let raw = try? Data(contentsOf: file), let box = try? AES.GCM.SealedBox(combined: raw),
              let plain = try? AES.GCM.open(box, using: key()),
              let arr = try? JSONSerialization.jsonObject(with: plain) as? [[String: Any]] else { return [] }
        return arr
    }

    private static func save(_ cookies: [[String: Any]]) {
        guard let plain = try? JSONSerialization.data(withJSONObject: cookies),
              let sealed = try? AES.GCM.seal(plain, using: key()).combined else { return }
        try? sealed.write(to: file, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    private static func ident(_ c: [String: Any]) -> String {
        "\(c["name"] ?? "")|\(c["domain"] ?? "")|\(c["path"] ?? "")"
    }

    private static func browserCookies() async -> [[String: Any]]? {
        guard let b = await ChromeHost.shared.browser() else { return nil }
        defer { b.close() }
        guard let r = try? await b.send("Storage.getCookies", timeout: 10) else { return nil }
        return (r["cookies"] as? [[String: Any]])?.filter { relevant($0["domain"] as? String ?? "") }
    }

    /// Snapshot of the seats' cookies. A site whose cookies all vanished keeps its last good copy
    /// (that is a crash or a wipe, not a sign-out: signing out leaves some cookies behind).
    @discardableResult
    static func backup() async -> Int {
        guard !domains.isEmpty, await ChromeHost.shared.alive(), let now = await browserCookies() else { return 0 }
        let present = Set(now.compactMap { ($0["domain"] as? String).map(registrable) })
        let kept = load().filter { c in
            let site = registrable(c["domain"] as? String ?? "")
            return relevant(site) && !present.contains(site) && !expired(c)
        }
        let all = now + kept
        if !all.isEmpty { save(all); lastBackup = Date() }
        return all.count
    }

    private static func expired(_ c: [String: Any]) -> Bool {
        if c["session"] as? Bool == true { return false }
        guard let e = c["expires"] as? Double, e > 0 else { return false }
        return e < Date().timeIntervalSince1970
    }

    /// Puts back the saved cookies Chrome no longer has. Session cookies come back with 14 days of life,
    /// so the next crash cannot take them either.
    @discardableResult
    static func restore() async -> Int {
        let saved = load()
        guard !saved.isEmpty, let now = await browserCookies() else { return 0 }
        let have = Set(now.map(ident))
        let fields = ["name", "value", "domain", "path", "secure", "httpOnly", "sameSite", "priority", "sourceScheme", "sourcePort", "partitionKey"]
        let missing: [[String: Any]] = saved.filter { !have.contains(ident($0)) && !expired($0) }.map { c in
            var p: [String: Any] = [:]
            for f in fields { if let v = c[f] { p[f] = v } }
            if c["session"] as? Bool == true || (c["expires"] as? Double ?? -1) <= 0 {
                p["expires"] = Date().addingTimeInterval(14 * 86_400).timeIntervalSince1970
            } else { p["expires"] = c["expires"] }
            return p
        }
        guard !missing.isEmpty, let b = await ChromeHost.shared.browser() else { return 0 }
        defer { b.close() }
        var put = 0
        for chunk in stride(from: 0, to: missing.count, by: 50).map({ Array(missing[$0..<min($0 + 50, missing.count)]) }) {
            if (try? await b.send("Storage.setCookies", ["cookies": chunk], timeout: 10)) != nil { put += chunk.count }
            else { for c in chunk where (try? await b.send("Storage.setCookies", ["cookies": [c]], timeout: 5)) != nil { put += 1 } }
        }
        lastRestore = put
        return put
    }
}
