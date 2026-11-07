// FBS data: what the Mac writes (state/fbs.json) and what this phone enters (entries.json).
// Both use the same three shapes: Contract, Product, Money. Keys are snake_case in the files.
import Foundation
import SwiftUI

struct Person: Codable, Hashable, Identifiable {
    var id: String
    var name: String
}

struct Contract: Codable, Hashable, Identifiable {
    var id: String
    var provider: String = ""
    var kind: String = "other"
    var holder: String?
    var label: String?
    var status: String? = "active"
    var start: String?
    var commitmentEnd: String?
    var period: String? = "monthly"
    var amount: Double?
    var currency: String? = "TRY"
    var billDay: Int?
    var payMethod: String?
    var exitFee: String?
    var priceClause: String?
    var keyTerms: [String]?
    var document: String?
    var note: String?
    var origin: String?
    var created: String?

    var isActive: Bool { (status ?? "active") == "active" }
    var isPhone: Bool { origin == nil || origin!.hasPrefix("phone") }
    var yearly: Bool { (period ?? "monthly") == "yearly" }

    /// What the contract costs in one month (a yearly one divided by twelve).
    var monthly: Double? {
        guard let amount else { return nil }
        switch period ?? "monthly" {
        case "yearly": return amount / 12
        case "quarterly": return amount / 3
        default: return amount
        }
    }
}

struct Product: Codable, Hashable, Identifiable {
    var id: String
    var name: String = ""
    var bought: String?
    var price: Double?
    var seller: String?
    var warrantyEnd: String?
    var document: String?
    var note: String?
    var origin: String?
    var created: String?

    var isPhone: Bool { origin == nil || origin!.hasPrefix("phone") }
}

struct Money: Codable, Hashable, Identifiable {
    var id: String
    var date: String
    var kind: String            // input · output
    var category: String?
    var amount: Double
    var currency: String? = "TRY"
    var party: String?
    var contract: String?
    var method: String?
    var note: String?
    var document: String?
    var source: String?
    var origin: String?
    var created: String?

    var isPhone: Bool { origin == nil || origin!.hasPrefix("phone") }
    var isIncome: Bool { kind == "input" }
}

/// The file the phone owns: FBS/phone/<device>/entries.json in the vault, and the same file in the app's Documents.
struct Entries: Codable {
    var v = 1
    var updated: String?
    var contracts: [Contract] = []
    var products: [Product] = []
    var records: [Money] = []
}

/// state/fbs.json from fbs.py. Only the raw lists are used; the app derives the rest itself so that
/// what is entered on the phone shows at once.
struct FBSState: Codable {
    var generated: String?
    var household: [Person]?
    var contracts: [Contract]?
    var products: [Product]?
    var records: [Money]?
    var pending: [String: Int]?
}

// MARK: - categories and kinds

struct Category: Identifiable, Hashable {
    var id: String
    var name: String
    var symbol: String
    var color: Color
}

enum Catalog {
    static let expense: [Category] = [
        .init(id: "iletişim", name: "İletişim", symbol: "iphone", color: Color(light: 0x2F6BFF, dark: 0x5C8DFF)),
        .init(id: "internet", name: "İnternet", symbol: "wifi", color: Color(light: 0x18A8B8, dark: 0x4CCAD8)),
        .init(id: "enerji", name: "Elektrik", symbol: "bolt.fill", color: Color(light: 0xF0A030, dark: 0xFFC04A)),
        .init(id: "doğalgaz", name: "Doğalgaz", symbol: "flame.fill", color: Color(light: 0xF07830, dark: 0xFF9550)),
        .init(id: "su", name: "Su", symbol: "drop.fill", color: Color(light: 0x30A0E0, dark: 0x5CC0FF)),
        .init(id: "kira", name: "Kira", symbol: "house.fill", color: Color(light: 0x7C5CFF, dark: 0x9D85FF)),
        .init(id: "aidat", name: "Aidat", symbol: "building.2.fill", color: Color(light: 0x5856D6, dark: 0x7D7BFF)),
        .init(id: "kredi", name: "Kredi ve taksit", symbol: "creditcard.fill", color: Color(light: 0xC0392B, dark: 0xF06050)),
        .init(id: "market", name: "Market", symbol: "cart.fill", color: Color(light: 0x34A853, dark: 0x58C877)),
        .init(id: "yemek", name: "Yemek", symbol: "fork.knife", color: Color(light: 0xE0609A, dark: 0xFF80B5)),
        .init(id: "ulaşım", name: "Ulaşım", symbol: "car.fill", color: Color(light: 0x6E7B8B, dark: 0x9AA8B8)),
        .init(id: "sağlık", name: "Sağlık", symbol: "cross.case.fill", color: Color(light: 0xE5484D, dark: 0xFF6B70)),
        .init(id: "eğitim", name: "Eğitim", symbol: "book.fill", color: Color(light: 0x8D6E63, dark: 0xB09080)),
        .init(id: "dijital", name: "Dijital abonelik", symbol: "play.rectangle.fill", color: Color(light: 0xAF52DE, dark: 0xC77DFF)),
        .init(id: "sigorta", name: "Sigorta", symbol: "shield.fill", color: Color(light: 0x00968F, dark: 0x2FC0B8)),
        .init(id: "vergi", name: "Vergi ve harç", symbol: "building.columns.fill", color: Color(light: 0x8E8E93, dark: 0xAEAEB2)),
        .init(id: "alışveriş", name: "Alışveriş", symbol: "bag.fill", color: Color(light: 0xD4537E, dark: 0xF07AA0)),
        .init(id: "diğer", name: "Diğer", symbol: "ellipsis.circle.fill", color: Color(light: 0x9A9AA6, dark: 0x7A7A86)),
    ]
    static let income: [Category] = [
        .init(id: "maaş", name: "Maaş", symbol: "banknote.fill", color: Color(light: 0x0E9E78, dark: 0x2FC79A)),
        .init(id: "ek gelir", name: "Ek gelir", symbol: "plus.circle.fill", color: Color(light: 0x34A853, dark: 0x58C877)),
        .init(id: "iade", name: "İade", symbol: "arrow.uturn.backward.circle.fill", color: Color(light: 0x18A8B8, dark: 0x4CCAD8)),
        .init(id: "diğer gelir", name: "Diğer gelir", symbol: "ellipsis.circle.fill", color: Color(light: 0x9A9AA6, dark: 0x7A7A86)),
    ]

    static func category(_ id: String?) -> Category {
        let key = (id ?? "diğer").lowercased(with: Locale(identifier: "tr_TR"))
        return (expense + income).first { $0.id == key } ?? .init(id: key, name: key.capitalized(with: Locale(identifier: "tr_TR")),
                                                                    symbol: "tag.fill", color: Color(light: 0x9A9AA6, dark: 0x7A7A86))
    }

    /// Contract kinds: id → (name, the expense category its bills go to, symbol)
    static let kinds: [(id: String, name: String, category: String, symbol: String)] = [
        ("mobile", "Cep hattı", "iletişim", "iphone"), ("internet", "İnternet", "internet", "wifi"),
        ("tv", "TV ve yayın", "dijital", "tv"), ("electricity", "Elektrik", "enerji", "bolt.fill"),
        ("gas", "Doğalgaz", "doğalgaz", "flame.fill"), ("water", "Su", "su", "drop.fill"),
        ("rent", "Kira", "kira", "house.fill"), ("dues", "Aidat", "aidat", "building.2.fill"),
        ("insurance", "Sigorta", "sigorta", "shield.fill"), ("digital", "Dijital abonelik", "dijital", "play.rectangle.fill"),
        ("loan", "Kredi", "kredi", "creditcard.fill"), ("education", "Eğitim", "eğitim", "book.fill"),
        ("other", "Diğer", "diğer", "doc.text.fill")]

    static func kind(_ id: String?) -> (id: String, name: String, category: String, symbol: String) {
        kinds.first { $0.id == id } ?? kinds.last!
    }
}

// MARK: - dates and money

enum Day {
    static let iso: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    static let tr = Locale(identifier: "tr_TR")
    static var cal: Calendar { var c = Calendar(identifier: .gregorian); c.locale = tr; c.firstWeekday = 2; return c }

    static func parse(_ s: String?) -> Date? { s.flatMap { iso.date(from: String($0.prefix(10))) } }
    static func key(_ d: Date) -> String { iso.string(from: d) }
    static var today: Date { cal.startOfDay(for: .now) }

    static func short(_ s: String?) -> String {
        guard let d = parse(s) else { return "—" }
        return d.formatted(.dateTime.day().month(.abbreviated).year().locale(tr))
    }

    static func dayMonth(_ d: Date) -> String { d.formatted(.dateTime.day().month(.abbreviated).locale(tr)) }
    static func month(_ d: Date) -> String { d.formatted(.dateTime.month(.wide).year().locale(tr)) }
    static func daysFromToday(_ d: Date) -> Int { cal.dateComponents([.day], from: today, to: cal.startOfDay(for: d)).day ?? 0 }

    /// "bugün", "yarın", "3 gün sonra", "2 gün önce"
    static func relative(_ d: Date) -> String {
        let n = daysFromToday(d)
        switch n {
        case 0: return "bugün"
        case 1: return "yarın"
        case -1: return "dün"
        case let x where x > 1: return "\(x) gün sonra"
        default: return "\(-n) gün önce"
        }
    }
}

enum TL {
    static func text(_ v: Double?, currency: String? = "TRY", decimals: Bool = true) -> String {
        guard let v else { return "—" }
        let f = NumberFormatter()
        f.locale = Day.tr
        f.numberStyle = .decimal
        f.maximumFractionDigits = decimals ? 2 : 0
        f.minimumFractionDigits = decimals && v.rounded() != v ? 2 : 0
        let n = f.string(from: NSNumber(value: v)) ?? "\(v)"
        switch currency ?? "TRY" {
        case "TRY", "": return n + " ₺"
        case "USD": return "$" + n
        case "EUR": return "€" + n
        default: return n + " " + currency!
        }
    }

    /// "12,4 bin ₺" for large round figures in the centre of a ring.
    static func compact(_ v: Double) -> String {
        let a = abs(v)
        if a >= 1_000_000 { return String(format: "%.1f", v / 1_000_000).replacingOccurrences(of: ".", with: ",") + " mn ₺" }
        if a >= 10_000 { return String(format: "%.1f", v / 1000).replacingOccurrences(of: ".", with: ",") + " bin ₺" }
        return text(v, decimals: false)
    }

    /// "450", "450,5", "1.250,75" → Double. Empty or not a number → nil.
    static func parse(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "₺", with: "").replacingOccurrences(of: " ", with: "")
        guard !t.isEmpty else { return nil }
        let normal = t.contains(",") ? t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") : t
        return Double(normal)
    }
}

enum Privacy {
    /// A card number, IBAN or national id is never kept: every run of 9 or more digits becomes "…" + its last 4 digits.
    static func mask(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        let compact = s.replacingOccurrences(of: " ", with: "")
        guard compact.range(of: #"\d{9,}"#, options: .regularExpression) != nil else { return s }
        var out = s
        if let re = try? NSRegularExpression(pattern: #"(?:\d[ -]?){9,}"#) {
            let ns = out as NSString
            for m in re.matches(in: out, range: NSRange(location: 0, length: ns.length)).reversed() {
                let digits = ns.substring(with: m.range).filter(\.isNumber)
                out = (out as NSString).replacingCharacters(in: m.range, with: "…" + digits.suffix(4))
            }
        }
        return out
    }
}
