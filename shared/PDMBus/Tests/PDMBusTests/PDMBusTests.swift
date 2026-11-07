import XCTest
@testable import PDMBus

final class PDMBusTests: XCTestCase {
    func testEventLineFormat() throws {
        let e = PDMEvent(app: "vocuteach", device: "iphone", type: "word.known", subject: PDMSubject.word(" Abandon "),
                         data: ["n": 2, "ok": true], date: Date(timeIntervalSince1970: 0), id: "X")
        let line = try XCTUnwrap(e.jsonLine())
        XCTAssertEqual(line.last, 0x0A)
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: line.dropLast()) as? [String: Any])
        XCTAssertEqual(o["v"] as? Int, 1)
        XCTAssertEqual(o["ts"] as? String, "1970-01-01T00:00:00Z")
        XCTAssertEqual(o["subject"] as? String, "word:abandon")
        XCTAssertEqual((o["data"] as? [String: Any])?["n"] as? Int, 2)
    }

    func testEmitFlushRefresh() throws {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("pdm-test-\(UUID().uuidString)")
        let bus = vault.appendingPathComponent("_bus")
        try FileManager.default.createDirectory(at: bus.appendingPathComponent("state"), withIntermediateDirectories: true)
        let words = #"{"v":1,"generated":"g1","counts":{"known":1},"focus":[{"word":"dominant","why":"x","status":"new"},{"word":"old","status":"known"}],"words":{"old":{"status":"known","sources":{}},"dominant":{"status":"new","cefr":null}}}"#
        try words.data(using: .utf8)!.write(to: bus.appendingPathComponent("state/words.json"))
        try #"{"v":1,"date":"2026-10-16","lines":[{"id":"cumle","name":"Cümle","today":"Gün 23"}],"focus_words":[]}"#
            .data(using: .utf8)!.write(to: bus.appendingPathComponent("state/today.json"))

        let app = "test-\(UUID().uuidString.prefix(6))"
        let b = PDMBus(app: app, vaultRoot: { vault })
        b.emit("word.known", subject: PDMSubject.word("dominant"))
        b.emit("word.learning", subject: PDMSubject.word("reinforce"))
        XCTAssertEqual(b.pendingCount, 2)
        let r = b.syncNow()
        XCTAssertEqual(r.status, .ok)
        XCTAssertEqual(r.sent, 2)
        XCTAssertEqual(b.pendingCount, 0)
        let file = bus.appendingPathComponent("events/\(app)/\(PDMBus.device).jsonl")
        let lines = try String(contentsOf: file).split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        // A second sync appends; it does not replace.
        b.emit("app.opened")
        XCTAssertEqual(b.syncNow().sent, 1)
        XCTAssertEqual(try String(contentsOf: file).split(separator: "\n").count, 3)

        let s = try XCTUnwrap(PDMBus.cachedWords())
        XCTAssertEqual(s.closed, ["old"])
        XCTAssertEqual(s.openFocus().map(\.word), ["dominant"])
        XCTAssertEqual(s.openFocus(extraClosed: ["Dominant"]).count, 0)
        XCTAssertEqual(PDMBus.cachedToday()?.lines?.first?.today, "Gün 23")
    }

    func testLiveState() throws {
        let app = "live-\(UUID().uuidString.prefix(6))"
        let b = PDMBus(app: app, vaultRoot: { nil })
        XCTAssertNil(PDMBus.live(of: app))
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        b.publishLive(PDMLive(app: "other", updated: t0, kind: "book", id: "d1", title: "Arkhe", progress: 0.421,
                              active: true, link: "wisepath://book/d1", refs: ["teoria": "by-k1-c04"]))
        let a = try XCTUnwrap(PDMBus.live(of: app))
        XCTAssertEqual(a.app, app)                       // an app writes only its own file
        XCTAssertEqual(a.refs?["teoria"], "by-k1-c04")
        // The same content a few seconds later is not written again.
        b.publishLive(PDMLive(app: app, updated: t0.addingTimeInterval(5), kind: "book", id: "d1", title: "Arkhe",
                              progress: 0.424, active: true, link: "wisepath://book/d1", refs: ["teoria": "by-k1-c04"]))
        XCTAssertEqual(PDMBus.live(of: app)?.updated, t0)
        // A change is written immediately.
        b.publishLive(PDMLive(app: app, updated: t0.addingTimeInterval(6), kind: "book", id: "d1", title: "Arkhe",
                              progress: 0.424, active: false, link: "wisepath://book/d1", refs: ["teoria": "by-k1-c04"]))
        XCTAssertEqual(PDMBus.live(of: app)?.active, false)
        // After the refresh interval the time is written again.
        b.publishLive(PDMLive(app: app, updated: t0.addingTimeInterval(120), kind: "book", id: "d1", title: "Arkhe",
                              progress: 0.424, active: false, link: "wisepath://book/d1", refs: ["teoria": "by-k1-c04"]))
        XCTAssertEqual(PDMBus.live(of: app)?.updated, t0.addingTimeInterval(120))
        XCTAssertNil(PDMBus.live(of: app, maxAge: 60))    // t0 is in 1970
        XCTAssertTrue(PDMBus.allLive().contains { $0.app == app })
        b.clearLive()
        XCTAssertNil(PDMBus.live(of: app))
    }

    func testRelayCarriesOtherOutboxes() throws {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("pdm-relay-\(UUID().uuidString)")
        let bus = vault.appendingPathComponent("_bus")
        try FileManager.default.createDirectory(at: bus, withIntermediateDirectories: true)
        let other = "ufuk-\(UUID().uuidString.prefix(4).lowercased())"
        let silent = PDMBus(app: other, vaultRoot: { nil })     // no vault folder of its own
        silent.emit("weather.day")
        silent.emit("app.opened")
        XCTAssertEqual(silent.syncNow().status, .noVault)
        XCTAssertEqual(silent.pendingCount, 2)

        let carrier = PDMBus(app: "carrier-\(UUID().uuidString.prefix(4).lowercased())", vaultRoot: { vault })
        let r = carrier.syncNow()
        XCTAssertEqual(r.status, .ok)
        XCTAssertGreaterThanOrEqual(r.relayed, 2)
        XCTAssertTrue(r.relayedApps.contains(other))
        XCTAssertEqual(silent.pendingCount, 0)
        let file = bus.appendingPathComponent("events/\(other)/\(PDMBus.device).jsonl")
        let lines = try String(contentsOf: file).split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("\"app\":\"\(other)\""))
        // Nothing is carried twice.
        XCTAssertFalse(carrier.syncNow().relayedApps.contains(other))
        XCTAssertFalse(PDMEvent.isSafeApp("../x"))
    }

    func testWrongRootIsRejected() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pdm-none-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let b = PDMBus(app: "t", vaultRoot: { tmp })
        XCTAssertEqual(b.syncNow().status, .notVaultRoot)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("_bus").path))
    }
}
