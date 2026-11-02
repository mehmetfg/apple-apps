// Reading and listening preferences, kept in UserDefaults. Grouped like Voice Dream's two panels:
// Visual Settings (text, colours, highlighting, scrolling) and Audio Settings (speed, voice, advanced).
import SwiftUI
import Observation

enum NavigationUnit: String, CaseIterable, Identifiable, Sendable {
    case sentence, paragraph, page, chapter, bookmark, highlight, seconds15, seconds30
    var id: String { rawValue }
    var name: String {
        switch self {
        case .sentence: "Cümle"
        case .paragraph: "Paragraf"
        case .page: "Sayfa"
        case .chapter: "Bölüm"
        case .bookmark: "Yer imi"
        case .highlight: "İşaret"
        case .seconds15: "15 saniye"
        case .seconds30: "30 saniye"
        }
    }
    var symbol: String {
        switch self {
        case .sentence: "text.alignleft"
        case .paragraph: "paragraphsign"
        case .page: "doc"
        case .chapter: "list.bullet.indent"
        case .bookmark: "bookmark"
        case .highlight: "highlighter"
        case .seconds15: "15.circle"
        case .seconds30: "30.circle"
        }
    }
}

/// How reading sits with music from another app (Spotify, Apple Music…): off stops the music; otherwise the music
/// plays under the voice and its amount is set with Settings.musicLevel. (`duck` is kept only so an old saved value
/// still reads as "with music".)
/// A system voice's own pitch and volume (Voice Dream's Kalınlık and Ses Miktarı).
struct VoiceTune: Equatable, Sendable {
    var pitch: Double = 1        // 0.5 … 2.0 (shown as 50 … 200)
    var volume: Double = 1       // 0 … 1 (shown as 0 … 100)
    var steady: Double = 0       // 0 … 0.5: how much narrower the melody is made (0 = the voice's own)
}

enum MusicMix: String, CaseIterable, Identifiable, Sendable {
    case off, duck, mix
    var id: String { rawValue }
    var name: String { self == .off ? "Kapalı (müziği durdurur)" : "Müzik arka planda" }
    /// The two choices shown (duck and mix read the same now).
    static let shown: [MusicMix] = [.off, .mix]
}

enum EndBehavior: String, CaseIterable, Identifiable, Sendable {
    case stopAtEnd, keepGoing           // no "repeat": a finished book never goes back to its start by itself
    var id: String { rawValue }
    var name: String {
        switch self {
        case .stopAtEnd: "Belgenin sonunda dur"
        case .keepGoing: "Sonraki bitmemiş belgeye geç"
        }
    }
}

enum ReaderTheme: String, CaseIterable, Identifiable, Sendable {
    case light, sepia, dark, black
    var id: String { rawValue }
    var name: String {
        switch self {
        case .light: "Açık"
        case .sepia: "Sepya"
        case .dark: "Koyu"
        case .black: "Siyah"
        }
    }
    var isDark: Bool { self == .dark || self == .black }
    /// The page.
    var background: UIColor {
        switch self {
        case .light: UIColor(white: 0.941, alpha: 1)                                          // #F0F0F0 (Voice Dream)
        case .sepia: UIColor(red: 0.953, green: 0.914, blue: 0.824, alpha: 1)
        case .dark: UIColor(red: 0.110, green: 0.114, blue: 0.125, alpha: 1)
        case .black: .black
        }
    }
    var text: UIColor {
        switch self {
        case .light: UIColor(white: 0.06, alpha: 1)
        case .sepia: UIColor(red: 0.255, green: 0.190, blue: 0.133, alpha: 1)
        case .dark, .black: UIColor(white: 0.88, alpha: 1)
        }
    }
    /// The top and bottom bars.
    var chrome: UIColor {
        switch self {
        case .light: UIColor(white: 0.965, alpha: 1)                                          // #F6F6F6
        case .sepia: UIColor(red: 0.925, green: 0.878, blue: 0.776, alpha: 1)
        case .dark: UIColor(red: 0.145, green: 0.150, blue: 0.165, alpha: 1)
        case .black: UIColor(white: 0.055, alpha: 1)
        }
    }
    /// The band under the line being read.
    var band: UIColor {
        switch self {
        case .light: .white
        case .sepia: UIColor(red: 0.988, green: 0.965, blue: 0.898, alpha: 1)
        case .dark: UIColor(red: 0.200, green: 0.208, blue: 0.228, alpha: 1)
        case .black: UIColor(white: 0.13, alpha: 1)
        }
    }
    var hairline: UIColor {
        switch self {
        case .light: UIColor(white: 0.63, alpha: 1)                                           // #A0A0A0
        case .sepia: UIColor(red: 0.78, green: 0.72, blue: 0.59, alpha: 1)
        case .dark, .black: UIColor(white: 1, alpha: 0.18)
        }
    }
}

enum ReaderFont: String, CaseIterable, Identifiable, Sendable {
    case system, newYork, georgia, charter, palatino, avenir, helvetica, verdana
    var id: String { rawValue }
    var name: String {
        switch self {
        case .system: "San Francisco"
        case .newYork: "New York"
        case .georgia: "Georgia"
        case .charter: "Charter"
        case .palatino: "Palatino"
        case .avenir: "Avenir Next"
        case .helvetica: "Helvetica Neue"
        case .verdana: "Verdana"
        }
    }
    func font(size: CGFloat) -> UIFont {
        switch self {
        case .system: return .systemFont(ofSize: size)
        case .newYork:
            let d = UIFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif)
            return d.map { UIFont(descriptor: $0, size: size) } ?? .systemFont(ofSize: size)
        case .georgia: return UIFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size)
        case .charter: return UIFont(name: "Charter-Roman", size: size) ?? .systemFont(ofSize: size)
        case .palatino: return UIFont(name: "Palatino-Roman", size: size) ?? .systemFont(ofSize: size)
        case .avenir: return UIFont(name: "AvenirNext-Regular", size: size) ?? .systemFont(ofSize: size)
        case .helvetica: return UIFont(name: "HelveticaNeue", size: size) ?? .systemFont(ofSize: size)
        case .verdana: return UIFont(name: "Verdana", size: size) ?? .systemFont(ofSize: size)
        }
    }
}

/// The colours offered for the spoken word, the spoken line and selections.
enum MarkColor: String, CaseIterable, Identifiable, Sendable {
    case paper, yellow, orange, green, blue, purple, pink, gray
    var id: String { rawValue }
    var name: String {
        switch self {
        case .paper: "Beyaz"
        case .yellow: "Sarı"
        case .orange: "Turuncu"
        case .green: "Yeşil"
        case .blue: "Mavi"
        case .purple: "Mor"
        case .pink: "Pembe"
        case .gray: "Gri"
        }
    }
    var uiColor: UIColor {
        switch self {
        case .paper: .white
        case .yellow: UIColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 1)                     // pure yellow, as in Voice Dream
        case .orange: UIColor(red: 1.00, green: 0.62, blue: 0.25, alpha: 1)
        case .green: UIColor(red: 0.40, green: 0.85, blue: 0.45, alpha: 1)
        case .blue: UIColor(red: 0.16, green: 0.38, blue: 0.95, alpha: 1)
        case .purple: UIColor(red: 0.70, green: 0.50, blue: 1.00, alpha: 1)
        case .pink: UIColor(red: 1.00, green: 0.50, blue: 0.70, alpha: 1)
        case .gray: UIColor(white: 0.6, alpha: 1)
        }
    }
}

extension HighlightColor {
    var uiColor: UIColor {
        switch self {
        case .yellow: UIColor(red: 1.00, green: 0.86, blue: 0.25, alpha: 1)
        case .blue: UIColor(red: 0.45, green: 0.68, blue: 1.00, alpha: 1)
        case .red: UIColor(red: 1.00, green: 0.45, blue: 0.45, alpha: 1)
        case .green: UIColor(red: 0.45, green: 0.86, blue: 0.50, alpha: 1)
        }
    }
    var color: Color { Color(uiColor: uiColor) }
}

enum CursorPosition: String, CaseIterable, Identifiable, Sendable {
    case top, middle
    var id: String { rawValue }
    var name: String { self == .top ? "Üstte" : "Ortada" }
    var fraction: CGFloat { self == .top ? 0.25 : 0.45 }
}

enum SortOrder: String, CaseIterable, Identifiable, Sendable {
    case lastOpened, addDate, title, author, duration, progress
    var id: String { rawValue }
    var name: String {
        switch self {
        case .lastOpened: "Son açılan"
        case .addDate: "Eklenme tarihi"
        case .title: "Başlık"
        case .author: "Yazar"
        case .duration: "Süre"
        case .progress: "İlerleme"
        }
    }
}

enum LibraryStyle: String, CaseIterable, Identifiable, Sendable {
    case spines, shelf, grid, list
    var id: String { rawValue }
    var name: String {
        switch self {
        case .spines: "Kitaplık"
        case .shelf: "Vitrin"
        case .grid: "Izgara"
        case .list: "Liste"
        }
    }
    var symbol: String {
        switch self {
        case .spines: "books.vertical.fill"
        case .shelf: "books.vertical"
        case .grid: "square.grid.3x3"
        case .list: "list.bullet"
        }
    }
}

enum LibraryFilter: String, CaseIterable, Identifiable, Sendable {
    case all, unread, inProgress, finished, flagged
    var id: String { rawValue }
    var name: String {
        switch self {
        case .all: "Tümü"
        case .unread: "Okunmamış"
        case .inProgress: "Devam eden"
        case .finished: "Biten"
        case .flagged: "Etiketli"
        }
    }
}

@MainActor
@Observable
final class Settings {
    @ObservationIgnored private let d = UserDefaults.standard

    // visual
    var font: ReaderFont { didSet { d.set(font.rawValue, forKey: "v.font") } }
    var fontSize: Double { didSet { d.set(fontSize, forKey: "v.size") } }
    var lineSpacing: Double { didSet { d.set(lineSpacing, forKey: "v.line") } }
    var characterSpacing: Double { didSet { d.set(characterSpacing, forKey: "v.kern") } }
    /// Page colours: Açık / Sepya / Koyu / Siyah, or the phone's own light/dark when `followSystem` is on.
    var theme: ReaderTheme { didSet { d.set(theme.rawValue, forKey: "v.theme2") } }
    var followSystem: Bool { didSet { d.set(followSystem, forKey: "v.followSystem") } }
    /// The accent colour (hex, no #): bars, icons, progress, switches.
    var accentHex: String { didSet { d.set(accentHex, forKey: "v.accent") } }
    var showSpokenWord: Bool { didSet { d.set(showSpokenWord, forKey: "v.word") } }
    var showSpokenLine: Bool { didSet { d.set(showSpokenLine, forKey: "v.lineHL") } }
    var wordColor: MarkColor { didSet { d.set(wordColor.rawValue, forKey: "v.wordColor") } }
    var lineColor: MarkColor { didSet { d.set(lineColor.rawValue, forKey: "v.lineColor") } }
    var cursorPosition: CursorPosition { didSet { d.set(cursorPosition.rawValue, forKey: "v.cursor") } }
    var focusMode: Bool { didSet { d.set(focusMode, forKey: "v.focus") } }
    /// Bicycle mode: big text that follows the voice, three big buttons, headphone ⏭ = mark, ⏮ = voice note.
    var bikeMode: Bool { didSet { d.set(bikeMode, forKey: "v.bike") } }
    /// The moving mode in use while `bikeMode` is on: on a bicycle or on foot (the same screens, its own record).
    var moveKind: MoveKind { didSet { d.set(moveKind.rawValue, forKey: "v.moveKind") } }
    /// Body weight in kg for the calories; 0 = not given yet (75 is assumed and the screen asks).
    var bodyWeight: Double { didSet { d.set(bodyWeight, forKey: "v.weight") } }
    /// Müzik modu hears the beat through the microphone (music from the speaker); off = the tapped tempo only.
    var musicMic: Bool { didSet { d.set(musicMic, forKey: "v.musicMic") } }
    /// Müzik modu's lettering: true = Kinetik (phrases as compositions), false = Akış (words flowing into lines).
    var musicKinetic: Bool { didSet { d.set(musicKinetic, forKey: "v.musicKinetic") } }
    /// Müzik modu's background: glow · black · circle · dusk (see MusicBackdrop).
    var musicBackdrop: String { didSet { d.set(musicBackdrop, forKey: "v.musicBackdrop") } }
    var bikeStyle: BikeStyle { didSet { d.set(bikeStyle.rawValue, forKey: "v.bikeStyle") } }
    /// The moving mode's screen: Yolda (dark, the last sentences), Kinetik (the heard words set kinetically), Tam metin
    /// (the ordinary reader, the GPS record goes on) or Klasik (the page with the three glass keys).
    var bikeLook: BikeLook { didSet { d.set(bikeLook.rawValue, forKey: "v.bikeLook") } }
    /// Müzik modu's content: the book's sentences on the beat · only the rhythm, no text · the book read aloud, its
    /// words set kinetically as they are heard (see MusicContent).
    var musicContent: String { didSet { d.set(musicContent, forKey: "v.musicContent") } }
    /// An active wait or a music break opens Müzik modu (rhythm only) and closes it when reading goes on.
    var musicOnPause: Bool { didSet { d.set(musicOnPause, forKey: "v.musicOnPause") } }
    var bookLayout: Bool { didSet { d.set(bookLayout, forKey: "v.book") } }

    // audio
    var speed: Double { didSet { d.set(speed, forKey: "a.speed") } }
    var voiceByLanguage: [String: String] { didSet { d.set(voiceByLanguage, forKey: "a.voices") } }
    var startAtSentence: Bool { didSet { d.set(startAtSentence, forKey: "a.sentence") } }
    var simplifyLinks: Bool { didSet { d.set(simplifyLinks, forKey: "a.links") } }
    var skipCitations: Bool { didSet { d.set(skipCitations, forKey: "a.citations") } }
    var endBehavior: EndBehavior { didSet { d.set(endBehavior.rawValue, forKey: "a.end") } }
    var navigationUnit: NavigationUnit { didSet { d.set(navigationUnit.rawValue, forKey: "a.unit") } }
    var pitch: Double { didSet { d.set(pitch, forKey: "a.pitch") } }
    /// Read English sentences in a Turkish text (and Turkish in an English one) with that language's voice.
    var mixedLanguage: Bool { didSet { d.set(mixedLanguage, forKey: "a.mixed") } }
    var musicMix: MusicMix { didSet { d.set(musicMix.rawValue, forKey: "a.music") } }
    /// How much background music under the voice, 0 (barely) … 100 (as loud as the voice can allow).
    var musicLevel: Double { didSet { d.set(musicLevel, forKey: "a.musicLevel") } }
    /// iPhone voices through VoiceMaster (clear, full, louder, no crackle); off = as the synthesiser makes them.
    var clearVoice: Bool { didSet { d.set(clearVoice, forKey: "a.clearVoice") } }
    /// Turkish system voices read with the phone's own Spoken Content settings (speed, pitch, equalizer), as iOS
    /// itself reads them. On iOS 27 only this reaches Yelda's old depth: pitchMultiplier 0.5 stops at 181 Hz.
    var systemSpeech: Bool { didSet { d.set(systemSpeech, forKey: "a.systemSpeech") } }
    /// Music break: every `breakMinutes` of listening (3…15) the voice pauses `breakSeconds` (30…120) for the music.
    var musicBreak: Bool { didSet { d.set(musicBreak, forKey: "a.break") } }
    var breakMinutes: Double { didSet { d.set(breakMinutes, forKey: "a.breakMin") } }
    var breakSeconds: Double { didSet { d.set(breakSeconds, forKey: "a.breakSec") } }
    /// Aktif bekleme: the headphone's ⏯ (and the lock screen's pause) while reading waits and then goes on by itself.
    var remotePauseWaits: Bool { didSet { d.set(remotePauseWaits, forKey: "a.waitRemote") } }
    /// The wait's length in seconds; 0 = until the music stops (Spotify paused or ended).
    var waitSeconds: Double { didSet { d.set(waitSeconds, forKey: "a.waitSec") } }
    /// Extra depth per Voice Reader voice, in semitones on top of the voice's own (−3 … +2; negative = deeper).
    var voiceDepth: [String: Double] { didSet { d.set(voiceDepth, forKey: "a.depth") } }
    /// Pitch, volume and steadiness per voice id, stored as [pitch, volume, steady].
    var voiceTune: [String: VoiceTune] {
        didSet { d.set(voiceTune.mapValues { [$0.pitch, $0.volume, $0.steady] }, forKey: "a.tune") }
    }

    // library
    var sortOrder: SortOrder { didSet { d.set(sortOrder.rawValue, forKey: "l.sort") } }
    var filter: LibraryFilter { didSet { d.set(filter.rawValue, forKey: "l.filter") } }
    var style: LibraryStyle { didSet { d.set(style.rawValue, forKey: "l.style") } }
    /// The home page's books: Kitaplık (spines on shelves), a grid of covers or a list.
    var homeStyle: LibraryStyle { didSet { d.set(homeStyle.rawValue, forKey: "l.homeStyle") } }
    /// The home page's shelf: süren · okunacak · bitenler · tümü, or a folder's name.
    var homeShelf: String { didSet { d.set(homeShelf, forKey: "l.homeShelf") } }

    init() {
        let d = UserDefaults.standard
        font = ReaderFont(rawValue: d.string(forKey: "v.font") ?? "") ?? .georgia
        fontSize = d.object(forKey: "v.size") as? Double ?? 20
        lineSpacing = d.object(forKey: "v.line") as? Double ?? 6
        characterSpacing = d.object(forKey: "v.kern") as? Double ?? 0
        // 2026-10-22: one colour scheme (page, bars, band) instead of three overlapping ones (page theme, app colour,
        // light/dark). Once, the look is set to Voice Dream's: light, navy. Both stay changeable in Görsel Ayarlar.
        if !d.bool(forKey: "v.look.20261022") {
            d.set(true, forKey: "v.look.20261022")
            d.set(ReaderTheme.light.rawValue, forKey: "v.theme2")
            d.set(false, forKey: "v.followSystem")
            d.set(Accent.standard.ink, forKey: "v.accent")
            d.set(MarkColor.paper.rawValue, forKey: "v.lineColor")
            d.set(MarkColor.yellow.rawValue, forKey: "v.wordColor")
            for k in ["v.theme", "v.appTheme", "v.appearance", "a.boost", "a.extraLangs"] { d.removeObject(forKey: k) }
        }
        theme = ReaderTheme(rawValue: d.string(forKey: "v.theme2") ?? "") ?? .light
        followSystem = d.bool(forKey: "v.followSystem")
        accentHex = d.string(forKey: "v.accent") ?? Accent.standard.ink
        showSpokenWord = d.object(forKey: "v.word") as? Bool ?? true
        showSpokenLine = d.object(forKey: "v.lineHL") as? Bool ?? true
        // the spoken word is a yellow marker by default (2026-10-20, as in Voice Dream); moved once for existing users
        if !d.bool(forKey: "v.wordColor.yellow") { d.set(true, forKey: "v.wordColor.yellow"); d.set(MarkColor.yellow.rawValue, forKey: "v.wordColor") }
        wordColor = MarkColor(rawValue: d.string(forKey: "v.wordColor") ?? "") ?? .yellow
        lineColor = MarkColor(rawValue: d.string(forKey: "v.lineColor") ?? "") ?? .paper
        cursorPosition = CursorPosition(rawValue: d.string(forKey: "v.cursor") ?? "") ?? .top
        focusMode = d.bool(forKey: "v.focus")
        bikeMode = d.bool(forKey: "v.bike")
        moveKind = MoveKind(rawValue: d.string(forKey: "v.moveKind") ?? "") ?? .bike
        bodyWeight = d.double(forKey: "v.weight")
        musicMic = d.object(forKey: "v.musicMic") as? Bool ?? true
        musicKinetic = d.object(forKey: "v.musicKinetic") as? Bool ?? true
        musicBackdrop = d.string(forKey: "v.musicBackdrop") ?? "circle"
        bikeStyle = BikeStyle(rawValue: d.string(forKey: "v.bikeStyle") ?? "") ?? .crystal
        bikeLook = BikeLook(rawValue: d.string(forKey: "v.bikeLook") ?? "") ?? .focus
        musicContent = d.string(forKey: "v.musicContent") ?? "lines"
        musicOnPause = d.object(forKey: "v.musicOnPause") as? Bool ?? true
        bookLayout = d.object(forKey: "v.book") as? Bool ?? true
        speed = d.object(forKey: "a.speed") as? Double ?? 1.0
        voiceByLanguage = d.dictionary(forKey: "a.voices") as? [String: String] ?? [:]
        startAtSentence = d.object(forKey: "a.sentence") as? Bool ?? true
        simplifyLinks = d.object(forKey: "a.links") as? Bool ?? true
        skipCitations = d.object(forKey: "a.citations") as? Bool ?? true
        endBehavior = EndBehavior(rawValue: d.string(forKey: "a.end") ?? "") ?? .stopAtEnd
        navigationUnit = NavigationUnit(rawValue: d.string(forKey: "a.unit") ?? "") ?? .sentence
        pitch = d.object(forKey: "a.pitch") as? Double ?? 1.0
        mixedLanguage = d.object(forKey: "a.mixed") as? Bool ?? true
        musicMix = MusicMix(rawValue: d.string(forKey: "a.music") ?? "") ?? .off
        musicLevel = d.object(forKey: "a.musicLevel") as? Double ?? 40
        clearVoice = d.object(forKey: "a.clearVoice") as? Bool ?? true
        systemSpeech = d.object(forKey: "a.systemSpeech") as? Bool ?? true
        musicBreak = d.bool(forKey: "a.break")
        breakMinutes = d.object(forKey: "a.breakMin") as? Double ?? 5
        breakSeconds = d.object(forKey: "a.breakSec") as? Double ?? 30
        remotePauseWaits = d.object(forKey: "a.waitRemote") as? Bool ?? true
        waitSeconds = d.object(forKey: "a.waitSec") as? Double ?? 120
        voiceDepth = d.dictionary(forKey: "a.depth") as? [String: Double] ?? [:]
        voiceTune = (d.dictionary(forKey: "a.tune") as? [String: [Double]] ?? [:]).compactMapValues { v in
            v.count >= 2 ? VoiceTune(pitch: v[0], volume: v[1], steady: v.count > 2 ? v[2] : 0) : nil
        }
        sortOrder = SortOrder(rawValue: d.string(forKey: "l.sort") ?? "") ?? .lastOpened
        filter = LibraryFilter(rawValue: d.string(forKey: "l.filter") ?? "") ?? .all
        style = LibraryStyle(rawValue: d.string(forKey: "l.style") ?? "") ?? .shelf
        homeStyle = LibraryStyle(rawValue: d.string(forKey: "l.homeStyle") ?? "") ?? .spines
        homeShelf = d.string(forKey: "l.homeShelf") ?? "all"
    }

    var accent: Accent { Accent(hex: accentHex) }
    /// The theme in effect: the phone's light/dark when following the system, else the chosen one.
    func effectiveTheme(systemDark: Bool) -> ReaderTheme { followSystem ? (systemDark ? .dark : .light) : theme }
    /// For `preferredColorScheme`: nil follows the phone.
    var colorScheme: ColorScheme? { followSystem ? nil : (theme.isDark ? .dark : .light) }

    func restoreVisualDefaults() {
        font = .georgia; fontSize = 20; lineSpacing = 6; characterSpacing = 0; theme = .light; followSystem = false
        accentHex = Accent.standard.ink
        showSpokenWord = true; showSpokenLine = true; wordColor = .yellow; lineColor = .paper
        cursorPosition = .top; focusMode = false; bookLayout = true; bikeStyle = .crystal
    }
}
