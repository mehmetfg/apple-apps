// What the voice actually says can differ from what is on the page: a URL is read as its site name, an e-mail
// address as "name at site", an in-text citation such as "[12]" or "(Kant, 1781)" is skipped. The page keeps the
// original; `map` turns every position in the spoken string back into a position in the original, so the
// highlighted word still lands on the right place.
import Foundation

struct SpokenText {
    let string: String
    private let map: [Int]                  // spoken UTF-16 index → original UTF-16 index (count = spoken length + 1)

    struct Options: Equatable, Sendable {
        var simplifyLinks = true
        var skipCitations = true
    }

    /// Original range for a range in the spoken string.
    func original(_ r: NSRange) -> NSRange {
        let a = map[min(max(r.location, 0), map.count - 1)]
        let z = map[min(max(r.location + r.length, 0), map.count - 1)]
        return NSRange(location: a, length: max(0, z - a))
    }

    /// Spoken position for an original position: the first spoken unit at or after it.
    func spoken(at original: Int) -> Int {
        var lo = 0, hi = map.count - 1
        while lo < hi { let mid = (lo + hi) / 2; if map[mid] < original { lo = mid + 1 } else { hi = mid } }
        return lo
    }

    private static let url = try! NSRegularExpression(pattern: #"\b(?:https?://|www\.)[^\s<>"]+"#, options: [.caseInsensitive])
    private static let email = try! NSRegularExpression(pattern: #"\b([A-Za-z0-9._%+-]+)@([A-Za-z0-9.-]+\.[A-Za-z]{2,})\b"#)
    private static let bracketCitation = try! NSRegularExpression(pattern: #"\s?\[(?:\d+(?:[-–,]\s?\d+)*|[a-z])\]"#)
    private static let authorYear = try! NSRegularExpression(
        pattern: #"\s?\((?:[A-ZÇĞİÖŞÜ][\p{L}'’.-]+(?:\s(?:ve|and|&|et al\.?)\s[A-ZÇĞİÖŞÜ][\p{L}'’.-]+)?,?\s(?:\d{4}[a-z]?|t\.y\.|n\.d\.)(?:[,:]\s?(?:s\.\s?|p\.\s?)?\d+(?:[-–]\d+)?)?(?:;\s?)?)+\)"#)

    init(_ text: String, options: Options) {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var edits: [(range: NSRange, replacement: String)] = []
        if options.simplifyLinks {
            for m in Self.url.matches(in: text, range: full) {
                var s = ns.substring(with: m.range)
                s = s.replacingOccurrences(of: #"^(https?://)?(www\.)?"#, with: "", options: [.regularExpression, .caseInsensitive])
                let host = s.split(separator: "/").first.map(String.init) ?? s
                edits.append((m.range, host.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:)"))))
            }
            for m in Self.email.matches(in: text, range: full) where !edits.contains(where: { NSIntersectionRange($0.range, m.range).length > 0 }) {
                edits.append((m.range, ns.substring(with: m.range(at: 1)) + " at " + ns.substring(with: m.range(at: 2))))
            }
        }
        if options.skipCitations {
            for re in [Self.bracketCitation, Self.authorYear] {
                for m in re.matches(in: text, range: full) where !edits.contains(where: { NSIntersectionRange($0.range, m.range).length > 0 }) {
                    edits.append((m.range, ""))
                }
            }
        }
        guard !edits.isEmpty else {
            string = text
            map = Array(0...ns.length)
            return
        }
        edits.sort { $0.range.location < $1.range.location }
        var out = ""
        var map: [Int] = []
        var i = 0
        for e in edits where e.range.location >= i {
            if e.range.location > i {
                out += ns.substring(with: NSRange(location: i, length: e.range.location - i))
                map += Array(i..<e.range.location)
            }
            let rep = e.replacement as NSString
            out += e.replacement
            // every spoken unit of the replacement points into the original span, spread evenly over it
            for k in 0..<rep.length { map.append(e.range.location + k * e.range.length / max(rep.length, 1)) }
            i = e.range.location + e.range.length
        }
        if i < ns.length {
            out += ns.substring(from: i)
            map += Array(i..<ns.length)
        }
        map.append(ns.length)
        string = out
        self.map = map
    }
}
