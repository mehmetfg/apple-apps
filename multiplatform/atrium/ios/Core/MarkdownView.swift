// Renders Obsidian-flavoured Markdown as native SwiftUI blocks.
// Wikilinks become tappable `atrium-note:` links; embeds become chips.
import SwiftUI

enum MarkdownBlock: Identifiable {
    case heading(Int, String)
    case paragraph(String)
    case listItem(indent: Int, marker: String, checked: Bool?, text: String)
    case quote(String, callout: String?)
    case code(String)
    case table([[String]])
    case embed(String)
    case rule

    var id: String {
        switch self {
        case .heading(let l, let t): return "h\(l)\(t)"
        case .paragraph(let t): return "p\(t.prefix(80))\(t.count)"
        case .listItem(let i, let m, _, let t): return "l\(i)\(m)\(t.prefix(80))"
        case .quote(let t, _): return "q\(t.prefix(80))"
        case .code(let t): return "c\(t.prefix(80))\(t.count)"
        case .table(let r): return "t\(r.first?.joined() ?? "")\(r.count)"
        case .embed(let t): return "e\(t)"
        case .rule: return "r\(UUID().uuidString)"
        }
    }
}

enum MarkdownParser {
    static func blocks(_ text: String) -> [MarkdownBlock] {
        var out: [MarkdownBlock] = []
        var paragraph: [String] = []
        var quote: [String] = []
        var callout: String?
        var code: [String]?
        var table: [[String]] = []

        func flush() {
            if !paragraph.isEmpty { out.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = [] }
            if !quote.isEmpty { out.append(.quote(quote.joined(separator: "\n"), callout: callout)); quote = []; callout = nil }
            if !table.isEmpty { out.append(.table(table)); table = [] }
        }

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.replacingOccurrences(of: "\t", with: "    ")
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if var c = code {
                if trimmed.hasPrefix("```") { out.append(.code(c.joined(separator: "\n"))); code = nil } else { c.append(rawLine); code = c }
                continue
            }
            if trimmed.hasPrefix("```") { flush(); code = []; continue }
            if trimmed.isEmpty { flush(); continue }
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
                if !paragraph.isEmpty || !quote.isEmpty { let t = table; table = []; flush(); table = t }
                let cells = trimmed.dropFirst().dropLast().split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
                if !cells.allSatisfy({ $0.allSatisfy { "-: ".contains($0) } }) { table.append(cells) }
                continue
            }
            if trimmed.hasPrefix(">") {
                if !paragraph.isEmpty || !table.isEmpty { let q = quote; quote = []; flush(); quote = q }
                var content = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                if quote.isEmpty, content.hasPrefix("[!"), let close = content.firstIndex(of: "]") {
                    callout = String(content[content.index(content.startIndex, offsetBy: 2)..<close])
                    content = String(content[content.index(after: close)...]).trimmingCharacters(in: CharacterSet(charactersIn: "-+ "))
                }
                if !content.isEmpty { quote.append(content) }
                continue
            }
            if trimmed == "---" || trimmed == "***" || trimmed == "___" { flush(); out.append(.rule); continue }
            if let level = headingLevel(trimmed) {
                flush()
                out.append(.heading(level, String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)))
                continue
            }
            if trimmed.hasPrefix("![["), trimmed.hasSuffix("]]") {
                flush()
                out.append(.embed(String(trimmed.dropFirst(3).dropLast(2))))
                continue
            }
            if let item = listItem(line) { flush(); out.append(item); continue }
            if !quote.isEmpty || !table.isEmpty { flush() }
            paragraph.append(trimmed)
        }
        if let c = code { out.append(.code(c.joined(separator: "\n"))) }
        flush()
        return out
    }

    private static func headingLevel(_ s: String) -> Int? {
        var n = 0
        for ch in s { if ch == "#" { n += 1 } else { break } }
        guard (1...6).contains(n), s.count > n, s[s.index(s.startIndex, offsetBy: n)] == " " else { return nil }
        return n
    }

    private static func listItem(_ line: String) -> MarkdownBlock? {
        let indent = line.prefix { $0 == " " }.count / 2
        let s = line.trimmingCharacters(in: .whitespaces)
        var marker = "•"
        var rest: Substring
        if s.hasPrefix("- ") || s.hasPrefix("* ") || s.hasPrefix("+ ") {
            rest = s.dropFirst(2)
        } else if let dot = s.firstIndex(of: "."), s[..<dot].allSatisfy(\.isNumber), !s[..<dot].isEmpty,
                  s.index(after: dot) < s.endIndex, s[s.index(after: dot)] == " " {
            marker = String(s[...dot])
            rest = s[s.index(dot, offsetBy: 2)...]
        } else { return nil }
        var checked: Bool?
        if rest.hasPrefix("[ ] ") { checked = false; rest = rest.dropFirst(4) }
        else if rest.hasPrefix("[x] ") || rest.hasPrefix("[X] ") { checked = true; rest = rest.dropFirst(4) }
        return .listItem(indent: indent, marker: marker, checked: checked, text: String(rest))
    }

    private static let wikilink = try! NSRegularExpression(pattern: #"\[\[([^\]|]+)(?:\|([^\]]+))?\]\]"#)
    private static let highlight = try! NSRegularExpression(pattern: #"==([^=]+)=="#)

    /// Inline Markdown → AttributedString, with wikilinks turned into app links.
    static func inline(_ s: String) -> AttributedString {
        let ns = s as NSString
        var text = s
        for m in wikilink.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
            let target = ns.substring(with: m.range(at: 1))
            let label = m.range(at: 2).location != NSNotFound ? ns.substring(with: m.range(at: 2)) : target.split(separator: "/").last.map(String.init) ?? target
            let encoded = target.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? target
            let r = Range(m.range, in: text)!
            text.replaceSubrange(r, with: "[\(label.replacingOccurrences(of: "]", with: ""))](atrium-note:\(encoded))")
        }
        text = highlight.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: "**$1**")
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(s)
    }
}

struct MarkdownView: View {
    var text: String
    var accent: Color = Palette.accent
    private var blocks: [MarkdownBlock] { MarkdownParser.blocks(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .tint(accent)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let t):
            Text(MarkdownParser.inline(t))
                .font(level == 1 ? .title.weight(.bold) : level == 2 ? .title2.weight(.bold) : level == 3 ? .title3.weight(.semibold) : .headline)
                .fontDesign(.serif)
                .padding(.top, level <= 2 ? 10 : 4)
        case .paragraph(let t):
            Text(MarkdownParser.inline(t)).font(.body).fontDesign(.serif).lineSpacing(4)
        case .listItem(let indent, let marker, let checked, let t):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let checked {
                    Image(systemName: checked ? "checkmark.square.fill" : "square").foregroundStyle(checked ? accent : .secondary)
                } else {
                    Text(marker).foregroundStyle(accent).font(.body.weight(.bold))
                }
                Text(MarkdownParser.inline(t)).fontDesign(.serif).strikethrough(checked == true, color: .secondary)
                    .foregroundStyle(checked == true ? .secondary : .primary)
            }
            .padding(.leading, CGFloat(indent) * 18)
        case .quote(let t, let callout):
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 2).fill(accent.opacity(0.6)).frame(width: 4)
                VStack(alignment: .leading, spacing: 4) {
                    if let callout { Text(callout.uppercased()).font(.caption.weight(.bold)).foregroundStyle(accent) }
                    Text(MarkdownParser.inline(t)).fontDesign(.serif).italic(callout == nil).foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        case .code(let t):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(t).font(.system(.footnote, design: .monospaced)).padding(12)
            }
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        case .table(let rows):
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                Text(MarkdownParser.inline(cell)).font(i == 0 ? .footnote.weight(.bold) : .footnote)
                            }
                        }
                        if i == 0 { Divider() }
                    }
                }
                .padding(12)
            }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        case .embed(let target):
            Link(destination: URL(string: "atrium-note:" + (target.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? target))!) {
                Label(target, systemImage: "rectangle.on.rectangle").font(.footnote.weight(.medium))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(accent.opacity(0.1), in: Capsule())
            }
        case .rule:
            Divider().padding(.vertical, 4)
        }
    }
}
