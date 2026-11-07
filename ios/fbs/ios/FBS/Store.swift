// Reads FBS/state/fbs.json from the vault, keeps the phone's own entries, writes them to
// FBS/phone/<device>/entries.json and puts added documents into FBS/phone/<device>/inbox.
import Foundation
import PDMBus
import SwiftUI
import UserNotifications

@MainActor
final class Store: ObservableObject {
    static let shared = Store()
    nonisolated static let folder = "02 - Eudomonia/Dış Unsurlar/Maddi/FBS"

    @Published var mac = FBSState()          // what the Mac knows (documents processed by Claude)
    @Published var mine = Entries()          // what this phone entered
    @Published var origin = ""
    @Published var vaultLinked = false
    @Published var inboxWaiting = 0
    @Published var lastWrite: String?

    let bus = PDMBus(app: "fbs")
    private let demo = ProcessInfo.processInfo.arguments.contains("-demoFinance")

    private var docs: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    private var cacheURL: URL { docs.appendingPathComponent("fbs.json") }
    private var entriesURL: URL { docs.appendingPathComponent("entries.json") }
    private var localInbox: URL {
        let u = docs.appendingPathComponent("inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d }()
    static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.keyEncodingStrategy = .convertToSnakeCase; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e
    }()

    // MARK: load

    func load() async {
        if demo { loadDemo(); return }
        if mine.contracts.isEmpty && mine.products.isEmpty && mine.records.isEmpty,
           let d = try? Data(contentsOf: entriesURL), let e = try? Self.decoder.decode(Entries.self, from: d) {
            mine = e
        }
        let data: Data? = await Task.detached(priority: .userInitiated) { Self.readVault("state/fbs.json") }.value
        vaultLinked = Self.vaultRoot() != nil
        if let data, let s = try? Self.decoder.decode(FBSState.self, from: data) {
            mac = s
            origin = "Vault · " + (s.generated.map { String($0.prefix(16)).replacingOccurrences(of: "T", with: " ") } ?? "")
            try? data.write(to: cacheURL, options: .atomic)
        } else if let d = try? Data(contentsOf: cacheURL), let s = try? Self.decoder.decode(FBSState.self, from: d) {
            mac = s
            origin = "Telefondaki kopya · " + (s.generated.map { String($0.prefix(10)) } ?? "")
        } else {
            origin = vaultLinked ? "Vault'ta henüz defter yok" : "Vault bağlı değil"
        }
        inboxWaiting = (try? FileManager.default.contentsOfDirectory(atPath: localInbox.path).count) ?? 0
    }

    // MARK: the merged view: Mac items plus this phone's entries

    var household: [Person] {
        let base = mac.household ?? []
        return base.isEmpty ? [Person(id: "me", name: "Ben")] : base
    }
    var contracts: [Contract] { (mac.contracts ?? []).filter { !$0.isPhone } + mine.contracts }
    var products: [Product] { (mac.products ?? []).filter { !$0.isPhone } + mine.products }
    var records: [Money] { (mac.records ?? []).filter { !$0.isPhone } + mine.records }
    var isEmpty: Bool { contracts.isEmpty && products.isEmpty && records.isEmpty }

    func personName(_ id: String?) -> String {
        guard let id else { return "—" }
        return household.first { $0.id == id }?.name ?? id
    }

    // MARK: edits (phone entries only)

    static func newID(_ prefix: String) -> String {
        prefix + "-" + Day.key(.now).replacingOccurrences(of: "-", with: "") + "-" + String(UUID().uuidString.prefix(6)).lowercased()
    }

    func save(_ c: Contract) {
        var c = c
        c.payMethod = Privacy.mask(c.payMethod); c.note = Privacy.mask(c.note); c.label = Privacy.mask(c.label)
        if c.created == nil { c.created = ISO8601DateFormatter().string(from: .now) }
        if let i = mine.contracts.firstIndex(where: { $0.id == c.id }) { mine.contracts[i] = c } else { mine.contracts.append(c) }
        bus.emit("finance.logged", subject: "contract:" + c.id, data: ["kind": .string(c.kind)])
        persist()
    }

    func save(_ p: Product) {
        var p = p
        p.note = Privacy.mask(p.note)
        if p.created == nil { p.created = ISO8601DateFormatter().string(from: .now) }
        if let i = mine.products.firstIndex(where: { $0.id == p.id }) { mine.products[i] = p } else { mine.products.append(p) }
        persist()
    }

    func save(_ m: Money) {
        var m = m
        m.method = Privacy.mask(m.method); m.note = Privacy.mask(m.note); m.party = Privacy.mask(m.party)
        if m.created == nil { m.created = ISO8601DateFormatter().string(from: .now) }
        if let i = mine.records.firstIndex(where: { $0.id == m.id }) { mine.records[i] = m } else { mine.records.append(m) }
        bus.emit("finance.logged", subject: "money:" + m.id, data: ["kind": .string(m.kind), "category": .string(m.category ?? "")])
        persist()
    }

    func delete(contract id: String) { mine.contracts.removeAll { $0.id == id }; persist() }
    func delete(product id: String) { mine.products.removeAll { $0.id == id }; persist() }
    func delete(money id: String) { mine.records.removeAll { $0.id == id }; persist() }

    /// "Ödendi": one output record for the contract's bill of that date.
    func markPaid(_ c: Contract, on date: Date, amount: Double? = nil) {
        save(Money(id: Self.newID("pay"), date: Day.key(date), kind: "output", category: Catalog.kind(c.kind).category,
                   amount: amount ?? c.amount ?? 0, currency: c.currency, party: c.provider, contract: c.id, method: c.payMethod, source: "telefon"))
    }

    private func persist() {
        mine.updated = ISO8601DateFormatter().string(from: .now)
        guard !demo, let data = try? Self.encoder.encode(mine) else { return }
        try? data.write(to: entriesURL, options: .atomic)
        Task { await pushEntries(data); await scheduleReminders() }
    }

    /// The phone owns its file in the vault: it is replaced as a whole.
    func pushEntries(_ data: Data? = nil) async {
        guard !demo, let data = data ?? (try? Self.encoder.encode(mine)) else { return }
        let ok: Bool = await Task.detached(priority: .utility) {
            Self.withFolder { dir -> Bool? in
                let target = dir.appendingPathComponent(Self.phoneFolder, isDirectory: true)
                try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                let file = target.appendingPathComponent("entries.json")
                var err: NSError?
                var wrote = false
                NSFileCoordinator().coordinate(writingItemAt: file, options: .forReplacing, error: &err) { u in
                    wrote = (try? data.write(to: u, options: .atomic)) != nil
                }
                return wrote
            } ?? false
        }.value
        lastWrite = ok ? "Vault'a yazıldı · " + Date.now.formatted(date: .omitted, time: .shortened) : (vaultLinked ? "Vault'a yazılamadı" : "Vault bağlı değil: kayıt telefonda duruyor")
        await bus.sync()
    }

    // MARK: vault access

    nonisolated static func vaultRoot() -> URL? { PDMVault.simulatorOverride ?? PDMVault.resolve() }
    nonisolated static var phoneFolder: String { "phone/" + PDMBus.device }

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
            if !fm.fileExists(atPath: file.path) {
                try? fm.startDownloadingUbiquitousItem(at: file)
                for _ in 0..<24 where !fm.fileExists(atPath: file.path) { Thread.sleep(forTimeInterval: 0.25) }
            }
            var data: Data?
            var err: NSError?
            NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &err) { data = try? Data(contentsOf: $0) }
            return data
        }
    }

    // MARK: documents

    func addDocument(from url: URL, title: String) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let clean = (title.isEmpty ? url.deletingPathExtension().lastPathComponent : title).replacingOccurrences(of: "/", with: "-")
        let name = Day.key(.now) + "-" + String(Int(Date.now.timeIntervalSince1970) % 100000) + " " + clean + "." + (url.pathExtension.isEmpty ? "pdf" : url.pathExtension)
        try? FileManager.default.copyItem(at: url, to: localInbox.appendingPathComponent(name))
        bus.emit("document.added", subject: "document:" + name, data: ["title": .string(clean), "system": "fbs"])
        await flushInbox()
    }

    func addDocument(data: Data, title: String, ext: String) async {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
        try? data.write(to: tmp)
        await addDocument(from: tmp, title: title)
        try? FileManager.default.removeItem(at: tmp)
    }

    func flushInbox() async {
        guard !demo else { return }
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
    }

    // MARK: reminders

    @AppStorage("reminders") var reminders = true

    /// Bill two days before (10:00), commitment end 30 and 7 days before, warranty end 30 days before. At most 40.
    func scheduleReminders() async {
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("fbs.") }
        center.removePendingNotificationRequests(withIdentifiers: old)
        guard reminders, !demo else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let d = Derived(self)
        var items: [(Date, String, String, String)] = []
        for e in d.events(from: Day.today, days: 120) {
            switch e.type {
            case .bill where !e.paid:
                items.append((Day.cal.date(byAdding: .day, value: -2, to: e.date)!, "fbs.bill.\(e.ref).\(Day.key(e.date))",
                              "\(e.title) faturası 2 gün sonra", e.amount.map { TL.text($0) } ?? ""))
            case .commitmentEnd:
                for before in [30, 7] {
                    items.append((Day.cal.date(byAdding: .day, value: -before, to: e.date)!, "fbs.end.\(e.ref).\(before)",
                                  "\(e.title): taahhüt \(before) gün sonra bitiyor", "Fiyat ve yenileme şartına bak; istersen başka teklif al."))
                }
            case .warrantyEnd:
                items.append((Day.cal.date(byAdding: .day, value: -30, to: e.date)!, "fbs.warranty.\(e.ref)",
                              "\(e.title): garanti 30 gün sonra bitiyor", "Arızası varsa garanti bitmeden servise götür."))
            default: break
            }
        }
        for (when, id, title, body) in items.filter({ $0.0 > .now }).sorted(by: { $0.0 < $1.0 }).prefix(40) {
            let c = UNMutableNotificationContent()
            c.title = title
            c.body = body
            c.sound = .default
            var comps = Day.cal.dateComponents([.year, .month, .day], from: when)
            comps.hour = 10
            try? await center.add(UNNotificationRequest(identifier: id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
    }

    func requestNotifications() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    // MARK: preview data (launch argument -demoFinance), never written anywhere

    private func loadDemo() {
        let cal = Day.cal
        func d(_ offset: Int) -> String { Day.key(cal.date(byAdding: .day, value: offset, to: Day.today)!) }
        func m(_ months: Int, _ day: Int) -> String {
            let base = cal.date(byAdding: .month, value: months, to: Day.today)!
            var c = cal.dateComponents([.year, .month], from: base); c.day = day
            return Day.key(cal.date(from: c)!)
        }
        mac = FBSState(generated: ISO8601DateFormatter().string(from: .now),
                       household: [Person(id: "me", name: "Ben"), Person(id: "es", name: "Eş"), Person(id: "c1", name: "Çocuk 1"), Person(id: "c2", name: "Çocuk 2")])
        mine.contracts = [
            Contract(id: "op-me", provider: "Operatör A", kind: "mobile", holder: "me", label: "hat …1234", start: m(-10, 15), commitmentEnd: m(2, 15), amount: 450, billDay: 12,
                     payMethod: "kart …4321 otomatik", exitFee: "Kalan ay × indirim tutarı", priceClause: "12 ay sabit, sonra liste fiyatı",
                     keyTerms: ["12 ay taahhüt (madde 4)", "Cayarsan verilen indirim geri alınır (madde 7)", "Yenileme kendiliğinden, liste fiyatından (madde 9)"]),
            Contract(id: "op-es", provider: "Operatör A", kind: "mobile", holder: "es", label: "hat …5678", start: m(-4, 2), commitmentEnd: m(8, 2), amount: 390, billDay: 12),
            Contract(id: "op-c1", provider: "Operatör B", kind: "mobile", holder: "c1", start: m(-14, 20), amount: 210, billDay: 20),
            Contract(id: "op-c2", provider: "Operatör B", kind: "mobile", holder: "c2", start: m(-14, 20), amount: 210, billDay: 20),
            Contract(id: "net-ev", provider: "Sağlayıcı C", kind: "internet", holder: "es", label: "Ev fiber 100 Mbps", start: m(-20, 1), commitmentEnd: d(44), amount: 699.9, billDay: 3,
                     exitFee: "Kalan ay × 150 ₺", keyTerms: ["24 ay taahhüt", "Modem iadesi zorunlu"]),
            Contract(id: "net-ofis", provider: "Sağlayıcı D", kind: "internet", holder: "me", start: m(-6, 9), commitmentEnd: m(6, 9), amount: 549, billDay: 9),
            Contract(id: "elek", provider: "Elektrik dağıtım", kind: "electricity", holder: "me", amount: 1150, billDay: 18),
            Contract(id: "gaz", provider: "Doğalgaz", kind: "gas", holder: "me", amount: 1400, billDay: 22),
            Contract(id: "kira", provider: "Ev sahibi", kind: "rent", holder: "me", start: m(-8, 1), commitmentEnd: m(4, 1), amount: 18000, billDay: 1, priceClause: "Yıllık artış TÜFE oranında"),
            Contract(id: "muzik", provider: "Müzik servisi", kind: "digital", holder: "me", amount: 99.99, billDay: 26),
            Contract(id: "kasko", provider: "Sigorta E", kind: "insurance", holder: "me", start: m(-3, 10), period: "yearly", amount: 14500),
        ]
        mine.products = [
            Product(id: "tv", name: "Televizyon", bought: m(-22, 5), price: 21000, seller: "Mağaza", warrantyEnd: d(58)),
            Product(id: "bm", name: "Bulaşık makinesi", bought: m(-8, 12), price: 17500, warrantyEnd: m(16, 12)),
            Product(id: "tel", name: "Telefon", bought: m(-30, 3), warrantyEnd: m(-6, 3)),
        ]
        var recs: [Money] = []
        for back in (0...5).reversed() {
            func on(_ day: Int) -> String { m(-back, day) }
            recs.append(Money(id: "sal\(back)", date: on(1), kind: "input", category: "maaş", amount: 62000, party: "İşveren", source: "demo"))
            if back % 2 == 0 { recs.append(Money(id: "ek\(back)", date: on(15), kind: "input", category: "ek gelir", amount: 6500, party: "Danışmanlık", source: "demo")) }
            let paidSoFar = back > 0
            for c in mine.contracts where !c.yearly {
                guard let bd = c.billDay, paidSoFar || bd <= cal.component(.day, from: .now) else { continue }
                let rise = c.id == "op-me" && back >= 3 ? 420.0 : (c.id == "net-ev" && back >= 4 ? 599.9 : (c.amount ?? 0))
                recs.append(Money(id: "\(c.id)-\(back)", date: on(bd), kind: "output", category: Catalog.kind(c.kind).category, amount: rise, party: c.provider, contract: c.id, source: "demo"))
            }
            recs.append(Money(id: "mk\(back)", date: on(6), kind: "output", category: "market", amount: 9400 + Double(back) * 310, party: "Market", source: "demo"))
            recs.append(Money(id: "ym\(back)", date: on(13), kind: "output", category: "yemek", amount: 2800, party: "Restoran", source: "demo"))
            recs.append(Money(id: "ul\(back)", date: on(16), kind: "output", category: "ulaşım", amount: 3200, party: "Akaryakıt", source: "demo"))
            if back == 2 { recs.append(Money(id: "sg", date: on(19), kind: "output", category: "sağlık", amount: 2400, party: "Eczane", source: "demo")) }
            if back == 1 { recs.append(Money(id: "al", date: on(24), kind: "output", category: "alışveriş", amount: 5600, party: "Giyim", source: "demo")) }
        }
        mine.records = recs.filter { (Day.parse($0.date) ?? .distantFuture) <= .now }
        origin = "Örnek veri (yalnız ön izleme)"
        vaultLinked = true
    }
}
