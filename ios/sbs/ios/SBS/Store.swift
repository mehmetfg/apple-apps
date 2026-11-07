// Reads SBS/state/sbs.json from the vault, keeps a copy on the phone, and writes the phone's own files
// (Apple Health day summaries, documents for the inbox) into SBS/phone/<device>/.
import Foundation
import PDMBus
import SwiftUI

@MainActor
final class Store: ObservableObject {
    static let shared = Store()
    nonisolated static let folder = "02 - Eudomonia/Beden/SBS"

    @Published var state: SBSState?
    @Published var origin = ""          // where the shown data came from, for the settings screen
    @Published var vaultLinked = false
    @Published var inboxWaiting = 0

    let bus = PDMBus(app: "sbs")

    private var cacheURL: URL { docs.appendingPathComponent("sbs.json") }
    private var docs: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    private var localInbox: URL {
        let u = docs.appendingPathComponent("inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static func decode(_ data: Data) -> SBSState? {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        do { return try d.decode(SBSState.self, from: data) } catch {
            print("sbs.json decode:", error)
            return nil
        }
    }

    /// Vault first, then the phone's copy, then the snapshot that was bundled at build time.
    func load() async {
        let fromVault: Data? = await Task.detached(priority: .userInitiated) { Self.readVault("state/sbs.json") }.value
        vaultLinked = Self.vaultRoot() != nil
        if let data = fromVault, let s = Self.decode(data) {
            state = s
            origin = "Vault · " + (s.generated.map { String($0.prefix(16)).replacingOccurrences(of: "T", with: " ") } ?? "")
            try? data.write(to: cacheURL, options: .atomic)
        } else if let data = try? Data(contentsOf: cacheURL), let s = Self.decode(data) {
            state = s
            origin = "Telefondaki kopya · " + (s.generated.map { String($0.prefix(10)) } ?? "")
        } else if let u = Bundle.main.url(forResource: "snapshot", withExtension: "json"),
                  let data = try? Data(contentsOf: u), let s = Self.decode(data) {
            state = s
            origin = "Kurulumdaki kopya · " + (s.generated.map { String($0.prefix(10)) } ?? "")
        }
        inboxWaiting = (try? FileManager.default.contentsOfDirectory(atPath: localInbox.path).count) ?? 0
    }

    // MARK: vault access

    nonisolated static func vaultRoot() -> URL? { PDMVault.simulatorOverride ?? PDMVault.resolve() }

    /// Runs `body` with the SBS folder of the vault, inside the security scope. nil when the vault is not linked.
    nonisolated static func withFolder<T>(_ body: (URL) -> T?) -> T? {
        guard let root = vaultRoot() else { return nil }
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        guard PDMVault.busFolder(in: root) != nil else { return nil }
        return body(root.appendingPathComponent(folder, isDirectory: true))
    }

    nonisolated static func readVault(_ relative: String) -> Data? {
        withFolder { dir in
            let file = dir.appendingPathComponent(relative)
            let fm = FileManager.default
            if !fm.fileExists(atPath: file.path) {   // an iCloud file that is not on the phone yet
                try? fm.startDownloadingUbiquitousItem(at: file)
                for _ in 0..<24 where !fm.fileExists(atPath: file.path) { Thread.sleep(forTimeInterval: 0.25) }
            }
            var data: Data?
            var err: NSError?
            NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &err) { data = try? Data(contentsOf: $0) }
            return data
        }
    }

    nonisolated static var phoneFolder: String { "phone/" + PDMBus.device }

    // MARK: Apple Health → vault

    /// One small file for each finished day: SBS/phone/<device>/days/<date>.json. Written only when it changed.
    func writeDays(_ days: [HealthDay]) async {
        let today = Day.key(.now)
        let rows = days.filter { $0.date < today && $0.hasData }
        guard !rows.isEmpty else { return }
        await Task.detached(priority: .utility) {
            _ = Self.withFolder { dir -> Bool? in
                let target = dir.appendingPathComponent(Self.phoneFolder + "/days", isDirectory: true)
                try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                let enc = JSONEncoder()
                enc.keyEncodingStrategy = .convertToSnakeCase
                enc.outputFormatting = [.sortedKeys, .prettyPrinted]
                for r in rows {
                    guard let data = try? enc.encode(r) else { continue }
                    let file = target.appendingPathComponent(r.date + ".json")
                    if (try? Data(contentsOf: file)) != data { try? data.write(to: file, options: .atomic) }
                }
                return true
            }
        }.value
    }

    // MARK: documents

    /// Keeps the picked file on the phone, then moves every waiting file into SBS/phone/<device>/inbox.
    func addDocument(from url: URL, title: String) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let stamp = Day.key(.now) + "-" + String(Int(Date.now.timeIntervalSince1970) % 100000)
        let clean = title.isEmpty ? url.deletingPathExtension().lastPathComponent : title
        let name = stamp + " " + clean.replacingOccurrences(of: "/", with: "-") + "." + (url.pathExtension.isEmpty ? "pdf" : url.pathExtension)
        try? FileManager.default.copyItem(at: url, to: localInbox.appendingPathComponent(name))
        bus.emit("document.added", subject: "document:" + name, data: ["title": .string(clean)])
        await flushInbox()
    }

    func addDocument(data: Data, title: String, ext: String) async {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
        try? data.write(to: tmp)
        await addDocument(from: tmp, title: title)
        try? FileManager.default.removeItem(at: tmp)
    }

    func flushInbox() async {
        let source = localInbox
        await Task.detached(priority: .utility) {
            _ = Self.withFolder { dir -> Bool? in
                let fm = FileManager.default
                let target = dir.appendingPathComponent(Self.phoneFolder + "/inbox", isDirectory: true)
                try? fm.createDirectory(at: target, withIntermediateDirectories: true)
                for name in (try? fm.contentsOfDirectory(atPath: source.path)) ?? [] {
                    let to = target.appendingPathComponent(name)
                    if !fm.fileExists(atPath: to.path), (try? fm.copyItem(at: source.appendingPathComponent(name), to: to)) != nil {
                        try? fm.removeItem(at: source.appendingPathComponent(name))
                    }
                }
                return true
            }
        }.value
        inboxWaiting = (try? FileManager.default.contentsOfDirectory(atPath: localInbox.path).count) ?? 0
        await bus.sync()
    }
}
