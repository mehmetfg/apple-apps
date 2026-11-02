// Vault access: a security-scoped bookmark of the vault folder ("Vault klasörünü seç").
// iOS does not share a bookmark between apps, so each app selects the folder one time.
// Apps that already have their own bookmark (VocuTeach, Vitrin) give it to PDMBus with `vaultRoot:`.
import Foundation

public enum PDMVault {
    static let bookmarkKey = "pdm.vault.bookmark"

    /// Simulator test hook: `SIMCTL_CHILD_PDM_VAULT=/path/to/vault xcrun simctl launch …`.
    /// The simulator reads Mac paths directly, so no bookmark is necessary there.
    public static var simulatorOverride: URL? {
        #if targetEnvironment(simulator)
        if let p = ProcessInfo.processInfo.environment["PDM_VAULT"], !p.isEmpty {
            return URL(fileURLWithPath: p, isDirectory: true)
        }
        #endif
        return nil
    }

    /// Keep the selected folder. Call it while the URL from the file importer is in scope.
    public static func save(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if let d = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(d, forKey: bookmarkKey)
        }
    }

    public static func forget() { UserDefaults.standard.removeObject(forKey: bookmarkKey) }

    /// The folder that the user selected in this app (through PDMVault), or nil.
    public static func resolve() -> URL? { resolveBookmark(UserDefaults.standard.data(forKey: bookmarkKey)) {
        UserDefaults.standard.set($0, forKey: bookmarkKey)
    } }

    /// Resolves bookmark data. When the bookmark is stale, `refresh` gets new data.
    public static func resolveBookmark(_ data: Data?, refresh: ((Data) -> Void)? = nil) -> URL? {
        guard let data else { return nil }
        var stale = false
        guard let u = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        else { return nil }
        if stale, let refresh {
            let scoped = u.startAccessingSecurityScopedResource()
            defer { if scoped { u.stopAccessingSecurityScopedResource() } }
            if let d = try? u.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) { refresh(d) }
        }
        return u
    }

    /// `<root>/_bus`, if the root is the vault (Personel Data Management). Never makes the folder:
    /// a wrong root must not get a new `_bus`.
    public static func busFolder(in root: URL) -> URL? {
        let bus = root.appendingPathComponent("_bus", isDirectory: true)
        var dir: ObjCBool = false
        if FileManager.default.fileExists(atPath: bus.path, isDirectory: &dir), dir.boolValue { return bus }
        return nil
    }
}
