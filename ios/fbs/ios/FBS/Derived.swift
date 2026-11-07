// Everything the screens show is computed here from three lists: contracts, products, money records.
import SwiftUI

struct FinEvent: Identifiable, Hashable {
    enum Kind: Hashable { case bill, commitmentEnd, warrantyEnd, payment, income }
    var type: Kind
    var date: Date
    var title: String
    var detail: String
    var amount: Double?
    var ref: String
    var category: String
    var paid = false
    var id: String { "\(type)-\(ref)-\(Day.key(date))" }
}

struct MonthSummary: Identifiable, Hashable {
    var start: Date
    var income: Double
    var expense: Double
    var byCategory: [(String, Double)]
    var id: Date { start }
    var net: Double { income - expense }

    static func == (a: MonthSummary, b: MonthSummary) -> Bool { a.start == b.start && a.income == b.income && a.expense == b.expense }
    func hash(into h: inout Hasher) { h.combine(start) }
}

struct Derived {
    var contracts: [Contract]
    var products: [Product]
    var records: [Money]
    var household: [Person]

    @MainActor
    init(_ store: Store) {
        contracts = store.contracts
        products = store.products
        records = store.records.sorted { $0.date > $1.date }
        household = store.household
    }

    var active: [Contract] { contracts.filter(\.isActive) }
    var cal: Calendar { Day.cal }

    func name(_ person: String?) -> String { household.first { $0.id == person }?.name ?? person ?? "—" }

    // MARK: bills

    /// Every bill date of a contract between two dates (monthly: the bill day each month; yearly: the start date each year).
    func billDates(_ c: Contract, from: Date, to: Date) -> [Date] {
        guard c.isActive else { return [] }
        var out: [Date] = []
        if c.yearly {
            guard let s = Day.parse(c.start) else { return [] }
            var y = cal.component(.year, from: from) - 1
            while y <= cal.component(.year, from: to) {
                var comps = cal.dateComponents([.month, .day], from: s); comps.year = y
                if let d = cal.date(from: comps), d >= from, d <= to { out.append(d) }
                y += 1
            }
            return out
        }
        guard let bd = c.billDay else { return [] }
        var month = cal.date(from: cal.dateComponents([.year, .month], from: from))!
        while month <= to {
            let days = cal.range(of: .day, in: .month, for: month)!.count
            var comps = cal.dateComponents([.year, .month], from: month); comps.day = min(bd, days)
            if let d = cal.date(from: comps), d >= from, d <= to {
                if let start = Day.parse(c.start), d < start {} else { out.append(d) }
            }
            month = cal.date(byAdding: .month, value: 1, to: month)!
        }
        return out
    }

    /// A bill counts as paid when a payment for the contract falls within 12 days before or 20 days after the bill date.
    func payment(for c: Contract, near d: Date) -> Money? {
        records.first { r in
            guard r.contract == c.id, !r.isIncome, let rd = Day.parse(r.date) else { return false }
            let diff = cal.dateComponents([.day], from: d, to: rd).day ?? 99
            return diff >= -12 && diff <= 20
        }
    }

    func nextBill(_ c: Contract) -> Date? { billDates(c, from: Day.today, to: cal.date(byAdding: .month, value: 13, to: Day.today)!).first }

    func events(from: Date, days: Int) -> [FinEvent] {
        let to = cal.date(byAdding: .day, value: days, to: from)!
        var out: [FinEvent] = []
        for c in active {
            let k = Catalog.kind(c.kind)
            for d in billDates(c, from: from, to: to) {
                out.append(FinEvent(type: .bill, date: d, title: c.provider.isEmpty ? k.name : c.provider,
                                    detail: [k.name, name(c.holder)].joined(separator: " · "), amount: c.amount, ref: c.id, category: k.category,
                                    paid: payment(for: c, near: d) != nil))
            }
            if let end = Day.parse(c.commitmentEnd), end >= cal.date(byAdding: .day, value: -30, to: from)!, end <= to {
                out.append(FinEvent(type: .commitmentEnd, date: end, title: c.provider.isEmpty ? k.name : c.provider,
                                    detail: "Taahhüt bitiyor · " + (c.priceClause ?? "fiyat ve yenileme şartına bak"), amount: nil, ref: c.id, category: k.category))
            }
        }
        for p in products {
            if let w = Day.parse(p.warrantyEnd), w >= from, w <= to {
                out.append(FinEvent(type: .warrantyEnd, date: w, title: p.name, detail: "Garanti bitiyor", amount: nil, ref: p.id, category: "alışveriş"))
            }
        }
        return out.sorted { $0.date < $1.date }
    }

    /// For the calendar: expected bills, recorded payments and income, ends, in one month.
    func monthEvents(_ monthStart: Date) -> [FinEvent] {
        let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart)!
        var out = events(from: monthStart, days: cal.dateComponents([.day], from: monthStart, to: end).day ?? 30)
        for r in records {
            guard let d = Day.parse(r.date), d >= monthStart, d <= end else { continue }
            if r.contract != nil && !r.isIncome { continue }   // shown as a paid bill
            out.append(FinEvent(type: r.isIncome ? .income : .payment, date: d, title: r.party ?? Catalog.category(r.category).name,
                                detail: Catalog.category(r.category).name, amount: r.amount, ref: r.id, category: r.category ?? "diğer", paid: true))
        }
        return out.sorted { $0.date < $1.date }
    }

    // MARK: months

    func month(_ start: Date) -> MonthSummary {
        let end = cal.date(byAdding: .month, value: 1, to: start)!
        var inc = 0.0, exp = 0.0
        var cats: [String: Double] = [:]
        for r in records {
            guard let d = Day.parse(r.date), d >= start, d < end else { continue }
            if r.isIncome { inc += r.amount } else {
                exp += r.amount
                cats[r.category ?? "diğer", default: 0] += r.amount
            }
        }
        return MonthSummary(start: start, income: inc, expense: exp, byCategory: cats.sorted { $0.value > $1.value })
    }

    static func monthStart(_ d: Date) -> Date { Day.cal.date(from: Day.cal.dateComponents([.year, .month], from: d))! }

    func lastMonths(_ n: Int, ending: Date = .now) -> [MonthSummary] {
        let last = Self.monthStart(ending)
        return (0..<n).reversed().map { month(cal.date(byAdding: .month, value: -$0, to: last)!) }
    }

    // MARK: fixed load

    var monthlyLoad: Double { active.reduce(0) { $0 + ($1.monthly ?? 0) } }

    var loadByKind: [(String, Double)] {
        var out: [String: Double] = [:]
        for c in active { out[Catalog.kind(c.kind).category, default: 0] += c.monthly ?? 0 }
        return out.sorted { $0.value > $1.value }
    }

    var loadByHolder: [(String, Double)] {
        var out: [String: Double] = [:]
        for c in active { out[name(c.holder), default: 0] += c.monthly ?? 0 }
        return out.sorted { $0.value > $1.value }
    }

    // MARK: contracts

    func payments(_ c: Contract) -> [Money] { records.filter { $0.contract == c.id && !$0.isIncome }.sorted { $0.date < $1.date } }

    /// Change from the first to the last recorded payment, in percent.
    func priceChange(_ c: Contract) -> Double? {
        let p = payments(c)
        guard p.count >= 2, let a = p.first?.amount, a > 0, let b = p.last?.amount else { return nil }
        let pct = (b - a) / a * 100
        return abs(pct) < 0.5 ? nil : pct
    }

    /// 0…1 share of the commitment that has passed, or nil.
    func commitmentProgress(_ c: Contract) -> Double? {
        guard let s = Day.parse(c.start), let e = Day.parse(c.commitmentEnd), e > s else { return nil }
        return min(max(Date.now.timeIntervalSince(s) / e.timeIntervalSince(s), 0), 1)
    }

    func warrantyProgress(_ p: Product) -> Double? {
        guard let s = Day.parse(p.bought), let e = Day.parse(p.warrantyEnd), e > s else { return nil }
        return min(max(Date.now.timeIntervalSince(s) / e.timeIntervalSince(s), 0), 1)
    }
}
