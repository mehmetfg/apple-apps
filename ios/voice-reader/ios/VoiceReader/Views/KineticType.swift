// Müzik modu, Kinetik: a sentence as kinetic typography. It is cut into short phrases (at punctuation, three to five
// words); each phrase is set as one composition and its words land on the beat. Four compositions, as in lyric and
// title sequences: a justified stack (every word as wide as the column), a vertical key word on the side with the rest
// stacked beside it, a giant key word with the small words spaced above and below, and the stack tilted. Small words
// (ve, bir, ile…) are set small in capitals with wide spacing; the phrase's key word is the largest and warm-coloured.
// A word with a known image (akıl, zaman, yol, ışık…) brings its symbol in with it.
import SwiftUI

struct KineticPhrase: Identifiable, Hashable {
    enum Layout: CaseIterable { case stack, side, giant, tilt }
    let id: Int
    let words: [String]
    let key: Int                        // index of the key word
    let layout: Layout
    let symbol: String?

    static let small: Set<String> = ["ve", "bir", "bu", "şu", "o", "da", "de", "ile", "ki", "için", "gibi", "ne", "en", "çok", "daha",
        "her", "mi", "mı", "ama", "ya", "olan", "olarak", "değil", "kadar", "sonra", "önce", "hem", "ise", "veya", "the", "a", "an",
        "of", "to", "and", "in", "is", "on", "bütün", "tüm", "nasıl", "neden", "çünkü", "eğer", "yani", "artık", "hiç", "biz", "ben", "sen"]

    /// Word roots → SF Symbols. The first match in a phrase is shown with it.
    static let symbols: [(String, String)] = [
        ("akıl", "brain.head.profile"), ("zihin", "brain"), ("düşün", "brain"), ("bilinç", "brain"),
        ("zaman", "hourglass"), ("saat", "clock"), ("gün", "sun.max"), ("gece", "moon.stars"), ("ışık", "lightbulb"),
        ("yol", "point.topleft.down.to.point.bottomright.curvepath"), ("yön", "location.north.line"),
        ("kalp", "heart"), ("yürek", "heart"), ("sevgi", "heart"), ("aşk", "heart"),
        ("göz", "eye"), ("gör", "eye"), ("bak", "eye"), ("kitap", "book"), ("oku", "book"), ("yaz", "pencil.line"),
        ("söz", "quote.opening"), ("dil", "character.bubble"), ("konuş", "bubble.left.and.bubble.right"), ("soru", "questionmark"),
        ("hakikat", "checkmark.seal"), ("doğru", "checkmark.seal"), ("bilgi", "books.vertical"), ("bil", "graduationcap"),
        ("iman", "sparkles"), ("tanrı", "sparkles"), ("ruh", "sparkles"), ("dünya", "globe.europe.africa"), ("evren", "sparkles"),
        ("para", "banknote"), ("değer", "diamond"), ("güç", "bolt"), ("kuvvet", "bolt"), ("özgür", "bird"),
        ("ölüm", "leaf"), ("hayat", "leaf"), ("yaşam", "leaf"), ("doğa", "tree"), ("su", "drop"), ("ateş", "flame"),
        ("yıldız", "star"), ("sayı", "number"), ("hesap", "function"), ("makine", "cpu"), ("kod", "chevron.left.forwardslash.chevron.right"),
        ("ev", "house"), ("şehir", "building.2"), ("toplum", "person.3"), ("insan", "figure.stand"), ("kişi", "person"),
        ("düzen", "square.grid.3x3"), ("yapı", "building.columns"), ("bellek", "memorychip"), ("hatır", "memorychip"),
        ("savaş", "shield"), ("barış", "hands.sparkles"), ("ses", "waveform"), ("müzik", "music.note"), ("yasa", "scroll"),
    ]

    static func symbol(for word: String) -> String? {
        let w = word.lowercased(with: Locale(identifier: "tr"))
        return symbols.first { w.hasPrefix($0.0) }?.1
    }

    static func clean(_ w: String) -> String {
        w.trimmingCharacters(in: .punctuationCharacters.union(.symbols)).lowercased(with: Locale(identifier: "tr"))
    }

    /// A sentence into phrases: a phrase ends at a comma, colon, dash or full stop, or after five words; a phrase of
    /// one small word joins the next.
    static func phrases(_ text: String, seed: Int) -> [KineticPhrase] {
        let words = text.split(separator: " ").map(String.init)
        var groups: [[String]] = [], cur: [String] = []
        for w in words {
            cur.append(w)
            let ends = w.last.map { ",;:.!?—–".contains($0) } ?? false
            if cur.count >= 5 || (ends && cur.count >= 2) { groups.append(cur); cur = [] }
        }
        if !cur.isEmpty {
            if cur.count == 1, !groups.isEmpty { groups[groups.count - 1] += cur } else { groups.append(cur) }
        }
        return groups.enumerated().map { i, g in
            let scored = g.enumerated().map { j, w -> (Int, Int) in
                let c = clean(w)
                return (j, small.contains(c) ? -1 : c.count + (symbol(for: c) != nil ? 4 : 0))
            }
            let key = scored.max { $0.1 < $1.1 }?.0 ?? 0
            let sym = g.lazy.map { clean($0) }.compactMap { symbol(for: $0) }.first
            var layout = Layout.allCases[(seed * 3 + i) % Layout.allCases.count]
            if layout == .side, clean(g[key]).count < 4 || g.count < 2 { layout = .stack }
            if sym != nil, i % 2 == 0 { layout = .giant }
            return KineticPhrase(id: i, words: g, key: key, layout: layout, symbol: sym)
        }
    }
}

/// One phrase set as a composition; `shown` words of it are on screen (they land one per beat).
struct KineticPhraseView: View {
    let phrase: KineticPhrase
    let shown: Int
    let size: CGSize
    let accent: Color
    let paper: Color

    var body: some View {
        Group {
            switch phrase.layout {
            case .stack: stack(width: size.width)
            case .tilt: stack(width: size.width * 0.9).rotationEffect(.degrees(-7))
            case .side: side
            case .giant: giant
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// A big word without the comma, semicolon or colon after it: at that size they read as noise.
    private func bare(_ i: Int) -> String {
        var w = phrase.words[i]
        while let c = w.last, ",;:".contains(c) { w.removeLast() }
        return w
    }

    private func isSmall(_ i: Int) -> Bool { KineticPhrase.small.contains(KineticPhrase.clean(phrase.words[i])) }

    /// A word as wide as the column (big words) or small capitals with wide spacing (small words).
    @ViewBuilder private func word(_ i: Int, width: CGFloat, maxSize: CGFloat) -> some View {
        let w = phrase.words[i]
        if isSmall(i) && i != phrase.key {
            Text(w.uppercased(with: Locale(identifier: "tr")))
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .tracking(6)
                .foregroundStyle(paper.opacity(0.7))
                .frame(width: width, alignment: .leading)
        } else {
            Text(bare(i))
                .font(.system(size: maxSize, weight: i == phrase.key ? .black : .heavy, design: i == phrase.key ? .serif : .default))
                .italic(i == phrase.key && phrase.layout == .tilt)
                .foregroundStyle(i == phrase.key ? accent : paper)
                .shadow(color: accent.opacity(i == phrase.key ? 0.5 : 0), radius: 18)
                .lineLimit(1)
                .minimumScaleFactor(0.08)
                .frame(width: width, alignment: .leading)
        }
    }

    private func land(_ i: Int) -> AnyTransition {
        i == phrase.key ? .modifier(active: Slam(t: 0, big: true), identity: Slam(t: 1, big: true))
                        : .modifier(active: Slam(t: 0, big: false), identity: Slam(t: 1, big: false))
    }

    private func stack(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: -4) {
            ForEach(0..<min(shown, phrase.words.count), id: \.self) { i in
                word(i, width: width, maxSize: 220).transition(land(i))
            }
            if let s = phrase.symbol, shown >= phrase.words.count {
                Image(systemName: s).font(.system(size: width * 0.22, weight: .light)).foregroundStyle(accent)
                    .padding(.top, 12)
                    .transition(.modifier(active: Slam(t: 0, big: true), identity: Slam(t: 1, big: true)))
            }
        }
        .frame(width: width, alignment: .leading)
    }

    /// The key word turned on its side down the left edge, the other words stacked beside it.
    private var side: some View {
        let colW = size.width * 0.3
        return HStack(alignment: .center, spacing: 10) {
            ZStack {
                if shown > phrase.key {
                    Text(bare(phrase.key))
                        .font(.system(size: 220, weight: .black, design: .serif))
                        .foregroundStyle(accent)
                        .shadow(color: accent.opacity(0.5), radius: 18)
                        .lineLimit(1).minimumScaleFactor(0.08)
                        .frame(width: size.height * 0.92)
                        .fixedSize(horizontal: true, vertical: false)
                        .rotationEffect(.degrees(-90))
                        .transition(.modifier(active: Slam(t: 0, big: true), identity: Slam(t: 1, big: true)))
                }
            }
            .frame(width: colW, height: size.height)
            VStack(alignment: .leading, spacing: -2) {
                ForEach(0..<min(shown, phrase.words.count), id: \.self) { i in
                    if i != phrase.key { word(i, width: size.width - colW - 10, maxSize: 130).transition(land(i)) }
                }
                if let s = phrase.symbol, shown >= phrase.words.count {
                    Image(systemName: s).font(.system(size: 54, weight: .light)).foregroundStyle(accent).padding(.top, 10)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The key word huge in the middle, the symbol large and faint behind it, the other words small above and below.
    private var giant: some View {
        let before = Array(0..<phrase.key), after = Array((phrase.key + 1)..<phrase.words.count)
        return ZStack {
            if let s = phrase.symbol, shown > phrase.key {
                Image(systemName: s).font(.system(size: size.width * 0.7, weight: .ultraLight))
                    .foregroundStyle(accent.opacity(0.16))
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
            VStack(spacing: 10) {
                Text(before.filter { $0 < shown }.map { phrase.words[$0] }.joined(separator: " ").uppercased(with: Locale(identifier: "tr")))
                    .font(.system(size: 16, weight: .semibold, design: .monospaced)).tracking(5)
                    .foregroundStyle(paper.opacity(0.75)).multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                if shown > phrase.key {
                    Text(bare(phrase.key))
                        .font(.system(size: 260, weight: .black, design: .serif))
                        .foregroundStyle(accent)
                        .shadow(color: accent.opacity(0.55), radius: 22)
                        .lineLimit(1).minimumScaleFactor(0.08)
                        .frame(width: size.width)
                        .transition(.modifier(active: Slam(t: 0, big: true), identity: Slam(t: 1, big: true)))
                }
                Text(after.filter { $0 < shown }.map { phrase.words[$0] }.joined(separator: " ").uppercased(with: Locale(identifier: "tr")))
                    .font(.system(size: 16, weight: .semibold, design: .monospaced)).tracking(5)
                    .foregroundStyle(paper.opacity(0.75)).multilineTextAlignment(.center)
                    .contentTransition(.opacity)
            }
        }
    }
}

/// A word landing: from big, turned a little and blurred, down onto its place.
struct Slam: ViewModifier {
    var t: Double
    var big: Bool
    func body(content: Content) -> some View {
        content
            .scaleEffect(1 + (1 - t) * (big ? 1.4 : 0.8))
            .rotationEffect(.degrees((1 - t) * (big ? -8 : 4)))
            .blur(radius: (1 - t) * 12)
            .opacity(t)
    }
}
