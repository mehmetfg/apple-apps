// Written Turkish → the models' letter sequence, the word map back to the page, and ~10-second chunks.
// Ported from Ema's Metin.swift (Python reference: _araçlar/ema/model/referans.py — harfler, parcala).
import Foundation

enum TextPrep {
    // MARK: numbers (Turkish words; these strings are what the voice says)

    private static let ones = ["", "bir", "iki", "üç", "dört", "beş", "altı", "yedi", "sekiz", "dokuz"]
    private static let tens = ["", "on", "yirmi", "otuz", "kırk", "elli", "altmış", "yetmiş", "seksen", "doksan"]
    private static let large: [(UInt64, String)] = [(1_000_000_000_000, "trilyon"), (1_000_000_000, "milyar"),
                                                    (1_000_000, "milyon"), (1000, "bin")]

    private static func hundreds(_ n: UInt64) -> [String] {
        let h = Int(n / 100), t = Int(n % 100 / 10), o = Int(n % 10)
        var p: [String] = h == 0 ? [] : (h == 1 ? ["yüz"] : [ones[h], "yüz"])
        p += [tens[t], ones[o]].filter { !$0.isEmpty }
        return p
    }

    static func numberWords(_ value: UInt64) -> String {
        if value == 0 { return "sıfır" }
        var n = value, out: [String] = []
        for (unit, name) in large {
            let q = n / unit
            n %= unit
            if q == 0 { continue }
            if q < 1000 {
                out += (q == 1 && name == "bin") ? [name] : hundreds(q) + [name]
            } else {
                out += numberWords(q).split(separator: " ").map(String.init) + [name]
            }
        }
        return (out + hundreds(n)).joined(separator: " ")
    }

    // MARK: abbreviations and digits

    private static let abbreviations: [(String, String)] = [
        ("\\bTL\\b", "Türk lirası"), ("\\bvb\\.", "ve benzeri"), ("\\bvs\\.", "vesaire"),
        ("\\börn\\.", "örneğin"), ("\\bDr\\.", "doktor"), ("\\bProf\\.", "profesör"),
    ]
    private static let digitRun = try! NSRegularExpression(pattern: "[0-9]+")

    private static func replace(_ s: String, _ pattern: String, _ with: String) -> String {
        s.replacingOccurrences(of: pattern, with: with, options: .regularExpression)
    }

    static func spellNumbers(_ input: String) -> String {
        var s = input
        for (p, w) in abbreviations { s = replace(s, p, w) }
        s = replace(s, "%\\s*([0-9])", "yüzde $1")
        s = replace(s, "([0-9])\\.([0-9]{3})(?![0-9])", "$1$2")
        s = replace(s, "([0-9])\\.([0-9]{3})(?![0-9])", "$1$2")
        s = replace(s, "([0-9]+),([0-9]+)", "$1 virgül $2")
        let ns = NSMutableString(string: s)
        for m in digitRun.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
            let r = ns.substring(with: m.range)
            let words: String
            if r.count <= 15, let v = UInt64(r) {
                words = numberWords(v)
            } else {
                words = r.compactMap { $0.wholeNumberValue }.map { numberWords(UInt64($0)) }.joined(separator: " ")
            }
            ns.replaceCharacters(in: m.range, with: " " + words + " ")
        }
        return ns as String
    }

    // MARK: letter sequence

    private static let typography: [Character: String] = [
        "’": "'", "‘": "'", "ʼ": "'", "´": "'", "`": "'", "“": "\"", "”": "\"", "„": "\"",
        "«": "\"", "»": "\"", "–": "-", "—": "-", "−": "-", "…": "...",
    ]
    private static let turkishLetters = Set("çğıöşüÇĞİÖŞÜ".unicodeScalars)

    static func letters(_ input: String, alphabet: Set<Unicode.Scalar>) -> String {
        var s = String(spellNumbers(input).map { typography[$0] ?? String($0) }.joined())
        s = s.replacingOccurrences(of: "İ", with: "i").replacingOccurrences(of: "I", with: "ı").lowercased()
        var out = String.UnicodeScalarView()
        for sc in s.unicodeScalars {
            var parts: [Unicode.Scalar] = [sc]
            if !turkishLetters.contains(sc) {
                parts = String(sc).decomposedStringWithCompatibilityMapping.unicodeScalars
                    .filter { $0.properties.canonicalCombiningClass == .notReordered }
            }
            if !parts.isEmpty && parts.allSatisfy(alphabet.contains) {
                out.append(contentsOf: parts)
            } else {
                out.append(" ")
            }
        }
        return String(out).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: word map

    private static let nonSpace = try! NSRegularExpression(pattern: "\\S+")

    /// For every word the model will say, the range of its source word in `original` (UTF-16). "1971" becomes
    /// several model words that all point at it; if word-by-word expansion does not add up, spread evenly.
    static func wordMap(_ original: String, alphabet: Set<Unicode.Scalar>) -> [NSRange] {
        let ns = original as NSString
        let words = nonSpace.matches(in: original, range: NSRange(location: 0, length: ns.length)).map(\.range)
        let total = letters(original, alphabet: alphabet).split(separator: " ").count
        var map: [NSRange] = []
        for r in words {
            let n = letters(ns.substring(with: r), alphabet: alphabet).split(separator: " ").count
            map += Array(repeating: r, count: n)
        }
        if map.count == total || words.isEmpty { return map }
        return (0..<total).map { i in words[min(words.count - 1, i * words.count / max(total, 1))] }
    }

    // MARK: chunking

    private static let cuts: [(NSRegularExpression, Double)] = [
        (try! NSRegularExpression(pattern: "[.!?]+[\"')]*(?= )"), 0.25),
        (try! NSRegularExpression(pattern: "[,;:](?= )"), 0.12),
        (try! NSRegularExpression(pattern: "\\S(?= )"), 0.12),
    ]
    private static let letterPattern = try! NSRegularExpression(pattern: "\\p{L}")

    /// [(chunk, pause seconds after it)]; every chunk ends with sentence punctuation. `firstLimit`: the first chunk
    /// is cut only at a sentence or clause mark within that many letters, so the first audio comes early.
    static func split(_ text: String, speed: Double, firstLimit: Int? = nil) -> [(String, Double)] {
        let limit = Int(min(250, 18.0 * 10.0 * speed))
        var chunks: [(String, Double)] = []
        var rest = text.trimmingCharacters(in: .whitespaces) as NSString
        var first = true
        while rest.length > 0 {
            var cut = rest.length, pause = 0.0
            if first, let k = firstLimit, rest.length > k {
                let head = rest.substring(to: k + 1)
                for (re, gap) in cuts.prefix(2) {
                    if let last = re.matches(in: head, range: NSRange(location: 0, length: (head as NSString).length)).last {
                        cut = last.range.location + last.range.length
                        pause = gap
                        break
                    }
                }
            }
            first = false
            if cut == rest.length && rest.length > limit {
                cut = limit
                let head = rest.substring(to: limit + 1)
                for (re, gap) in cuts {
                    if let last = re.matches(in: head, range: NSRange(location: 0, length: (head as NSString).length)).last {
                        cut = last.range.location + last.range.length
                        pause = gap
                        break
                    }
                }
            }
            var piece = rest.substring(to: cut).trimmingCharacters(in: .whitespaces)
            rest = rest.substring(from: cut).trimmingCharacters(in: .whitespaces) as NSString
            if letterPattern.firstMatch(in: piece, range: NSRange(location: 0, length: (piece as NSString).length)) != nil {
                let body = piece.trimmingCharacters(in: CharacterSet(charactersIn: "\"')"))
                if !(body.hasSuffix(".") || body.hasSuffix("!") || body.hasSuffix("?")) {
                    while let c = piece.last, ",;:- ".contains(c) { piece.removeLast() }
                    piece += "."
                }
                chunks.append((piece, pause))
            }
        }
        if !chunks.isEmpty { chunks[chunks.count - 1].1 = 0 }
        return chunks
    }
}
