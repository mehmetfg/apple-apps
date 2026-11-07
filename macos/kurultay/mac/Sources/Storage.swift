import Foundation
import Security

enum Paths {
    static let vault: URL = {
        if let v = ProcessInfo.processInfo.environment["KURULTAY_VAULT"] { return URL(fileURLWithPath: v) }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/iCloud~md~obsidian/Documents/Personel Data Management")
    }()
    static var sessions: URL { vault.appendingPathComponent("05 - Notlar/Kurultay") }
    static var tool: URL { vault.appendingPathComponent("_araçlar/kurultay") }
    static var adapters: URL { tool.appendingPathComponent("adapters.json") }
    static var inbox: URL { tool.appendingPathComponent("durum/istek") }
    static var processed: URL { tool.appendingPathComponent("durum/islenen") }
    static var pending: URL { tool.appendingPathComponent("BEKLEYEN.md") }
    static var support: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Kurultay")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static var token: URL { support.appendingPathComponent("token") }
    static var sparks: URL { vault.appendingPathComponent("05 - Notlar/Fikirler/Kıvılcım/dizin.json") }
    static var follow: URL { tool.appendingPathComponent("durum/takip") }
    static var followScript: URL { tool.appendingPathComponent("takip.py") }
    /// Kıvılcım record id → Kurultay sessions; Kıvılcım shows this under the record.
    static var sparkLinks: URL { tool.appendingPathComponent("durum/kivilcim-baglar.json") }
}

/// Loads, saves and lists sessions. Plain files: the vault is the only store.
enum SessionFiles {
    static func folder(_ id: String) -> URL { Paths.sessions.appendingPathComponent(id) }

    static func save(_ s: Session) {
        let dir = folder(s.id)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let d = try? JSONEncoder.kurultay.encode(s) { try? d.write(to: dir.appendingPathComponent("oturum.json"), options: .atomic) }
        try? answersMarkdown(s).write(to: dir.appendingPathComponent("Cevaplar — \(noteTitle(s.title)).md"), atomically: true, encoding: .utf8)
    }

    static func loadAll() -> [Session] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: Paths.sessions, includingPropertiesForKeys: nil) else { return [] }
        return items.compactMap { dir in
            guard let d = try? Data(contentsOf: dir.appendingPathComponent("oturum.json")) else { return nil }
            return try? JSONDecoder.kurultay.decode(Session.self, from: d)
        }.sorted { $0.created > $1.created }
    }

    static func report(_ id: String) -> (url: URL, text: String)? {
        let dir = folder(id)
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return nil }
        guard let u = items.first(where: { $0.lastPathComponent.hasPrefix("Kurultay — ") && $0.pathExtension == "md" }),
              let t = try? String(contentsOf: u, encoding: .utf8) else { return nil }
        return (u, t)
    }

    static func arrangement(_ id: String) -> Arrangement? {
        guard let d = try? Data(contentsOf: folder(id).appendingPathComponent("tertip.json")) else { return nil }
        return try? JSONDecoder().decode(Arrangement.self, from: d)
    }

    static func followState(_ id: String) -> FollowState? {
        guard let d = try? Data(contentsOf: Paths.follow.appendingPathComponent("\(id).json")) else { return nil }
        return try? JSONDecoder().decode(FollowState.self, from: d)
    }

    static func decision(_ id: String) -> Decision? {
        guard let d = try? Data(contentsOf: folder(id).appendingPathComponent("karar.json")) else { return nil }
        return try? JSONDecoder.kurultay.decode(Decision.self, from: d)
    }

    static func saveDecision(_ id: String, _ dec: Decision) {
        if let d = try? JSONEncoder.kurultay.encode(dec) { try? d.write(to: folder(id).appendingPathComponent("karar.json"), options: .atomic) }
    }

    static func answersMarkdown(_ s: Session) -> String {
        let df = DateFormatter(); df.locale = Locale(identifier: "tr_TR"); df.dateFormat = "d MMMM yyyy HH:mm"
        var md = "---\ntur: kurultay-cevaplar\noturum: \(s.id)\ntarih: \(ISO8601DateFormatter().string(from: s.created).prefix(10))\n---\n\n"
        md += "# Cevaplar — \(s.title)\n\nHam cevaplar, değiştirilmeden. Değerlendirme rapor notunda.\n"
        if let src = s.sources, !src.isEmpty {
            md += "\n**Kaynak (Kıvılcım):** " + src.map { "\($0.title)" + ($0.date.map { " (\($0.prefix(10)))" } ?? "") }.joined(separator: " · ") + "\n"
        }
        for r in s.rounds {
            md += "\n## Soru \(r.id) · \(df.string(from: r.asked))\n\n> " + r.shownText.replacingOccurrences(of: "\n", with: "\n> ") + "\n"
            if r.question != nil, let n = s.sources?.count, n > 0 { md += "\n_(Soruya \(n) Kıvılcım kaydının dökümü eklendi.)_\n" }
            for seat in s.seats {
                guard let a = r.answers[seat] else { continue }
                var meta = [a.state.label, a.via == "api" ? "API" : "tarayıcı"]
                if let t = a.thinking { meta.append("düşünme: \(t)") }
                if let sec = a.seconds { meta.append("\(sec) sn") }
                md += "\n### \(seat) · \(meta.joined(separator: " · "))\n\n"
                md += a.text.isEmpty ? "_(cevap yok\(a.error.map { ": \($0)" } ?? ""))_\n" : a.text + "\n"
            }
        }
        return md
    }
}

enum Keychain {
    static let service = "com.fatihgocgun.kurultay"

    static func get(_ name: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: name, kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        let s = String(data: d, encoding: .utf8)
        return (s?.isEmpty ?? true) ? nil : s
    }

    static func set(_ name: String, _ value: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: name]
        SecItemDelete(q as CFDictionary)
        guard !value.isEmpty else { return }
        var add = q; add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// OpenAI-compatible chat completion with the highest free thinking effort the provider accepts.
enum ApiClient {
    struct Failure: Error, LocalizedError { let message: String; var errorDescription: String? { message } }

    static func ask(provider: ProviderConfig, key: String, model: String, messages: [[String: String]]) async throws -> (text: String, reasoning: String?) {
        guard let url = URL(string: provider.base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions") else {
            throw Failure(message: "adres bozuk")
        }
        var body: [String: Any] = ["model": model, "messages": messages]
        switch provider.style {
        case "openrouter": body["reasoning"] = ["effort": "high"]
        case "gemini": body["reasoning_effort"] = "high"
        case "groq": body["reasoning_format"] = "parsed"
        default: break
        }
        var req = URLRequest(url: url, timeoutInterval: 900)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("Kurultay", forHTTPHeaderField: "X-Title")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure(message: "HTTP \(code): " + String(decoding: data.prefix(300), as: UTF8.self))
        }
        if let err = obj["error"] as? [String: Any] { throw Failure(message: "HTTP \(code): \(err["message"] ?? err)") }
        guard let choice = (obj["choices"] as? [[String: Any]])?.first, let msg = choice["message"] as? [String: Any] else {
            throw Failure(message: "HTTP \(code): cevap yok")
        }
        let text = (msg["content"] as? String) ?? ""
        let reasoning = (msg["reasoning"] as? String) ?? (msg["reasoning_content"] as? String)
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), reasoning)
    }
}
