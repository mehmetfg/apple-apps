// Shared between the app, the widget extension and App Intents (2026-11-02).
// The edit log (olay-iphone.jsonl) lives in the App Group so a widget button or a Shortcuts action can mark an item
// done without opening the app; the app reads the same file and sends it to the vault as olay/iphone.jsonl.
// items.json is a small snapshot of the list (open items + recently done) for widgets, entity queries and snippets.
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

struct ItemSnapshot: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var priority: Int
    var status: String
    var kind: String
    var area: String
    var color: String
    var date: String
    var noteCount: Int

    var isDone: Bool { status == "done" }
    var prio: Priority { Priority(rawValue: priority) ?? .normal }
}

enum SharedStore {
    static var container: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.fatihgocgun.kivilcim") }
    static var eventsFile: URL? { container?.appendingPathComponent("olay-iphone.jsonl") }
    static var itemsFile: URL? { container?.appendingPathComponent("items.json") }

    static func appendEvent(target: String, type: String, value: Any) {
        guard let u = eventsFile else { return }
        let v = Olay.satir(hedef: target, tur: type, deger: value, cihaz: "iphone")
        if let h = try? FileHandle(forWritingTo: u) { h.seekToEndOfFile(); h.write(v); try? h.close() }
        else { try? v.write(to: u, options: .atomic) }
    }

    static func items() -> [ItemSnapshot] {
        guard let u = itemsFile, let v = try? Data(contentsOf: u) else { return [] }
        return (try? JSONDecoder().decode([ItemSnapshot].self, from: v)) ?? []
    }

    static func writeItems(_ list: [ItemSnapshot]) {
        guard let u = itemsFile, let v = try? JSONEncoder().encode(list) else { return }
        try? v.write(to: u, options: .atomic)
    }

    /// Open items, most urgent first, then newest first (a fresh recording must be visible at once).
    static func openItems() -> [ItemSnapshot] {
        items().filter { !$0.isDone && $0.kind != "journal" }.sorted { ($0.priority, $0.date) > ($1.priority, $1.date) }
    }

    /// Applies an edit to the snapshot at once (the widget redraws before the app recomputes the list).
    static func update(_ id: String, _ change: (inout ItemSnapshot) -> Void) {
        var list = items()
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        change(&list[i])
        writeItems(list)
    }

    static func setStatus(_ id: String, done: Bool) {
        appendEvent(target: id, type: "status", value: done ? "done" : "open")
        update(id) { $0.status = done ? "done" : "open" }
        reloadWidgets()
    }

    static func setPriority(_ id: String, _ p: Priority) {
        appendEvent(target: id, type: "priority", value: p.rawValue)
        update(id) { $0.priority = p.rawValue }
        reloadWidgets()
    }

    static func addNote(_ id: String, _ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        appendEvent(target: id, type: "note", value: t)
        update(id) { $0.noteCount += 1 }
    }

    static func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
