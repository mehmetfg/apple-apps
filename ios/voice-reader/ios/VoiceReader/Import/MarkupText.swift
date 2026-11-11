// HTML / XHTML → plain paragraphs, without WebKit (NSAttributedString's HTML import must run on the main thread and is
// slow for whole books). Tolerant of broken markup: it scans tags rather than parsing a tree.
import Foundation

struct MarkupText {
    struct Output {
        var paragraphs: [String] = []
        var headings: [(paragraph: Int, title: String, level: Int)] = []
        var title: String?
    }

    private static let blockTags: Set<String> = [
        "p", "div", "br", "li", "ul", "ol", "tr", "td", "th", "table", "section", "article", "aside", "header", "footer",
        "blockquote", "pre", "hr", "dt", "dd", "dl", "figcaption", "figure", "h1", "h2", "h3", "h4", "h5", "h6", "nav", "main",
        "body", "caption",
    ]
    private static let skipTags: Set<String> = ["script", "style", "head", "svg", "math", "noscript", "template"]

    static func convert(_ html: String) -> Output {
        var out = Output()
        var current = ""
        var heading: (level: Int, start: Int)?
        var skipDepth = 0
        var skipName = ""
        var inTitle = false
        var titleText = ""

        func flush() {
            let p = current.trimmingCharacters(in: .whitespacesAndNewlines)
            current = ""
            guard !p.isEmpty else { return }
            out.paragraphs.append(p)
        }

        let s = Array(html.unicodeScalars)
        var i = 0
        var text = String.UnicodeScalarView()
        func takeText() {
            guard !text.isEmpty else { return }
            let chunk = decodeEntities(String(text))
            text = String.UnicodeScalarView()
            if inTitle { titleText += chunk; return }
            if skipDepth > 0 { return }
            appendCollapsed(chunk, to: &current)
        }

        while i < s.count {
            if s[i] == "<" {
                // comment
                if i + 3 < s.count, s[i + 1] == "!", s[i + 2] == "-", s[i + 3] == "-" {
                    takeText()
                    var j = i + 4
                    while j + 2 < s.count, !(s[j] == "-" && s[j + 1] == "-" && s[j + 2] == ">") { j += 1 }
                    i = j + 3
                    continue
                }
                var j = i + 1
                var quote: Unicode.Scalar?
                while j < s.count {
                    let c = s[j]
                    if let q = quote { if c == q { quote = nil } }
                    else if c == "\"" || c == "'" { quote = c }
                    else if c == ">" { break }
                    j += 1
                }
                guard j < s.count else { text.append(contentsOf: s[i...]); break }
                takeText()
                let tag = String(String.UnicodeScalarView(s[(i + 1)..<j]))
                i = j + 1
                let closing = tag.hasPrefix("/")
                let name = tag.drop { $0 == "/" }.prefix { !$0.isWhitespace && $0 != "/" && $0 != ">" }.lowercased()
                let bare = name.split(separator: ":").last.map(String.init) ?? name   // xhtml:p
                // a self-closing <title/> opens nothing, and a title left open ends with the head: either one used to
                // send the whole rest of the file into the title, and the chapter came out empty
                if inTitle, bare == "head" || bare == "body" { inTitle = false }
                if bare == "title" { inTitle = !closing && !tag.hasSuffix("/"); if closing { out.title = titleText.trimmingCharacters(in: .whitespacesAndNewlines) }; continue }
                if skipTags.contains(bare) {
                    if closing { if bare == skipName { skipDepth = max(0, skipDepth - 1); if skipDepth == 0 { skipName = "" } } }
                    else if !tag.hasSuffix("/") && (skipName.isEmpty || skipName == bare) { skipName = bare; skipDepth += 1 }
                    continue
                }
                if skipDepth > 0 { continue }
                if bare == "img", !closing, let alt = attribute("alt", in: tag), !alt.isEmpty, alt.count > 2 {
                    appendCollapsed(" " + alt + " ", to: &current)
                }
                if blockTags.contains(bare) {
                    if bare.count == 2, bare.first == "h", let lv = Int(String(bare.last!)) {
                        if !closing { flush(); heading = (lv, out.paragraphs.count) }
                        else {
                            flush()
                            if let h = heading, h.start < out.paragraphs.count {
                                let t = out.paragraphs[h.start..<out.paragraphs.count].joined(separator: " ")
                                out.headings.append((h.start, String(t.prefix(140)), h.level))
                            }
                            heading = nil
                        }
                    } else {
                        flush()
                    }
                }
            } else {
                text.append(s[i])
                i += 1
            }
        }
        takeText()
        flush()
        return out
    }

    private static func appendCollapsed(_ chunk: String, to current: inout String) {
        for ch in chunk {
            if ch.isWhitespace || ch == "\u{00A0}" {
                if !current.isEmpty, current.last != " " { current.append(" ") }
            } else {
                current.append(ch)
            }
        }
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        guard let r = tag.range(of: name + "=", options: .caseInsensitive) else { return nil }
        let rest = tag[r.upperBound...]
        guard let q = rest.first, q == "\"" || q == "'" else { return nil }
        let body = rest.dropFirst()
        guard let end = body.firstIndex(of: q) else { return nil }
        return decodeEntities(String(body[..<end]))
    }

    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "mdash": "—", "ndash": "–",
        "hellip": "…", "rsquo": "’", "lsquo": "‘", "ldquo": "“", "rdquo": "”", "laquo": "«", "raquo": "»",
        "copy": "©", "reg": "®", "trade": "™", "shy": "", "middot": "·", "bull": "•", "deg": "°", "times": "×",
        "eacute": "é", "egrave": "è", "agrave": "à", "acirc": "â", "icirc": "î", "ucirc": "û", "ouml": "ö", "uuml": "ü",
        "ccedil": "ç", "Ouml": "Ö", "Uuml": "Ü", "Ccedil": "Ç", "szlig": "ß", "auml": "ä", "Auml": "Ä", "zwj": "", "zwnj": "",
        "thinsp": " ", "ensp": " ", "emsp": " ", "prime": "′", "Prime": "″", "euro": "€", "pound": "£", "sect": "§", "para": "¶",
    ]

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "&", let semi = s[i...].prefix(12).firstIndex(of: ";") {
                let body = s[s.index(after: i)..<semi]
                var rep: String?
                if body.hasPrefix("#x") || body.hasPrefix("#X") {
                    if let v = UInt32(body.dropFirst(2), radix: 16), let u = Unicode.Scalar(v) { rep = String(Character(u)) }
                } else if body.hasPrefix("#") {
                    if let v = UInt32(body.dropFirst()), let u = Unicode.Scalar(v) { rep = String(Character(u)) }
                } else {
                    rep = named[String(body)]
                }
                if let rep { out += rep; i = s.index(after: semi); continue }
            }
            out.append(c)
            i = s.index(after: i)
        }
        return out
    }
}
