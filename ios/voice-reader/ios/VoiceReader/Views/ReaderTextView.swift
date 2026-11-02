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
    var onBookmark: (Int) -> Void
    var onPlayFrom: (Int) -> Void
    var onVisibleOffset: (Int) -> Void
    var onScrolling: (Bool) -> Void = { _ in }   // the finger moves the page (true) / the page has come to rest

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

        init(_ p: ReaderTextView) { parent = p }

        func attach(_ tv: UITextView) {
            textView = tv
            band.isUserInteractionEnabled = false
            band.alpha = 0
            tv.insertSubview(band, at: 0)
            parent.player.onSpokenChange = { [weak self] in self?.spokenChanged() }
        }

        func detach() {
            if parent.player.onSpokenChange != nil { parent.player.onSpokenChange = nil }
        }

        // MARK: update from SwiftUI

        func update(_ tv: UITextView) {
            let p = parent
            tv.backgroundColor = p.style.background
            tv.indicatorStyle = p.style.background.isDark ? .white : .black
            var rebuilt = false
            if builtFor?.0 != p.documentID || builtFor?.1 != p.style || builtFor?.2 != p.highlights || builtFor?.3 != p.notes {
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
            let ink = UIColor(red: 0, green: 0.435, blue: 0.706, alpha: 1)       // the progress bar's blue
            for n in p.notes where NSMaxRange(n.range) <= len {
                a.addAttribute(.underlineStyle, value: NSUnderlineStyle.thick.rawValue | NSUnderlineStyle.patternDot.rawValue, range: n.range)
                a.addAttribute(.underlineColor, value: ink, range: n.range)
            }
            tv.attributedText = a
            tempWord = nil; tempSentence = nil
            bandFrame = nil
            band.alpha = 0
            chips.forEach { $0.isHidden = true }
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
                guard let w = word, let c = p.style.wordColor else { return nil }
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
                bandFrame = nil
                return
            }

            // the band: one line, edge to edge. It moves with the word chip, in the same frame, never behind it.
            if let c = p.style.lineColor {
                band.backgroundColor = c
                band.layer.removeAllAnimations()
                band.frame = g.band
                if band.alpha < 1 { UIView.animate(withDuration: 0.15) { self.band.alpha = 1 } }
                bandFrame = g.band
            } else {
                band.alpha = 0
                bandFrame = g.band
            }

            // the word: a chip, jumping to each word
            if let c = p.style.wordColor, word != nil {
                for (i, r) in g.chips.enumerated() {
                    let v = chip(i, in: tv)
                    v.backgroundColor = c
                    v.frame = r
                    v.isHidden = false
                }
                if g.chips.count < chips.count { for v in chips[g.chips.count...] { v.isHidden = true } }
            } else {
                chips.forEach { $0.isHidden = true }
            }

            if follow, p.following, !userDragging, pendingScroll == nil { followBand(tv, g.band) }
        }

        private struct Geometry { var band: CGRect; var chips: [CGRect] }

        /// Where the line of `anchor` sits, and the rectangles of `word`, in the text view's content coordinates.
        private func geometry(in tv: UITextView, anchor: Int, word: NSRange?) -> Geometry? {
            let len = tv.textStorage.length
            guard len > 0, anchor >= 0, anchor < len else { return nil }
            let lm = tv.layoutManager
            let from = max(0, anchor - 300)
            lm.ensureLayout(forCharacterRange: NSRange(location: from, length: min(len - from, 1000)))
            let g = lm.glyphIndexForCharacter(at: anchor)
            let used = lm.lineFragmentUsedRect(forGlyphAt: g, effectiveRange: nil)
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
            return Geometry(band: band, chips: chips)
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
            var noteItems: [UIMenuElement] = [voice, write]
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
            let ours = UIMenu(options: .displayInline, children: [play, highlight, note, bookmark])
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
