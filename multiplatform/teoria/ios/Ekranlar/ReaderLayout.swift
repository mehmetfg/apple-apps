// Reader layout — the book as typeset pages (TextKit). Every chapter starts on a new page, like a printed book.
// One NSLayoutManager per chapter holds all of that chapter's page containers; a page view draws its container's
// glyphs directly, so what is measured is exactly what is drawn (no re-layout, no overflow).
import SwiftUI
#if canImport(UIKit)
import UIKit
typealias PFont = UIFont
typealias PColor = UIColor
#else
import AppKit
typealias PFont = NSFont
typealias PColor = NSColor
#endif

enum ReaderTheme: String, CaseIterable, Identifiable {
    case paper, sepia, night
    var id: String { rawValue }
    var name: String { switch self { case .paper: "Kâğıt"; case .sepia: "Sepya"; case .night: "Gece" } }
    var background: Color { switch self { case .paper: Color(hex: 0xFBF9F4); case .sepia: Color(hex: 0xF4EAD5); case .night: Color(hex: 0x141414) } }
    var ink: PColor { switch self { case .paper: PColor(hex: 0x1D1B18); case .sepia: PColor(hex: 0x3A2E20); case .night: PColor(hex: 0xD8D3C8) } }
    var muted: PColor { switch self { case .paper: PColor(hex: 0x8A857C); case .sepia: PColor(hex: 0x8C7A5F); case .night: PColor(hex: 0x7D786F) } }
    var accent: PColor { switch self { case .paper: PColor(hex: 0x1673E6); case .sepia: PColor(hex: 0x9A5B1E); case .night: PColor(hex: 0x5FA8FF) } }
    var isDark: Bool { self == .night }
}

extension Color {
    init(hex: UInt32) { self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255) }
}
extension PColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

/// Highlight tints, one per Voice Dream colour (core claim · agree · term · objection), soft like a marker.
enum Marker {
    static func color(_ c: Int, dark: Bool) -> PColor {
        let hex: UInt32 = switch c { case 1: 0xFFD54A; case 2: 0x7ED69B; case 3: 0x7DB8FF; case 4: 0xFF9F6B; default: 0xFFD54A }
        return PColor(hex: hex, alpha: dark ? 0.32 : 0.42)
    }
    static func swatch(_ c: Int) -> Color { Color(PColor(hex: { switch c { case 1: 0xE8B20E; case 2: 0x3FB86A; case 3: 0x3D8EF0; case 4: 0xF0742E; default: 0xE8B20E } }())) }
}

struct ReaderStyle: Equatable {
    var size: CGFloat = 19
    var theme: ReaderTheme = .paper
    var justify = false
    var lineSpacing: CGFloat { size * 0.42 }

    func font(_ s: CGFloat, bold: Bool = false, italic: Bool = false) -> PFont {
        #if canImport(UIKit)
        var d = UIFont.systemFont(ofSize: s, weight: bold ? .semibold : .regular).fontDescriptor
        d = d.withDesign(.serif) ?? d
        if italic, let i = d.withSymbolicTraits(.traitItalic) { d = i }
        return UIFont(descriptor: d, size: s)
        #else
        var d = NSFont.systemFont(ofSize: s, weight: bold ? .semibold : .regular).fontDescriptor
        d = d.withDesign(.serif) ?? d
        if italic { d = d.withSymbolicTraits(.italic) }
        return NSFont(descriptor: d, size: s) ?? NSFont.systemFont(ofSize: s)
        #endif
    }
    func sans(_ s: CGFloat, weight: PFont.Weight = .semibold) -> PFont { PFont.systemFont(ofSize: s, weight: weight) }
}

/// Custom attribute keys: a highlight id on its characters, a block address on paragraphs.
extension NSAttributedString.Key {
    static let teoriaHighlight = NSAttributedString.Key("teoriaHighlight")
    static let teoriaBlock = NSAttributedString.Key("teoriaBlock")
}

/// One typeset page: which chapter layout, which container, and its characters in the whole-book string.
extension NSRange {
    var nonEmpty: NSRange? { length > 0 && location != NSNotFound ? self : nil }
}

struct BookPage: Hashable {
    let chapter: Int
    let container: Int
    let range: NSRange          // in the chapter's string
    let start: Int              // global character offset (stable across font sizes)
    var highlightIDs: [String]
}

/// A transient mark drawn under the text: the sentence being read aloud, or a search hit.
struct LiveMark: Equatable {
    let chapter: Int
    let range: NSRange          // chapter-local characters
    let kind: Kind
    var word: NSRange? = nil    // speech: the word being spoken now, inside `range`
    enum Kind { case speech, search }
}

final class BookLayout: @unchecked Sendable {
    let book: Book
    let style: ReaderStyle
    let size: CGSize
    private(set) var managers: [NSLayoutManager] = []
    private(set) var storages: [NSTextStorage] = []
    private(set) var pages: [BookPage] = []
    private(set) var chapterFirstPage: [Int] = []
    private var chapterOffsets: [Int] = []
    /// chapter → block → (start in the chapter string, UTF-16 length of the block's own text)
    private(set) var blockStarts: [[Int: (Int, Int)]] = []

    init(book: Book, style: ReaderStyle, size: CGSize, hidden: Set<String>) {
        self.book = book; self.style = style; self.size = size
        var offset = 0
        for (ci, ch) in book.chapters.enumerated() {
            let s = BookLayout.attributed(ch, ci, book: book, style: style, hidden: hidden)
            let storage = NSTextStorage(attributedString: s)
            var starts: [Int: (Int, Int)] = [:]
            storage.enumerateAttribute(.teoriaBlock, in: NSRange(location: 0, length: storage.length)) { v, r, _ in
                if let b = v as? Int, starts[b] == nil { starts[b] = (r.location, max(0, r.length - 1)) }   // minus the paragraph break
            }
            blockStarts.append(starts)
            let lm = NSLayoutManager()
            storage.addLayoutManager(lm)
            chapterFirstPage.append(pages.count)
            chapterOffsets.append(offset)
            var k = 0
            while true {
                let tc = NSTextContainer(size: size)
                tc.lineFragmentPadding = 0
                lm.addTextContainer(tc)
                let gr = lm.glyphRange(for: tc)
                let cr = lm.characterRange(forGlyphRange: gr, actualGlyphRange: nil)
                if cr.length == 0 && k > 0 { lm.removeTextContainer(at: k); break }
                pages.append(BookPage(chapter: ci, container: k, range: cr, start: offset + cr.location,
                                      highlightIDs: BookLayout.ids(in: cr, storage)))
                k += 1
                if NSMaxRange(cr) >= storage.length { break }
            }
            managers.append(lm); storages.append(storage)
            offset += storage.length
        }
    }

    private static func ids(in r: NSRange, _ st: NSTextStorage) -> [String] {
        var ids: [String] = []
        st.enumerateAttribute(.teoriaHighlight, in: r) { v, _, _ in
            if let id = v as? String, !ids.contains(id) { ids.append(id) }
        }
        return ids
    }

    var pageCount: Int { pages.count }

    func page(forOffset o: Int) -> Int {
        var lo = 0, hi = pages.count - 1, best = 0
        while lo <= hi {
            let m = (lo + hi) / 2
            if pages[m].start <= o { best = m; lo = m + 1 } else { hi = m - 1 }
        }
        return best
    }

    func page(chapter: Int, block: Int, offset: Int = 0) -> Int {
        guard chapter < storages.count else { return 0 }
        guard let (start, _) = blockStarts[chapter][block] else { return chapterFirstPage[chapter] }
        return page(forOffset: chapterOffsets[chapter] + start + offset)
    }

    func page(chapter: Int, local: Int) -> Int { page(forOffset: (chapterOffsets[safe: chapter] ?? 0) + local) }

    /// Chapter-local range of a piece of a block's text (UTF-16 offsets within the block).
    func range(chapter: Int, block: Int, s: Int, e: Int) -> NSRange? {
        guard let (start, len) = blockStarts[safe: chapter]?[block] else { return nil }
        let a = min(max(0, s), len), z = min(max(a, e), len)
        return NSRange(location: start + a, length: z - a)
    }

    /// The character under a point: the whole line counts (line spacing included), so a tap between two lines
    /// still lands on the nearer one; a point beyond the end of a line or outside the text returns nil.
    private func character(at point: CGPoint, page p: Int) -> (chapter: Int, index: Int)? {
        guard let pg = pages[safe: p] else { return nil }
        let lm = managers[pg.chapter]
        let tc = lm.textContainers[pg.container]
        var frac: CGFloat = 0
        let g = lm.glyphIndex(for: point, in: tc, fractionOfDistanceThroughGlyph: &frac)
        guard g < lm.numberOfGlyphs else { return nil }
        var lineRange = NSRange()
        let line = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: &lineRange)
        let used = lm.lineFragmentUsedRect(forGlyphAt: g, effectiveRange: nil)
        guard line.insetBy(dx: 0, dy: -4).contains(point), point.x <= used.maxX + 12, point.x >= used.minX - 12 else { return nil }
        let c = lm.characterIndexForGlyph(at: g)
        guard c < storages[pg.chapter].length else { return nil }
        return (pg.chapter, c)
    }

    /// What is under a point on a page: chapter, block and UTF-16 offset in the block's text.
    func spot(at point: CGPoint, page p: Int) -> (ch: Int, b: Int, off: Int)? {
        guard let (ch, c) = character(at: point, page: p) else { return nil }
        let st = storages[ch]
        guard let b = st.attribute(.teoriaBlock, at: c, effectiveRange: nil) as? Int, let (start, _) = blockStarts[ch][b] else { return nil }
        return (ch, b, c - start)
    }

    func highlight(at point: CGPoint, page p: Int) -> String? {
        guard let (ch, c) = character(at: point, page: p) else { return nil }
        return storages[ch].attribute(.teoriaHighlight, at: c, effectiveRange: nil) as? String
    }

    /// Paint a new highlight in place (background only, so pages keep their characters; no relayout).
    func apply(_ h: BookHighlight) {
        for p in h.at {
            guard let r = range(chapter: p.ch, block: p.b, s: p.s, e: p.e), r.length > 0 else { continue }
            let st = storages[p.ch]
            st.addAttributes([.backgroundColor: Marker.color(h.color, dark: style.theme.isDark), .teoriaHighlight: h.id], range: r)
            refreshIDs(chapter: p.ch)
        }
    }

    func remove(_ id: String) {
        for (ci, st) in storages.enumerated() {
            var hit = false
            st.enumerateAttribute(.teoriaHighlight, in: NSRange(location: 0, length: st.length)) { v, r, _ in
                if (v as? String) == id {
                    st.removeAttribute(.backgroundColor, range: r); st.removeAttribute(.teoriaHighlight, range: r); hit = true
                }
            }
            if hit { refreshIDs(chapter: ci) }
        }
    }

    private func refreshIDs(chapter: Int) {
        for i in pages.indices where pages[i].chapter == chapter {
            pages[i].highlightIDs = BookLayout.ids(in: pages[i].range, storages[chapter])
        }
    }

    func draw(page p: Int, origin: CGPoint, live: LiveMark? = nil) {
        guard let pg = pages[safe: p] else { return }
        let lm = managers[pg.chapter]
        let tc = lm.textContainers[pg.container]
        let gr = lm.glyphRange(for: tc)
        if let live, live.chapter == pg.chapter {
            func fill(_ range: NSRange, _ color: PColor, radius: CGFloat) {
                guard let r = NSIntersectionRange(range, pg.range).nonEmpty else { return }
                let lg = lm.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
                color.setFill()
                lm.enumerateEnclosingRects(forGlyphRange: lg, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: tc) { rect, _ in
                    let box = rect.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: -2, dy: -1)
                    #if canImport(UIKit)
                    UIBezierPath(roundedRect: box, cornerRadius: radius).fill()
                    #else
                    NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius).fill()
                    #endif
                }
            }
            if live.kind == .speech {
                // the sentence faintly, the word being spoken strongly — the cursor follows the voice word by word
                fill(live.range, style.theme.accent.withAlphaComponent(style.theme.isDark ? 0.20 : 0.10), radius: 4)
                if let w = live.word, w.length > 0 {
                    fill(w, style.theme.accent.withAlphaComponent(style.theme.isDark ? 0.55 : 0.32), radius: 3)
                }
            } else {
                fill(live.range, PColor(hex: 0xFF9F0A, alpha: 0.45), radius: 4)
            }
        }
        lm.drawBackground(forGlyphRange: gr, at: origin)
        lm.drawGlyphs(forGlyphRange: gr, at: origin)
    }

    // MARK: attributed text

    static func attributed(_ ch: BookChapter, _ ci: Int, book: Book, style: ReaderStyle, hidden: Set<String>) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let ink = style.theme.ink, muted = style.theme.muted
        let s = style.size

        func para(_ align: NSTextAlignment = .natural, indent: CGFloat = 0, before: CGFloat = 0, after: CGFloat = 0,
                  line: CGFloat? = nil, head: CGFloat = 0) -> NSParagraphStyle {
            let p = NSMutableParagraphStyle()
            p.alignment = align
            p.firstLineHeadIndent = indent + head
            p.headIndent = head
            p.tailIndent = head > 0 ? -head : 0
            p.paragraphSpacingBefore = before
            p.paragraphSpacing = after
            p.lineSpacing = line ?? style.lineSpacing
            p.hyphenationFactor = 0.85
            #if canImport(UIKit)
            p.lineBreakStrategy = .pushOut
            #endif
            return p
        }

        // chapter opening: set low on the page like a printed chapter (spacing before the first line of a page is
        // ignored by TextKit, so the drop is an empty line of fixed height)
        let drop = NSMutableParagraphStyle(); drop.minimumLineHeight = s * 4.2; drop.maximumLineHeight = s * 4.2
        out.append(NSAttributedString(string: "\n", attributes: [.font: style.font(s), .paragraphStyle: drop]))
        if let part = ch.part, !part.isEmpty {
            out.append(NSAttributedString(string: part.uppercased(with: Dil.tr) + "\n", attributes: [
                .font: style.sans(s * 0.62), .foregroundColor: muted, .kern: 1.6,
                .paragraphStyle: para(.center, after: s * 0.9)]))
        }
        out.append(NSAttributedString(string: ch.title + "\n", attributes: [
            .font: style.font(s * 1.55, bold: true), .foregroundColor: ink,
            .paragraphStyle: para(.center, before: s * 0.2, after: ch.sub == nil ? s * 1.8 : s * 0.4, line: s * 0.25)]))
        if let sub = ch.sub, !sub.isEmpty {
            out.append(NSAttributedString(string: sub + "\n", attributes: [
                .font: style.font(s * 0.95, italic: true), .foregroundColor: muted,
                .paragraphStyle: para(.center, after: s * 1.8)]))
        }

        let marks = book.highlights.flatMap { h in h.at.filter { $0.ch == ci }.map { (h, $0) } }
        var afterHeading = true
        for (bi, b) in ch.blocks.enumerated() {
            if b.st == "tekrar" || hidden.contains("\(ci).\(bi)") { continue }
            let start = out.length
            if b.isHeading {
                let essence = b.st == "oz-head"
                out.append(NSAttributedString(string: (essence ? b.x.uppercased(with: Dil.tr) : b.x) + "\n", attributes: [
                    .font: essence ? style.sans(s * 0.62) : style.font(s * 1.08, bold: true),
                    .foregroundColor: essence ? style.theme.accent : ink, .kern: essence ? 1.4 : 0,
                    .paragraphStyle: para(essence ? .left : .natural, before: s * 1.3, after: s * 0.5)]))
                afterHeading = true
            } else if b.st == "oz" {
                out.append(NSAttributedString(string: b.x + "\n", attributes: [
                    .font: style.font(s * 0.92, italic: true), .foregroundColor: ink.withAlphaComponent(0.88),
                    .paragraphStyle: para(.natural, after: s * 0.5, head: s * 0.9)]))
                afterHeading = false
            } else {
                out.append(NSAttributedString(string: b.x + "\n", attributes: [
                    .font: style.font(s), .foregroundColor: ink,
                    .paragraphStyle: para(style.justify ? .justified : .natural, indent: afterHeading ? 0 : s * 1.3, after: s * 0.18)]))
                afterHeading = false
            }
            let r = NSRange(location: start, length: out.length - start)
            out.addAttribute(.teoriaBlock, value: bi, range: r)
            let textLen = (b.x as NSString).length
            for (h, p) in marks where p.b == bi {
                let a = max(0, min(p.s, textLen)), z = max(a, min(p.e, textLen))
                guard z > a else { continue }
                let hr = NSRange(location: start + a, length: z - a)
                out.addAttributes([.backgroundColor: Marker.color(h.color, dark: style.theme.isDark),
                                   .teoriaHighlight: h.id], range: hr)
                if h.note != nil { out.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: hr) }
            }
        }
        if out.length == 0 { out.append(NSAttributedString(string: " ")) }
        out.addAttribute(NSAttributedString.Key("NSLanguage"), value: "tr", range: NSRange(location: 0, length: out.length))
        return out
    }
}

// MARK: - Page view

#if canImport(UIKit)
final class PageCanvasView: UIView {
    var layout: BookLayout?
    var index = 0
    var inset = CGPoint.zero
    var live: LiveMark?
    override func draw(_ rect: CGRect) {
        guard let layout, index < layout.pages.count else { return }
        layout.draw(page: index, origin: inset, live: live)
    }
}

struct PageCanvas: UIViewRepresentable {
    let layout: BookLayout
    let index: Int
    let inset: CGPoint
    var live: LiveMark? = nil
    var revision = 0
    func makeUIView(context: Context) -> PageCanvasView {
        let v = PageCanvasView(); v.backgroundColor = .clear; v.isOpaque = false; v.contentMode = .redraw
        return v
    }
    func updateUIView(_ v: PageCanvasView, context: Context) {
        v.layout = layout; v.index = index; v.inset = inset; v.live = live; v.setNeedsDisplay()
    }
}
#else
final class PageCanvasView: NSView {
    var layout: BookLayout?
    var index = 0
    var inset = CGPoint.zero
    var live: LiveMark?
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard let layout, index < layout.pages.count else { return }
        layout.draw(page: index, origin: inset, live: live)
    }
}

struct PageCanvas: NSViewRepresentable {
    let layout: BookLayout
    let index: Int
    let inset: CGPoint
    var live: LiveMark? = nil
    var revision = 0
    func makeNSView(context: Context) -> PageCanvasView { PageCanvasView() }
    func updateNSView(_ v: PageCanvasView, context: Context) {
        v.layout = layout; v.index = index; v.inset = inset; v.live = live; v.needsDisplay = true
    }
}
#endif
