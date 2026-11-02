// Self-update for the Mac apps through the shared iCloud folder (vault › _araçlar/dagitim).
// The building Mac publishes <Name>.zip + manifest.json (publish.sh); every other Mac picks it up here.
// At launch a newer build installs without asking; while the app runs, an hourly check asks first.
import AppKit
import CryptoKit
import Foundation
import UserNotifications

enum AppUpdater {
    static let folder: URL = {
        if let custom = ProcessInfo.processInfo.environment["APP_UPDATER_DIR"] { return URL(fileURLWithPath: custom) }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/iCloud~md~obsidian/Documents/Personel Data Management/_araçlar/dagitim")
    }()

    private struct Entry: Decodable { let name: String; let file: String; let build: String; let sha256: String; let date: String? }
    private struct Manifest: Decodable { let apps: [String: Entry] }

    /// Where the apps are installed. APP_UPDATER_APPS_DIR overrides it (tests only).
    static let appsFolder: URL = {
        if let custom = ProcessInfo.processInfo.environment["APP_UPDATER_APPS_DIR"] { return URL(fileURLWithPath: custom) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
    }()

    private static let queue = DispatchQueue(label: "app-updater", qos: .utility)
    private static var startedAt = Date()
    private static var declinedBuild = 0      // queue only
    private static var busy = false           // queue only
    private static var timer: Timer?
    private static var hubTimer: Timer?
    private static var hubWaiting: [String: String] = [:]   // queue only: bundle id -> build already reported as waiting
    private static var banner: NSPanel?

    private static var appName: String { Bundle.main.bundleURL.deletingPathExtension().lastPathComponent }
    private static var ownBuild: Int { Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0 }

    /// Call once from applicationDidFinishLaunching (or the App initializer).
    static func start() {
        startedAt = Date()
        queue.asyncAfter(deadline: .now() + 3) { check(atLaunch: true) }
        DispatchQueue.main.async {
            timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in queue.async { check(atLaunch: false) } }
        }
    }

    private static func check(atLaunch: Bool) {
        guard !busy, let bundleID = Bundle.main.bundleIdentifier else { return }
        busy = true
        defer { busy = false }
        guard let entry = readManifest()?.apps[bundleID] else { return }
        reportStatus(bundleID: bundleID)
        guard let build = Int(entry.build), build > ownBuild, build != declinedBuild else { return }
        guard let zip = waitForFile(folder.appendingPathComponent(entry.file), sha256: entry.sha256, timeout: 180),
              let newApp = unpack(zip, bundleID: bundleID, build: entry.build) else { return }
        let silent = atLaunch && Date().timeIntervalSince(startedAt) < 120
        DispatchQueue.main.async {
            if silent { install(newApp) } else { offer(newApp, entry: entry, build: build) }
        }
    }

    private static func readManifest() -> Manifest? {
        let url = folder.appendingPathComponent("manifest.json")
        for _ in 0..<10 {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            if let data = try? Data(contentsOf: url) { return try? JSONDecoder().decode(Manifest.self, from: data) }
            Thread.sleep(forTimeInterval: 3)
        }
        return nil
    }

    /// iCloud may still be downloading the zip (or hold an older copy): wait until its hash matches.
    private static func waitForFile(_ url: URL, sha256: String, timeout: TimeInterval) -> URL? {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            if let data = try? Data(contentsOf: url, options: .mappedIfSafe) {
                let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                if hex == sha256.lowercased() { return url }
            }
            Thread.sleep(forTimeInterval: 5)
        }
        return nil
    }

    private static func unpack(_ zip: URL, bundleID: String, build: String) -> URL? {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("AppUpdater-\(bundleID)-\(build)")
        try? fm.removeItem(at: dir)
        guard (try? fm.createDirectory(at: dir, withIntermediateDirectories: true)) != nil,
              run("/usr/bin/ditto", ["-x", "-k", zip.path, dir.path]) == 0,
              let app = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?.first(where: { $0.pathExtension == "app" }),
              let bundle = Bundle(url: app), bundle.bundleIdentifier == bundleID,
              bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String == build else { return nil }
        return app
    }

    /// Hands the swap to a small shell script that waits for this process to exit, replaces the bundle and reopens it.
    private static func install(_ newApp: URL) {
        let dest = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: dest.deletingLastPathComponent().path) else { return }
        let script = """
        pid=\(ProcessInfo.processInfo.processIdentifier); dest="$1"; new="$2"
        for i in {1..300}; do kill -0 $pid 2>/dev/null || break; sleep 0.2; done
        kill -0 $pid 2>/dev/null && exit 1
        rm -rf "$dest.old"
        if mv "$dest" "$dest.old"; then
          if mv "$new" "$dest"; then rm -rf "$dest.old"; else mv "$dest.old" "$dest"; fi
        fi
        xattr -dr com.apple.quarantine "$dest" 2>/dev/null
        open "$dest"
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-c", script, "app-updater", dest.path, newApp.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return }
        showBanner("\(appName) güncelleniyor…")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { NSApp.terminate(nil) }
    }

    private static func offer(_ newApp: URL, entry: Entry, build: Int) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "\(appName) için yeni sürüm hazır"
        alert.informativeText = "Yayın: \(entry.date ?? entry.build). Uygulama kapanır ve yeni sürümle yeniden açılır."
        alert.addButton(withTitle: "Yeniden başlat")
        alert.addButton(withTitle: "Sonra")
        if alert.runModal() == .alertFirstButtonReturn { install(newApp) } else { queue.async { declinedBuild = build } }
    }

    private static func showBanner(_ text: String) {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 64), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 320, height: 64))
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.alignment = .center
        label.frame = NSRect(x: 10, y: 22, width: 300, height: 20)
        effect.addSubview(label)
        panel.contentView = effect
        panel.center()
        panel.orderFrontRegardless()
        banner = panel
    }

    /// cihazlar/<Mac>/<bundle id>.json: which build this Mac runs. Rewritten only when it changes or is a day old.
    private static func reportStatus(bundleID: String) {
        writeRecord(bundleID: bundleID, app: appName, build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?",
                    path: Bundle.main.bundlePath)
    }

    private static func writeRecord(bundleID: String, app: String, build: String, path: String) {
        let host = (Host.current().localizedName ?? ProcessInfo.processInfo.hostName).replacingOccurrences(of: "/", with: "-")
        let dir = folder.appendingPathComponent("cihazlar/\(host)")
        let url = dir.appendingPathComponent("\(bundleID).json")
        if let data = try? Data(contentsOf: url),
           let old = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           old["build"] == build, let seen = old["seen"].flatMap({ ISO8601DateFormatter().date(from: $0) }),
           Date().timeIntervalSince(seen) < 86_400 { return }
        let record = ["host": host, "app": app, "bundle": bundleID, "build": build,
                      "path": path, "seen": ISO8601DateFormatter().string(from: Date())]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Hub (always-open Mac app keeps every published app current on this Mac)

    /// Call from the always-open app only (Uygulamalarım). Every 5 minutes: a closed app with an older build is
    /// replaced at once; a running one is left alone, reported, and replaced on the next check after it quits.
    /// Apps missing from this Mac are installed too, so a fresh Mac needs only this app.
    static func startHub() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        queue.asyncAfter(deadline: .now() + 8) { hubCheck() }
        DispatchQueue.main.async {
            hubTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in queue.async { hubCheck() } }
        }
    }

    private static func hubCheck() {
        guard !busy, let manifest = readManifest() else { return }
        busy = true
        defer { busy = false }
        let me = Bundle.main.bundleIdentifier
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        for (bundleID, entry) in manifest.apps where bundleID != me {
            guard let build = Int(entry.build) else { continue }
            let dest = appsFolder.appendingPathComponent("\(entry.name).app")
            let have = Int(Bundle(url: dest)?.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
            if have >= build { writeRecord(bundleID: bundleID, app: entry.name, build: String(have), path: dest.path); continue }
            if running.contains(bundleID) {
                if hubWaiting[bundleID] != entry.build {
                    hubWaiting[bundleID] = entry.build
                    notify("\(entry.name) yeni sürümde hazır", "Uygulamayı kapatınca kendiliğinden kurulacak.")
                }
                continue
            }
            guard let zip = waitForFile(folder.appendingPathComponent(entry.file), sha256: entry.sha256, timeout: 60),
                  let newApp = unpack(zip, bundleID: bundleID, build: entry.build) else { continue }
            guard replaceClosed(dest, with: newApp) else { continue }
            hubWaiting[bundleID] = nil
            writeRecord(bundleID: bundleID, app: entry.name, build: entry.build, path: dest.path)
            notify("\(entry.name) güncellendi", "Sürüm \(entry.build) kuruldu.")
        }
    }

    /// Swaps the bundle while nothing runs it. Keeps the old copy until the new one is in place.
    private static func replaceClosed(_ dest: URL, with newApp: URL) -> Bool {
        let fm = FileManager.default
        let old = dest.deletingLastPathComponent().appendingPathComponent(dest.lastPathComponent + ".old")
        try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: old)
        if fm.fileExists(atPath: dest.path) {
            guard (try? fm.moveItem(at: dest, to: old)) != nil else { return false }
        }
        do { try fm.moveItem(at: newApp, to: dest) } catch {
            if fm.fileExists(atPath: old.path) { try? fm.moveItem(at: old, to: dest) }
            return false
        }
        try? fm.removeItem(at: old)
        run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", dest.path])
        return true
    }

    private static func notify(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    @discardableResult
    private static func run(_ tool: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}
