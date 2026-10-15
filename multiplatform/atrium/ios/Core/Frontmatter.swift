// Minimal YAML front-matter reader/writer, compatible with Vault Tezgâhı's rules:
// "key: value", "[a, b]" inline lists, "- x" list lines. Everything else is left untouched.
import Foundation

enum FrontmatterValue: Hashable {
    case text(String)
    case list([String])

    var text: String? { if case .text(let s) = self { return s }; return nil }
    var list: [String] {
        switch self {
        case .text(let s): return s.isEmpty ? [] : [s]
        case .list(let l): return l
        }
    }
}

struct Frontmatter {
    var raw: String?          // block between the --- fences, nil when the note has none
    var body: String
    var closed: Bool
    var fields: [(key: String, value: FrontmatterValue)]

    subscript(key: String) -> FrontmatterValue? { fields.first { $0.key == key }?.value }

    static func split(_ text: String) -> Frontmatter {
        guard text.hasPrefix("---") else { return Frontmatter(raw: nil, body: text, closed: true, fields: []) }
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return Frontmatter(raw: nil, body: text, closed: true, fields: [])
        }
        for i in 1..<min(lines.count, 400) {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t == "---" || t == "..." {
                let raw = lines[1..<i].joined(separator: "\n")
                let body = lines[(i + 1)...].joined(separator: "\n")
                return Frontmatter(raw: raw, body: body, closed: true, fields: parse(raw))
            }
        }
        let raw = lines.dropFirst().joined(separator: "\n")
        return Frontmatter(raw: raw, body: "", closed: false, fields: parse(raw))
    }

    static func parse(_ raw: String) -> [(key: String, value: FrontmatterValue)] {
        var out: [(key: String, value: FrontmatterValue)] = []
        for line in raw.components(separatedBy: "\n") {
            if let colon = line.firstIndex(of: ":"), let first = line.first, !first.isWhitespace, first != "#", first != "-" {
                let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                var value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("[") && value.hasSuffix("]") {
                    let items = value.dropFirst().dropLast().split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
                        .filter { !$0.isEmpty }
                    out.append((key, .list(items)))
                } else {
                    value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    out.append((key, .text(value)))
                }
            } else if let last = out.indices.last, line.trimmingCharacters(in: .whitespaces).hasPrefix("- ") {
                let item = line.trimmingCharacters(in: .whitespaces).dropFirst(2)
                    .trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                var list = out[last].value.list
                list.append(item)
                out[last].value = .list(list)
            }
        }
        return out
    }

    /// Sets or replaces one `key: value` line, leaving the rest of the block untouched.
    static func setting(_ key: String, to value: String, in text: String) -> String {
        let fm = split(text)
        let line = "\(key): \(value)"
        guard var raw = fm.raw else { return "---\n\(line)\n---\n\(text)" }
        guard fm.closed else { return text }
        var lines = raw.isEmpty ? [] : raw.components(separatedBy: "\n")
        if let i = lines.firstIndex(where: { $0.hasPrefix(key) && $0.dropFirst(key.count).trimmingCharacters(in: .whitespaces).hasPrefix(":") }) {
            lines[i] = line
        } else {
            lines.append(line)
        }
        raw = lines.joined(separator: "\n")
        return "---\n\(raw)\n---\n\(fm.body)"
    }
}

enum TextTools {
    static func nfc(_ s: String) -> String { s.precomposedStringWithCanonicalMapping }

    static func key(_ s: String) -> String { nfc(s).lowercased().trimmingCharacters(in: .whitespaces) }

    static func wordCount(_ body: String) -> Int {
        var count = 0
        var inWord = false
        for scalar in body.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if !inWord { count += 1; inWord = true }
            } else if scalar != "'" && scalar != "’" {
                inWord = false
            }
        }
        return count
    }

    private static let linkPattern = try! NSRegularExpression(pattern: #"!?\[\[([^\]|#^]+)"#)

    static func wikilinks(_ body: String) -> [String] {
        let ns = body as NSString
        var seen = Set<String>()
        var out: [String] = []
        for m in linkPattern.matches(in: body, range: NSRange(location: 0, length: ns.length)) {
            var target = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            if let slash = target.lastIndex(of: "/") { target = String(target[target.index(after: slash)...]) }
            if target.lowercased().hasSuffix(".md") { target = String(target.dropLast(3)) }
            let k = key(target)
            if !k.isEmpty, seen.insert(k).inserted { out.append(k) }
        }
        return out
    }

    /// Characters that are illegal or troublesome in vault file names.
    static func safeFileName(_ s: String) -> String {
        let banned = CharacterSet(charactersIn: "/\\:*?\"<>|#^[]")
        let cleaned = s.unicodeScalars.map { banned.contains($0) ? " " : String($0) }.joined()
        let collapsed = cleaned.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return String(collapsed.prefix(120)).trimmingCharacters(in: CharacterSet(charactersIn: " ."))
    }
}

enum TurkishCalendar {
    static let months = ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran", "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"]
    static let monthsEnglish = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    static let weekdays = ["Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi", "Pazar"]

    static var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.locale = Locale(identifier: "tr_TR")
        return c
    }()

    static func dayKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func date(fromKey key: String) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    /// Monday = 0 … Sunday = 6
    static func weekdayIndex(_ date: Date) -> Int { (calendar.component(.weekday, from: date) + 5) % 7 }

    static func monthName(_ date: Date) -> String { months[calendar.component(.month, from: date) - 1] }
    static func weekdayName(_ date: Date) -> String { weekdays[weekdayIndex(date)] }

    /// "11 Ekim 2026, Pazar" — the journal file-name format used across the vault.
    static func journalTitle(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%02d %@ %04d, %@", c.day!, months[c.month! - 1], c.year!, weekdayName(date))
    }

    private static let namedDate: NSRegularExpression = {
        let names = (months + monthsEnglish).joined(separator: "|")
        return try! NSRegularExpression(pattern: "(\\d{1,2})\\s+(\(names))\\s+(\\d{4})", options: [.caseInsensitive])
    }()
    private static let isoDate = try! NSRegularExpression(pattern: #"(\d{4})-(\d{2})-(\d{2})"#)

    static func parseDay(_ s: String) -> String? {
        let ns = s as NSString
        if let m = namedDate.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) {
            let monthName = ns.substring(with: m.range(at: 2)).lowercased()
            let idx = months.firstIndex { $0.lowercased() == monthName } ?? monthsEnglish.firstIndex { $0.lowercased() == monthName }
            if let idx, let d = Int(ns.substring(with: m.range(at: 1))), let y = Int(ns.substring(with: m.range(at: 3))) {
                return String(format: "%04d-%02d-%02d", y, idx + 1, d)
            }
        }
        if let m = isoDate.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) {
            return ns.substring(with: m.range(at: 0))
        }
        return nil
    }

    static func relative(_ date: Date, now: Date = Date()) -> String {
        let s = now.timeIntervalSince(date)
        if s < 60 { return "az önce" }
        if s < 3600 { return "\(Int(s / 60)) dk önce" }
        if calendar.isDateInToday(date) { return "\(Int(s / 3600)) sa önce" }
        if calendar.isDateInYesterday(date) { return "dün" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days < 7 { return "\(days) gün önce" }
        if days < 60 { return "\(days / 7) hafta önce" }
        return "\(days / 30) ay önce"
    }
}
