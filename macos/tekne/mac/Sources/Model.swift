import AppKit
import Combine
import SwiftUI

/// Glue: owns the store and the tracker, and recomputes the production numbers.
@MainActor
final class AppModel: ObservableObject {
    let store = Store()
    let tracker = Tracker()

    @Published var days: [DaySummary] = []
    @Published var todaySessions: [Session] = []
    @Published var selected: AreaID?
    @Published var windowStart: Int { didSet { UserDefaults.standard.set(windowStart, forKey: "tekne.start"); recompute() } }
    @Published var windowEnd: Int { didSet { UserDefaults.standard.set(windowEnd, forKey: "tekne.end"); recompute() } }

    private var disk: [Session] = []
    private var bag: Set<AnyCancellable> = []
    private var timer: Timer?

    init() {
        let d = UserDefaults.standard
        windowStart = d.object(forKey: "tekne.start") as? Int ?? 7
        windowEnd = d.object(forKey: "tekne.end") as? Int ?? 23
        tracker.$revision.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.reloadDisk() }
        }.store(in: &bag)
        tracker.$auto.sink { [weak self] _ in Task { @MainActor in self?.recompute() } }.store(in: &bag)
        tracker.$manual.sink { [weak self] _ in Task { @MainActor in self?.recompute() } }.store(in: &bag)
    }

    func start() {
        tracker.start()
        refreshAll()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshAll() }
        }
    }

    func refreshAll() {
        store.reload()
        reloadDisk()
    }

    /// Asks the PDM hub to rebuild state (reading %, words) and reloads when it is done.
    func runHub() {
        let hub = Vault.url("_bus/hub.py").path
        Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = ["python3", hub]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
            await MainActor.run { self.refreshAll() }
        }
    }

    private func reloadDisk() {
        disk = Ledger.sessions(since: Day.daysAgo(14))
        recompute()
    }

    func recompute() {
        let all = disk + tracker.openSessions
        days = Summaries.make(all, days: 14)
        let start = Day.daysAgo(0)
        todaySessions = Ledger.clip(all, from: start, to: Date()).sorted { $0.start < $1.start }
    }

    var today: DaySummary? { days.last }
    var windowMinutes: Int { max(60, (windowEnd - windowStart) * 60) }

    var elapsedMinutes: Int {
        let now = Date()
        let s = Day.cal.date(bySettingHour: windowStart, minute: 0, second: 0, of: now)!
        return min(windowMinutes, max(0, Int(now.timeIntervalSince(s) / 60)))
    }

    var percentOfDay: Double { Double(today?.production ?? 0) / Double(windowMinutes) * 100 }
    var percentSoFar: Double { Double(today?.production ?? 0) / Double(max(1, elapsedMinutes)) * 100 }

    func minutes(_ area: AreaID) -> Int { today?.byArea[area] ?? 0 }

    var dueCount: Int { store.cards.filter { $0.status == .due || $0.status == .late }.count }

    func open(_ area: AreaID) {
        let ws = NSWorkspace.shared
        switch area {
        case .body:
            if let u = store.journalURL,
               let enc = u.path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let url = URL(string: "obsidian://open?path=\(enc)") { ws.open(url) }
        case .english: openApp("Cümle")
        case .reading: openApp("Teoria")
        case .technical: if let u = URL(string: "tezgah://muhendis") { ws.open(u) }
        case .general: break
        }
    }

    private func openApp(_ name: String) {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/\(name).app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func toggleManual() {
        if tracker.manual != nil { tracker.stopManual() } else { tracker.startManual(area: lastArea, kind: lastKind) }
    }

    var lastArea: AreaID {
        get { AreaID(rawValue: UserDefaults.standard.string(forKey: "tekne.area") ?? "") ?? .general }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "tekne.area"); objectWillChange.send() }
    }

    var lastKind: ProductionKind {
        get { ProductionKind(rawValue: UserDefaults.standard.string(forKey: "tekne.kind") ?? "") ?? .written }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "tekne.kind"); objectWillChange.send() }
    }
}
