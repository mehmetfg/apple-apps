// Müzik modu, Kinetik: a sentence as kinetic typography. It is cut into short phrases (at punctuation, three to five
// words); each phrase is set as one composition and its words land on the beat. Four compositions, as in lyric and
// title sequences: a justified stack (every word as wide as the column), a vertical key word on the side with the rest
// stacked beside it, a giant key word with the small words spaced above and below, and the stack tilted. Small words
// (ve, bir, ile…) are set small in capitals with wide spacing; the phrase's key word is the largest and warm-coloured.
// A word with a known image (akıl, zaman, yol, ışık… about 330 roots and forms) brings its symbol in with it, on its own line;
// a phrase that has one is often set as an emblem (the image in a ring over the word) or with the image large and
// faint behind the giant word. Years bring the calendar, a question its mark.
import SwiftUI

struct KineticPhrase: Identifiable, Hashable {
    enum Layout: CaseIterable { case stack, side, giant, tilt, emblem }
    let id: Int
    let words: [String]
    let key: Int                        // index of the key word
    let layout: Layout
    let symbol: String?                 // the phrase's main image: the key word's, else the first word's that has one
    let marks: [Int: String]            // every word that has an image → its symbol

    /// Beats the phrase takes in Müzik modu: one a word, and one more for the image that lands after the words.
    var beats: Int { words.count + (layout == .side && symbol != nil ? 1 : 0) }

    static let small: Set<String> = ["ve", "bir", "bu", "şu", "o", "da", "de", "ile", "ki", "için", "gibi", "ne", "en", "çok", "daha",
        "her", "mi", "mı", "ama", "ya", "olan", "olarak", "değil", "kadar", "sonra", "önce", "hem", "ise", "veya", "the", "a", "an",
        "of", "to", "and", "in", "is", "on", "bütün", "tüm", "nasıl", "neden", "çünkü", "eğer", "yani", "artık", "hiç", "biz", "ben", "sen"]

    /// Word roots → SF Symbols (every name checked against the system's symbols, 2026-11-06). The longest root that
    /// fits a word wins ("bilim" before "bilgi" before nothing; "sorun" before "soru").
    ///
    /// A root of up to three letters fits only the word itself or the word with a plain noun ending (su, suyu,
    /// sular, suda… but not suç or sunmak; ev, evde, evler… but not evet or evren): a bare prefix test put a house on
    /// "evet" and an eye on "göre". Longer roots fit any word that starts with them, except the words in `never`.
    static let symbols: [(String, String)] = [
        // mind
        ("akıl", "brain.head.profile"), ("akl", "brain.head.profile"), ("zihin", "brain"), ("zihn", "brain"), ("düşün", "brain"),
        ("bilinç", "brain"), ("beyin", "brain"), ("fikir", "lightbulb"), ("fikr", "lightbulb"), ("buluş", "lightbulb.max"),
        ("kavram", "cube.transparent"), ("anlam", "text.magnifyingglass"), ("mantık", "point.3.connected.trianglepath.dotted"),
        ("mantığ", "point.3.connected.trianglepath.dotted"), ("kanıt", "checkmark.seal"), ("ispat", "checkmark.seal"),
        ("merak", "questionmark.circle"), ("şüphe", "questionmark.circle"), ("kuşku", "questionmark.circle"),
        ("hayret", "exclamationmark"), ("bellek", "archivebox"), ("belleğ", "archivebox"), ("hafıza", "archivebox"),
        ("hatır", "bookmark"), ("unut", "eye.slash"), ("dikkat", "scope"), ("odak", "scope"), ("rüya", "moon.stars"),
        // time
        ("zaman", "hourglass"), ("saat", "clock"), ("tarih", "calendar"), ("yüzyıl", "calendar.badge.clock"), ("çağ", "calendar.badge.clock"),
        ("dönem", "calendar.badge.clock"), ("geçmiş", "clock.arrow.circlepath"), ("gelecek", "arrow.forward.circle"),
        ("gün", "sun.max"), ("gece", "moon.stars"), ("sabah", "sunrise"), ("akşam", "sunset"), ("yıl", "calendar"),
        ("başla", "play"), ("sonuç", "flag.checkered"), ("sonsuz", "infinity"), ("ebed", "infinity"), ("değiş", "arrow.triangle.2.circlepath"),
        // light, sky
        ("ışık", "lightbulb"), ("ışığ", "lightbulb"), ("güneş", "sun.max.fill"), ("yıldız", "star"), ("gök", "cloud.sun"),
        ("karanlık", "moon.fill"), ("gölge", "circle.lefthalf.filled"), ("evren", "moon.stars"), ("uzay", "moon.stars"),
        ("gezegen", "globe"), ("dünya", "globe.europe.africa"),
        // way
        ("yol", "point.topleft.down.to.point.bottomright.curvepath"), ("yön", "location.north.line"), ("adım", "figure.walk"),
        ("yürü", "figure.walk"), ("koş", "figure.run"), ("kapı", "door.left.hand.open"), ("eşik", "door.left.hand.open"),
        ("eşiğ", "door.left.hand.open"), ("harita", "map"), ("sınır", "rectangle.dashed"), ("merkez", "scope"),
        ("hedef", "target"), ("amaç", "target"), ("plan", "list.bullet.clipboard"), ("karar", "signpost.right"),
        ("gemi", "sailboat"), ("uçak", "airplane"), ("araba", "car"), ("tren", "tram"), ("bisiklet", "bicycle"), ("pusula", "location.north.line"),
        // heart
        ("kalp", "heart"), ("kalb", "heart"), ("yürek", "heart"), ("yüreğ", "heart"), ("sevgi", "heart"), ("sevda", "heart"),
        ("aşk", "heart"), ("duygu", "heart"), ("korku", "exclamationmark.triangle"), ("kork", "exclamationmark.triangle"),
        ("tehlike", "exclamationmark.triangle"), ("risk", "exclamationmark.triangle"), ("umut", "sunrise"), ("mutlu", "face.smiling"),
        ("acı", "bolt.heart"), ("öfke", "flame"),
        // senses, body
        ("göz", "eye"), ("gör", "eye"), ("görü", "eye"), ("görm", "eye"), ("gördü", "eye"), ("bakış", "eye"), ("kulak", "ear"),
        ("kulağ", "ear"), ("duy", "ear"), ("duyu", "ear"), ("duyd", "ear"), ("duym", "ear"), ("dokun", "hand.tap"),
        ("beden", "figure.stand"), ("vücut", "figure.stand"), ("sağlık", "cross.case"), ("hasta", "cross.case"), ("hekim", "stethoscope"),
        ("doktor", "stethoscope"), ("ilaç", "pills"), ("kan", "drop.fill"), ("nefes", "wind"), ("akciğer", "lungs"), ("uyku", "bed.double"),
        ("yemek", "fork.knife"), ("mikrop", "microbe"), ("bakteri", "microbe"), ("virüs", "microbe"), ("hücre", "circle.hexagongrid"),
        // word
        ("kitap", "book"), ("kitab", "book"), ("oku", "book"), ("okur", "book"), ("okum", "book"), ("okud", "book"), ("okuy", "book"),
        ("okul", "building.columns"), ("yaz", "pencil.line"), ("yazı", "pencil.line"), ("yazar", "pencil.line"), ("yazm", "pencil.line"),
        ("yazd", "pencil.line"), ("kalem", "pencil"),
        ("söz", "quote.opening"), ("kelime", "textformat"), ("dil", "character.bubble"), ("konuş", "bubble.left.and.bubble.right"),
        ("soru", "questionmark"), ("sorun", "exclamationmark.questionmark"), ("cevap", "text.bubble"), ("cevab", "text.bubble"),
        ("yanıt", "text.bubble"), ("metin", "doc.text"), ("metn", "doc.text"), ("harf", "character"), ("hikâye", "book.pages"),
        ("hikaye", "book.pages"), ("öykü", "book.pages"), ("mektup", "envelope"), ("mektub", "envelope"), ("gazete", "newspaper"),
        ("haber", "megaphone"), ("ses", "waveform"), ("sessiz", "waveform"),
        // truth, knowledge
        ("hakikat", "checkmark.seal"), ("doğru", "checkmark.seal"), ("gerçek", "checkmark.seal"), ("yanlış", "xmark.seal"),
        ("hata", "xmark.circle"), ("bilgi", "books.vertical"), ("bilge", "graduationcap"), ("bilim", "atom"), ("öğren", "graduationcap"),
        ("öğret", "graduationcap"), ("ders", "book.closed"), ("kuram", "function"), ("teori", "function"), ("deney", "flask"),
        ("gözlem", "binoculars"), ("ölç", "ruler"), ("kanun", "scroll"), ("yasa", "scroll"), ("ilke", "pin"), ("sebep", "arrow.triangle.branch"),
        ("neden", "arrow.triangle.branch"), ("keşif", "magnifyingglass"), ("keşf", "magnifyingglass"), ("araştır", "magnifyingglass"),
        ("yöntem", "list.bullet.clipboard"), ("atom", "atom"), ("madde", "cube"), ("enerji", "bolt.fill"), ("elektrik", "bolt"),
        ("dalga", "water.waves"), ("ısı", "thermometer.medium"), ("sıcak", "thermometer.medium"), ("soğuk", "snowflake"),
        ("basınç", "gauge"), ("evrim", "tortoise"), ("fosil", "fossil.shell"),
        // faith
        ("iman", "sparkles"), ("inanç", "sparkles"), ("tanrı", "sparkles"), ("allah", "sparkles"), ("ruh", "sparkles"),
        ("kutsal", "sparkles"), ("dua", "hands.sparkles"), ("mucize", "sparkle"), ("güzel", "sparkle"),
        // nature
        ("doğa", "tree"), ("ağaç", "tree"), ("orman", "tree.fill"), ("dağ", "mountain.2"), ("deniz", "water.waves"), ("nehir", "water.waves"),
        ("ırmak", "water.waves"), ("su", "drop"), ("ateş", "flame"), ("hava", "wind"), ("rüzgâr", "wind"), ("rüzgar", "wind"),
        ("yağmur", "cloud.rain"), ("hayvan", "pawprint"), ("kuş", "bird"), ("balık", "fish"), ("yaprak", "leaf"), ("çiçek", "camera.macro"),
        ("toprak", "globe.asia.australia"), ("buz", "snowflake"),
        // life
        ("ölüm", "hourglass.bottomhalf.filled"), ("hayat", "leaf"), ("yaşam", "leaf"), ("doğum", "sunrise"),
        // people, society
        ("toplum", "person.3"), ("insan", "figure.stand"), ("kişi", "person"), ("halk", "person.3"), ("aile", "figure.2.and.child.holdinghands"),
        ("çocuk", "figure.child"), ("dost", "person.2"), ("arkadaş", "person.2"), ("devlet", "building.columns"), ("hükümet", "building.columns"),
        ("mahkeme", "building.columns"), ("adalet", "scalemass"), ("hukuk", "scalemass"), ("denge", "scalemass"), ("kral", "crown"),
        ("padişah", "crown"), ("sultan", "crown"), ("iktidar", "crown"), ("ferman", "scroll"), ("savaş", "shield"), ("ordu", "shield.lefthalf.filled"),
        ("asker", "shield.lefthalf.filled"), ("barış", "hands.sparkles"), ("özgür", "bird"), ("şehir", "building.2"), ("kent", "building.2"),
        ("köy", "house.lodge"), ("ev", "house"), ("ülke", "flag"), ("millet", "flag"), ("ulus", "flag"), ("bayrak", "flag"),
        ("filozof", "brain.head.profile"), ("felsef", "brain.head.profile"), ("düşünür", "brain.head.profile"), ("can", "heart"),
        ("mal", "shippingbox"), ("hak", "hand.raised"), ("tebaa", "person.3"), ("zafer", "trophy"), ("ödül", "medal"), ("hapis", "lock"),
        // economy, work
        ("para", "banknote"), ("değer", "diamond"), ("fiyat", "tag"), ("borç", "creditcard"), ("pazar", "cart"), ("ticaret", "cart"),
        ("zengin", "banknote"), ("vergi", "percent"), ("faiz", "percent"), ("sermaye", "chart.line.uptrend.xyaxis"),
        ("büyüme", "chart.line.uptrend.xyaxis"), ("çalış", "hammer"), ("emek", "hammer"), ("üret", "gearshape.2"), ("alet", "wrench.and.screwdriver"),
        ("araç", "wrench.and.screwdriver"),
        // force
        ("güç", "bolt"), ("güc", "bolt"), ("kuvvet", "bolt"), ("hız", "speedometer"), ("çatış", "bolt.horizontal"), ("çeliş", "bolt.horizontal"),
        ("karşı", "arrow.left.arrow.right"), ("birleş", "arrow.triangle.merge"), ("birlik", "arrow.triangle.merge"), ("ayrım", "arrow.triangle.branch"),
        ("eşit", "equal"), ("fark", "plusminus"), ("koru", "shield"), ("güven", "lock.shield"), ("gizli", "lock"), ("sır", "lock"),
        ("anahtar", "key"), ("kilit", "lock"), ("çözüm", "key"),
        // number, machine
        ("sayı", "number"), ("hesap", "function"), ("hesab", "function"), ("sıfır", "0.circle"), ("makine", "gearshape.2"),
        ("bilgisayar", "desktopcomputer"), ("kod", "chevron.left.forwardslash.chevron.right"), ("program", "terminal"),
        ("yazılım", "chevron.left.forwardslash.chevron.right"), ("veri", "cylinder.split.1x2"), ("ağ", "network"), ("telefon", "iphone"),
        ("ekran", "display"), ("işlemci", "cpu"),
        // structure
        ("düzen", "square.grid.3x3"), ("yapı", "building.columns"), ("sistem", "gearshape.2"), ("parça", "puzzlepiece"),
        ("katman", "square.stack.3d.up"), ("temel", "square.stack.3d.up"), ("zincir", "link"), ("bağ", "link"), ("bağla", "link"),
        ("ilişki", "link"), ("kutu", "shippingbox"),
        // art
        ("müzik", "music.note"), ("şarkı", "music.mic"), ("sanat", "paintpalette"), ("renk", "paintpalette"), ("resim", "photo"),
        ("sahne", "theatermasks"), ("tiyatro", "theatermasks"), ("oyun", "die.face.5"), ("film", "film"), ("hediye", "gift"), ("çan", "bell"),
    ]

    /// Words that start with a root and mean something else.
    private static let never: Set<String> = ["göre", "görece", "bile", "yazık", "güncel", "sorumlu", "dilek"]
    private static let neverStarts = ["görev", "görkem", "yapıl", "yapıyo", "yapın", "yapıp", "yapma", "duyur", "sorum", "kanal", "karşıl",
                                      "parag", "parad", "paral", "paran", "parab"]
    /// The plain endings a short root may carry.
    private static let endings: Set<String> = ["", "lar", "ler", "ı", "i", "u", "ü", "a", "e", "da", "de", "ta", "te", "dan", "den", "tan",
        "ten", "ın", "in", "un", "ün", "yı", "yi", "yu", "yü", "ya", "ye", "nın", "nin", "nun", "nün", "la", "le", "yla", "yle", "lı", "li",
        "lu", "lü", "sız", "siz", "suz", "süz", "ları", "leri", "ların", "lerin", "larda", "lerde", "lara", "lere", "ım", "im", "um", "üm",
        "sı", "si", "su", "sü", "ca", "ce", "dır", "dir", "dur", "dür", "tır", "tir", "tur", "tür", "ünü", "ini", "ını", "unu", "ında",
        "inde", "unda", "ünde", "ına", "ine", "una", "üne", "yun", "yün", "ndan", "nden"]
    private static let byLength: [(root: String, symbol: String)] = symbols.map { (root: $0.0, symbol: $0.1) }.sorted { $0.root.count > $1.root.count }

    static func symbol(for word: String) -> String? {
        let w = word.lowercased(with: Locale(identifier: "tr"))
        guard w.count >= 2, !small.contains(w), !never.contains(w), !neverStarts.contains(where: { w.hasPrefix($0) }) else { return nil }
        // a year → the calendar, any other number → the number sign
        if w.allSatisfy(\.isNumber) { return w.count == 4 ? "calendar" : "number" }
        for (root, symbol) in byLength where w.hasPrefix(root) {
            if root.count > 3 || endings.contains(String(w.dropFirst(root.count))) { return symbol }
        }
        return nil
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
        var withImage = 0
        return groups.enumerated().map { i, g in
            var marks: [Int: String] = [:]
            for (j, w) in g.enumerated() { if let s = symbol(for: clean(w)) { marks[j] = s } }
            let scored = g.enumerated().map { j, w -> (Int, Int) in
                let c = clean(w)
                return (j, small.contains(c) ? -1 : c.count + (marks[j] != nil ? 4 : 0))
            }
            let key = scored.max { $0.1 < $1.1 }?.0 ?? 0
            // a question or an exclamation brings its mark when no word of the phrase has an image
            let closing: String? = g.last.flatMap { $0.hasSuffix("?") ? "questionmark" : $0.hasSuffix("!") ? "exclamationmark" : nil }
            let sym = marks[key] ?? marks.sorted { $0.key < $1.key }.first?.value ?? closing
            var layout = Layout.allCases[(seed * 3 + i) % 4]              // the four plain compositions in turn
            if layout == .side, clean(g[key]).count < 4 || g.count < 2 { layout = .stack }
            if sym != nil {
                // Most phrases have an image now, so they take four compositions in turn: the emblem (the image in a
                // ring over the word, as a mark), the stack with every word's image on its own line, the giant word
                // with the image large and faint behind it, and the plain turn (tilt or side) with the images in line.
                switch withImage % 4 {
                case 0: layout = .emblem
                case 1: layout = .stack
                case 2: layout = .giant
                default: if layout == .giant { layout = .tilt }
                }
                withImage += 1
            }
            return KineticPhrase(id: i, words: g, key: key, layout: layout, symbol: sym, marks: marks)
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
    /// The warm glow round the key word and the images: on a dark page. On a light page (Gündüz) it only muddies.
    var glow = true
    /// Perde: the words rise from behind a line instead of slamming down, the key word on a marker bar that sweeps
    /// in first; no blur, no glow, no shader (only offsets and clips: the phone draws it without effort).
    var mask = false
    /// The page behind the lettering: the key word's colour when it stands on the marker bar.
    var page: Color = .black

    var body: some View {
        Group {
            switch phrase.layout {
            case .stack: stack(width: size.width)
            case .tilt: stack(width: size.width * 0.9).rotationEffect(.degrees(-7))
            case .side where mask: stack(width: size.width)       // a word turned on its side cannot rise behind a line
            case .side: side
            case .giant: giant
            case .emblem: emblem
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .bottomLeading) {
            // Perde: a rule under the stage fills as the phrase is heard
            if mask {
                Rectangle().fill(accent.opacity(0.85)).frame(width: size.width, height: 3)
                    .scaleEffect(x: CGFloat(min(shown, phrase.words.count)) / CGFloat(max(1, phrase.words.count)), y: 1, anchor: .leading)
                    .animation(.easeOut(duration: 0.3), value: shown)
            }
        }
    }

    /// The key word stands on the marker bar (Perde, where the word sits in a line of its own).
    private var barred: Bool { mask && phrase.layout != .emblem }

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
            // a word with an image gives it a fifth of the line: the image lands with its word
            let image = phrase.marks[i]
            let side = image == nil ? 0 : min(width * 0.2, 86)
            HStack(alignment: .center, spacing: image == nil ? 0 : 10) {
                Text(bare(i))
                    .font(.system(size: maxSize, weight: i == phrase.key ? .black : .heavy, design: i == phrase.key ? .serif : .default))
                    .italic(i == phrase.key && phrase.layout == .tilt)
                    .foregroundStyle(i == phrase.key ? (barred ? page : accent) : paper)
                    .shadow(color: accent.opacity(i == phrase.key && glow && !mask ? 0.5 : 0), radius: 18)
                    .lineLimit(1)
                    .minimumScaleFactor(0.08)
                    .frame(width: width - side - (image == nil ? 0 : 10), alignment: .leading)
                if let image {
                    Image(systemName: image).font(.system(size: side * 0.72, weight: .regular))
                        .foregroundStyle(i == phrase.key ? (barred ? page : accent) : paper.opacity(0.8))
                        .shadow(color: accent.opacity(i == phrase.key && glow && !mask ? 0.45 : 0), radius: 12)
                        .frame(width: side)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: width, alignment: .leading)
        }
    }

    private func land(_ i: Int) -> AnyTransition {
        if mask { return i == phrase.key && barred ? Rise.key(bar: accent) : Rise.word }
        return i == phrase.key ? .modifier(active: Slam(t: 0, big: true), identity: Slam(t: 1, big: true))
                               : .modifier(active: Slam(t: 0, big: false), identity: Slam(t: 1, big: false))
    }

    /// The key word's (or the image's) arrival where it stands alone.
    private var landBig: AnyTransition {
        mask ? Rise.word : .modifier(active: Slam(t: 0, big: true), identity: Slam(t: 1, big: true))
    }

    /// The giant key word: on the bar in Perde.
    private var landGiant: AnyTransition { mask ? Rise.key(bar: accent) : landBig }

    private func stack(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: -4) {
            ForEach(0..<min(shown, phrase.words.count), id: \.self) { i in
                word(i, width: width, maxSize: 220).transition(land(i))
            }
            // a question's or an exclamation's mark (no word of the phrase had an image) closes the stack
            if let s = phrase.symbol, phrase.marks.isEmpty, shown >= phrase.words.count {
                Image(systemName: s).font(.system(size: width * 0.2, weight: .semibold)).foregroundStyle(accent)
                    .padding(.top, 12)
                    .transition(landBig)
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
                        .shadow(color: accent.opacity(glow && !mask ? 0.5 : 0), radius: 18)
                        .lineLimit(1).minimumScaleFactor(0.08)
                        .frame(width: size.height * 0.92)
                        .fixedSize(horizontal: true, vertical: false)
                        .rotationEffect(.degrees(-90))
                        .transition(landBig)
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
                    .foregroundStyle(accent.opacity(glow ? 0.16 : 0.2))
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                    .accessibilityHidden(true)
            }
            VStack(spacing: 10) {
                Text(before.filter { $0 < shown }.map { phrase.words[$0] }.joined(separator: " ").uppercased(with: Locale(identifier: "tr")))
                    .font(.system(size: 16, weight: .semibold, design: .monospaced)).tracking(5)
                    .foregroundStyle(paper.opacity(0.75)).multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                if shown > phrase.key {
                    Text(bare(phrase.key))
                        .font(.system(size: 260, weight: .black, design: .serif))
                        .foregroundStyle(mask ? page : accent)
                        .shadow(color: accent.opacity(glow && !mask ? 0.55 : 0), radius: 22)
                        .lineLimit(1).minimumScaleFactor(0.08)
                        .frame(width: size.width)
                        .transition(landGiant)
                }
                Text(after.filter { $0 < shown }.map { phrase.words[$0] }.joined(separator: " ").uppercased(with: Locale(identifier: "tr")))
                    .font(.system(size: 16, weight: .semibold, design: .monospaced)).tracking(5)
                    .foregroundStyle(paper.opacity(0.75)).multilineTextAlignment(.center)
                    .contentTransition(.opacity)
            }
        }
    }
}

extension KineticPhraseView {
    /// The image as a mark over its word, the way a logo is set: a ring, the image in it, the key word under it in
    /// heavy serif, the phrase's other words small and spaced above and below. The image lands with the first word.
    var emblem: some View {
        let before = Array(0..<phrase.key), after = Array((phrase.key + 1)..<phrase.words.count)
        let d = min(size.width * 0.46, size.height * 0.36)
        func line(_ ids: [Int]) -> some View {
            Text(ids.filter { $0 < shown }.map { phrase.words[$0] }.joined(separator: " ").uppercased(with: Locale(identifier: "tr")))
                .font(.system(size: 16, weight: .semibold, design: .monospaced)).tracking(5)
                .foregroundStyle(paper.opacity(0.75)).multilineTextAlignment(.center)
                .contentTransition(.opacity)
        }
        return VStack(spacing: 14) {
            if let s = phrase.symbol, shown > 0 {
                ZStack {
                    Circle().strokeBorder(accent.opacity(0.55), lineWidth: 2)
                    Circle().strokeBorder(accent.opacity(0.18), lineWidth: 1).padding(-9)
                    Image(systemName: s).font(.system(size: d * 0.5, weight: .medium)).foregroundStyle(accent)
                        .shadow(color: accent.opacity(glow && !mask ? 0.6 : 0), radius: 16)
                }
                .frame(width: d, height: d)
                .transition(landBig)
                .accessibilityHidden(true)
            }
            line(before)
            if shown > phrase.key {
                Text(bare(phrase.key))
                    .font(.system(size: 150, weight: .black, design: .serif))
                    .foregroundStyle(paper)
                    .lineLimit(1).minimumScaleFactor(0.08)
                    .frame(width: size.width)
                    .transition(landBig)
            }
            line(after)
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

/// Perde: a word rises into its own line from below, cut off at the line (the "mask reveal" of film titles). Only an
/// offset and a clip, so it costs the phone next to nothing; the ink shader it replaced (2026-11-06) ran a noise
/// field over every pixel of every word and stuttered on the phone. The key word's marker bar sweeps in from the
/// left while the word rises on it.
struct Rise: ViewModifier, Animatable {
    var t: Double
    var bar: Color? = nil

    var animatableData: Double {
        get { t }
        set { t = newValue }
    }

    func body(content: Content) -> some View {
        let up = t
        content
            .visualEffect { c, proxy in c.offset(y: (1 - up) * proxy.size.height * 1.08) }
            // at rest the cut is moved away, so nothing of the settled word is trimmed
            .mask { Rectangle().padding(up >= 0.999 ? -80 : 0) }
            .background {
                if let bar {
                    Rectangle().fill(bar).padding(.horizontal, -10)
                        .scaleEffect(x: min(1, t / 0.6), y: 1, anchor: .leading)
                }
            }
    }

    static var word: AnyTransition {
        .modifier(active: Rise(t: 0), identity: Rise(t: 1)).animation(.easeOut(duration: 0.26))
    }

    static func key(bar: Color) -> AnyTransition {
        .modifier(active: Rise(t: 0, bar: bar), identity: Rise(t: 1, bar: bar)).animation(.easeOut(duration: 0.3))
    }

    /// A whole phrase leaving: up and away.
    static var leave: AnyTransition {
        .modifier(active: Lift(t: 0), identity: Lift(t: 1)).animation(.easeIn(duration: 0.28))
    }
}

struct Lift: ViewModifier {
    var t: Double
    func body(content: Content) -> some View {
        content.offset(y: (1 - t) * -70).opacity(t)
    }
}
