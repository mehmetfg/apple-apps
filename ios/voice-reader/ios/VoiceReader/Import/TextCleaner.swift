// The first pass on every imported document, for listening: whatever the format gave (a hard-wrapped .txt, a PDF
// with running heads, a DOCX with empty paragraphs), the reader gets one sentence-ending paragraph per line.
//
//   1. characters: zero-width and soft hyphens out, odd spaces to one space, "....." → "…", "!!!" → "!",
//      superscript footnote marks glued to words out, "word - word" dashes kept as a pause
//   2. lines that say nothing aloud: lone page numbers, separators (***, ———, ____), lone bullets, "Page 12 of 300"
//   3. running heads and feet: a short line that comes back on many pages
//   4. hard-wrapped text: a paragraph that stops mid-sentence and the next starting in lower case are one paragraph;
//      "philo-" + "sophy" → "philosophy"
//   5. shouting: a paragraph in capitals (not a short heading) is read as a sentence, not letter by letter
//
// Headings are never joined or dropped; their indexes are mapped to the new paragraphs.
import Foundation

enum TextCleaner {
    struct Result {
        var paragraphs: [String]
        var headings: [(paragraph: Int, title: String, level: Int)]
        /// Old paragraph index → new one (a dropped paragraph → the next one kept), for PDF page starts.
        var index: [Int]
    }

    /// `paged`: the source has pages (PDF), so a short line coming back on many of them is a running head.
    static func clean(_ paragraphs: [String], headings: [(paragraph: Int, title: String, level: Int)], paged: Bool = false) -> Result {
        let protected = Set(headings.map(\.paragraph))
        // 1-2: per paragraph
        var items: [(text: String, old: Int)] = []
        for (i, p) in paragraphs.enumerated() {
            let t = normalize(p)
            if protected.contains(i) { items.append((t.isEmpty ? p : t, i)); continue }
            if t.isEmpty || silent(t) { continue }
            items.append((t, i))
        }
        // 3: running heads (paged and long documents only: a novel's repeated "Evet." stays)
        if paged, items.count > 60 {
            var seen: [String: Int] = [:]
            for it in items where it.text.count <= 70 && !protected.contains(it.old) { seen[key(it.text), default: 0] += 1 }
            let limit = max(4, items.count / 80)
            let repeated = Set(seen.filter { $0.value >= limit }.map(\.key))
            if !repeated.isEmpty { items.removeAll { !protected.contains($0.old) && repeated.contains(key($0.text)) } }
        }
        // 4: join broken paragraphs
        var out: [(text: String, old: [Int])] = []
        for it in items {
            if let last = out.last, !protected.contains(it.old), !last.old.contains(where: protected.contains), continues(last.text, it.text) {
                var joined = last.text
                if joined.hasSuffix("-"), let f = it.text.first, f.isLowercase { joined.removeLast(); joined += it.text }
                else { joined += " " + it.text }
                out[out.count - 1] = (joined, last.old + [it.old])
            } else {
                out.append((it.text, [it.old]))
            }
        }
        // 5: capitals
        let final = out.enumerated().map { (_, o) in o.old.contains(where: protected.contains) ? o.text : uncapital(o.text) }
        // map headings
        var newIndex: [Int: Int] = [:]
        for (n, o) in out.enumerated() { for k in o.old { newIndex[k] = n } }
        let mapped = headings.compactMap { h -> (paragraph: Int, title: String, level: Int)? in
            guard let n = newIndex[h.paragraph] else { return nil }
            return (n, normalize(h.title).isEmpty ? h.title : normalize(h.title), h.level)
        }
        var index = Array(repeating: final.count, count: paragraphs.count + 1)
        for k in stride(from: paragraphs.count - 1, through: 0, by: -1) { index[k] = newIndex[k] ?? index[k + 1] }
        return Result(paragraphs: final, headings: mapped, index: Array(index.dropLast()))
    }

    // MARK: rules

    private static let zeroWidth = CharacterSet(charactersIn: "\u{200B}\u{200C}\u{200D}\u{2060}\u{FEFF}\u{00AD}")
    private static let oddSpaces = try! NSRegularExpression(pattern: "[\\u00A0\\u2000-\\u200A\\u202F\\u205F\\u3000\\t ]+")
    private static let superscripts = try! NSRegularExpression(pattern: "(?<=\\p{L}[.,;:!?”\"»)]?)[¹²³⁰⁴-⁹]+")
    private static let bracketNumber = try! NSRegularExpression(pattern: "(?<=\\p{L}[.,;:]?)\\[\\d{1,3}\\]")

    static func normalize(_ s: String) -> String {
        var t = String(String.UnicodeScalarView(s.unicodeScalars.filter { !zeroWidth.contains($0) }))
        t = replace(oddSpaces, in: t, with: " ")
        t = replace(superscripts, in: t, with: "")
        t = replace(bracketNumber, in: t, with: "")
        t = t.replacingOccurrences(of: #"\.{4,}"#, with: "…", options: .regularExpression)
        t = t.replacingOccurrences(of: "...", with: "…")
        t = t.replacingOccurrences(of: #"([!?])\1+"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+([,.;:!?…])"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"^[•·▪◦●○■□➢►\-–—*]+\s+"#, with: "", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Nothing to say aloud: a page number, a separator, "Sayfa 3 / 120", "- 12 -".
    static func silent(_ t: String) -> Bool {
        if !t.contains(where: { $0.isLetter || $0.isNumber }) { return true }
        if t.count <= 12, t.range(of: #"^[\-–—\s]*\d{1,4}[\-–—\s]*$"#, options: .regularExpression) != nil { return true }
        if t.range(of: #"^(sayfa|page|s\.|p\.)\s*\d{1,4}(\s*(/|of|\'den|’den)\s*\d{1,4})?$"#,
                   options: [.regularExpression, .caseInsensitive]) != nil { return true }
        return false
    }

    /// The next paragraph carries on the sentence: the first stops without a closing mark and the second begins in
    /// lower case (or after a hyphenated break).
    static func continues(_ a: String, _ b: String) -> Bool {
        guard let last = a.last, let first = b.first else { return false }
        if ".!?…:;”\"»)]".contains(last) { return false }
        if a.hasSuffix("-"), first.isLowercase { return true }
        return first.isLowercase && a.count >= 25
    }

    /// "BÖLÜM BİR: YOLUN BAŞI ve sonu" read as "Bölüm bir: yolun başı ve sonu" when it is a long all-capital line.
    static func uncapital(_ t: String) -> String {
        let letters = t.filter(\.isLetter)
        guard letters.count >= 25, letters.allSatisfy({ !$0.isLowercase }) else { return t }
        let tr = Locale(identifier: "tr_TR")
        let low = t.lowercased(with: tr)
        guard let f = low.first else { return t }
        return String(f).uppercased(with: tr) + low.dropFirst()
    }

    private static func key(_ t: String) -> String {
        t.lowercased().replacingOccurrences(of: #"\d+"#, with: "#", options: .regularExpression)
    }

    private static func replace(_ re: NSRegularExpression, in s: String, with r: String) -> String {
        re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: r)
    }
}
