import Foundation

enum Status: Int, Comparable {
    case done = 0, idle = 1, due = 2, late = 3
    static func < (a: Status, b: Status) -> Bool { a.rawValue < b.rawValue }
    var label: String {
        switch self {
        case .done: "tamam"
        case .due: "sırası geldi"
        case .late: "gecikti"
        case .idle: "veri yok"
        }
    }
}

struct Item: Identifiable {
    let id = UUID()
    let text: String
    let status: Status
}

struct AreaCard: Identifiable {
    let id: AreaID
    var status: Status
    var headline: String
    var items: [Item]
}

/// A cell in a roof grid (the whole map of one area).
struct Cell: Identifiable {
    let id: String
    let label: String
    let status: Status?    // nil = not reached yet
    let hint: String
}

struct RoofRow: Identifiable {
    let id: String
    let title: String
    let cells: [Cell]
}

struct Roof {
    var summary: String = ""
    var rows: [RoofRow] = []
    var notes: [String] = []
}

// MARK: - Body (journal front matter is the single source)

struct Journal {
    static let routine: [(key: String, name: String)] = [
        ("kefir", "Kefir"), ("kreatin", "Kreatin"), ("omega3", "Omega-3"), ("chia", "Chia"),
        ("kabak", "Kabak çek."), ("sirke", "Sirke"), ("lor", "Lor"),
    ]

    /// Mon A · Tue B · Wed walk · Thu C · Fri D · weekend walk (🏋 Antrenman Programı §1).
    static func training(for date: Date) -> (code: String, name: String) {
        switch Day.cal.component(.weekday, from: date) {
        case 2: ("A", "Üst vücut 1")
        case 3: ("B", "Alt vücut 1")
        case 5: ("C", "Üst vücut 2")
        case 6: ("D", "Alt vücut 2")
        default: ("Y", "30 dk yürüyüş")
        }
    }

    static func file(for date: Date) -> URL? {
        let c = Day.cal.dateComponents([.year, .month], from: date)
        let folder = Vault.url(String(format: "03 - Seyir Defteri/Günlükler/%04d/%02d", c.year!, c.month!))
        let key = Day.key(date)
        for f in Vault.files(in: folder, ext: "md") {
            if let h = try? FileHandle(forReadingFrom: f) {
                let head = String(decoding: h.readData(ofLength: 1200), as: UTF8.self)
                try? h.close()
                if head.contains("Günlük Tarihi: \(key)") { return f }
            }
        }
        return nil
    }

    static func frontMatter(_ url: URL) -> [String: String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8), text.hasPrefix("---") else { return [:] }
        var out: [String: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            if let r = line.range(of: ":") {
                out[String(line[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)] =
                    String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return out
    }

    /// Sets `key: value` inside the front matter; adds the key before the closing --- if missing.
    @discardableResult
    static func set(_ key: String, _ value: String, in url: URL) -> Bool {
        guard var text = try? String(contentsOf: url, encoding: .utf8), text.hasPrefix("---") else { return false }
        var lines = text.components(separatedBy: "\n")
        guard let close = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else { return false }
        if let i = lines[1..<close].firstIndex(where: { $0.hasPrefix(key + ":") }) {
            lines[i] = "\(key): \(value)"
        } else {
            lines.insert("\(key): \(value)", at: close)
        }
        text = lines.joined(separator: "\n")
        return (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil
    }
}

// MARK: - Store

@MainActor
final class Store: ObservableObject {
    @Published var cards: [AreaCard] = []
    @Published var roofs: [AreaID: Roof] = [:]
    @Published var journalURL: URL?
    @Published var journalFields: [String: String] = [:]
    @Published var loadedAt = Date()

    static let programStart = Day.parse("2026-10-19")!   // Bir Yöne, Güz week 1

    func reload(now: Date = Date()) {
        journalURL = Journal.file(for: now)
        journalFields = journalURL.map(Journal.frontMatter) ?? [:]
        let today = Vault.json("_bus/state/today.json") ?? [:]
        let reading = Vault.json("_bus/state/reading.json") ?? [:]
        let words = Vault.json("_bus/state/words.json") ?? [:]
        let body = Vault.json("_bus/state/body.json") ?? [:]
        let hour = Day.cal.component(.hour, from: now)

        let b = bodyCard(now: now, hour: hour, body: body)
        let e = englishCard(now: now, hour: hour, words: words)
        let r = readingCard(now: now, reading: reading)
        let t = technicalCard(now: now, today: today, reading: reading)
        cards = [b.0, e.0, r.0, t.0]
        roofs = [.body: b.1, .english: e.1, .reading: r.1, .technical: t.1]
        loadedAt = now
    }

    func toggle(_ key: String, on: Bool) {
        guard let url = journalURL else { return }
        Journal.set(key, on ? "true" : "false", in: url)
        reload()
    }

    // MARK: Body

    private func bodyCard(now: Date, hour: Int, body: [String: Any]) -> (AreaCard, Roof) {
        let tr = Journal.training(for: now)
        let f = journalFields
        let trainingDone = f["antrenman"] == "true"
        let ticked = Journal.routine.filter { f[$0.key] == "true" }.count
        var items: [Item] = []
        let late = hour >= 20
        items.append(Item(text: tr.code == "Y" ? "Yürüyüş · 30 dk" : "Antrenman \(tr.code) · \(tr.name)",
                          status: trainingDone ? .done : (late ? .late : .due)))
        items.append(Item(text: "Rutin \(ticked)/\(Journal.routine.count)",
                          status: ticked == Journal.routine.count ? .done : (late && ticked == 0 ? .late : .due)))
        if let lab = body["lab"] as? [String: Any], let over = lab["overdue_days"] as? Int, over > 0 {
            items.append(Item(text: "Kan testi \(over) gün gecikti", status: .late))
        }
        if journalURL == nil { items.insert(Item(text: "Bugünün günlüğü yok — Obsidian'da aç", status: .idle), at: 0) }
        let worst = items.prefix(2).map(\.status).max() ?? .idle
        let card = AreaCard(id: .body, status: worst, headline: tr.code == "Y" ? "Dinlenme günü" : "Antrenman \(tr.code)", items: items)

        // Roof: 14 days × (training + 7 routines)
        var rows: [RoofRow] = []
        let days = (0..<14).reversed().map { Day.daysAgo($0, from: now) }
        let fields = days.map { d in Journal.file(for: d).map(Journal.frontMatter) ?? [:] }
        rows.append(RoofRow(id: "antrenman", title: "Antrenman", cells: days.enumerated().map { i, d in
            let code = Journal.training(for: d).code
            let done = fields[i]["antrenman"] == "true"
            return Cell(id: "a\(i)", label: code, status: done ? .done : (d > now ? nil : .due), hint: Day.key(d))
        }))
        for r in Journal.routine {
            rows.append(RoofRow(id: r.key, title: r.name, cells: days.enumerated().map { i, d in
                Cell(id: "\(r.key)\(i)", label: "", status: fields[i][r.key] == "true" ? .done : .due, hint: Day.key(d))
            }))
        }
        var roof = Roof(summary: "Son 14 gün · haftada 4 antrenman (A·B·C·D), her gün 7 rutin", rows: rows)
        roof.notes = (body["gaps"] as? [String]) ?? []
        return (card, roof)
    }

    // MARK: English

    private func englishCard(now: Date, hour: Int, words: [String: Any]) -> (AreaCard, Roof) {
        var byDay: [String: (gun: Int, minutes: Int)] = [:]
        for f in Vault.files(in: Vault.downloads, ext: "json")
        where f.lastPathComponent.range(of: #"-gun\d+-tezgah\.json$"#, options: .regularExpression) != nil {
            guard let d = Vault.json(f), let date = d["tarih"] as? String else { continue }
            let gun = d["gun"] as? Int ?? 0
            let m = d["sure_dk"] as? Int ?? Int(d["sure_dk"] as? Double ?? 0)
            if (byDay[date]?.gun ?? -1) < gun { byDay[date] = (gun, m) }
        }
        let todayKey = Day.key(now)
        let lastGun = byDay.values.map(\.gun).max() ?? 0
        var items: [Item] = []
        if let t = byDay[todayKey] {
            items.append(Item(text: "Cümle Gün \(t.gun) yazıldı · \(t.minutes) dk", status: .done))
        } else {
            items.append(Item(text: "Cümle Gün \(lastGun + 1) masada", status: hour >= 20 ? .late : .due))
        }
        let counts = words["counts"] as? [String: Int] ?? [:]
        if let s = counts["struggling"], s > 0 { items.append(Item(text: "\(s) kelime takılıyor", status: .idle)) }
        let card = AreaCard(id: .english, status: items[0].status,
                            headline: byDay[todayKey] != nil ? "Bugünün yazımı bitti" : "Bugün yazılmadı", items: items)

        let days = (0..<30).reversed().map { Day.daysAgo($0, from: now) }
        let cells = days.map { d -> Cell in
            let k = Day.key(d)
            if let t = byDay[k] { return Cell(id: k, label: "\(t.gun)", status: .done, hint: "\(k) · \(t.minutes) dk") }
            return Cell(id: k, label: "", status: k == todayKey ? .due : .late, hint: k)
        }
        let order = ["known", "learning", "struggling", "seen", "new", "dropped"]
        let names = ["known": "biliyor", "learning": "öğreniyor", "struggling": "takılıyor", "seen": "gördü", "new": "yeni", "dropped": "bırakıldı"]
        let total = max(1, counts.values.reduce(0, +))
        var roof = Roof(summary: "Cümle · son 30 gün (kare = yazılan gün, sayı = Gün no)",
                        rows: [RoofRow(id: "cumle", title: "Cümle", cells: cells)])
        roof.notes = order.compactMap { k in counts[k].map { "\(names[k]!): \($0) (%\($0 * 100 / total))" } }
        return (card, roof)
    }

    // MARK: Reading (Bir Yöne: week n = three books, number = week)

    private func readingCard(now: Date, reading: [String: Any]) -> (AreaCard, Roof) {
        let days = Day.cal.dateComponents([.day], from: Self.programStart, to: Day.cal.startOfDay(for: now)).day ?? 0
        let week = max(1, days / 7 + 1)
        let dayOfWeek = days % 7 + 1
        let target = Int((Double(dayOfWeek) / 7.0 * 100).rounded())
        let books = reading["books"] as? [[String: Any]] ?? []
        func percent(_ branch: String, _ n: Int) -> Int? {
            let prefix = String(format: "%@ %02d — ", branch, n)
            return books.filter { ($0["title"] as? String)?.hasPrefix(prefix) == true }.compactMap { $0["percent"] as? Int }.max()
        }
        let branches = [("Felsefe", "sabah 30 dk"), ("Bilimler", "öğle 15 dk"), ("Mühendislik", "akşam 45 dk")]
        var items: [Item] = []
        for (b, when) in branches {
            let p = percent(b, week)
            let st: Status = p == nil ? .idle : (p! >= target ? .done : (p! + 25 < target ? .late : .due))
            items.append(Item(text: "\(b) \(String(format: "%02d", week)) · %\(p ?? 0) / hedef %\(target) · \(when)", status: st))
        }
        let worst = items.map(\.status).max() ?? .idle
        let card = AreaCard(id: .reading, status: worst, headline: "Hafta \(week) · \(dayOfWeek). gün", items: items)

        let rows = branches.map { b, _ in
            RoofRow(id: b, title: b, cells: (1...52).map { n -> Cell in
                guard n <= week else { return Cell(id: "\(b)\(n)", label: "\(n)", status: nil, hint: "Hafta \(n)") }
                let p = percent(b, n) ?? 0
                let st: Status = p >= 90 ? .done : (n < week ? .late : (p >= target ? .done : (p + 25 < target ? .late : .due)))
                return Cell(id: "\(b)\(n)", label: "\(n)", status: st, hint: "Hafta \(n) · %\(p)")
            })
        }
        var roof = Roof(summary: "Bir Yöne · 52 hafta × 3 dal · kitap no = hafta no · %90 dinlenince tamam", rows: rows)
        let inProgress = (reading["in_progress"] as? [String]) ?? []
        let byID = Dictionary(books.compactMap { b in (b["id"] as? String).map { ($0, b) } }, uniquingKeysWith: { a, _ in a })
        roof.notes = inProgress.prefix(6).compactMap { id in
            guard let b = byID[id], let t = b["title"] as? String else { return nil }
            return "Sürüyor: \(t) · %\(b["percent"] as? Int ?? 0)"
        }
        return (card, roof)
    }

    // MARK: Technical (Mühendis Tezgâhı 12 × 180 + Mühendislik book)

    private func technicalCard(now: Date, today: [String: Any], reading: [String: Any]) -> (AreaCard, Roof) {
        let curriculum = Vault.json("Artifacts/_muhendis/mufredat.json")?["alanlar"] as? [[String: Any]] ?? []
        let ledger = Vault.json("Artifacts/_muhendis/defter.json")?["meseleler"] as? [String: Any] ?? [:]
        let produced = Set(Vault.files(in: Vault.url("Artifacts/_muhendis/mesele"), ext: "json").map { $0.deletingPathExtension().lastPathComponent })
        let desk = (today["muhendis"] as? [String: Any]) ?? [:]
        let deskID = desk["id"] as? String ?? ""
        func isDone(_ id: String) -> Bool {
            guard let m = ledger[id] as? [String: Any] else { return false }
            return m["bitti"] as? Bool == true || m["durum"] as? String == "tamam" || m["sonuc"] != nil
        }
        var deskAge = 0
        if let made = (Vault.json("Artifacts/_muhendis/mesele/\(deskID).json")?["uretildi"] as? String).flatMap(Day.parse) {
            deskAge = Day.cal.dateComponents([.day], from: made, to: now).day ?? 0
        }
        let total = curriculum.reduce(0) { $0 + (($1["meseleler"] as? [Any])?.count ?? 0) }
        let doneCount = curriculum.flatMap { ($0["meseleler"] as? [[String: Any]]) ?? [] }.filter { isDone($0["id"] as? String ?? "") }.count
        var items: [Item] = []
        if !deskID.isEmpty {
            items.append(Item(text: "\(deskID) · \(desk["baslik"] as? String ?? "")\(deskAge > 1 ? " · \(deskAge) gündür masada" : "")",
                              status: isDone(deskID) ? .done : (deskAge > 3 ? .late : .due)))
        }
        let books = reading["books"] as? [[String: Any]] ?? []
        if let mb = books.first(where: { ($0["title"] as? String)?.hasPrefix("Mühendislik 01 — ") == true }) {
            let p = mb["percent"] as? Int ?? 0
            items.append(Item(text: "Mühendislik 01 dinleme · %\(p)", status: p >= 90 ? .done : .due))
        }
        items.append(Item(text: "Çatı: \(doneCount)/\(total) mesele tamam", status: .idle))
        let card = AreaCard(id: .technical, status: items.first?.status ?? .idle, headline: "Mühendis Tezgâhı", items: items)

        let rows = curriculum.map { a -> RoofRow in
            let code = a["kod"] as? String ?? ""
            let list = (a["meseleler"] as? [[String: Any]]) ?? []
            return RoofRow(id: code, title: "\(code) · \(a["ad"] as? String ?? "")", cells: list.map { m in
                let id = m["id"] as? String ?? ""
                let st: Status? = isDone(id) ? .done : (id == deskID ? (deskAge > 3 ? .late : .due) : (produced.contains(id) ? .idle : nil))
                return Cell(id: id, label: String(id.split(separator: "-").last ?? ""), status: st, hint: "\(id) · \(m["baslik"] as? String ?? "")")
            })
        }
        var roof = Roof(summary: "12 alan · \(total) mesele · temelden ileriye (karmaşıklık → YZ ile mühendislik)", rows: rows)
        roof.notes = ["Kare: yeşil tamam · turuncu masada · kırmızı masada bekliyor · boş henüz sırası gelmedi"]
        return (card, roof)
    }
}
