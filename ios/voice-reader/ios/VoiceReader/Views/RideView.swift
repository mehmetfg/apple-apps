// Yolda: the moving modes' road screen. One OLED-black page, the same whatever the speed (2026-10-28: the stages
// that changed with the GPS speed are gone): on top only a quiet line (clock · battery · speed; a tap shows the way's
// time · km · calories large), the book and the chapter at the bottom; in the middle the last sentences as they are heard (Yolda) or the heard words set as kinetic type (Kinetik). The GPS
// record runs as long as the moving mode is on, also on the full text (Tam metin), where the whole book can be
// browsed and marked. Marking (a tap anywhere, the big key, the headphone's ⏭), a voice note, the speed and the
// chapters are always at hand; a long press on the library key switches the book. The reading place moves only by
// the rest bar's buttons and the contents' ▶ — never by looking.
import SwiftUI

enum BikeLook: String, CaseIterable, Identifiable, Sendable {
    case focus, kinetic, reader, classic
    var id: String { rawValue }
    var name: String {
        switch self {
        case .focus: "Yolda"
        case .kinetic: "Kinetik"
        case .reader: "Tam metin"
        case .classic: "Klasik"
        }
    }
    var symbol: String {
        switch self {
        case .focus: "moon.stars"
        case .kinetic: "textformat.size.larger"
        case .reader: "doc.plaintext"
        case .classic: "rectangle.grid.1x2"
        }
    }
    /// The two dark road screens (the others are the reader's page).
    var road: Bool { self == .focus || self == .kinetic }
}

/// The colours of the road screen. Gece: OLED black, cream text, sunlight amber for what is heard, gold for marks.
/// Gündüz (2026-11-06): warm paper, ink text, a burnt orange and a deep gold that hold against daylight; the same
/// roles, so every piece of the screen follows. `day` is set by the screen before it draws (RideView, MusicModeView).
enum Ride {
    nonisolated(unsafe) static var day = false

    private static func pick(_ night: (Double, Double, Double), _ day: (Double, Double, Double)) -> Color {
        let c = Self.day ? day : night
        return Color(red: c.0, green: c.1, blue: c.2)
    }
    static var oled: Color { pick((0, 0, 0), (0.965, 0.945, 0.905)) }
    static var panel: Color { pick((0.051, 0.047, 0.043), (0.935, 0.912, 0.868)) }
    static var raise: Color { pick((0.090, 0.082, 0.075), (0.905, 0.880, 0.832)) }
    static var line: Color { pick((0.165, 0.149, 0.133), (0.800, 0.770, 0.710)) }
    static var paper: Color { pick((0.957, 0.925, 0.863), (0.125, 0.105, 0.085)) }
    static var muted: Color { pick((0.553, 0.525, 0.482), (0.400, 0.370, 0.330)) }
    static var dim: Color { pick((0.290, 0.271, 0.247), (0.600, 0.570, 0.520)) }
    static var amber: Color { pick((0.941, 0.698, 0.290), (0.780, 0.360, 0.030)) }
    static var gold: Color { pick((0.847, 0.698, 0.369), (0.620, 0.430, 0.060)) }
    static var alert: Color { pick((0.886, 0.439, 0.353), (0.760, 0.240, 0.160)) }
    /// Hairlines round the quiet keys, the wells the dock's keys sit in, the progress track, text on an amber key.
    static var edge: Color { pick((0.120, 0.110, 0.100), (0.830, 0.800, 0.745)) }
    static var well: Color { pick((0.055, 0.051, 0.047), (0.990, 0.978, 0.952)) }
    static var track: Color { pick((0.114, 0.106, 0.098), (0.850, 0.820, 0.765)) }
    static var onAmber: Color { day ? .white : Color.black.opacity(0.85) }
    static var uiPaper: UIColor { day ? UIColor(red: 0.125, green: 0.105, blue: 0.085, alpha: 1) : UIColor(red: 0.957, green: 0.925, blue: 0.863, alpha: 1) }

    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .serif) }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .monospaced) }
}

/// Whether the phone's screen is turned up as in daylight (auto-brightness goes above three quarters outdoors):
/// what "Otomatik" follows. It comes on at 75 % and goes off under 55 %, so it does not flicker at the edge.
@MainActor
@Observable
final class DayLight {
    static let shared = DayLight()
    private(set) var bright = false

    private init() {
        update()
        NotificationCenter.default.addObserver(forName: UIScreen.brightnessDidChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { DayLight.shared.update() }
        }
    }
    private func update() {
        let b = UIScreen.main.brightness
        if b >= 0.75 { bright = true } else if b <= 0.55 { bright = false }
    }
}

/// The road screen's and the kinetic type's light: Gece (as it was), Gündüz, or by the screen's brightness.
enum RideLight: String, CaseIterable, Identifiable {
    case night, day, auto
    var id: String { rawValue }
    var name: String { self == .night ? "Gece" : self == .day ? "Gündüz" : "Otomatik (ekran parlaklığına göre)" }
    var symbol: String { self == .night ? "moon.stars" : self == .day ? "sun.max" : "circle.lefthalf.filled" }
}

extension AppModel {
    var rideDay: Bool {
        switch RideLight(rawValue: settings.rideLight) ?? .night {
        case .night: false
        case .day: true
        case .auto: DayLight.shared.bright
        }
    }
}

// MARK: - concepts

/// The concept of each sentence: a content word that recurs in the book (grouped by its first five letters, so
/// "bilginin" and "bilgi" count together) or a proper noun. Worked out once per document, off the main thread.
enum RideConcepts {
    private static let stop: Set<String> = Set("""
        ve veya ile ama fakat ancak lakin çünkü için gibi kadar daha çok pek en bu şu o bir iki her hiç hiçbir ne neden nasıl niçin
        ki de da mi mı mu mü ise ya yani bile sadece yalnız artık hep hepsi olan olarak olur olup olduğu olduğunu oldu olmak olmuş olsa
        etmek eder ediyor etti değil değildir var yok ben sen biz siz onlar onun bunun şunun bunu şunu onu ona buna bana sana bize size
        kendi kendini kendine göre doğru sonra önce üzere iken diye beri karşı rağmen ayrıca hem hemen zaten belki tüm bütün bazı birçok
        birkaç böyle şöyle öyle burada orada şimdi bunlar şunlar onları bunları bunlara içinde üzerine üstünde altında arasında yine
        gene başka diğer aynı şekilde biraz bazen kimi kimse herkes herşey birşey nedir değildi gerek gerekir olabilir olmalı yapmak
        yapar yaptı demek dedi diyor sanki bütünüyle oysa halde şeyi şeyler şeylerin tarafından ilgili yalnızca aslında bunun şeyin
        olduğunu olduğu olarak olan olduğunda bizim sizin onların kendisi kendileri dolayı itibaren böylece ardından birlikte
        büyük küçük önemli yeni eski ilk uzun kısa bugün yalnızca neredeyse sonunda başında yerine tarafı zaman zamanda
        şöyle böylece çünkü hiçbir birinin birini birine ikinci üçüncü kelime kelimeyi kelimeler cümle soruyu sorusu
        the and of to in is that for with this from are was were have has but not
        """.split(whereSeparator: \.isWhitespace).map(String.init))

    private static let tr = Locale(identifier: "tr_TR")

    private static func norm(_ w: String) -> String {
        let head = w.split(whereSeparator: { $0 == "'" || $0 == "’" }).first.map(String.init) ?? w
        return head.lowercased(with: tr).filter(\.isLetter)
    }
    private static func key(_ n: String) -> String { n.count >= 6 ? String(n.prefix(5)) : n }

    /// Word offset → the label shown for it.
    nonisolated static func build(_ text: String) -> [Int: String] {
        let ns = text as NSString
        struct Word { var loc: Int; var norm: String; var surface: String; var proper: Bool }
        var sentences: [[Word]] = []
        var freq: [String: Int] = [:]
        var label: [String: String] = [:]
        var properLabel: [String: String] = [:]            // a name seen capitalised mid-sentence keeps its capital
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .bySentences) { _, sr, _, _ in
            var raw: [(w: String, r: NSRange)] = []
            ns.enumerateSubstrings(in: sr, options: .byWords) { w, r, _, _ in if let w { raw.append((w, r)) } }
            // a heading capitalises every word: there a capital says nothing about a name
            let caps = raw.filter { $0.w.first?.isUppercase ?? false }.count
            let heading = raw.count > 1 && caps * 2 > raw.count
            var words: [Word] = []
            for (i, item) in raw.enumerated() {
                let n = norm(item.w)
                let surface = String((item.w.split(whereSeparator: { $0 == "'" || $0 == "’" }).first ?? Substring(item.w)).filter(\.isLetter))
                let proper = i > 0 && !heading && (surface.first?.isUppercase ?? false)
                guard n.count >= 4, !stop.contains(n) else { continue }
                let k = key(n)
                freq[k, default: 0] += 1
                let l = proper ? surface : n
                if let b = label[k] { if l.count < b.count { label[k] = l } } else { label[k] = l }
                if proper, surface.count < (properLabel[k]?.count ?? .max) { properLabel[k] = surface }
                words.append(Word(loc: item.r.location, norm: n, surface: surface, proper: proper))
            }
            sentences.append(words)
        }
        var out: [Int: String] = [:]
        for words in sentences {
            let want = words.count >= 12 ? 2 : 1
            let cands = words.compactMap { w -> (Word, String, Double)? in
                guard w.norm.count >= 5, w.norm.count <= 18 else { return nil }
                let k = key(w.norm), f = freq[k] ?? 1
                guard f >= 2 || w.proper else { return nil }
                return (w, k, log2(1 + Double(f)) + (w.proper ? 1.5 : 0) + Double(w.norm.count) * 0.08)
            }.sorted { $0.2 > $1.2 }
            var used: Set<String> = []
            for (w, k, _) in cands where used.count < want && !used.contains(k) {
                used.insert(k)
                out[w.loc] = properLabel[k] ?? label[k] ?? w.norm
            }
        }
        return out
    }
}

// MARK: - the screen's state

@MainActor
@Observable
final class RideState {
    private(set) var sediment: [String] = []
    private(set) var leaves = 0
    private(set) var falling = 0
    var toast: String?
    @ObservationIgnored var concepts: [Int: String] = [:]
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored var markPoint: CGPoint = .zero

    /// The voice reached a word: its concept joins the sediment.
    func heard(_ word: NSRange?) {
        guard let word, let label = concepts[word.location], !sediment.contains(label) else { return }
        sediment.append(label)
        if sediment.count > 24 { sediment.removeFirst() }
    }

    func marked(_ r: AppModel.MarkResult) {
        if r.added { leaves += 1; falling += 1 } else { leaves = max(0, leaves - 1) }
        say(r.added ? (r.previous ? "Önceki cümle işaretlendi" : "Cümle işaretlendi")
                    : (r.previous ? "Önceki cümlenin işareti kaldırıldı" : "İşaret kaldırıldı"))
    }

    func say(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func reset() { sediment = []; leaves = 0 }
}

// MARK: - the view

struct RideView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let content: DocumentContent?
    var onBack: () -> Void
    var onContents: () -> Void
    var onJump: (Int, Bool?) -> Void
    @State private var state = RideState()
    @State private var board = false               // the way's numbers, large, in the middle
    @State private var switching = false           // the books to switch to (a long press on the library key)
    @State private var held = 0

    private var player: SpeechPlayer { model.player }
    private var kinetic: Bool { model.settings.bikeLook == .kinetic }

    var body: some View {
        // the palette is chosen before anything is drawn; a change of it builds the screen again (`.id`), since the
        // pieces take their colours from Ride, not from their inputs
        let day = model.rideDay
        let _ = (Ride.day = day)
        return screen
            .id(day)
            .preferredColorScheme(day ? .light : .dark)
    }

    private var screen: some View {
        GeometryReader { g in
            let w = min(g.size.width, 520)
            ZStack {
                Ride.oled.ignoresSafeArea()
                RideTint(w: w)
                Group {
                    if kinetic {
                        KineticListening(size: CGSize(width: w * 0.88, height: max(200, g.size.height - 430)), accent: Ride.amber, paper: Ride.paper,
                                         glow: !Ride.day, mask: model.settings.kineticMask, page: Ride.oled)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        RestLayer(w: w, concepts: state.concepts, markTick: state.falling)
                            .padding(.horizontal, w * 0.07)
                    }
                }
                .padding(.top, 96)
                .padding(.bottom, 220)
                .frame(width: w)
                .allowsHitTesting(false)
                MarkBurst(tick: state.falling, from: state.markPoint, to: CGPoint(x: g.size.width * 0.86, y: g.size.height - 150),
                          reduceMotion: reduceMotion)
                    .allowsHitTesting(false)
                // anywhere on the page: a tap marks the sentence being heard
                Color.clear.contentShape(Rectangle())
                    .padding(.top, 70).padding(.bottom, 96)
                    .onTapGesture(coordinateSpace: .named("ride")) { p in state.markPoint = p; mark() }
                    .accessibilityLabel("Okunan cümleyi işaretle")
                    .accessibilityAddTraits(.isButton)
                chrome(w: w)
                    .frame(width: w)
                if let t = state.toast {
                    Text(t)
                        .font(Ride.mono(13))
                        .foregroundStyle(Ride.gold)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Ride.well, in: Capsule())
                        .overlay(Capsule().strokeBorder(Ride.gold.opacity(0.35), lineWidth: 1))
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, w * 0.2)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
                MoveBoard(shown: $board)
            }
            .frame(maxWidth: .infinity)
            .coordinateSpace(.named("ride"))
            .onAppear { state.markPoint = CGPoint(x: g.size.width / 2, y: g.size.height * 0.35) }
        }
        .statusBarHidden(true)                      // the quiet top line has the clock and the battery
        .animation(.easeInOut(duration: 0.3), value: state.toast)
        .animation(.smooth(duration: 0.4), value: kinetic)
        .sheet(isPresented: $switching) { BookSwitchSheet() }
        // the word being heard is watched by a view of its own: read here, every word evaluated this whole screen again
        .background { HeardWordWatch(state: state) }
        // the concepts are worked out once the text is there (it can arrive a moment after the screen)
        .task(id: "\(player.documentID?.uuidString ?? "")·\(content?.text.utf16.count ?? 0)") {
            state.reset()
            guard let text = content?.text else { return }
            let map = await Task.detached(priority: .utility) { RideConcepts.build(text) }.value
            state.concepts = map
        }
    }

    // MARK: chrome

    @ViewBuilder private func chrome(w: CGFloat) -> some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            if !kinetic { sediment(w: w) }
            RestBar(onJump: onJump)
                .padding(.bottom, 10)
            RideBookLine(title: title, onContents: onContents)
                .padding(.horizontal, w * 0.06)
                .padding(.bottom, 6)
            RideProgress()
                .padding(.horizontal, w * 0.06)
                .padding(.bottom, 10)
            RideDock(state: state, mark: mark)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
        }
    }

    /// Library (a long press: switch the book) · contents · the quiet line (a tap: the way's numbers large) · the
    /// full text · the mode.
    private var topBar: some View {
        HStack(spacing: 8) {
            libraryKey
            ghost("list.bullet", "İçindekiler", action: onContents)
            Spacer(minLength: 0)
            Button { withAnimation(.smooth(duration: 0.3)) { board.toggle() } } label: {
                RoadStatus()
                    .padding(.vertical, 6)
                    .frame(maxWidth: 220)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Dokun: süre, km, kalori")
            Spacer(minLength: 0)
            ghost("doc.plaintext", "Tam metne geç (yol kaydı sürer)") {
                withAnimation(.smooth(duration: 0.35)) { model.settings.bikeLook = .reader }
            }
            MoveModeMenu(size: 24, color: Ride.amber)
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
    }

    /// Tap: the library. Hold: the books to switch to, at the bottom of the screen.
    private var libraryKey: some View {
        Image(systemName: "books.vertical").font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Ride.muted)
            .frame(width: 44, height: 40)
            .overlay(Capsule().strokeBorder(Ride.edge, lineWidth: 1))
            .contentShape(Capsule())
            .onTapGesture(perform: onBack)
            .onLongPressGesture(minimumDuration: 0.45) { held += 1; switching = true }
            .sensoryFeedback(.impact(weight: .medium), trigger: held)
            .accessibilityLabel("Kütüphane")
            .accessibilityHint("Basılı tut: başka kitaba geç")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Başka kitaba geç") { switching = true }
    }

    private func ghost(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Ride.muted)
                .frame(width: 44, height: 40)
                .overlay(Capsule().strokeBorder(Ride.edge, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// The concepts heard this ride, quietly settled at the bottom; at most two lines, older ones paler.
    private func sediment(w: CGFloat) -> some View {
        let recent = Array(state.sediment.suffix(10))
        return HStack(alignment: .bottom) {
            FlowRow(spacing: w * 0.03) {
                ForEach(Array(recent.enumerated()), id: \.element) { i, s in
                    Text(s).font(Ride.serif(w * 0.039))
                        .foregroundStyle(Ride.muted.opacity(i < recent.count - 4 ? 0.45 : 1))
                        .transition(.opacity.combined(with: .offset(y: -8)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: w * 0.17, alignment: .bottomLeading)
            .clipped()
            HStack(spacing: w * 0.012) {
                ForEach(0..<min(state.leaves, 6), id: \.self) { _ in
                    Leaf().fill(Ride.gold).frame(width: w * 0.024, height: w * 0.034)
                        .shadow(color: Ride.gold.opacity(0.6), radius: 4)
                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                }
            }
        }
        .padding(.horizontal, w * 0.06)
        .padding(.bottom, 8)
        .animation(.easeOut(duration: 1.2), value: state.sediment)
        .animation(.spring(duration: 0.5, bounce: 0.5).delay(1.0), value: state.leaves)
        .allowsHitTesting(false)
    }

    private func mark() {
        guard player.documentID != nil, let r = model.markSpokenSentence() else { return }
        state.marked(r)
    }
}

// MARK: - the road screen's pieces that follow the voice
//
// Each is a view of its own, so what changes with the voice (the word, the sentence, the place) evaluates only that
// piece again and never the whole road screen.

/// Feeds the heard word to the ride's state (its concept joins the sediment).
private struct HeardWordWatch: View {
    @Environment(AppModel.self) private var model
    let state: RideState

    var body: some View {
        Color.clear
            .onChange(of: model.player.spokenWord) { _, wr in state.heard(wr) }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A warm glow whose hue drifts with the sentences, slowly enough not to be noticed.
private struct RideTint: View {
    @Environment(AppModel.self) private var model
    let w: CGFloat

    var body: some View {
        let player = model.player
        let hue = 24 + Double((player.spokenSentence?.location ?? player.shownCursor) / 600 % 9) * 7
        RadialGradient(colors: [Ride.day ? Color(hue: hue / 360, saturation: 0.35, brightness: 1).opacity(0.22)
                                         : Color(hue: hue / 360, saturation: 0.45, brightness: 0.14).opacity(0.55), .clear],
                       center: UnitPoint(x: 0.5, y: 0.32), startRadius: 0, endRadius: w * 0.9)
            .ignoresSafeArea()
            .animation(.linear(duration: 6), value: hue)
            .allowsHitTesting(false)
    }
}

/// The book and the chapter, quiet, above the progress line. A tap opens the contents.
private struct RideBookLine: View {
    @Environment(AppModel.self) private var model
    let title: String
    var onContents: () -> Void

    var body: some View {
        let player = model.player
        Button(action: onContents) {
            HStack(spacing: 6) {
                Text(title).font(Ride.serif(13, .semibold)).foregroundStyle(Ride.muted)
                if let ch = player.chapterTitle(at: player.spokenSentence?.location ?? player.shownCursor) {
                    Text("·").foregroundStyle(Ride.dim)
                    Text(ch).font(.system(size: 12)).foregroundStyle(Ride.dim)
                }
                Spacer(minLength: 0)
            }
            .lineLimit(1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("İçindekiler: \(title)")
    }
}

/// The chapter's and the book's progress and the time left in the chapter (follows the place once a second).
private struct RideProgress: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let player = model.player
        let at = player.shownCursor
        let ch = player.chapters.lastIndex { $0.offset <= at }
        let start = ch.map { player.chapters[$0].offset } ?? 0
        let end = ch.flatMap { $0 + 1 < player.chapters.count ? player.chapters[$0 + 1].offset : nil } ?? player.length
        let inChapter = Double(at - start) / Double(max(1, end - start))
        let whole = Double(at) / Double(max(1, player.length))
        VStack(spacing: 5) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Ride.track)
                    Capsule().fill(Ride.amber).frame(width: max(3, g.size.width * min(1, max(0, inChapter))))
                        .shadow(color: Ride.amber.opacity(0.7), radius: 6)
                }
            }
            .frame(height: 2)
            HStack {
                Text("bölüm %\(Int(inChapter * 100))")
                Spacer()
                Text("kitap %\(Int(whole * 100))")
                Spacer()
                Text("bölümde \(Format.duration(Double(max(0, end - at)) / (player.charsPerSecond * player.speed))) kaldı")
            }
            .font(Ride.mono(11))
            .foregroundStyle(Ride.dim)
        }
        .animation(.linear(duration: 0.4), value: at)
        .allowsHitTesting(false)
    }
}

// MARK: - kinetic type of what is heard

/// The sentence being read, cut into phrases and set as kinetic type: the phrase holding the heard word is on screen,
/// its words land as the voice reaches them, and the next phrase flies in. Used by Yolda's Kinetik look and by
/// Müzik modu's "Dinle".
struct KineticListening: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let size: CGSize
    var accent: Color = Ride.amber
    var paper: Color = Ride.paper
    var glow = true
    var mask = false
    var page: Color = .black

    var body: some View {
        let p = model.player
        let sentence = p.spokenSentence ?? p.sentenceRange(around: p.cursor)
        if let sentence {
            let text = p.excerptWord(sentence).trimmingCharacters(in: .whitespacesAndNewlines)
            let phrases = KineticPhrase.phrases(text, seed: sentence.location / 7)
            let (index, shown) = Self.place(of: p.spokenWord, in: sentence, phrases: phrases, player: p)
            if phrases.indices.contains(index) {
                let phrase = phrases[index]
                KineticPhraseView(phrase: phrase, shown: shown, size: size, accent: accent, paper: paper, glow: glow, mask: mask && !reduceMotion, page: page)
                    .id("\(sentence.location)-\(phrase.id)")
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity,
                                                                      removal: mask ? Rise.leave : .modifier(active: FlyPast(t: 1), identity: FlyPast(t: 0))))
                    .animation(.spring(duration: 0.3, bounce: 0.35), value: shown)
            }
        }
    }

    /// Which phrase holds the heard word, and how many of its words are heard. Not reading: the sentence's last
    /// phrase, whole.
    static func place(of word: NSRange?, in sentence: NSRange, phrases: [KineticPhrase], player: SpeechPlayer) -> (Int, Int) {
        guard !phrases.isEmpty else { return (0, 0) }
        guard let word, NSLocationInRange(word.location, sentence) else {
            return (phrases.count - 1, phrases[phrases.count - 1].words.count)
        }
        let before = player.excerptWord(NSRange(location: sentence.location, length: word.location - sentence.location))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var n = before.isEmpty ? 0 : before.split(separator: " ").count         // words before the heard one
        for (i, ph) in phrases.enumerated() {
            if n < ph.words.count { return (i, n + 1) }
            n -= ph.words.count
        }
        return (phrases.count - 1, phrases[phrases.count - 1].words.count)
    }
}

/// A falling leaf's shape: a rounded diagonal.
private struct Leaf: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        return p
    }
}

/// Words flowing left to right, wrapping upward from the bottom line.
private struct FlowRow: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        let rows = arrange(subviews, width: width)
        let h = rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * spacing * 0.5
        return CGSize(width: width, height: h)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews, width: bounds.width)
        var y = bounds.maxY
        for row in rows.reversed() {
            y -= row.height
            var x = bounds.minX
            for i in row.items {
                let s = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + row.height - s.height), proposal: .unspecified)
                x += s.width + spacing
            }
            y -= spacing * 0.5
        }
    }
    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(items: [Int], height: CGFloat)] {
        var rows: [(items: [Int], height: CGFloat)] = []
        var cur: [Int] = [], x: CGFloat = 0, h: CGFloat = 0
        for i in subviews.indices {
            let s = subviews[i].sizeThatFits(.unspecified)
            if !cur.isEmpty, x + s.width > width { rows.append((cur, h)); cur = []; x = 0; h = 0 }
            cur.append(i); x += s.width + spacing; h = max(h, s.height)
        }
        if !cur.isEmpty { rows.append((cur, h)) }
        return rows
    }
}

// MARK: - standing still: the last three sentences

private struct RestLayer: View {
    @Environment(AppModel.self) private var model
    let w: CGFloat
    let concepts: [Int: String]
    let markTick: Int
    @State private var sweep: CGFloat = -0.3
    @State private var pageStart = -1                // the first sentence of the page on screen
    @State private var area = CGSize.zero

    var body: some View {
        let p = model.player
        let cur = p.spokenSentence ?? p.sentenceRange(around: p.cursor)
        let list = sentences(cur)
        VStack(alignment: .leading, spacing: w * 0.035) {
            ForEach(Array(list.enumerated()), id: \.element.range.location) { n, s in
                Text(attributed(s))
                    .font(Ride.serif(Self.size(w)))
                    .lineSpacing(4)
                    .lineLimit(s.past ? nil : 12)
                    .truncationMode(.head)            // a long sentence keeps its end, where the voice is
                    // the page fills downwards; the older a sentence on it, the fainter
                    .foregroundStyle(s.past ? Ride.paper.opacity(max(0.28, 0.6 - Double(list.count - 1 - n) * 0.08)) : Ride.paper)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(s.past ? 0 : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 18)),
                                            removal: .opacity.combined(with: .offset(y: -18))))
                    .overlay(alignment: .leading) {
                        if model.isMarked(s.range) {
                            Capsule().fill(Ride.gold).frame(width: 3).padding(.vertical, 2).offset(x: -w * 0.036)
                                .shadow(color: Ride.gold.opacity(0.8), radius: 6)
                                .transition(.scale(scale: 0.1, anchor: .top).combined(with: .opacity))
                        }
                    }
                    .background {
                        // a marked sentence: a soft gold wash, and a light that sweeps across it once when marked
                        if model.isMarked(s.range) {
                            GeometryReader { g in
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8).fill(Ride.gold.opacity(s.past ? 0.09 : 0.16))
                                    RoundedRectangle(cornerRadius: 8).strokeBorder(Ride.gold.opacity(s.past ? 0.18 : 0.32), lineWidth: 1)
                                    LinearGradient(colors: [.clear, Ride.gold.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing)
                                        .frame(width: g.size.width * 0.35)
                                        .offset(x: g.size.width * sweep)
                                        .blendMode(.plusLighter)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .padding(.vertical, -6).padding(.leading, -10).padding(.trailing, -6)
                            .transition(.opacity)
                        }
                    }
                    .animation(.spring(duration: 0.45, bounce: 0.35), value: model.isMarked(s.range))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .id(pageStart)                                       // a new page: the old one fades away, the new one fades in
        .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.5).delay(0.25)),
                                removal: .opacity.combined(with: .offset(y: -24)).animation(.easeIn(duration: 0.35))))
        .animation(.smooth(duration: 0.45), value: cur?.location)
        .background(GeometryReader { g in Color.clear.onAppear { area = g.size }.onChange(of: g.size) { _, v in area = v } })
        .onChange(of: cur?.location) { _, _ in turnPageIfFull(cur) }
        .onAppear { if let cur { pageStart = cur.location } }
        .onChange(of: markTick) { _, _ in
            sweep = -0.4
            withAnimation(.easeInOut(duration: 0.9)) { sweep = 1.1 }
        }
    }

    private struct Piece { var range: NSRange; var shown: NSRange; var past: Bool }

    static func size(_ w: CGFloat) -> CGFloat { w * 0.058 }

    /// The page is full when the sentences from its first one to the one being heard (whole) would not fit: then the
    /// page turns and the heard sentence starts the next one at the top. A jump back starts a page there too.
    private func turnPageIfFull(_ cur: NSRange?) {
        guard let cur else { return }
        if pageStart < 0 || cur.location < pageStart { withAnimation { pageStart = cur.location }; return }
        let p = model.player
        // measured with the screen's own serif (the key words are set semibold: measure them all semibold, so the page
        // turns a little early rather than cut a line)
        let base = UIFont.systemFont(ofSize: Self.size(w), weight: .semibold)
        let font = base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: Self.size(w)) } ?? base
        let style = NSMutableParagraphStyle(); style.lineSpacing = 4
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: style]
        var height = 0.0
        var at = cur.location
        var parts = [cur]
        while let prev = p.sentence(before: at), prev.location >= pageStart, parts.count < 30 { parts.insert(prev, at: 0); at = prev.location }
        for r in parts {
            let box = (p.excerptWord(r) as NSString).boundingRect(with: CGSize(width: area.width, height: .greatestFiniteMagnitude),
                                                                  options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
            height += Double(ceil(box.height)) + Double(w * 0.035)
        }
        if height > Double(area.height) { withAnimation { pageStart = cur.location } }
    }

    /// Two sentences before the one being heard, then that one up to the word being heard (what comes next is never
    /// shown, so the eye does not run ahead of the voice).
    private func sentences(_ cur: NSRange?) -> [Piece] {
        let p = model.player
        guard let cur else { return [] }
        var out: [Piece] = []
        var at = cur.location
        for _ in 0..<14 {
            if pageStart < 0 || at <= pageStart { break }
            // step back over the spaces and line breaks before this sentence, then take the sentence that ends there
            var k = at - 1
            while k > 0, p.excerptWord(NSRange(location: k, length: 1)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { k -= 1 }
            guard k > 0, let prev = p.sentenceRange(around: k - 1), prev.location < at, NSMaxRange(prev) <= at,
                  !p.excerptWord(prev).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { break }
            out.insert(Piece(range: prev, shown: prev, past: true), at: 0)
            at = prev.location
        }
        let heardEnd: Int
        if let w = p.spokenWord, NSLocationInRange(w.location, cur) { heardEnd = NSMaxRange(w) }
        else { heardEnd = min(max(p.cursor, cur.location), NSMaxRange(cur)) }
        if heardEnd > cur.location {
            out.append(Piece(range: cur, shown: NSRange(location: cur.location, length: heardEnd - cur.location), past: false))
        }
        return out
    }

    private func attributed(_ s: Piece) -> AttributedString {
        let p = model.player
        let ns = p.excerptWord(s.shown) as NSString
        var a = AttributedString(ns as String)
        let word = p.spokenWord
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byWords) { _, r, _, _ in
            let abs = r.location + s.shown.location
            guard let lo = AttributedString.Index(String.Index(utf16Offset: r.location, in: ns as String), within: a),
                  let hi = AttributedString.Index(String.Index(utf16Offset: NSMaxRange(r), in: ns as String), within: a) else { return }
            if concepts[abs] != nil {
                a[lo..<hi].foregroundColor = s.past ? Ride.amber.opacity(0.6) : Ride.amber
                a[lo..<hi].font = Ride.serif(s.past ? w * 0.05 : w * 0.062, .semibold)
            }
            if !s.past, let word, word.location == abs { a[lo..<hi].foregroundColor = Ride.amber }
        }
        return a
    }
}

// MARK: - standing still: the reading place's buttons

private struct RestBar: View {
    @Environment(AppModel.self) private var model
    var onJump: (Int, Bool?) -> Void

    var body: some View {
        let p = model.player
        HStack(spacing: 14) {
            key("backward.end.fill", "Önceki bölüm") { chapter(forward: false) }
                .disabled(p.chapters.isEmpty)
            key("gobackward", "Önceki cümle") { p.skip(forward: false, unit: .sentence) }
            Button { p.toggle() } label: {
                Image(systemName: p.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Ride.onAmber)
                    .offset(x: p.isPlaying ? 0 : 2)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 58, height: 58)
                    .background(Ride.amber, in: Circle())
                    .shadow(color: Ride.amber.opacity(0.45), radius: 14)
            }
            .contextMenu { ActivePauseMenu() }
            .accessibilityLabel(p.isPlaying ? "Duraklat" : "Oynat")
            key("goforward", "Sonraki cümle") { p.skip(forward: true, unit: .sentence) }
            key("forward.end.fill", "Sonraki bölüm") { chapter(forward: true) }
                .disabled(p.chapters.isEmpty)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: p.isPlaying)
    }

    private func key(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Ride.paper.opacity(0.75))
                .frame(width: 44, height: 44)
                .overlay(Circle().strokeBorder(Ride.line, lineWidth: 1))
                .contentShape(Circle())
        }
        .accessibilityLabel(label)
    }

    /// A chapter step moves the reading place on purpose; mid-chapter "back" first returns to its start.
    private func chapter(forward: Bool) {
        let p = model.player
        let cur = p.chapters.lastIndex { $0.offset <= p.cursor } ?? -1
        let j = forward ? cur + 1 : (cur >= 0 && p.cursor - p.chapters[cur].offset > 40 ? cur : cur - 1)
        guard p.chapters.indices.contains(j) else { return }
        onJump(p.chapters[j].offset, p.isPlaying ? true : false)
    }
}

// MARK: - the dock: speed · mark · voice note, always in reach

private struct RideDock: View {
    @Environment(AppModel.self) private var model
    let state: RideState
    var mark: () -> Void
    @State private var holding = false
    @State private var started = 0
    @State private var marks = 0
    @State private var held = 0

    var body: some View {
        let rec = model.recorder
        HStack(spacing: 8) {
            speed
            record(rec)
            ZStack {
                Label(held > 1 ? "\(held) cümle" : model.spokenSentenceMarked ? "Kaldır" : "İşaretle",
                      systemImage: held > 1 ? "text.line.first.and.arrowtriangle.forward" : model.spokenSentenceMarked ? "eraser" : "highlighter")
                    .contentTransition(.numericText())
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Ride.gold)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(Ride.well, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Ride.gold.opacity(0.4), lineWidth: 1))
            }
            .modifier(MarkHold(mark: { mark(); marks += 1 }, count: $held))
            .animation(.snappy, value: held)
            .sensoryFeedback(.success, trigger: marks)
            .accessibilityLabel(model.spokenSentenceMarked ? "Okunan cümlenin işaretini kaldır" : "Okunan cümleyi işaretle")
        }
    }

    /// One key, four speeds: each tap goes 330 → 380 → 430 → 470 → 330 words a minute (the same setting as everywhere).
    static let speeds = [330, 380, 430, 470]

    private var speed: some View {
        let now = SpeechPlayer.wpm(model.player.speed)
        return Button {
            let next = Self.speeds.first { $0 > now + 2 } ?? Self.speeds[0]
            model.setSpeed(Double(next) / SpeechPlayer.wordsAtOneX, documentOnly: model.speedIsDocumentSpecific)
            state.say("Hız \(next) kelime/dk")
        } label: {
            VStack(spacing: 0) {
                Text("\(now)").font(Ride.mono(17, .semibold)).monospacedDigit()
                    .contentTransition(.numericText(value: Double(now)))
                Text("k/dk").font(Ride.mono(10)).foregroundStyle(Ride.muted)
            }
            .foregroundStyle(Ride.paper)
            .frame(width: 66, height: 60)
            .background(Ride.well, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Ride.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.smooth(duration: 0.2), value: now)
        .sensoryFeedback(.selection, trigger: now)
        .accessibilityLabel("Hız: dakikada \(now) kelime. Dokun: sonraki hız")
    }

    /// Hold one second to start (a ring runs round the key), tap to stop: a stray touch never starts a recording.
    private func record(_ rec: NoteRecorder) -> some View {
        let on = rec.isRecording
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return VStack(spacing: 3) {
            Image(systemName: on ? "stop.fill" : "mic.fill").font(.system(size: 18, weight: .semibold))
            Text(on ? "Bitir" : "Basılı tut").font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(on ? (Ride.day ? Color.white : Color(red: 1, green: 0.85, blue: 0.81)) : Ride.alert)
        .frame(width: 84, height: 60)
        .background(on ? (Ride.day ? Ride.alert : Color(red: 0.227, green: 0.098, blue: 0.071)) : Ride.well, in: shape)
        .overlay(shape.strokeBorder(on ? Ride.alert : Ride.alert.opacity(0.4), lineWidth: 1))
        .overlay(shape.trim(from: 0, to: holding ? 1 : 0).stroke(Ride.alert, style: StrokeStyle(lineWidth: 3, lineCap: .round)).padding(2)
            .animation(holding ? .linear(duration: MicHold.seconds) : .easeOut(duration: 0.15), value: holding).allowsHitTesting(false))
        .scaleEffect(on ? 1 + CGFloat(rec.level) * 0.05 : 1)
        .animation(.easeOut(duration: 0.12), value: rec.level)
        .contentShape(shape)
        .onTapGesture { if on { model.finishVoiceNote(); state.say("Sesli not kaydedildi") } }
        .onLongPressGesture(minimumDuration: MicHold.seconds, perform: {
            guard !model.recorder.isRecording else { return }
            started += 1
            model.startVoiceNote()
            state.say("Kayıt başladı · bitirmek için dokun")
        }, onPressingChanged: { p in holding = p && !model.recorder.isRecording })
        .sensoryFeedback(.impact(weight: .heavy), trigger: started)
        .accessibilityLabel(on ? "Sesli notu bitir" : "Sesli not: yarım saniye basılı tut")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.toggleVoiceNote() }
    }
}

// MARK: - the mark's animation

/// A mark, seen without reading: a gold ring spreads from where the finger touched, a few sparks rise, and a leaf
/// drifts down to the leaves by the progress line. Off with Reduce Motion (only a short glow).
private struct MarkBurst: View {
    let tick: Int
    let from: CGPoint
    let to: CGPoint
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            if tick > 0 {
                Burst(from: from, to: to, reduceMotion: reduceMotion).id(tick)
            }
        }
        .ignoresSafeArea()
    }

    private struct Burst: View {
        let from: CGPoint
        let to: CGPoint
        let reduceMotion: Bool
        @State private var t: CGFloat = 0
        @State private var fall: CGFloat = 0

        var body: some View {
            ZStack {
                // two rings, the second a beat later
                ForEach(0..<2, id: \.self) { k in
                    Circle()
                        .strokeBorder(Ride.gold.opacity(Double(1 - t) * (k == 0 ? 0.9 : 0.5)), lineWidth: k == 0 ? 2.5 : 1.5)
                        .frame(width: 30 + 190 * t * (k == 0 ? 1 : 0.7), height: 30 + 190 * t * (k == 0 ? 1 : 0.7))
                        .position(from)
                }
                Circle().fill(RadialGradient(colors: [Ride.gold.opacity(0.55 * Double(1 - t)), .clear], center: .center, startRadius: 0, endRadius: 70))
                    .frame(width: 140, height: 140)
                    .position(from)
                if !reduceMotion {
                    // sparks
                    ForEach(0..<8, id: \.self) { i in
                        let a = Double(i) / 8 * 2 * .pi - .pi / 2
                        Circle().fill(Ride.amber)
                            .frame(width: 4, height: 4)
                            .position(x: from.x + cos(a) * 70 * t, y: from.y + sin(a) * 70 * t - 20 * t)
                            .opacity(Double(1 - t))
                    }
                    // the leaf: drifts with a sway, turns, lands by the counter
                    Leaf()
                        .fill(LinearGradient(colors: [Ride.gold, Ride.amber], startPoint: .top, endPoint: .bottom))
                        .frame(width: 16, height: 22)
                        .shadow(color: Ride.gold.opacity(0.7), radius: 6)
                        .rotationEffect(.degrees(Double(fall) * 220))
                        .position(x: from.x + (to.x - from.x) * fall + sin(fall * .pi * 3) * 24,
                                  y: from.y + (to.y - from.y) * fall * fall)
                        .opacity(fall < 0.98 ? 1 : 0)
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.75)) { t = 1 }
                if !reduceMotion { withAnimation(.easeIn(duration: 1.1)) { fall = 1 } }
            }
        }
    }
}

// MARK: - a look at another place (the contents, while riding)

/// A row of the contents tapped on the road screen: that place's opening lines, with ▶ to read from there. The
/// reading place stays where it is until ▶ is pressed.
struct RidePeek: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let offset: Int
    var onJump: (Int, Bool?) -> Void

    var body: some View {
        let p = model.player
        let end = min(p.length, offset + 700)
        let text = p.excerptWord(NSRange(location: offset, length: max(0, end - offset)))
        VStack(alignment: .leading, spacing: 16) {
            Text(p.chapterTitle(at: offset) ?? "Bu yer").font(Ride.serif(22, .semibold)).foregroundStyle(Ride.paper)
            ScrollView {
                Text(text + (end < p.length ? "…" : "")).font(Ride.serif(18)).lineSpacing(5).foregroundStyle(Ride.paper.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 10) {
                Button { dismiss() } label: {
                    Text("Kaldığım yerde kal").frame(maxWidth: .infinity, minHeight: 52)
                        .background(Ride.raise, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                Button { onJump(offset, true); dismiss() } label: {
                    Label("Buradan oku", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(Ride.amber)
                        .background(Ride.day ? Ride.raise : Color(red: 0.169, green: 0.129, blue: 0.086), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Ride.amber, lineWidth: 1))
                }
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Ride.paper)
            .buttonStyle(.plain)
        }
        .padding(20)
        .presentationDetents([.medium, .large])
        .presentationBackground(Ride.panel)
        .preferredColorScheme(Ride.day ? .light : .dark)
    }
}
