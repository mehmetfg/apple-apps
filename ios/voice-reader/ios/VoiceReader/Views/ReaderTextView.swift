// The page: the whole document in one scrolling UITextView (TextKit 1, non-contiguous layout, so long books stay
// fast).
//
// Reading marks are not text attributes. A band behind the spoken line (full width, exactly one line high) and a chip
// behind the spoken word are two plain views that sit under the text inside the scroll view; the word's text colour is
// a layout-manager temporary attribute. So a word change touches no text storage and relays out nothing: it moves two
// rectangles and recolours one word. The player tells the coordinator directly (`SpeechPlayer.onSpokenChange`), so no
// SwiftUI view is re-evaluated per word either.
//
// The page follows the voice like a book: the band moves down line by line and, when it nears the bottom, the page
// slides up once (a short ease) so the band sits at the chosen height again. Dragging the text stops following until
// "go to speech cursor".
import SwiftUI
import UIKit

struct ReaderStyle: Equatable {
    var font: ReaderFont
    var size: CGFloat
    var lineSpacing: CGFloat
    var kern: CGFloat
    var background: UIColor
    var foreground: UIColor
    var wordColor: UIColor?                      // chip behind the spoken word (nil = off)
    var lineColor: UIColor?                      // band behind the spoken line (nil = off)
    var focus: Bool
    var cursorFraction: CGFloat
    var bookLayout: Bool
    var lens = false                             // a glass band over the line being read, the line a touch larger (WordLens)
    var lensScale: CGFloat = 1.08                // how much larger at most (Settings.lensScale)
    var dim: PageDim = .off                      // the page around the line being read (PageShade)
    var dimStrength: CGFloat = 0.5
}

/// A note's place on the page: a dotted underline, a tap opens it.
struct NoteMark: Hashable {
    var id: String
    var range: NSRange
    var voice: Bool
}

struct ReaderTextView: UIViewRepresentable {
    let documentID: UUID
    let text: String
    let style: ReaderStyle
    let highlights: [Highlight]
    var notes: [NoteMark] = []
    let player: SpeechPlayer                     // read only inside the coordinator, never in body
    @Binding var following: Bool
    var scrollRequest: Int                       // offset to scroll to; changes trigger a jump
    var onTap: (Int) -> Void                     // single tap: show / hide the bars
    var onDoubleTap: (Int) -> Void               // double tap on a word: read from there
    var onHighlight: (NSRange, HighlightColor, String) -> Void
    var onRemoveHighlight: (UUID) -> Void
    var onNote: (NSRange, String) -> Void
    var onVoiceNote: (NSRange) -> Void = { _ in }
    var onOpenNote: (String) -> Void = { _ in }
    var onExpand: (NSRange, String) -> Void = { _, _ in }   // Genişlet: a prompt made from this passage
    var onBookmark: (Int) -> Void
    var onPlayFrom: (Int) -> Void
    var onVisibleOffset: (Int) -> Void
    var onScrolling: (Bool) -> Void = { _ in }   // the finger moves the page (true) / the page has come to rest
    /// The bars floating over the page (and the safe area): the text runs under them, the reading line stays clear.
    var insets: UIEdgeInsets = .zero

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = LayoutReportingTextView(usingTextLayoutManager: false)
        tv.onLayout = { [weak coordinator = context.coordinator, weak tv] in
            guard let coordinator, let tv else { return }
            coordinator.layoutChanged(tv)
        }
        tv.isEditable = false
        tv.scrollsToTop = false             // a tap on the status bar must not throw the book back to its first page
        tv.isSelectable = true
        tv.alwaysBounceVertical = true
        tv.textContainerInset = UIEdgeInsets(top: 14, left: 18, bottom: 28, right: 18)
        tv.layoutManager.allowsNonContiguousLayout = true
        tv.delegate = context.coordinator
        tv.dataDetectorTypes = []
        tv.contentInsetAdjustmentBehavior = .never
        tv.adjustsFontForContentSizeCategory = false
        let double = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        double.numberOfTapsRequired = 2
        double.delegate = context.coordinator
        tv.addGestureRecognizer(double)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.require(toFail: double)
        tap.delegate = context.coordinator
        tv.addGestureRecognizer(tap)
        // a selection turns into a yellow mark the moment the finger lifts
        // a long press takes the whole sentence, not the word
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pressed(_:)))
        press.minimumPressDuration = 0.4
        press.cancelsTouchesInView = false
        press.delegate = context.coordinator
        tv.addGestureRecognizer(press)
        let lift = TouchLiftRecognizer(target: nil, action: nil)
        lift.onLift = { [weak coordinator = context.coordinator] in coordinator?.fingerLifted() }
        lift.delegate = context.coordinator
        tv.addGestureRecognizer(lift)
        let menu = UIEditMenuInteraction(delegate: context.coordinator)
        tv.addInteraction(menu)
        context.coordinator.recolorMenu = menu
        context.coordinator.attach(tv)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update(tv)
    }

    static func dismantleUIView(_ tv: UITextView, coordinator: Coordinator) { coordinator.detach() }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate, UIEditMenuInteractionDelegate {
        var recolorMenu: UIEditMenuInteraction?
        private var recoloring: Highlight?
        var parent: ReaderTextView
        weak var textView: UITextView?
        private var builtFor: (UUID, ReaderStyle, [Highlight], [NoteMark])?
        private var openingNote: NoteMark?
        private var quietUntil = Date.distantPast       // after a double tap: its word selection is not a mark
        private var pressSentence: NSRange?             // a long press is down on this sentence
        /// The sentence a long press just marked, still selected with its handles: dragging a handle and lifting
        /// narrows (or widens) that same mark instead of adding a second one.
        private var shaping: (range: NSRange, color: HighlightColor)?
        private var pressedAt = Date.distantPast        // the lift of a long press is not a tap
        private var lastScrollRequest = -1
        private var lastJump: (offset: Int, fraction: CGFloat, at: Date)?
        /// The page whose marks the player drives now. A reader that opens while another closes must not lose them.
        private static weak var owner: Coordinator?
        private var userDragging = false
        /// A jump not done yet: it waits until the view has its real size, so a book opens at its place with no
        /// visible run down the page. Until then the text is hidden and following is held.
        private var pendingScroll: (offset: Int, fraction: CGFloat)?

        // reading marks
        private let band = UIView()
        private var chips: [UIView] = []
        private var tempWord: NSRange?
        private var tempSentence: NSRange?
        private var bandFrame: CGRect?
        private var spokenDirty = false
        private var lens: WordLens?
        private var shade: PageShade?

        init(_ p: ReaderTextView) { parent = p }

        func attach(_ tv: UITextView) {
            textView = tv
            band.isUserInteractionEnabled = false
            band.alpha = 0
            tv.insertSubview(band, at: 0)
            parent.player.onSpokenChange = { [weak self] in self?.spokenChanged() }
            Self.owner = self
        }

        func detach() {
            guard Self.owner == nil || Self.owner === self else { return }      // another page took the player over
            if parent.player.onSpokenChange != nil { parent.player.onSpokenChange = nil }
        }

        // MARK: update from SwiftUI

        func update(_ tv: UITextView) {
            let p = parent
            tv.backgroundColor = p.style.background
            tv.indicatorStyle = p.style.background.isDark ? .white : .black
            if tv.contentInset != p.insets {
                let atTop = tv.contentOffset.y <= -tv.contentInset.top + 1
                tv.contentInset = p.insets
                tv.verticalScrollIndicatorInsets = p.insets
                if atTop { tv.contentOffset.y = -p.insets.top }
                // the bars were measured a moment after the book opened at its place: the place is taken again, so
                // it is not left under the top bar
                if let j = lastJump, Date.now.timeIntervalSince(j.at) < 1.5, pendingScroll == nil, tv.bounds.height > 1 {
                    scroll(tv, to: j.offset, fraction: j.fraction, animated: false)
                    paintMarks(animated: false, follow: false)
                }
            }
            var rebuilt = false
            if let old = builtFor, old.0 == p.documentID, old.1 == p.style, old.2 != p.highlights || old.3 != p.notes,
               tv.textStorage.length > 0, tv.textStorage.length == p.text.utf16.count {
                // Only the marks changed (a highlight or a note added, removed, recoloured): their attributes are
                // changed in place. Setting the whole text again laid the book out from its first line down to the
                // reading place on every mark, which grew with the place and was paid on each bicycle-mode mark.
                restyleMarks(tv, from: old.2, old.3)
                builtFor = (p.documentID, p.style, p.highlights, p.notes)
                rebuilt = true
                if let sh = shaping, NSMaxRange(sh.range) <= tv.textStorage.length, tv.selectedRange != sh.range {
                    tv.selectedRange = sh.range
                }
            } else if builtFor?.0 != p.documentID || builtFor?.1 != p.style || builtFor?.2 != p.highlights || builtFor?.3 != p.notes {
                let firstBuild = builtFor?.0 != p.documentID
                let keep = firstBuild ? nil : topOffset(tv)
                build(tv)
                builtFor = (p.documentID, p.style, p.highlights, p.notes)
                rebuilt = true
                if let keep { scroll(tv, to: keep, fraction: 0, animated: false) }
                // new text drops the selection: keep the sentence being shaped selected, handles and all
                if let sh = shaping, NSMaxRange(sh.range) <= tv.textStorage.length {
                    tv.selectedRange = sh.range
                }
                if firstBuild {
                    lastScrollRequest = -1
                    tv.alpha = 0
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak tv] in if let tv, tv.alpha < 1 { tv.alpha = 1 } }
                }
            }
            if p.scrollRequest != lastScrollRequest {
                lastScrollRequest = p.scrollRequest
                pendingScroll = (p.scrollRequest, p.style.cursorFraction)
                tv.setNeedsLayout()
                layoutChanged(tv)
            } else if rebuilt {
                paintMarks(animated: false, follow: false)
            }
        }

        /// Called from layoutSubviews: do a waiting jump once the view has a size, then show the text.
        func layoutChanged(_ tv: UITextView) {
            if let j = pendingScroll, tv.bounds.height > 1, tv.window != nil {
                pendingScroll = nil
                lastJump = (j.offset, j.fraction, .now)
                scroll(tv, to: j.offset, fraction: j.fraction, animated: false)
                paintMarks(animated: false, follow: false)
                if tv.alpha < 1 { UIView.animate(withDuration: 0.15) { tv.alpha = 1 } }
            } else if pendingScroll == nil, let f = bandFrame, abs(f.width - tv.bounds.width) > 0.5 {
                paintMarks(animated: false, follow: false)          // rotated or resized: the band is full width
            }
        }

        // MARK: building

        private func baseAttributes(_ s: ReaderStyle) -> [NSAttributedString.Key: Any] {
            let para = NSMutableParagraphStyle()
            para.lineSpacing = s.lineSpacing
            if s.bookLayout {
                para.firstLineHeadIndent = s.size * 1.3       // book page: indented paragraphs, little space between
                para.paragraphSpacing = s.size * 0.25
                para.alignment = .natural
            } else {
                para.paragraphSpacing = s.size * 0.6
            }
            para.hyphenationFactor = 0.3
            return [
                .font: s.font.font(size: s.size),
                .foregroundColor: s.focus ? s.foreground.withAlphaComponent(0.28) : s.foreground,
                .paragraphStyle: para,
                .kern: s.kern,
            ]
        }

        private func build(_ tv: UITextView) {
            let p = parent
            let a = NSMutableAttributedString(string: p.text, attributes: baseAttributes(p.style))
            let len = a.length
            for h in p.highlights where h.location + h.length <= len {
                a.addAttribute(.backgroundColor, value: h.color.uiColor.withAlphaComponent(0.42), range: h.range)
                if h.note != nil { a.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: h.range) }
            }
            for n in p.notes where NSMaxRange(n.range) <= len {
                a.addAttribute(.underlineStyle, value: NSUnderlineStyle.thick.rawValue | NSUnderlineStyle.patternDot.rawValue, range: n.range)
                a.addAttribute(.underlineColor, value: Self.noteInk, range: n.range)
            }
            tv.attributedText = a
            tempWord = nil; tempSentence = nil
            bandFrame = nil
            band.alpha = 0
            chips.forEach { $0.isHidden = true }
            lens?.hide(animated: false)
            shade?.hide(animated: false)
        }

        private static let noteInk = UIColor(red: 0, green: 0.435, blue: 0.706, alpha: 1)       // the progress bar's blue

        /// Brings the text's mark attributes from the old highlights and notes to the parent's, touching only the
        /// ranges of the marks that differ. Inside such a range the result is what `build` gives: the highlights'
        /// colour (and underline when they carry a note), then the notes' dotted underline over them. Colours and
        /// underlines do not change a line's height, so the page stays where it is.
        private func restyleMarks(_ tv: UITextView, from oldHighlights: [Highlight], _ oldNotes: [NoteMark]) {
            let p = parent
            let storage = tv.textStorage
            let len = storage.length
            var dirty: [NSRange] = []
            let before = Dictionary(oldHighlights.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let after = Dictionary(p.highlights.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for h in oldHighlights where after[h.id] != h { dirty.append(h.range) }
            for h in p.highlights where before[h.id] != h { dirty.append(h.range) }
            for n in Set(oldNotes).symmetricDifference(p.notes) { dirty.append(n.range) }
            // clamp to the text, then join ranges that touch
            var merged: [NSRange] = []
            for r in dirty.map({ NSIntersectionRange($0, NSRange(location: 0, length: len)) }).filter({ $0.length > 0 })
                .sorted(by: { $0.location < $1.location }) {
                if let last = merged.last, r.location <= NSMaxRange(last) { merged[merged.count - 1] = NSUnionRange(last, r) }
                else { merged.append(r) }
            }
            guard !merged.isEmpty else { return }
            storage.beginEditing()
            for r in merged {
                storage.removeAttribute(.backgroundColor, range: r)
                storage.removeAttribute(.underlineStyle, range: r)
                storage.removeAttribute(.underlineColor, range: r)
                for h in p.highlights where h.location + h.length <= len {
                    let part = NSIntersectionRange(h.range, r)
                    guard part.length > 0 else { continue }
                    storage.addAttribute(.backgroundColor, value: h.color.uiColor.withAlphaComponent(0.42), range: part)
                    if h.note != nil { storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: part) }
                }
                for n in p.notes where NSMaxRange(n.range) <= len {
                    let part = NSIntersectionRange(n.range, r)
                    guard part.length > 0 else { continue }
                    storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.thick.rawValue | NSUnderlineStyle.patternDot.rawValue, range: part)
                    storage.addAttribute(.underlineColor, value: Self.noteInk, range: part)
                }
            }
            storage.endEditing()
        }

        // MARK: reading marks

        /// The player says the spoken word or sentence changed: paint once, after the whole step has landed.
        func spokenChanged() {
            guard !spokenDirty else { return }
            spokenDirty = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.spokenDirty = false
                guard self.pendingScroll == nil else { return }
                self.paintMarks(animated: true, follow: true)
            }
        }

        private func chip(_ i: Int, in tv: UITextView) -> UIView {
            while chips.count <= i {
                let v = UIView()
                v.isUserInteractionEnabled = false
                v.layer.cornerRadius = 2
                v.layer.cornerCurve = .continuous
                tv.insertSubview(v, aboveSubview: band)
                chips.append(v)
            }
            return chips[i]
        }

        private func luminance(_ c: UIColor) -> CGFloat {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: nil)
            return 0.299 * r + 0.587 * g + 0.114 * b
        }

        private func paintMarks(animated: Bool, follow: Bool) {
            guard let tv = textView else { return }
            let p = parent
            let len = tv.textStorage.length
            let player = p.player
            let mine = player.documentID == p.documentID
            func valid(_ r: NSRange?) -> NSRange? {
                guard mine, let r, r.location >= 0, r.location + r.length <= len, r.length > 0 else { return nil }
                return r
            }
            let word = valid(player.spokenWord)
            let sentence = valid(player.spokenSentence)
            let anchor = word?.location ?? sentence?.location

            // Text colour: only where the base colour would not read on the chip (a light text on yellow in the dark
            // themes) and, in focus mode, the spoken sentence. The light theme needs no text edit at all while reading.
            let contrast: UIColor? = {
                guard !p.style.lens, word != nil, let c = p.style.wordColor else { return nil }   // the lens carries its own line
                let pick: UIColor = luminance(c) > 0.55 ? .black : .white
                return pick.isDark == p.style.foreground.isDark ? nil : pick
            }()
            let wordTint = word.flatMap { w in contrast.map { _ in w } }
            if wordTint != tempWord || (p.style.focus && sentence != tempSentence) {
                let storage = tv.textStorage
                let base = p.style.focus ? p.style.foreground.withAlphaComponent(0.28) : p.style.foreground
                storage.beginEditing()
                if let o = tempSentence, o.location + o.length <= len { storage.addAttribute(.foregroundColor, value: base, range: o) }
                if let o = tempWord, o.location + o.length <= len { storage.addAttribute(.foregroundColor, value: base, range: o) }
                tempSentence = nil; tempWord = nil
                if p.style.focus, let s = sentence {
                    storage.addAttribute(.foregroundColor, value: p.style.foreground, range: s)
                    tempSentence = s
                }
                if let w = wordTint, let c = contrast {
                    storage.addAttribute(.foregroundColor, value: c, range: w)
                    tempWord = w
                }
                storage.endEditing()
            }

            guard let anchor, let g = geometry(in: tv, anchor: anchor, word: word) else {
                if band.alpha > 0 { UIView.animate(withDuration: 0.12) { self.band.alpha = 0 } }
                chips.forEach { $0.isHidden = true }
                lens?.hide(animated: true)
                shade?.hide(animated: true)
                bandFrame = nil
                return
            }

            // the band: one line, edge to edge. It moves with the word chip, in the same frame, never behind it.
            if let c = p.style.lineColor {
                band.backgroundColor = c
                if band.alpha > 0.5, abs(band.frame.minY - g.band.minY) > 1 {
                    let to = g.band
                    LineGlide.run { self.band.frame = to }          // glides with the capsule to the next line
                } else {
                    band.layer.removeAllAnimations()
                    band.frame = g.band
                }
                if band.alpha < 1 { UIView.animate(withDuration: 0.15) { self.band.alpha = 1 } }
                bandFrame = g.band
            } else {
                band.alpha = 0
                bandFrame = g.band
            }

            // Sayfa karartma: the page around the line steps back (faded, dark, a spotlight, a window, dusk). It lies
            // under the Mercek band and moves only when the line does, like the band.
            if p.style.dim != .off {
                let s = shade ?? {
                    let v = PageShade()
                    tv.addSubview(v)
                    shade = v
                    return v
                }()
                s.show(p.style.dim, strength: p.style.dimStrength, clear: g.band, width: tv.bounds.width,
                       viewport: visibleHeight(tv), paper: p.style.background)
                if let lens { tv.bringSubviewToFront(lens) }
            } else {
                shade?.hide(animated: false)
            }

            // Mercek: the whole line being read, larger, in a glass lens over it; the spoken word keeps its colour
            // inside the lens. (First, 2026-11-10, the lens held only the word; the same day: "kelimeyi değil, satırı
            // büyüt, kelime yine renkle işaretli olsun".)
            if p.style.lens, g.line.length > 0, NSMaxRange(g.line) <= len {
                chips.forEach { $0.isHidden = true }
                let l = lens ?? {
                    let v = WordLens()
                    tv.addSubview(v)
                    lens = v
                    return v
                }()
                let inLine = word.map { NSIntersectionRange($0, g.line) }.flatMap { $0.length > 0 ? NSRange(location: $0.location - g.line.location, length: $0.length) : nil }
                let face = p.style.font, size = p.style.size
                l.show((tv.textStorage.string as NSString).substring(with: g.line), word: inLine,
                       textStart: g.lineStart, band: g.band, font: { face.font(size: size * $0) }, scale: p.style.lensScale,
                       kern: p.style.kern, paper: p.style.background, ink: p.style.foreground, mark: p.style.wordColor)
            } else if let c = p.style.wordColor, word != nil {
                lens?.hide(animated: false)
                for (i, r) in g.chips.enumerated() {
                    let v = chip(i, in: tv)
                    v.backgroundColor = c
                    v.frame = r
                    v.isHidden = false
                }
                if g.chips.count < chips.count { for v in chips[g.chips.count...] { v.isHidden = true } }
            } else {
                chips.forEach { $0.isHidden = true }
                lens?.hide(animated: false)
            }

            if follow, p.following, !userDragging, pendingScroll == nil { followBand(tv, g.band) }
        }

        /// `line`: the characters of the line being read; `lineStart`: where its text begins on the page (x).
        private struct Geometry { var band: CGRect; var chips: [CGRect]; var line: NSRange; var lineStart: CGFloat }

        /// Where the line of `anchor` sits, and the rectangles of `word`, in the text view's content coordinates.
        private func geometry(in tv: UITextView, anchor: Int, word: NSRange?) -> Geometry? {
            let len = tv.textStorage.length
            guard len > 0, anchor >= 0, anchor < len else { return nil }
            let lm = tv.layoutManager
            let from = max(0, anchor - 300)
            lm.ensureLayout(forCharacterRange: NSRange(location: from, length: min(len - from, 1000)))
            let g = lm.glyphIndexForCharacter(at: anchor)
            var lineGlyphs = NSRange(location: 0, length: 0)
            let used = lm.lineFragmentUsedRect(forGlyphAt: g, effectiveRange: &lineGlyphs)
            let line = lm.characterRange(forGlyphRange: lineGlyphs, actualGlyphRange: nil)
            let inset = tv.textContainerInset
            let sp = parent.style.lineSpacing
            // the line's own height plus its spacing, centred on the text, so the band hugs one line
            let top = inset.top + used.minY - sp / 2
            let height = used.height + sp
            let band = CGRect(x: 0, y: top, width: tv.bounds.width, height: height)
            var chips: [CGRect] = []
            if let w = word {
                let gr = lm.glyphRange(forCharacterRange: w, actualCharacterRange: nil)
                lm.enumerateEnclosingRects(forGlyphRange: gr, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: tv.textContainer) { r, _ in
                    chips.append(CGRect(x: r.minX + inset.left - 1, y: r.minY + inset.top - sp / 2, width: r.width + 2, height: r.height + sp))
                }
            }
            return Geometry(band: band, chips: chips, line: line, lineStart: used.minX + inset.left)
        }

        // MARK: scrolling

        /// Position of the character `offset`'s line, in content coordinates (used for jumps, where layout from the
        /// top is forced once so the offset is exact).
        private func rect(_ tv: UITextView, for offset: Int) -> CGRect? {
            let len = tv.textStorage.length
            guard len > 0 else { return nil }
            let r = NSRange(location: min(max(0, offset), len - 1), length: 1)
            tv.layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: min(len, r.location + 400)))
            let g = tv.layoutManager.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
            var b = tv.layoutManager.boundingRect(forGlyphRange: g, in: tv.textContainer)
            b.origin.x += tv.textContainerInset.left
            b.origin.y += tv.textContainerInset.top
            return b
        }

        private func visibleHeight(_ tv: UITextView) -> CGFloat { tv.bounds.height - tv.adjustedContentInset.top - tv.adjustedContentInset.bottom }

        private func clampedY(_ tv: UITextView, _ y: CGFloat) -> CGFloat {
            let minY = -tv.adjustedContentInset.top
            let maxY = max(minY, tv.contentSize.height - tv.bounds.height + tv.adjustedContentInset.bottom)
            return min(max(minY, y), maxY)
        }

        func scroll(_ tv: UITextView, to offset: Int, fraction: CGFloat, animated: Bool) {
            guard let r = rect(tv, for: offset) else { return }
            let y = clampedY(tv, r.minY - visibleHeight(tv) * fraction - tv.adjustedContentInset.top)
            tv.layer.removeAllAnimations()
            tv.setContentOffset(CGPoint(x: 0, y: y), animated: animated)
        }

        /// Keep the spoken line on the page: the band walks down the lines; when its bottom passes the fence the page
        /// slides up once so the band is back at the chosen height. A line far off the page (a seek) is jumped to.
        private func followBand(_ tv: UITextView, _ band: CGRect) {
            let visible = visibleHeight(tv)
            guard visible > 50 else { return }
            let top = tv.contentOffset.y + tv.adjustedContentInset.top
            let y = band.minY - top
            let f = parent.style.cursorFraction
            let lowFence = min(0.88, f + 0.42)
            guard y < visible * 0.02 || y + band.height > visible * lowFence else { return }
            let target = clampedY(tv, band.minY - visible * f - tv.adjustedContentInset.top)
            guard abs(target - tv.contentOffset.y) > 1 else { return }
            let far = y < -visible * 0.6 || y > visible * 1.6
            if far {
                tv.setContentOffset(CGPoint(x: 0, y: target), animated: false)
            } else {
                // a slide of about a third of a screen: ease in and out, interruptible by a touch
                UIView.animate(withDuration: 0.42, delay: 0, options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState]) {
                    tv.contentOffset = CGPoint(x: 0, y: target)
                }
            }
        }

        private func topOffset(_ tv: UITextView) -> Int {
            let pt = CGPoint(x: tv.textContainerInset.left + 4, y: tv.contentOffset.y + tv.adjustedContentInset.top + 8 - tv.textContainerInset.top)
            return tv.layoutManager.characterIndex(for: pt, in: tv.textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            userDragging = true
            parent.onScrolling(true)
            scrollView.layer.removeAllAnimations()
            if parent.following { parent.following = false }
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { userDragging = false; reportVisible(); parent.onScrolling(false) }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { userDragging = false; reportVisible(); parent.onScrolling(false) }

        private func reportVisible() {
            guard let tv = textView else { return }
            parent.onVisibleOffset(topOffset(tv))
        }

        // MARK: touch

        @objc func doubleTapped(_ g: UITapGestureRecognizer) {
            quietUntil = Date.now.addingTimeInterval(0.6)
            textView?.selectedRange = NSRange(location: textView?.selectedRange.location ?? 0, length: 0)
            guard let i = index(at: g) else { return }
            parent.onDoubleTap(i)
        }

        @objc func pressed(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let tv = textView, let i = index(at: g) else { return }
            let player = parent.player
            guard player.documentID == parent.documentID, let s = player.sentenceRange(around: i),
                  NSMaxRange(s) <= tv.textStorage.length else { return }
            pressSentence = s
            pressedAt = .now
            tv.selectedRange = s
        }

        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard let tv = textView, Date.now.timeIntervalSince(pressedAt) > 1.5 else { return }
            if tv.selectedRange.length > 0 || shaping != nil {
                // a tap ends the selection and leaves the mark as it is
                shaping = nil
                tv.selectedRange = NSRange(location: tv.selectedRange.location, length: 0)
                return
            }
            let i = index(at: g)
            // Tapping a highlight offers a colour change (and removal) right there.
            if let i, let h = parent.highlights.first(where: { NSLocationInRange(i, $0.range) }) {
                recoloring = h
                openingNote = parent.notes.first { NSIntersectionRange($0.range, h.range).length > 0 }
                let cfg = UIEditMenuConfiguration(identifier: nil, sourcePoint: g.location(in: tv))
                recolorMenu?.presentEditMenu(with: cfg)
                return
            }
            if let i, let n = parent.notes.first(where: { NSLocationInRange(i, $0.range) }) {
                parent.onOpenNote(n.id)
                return
            }
            parent.onTap(i ?? 0)
        }

        /// The finger is up: a selection becomes a yellow mark at once (no menu). It joins the marks it touches and
        /// takes their colour. Everything else (colour, copy, notes, removal) is on a tap on the mark.
        func fingerLifted() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                guard let self, let tv = self.textView, Date.now > self.quietUntil else { self?.pressSentence = nil; return }
                let sentence = self.pressSentence
                self.pressSentence = nil
                var r = sentence ?? tv.selectedRange
                guard r.length > 0, NSMaxRange(r) <= tv.textStorage.length else { return }
                let ns = tv.textStorage.string as NSString
                // trim spaces and line breaks at both ends
                while r.length > 0, let c = Unicode.Scalar(ns.character(at: r.location)), CharacterSet.whitespacesAndNewlines.contains(c) {
                    r.location += 1; r.length -= 1
                }
                while r.length > 0, let c = Unicode.Scalar(ns.character(at: NSMaxRange(r) - 1)), CharacterSet.whitespacesAndNewlines.contains(c) {
                    r.length -= 1
                }
                // whole words: a mark never ends inside a word
                let letters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'’-"))
                func isLetter(_ i: Int) -> Bool { Unicode.Scalar(ns.character(at: i)).map { letters.contains($0) } ?? false }
                if r.length > 0 {
                    var a = r.location, z = NSMaxRange(r)
                    while a > 0, isLetter(a - 1), isLetter(a) { a -= 1 }
                    while z < ns.length, isLetter(z), isLetter(z - 1) { z += 1 }
                    r = NSRange(location: a, length: z - a)
                }
                guard r.length > 0 else {
                    tv.selectedRange = NSRange(location: tv.selectedRange.location, length: 0)
                    return
                }
                // a handle moved on the sentence being shaped: that mark becomes exactly the new range
                if sentence == nil, let sh = self.shaping, NSIntersectionRange(r, sh.range).length > 0 {
                    self.shaping = nil
                    tv.selectedRange = NSRange(location: r.location, length: 0)
                    guard r != sh.range else { return }
                    if let old = self.parent.highlights.first(where: { $0.range == sh.range }) { self.parent.onRemoveHighlight(old.id) }
                    self.parent.onHighlight(r, sh.color, ns.substring(with: r))
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    return
                }
                self.shaping = nil
                let touching = self.parent.highlights.filter { NSIntersectionRange($0.range, r).length > 0 || NSMaxRange($0.range) == r.location || NSMaxRange(r) == $0.location }
                var u = r
                for h in touching { u = NSUnionRange(u, h.range) }
                let color = touching.first?.color ?? .yellow
                self.parent.onHighlight(u, color, ns.substring(with: u))
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if sentence != nil {
                    // the sentence stays selected so a handle can shorten it
                    self.shaping = (u, color)
                    // after the system's own long-press handling has settled, or it takes the selection back
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self, weak tv] in
                        guard let self, let tv, let sh = self.shaping, NSMaxRange(sh.range) <= tv.textStorage.length else { return }
                        if !tv.isFirstResponder { tv.becomeFirstResponder() }
                        tv.selectedRange = sh.range
                    }
                } else {
                    tv.selectedRange = NSRange(location: tv.selectedRange.location, length: 0)
                }
            }
        }

        private func index(at g: UIGestureRecognizer) -> Int? {
            guard let tv = textView else { return nil }
            var pt = g.location(in: tv)
            pt.x -= tv.textContainerInset.left
            pt.y -= tv.textContainerInset.top
            var frac: CGFloat = 0
            let i = tv.layoutManager.characterIndex(for: pt, in: tv.textContainer, fractionOfDistanceBetweenInsertionPoints: &frac)
            return i < tv.textStorage.length ? i : nil
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard let h = recoloring else { return nil }
            let p = parent
            let colors = HighlightColor.allCases.filter { $0 != h.color }.map { c in
                UIAction(title: c.name, image: UIImage(systemName: "circle.fill")?.withTintColor(c.uiColor, renderingMode: .alwaysOriginal)) { _ in
                    p.onHighlight(h.range, c, h.text)
                }
            }
            let remove = UIAction(title: "İşareti kaldır", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                p.onRemoveHighlight(h.id)
            }
            let voice = UIAction(title: "Sesli not", image: UIImage(systemName: "mic.fill")) { _ in p.onVoiceNote(h.range) }
            let write = UIAction(title: "Not yaz", image: UIImage(systemName: "square.and.pencil")) { _ in p.onNote(h.range, h.text) }
            let expand = UIAction(title: "Bu kısmı genişlet", image: UIImage(systemName: "sparkles")) { _ in p.onExpand(h.range, h.text) }
            var noteItems: [UIMenuElement] = [expand, voice, write]
            if let n = openingNote {
                noteItems.insert(UIAction(title: n.voice ? "Notu dinle" : "Notu aç", image: UIImage(systemName: n.voice ? "play.circle" : "note.text")) { _ in
                    p.onOpenNote(n.id)
                }, at: 0)
            }
            let copy = UIAction(title: "Kopyala", image: UIImage(systemName: "doc.on.doc")) { _ in UIPasteboard.general.string = h.text }
            let play = UIAction(title: "Buradan oku", image: UIImage(systemName: "play.fill")) { _ in p.onPlayFrom(h.location) }
            return UIMenu(children: [
                UIMenu(options: .displayInline, children: noteItems),
                UIMenu(options: .displayInline, children: colors),
                UIMenu(options: .displayInline, children: [copy, play, remove]),
            ])
        }

        func textView(_ tv: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard range.length > 0 else { return UIMenu(children: suggestedActions) }
            let text = (tv.text as NSString).substring(with: range)
            let p = parent
            // One step: marks yellow straight away. Tap the mark afterwards to change its colour.
            let highlight = UIAction(title: "İşaretle", image: UIImage(systemName: "highlighter")) { _ in
                p.onHighlight(range, .yellow, text)
                tv.selectedRange = NSRange(location: range.location, length: 0)
            }
            let note = UIAction(title: "Not ekle", image: UIImage(systemName: "note.text.badge.plus")) { _ in
                p.onNote(range, text)
                tv.selectedRange = NSRange(location: range.location, length: 0)
            }
            let bookmark = UIAction(title: "Yer imi", image: UIImage(systemName: "bookmark")) { _ in
                p.onBookmark(range.location)
                tv.selectedRange = NSRange(location: range.location, length: 0)
            }
            let play = UIAction(title: "Buradan oku", image: UIImage(systemName: "play.fill")) { _ in
                p.onPlayFrom(range.location)
                tv.selectedRange = NSRange(location: range.location, length: 0)
            }
            let expand = UIAction(title: "Genişlet", image: UIImage(systemName: "sparkles")) { _ in
                p.onExpand(range, text)
                tv.selectedRange = NSRange(location: range.location, length: 0)
            }
            let ours = UIMenu(options: .displayInline, children: [play, highlight, expand, note, bookmark])
            return UIMenu(children: [ours] + suggestedActions)
        }
    }
}

extension UIColor {
    var isDark: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: nil) else {
            var w: CGFloat = 0
            getWhite(&w, alpha: nil)
            return w < 0.5
        }
        return 0.299 * r + 0.587 * g + 0.114 * b < 0.5
    }
}

/// Watches every touch on the page without taking any: says when the last finger is lifted (after a selection drag
/// or a long press). Never recognises, so scrolling, taps and the selection handles work as before.
final class TouchLiftRecognizer: UIGestureRecognizer {
    var onLift: (() -> Void)?
    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if (event.allTouches ?? touches).allSatisfy({ $0.phase == .ended || $0.phase == .cancelled }) { onLift?() }
        state = .failed
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { state = .failed }
    override func canBePrevented(by other: UIGestureRecognizer) -> Bool { false }
    override func canPrevent(_ other: UIGestureRecognizer) -> Bool { false }
}

/// UITextView that says when it lays out, so a waiting scroll can run once the real size is known.
final class LayoutReportingTextView: UITextView {
    var onLayout: (() -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

/// Satır bandı (2026-11-10, last form: "büyüteç kullanışlı değil, resimdeki gibi yuvarlatılmış kenar"): a capsule
/// with a hairline edge over the line being read, the line at its own size by default (Settings.lensScale 1.0).
/// Earlier, Mercek (2026-11-10): a glass band lying over the line being read, the line a touch larger on it, the spoken word
/// in its colour. Nothing slides: the band stands still on its line and only the word's colour steps along it; when
/// the voice reaches the next line the band is there at once. (Two earlier forms of the same day were dropped by the
/// user: a lens holding only the word, and a line that slid under the glass, "kayma çirkin gösteriyor".) The line is
/// enlarged only as far as it still fits the page's width whole. One small view; the page's text is not laid out
/// again. On iOS 26 and later the band is the system's glass; before that a thin blur.
/// The glide from one line to the next (2026-11-11, "atlamalı değil, aşağı doğru akıcı geçsin"): the band, the
/// line band behind it and the page's shade move together, on one curve, in about a third of a second.
enum LineGlide {
    static let duration: TimeInterval = 0.32
    static func run(_ moves: @escaping () -> Void) {
        UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut], animations: moves)
    }
}

final class WordLens: UIView {
    private let glass = UIVisualEffectView()
    private let tint = UIView()
    private let label = UILabel()

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        alpha = 0
        // no shadow: it gathered at the capsule's round ends as a smudge (2026-11-11); only the hairline ring stays
        if #available(iOS 26.0, *) {
            glass.effect = UIGlassEffect()
        } else {
            glass.effect = UIBlurEffect(style: .systemThinMaterial)
        }
        glass.clipsToBounds = true
        glass.layer.cornerCurve = .circular
        glass.layer.borderWidth = 1
        glass.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(glass)
        tint.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        glass.contentView.addSubview(tint)
        label.lineBreakMode = .byClipping
        label.numberOfLines = 1
        glass.contentView.addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// `text`: the line; `word`: the spoken word inside it; `textStart`: where the line's text begins on the page;
    /// `band`: the line's own band, edge to edge; `font`: the page's type at a given enlargement; `scale`: the
    /// enlargement asked for (the line gets less when it would not fit).
    func show(_ text: String, word: NSRange?, textStart: CGFloat, band: CGRect, font: (CGFloat) -> UIFont, scale: CGFloat,
              kern: CGFloat, paper: UIColor, ink: UIColor, mark: UIColor?) {
        var shown = text
        while let c = shown.unicodeScalars.last, CharacterSet.whitespacesAndNewlines.contains(c) { shown.unicodeScalars.removeLast() }
        let margin: CGFloat = 2, pad: CGFloat = 8
        let room = max(40, band.width - 2 * margin - 2 * pad)
        let plain = (shown as NSString).size(withAttributes: [.font: font(1), .kern: kern]).width
        let k = max(1, min(scale, plain > 1 ? room / plain : scale))
        let face = font(k)
        let a = NSMutableAttributedString(string: shown, attributes: [.font: face, .kern: kern * k, .foregroundColor: ink])
        if let word, let mark, NSMaxRange(word) <= a.length {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
            mark.getRed(&r, green: &g, blue: &b, alpha: nil)
            a.addAttributes([.backgroundColor: mark, .foregroundColor: 0.299 * r + 0.587 * g + 0.114 * b > 0.55 ? UIColor.black : UIColor.white], range: word)
        }
        let height = max(band.height * k, ceil(face.lineHeight)) + 4
        let frame = CGRect(x: margin, y: band.midY - height / 2, width: max(40, band.width - 2 * margin), height: height)
        // the enlarged line keeps the middle of the line it covers, and stays inside the band
        let width = ceil(a.size().width) + 2
        let middle = textStart + plain / 2 - margin
        let x = min(max(pad, middle - width / 2), max(pad, frame.width - width - pad))
        // Within a line nothing moves (only the word's colour steps on). To the next line the capsule glides down
        // while the old line's text dissolves into the new one (2026-11-11); the text itself never slides sideways.
        let moving = alpha > 0.5 && abs(self.frame.midY - frame.midY) > 1
        UIView.performWithoutAnimation {
            // a capsule: both ends fully round, a hairline edge, the page's own colour a shade lifted
            let dark = paper.isDark
            self.tint.backgroundColor = dark ? UIColor(white: 1, alpha: 0.07).blended(over: paper) : paper.withAlphaComponent(0.94)
            self.glass.layer.cornerRadius = height / 2
            self.glass.layer.borderColor = (dark ? UIColor(white: 1, alpha: 0.28) : UIColor(white: 0, alpha: 0.14)).cgColor
            if !moving {
                self.label.attributedText = a
                self.frame = frame
                self.label.frame = CGRect(x: x, y: 0, width: width, height: height)
            }
        }
        if moving {
            UIView.transition(with: label, duration: LineGlide.duration * 0.8, options: [.transitionCrossDissolve, .beginFromCurrentState]) {
                self.label.attributedText = a
            }
            LineGlide.run {
                self.frame = frame
                self.label.frame = CGRect(x: x, y: 0, width: width, height: height)
            }
        }
        superview?.bringSubviewToFront(self)
        if alpha < 1 { UIView.animate(withDuration: 0.12) { self.alpha = 1 } }
    }

    func hide(animated: Bool) {
        guard alpha > 0 else { return }
        if animated { UIView.animate(withDuration: 0.12) { self.alpha = 0 } } else { alpha = 0 }
    }
}

/// Sayfa karartma (2026-11-10, "o bantla beraber arka planı çeşitli biçimlerde karartma"): the page around the line
/// being read steps back while the line stays clear. Four plain pieces in the text's own coordinates, above the text
/// and below the Mercek band: a solid shade far above and far below, and a short gradient where each meets the clear
/// part, so the edge is soft. Plain colour views need no backing store however tall they are; the gradients are
/// at most a screen high. Like the band, it moves only when the line does, with no animation.
final class PageShade: UIView {
    private final class Fade: UIView {
        override class var layerClass: AnyClass { CAGradientLayer.self }
        var gradient: CAGradientLayer { layer as! CAGradientLayer }
    }
    private let topSolid = UIView(), bottomSolid = UIView()
    private let topFade = Fade(), bottomFade = Fade()

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        alpha = 0
        for v in [topSolid, topFade, bottomFade, bottomSolid] as [UIView] {
            v.isUserInteractionEnabled = false
            addSubview(v)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// `clear`: the line's band, edge to edge, in the text's coordinates; `viewport`: the height of the page on
    /// screen; `paper`: the page's colour (what "Soluk" and "Pencere" fade the text into).
    func show(_ kind: PageDim, strength: CGFloat, clear band: CGRect, width: CGFloat, viewport: CGFloat, paper: UIColor) {
        let ink: UIColor
        var strength = strength
        var clear = band
        var fade: CGFloat = 10                       // a soft edge, not a hard cut
        var near: CGFloat = 0                        // the shade right at the clear part (spotlight starts lit)
        switch kind {
        case .off:
            hide(animated: false); return
        case .fade:
            ink = paper
        case .dark:
            ink = .black
        case .spotlight:
            ink = .black
            fade = max(140, viewport * 0.45)
            near = 0.04
            strength = min(0.95, strength * 1.2)
        case .window:
            ink = paper
            clear = band.insetBy(dx: 0, dy: -band.height * 0.6)    // the line above and the line below
            fade = band.height * 0.5
            strength = min(0.92, strength * 1.15)
        case .dusk:
            ink = paper.isDark ? UIColor(red: 0.14, green: 0.07, blue: 0.01, alpha: 1)
                               : UIColor(red: 0.42, green: 0.24, blue: 0.05, alpha: 1)
        }
        let far: CGFloat = 30000
        let x: CGFloat = -40, w = width + 80
        let full = ink.withAlphaComponent(strength).cgColor
        let lit = ink.withAlphaComponent(strength * near).cgColor
        let target = CGRect(x: x, y: clear.minY - far, width: w, height: clear.height + 2 * far)
        let moving = alpha > 0.5 && abs(frame.minY - target.minY) > 1
        if moving { LineGlide.run { self.frame = target } }   // glides with the band; the pieces inside stay put
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIView.performWithoutAnimation {
            if !moving { frame = target }
            let top = far                            // the clear part's top, in this view
            let bottom = far + clear.height
            topSolid.frame = CGRect(x: 0, y: 0, width: w, height: max(0, top - fade))
            topFade.frame = CGRect(x: 0, y: top - fade, width: w, height: fade)
            bottomFade.frame = CGRect(x: 0, y: bottom, width: w, height: fade)
            bottomSolid.frame = CGRect(x: 0, y: bottom + fade, width: w, height: max(0, far - fade))
            topSolid.backgroundColor = UIColor(cgColor: full)
            bottomSolid.backgroundColor = UIColor(cgColor: full)
            // the spotlight darkens slowly near the line, then faster: three stops instead of two
            let spot = kind == .spotlight
            let mid = ink.withAlphaComponent(strength * 0.42).cgColor
            topFade.gradient.colors = spot ? [full, mid, lit] : [full, lit]
            topFade.gradient.locations = spot ? [0, 0.4, 1] : nil
            bottomFade.gradient.colors = spot ? [lit, mid, full] : [lit, full]
            bottomFade.gradient.locations = spot ? [0, 0.6, 1] : nil
        }
        CATransaction.commit()
        if alpha < 1 { UIView.animate(withDuration: 0.25) { self.alpha = 1 } }
    }

    func hide(animated: Bool) {
        guard alpha > 0 else { return }
        if animated { UIView.animate(withDuration: 0.2) { self.alpha = 0 } } else { alpha = 0 }
    }
}


private extension UIColor {
    /// This colour laid over `base` (alpha compositing), opaque.
    func blended(over base: UIColor) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        base.getRed(&br, green: &bg, blue: &bb, alpha: nil)
        return UIColor(red: r * a + br * (1 - a), green: g * a + bg * (1 - a), blue: b * a + bb * (1 - a), alpha: 1)
    }
}
