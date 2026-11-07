// "Cümle cümle" widget: build the sentence yourself (record), copy an AI prompt about it.
// Compiled in the app and in the widget extension. Recording intents run in the APP's process
// (AudioRecordingIntent + LiveActivityIntent, the same pattern as Kıvılcım): the extension cannot open the microphone.
// Recordings: App Group kurma/<day>-<sentence>-iphone-<id>.m4a + .json → the app copies them to the vault
// (oncalisma/paket/gun-NNN/kurma/) for later evaluation.
// Fading ladder: each good attempt hides more of the sentence in the widget (full → gaps → first letters → Turkish only).
import Foundation
import AppIntents
import ActivityKit
import WidgetKit
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Live Activity (iOS requires one while recording from a widget)

struct RebuildActivity: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var start: Date
        var done = false
        var ratio: Double?
        var missed: [String] = []
    }
    var day: Int
    var index: Int
    var tr: String
}

// MARK: - Shared state (App Group defaults)

/// One attempt's summary, shown in the widget.
struct RebuildAttempt: Codable, Hashable {
    var day: Int
    var index: Int
    var date: Date
    var seconds: Double
    var ratio: Double?          // nil: speech recognition was not available
    var missed: [String]
    var heard: String?
}

enum RebuildState {
    static let activeKey = "w.kurma.aktif"           // "day-index" while recording
    static let activeStartKey = "w.kurma.t"          // when that recording began (the widget's timer)
    static let errorKey = "w.kurma.hata"
    static let attemptsKey = "w.kurma.son"           // [day-index: RebuildAttempt]
    static let rungKey = "w.kurma.basamak"           // [day-index: Int]
    static let revealKey = "w.kurma.goster"          // "day-index" while the full sentence is shown
    static let copyDateKey = "w.kopya.t"
    static let tavan: TimeInterval = 30
    static let rungs = 4                             // 0 full · 1 gaps · 2 first letters · 3 Turkish only

    static var d: UserDefaults { Paylasim.ayar }
    static func key(_ day: Int, _ index: Int) -> String { "\(day)-\(index)" }

    static var active: String? { d.string(forKey: activeKey) }
    static func isRecording(_ day: Int, _ index: Int) -> Bool { active == key(day, index) }
    static var activeStart: Date? { d.object(forKey: activeStartKey) as? Date }

    static func attempt(_ day: Int, _ index: Int) -> RebuildAttempt? { attempts()[key(day, index)] }

    /// Every stored attempt, by "day-index". Decoded once per stored value: a list that asks for each row's
    /// attempt (Oku) does not decode the whole table again for every row and every redraw.
    static func attempts() -> [String: RebuildAttempt] {
        guard let v = d.data(forKey: attemptsKey) else { return [:] }
        attemptsLock.lock(); defer { attemptsLock.unlock() }
        if v != attemptsData {
            attemptsCache = (try? JSONDecoder().decode([String: RebuildAttempt].self, from: v)) ?? [:]
            attemptsData = v
        }
        return attemptsCache
    }
    private static let attemptsLock = NSLock()
    private static var attemptsData: Data?
    private static var attemptsCache: [String: RebuildAttempt] = [:]
    static func save(_ a: RebuildAttempt) {
        var all = (d.data(forKey: attemptsKey)).flatMap { try? JSONDecoder().decode([String: RebuildAttempt].self, from: $0) } ?? [:]
        all[key(a.day, a.index)] = a
        // keep only the last 7 days
        let minDay = a.day - 7
        all = all.filter { $0.value.day >= minDay }
        if let v = try? JSONEncoder().encode(all) { d.set(v, forKey: attemptsKey) }
    }

    static func rung(_ day: Int, _ index: Int) -> Int {
        (d.dictionary(forKey: rungKey)?[key(day, index)] as? Int) ?? 0
    }
    /// Good attempt (≥ 85 %) → one rung up; weak attempt (< 60 %) → one rung down. No streaks, no debt.
    static func step(_ day: Int, _ index: Int, ratio: Double?) {
        guard let r = ratio else { return }
        var all = d.dictionary(forKey: rungKey) ?? [:]
        let now = (all[key(day, index)] as? Int) ?? 0
        let next = r >= 0.85 ? min(rungs - 1, now + 1) : r < 0.6 ? max(0, now - 1) : now
        all[key(day, index)] = next
        d.set(all, forKey: rungKey)
    }
    static func setRung(_ day: Int, _ index: Int, _ value: Int) {
        var all = d.dictionary(forKey: rungKey) ?? [:]
        all[key(day, index)] = max(0, min(rungs - 1, value))
        d.set(all, forKey: rungKey)
    }
    static func isRevealed(_ day: Int, _ index: Int) -> Bool { d.string(forKey: revealKey) == key(day, index) }

    // Manual hide ("let me think"): independent of the ladder; per sentence, until you show it again.
    static let hiddenKey = "w.kurma.gizli"
    static func isHidden(_ day: Int, _ index: Int) -> Bool { (d.stringArray(forKey: hiddenKey) ?? []).contains(key(day, index)) }
    static func setHidden(_ day: Int, _ index: Int, _ on: Bool) {
        var all = (d.stringArray(forKey: hiddenKey) ?? []).filter { $0 != key(day, index) }
        if on { all.append(key(day, index)) }
        d.set(Array(all.suffix(40)), forKey: hiddenKey)
    }
    /// Is the English text covered right now (ladder or manual hide), before a peek?
    static func isCovered(_ day: Int, _ index: Int) -> Bool { isHidden(day, index) || rung(day, index) >= rungs - 1 }

    static var recentCopy: Bool {
        guard let t = d.object(forKey: copyDateKey) as? Date else { return false }
        return Date().timeIntervalSince(t) < 6
    }

    static var folder: URL {
        let u = Paylasim.kapsayici.appendingPathComponent("kurma", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static func reload() { WidgetCenter.shared.reloadTimelines(ofKind: Paylasim.sentenceKind) }
}

// MARK: - Fading ladder text

enum Fade {
    /// The sentence at a rung. 1: every third word becomes a gap; 2: only first letters; 3: nil (Turkish only).
    static func text(_ en: String, rung: Int) -> String? {
        switch rung {
        case 0: return en
        case 1:
            var n = 0
            return words(en) { w in n += 1; return n % 3 == 0 ? String(repeating: "_", count: min(w.count, 6)) : w }
        case 2:
            return words(en) { w in String(w.prefix(1)) + String(repeating: "·", count: max(0, min(w.count - 1, 5))) }
        default: return nil
        }
    }

    /// Maps each run of letters; punctuation and spaces stay.
    private static func words(_ s: String, _ f: (String) -> String) -> String {
        var out = "", cur = ""
        for c in s {
            if c.isLetter || c == "'" || c == "’" { cur.append(c) }
            else { if !cur.isEmpty { out += f(cur); cur = "" }; out.append(c) }
        }
        if !cur.isEmpty { out += f(cur) }
        return out
    }

    static func label(_ rung: Int) -> String {
        ["Tam metin", "Boşluklu", "Baş harfler", "Yalnız Türkçe"][max(0, min(3, rung))]
    }
}

// MARK: - Diagnostics (App Group diagnose.log, last 200 lines; read with devicectl or simctl)

enum Diagnose {
    static func write(_ line: String) {
        let u = Paylasim.kapsayici.appendingPathComponent("diagnose.log")
        let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm:ss"
        let who = Bundle.main.bundleIdentifier?.hasSuffix(".widget") == true ? "widget" : "app"
        var old = (try? String(contentsOf: u, encoding: .utf8)) ?? ""
        let lines = old.split(separator: "\n")
        if lines.count > 200 { old = lines.suffix(150).joined(separator: "\n") + "\n" }
        try? (old + "[\(f.string(from: Date()))] [\(who)] \(line)\n").write(to: u, atomically: true, encoding: .utf8)
    }
}

// MARK: - AI prompt

enum SentencePrompt {
    static func text(en: String, tr: String?) -> String {
        """
        Bir İngilizce öğrencisiyim (B1–B2). Aşağıdaki cümleyi yapısal olarak incele ve bana bu kalıbı içselleştirmem için yardım et.

        Cümle: "\(en)"\(tr.map { "\nTürkçesi: \"\($0)\"" } ?? "")

        1. Parçalarına ayır: özne, yüklem, nesne, tümleçler, yan cümleler (clause) ve söz öbekleri (phrase). Her parçanın cümledeki işlevini bir satırda yaz.
        2. Kullanılan dilbilgisi yapılarını adlandır (zaman, edat, kalıp, bağlaç) ve yazarın neden bunları seçtiğini kısaca açıkla.
        3. Aynı yapıyla 5 yeni örnek cümle kur: gündelik hayattan, B1–B2 kelimelerle, her birinin Türkçesiyle.
        4. Türkçe konuşanların bu yapıda yaptığı en sık 2 hatayı göster (✗ yanlış → ✓ doğru).
        5. Bana kalıbı kullanarak çevirmem için 3 Türkçe cümle ver. Cevaplarını en sona, "Cevaplar" başlığıyla ayrı koy; ben önce deneyeceğim.

        Kısa ve net yaz, uzun teori anlatma.
        """
    }
}

// MARK: - Intents

/// Widget mic button: starts recording the sentence; tapped again, it stops. The app is not opened.
struct RebuildSentence: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Cümleyi kendin kur"
    static let description = IntentDescription("Cümleyi kendi sesinle kurarsın; kayıt değerlendirme için saklanır.")
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Gün") var day: Int
    @Parameter(title: "Cümle") var index: Int

    init() {}
    init(day: Int, index: Int) { self.day = day; self.index = index }

    func perform() async throws -> some IntentResult {
        #if !WIDGET
        await SentenceRecorder.shared.toggle(day: day, index: index)
        #endif
        return .result()
    }
}

struct StopRebuild: LiveActivityIntent {
    static let title: LocalizedStringResource = "Kaydı bitir"
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    func perform() async throws -> some IntentResult {
        #if !WIDGET
        await SentenceRecorder.shared.stop()
        #endif
        return .result()
    }
}

/// Widget's ✨ YZ istemi: opens the app and copies the AI prompt there. A background pasteboard write from a widget
/// intent never stuck on the phone (diagnose.log, 28–30 Oct: every background copy FAILED, every in-app copy OK),
/// so the one reliable path is the only one left. The app shows "İstem panoda" and opens the sentence in Oku.
struct CopyPrompt: AppIntent {
    static let title: LocalizedStringResource = "YZ istemini kopyala"
    static let description = IntentDescription("Cümleyi yapısal inceleme istemiyle panoya alır (uygulamayı açar).")
    static let openAppWhenRun = true
    @Parameter(title: "Cümle") var index: Int
    init() {}
    init(index: Int) { self.index = index }
    func perform() async throws -> some IntentResult {
        let ok = await PasteboardCopy.prompt(index: index)
        Diagnose.write("copy-prompt #\(index) → \(ok ? "OK" : "FAILED")")
        RebuildState.reload()
        return .result()
    }
}

enum PasteboardCopy {
    /// Posted after a copy in the app (object: the confirmation text), so the app can show a short banner.
    static let copied = Notification.Name("memories.copied")

    /// Writes the text; changeCount (not a read-back, which iOS may block) tells whether the write landed.
    @MainActor @discardableResult static func write(_ text: String, note: String) -> Bool {
        #if canImport(UIKit)
        let before = UIPasteboard.general.changeCount
        UIPasteboard.general.string = text
        let ok = UIPasteboard.general.changeCount != before
        #else
        let ok = false
        #endif
        if ok {
            RebuildState.d.set(Date(), forKey: RebuildState.copyDateKey)
            NotificationCenter.default.post(name: copied, object: note)
        }
        return ok
    }

    @MainActor static func prompt(index: Int) -> Bool {
        guard let s = Paylasim.oku()?.sentences?.first(where: { $0.i == index }) else { return false }
        NotificationCenter.default.post(name: openSentence, object: index)
        return write(SentencePrompt.text(en: s.en, tr: s.tr), note: "YZ istemi panoda · bir YZ uygulamasına yapıştır")
    }

    /// Posted when the widget's prompt button opened the app: Oku scrolls to that sentence.
    static let openSentence = Notification.Name("memories.openSentence")
}

/// Eye button, always there: hides the English so you can think; tapped again, shows it. If the ladder already hides
/// the text, it peeks at the full sentence instead (tap again to cover it).
struct RevealSentence: AppIntent {
    static let title: LocalizedStringResource = "Cümleyi gizle / göster"
    @Parameter(title: "Gün") var day: Int
    @Parameter(title: "Cümle") var index: Int
    init() {}
    init(day: Int, index: Int) { self.day = day; self.index = index }
    func perform() async throws -> some IntentResult {
        let k = RebuildState.key(day, index)
        let st = RebuildState.self
        if st.isRevealed(day, index) {                       // peeking → cover again
            st.d.removeObject(forKey: st.revealKey)
        } else if st.isHidden(day, index) {                  // manually hidden → show
            st.setHidden(day, index, false)
        } else if st.rung(day, index) > 0 {                  // faded by the ladder → peek at the full text
            st.d.set(k, forKey: st.revealKey)
        } else {                                             // fully visible → hide to think
            st.setHidden(day, index, true)
        }
        st.reload()
        return .result()
    }
}

/// Rung dots: tap to step the ladder by hand (wraps around).
struct StepRung: AppIntent {
    static let title: LocalizedStringResource = "Gizleme basamağını değiştir"
    @Parameter(title: "Gün") var day: Int
    @Parameter(title: "Cümle") var index: Int
    init() {}
    init(day: Int, index: Int) { self.day = day; self.index = index }
    func perform() async throws -> some IntentResult {
        RebuildState.setRung(day, index, (RebuildState.rung(day, index) + 1) % RebuildState.rungs)
        RebuildState.d.removeObject(forKey: RebuildState.revealKey)
        RebuildState.reload()
        return .result()
    }
}

/// Word chip: reads the word with the device voice; the app is not opened.
struct SpeakWord: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Kelimeyi seslendir"
    @Parameter(title: "Kelime") var word: String
    init() {}
    init(word: String) { self.word = word }
    func perform() async throws -> some IntentResult {
        await SentencePlayer.shared.say(word)
        return .result()
    }
}
