// Turns a file into readable text: one paragraph per line, headings at their offsets, PDF page starts.
// Runs off the main thread (see AppModel.importFiles).
import Foundation
import PDFKit
import NaturalLanguage
import UniformTypeIdentifiers

struct ImportedDocument: Sendable {
    var title: String
    var author: String?
    var format: DocumentFormat
    var sourceName: String
    var content: DocumentContent
    var wordCount: Int
    var language: String?
    var cover: Data? = nil                              // JPEG, at most 600 px tall
}

enum ImportError: LocalizedError {
    case unsupported(String)
    case unreadable(String)
    case empty(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let n): "“\(n)” biçimi desteklenmiyor."
        case .unreadable(let n): "“\(n)” okunamadı."
        case .empty(let n): "“\(n)” içinde okunacak metin bulunamadı. Taranmış bir PDF olabilir."
        }
    }
}

enum DocumentImporter {
    static func importFile(at url: URL) throws -> ImportedDocument {
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        let base = url.deletingPathExtension().lastPathComponent
        var result: ImportedDocument
        switch ext {
        case "pdf": result = try pdf(url, name: name, base: base)
        case "epub": result = try epub(url, name: name, base: base)
        case "docx": result = try docx(url, name: name, base: base)
        case "html", "htm", "xhtml": result = try html(url, name: name, base: base)
        case "rtf", "rtfd": result = try rtf(url, name: name, base: base)
        case "md", "markdown": result = try markdown(url, name: name, base: base)
        default:
            if ext == "txt" || ext.isEmpty || (UTType(filenameExtension: ext)?.conforms(to: .text) ?? false) {
                result = try plain(url, name: name, base: base)
            } else {
                throw ImportError.unsupported(name)
            }
        }
        guard !result.content.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ImportError.empty(name) }
        return result
    }

    static func fromClipboard(_ text: String) -> ImportedDocument? {
        let paragraphs = splitParagraphs(text)
        guard !paragraphs.isEmpty else { return nil }
        let title = String(paragraphs[0].prefix(60))
        return assemble(title: title, author: nil, format: .clipboard, sourceName: "Pano", paragraphs: paragraphs, headings: [])
    }

    // MARK: formats

    private static func plain(_ url: URL, name: String, base: String) throws -> ImportedDocument {
        guard let data = try? Data(contentsOf: url) else { throw ImportError.unreadable(name) }
        let text = decode(data)
        return assemble(title: base, author: nil, format: .txt, sourceName: name, paragraphs: splitParagraphs(text), headings: [])
    }

    private static func markdown(_ url: URL, name: String, base: String) throws -> ImportedDocument {
        guard let data = try? Data(contentsOf: url) else { throw ImportError.unreadable(name) }
        let (paragraphs, headings) = parseMarkdown(decode(data))
        let title = headings.first(where: { $0.level == 1 })?.title ?? base
        return assemble(title: title, author: nil, format: .markdown, sourceName: name, paragraphs: paragraphs, headings: headings)
    }

    /// Markdown → readable paragraphs and headings (front matter, fences, tables, links and emphasis handled).
    static func parseMarkdown(_ text: String) -> ([String], [(paragraph: Int, title: String, level: Int)]) {
        var paragraphs: [String] = []
        var headings: [(paragraph: Int, title: String, level: Int)] = []
        var inFence = false
        var inFront = false
        for (n, raw) in text.components(separatedBy: .newlines).enumerated() {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if n == 0, line == "---" { inFront = true; continue }
            if inFront { if line == "---" { inFront = false }; continue }
            if line.hasPrefix("```") { inFence.toggle(); continue }
            if line.isEmpty || line.allSatisfy({ "-*_=|: ".contains($0) }) { continue }
            var level = 0
            while line.hasPrefix("#") { line.removeFirst(); level += 1 }
            line = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix(">") { line = String(line.drop { $0 == ">" || $0 == " " }) }
            if line.hasPrefix("|") {                     // table row → cells separated by a pause
                line = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " · ")
            }
            if !inFence, line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") { line = String(line.dropFirst(2)) }
            line = stripMarkdown(line)
            guard !line.isEmpty else { continue }
            if level > 0 { headings.append((paragraphs.count, line, level)) }
            paragraphs.append(line)
        }
        return (paragraphs, headings)
    }

    private static func stripMarkdown(_ s: String) -> String {
        var t = s
        // [text](link) and ![alt](src) → text; [[wiki|alias]] → alias
        t = t.replacingOccurrences(of: #"!?\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\[\[(?:[^\]|]*\|)?([^\]]*)\]\]"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(\*\*|__|\*|_|`|~~)"#, with: "", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespaces)
    }

    private static func html(_ url: URL, name: String, base: String) throws -> ImportedDocument {
        guard let data = try? Data(contentsOf: url) else { throw ImportError.unreadable(name) }
        let out = MarkupText.convert(decode(data))
        let title = out.title.flatMap { $0.isEmpty ? nil : $0 } ?? base
        return assemble(title: title, author: nil, format: .html, sourceName: name, paragraphs: out.paragraphs, headings: out.headings)
    }

    private static func rtf(_ url: URL, name: String, base: String) throws -> ImportedDocument {
        let type: NSAttributedString.DocumentType = url.pathExtension.lowercased() == "rtfd" ? .rtfd : .rtf
        guard let s = try? NSAttributedString(url: url, options: [.documentType: type], documentAttributes: nil) else {
            throw ImportError.unreadable(name)
        }
        return assemble(title: base, author: nil, format: .rtf, sourceName: name, paragraphs: splitParagraphs(s.string), headings: [])
    }

    private static func docx(_ url: URL, name: String, base: String) throws -> ImportedDocument {
        guard let zip = try? ZipArchive(url: url), let xml = zip.data(for: "word/document.xml") else { throw ImportError.unreadable(name) }
        let parser = DocxParser()
        parser.parse(xml)
        var title = base
        var author: String?
        if let core = zip.data(for: "docProps/core.xml") {
            let meta = SimpleXMLText.values(in: core, for: ["title", "creator"])
            if let t = meta["title"], !t.isEmpty { title = t }
            author = meta["creator"].flatMap { $0.isEmpty ? nil : $0 }
        }
        return assemble(title: title, author: author, format: .docx, sourceName: name, paragraphs: parser.paragraphs, headings: parser.headings)
    }

    private static func epub(_ url: URL, name: String, base: String) throws -> ImportedDocument {
        guard let zip = try? ZipArchive(url: url),
              let container = zip.data(for: "META-INF/container.xml"),
              let opfPath = SimpleXMLText.attribute("full-path", ofFirst: "rootfile", in: container),
              let opfData = zip.data(for: opfPath)
        else { throw ImportError.unreadable(name) }
        let opf = OPFParser()
        opf.parse(opfData)
        let dir = (opfPath as NSString).deletingLastPathComponent

        // table of contents: file → title (EPUB 3 nav, else EPUB 2 NCX)
        var tocTitles: [String: String] = [:]
        if let navHref = opf.navHref, let nav = zip.data(for: resolve(navHref, in: dir)) {
            let navDir = (resolve(navHref, in: dir) as NSString).deletingLastPathComponent
            for (href, title) in NavParser.links(in: nav) {
                let file = resolve(String(href.split(separator: "#").first ?? ""), in: navDir)
                if tocTitles[file] == nil { tocTitles[file] = title }
            }
        } else if let ncxHref = opf.ncxHref, let ncx = zip.data(for: resolve(ncxHref, in: dir)) {
            let ncxDir = (resolve(ncxHref, in: dir) as NSString).deletingLastPathComponent
            for (src, title) in NCXParser.points(in: ncx) {
                let file = resolve(String(src.split(separator: "#").first ?? ""), in: ncxDir)
                if tocTitles[file] == nil { tocTitles[file] = title }
            }
        }

        var paragraphs: [String] = []
        var headings: [(paragraph: Int, title: String, level: Int)] = []
        for href in opf.spineHrefs {
            let path = resolve(href, in: dir)
            guard let d = zip.data(for: path) else { continue }
            let out = MarkupText.convert(decode(d))
            guard !out.paragraphs.isEmpty else { continue }
            let start = paragraphs.count
            if let t = tocTitles[path] {
                headings.append((start, t, 1))
                for h in out.headings where h.level >= 2 && h.paragraph > 0 { headings.append((start + h.paragraph, h.title, 2)) }
            } else if tocTitles.isEmpty {
                for h in out.headings where h.level <= 2 { headings.append((start + h.paragraph, h.title, h.level)) }
            }
            paragraphs += out.paragraphs
        }
        let title = opf.title.flatMap { $0.isEmpty ? nil : $0 } ?? base
        var imported = assemble(title: title, author: opf.creator, format: .epub, sourceName: name, paragraphs: paragraphs, headings: headings)
        if let href = opf.coverHref, let data = zip.data(for: resolve(href, in: dir)) { imported.cover = CoverMaker.jpeg(fromImageData: data) }
        return imported
    }

    private static func pdf(_ url: URL, name: String, base: String) throws -> ImportedDocument {
        guard let doc = PDFDocument(url: url) else { throw ImportError.unreadable(name) }
        var text = ""
        var pages: [Int] = []
        var pageParagraphStart: [Int] = []
        var paragraphs: [String] = []
        for i in 0..<doc.pageCount {
            pages.append((text as NSString).length)
            pageParagraphStart.append(paragraphs.count)
            let raw = doc.page(at: i)?.string ?? ""
            let ps = reflowPDF(raw)
            paragraphs += ps
            text += ps.map { $0 + "\n" }.joined()
        }
        // headings from the PDF outline
        var headings: [(paragraph: Int, title: String, level: Int)] = []
        func walk(_ o: PDFOutline, level: Int) {
            for k in 0..<o.numberOfChildren {
                guard let c = o.child(at: k) else { continue }
                if let page = c.destination?.page, let idx = Optional(doc.index(for: page)), idx >= 0, idx < pageParagraphStart.count,
                   let label = c.label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
                    headings.append((pageParagraphStart[idx], label, level))
                }
                if level < 2 { walk(c, level: level + 1) }
            }
        }
        if let root = doc.outlineRoot { walk(root, level: 1) }
        let attrs = doc.documentAttributes ?? [:]
        let title = (attrs[PDFDocumentAttribute.titleAttribute] as? String).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? base
        let author = (attrs[PDFDocumentAttribute.authorAttribute] as? String).flatMap { $0.isEmpty ? nil : $0 }
        var imported = assemble(title: title, author: author, format: .pdf, sourceName: name, paragraphs: paragraphs, headings: headings)
        imported.content.pages = pages
        if let first = doc.page(at: 0) { imported.cover = CoverMaker.jpeg(fromPDFPage: first) }
        return imported
    }

    /// PDF text breaks every line. Join lines back into paragraphs: a line continues the previous one unless the
    /// previous line closes a sentence and is clearly shorter than a full line. Lone page numbers are dropped.
    static func reflowPDF(_ raw: String) -> [String] {
        let lines = raw.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        let full = lines.map(\.count).sorted().dropLast(lines.count / 10).last ?? 60
        var out: [String] = []
        var cur = ""
        var lastLine = 0                                // length of the last physical line joined into `cur`
        for line in lines {
            if line.isEmpty { if !cur.isEmpty { out.append(cur); cur = "" }; continue }
            if line.count <= 4, line.allSatisfy({ $0.isNumber || $0 == "-" || $0 == "–" }) { continue }
            defer { lastLine = line.count }
            if cur.isEmpty { cur = line; continue }
            let ends = cur.last.map { ".!?:”\"»)".contains($0) } ?? false
            let short = Double(lastLine) < Double(full) * 0.7
            let veryShort = Double(lastLine) < Double(full) * 0.55
            let nextUpper = line.first.map { $0.isUppercase || $0.isNumber || "“\"«".contains($0) } ?? false
            if short && (ends || (veryShort && nextUpper)) {
                // a sentence that ends a short line, or a short title-like line followed by a capital: new paragraph
                out.append(cur); cur = line
            } else if cur.hasSuffix("-"), let f = line.first, f.isLowercase {
                cur.removeLast(); cur += line
            } else {
                cur += " " + line
            }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    // MARK: helpers

    static func decode(_ data: Data) -> String {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { return String(decoding: data.dropFirst(3), as: UTF8.self) }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) { return String(data: data, encoding: .utf16) ?? "" }
        if let s = String(data: data, encoding: .utf8) { return s }
        let turkish = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.windowsLatin5.rawValue)))
        return String(data: data, encoding: turkish) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    static func splitParagraphs(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: "\t", with: " ").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// "OEBPS" + "../Text/ch%201.xhtml" → "Text/ch 1.xhtml"
    static func resolve(_ href: String, in dir: String) -> String {
        let decoded = href.removingPercentEncoding ?? href
        var parts = dir.isEmpty ? [] : dir.split(separator: "/").map(String.init)
        for p in decoded.split(separator: "/").map(String.init) {
            if p == ".." { if !parts.isEmpty { parts.removeLast() } }
            else if p != "." { parts.append(p) }
        }
        return parts.joined(separator: "/")
    }

    static func assemble(title: String, author: String?, format: DocumentFormat, sourceName: String,
                         paragraphs: [String], headings: [(paragraph: Int, title: String, level: Int)]) -> ImportedDocument {
        var offsets: [Int] = []
        var text = ""
        var length = 0
        for p in paragraphs {
            offsets.append(length)
            text += p + "\n"
            length += p.utf16.count + 1
        }
        let chapters = headings.compactMap { h -> Chapter? in
            guard h.paragraph < offsets.count else { return nil }
            return Chapter(title: h.title, offset: offsets[h.paragraph], level: h.level)
        }
        var words = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in words += 1 }
        let rec = NLLanguageRecognizer()
        rec.processString(String(text.prefix(6000)))
        return ImportedDocument(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines), author: author, format: format, sourceName: sourceName,
            content: DocumentContent(text: text, chapters: chapters, pages: []),
            wordCount: words, language: rec.dominantLanguage?.rawValue)
    }
}

// MARK: - small XML readers

/// Text of the first element with each given local name ("dc:title" → "title").
enum SimpleXMLText {
    static func values(in data: Data, for names: Set<String>) -> [String: String] {
        let d = Collector(names: names)
        let p = XMLParser(data: data); p.delegate = d; p.parse()
        return d.found
    }

    static func attribute(_ attr: String, ofFirst element: String, in data: Data) -> String? {
        let d = AttributeFinder(element: element, attr: attr)
        let p = XMLParser(data: data); p.delegate = d; p.parse()
        return d.value
    }

    private final class Collector: NSObject, XMLParserDelegate {
        let names: Set<String>
        var found: [String: String] = [:]
        var current: String?
        var buffer = ""
        init(names: Set<String>) { self.names = names }
        func parser(_ parser: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName q: String?, attributes a: [String: String] = [:]) {
            let local = String(e.split(separator: ":").last ?? Substring(e))
            if names.contains(local), found[local] == nil { current = local; buffer = "" }
        }
        func parser(_ parser: XMLParser, foundCharacters s: String) { if current != nil { buffer += s } }
        func parser(_ parser: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName q: String?) {
            let local = String(e.split(separator: ":").last ?? Substring(e))
            if local == current { found[local] = buffer.trimmingCharacters(in: .whitespacesAndNewlines); current = nil }
        }
    }

    private final class AttributeFinder: NSObject, XMLParserDelegate {
        let element: String, attr: String
        var value: String?
        init(element: String, attr: String) { self.element = element; self.attr = attr }
        func parser(_ parser: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName q: String?, attributes a: [String: String] = [:]) {
            let local = String(e.split(separator: ":").last ?? Substring(e))
            if value == nil, local == element, let v = a[attr] { value = v; parser.abortParsing() }
        }
    }
}

/// EPUB package: title, creator, manifest, spine, navigation documents.
private final class OPFParser: NSObject, XMLParserDelegate {
    var title: String?
    var creator: String?
    var navHref: String?
    var ncxHref: String?
    var spineHrefs: [String] = []
    var coverHref: String?
    private var coverID: String?
    private var manifest: [String: (href: String, type: String)] = [:]
    private var spineIDs: [String] = []
    private var tocID: String?
    private var current: String?
    private var buffer = ""

    func parse(_ data: Data) {
        let p = XMLParser(data: data); p.delegate = self; p.parse()
        spineHrefs = spineIDs.compactMap { manifest[$0]?.href }
        if coverHref == nil, let id = coverID { coverHref = manifest[id]?.href }
        if coverHref == nil {
            coverHref = manifest.first { ($0.key.lowercased().contains("cover") || $0.value.href.lowercased().contains("cover"))
                && $0.value.type.hasPrefix("image/") }?.value.href
        }
        if let t = tocID { ncxHref = manifest[t]?.href }
        if ncxHref == nil { ncxHref = manifest.values.first { $0.type == "application/x-dtbncx+xml" }?.href }
    }

    func parser(_ parser: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName q: String?, attributes a: [String: String] = [:]) {
        let local = String(e.split(separator: ":").last ?? Substring(e))
        switch local {
        case "item":
            if let id = a["id"], let href = a["href"] {
                manifest[id] = (href, a["media-type"] ?? "")
                let props = (a["properties"] ?? "").split(separator: " ")
                if props.contains("nav") { navHref = href }
                if props.contains("cover-image") { coverHref = href }
            }
        case "itemref":
            if let idref = a["idref"], a["linear"] != "no" { spineIDs.append(idref) }
        case "spine":
            tocID = a["toc"]
        case "meta":
            if a["name"] == "cover", let c = a["content"] { coverID = c }
        case "title", "creator":
            current = local; buffer = ""
        default: break
        }
    }
    func parser(_ parser: XMLParser, foundCharacters s: String) { if current != nil { buffer += s } }
    func parser(_ parser: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName q: String?) {
        let local = String(e.split(separator: ":").last ?? Substring(e))
        guard local == current else { return }
        let v = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if local == "title", title == nil { title = v }
        if local == "creator", creator == nil { creator = v }
        current = nil
    }
}

/// EPUB 3 navigation document: the <a href> links inside the toc <nav>, with their text.
private enum NavParser {
    static func links(in data: Data) -> [(String, String)] {
        let html = DocumentImporter.decode(data)
        var scope = html
        if let r = html.range(of: #"<nav[^>]*epub:type\s*=\s*["']toc["'][^>]*>"#, options: .regularExpression),
           let end = html.range(of: "</nav>", range: r.upperBound..<html.endIndex) {
            scope = String(html[r.upperBound..<end.lowerBound])
        }
        var out: [(String, String)] = []
        let re = try? NSRegularExpression(pattern: #"<a[^>]*href\s*=\s*["']([^"']+)["'][^>]*>(.*?)</a>"#, options: [.dotMatchesLineSeparators, .caseInsensitive])
        let ns = scope as NSString
        re?.enumerateMatches(in: scope, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            let href = ns.substring(with: m.range(at: 1))
            let inner = ns.substring(with: m.range(at: 2)).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            let title = MarkupText.decodeEntities(inner).trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { out.append((href, title)) }
        }
        return out
    }
}

/// EPUB 2 NCX: navPoint label + content src, in document order.
private final class NCXParser: NSObject, XMLParserDelegate {
    private var out: [(String, String)] = []
    private var label = ""
    private var inText = false
    private var pending: String?

    static func points(in data: Data) -> [(String, String)] {
        let d = NCXParser()
        let p = XMLParser(data: data); p.delegate = d; p.parse()
        return d.out
    }

    func parser(_ parser: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName q: String?, attributes a: [String: String] = [:]) {
        switch e {
        case "navPoint": label = ""; pending = nil
        case "text": inText = true
        case "content":
            if let src = a["src"] {
                let t = label.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { out.append((src, t)) }
                pending = src
            }
        default: break
        }
    }
    func parser(_ parser: XMLParser, foundCharacters s: String) { if inText { label += s } }
    func parser(_ parser: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName q: String?) {
        if e == "text" { inText = false }
    }
}

/// DOCX body: w:p paragraphs of w:t runs; heading styles become chapters.
private final class DocxParser: NSObject, XMLParserDelegate {
    var paragraphs: [String] = []
    var headings: [(paragraph: Int, title: String, level: Int)] = []
    private var current = ""
    private var inText = false
    private var headingLevel: Int?

    func parse(_ data: Data) { let p = XMLParser(data: data); p.delegate = self; p.parse() }

    func parser(_ parser: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName q: String?, attributes a: [String: String] = [:]) {
        switch e {
        case "w:p": current = ""; headingLevel = nil
        case "w:t": inText = true
        case "w:tab", "w:br", "w:cr": current += " "
        case "w:pStyle":
            let v = (a["w:val"] ?? "").lowercased()
            if v == "title" { headingLevel = 1 }
            else if v.hasPrefix("heading") || v.hasPrefix("balk") || v.hasPrefix("başlık") {
                headingLevel = Int(v.filter(\.isNumber)) ?? 1
            }
        default: break
        }
    }
    func parser(_ parser: XMLParser, foundCharacters s: String) { if inText { current += s } }
    func parser(_ parser: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName q: String?) {
        if e == "w:t" { inText = false }
        if e == "w:p" {
            let p = current.trimmingCharacters(in: .whitespaces)
            guard !p.isEmpty else { return }
            if let lv = headingLevel, lv <= 3 { headings.append((paragraphs.count, String(p.prefix(140)), lv)) }
            paragraphs.append(p)
        }
    }
}
