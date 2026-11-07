import Foundation
import Network

/// Local bridge for Claude: 127.0.0.1:8790, every call except /health needs the token in
/// ~/Library/Application Support/Kurultay/token (header X-Kurultay-Token).
@MainActor
final class BridgeServer {
    static let port: UInt16 = 8790
    private var listener: NWListener?
    private let council: Council
    let token: String

    init(council: Council) {
        self.council = council
        if let t = try? String(contentsOf: Paths.token, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), t.count >= 32 {
            token = t
        } else {
            token = (0..<2).map { _ in UUID().uuidString.replacingOccurrences(of: "-", with: "") }.joined()
            try? token.write(to: Paths.token, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Paths.token.path)
        }
    }

    func start() {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
        params.allowLocalEndpointReuse = true
        guard let l = try? NWListener(using: params) else { return }
        l.newConnectionHandler = { [weak self] conn in
            conn.start(queue: .main)
            Task { @MainActor in self?.receive(conn, Data()) }
        }
        l.start(queue: .main)
        listener = l
    }

    private func receive(_ conn: NWConnection, _ buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, done, err in
            Task { @MainActor in
                guard let self else { return }
                var buf = buffer
                if let data { buf.append(data) }
                if let req = HTTPRequest(buf) {
                    let (code, body) = await self.handle(req)
                    self.respond(conn, code, body)
                } else if done || err != nil || buf.count > 8 << 20 {
                    conn.cancel()
                } else {
                    self.receive(conn, buf)
                }
            }
        }
    }

    private func respond(_ conn: NWConnection, _ code: Int, _ body: Any) {
        let data = (try? JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
        let head = "HTTP/1.1 \(code) \(code == 200 ? "OK" : "ERR")\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n"
        conn.send(content: Data(head.utf8) + data, completion: .contentProcessed { _ in conn.cancel() })
    }

    private func json<T: Encodable>(_ v: T) -> Any {
        (try? JSONSerialization.jsonObject(with: JSONEncoder.kurultay.encode(v))) ?? [:]
    }

    private func handle(_ r: HTTPRequest) async -> (Int, Any) {
        if r.path == "/health" { return (200, ["ok": true, "app": "Kurultay", "seats": council.activeSeats.map(\.id), "basket": council.sparkBasket.count]) }
        guard r.headers["x-kurultay-token"] == token else { return (401, ["error": "token"]) }
        let b = r.json
        switch (r.method, r.path) {
        case ("GET", "/seats"), ("POST", "/check"):
            var out: [[String: Any]] = []
            for s in council.seats {
                var row: [String: Any] = ["id": s.id, "name": s.name, "enabled": s.enabled ?? true, "api": s.api?.provider ?? "",
                                          "apiKey": s.api.map { Keychain.get($0.provider) != nil } ?? false]
                if let w = council.web[s.id] {
                    if r.method == "POST", s.enabled ?? true { _ = await w.relink() }
                    let p = r.method == "POST" ? await w.refreshState() : w.page
                    row.merge(["input": p.input, "login": p.login, "guest": p.guest, "url": p.url, "think": p.think, "busy": p.busy, "answers": p.count]) { $1 }
                }
                out.append(row)
            }
            return (200, ["seats": out, "accounts": ["saved": AccountKeeper.load().count, "restored": AccountKeeper.lastRestore,
                                                     "lastBackup": AccountKeeper.lastBackup.map { ISO8601DateFormatter().string(from: $0) } ?? ""]])
        case ("GET", "/sessions"):
            return (200, ["sessions": council.sessions.map { s in
                ["id": s.id, "title": s.title, "rounds": s.rounds.count, "done": s.rounds.last?.done ?? true,
                 "report": SessionFiles.report(s.id) != nil, "decision": SessionFiles.decision(s.id)?.state ?? ""] as [String: Any]
            }])
        case ("GET", "/session"):
            guard let s = council.session(r.query["id"]) else { return (404, ["error": "oturum yok"]) }
            var o = json(s) as? [String: Any] ?? [:]
            o["folder"] = SessionFiles.folder(s.id).path
            o["decision"] = SessionFiles.decision(s.id).map(json) ?? NSNull()
            o["reportPath"] = SessionFiles.report(s.id)?.url.path ?? NSNull()
            return (200, o)
        case ("POST", "/session"):
            let s = council.newSession(title: b["title"] as? String ?? "Kurultay", seats: b["seats"] as? [String], origin: "claude")
            return (200, ["id": s.id, "folder": SessionFiles.folder(s.id).path, "seats": s.seats])
        case ("POST", "/ask"):
            guard let text = b["text"] as? String, !text.isEmpty else { return (400, ["error": "text"]) }
            if let ks = b["kivilcim"] as? [String], !ks.isEmpty, b["session"] == nil {
                if council.library.sparks.isEmpty { council.library.load(); try? await Task.sleep(for: .seconds(2)) }
                guard let id = council.askWithSparks(title: b["title"] as? String ?? "", question: text, sparkIds: ks,
                                                     seats: b["seats"] as? [String], follow: b["follow"] as? Bool ?? false, origin: "claude") else {
                    return (400, ["error": "Kıvılcım kaydı bulunamadı"])
                }
                return (200, ["session": id, "round": 1])
            }
            let id = (b["session"] as? String).flatMap { council.session($0)?.id }
                ?? council.newSession(title: b["title"] as? String ?? String(text.prefix(60)), seats: b["seats"] as? [String], origin: "claude").id
            guard let round = council.ask(session: id, text: text, seats: b["seats"] as? [String], timeout: b["timeout"] as? Double ?? 600) else {
                return (400, ["error": "sorulamadı"])
            }
            return (200, ["session": id, "round": round])
        case ("GET", "/wait"):
            guard let id = r.query["session"], let s = council.session(id) else { return (404, ["error": "oturum yok"]) }
            let round = r.query["round"].flatMap(Int.init) ?? s.rounds.last?.id ?? 0
            await council.wait(session: id, round: round, timeout: r.query["timeout"].flatMap(Double.init) ?? 900)
            guard let rr = council.session(id)?.rounds.first(where: { $0.id == round }) else { return (404, ["error": "tur yok"]) }
            return (200, ["session": id, "done": rr.done, "round": json(rr)])
        case ("POST", "/probe"):
            guard let seat = b["seat"] as? String, let w = council.web[seat] else { return (404, ["error": "koltuk yok"]) }
            if let url = b["navigate"] as? String { await w.load(url); try? await Task.sleep(for: .seconds(3)) }
            guard let js = b["js"] as? String else { let p = await w.refreshState(); return (200, ["url": p.url, "input": p.input, "login": p.login]) }
            do {
                let v = try await w.run(js)
                return (200, ["result": v.map { JSONSerialization.isValidJSONObject([$0]) ? $0 : String(describing: $0) } ?? NSNull()])
            } catch { return (500, ["error": error.localizedDescription]) }
        case ("POST", "/retry"):
            guard let id = b["session"] as? String, council.session(id) != nil else { return (404, ["error": "oturum yok"]) }
            let seats = council.retry(session: id, round: b["round"] as? Int, seats: b["seats"] as? [String], timeout: b["timeout"] as? Double ?? 600)
            let round = (b["round"] as? Int) ?? council.session(id)?.rounds.last?.id ?? 0
            return (200, ["session": id, "round": round, "seats": seats])
        case ("GET", "/kivilcim"):
            council.library.load(); try? await Task.sleep(for: .seconds(1))
            let q = r.query["q"] ?? ""
            let rows = council.library.sparks.filter { q.isEmpty || $0.title.localizedCaseInsensitiveContains(q) || $0.text.localizedCaseInsensitiveContains(q) }
            return (200, ["sparks": rows.prefix(Int(r.query["limit"] ?? "40") ?? 40).map { s in
                ["id": s.id, "title": s.title, "kind": s.kindLabel, "date": ISO8601DateFormatter().string(from: s.date), "seconds": s.seconds, "chars": s.text.count] as [String: Any]
            }])
        case ("POST", "/reload"):
            council.reloadAdapters()
            return (200, ["ok": council.adapterError == nil, "error": council.adapterError ?? ""])
        case ("POST", "/decision"):
            guard let id = b["session"] as? String, let st = b["state"] as? String else { return (400, ["error": "session/state"]) }
            council.decide(id, state: st, note: b["note"] as? String)
            return (200, ["ok": true])
        case ("POST", "/pending"):
            council.writePending()
            return (200, ["path": Paths.pending.path])
        default:
            return (404, ["error": "yol yok: \(r.method) \(r.path)"])
        }
    }
}

struct HTTPRequest {
    var method = ""
    var path = ""
    var query: [String: String] = [:]
    var headers: [String: String] = [:]
    var body = Data()

    /// nil until the whole request (headers + Content-Length body) has arrived.
    init?(_ data: Data) {
        guard let sep = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[..<sep.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let first = head.first?.split(separator: " ") ?? []
        guard first.count >= 2 else { return nil }
        method = String(first[0])
        let comps = URLComponents(string: String(first[1]))
        path = comps?.path ?? "/"
        for q in comps?.queryItems ?? [] { query[q.name] = q.value ?? "" }
        for line in head.dropFirst() {
            if let c = line.firstIndex(of: ":") {
                headers[line[..<c].lowercased()] = line[line.index(after: c)...].trimmingCharacters(in: .whitespaces)
            }
        }
        let len = Int(headers["content-length"] ?? "0") ?? 0
        let rest = data[sep.upperBound...]
        guard rest.count >= len else { return nil }
        body = Data(rest.prefix(len))
    }

    var json: [String: Any] { (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:] }
}
