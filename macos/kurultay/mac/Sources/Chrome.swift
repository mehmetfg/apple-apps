import AppKit
import Foundation

/// Drives a dedicated Google Chrome profile over the DevTools protocol.
/// Sign-in happens in real Chrome (Google, Apple, Cloudflare, passkeys all work there);
/// the profile lives in ~/Library/Application Support/Kurultay/chrome, apart from the user's own Chrome.
@MainActor
final class ChromeHost {
    static let shared = ChromeHost()
    static let app = "/Applications/Google Chrome.app"
    static var installed: Bool { FileManager.default.fileExists(atPath: app) }
    let port = 9333
    private var launching = false

    var profile: URL {
        let u = Paths.support.appendingPathComponent("chrome")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    private func get(_ path: String, method: String = "GET") async -> Any? {
        guard let u = URL(string: "http://127.0.0.1:\(port)\(path)") else { return nil }
        var r = URLRequest(url: u, timeoutInterval: 4)
        r.httpMethod = method
        guard let (d, _) = try? await URLSession.shared.data(for: r) else { return nil }
        return try? JSONSerialization.jsonObject(with: d)
    }

    func alive() async -> Bool { await get("/json/version") != nil }

    /// Starts the Kurultay Chrome if its port is not answering.
    func ensureRunning() async -> Bool {
        if await alive() { return true }
        if !launching {
            launching = true
            preparePreferences()
            let p = Process()
            p.executableURL = URL(fileURLWithPath: Self.app + "/Contents/MacOS/Google Chrome")
            p.arguments = ["--user-data-dir=\(profile.path)", "--remote-debugging-port=\(port)",
                           "--no-first-run", "--no-default-browser-check",
                           "--disable-background-timer-throttling", "--disable-renderer-backgrounding",
                           "--disable-backgrounding-occluded-windows", "about:blank"]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
        }
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(500))
            if await alive() {
                launching = false
                // a fresh Chrome: put back sign-ins it lost (crash, wipe)
                try? await Task.sleep(for: .seconds(1))
                await AccountKeeper.restore()
                return true
            }
        }
        launching = false
        return false
    }

    /// Before Chrome starts: reopen the last tabs (this keeps session cookies) and clear the "crashed" mark,
    /// which otherwise makes Chrome drop the session.
    private func preparePreferences() {
        let f = profile.appendingPathComponent("Default/Preferences")
        guard let d = try? Data(contentsOf: f), var o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        var session = o["session"] as? [String: Any] ?? [:]
        session["restore_on_startup"] = 1
        o["session"] = session
        var prof = o["profile"] as? [String: Any] ?? [:]
        prof["exit_type"] = "Normal"
        prof["exited_cleanly"] = true
        o["profile"] = prof
        if let out = try? JSONSerialization.data(withJSONObject: o) { try? out.write(to: f, options: .atomic) }
    }

    /// The browser-level DevTools connection (cookies, windows).
    func browser() async -> ChromeTab? {
        guard let v = await get("/json/version") as? [String: Any], let ws = (v["webSocketDebuggerUrl"] as? String).flatMap(URL.init) else { return nil }
        return ChromeTab(targetId: "browser", ws: ws)
    }

    func pages() async -> [[String: Any]] {
        ((await get("/json/list")) as? [[String: Any]] ?? []).filter { $0["type"] as? String == "page" }
    }

    func newTab(_ url: String) async -> [String: Any]? {
        let q = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url
        return await get("/json/new?\(q)", method: "PUT") as? [String: Any]
    }

    /// Opens the page in a window of its own, so it is never a hidden background tab.
    func newWindow(_ url: String, index: Int) async -> String? {
        guard let v = await get("/json/version") as? [String: Any], let ws = (v["webSocketDebuggerUrl"] as? String).flatMap(URL.init) else { return nil }
        let browser = ChromeTab(targetId: "browser", ws: ws)
        defer { browser.close() }
        let r = try? await browser.send("Target.createTarget", ["url": url, "newWindow": true, "background": true])
        guard let id = r?["targetId"] as? String else { return nil }
        if let w = try? await browser.send("Browser.getWindowForTarget", ["targetId": id]), let wid = w["windowId"] as? Int {
            _ = try? await browser.send("Browser.setWindowBounds", ["windowId": wid, "bounds":
                ["left": 60 + index * 36, "top": 60 + index * 30, "width": 1100, "height": 860, "windowState": "normal"]])
        }
        return id
    }

    func close(_ id: String) async { _ = await get("/json/close/\(id)") }

    func activate(_ id: String) async {
        _ = await get("/json/activate/\(id)")
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: Self.app), configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }
}

/// One DevTools connection to one Chrome tab.
@MainActor
final class ChromeTab {
    let targetId: String
    private let socket: URLSessionWebSocketTask
    private var nextId = 1
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private(set) var closed = false

    struct Failure: Error, LocalizedError { let message: String; var errorDescription: String? { message } }

    init(targetId: String, ws: URL) {
        self.targetId = targetId
        socket = URLSession.shared.webSocketTask(with: ws)
        socket.maximumMessageSize = 64 << 20
        socket.resume()
        listen()
    }

    private func listen() {
        socket.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case let .success(msg):
                    var data: Data?
                    switch msg {
                    case let .string(s): data = Data(s.utf8)
                    case let .data(d): data = d
                    @unknown default: break
                    }
                    if let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let id = obj["id"] as? Int, let c = self.pending.removeValue(forKey: id) {
                        if let err = obj["error"] as? [String: Any] { c.resume(throwing: Failure(message: "\(err["message"] ?? err)")) }
                        else { c.resume(returning: obj["result"] as? [String: Any] ?? [:]) }
                    }
                    self.listen()
                case .failure:
                    self.closed = true
                    for (_, c) in self.pending { c.resume(throwing: Failure(message: "sekme bağlantısı koptu")) }
                    self.pending.removeAll()
                }
            }
        }
    }

    func send(_ method: String, _ params: [String: Any] = [:], timeout: Double = 60) async throws -> [String: Any] {
        if closed { throw Failure(message: "sekme kapalı") }
        let id = nextId; nextId += 1
        let body = try JSONSerialization.data(withJSONObject: ["id": id, "method": method, "params": params])
        return try await withCheckedThrowingContinuation { c in
            pending[id] = c
            socket.send(.string(String(decoding: body, as: UTF8.self))) { [weak self] err in
                guard let err else { return }
                Task { @MainActor in self?.pending.removeValue(forKey: id)?.resume(throwing: err) }
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                self?.pending.removeValue(forKey: id)?.resume(throwing: Failure(message: "zaman aşımı: \(method)"))
            }
        }
    }

    func evaluate(_ expression: String, timeout: Double = 60) async throws -> Any? {
        let r = try await send("Runtime.evaluate", ["expression": expression, "awaitPromise": true, "returnByValue": true], timeout: timeout)
        if let ex = r["exceptionDetails"] as? [String: Any] {
            let desc = ((ex["exception"] as? [String: Any])?["description"] as? String) ?? (ex["text"] as? String) ?? "JS hatası"
            throw Failure(message: desc)
        }
        return (r["result"] as? [String: Any])?["value"]
    }

    func navigate(_ url: String) async { _ = try? await send("Page.navigate", ["url": url]) }
    func insertText(_ text: String) async throws { _ = try await send("Input.insertText", ["text": text]) }
    func pressEnter() async {
        _ = try? await send("Input.dispatchKeyEvent", ["type": "keyDown", "key": "Enter", "code": "Enter", "text": "\r",
                                                        "unmodifiedText": "\r", "windowsVirtualKeyCode": 13, "nativeVirtualKeyCode": 13])
        _ = try? await send("Input.dispatchKeyEvent", ["type": "keyUp", "key": "Enter", "code": "Enter",
                                                        "windowsVirtualKeyCode": 13, "nativeVirtualKeyCode": 13])
    }
    func close() { closed = true; socket.cancel(with: .goingAway, reason: nil) }
}
