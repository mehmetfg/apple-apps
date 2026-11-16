// Uygulamalar page (2026-11-14): every app in the registry (Uygulamalar/apps.json, built by apps.py) in one place,
// grouped by where it stands (in progress · waiting · finished · idea · dropped) or by platform. The Apple side is
// shown device by device (iPhone · iPad · Mac · Watch · TV · Vision), read from each project's own files; the Android
// side is tracked apart: an app can be planned for Android, in progress there, done there, or paired with the app
// that is its Android twin. Those marks and a manual phase live in Uygulamalar/platforms.json (this app writes it,
// apps.py never touches it, iCloud carries it to the other Mac).
import SwiftUI
import AppKit

// MARK: Model

struct AppIdeaNote: Decodable, Hashable, Identifiable {
    var title = "", text = "", record = "", date = ""
    var id: String { record + "|" + title }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        func s(_ k: CodingKeys) -> String { (try? c.decode(String.self, forKey: k)) ?? "" }
        title = s(.title); text = s(.text); record = s(.record); date = s(.date)
    }
    enum CodingKeys: String, CodingKey { case title, text, record, date }
}

struct AppRecord: Decodable, Identifiable, Hashable {
    var id: String
    var name = "", platform = "", purpose = "", status = "active", commercial = "", storeNote = "", note = ""
    var path = "", started = "", lastActivity = ""
    var open: [String] = [], done: [String] = [], talk: [String] = []
    var ideas: [AppIdeaNote] = []

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        func s(_ k: CodingKeys) -> String { (try? c.decode(String.self, forKey: k)) ?? "" }
        func a(_ k: CodingKeys) -> [String] { (try? c.decode([String].self, forKey: k)) ?? [] }
        id = try c.decode(String.self, forKey: .id)
        name = s(.name); platform = s(.platform); purpose = s(.purpose); commercial = s(.commercial)
        storeNote = s(.store_note); note = s(.note); path = s(.path); started = s(.started); lastActivity = s(.last_activity)
        status = s(.status).isEmpty ? "active" : s(.status)
        open = a(.open); done = a(.done); talk = a(.talk)
        ideas = (try? c.decode([AppIdeaNote].self, forKey: .ideas)) ?? []
    }
    enum CodingKeys: String, CodingKey {
        case id, name, platform, purpose, status, commercial, store_note, note, path, started, last_activity, open, done, talk, ideas
    }

    var title: String { name.isEmpty ? id : name }
    var isPaid: Bool { commercial == "paid" }
    var daysSinceActivity: Int? {
        guard let d = Zaman.formatter("yyyy-MM-dd", posix: true).date(from: String(lastActivity.prefix(10))) else { return nil }
        return max(0, Int(Date().timeIntervalSince(d) / 86400))
    }
}

private struct AppCatalogFile: Decodable {
    var apps: [AppRecord] = []
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        apps = (try? c.decode([AppRecord].self, forKey: .apps)) ?? []
    }
    enum CodingKeys: String, CodingKey { case apps }
}

enum AppDevice: String, CaseIterable, Identifiable, Codable {
    case iphone, ipad, mac, watch, tv, vision, web, android, androidTV = "android-tv"
    var id: String { rawValue }
    var name: String {
        switch self {
        case .iphone: "iPhone"; case .ipad: "iPad"; case .mac: "Mac"; case .watch: "Watch"; case .tv: "Apple TV"
        case .vision: "Vision Pro"; case .web: "Web"; case .android: "Android telefon · tablet"; case .androidTV: "Android TV"
        }
    }
    var short: String {
        switch self {
        case .android: "Telefon · tablet"; case .androidTV: "TV"; default: name
        }
    }
    var symbol: String {
        switch self {
        case .iphone: "iphone"; case .ipad: "ipad"; case .mac: "laptopcomputer"; case .watch: "applewatch"
        case .tv: "appletv"; case .vision: "visionpro"; case .web: "globe"; case .android: "candybarphone"; case .androidTV: "tv"
        }
    }
    static let apple: [AppDevice] = [.iphone, .ipad, .mac, .watch, .tv, .vision]
    static let androidSide: [AppDevice] = [.android, .androidTV]
    var isApple: Bool { Self.apple.contains(self) }
    var isAndroid: Bool { Self.androidSide.contains(self) }
}

/// Where an app stands. Worked out from the registry and the last activity unless set by hand.
enum AppPhase: String, CaseIterable, Identifiable {
    case active, waiting, done, idea, retired
    var id: String { rawValue }
    var name: String {
        switch self {
        case .active: "Geliştiriliyor"; case .waiting: "Bekliyor"; case .done: "Tamamlandı"; case .idea: "Fikir"; case .retired: "Bırakıldı"
        }
    }
    var note: String {
        switch self {
        case .active: "Son 7 günde üzerinde çalışılanlar"
        case .waiting: "Kurulu ama bir haftadır dokunulmamış"
        case .done: "Bitti ya da yayında: elle işaretlenenler"
        case .idea: "Henüz kurulmamış uygulamalar"
        case .retired: "Bırakılanlar"
        }
    }
    var symbol: String {
        switch self {
        case .active: "bolt.fill"; case .waiting: "pause.circle"; case .done: "checkmark.seal.fill"; case .idea: "lightbulb"; case .retired: "archivebox"
        }
    }
    var color: Color {
        switch self {
        case .active: Ink.ember; case .waiting: Color(hex: "#E09B2D"); case .done: Color(hex: "#23915E")
        case .idea: Color(hex: "#7A4FD0"); case .retired: Ink.faint
        }
    }
}

/// The Android side of an app.
enum AndroidPlan: String, CaseIterable, Identifiable {
    case none, planned, building, done
    var id: String { rawValue }
    var name: String {
        switch self {
        case .none: "Android yok"; case .planned: "Android'e de yapılacak"; case .building: "Android'de sürüyor"; case .done: "Android'de var"
        }
    }
    var short: String {
        switch self { case .none: "—"; case .planned: "planlı"; case .building: "sürüyor"; case .done: "var" }
    }
    var symbol: String {
        switch self { case .none: "minus"; case .planned: "calendar.badge.plus"; case .building: "hammer"; case .done: "checkmark.circle.fill" }
    }
    var color: Color {
        switch self { case .none: Ink.faint; case .planned: Color(hex: "#2F6FEB"); case .building: Color(hex: "#E09B2D"); case .done: Color(hex: "#23915E") }
    }
}

/// One app's hand-set marks (Uygulamalar/platforms.json).
struct AppMarks: Codable, Equatable {
    var phase: String?
    var android: String?
    /// Another registry app that is this one's twin on the other side (an Android app for an iOS one, or back).
    var pair: String?
    var devices: [AppDevice]?
    var note: String?
}

// MARK: Store

@MainActor final class AppsHub: ObservableObject {
    static let shared = AppsHub()
    @Published private(set) var apps: [AppRecord] = []
    @Published private(set) var marks: [String: AppMarks] = [:]
    /// Devices read from each project's files (project.yml, project.pbxproj, AndroidManifest.xml).
    @Published private(set) var detected: [String: Set<AppDevice>] = [:]
    private var catalogDate: Date?
    private var marksDate: Date?
    private var scanned = false

    private func catalogURL(_ kok: URL) -> URL { kok.appendingPathComponent("Uygulamalar/apps.json") }
    private func marksURL(_ kok: URL) -> URL { kok.appendingPathComponent("Uygulamalar/platforms.json") }
    private static func date(_ u: URL) -> Date? { (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }

    func load(_ kok: URL) {
        let cu = catalogURL(kok), mu = marksURL(kok)
        let ct = Self.date(cu)
        if ct != catalogDate || apps.isEmpty {
            catalogDate = ct
            if let v = try? Data(contentsOf: cu), let f = try? JSONDecoder().decode(AppCatalogFile.self, from: v) {
                apps = f.apps
                scanned = false
            }
        }
        let mt = Self.date(mu)
        if mt != marksDate {
            marksDate = mt
            if let v = try? Data(contentsOf: mu), let f = try? JSONDecoder().decode([String: AppMarks].self, from: v) { marks = f }
        }
        if !scanned, !apps.isEmpty {
            scanned = true
            let list = apps.map { ($0.id, $0.path) }
            Task {
                let r = await Task.detached(priority: .utility) { Self.scan(list) }.value
                detected = r
            }
        }
    }

    /// Preview mode: the device scan on the spot.
    func scanNow() { detected = Self.scan(apps.map { ($0.id, $0.path) }); scanned = true }

    func app(_ id: String) -> AppRecord? { apps.first { $0.id == id } }

    func phase(_ a: AppRecord) -> AppPhase {
        if let p = marks[a.id]?.phase.flatMap(AppPhase.init(rawValue:)) { return p }
        switch a.status {
        case "idea": return .idea
        case "retired": return .retired
        case "done", "released", "shipped", "live": return .done
        case "paused": return .waiting
        default:
            guard let d = a.daysSinceActivity else { return .waiting }
            return d <= 7 ? .active : .waiting
        }
    }

    func android(_ a: AppRecord) -> AndroidPlan {
        if let p = marks[a.id]?.android.flatMap(AndroidPlan.init(rawValue:)) { return p }
        return devices(a).contains(where: \.isAndroid) ? .done : .none
    }

    /// Hand-set devices win; otherwise what the project files say, plus what the registry's platform text says.
    func devices(_ a: AppRecord) -> Set<AppDevice> {
        if let d = marks[a.id]?.devices, !d.isEmpty { return Set(d) }
        var s = detected[a.id] ?? []
        let p = a.platform.lowercased()
        if p.contains("android tv") { s.insert(.androidTV) } else if p.contains("android") { s.insert(.android) }
        if p.contains("macos") { s.insert(.mac) }
        if p.contains("watchos") { s.insert(.watch) }
        if p.contains("web") { s.insert(.web) }
        if p.contains("ios"), !s.contains(.iphone), !s.contains(.ipad) { s.insert(.iphone) }
        return s
    }

    func setPhase(_ id: String, _ p: AppPhase?, _ kok: URL) { write(kok) { $0[id, default: AppMarks()].phase = p?.rawValue } }
    func setAndroid(_ id: String, _ p: AndroidPlan?, _ kok: URL) { write(kok) { $0[id, default: AppMarks()].android = p?.rawValue } }
    func setPair(_ id: String, _ other: String?, _ kok: URL) {
        write(kok) { m in
            if let old = m[id]?.pair, old != other { m[old]?.pair = nil }
            m[id, default: AppMarks()].pair = other
            if let other { m[other, default: AppMarks()].pair = id }
        }
    }

    /// Read again right before writing: the other Mac may have changed it in between. Empty marks are dropped.
    private func write(_ kok: URL, _ change: (inout [String: AppMarks]) -> Void) {
        marksDate = nil
        load(kok)
        var m = marks
        change(&m)
        m = m.filter { $0.value != AppMarks() }
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(m) {
            try? FileManager.default.createDirectory(at: marksURL(kok).deletingLastPathComponent(), withIntermediateDirectories: true)
            try? d.write(to: marksURL(kok), options: .atomic)
        }
        marks = m
        marksDate = Self.date(marksURL(kok))
    }

    // MARK: Device scan

    nonisolated private static let skip: Set<String> = ["build", "DerivedData", "node_modules", ".git", "Pods", ".build", "spikes", "store", "site", "docs"]

    nonisolated static func scan(_ list: [(String, String)]) -> [String: Set<AppDevice>] {
        var out: [String: Set<AppDevice>] = [:]
        let fm = FileManager.default
        for (id, path) in list where !path.isEmpty {
            let root = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            guard fm.fileExists(atPath: root.path) else { continue }
            var found: Set<AppDevice> = []
            var stack: [(URL, Int)] = [(root, 0)]
            var looked = 0
            while let (dir, depth) = stack.popLast(), looked < 4000 {
                guard let kids = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
                for u in kids {
                    looked += 1
                    let name = u.lastPathComponent
                    let isDir = (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    if isDir {
                        if name.hasSuffix(".xcodeproj") {
                            read(u.appendingPathComponent("project.pbxproj"), into: &found)
                        } else if depth < 3, !skip.contains(name), !name.hasSuffix(".xcassets"), !name.hasSuffix(".lproj") {
                            stack.append((u, depth + 1))
                        }
                    } else if name == "project.yml" || name == "AndroidManifest.xml" {
                        read(u, into: &found)
                    }
                }
            }
            if !found.isEmpty { out[id] = found }
        }
        return out
    }

    nonisolated private static func read(_ u: URL, into s: inout Set<AppDevice>) {
        guard let d = try? Data(contentsOf: u), let text = String(data: d, encoding: .utf8) else { return }
        if u.lastPathComponent == "AndroidManifest.xml" {
            s.insert(text.contains("leanback") ? .androidTV : .android)
            return
        }
        let low = text.lowercased()
        // TARGETED_DEVICE_FAMILY = "1,2" (pbxproj) or TARGETED_DEVICE_FAMILY: "1,2" (XcodeGen)
        if let re = try? NSRegularExpression(pattern: #"TARGETED_DEVICE_FAMILY[\s:=]+"?([0-9,]+)"#) {
            for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let r = Range(m.range(at: 1), in: text) else { continue }
                let fam = text[r].split(separator: ",")
                if fam.contains("1") { s.insert(.iphone) }
                if fam.contains("2") { s.insert(.ipad) }
                if fam.contains("3") { s.insert(.tv) }
                if fam.contains("4") { s.insert(.watch) }
                if fam.contains("7") { s.insert(.vision) }
            }
        }
        if low.contains("sdkroot = macosx") || low.contains("platform: macos") || low.contains("supports_maccatalyst = yes")
            || (low.contains("supporteddestinations") && low.contains("macos")) { s.insert(.mac) }
        if low.contains("sdkroot = watchos") || low.contains("platform: watchos") { s.insert(.watch) }
        if low.contains("sdkroot = appletvos") || low.contains("platform: tvos") { s.insert(.tv) }
        if low.contains("sdkroot = xros") || low.contains("platform: visionos") { s.insert(.vision) }
        if (low.contains("sdkroot = iphoneos") || low.contains("platform: ios")), !s.contains(.ipad) { s.insert(.iphone) }
    }
}

// MARK: Page

struct AppsView: View {
    @EnvironmentObject var depo: Depo
    @ObservedObject private var hub = AppsHub.shared
    @Binding var selection: String?
    let query: String
    @AppStorage("appsGrouping") private var grouping = "phase"
    @AppStorage("appsClosed") private var closedRaw = "idea,retired"
    @State private var device: AppDevice?
    @State private var androidFilter: AndroidPlan?

    private var closed: Set<String> { Set(closedRaw.split(separator: ",").map(String.init)) }

    private var shown: [AppRecord] {
        let q = Arama.katla(query).split(separator: " ")
        return hub.apps.filter { a in
            if let device, !hub.devices(a).contains(device) { return false }
            if let androidFilter, hub.android(a) != androidFilter { return false }
            if !q.isEmpty {
                let s = Arama.katla([a.name, a.id, a.purpose, a.platform].joined(separator: " "))
                if !q.allSatisfy({ s.contains($0) }) { return false }
            }
            return true
        }
        .sorted { x, y in
            let dx = x.daysSinceActivity ?? 9999, dy = y.daysSinceActivity ?? 9999
            return dx != dy ? dx < dy : x.title.localizedCompare(y.title) == .orderedAscending
        }
    }

    private var groups: [(key: String, title: String, note: String, symbol: String, color: Color, apps: [AppRecord])] {
        let l = shown
        if grouping == "platform" {
            func g(_ k: String, _ t: String, _ n: String, _ sym: String, _ c: Color, _ f: (Set<AppDevice>) -> Bool) -> (String, String, String, String, Color, [AppRecord]) {
                (k, t, n, sym, c, l.filter { f(hub.devices($0)) })
            }
            let list: [(String, String, String, String, Color, [AppRecord])] = [
                g("both", "Apple + Android", "İki tarafta da olanlar", "arrow.left.arrow.right", Color(hex: "#23915E")) { d in d.contains(where: \.isApple) && d.contains(where: \.isAndroid) },
                g("apple", "Yalnız Apple", "iPhone, iPad, Mac, Watch…", "apple.logo", Ink.text) { d in d.contains(where: \.isApple) && !d.contains(where: \.isAndroid) },
                g("android", "Yalnız Android", "Telefon, tablet, TV", "candybarphone", Color(hex: "#3DDC84")) { d in d.contains(where: \.isAndroid) && !d.contains(where: \.isApple) },
                g("web", "Web", "Tarayıcıda çalışanlar", "globe", Color(hex: "#2F6FEB")) { d in d == [.web] },
                g("none", "Platformu yok", "Fikirler ve kaydı eksik olanlar", "questionmark.circle", Ink.faint) { d in d.isEmpty },
            ]
            return list.filter { !$0.5.isEmpty }.map { (key: $0.0, title: $0.1, note: $0.2, symbol: $0.3, color: $0.4, apps: $0.5) }
        }
        return AppPhase.allCases.compactMap { p in
            let x = l.filter { hub.phase($0) == p }
            return x.isEmpty ? nil : (key: p.rawValue, title: p.name, note: p.note, symbol: p.symbol, color: p.color, apps: x)
        }
    }

    var body: some View {
        if hub.apps.isEmpty {
            ContentUnavailableView("Uygulama kaydı yok", systemImage: "square.grid.2x2",
                                   description: Text("Uygulamalar/apps.json bulunamadı. Bir işleme koşusu apps.py'yi çalıştırır."))
                .onAppear { hub.load(depo.kok) }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    ecosystem
                    toolbar
                    if groups.isEmpty {
                        ContentUnavailableView("Bu süzgeçte uygulama yok", systemImage: "line.3.horizontal.decrease")
                    }
                    ForEach(groups, id: \.key) { g in group(g) }
                }
                .padding(.horizontal, 28).padding(.vertical, 24)
                .frame(maxWidth: 1100, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Ink.paper)
            .onAppear { hub.load(depo.kok) }
        }
    }

    // MARK: Header

    private var header: some View {
        let all = hub.apps
        let counts = Dictionary(grouping: all, by: { hub.phase($0) }).mapValues(\.count)
        return HStack(alignment: .center, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Uygulamalar").font(.system(size: 40, weight: .bold, design: .serif))
                Text("\(all.count) uygulama · \(all.filter(\.isPaid).count) ücretli. Kıvılcım'dan başlayan bütün hat, tek yerde.")
                    .font(Ink.serif(.title3)).foregroundStyle(Ink.secondary).lineLimit(2)
            }
            Spacer()
            HStack(spacing: 16) {
                ForEach([AppPhase.active, .waiting, .done, .idea]) { p in
                    VStack(spacing: 2) {
                        Text("\(counts[p] ?? 0)").font(.system(size: 30, weight: .bold, design: .serif)).monospacedDigit().foregroundStyle(p.color)
                        Label(p.name, systemImage: p.symbol).font(.caption.weight(.semibold)).foregroundStyle(p.color)
                    }
                }
            }
        }
    }

    // MARK: Ecosystem (Apple · Android · Web)

    private var ecosystem: some View {
        HStack(alignment: .top, spacing: 14) {
            sideCard("Apple ekosistemi", "apple.logo", Ink.text) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                    ForEach(AppDevice.apple) { d in deviceChip(d) }
                }
            }
            sideCard("Android", "candybarphone", Color(hex: "#3DDC84")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) { ForEach(AppDevice.androidSide) { d in deviceChip(d) } }
                    HStack(spacing: 8) {
                        ForEach([AndroidPlan.planned, .building, .done]) { p in androidChip(p) }
                    }
                }
            }
            .frame(maxWidth: 340)
            sideCard("Web", "globe", Color(hex: "#2F6FEB")) { deviceChip(.web) }
                .frame(maxWidth: 150)
        }
    }

    private func sideCard<C: View>(_ title: String, _ symbol: String, _ color: Color, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.headline).foregroundStyle(color)
            content()
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Ink.line) }
    }

    private func deviceChip(_ d: AppDevice) -> some View {
        let n = hub.apps.filter { hub.devices($0).contains(d) }.count
        let on = device == d
        return Button { withAnimation(.snappy) { device = on ? nil : d } } label: {
            VStack(alignment: .leading, spacing: 3) {
                Image(systemName: d.symbol).font(.title3)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(n)").font(.system(size: 20, weight: .bold, design: .serif)).monospacedDigit()
                    Text(d.short).font(.caption).lineLimit(1)
                }
            }
            .foregroundStyle(n == 0 ? Ink.faint : on ? Ink.ember : Ink.text)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? Ink.ember.opacity(0.13) : Ink.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(on ? Ink.ember : .clear, lineWidth: 1.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(n == 0 ? "\(d.name): henüz uygulama yok" : "Yalnız \(d.name) uygulamalarını göster")
    }

    private func androidChip(_ p: AndroidPlan) -> some View {
        let n = hub.apps.filter { hub.android($0) == p }.count
        let on = androidFilter == p
        return Button { withAnimation(.snappy) { androidFilter = on ? nil : p } } label: {
            HStack(spacing: 4) {
                Image(systemName: p.symbol)
                Text("\(p.short) \(n)").monospacedDigit()
            }
            .font(.callout.weight(on ? .semibold : .regular))
            .foregroundStyle(n == 0 ? Ink.faint : p.color)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Capsule().fill(on ? p.color.opacity(0.16) : Ink.surface2.opacity(0.6)))
            .overlay { Capsule().strokeBorder(on ? p.color : .clear) }
        }
        .buttonStyle(.plain)
        .help(p.name)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("Grupla", selection: $grouping) {
                Text("Duruma göre").tag("phase"); Text("Platforma göre").tag("platform")
            }
            .pickerStyle(.segmented).fixedSize().labelsHidden()
            if let device {
                filterTag(device.name, device.symbol) { self.device = nil }
            }
            if let androidFilter {
                filterTag(androidFilter.name, androidFilter.symbol) { self.androidFilter = nil }
            }
            Spacer()
            Text("Sağ tık: durum ve Android işareti").font(.caption).foregroundStyle(Ink.faint)
        }
    }

    private func filterTag(_ t: String, _ symbol: String, _ clear: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy) { clear() } } label: {
            HStack(spacing: 5) { Image(systemName: symbol); Text(t); Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                .font(.callout.weight(.semibold)).foregroundStyle(Ink.ember)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Ink.ember.opacity(0.13)))
        }
        .buttonStyle(.plain)
    }

    // MARK: Groups and rows

    private func toggle(_ key: String) {
        var s = closed
        if s.contains(key) { s.remove(key) } else { s.insert(key) }
        withAnimation(.snappy) { closedRaw = s.sorted().joined(separator: ",") }
    }

    private func group(_ g: (key: String, title: String, note: String, symbol: String, color: Color, apps: [AppRecord])) -> some View {
        let isOpen = !closed.contains(g.key)
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Ink.secondary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                Image(systemName: g.symbol).font(.title3).foregroundStyle(g.color).frame(width: 24)
                Text(g.title).font(Ink.serif(.title2, .bold))
                Text("\(g.apps.count)").font(.title3.monospacedDigit()).foregroundStyle(Ink.faint)
                Text(g.note).font(.callout).foregroundStyle(Ink.secondary).lineLimit(1)
                Spacer()
                if !isOpen {
                    Text(g.apps.prefix(5).map(\.title).joined(separator: " · ") + (g.apps.count > 5 ? " …" : ""))
                        .font(.caption).foregroundStyle(Ink.faint).lineLimit(1)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .contentShape(Rectangle())
            .onTapGesture { toggle(g.key) }
            if isOpen {
                Rectangle().fill(Ink.line).frame(height: 1)
                VStack(spacing: 0) {
                    ForEach(Array(g.apps.enumerated()), id: \.element.id) { i, a in
                        if i > 0 { Rectangle().fill(Ink.line.opacity(0.6)).frame(height: 1).padding(.leading, 50) }
                        AppRow(a: a, selected: selection == a.id)
                            .onTapGesture { selection = a.id }
                            .contextMenu { AppMenu(a: a) }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(Ink.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Ink.line) }
    }
}

/// Tatbik items that belong to an app (through the program → app table).
@MainActor func tatbikItems(for appID: String, _ t: TatbikState) -> [TatbikItem] {
    let progs = Set(t.programlar.filter { $0.apps.contains(appID) }.map(\.id))
    return t.maddeler.filter { progs.contains($0.program) }
}

func activityText(_ days: Int?) -> String {
    guard let d = days else { return "tarih yok" }
    switch d { case 0: return "bugün"; case 1: return "dün"; default: return "\(d) gün önce" }
}

struct AppRow: View {
    @EnvironmentObject var depo: Depo
    @ObservedObject private var hub = AppsHub.shared
    let a: AppRecord
    var selected = false
    @State private var hover = false

    var body: some View {
        let phase = hub.phase(a)
        let devices = hub.devices(a)
        let items = tatbikItems(for: a.id, depo.tatbik)
        let openItems = items.filter { !$0.status.isClosed }.count
        let android = hub.android(a)
        HStack(spacing: 12) {
            Circle().fill(phase.color).frame(width: 10, height: 10).padding(.leading, 6)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(a.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    if a.isPaid { badge("ücretli", Ink.gold) }
                    if let pair = hub.marks[a.id]?.pair, let p = hub.app(pair) {
                        Label(p.title, systemImage: "link").font(.caption).foregroundStyle(Ink.secondary).lineLimit(1)
                    }
                }
                if !a.purpose.isEmpty {
                    Text(a.purpose).font(.caption).foregroundStyle(Ink.faint).lineLimit(1)
                }
            }
            Spacer(minLength: 10)
            HStack(spacing: 5) {
                ForEach(AppDevice.allCases.filter { devices.contains($0) }) { d in
                    Image(systemName: d.symbol).foregroundStyle(d.isAndroid ? Color(hex: "#3DDC84") : Ink.secondary).help(d.name)
                }
                if android == .planned || android == .building {
                    Image(systemName: android.symbol).foregroundStyle(android.color).help(android.name)
                }
            }
            .font(.callout)
            .frame(minWidth: 70, alignment: .trailing)
            Group {
                if !items.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "checklist")
                        Text("\(openItems)/\(items.count)").monospacedDigit()
                    }
                    .foregroundStyle(openItems > 0 ? TatbikStatus.acik.color : Ink.faint)
                    .help("Tatbik: \(openItems) açık madde, toplam \(items.count)")
                } else if !a.open.isEmpty {
                    HStack(spacing: 3) { Image(systemName: "circle"); Text("\(a.open.count)").monospacedDigit() }
                        .foregroundStyle(Ink.secondary).help("\(a.open.count) açık kayıt")
                } else {
                    Text("")
                }
            }
            .font(.callout).frame(width: 64, alignment: .trailing)
            Text(activityText(a.daysSinceActivity)).font(.caption.monospacedDigit())
                .foregroundStyle((a.daysSinceActivity ?? 99) <= 7 ? Ink.secondary : Ink.faint)
                .frame(width: 78, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(selected ? Ink.ember.opacity(0.10) : hover ? Ink.surface2.opacity(0.7) : .clear)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }

    private func badge(_ t: String, _ c: Color) -> some View {
        Text(t).font(.caption2.weight(.semibold)).foregroundStyle(c)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill(c.opacity(0.13)))
    }
}

struct AppMenu: View {
    @EnvironmentObject var depo: Depo
    @ObservedObject private var hub = AppsHub.shared
    let a: AppRecord
    var body: some View {
        Menu("Durum") {
            Button("Kendiliğinden (son çalışmaya göre)") { hub.setPhase(a.id, nil, depo.kok) }
            Divider()
            ForEach(AppPhase.allCases) { p in
                Button { hub.setPhase(a.id, p, depo.kok) } label: {
                    Label(p.name, systemImage: hub.marks[a.id]?.phase == p.rawValue ? "checkmark" : p.symbol)
                }
            }
        }
        Menu("Android") {
            ForEach(AndroidPlan.allCases) { p in
                Button { hub.setAndroid(a.id, p == .none ? nil : p, depo.kok) } label: {
                    Label(p.name, systemImage: hub.android(a) == p ? "checkmark" : p.symbol)
                }
            }
        }
        if !a.path.isEmpty {
            Divider()
            Button("Finder'da göster") { revealApp(a) }
        }
    }
}

func revealApp(_ a: AppRecord) {
    let u = URL(fileURLWithPath: (a.path as NSString).expandingTildeInPath)
    if FileManager.default.fileExists(atPath: u.path) { NSWorkspace.shared.activateFileViewerSelecting([u]) }
}

// MARK: Detail (inspector)

struct AppDetail: View {
    @EnvironmentObject var depo: Depo
    @ObservedObject private var hub = AppsHub.shared
    let id: String
    @Binding var goRecord: String?
    var close: (() -> Void)?

    var body: some View {
        if let a = hub.app(id) {
            let phase = hub.phase(a)
            let devices = hub.devices(a)
            let items = tatbikItems(for: a.id, depo.tatbik)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(phase.name, systemImage: phase.symbol).font(.callout.weight(.semibold)).foregroundStyle(phase.color)
                            Spacer()
                            if let close {
                                Button(action: close) { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(Ink.faint) }
                                    .buttonStyle(.plain).help("Paneli kapat")
                            }
                        }
                        Text(a.title).font(Ink.serif(.largeTitle, .bold)).fixedSize(horizontal: false, vertical: true)
                        if !a.purpose.isEmpty { Text(a.purpose).font(.body).foregroundStyle(Ink.secondary).fixedSize(horizontal: false, vertical: true) }
                        HStack(spacing: 8) {
                            if !a.platform.isEmpty { chip(a.platform) }
                            if a.isPaid { chip("ücretli") }
                            if !a.started.isEmpty { chip("başladı \(a.started)") }
                            chip("son çalışma: \(activityText(a.daysSinceActivity))")
                        }
                        if !a.storeNote.isEmpty { Text(a.storeNote).font(.callout).foregroundStyle(Ink.secondary) }
                        if !a.note.isEmpty { Text(a.note).font(.callout).foregroundStyle(Ink.secondary) }
                    }

                    platforms(a, devices)

                    if !items.isEmpty { tatbik(items) }

                    records("Açık kayıtlar", a.open)
                    if !a.ideas.isEmpty { ideas(a.ideas) }
                    records("Konuşulanlar", Array(a.talk.prefix(8)))
                    records("Yapılanlar", a.done)

                    HStack {
                        Menu("Durumu değiştir") { AppMenu(a: a) }.fixedSize()
                        Spacer()
                        if !a.path.isEmpty {
                            Button { revealApp(a) } label: { Label("Finder'da göster", systemImage: "folder") }
                        }
                    }
                }
                .padding(22)
            }
            .background(Ink.paper)
        } else {
            ContentUnavailableView("Bir uygulama seç", systemImage: "square.grid.2x2",
                                   description: Text("Maddeleri, kayıtları, fikirleri ve platformları burada açılır."))
        }
    }

    private func platforms(_ a: AppRecord, _ devices: Set<AppDevice>) -> some View {
        let android = hub.android(a)
        let pair = hub.marks[a.id]?.pair.flatMap { hub.app($0) }
        return Card(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Platformlar").font(.headline)
                VStack(alignment: .leading, spacing: 6) {
                    Label("Apple ekosistemi", systemImage: "apple.logo").font(.callout.weight(.semibold)).foregroundStyle(Ink.secondary)
                    HStack(spacing: 6) {
                        ForEach(AppDevice.apple) { d in
                            let on = devices.contains(d)
                            VStack(spacing: 3) {
                                Image(systemName: d.symbol).font(.title3)
                                Text(d.short).font(.caption2).lineLimit(1)
                            }
                            .foregroundStyle(on ? Ink.text : Ink.faint.opacity(0.6))
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 8).fill(on ? Ink.surface2 : .clear))
                            .help(on ? "\(d.name): var" : "\(d.name): yok")
                        }
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Label("Android", systemImage: "candybarphone").font(.callout.weight(.semibold)).foregroundStyle(Color(hex: "#3DDC84"))
                    HStack(spacing: 10) {
                        Menu {
                            ForEach(AndroidPlan.allCases) { p in
                                Button { hub.setAndroid(a.id, p == .none ? nil : p, depo.kok) } label: {
                                    Label(p.name, systemImage: android == p ? "checkmark" : p.symbol)
                                }
                            }
                        } label: { Label(android.name, systemImage: android.symbol) }
                        .fixedSize()
                        Menu {
                            Button("Eşleşme yok") { hub.setPair(a.id, nil, depo.kok) }
                            Divider()
                            ForEach(hub.apps.filter { $0.id != a.id && hub.phase($0) != .idea }.sorted { $0.title < $1.title }) { o in
                                Button(o.title) { hub.setPair(a.id, o.id, depo.kok) }
                            }
                        } label: { Label(pair.map { "Eşi: \($0.title)" } ?? "Öteki taraftaki eşi…", systemImage: "link") }
                        .fixedSize()
                        .help("Aynı süreç öteki tarafta ayrı bir uygulamaysa ikisini bağla: biri değişince ötekine bakarsın")
                    }
                    if let pair {
                        Text("\(pair.title) · \(hub.phase(pair).name) · son çalışma \(activityText(pair.daysSinceActivity))")
                            .font(.caption).foregroundStyle(Ink.secondary)
                    }
                    if devices.contains(where: \.isAndroid) {
                        Text("Bu uygulamanın kendisi Android'de: " + AppDevice.androidSide.filter { devices.contains($0) }.map(\.name).joined(separator: ", "))
                            .font(.caption).foregroundStyle(Ink.secondary)
                    }
                }
            }
        }
    }

    private func tatbik(_ items: [TatbikItem]) -> some View {
        let sorted = items.sorted(by: TatbikView.smart)
        return Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Tatbik").font(.headline)
                    Spacer()
                    ForEach(TatbikStatus.allCases) { s in
                        let n = items.filter { $0.status == s }.count
                        if n > 0 { Label("\(n)", systemImage: s.symbol).font(.callout.monospacedDigit()).foregroundStyle(s.color) }
                    }
                }
                StackedBar(items: items).frame(height: 6)
                ForEach(sorted) { m in
                    HStack(spacing: 8) {
                        Image(systemName: m.status.symbol).foregroundStyle(m.status.color)
                        Text(m.baslik).lineLimit(2).foregroundStyle(m.status.isClosed ? Ink.secondary : Ink.text)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { depo.openTatbik = m.id }
                    .contextMenu { TatbikMenu(m: m) }
                }
            }
        }
    }

    @ViewBuilder private func records(_ title: String, _ ids: [String]) -> some View {
        let recs = ids.compactMap { id in depo.ogeler.first { $0.id == id } }
        if !recs.isEmpty {
            Card(padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(title) · \(recs.count)").font(.headline)
                    ForEach(recs) { o in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(o.baslik).lineLimit(2)
                                Text(o.tarih.prefix(16).replacingOccurrences(of: "T", with: " ")).font(.caption2).foregroundStyle(Ink.faint)
                            }
                            Spacer()
                            Button("Kayda git") { goRecord = o.id }.controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private func ideas(_ l: [AppIdeaNote]) -> some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Fikirler · \(l.count)").font(.headline)
                ForEach(l.sorted { $0.date > $1.date }) { i in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(i.title).font(.body.weight(.semibold))
                            Spacer()
                            Text(i.date).font(.caption2.monospacedDigit()).foregroundStyle(Ink.faint)
                        }
                        if !i.text.isEmpty { Text(i.text).font(.callout).foregroundStyle(Ink.secondary).fixedSize(horizontal: false, vertical: true) }
                    }
                }
            }
        }
    }

    private func chip(_ s: String) -> some View {
        Text(s).font(.caption).padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Ink.surface2)).foregroundStyle(Ink.secondary)
    }
}
