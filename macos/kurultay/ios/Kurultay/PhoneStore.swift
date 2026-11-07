import Foundation
import SwiftUI

/// The iPhone is a remote: it reads sessions and reports from the vault (iCloud) and writes
/// two kinds of files: a question request (Mac runs it) and a decision (karar.json).
@MainActor
final class PhoneStore: ObservableObject {
    @Published var root: URL?
    @Published var sessions: [Session] = []
    @Published var seats: [SeatConfig] = []
    @Published var reports: [String: String] = [:]
    @Published var decisions: [String: Decision] = [:]
    @Published var pendingRequests = 0
    @Published var error: String?
    @Published var loading = false

    private let bookmarkKey = "vaultBookmark"

    init() {
        #if DEBUG
        // simulator test: xcrun simctl launch … -vaultPath /path/to/copy
        if let p = UserDefaults.standard.string(forKey: "vaultPath") { root = URL(fileURLWithPath: p); return }
        #endif
        if let d = UserDefaults.standard.data(forKey: bookmarkKey) {
            var stale = false
            if let u = try? URL(resolvingBookmarkData: d, bookmarkDataIsStale: &stale) {
                root = u
                if stale { saveBookmark(u) }
            }
        }
    }

    func choose(_ url: URL) {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        saveBookmark(url)
        root = url
        Task { await refresh() }
    }

    private func saveBookmark(_ u: URL) {
        if let d = try? u.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(d, forKey: bookmarkKey)
        }
    }

    private var sessionsDir: URL? { root?.appendingPathComponent("05 - Notlar/Kurultay") }
    private var toolDir: URL? { root?.appendingPathComponent("_araçlar/kurultay") }

    private func access<T>(_ body: (URL) throws -> T) rethrows -> T? {
        guard let root else { return nil }
        let ok = root.startAccessingSecurityScopedResource()
        defer { if ok { root.stopAccessingSecurityScopedResource() } }
        return try body(root)
    }

    nonisolated private static func read(_ u: URL) -> Data? {
        let fm = FileManager.default
        if !fm.fileExists(atPath: u.path) {
            // iCloud placeholder: ask for the download
            let ph = u.deletingLastPathComponent().appendingPathComponent("." + u.lastPathComponent + ".icloud")
            if fm.fileExists(atPath: ph.path) { try? fm.startDownloadingUbiquitousItem(at: u) }
            return nil
        }
        var out: Data?
        var err: NSError?
        NSFileCoordinator().coordinate(readingItemAt: u, options: [], error: &err) { out = try? Data(contentsOf: $0) }
        return out
    }

    nonisolated private static func write(_ d: Data, to u: URL) throws {
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        var err: NSError?
        var inner: Error?
        NSFileCoordinator().coordinate(writingItemAt: u, options: .forReplacing, error: &err) { dest in
            do { try d.write(to: dest, options: .atomic) } catch { inner = error }
        }
        if let e = err ?? inner { throw e }
    }

    func refresh() async {
        guard let root, let sessionsDir, let toolDir else { return }
        loading = true
        defer { loading = false }
        let result: (sessions: [Session], reports: [String: String], decisions: [String: Decision], seats: [SeatConfig], pending: Int)
            = await Task.detached {
                let ok = root.startAccessingSecurityScopedResource()
                defer { if ok { root.stopAccessingSecurityScopedResource() } }
                let fm = FileManager.default
                try? fm.startDownloadingUbiquitousItem(at: sessionsDir)
                var sessions: [Session] = []
                var reports: [String: String] = [:]
                var decisions: [String: Decision] = [:]
                for dir in (try? fm.contentsOfDirectory(at: sessionsDir, includingPropertiesForKeys: nil)) ?? [] {
                    guard let d = Self.read(dir.appendingPathComponent("oturum.json")),
                          let s = try? JSONDecoder.kurultay.decode(Session.self, from: d) else { continue }
                    sessions.append(s)
                    let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
                    if let rep = files.first(where: { $0.lastPathComponent.hasPrefix("Kurultay — ") && $0.pathExtension == "md" }),
                       let t = Self.read(rep).flatMap({ String(data: $0, encoding: .utf8) }) { reports[s.id] = t }
                    if let k = Self.read(dir.appendingPathComponent("karar.json")),
                       let dec = try? JSONDecoder.kurultay.decode(Decision.self, from: k) { decisions[s.id] = dec }
                }
                var seats: [SeatConfig] = []
                if let a = Self.read(toolDir.appendingPathComponent("adapters.json")),
                   let f = try? JSONDecoder().decode(AdapterFile.self, from: a) { seats = f.seats }
                let pending = ((try? fm.contentsOfDirectory(atPath: toolDir.appendingPathComponent("durum/istek").path)) ?? [])
                    .filter { $0.hasSuffix(".json") }.count
                return (sessions.sorted { $0.created > $1.created }, reports, decisions, seats, pending)
            }.value
        sessions = result.sessions
        reports = result.reports
        decisions = result.decisions
        if !result.seats.isEmpty { seats = result.seats }
        pendingRequests = result.pending
        error = sessions.isEmpty && seats.isEmpty ? "Vault'ta Kurultay bulunamadı. Doğru klasörü (Personel Data Management) seçtin mi?" : nil
    }

    /// The Mac picks this up within ~15 s and asks the assembly.
    func ask(_ text: String, seats: [String], session: String?) {
        guard let toolDir else { return }
        let req = InboxRequest(text: text, session: session, title: session == nil ? String(text.prefix(60)) : nil, seats: seats)
        do {
            let d = try JSONEncoder.kurultay.encode(req)
            try access { _ in try Self.write(d, to: toolDir.appendingPathComponent("durum/istek/\(UUID().uuidString).json")) }
            pendingRequests += 1
        } catch { self.error = "İstek yazılamadı: \(error.localizedDescription)" }
    }

    func decide(_ id: String, state: String, note: String) {
        guard let sessionsDir else { return }
        let dec = Decision(state: state, note: note.isEmpty ? nil : note, date: Date(), by: "iphone")
        do {
            let d = try JSONEncoder.kurultay.encode(dec)
            try access { _ in try Self.write(d, to: sessionsDir.appendingPathComponent(id).appendingPathComponent("karar.json")) }
            decisions[id] = dec
        } catch { self.error = "Karar yazılamadı: \(error.localizedDescription)" }
    }
}
