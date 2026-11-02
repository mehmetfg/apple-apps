// The device's voices, grouped by language, best quality first. Voice Reader also uses the voices iOS provides
// (including downloaded Premium / Enhanced voices and the user's Personal Voice); it ships no voices of its own.
import AVFoundation

enum Voices {
    /// The installed voices, read once and kept: `speechVoices()` walks every voice on the phone (tens of ms), and the
    /// settings screens asked for it on every redraw, which is what made them stiff while reading. Refreshed when iOS
    /// says the voices changed (a download, a deletion).
    private static let cache = VoiceCache()

    static func installed() -> [AVSpeechSynthesisVoice] { cache.voices }
    static func voice(_ id: String) -> AVSpeechSynthesisVoice? { id.isEmpty ? nil : cache.byID[id] }

    static func all() -> [AVSpeechSynthesisVoice] { cache.sorted }

    /// Language codes ("tr", "en"…) that have at least one voice, with the given language first.
    static func languages(first: String?) -> [String] {
        var seen: [String] = []
        for v in all() {
            let l = base(v.language)
            if !seen.contains(l) { seen.append(l) }
        }
        seen.sort { languageName($0).localizedCompare(languageName($1)) == .orderedAscending }
        if let f = first.map(base), let i = seen.firstIndex(of: f) { seen.remove(at: i); seen.insert(f, at: 0) }
        return seen
    }

    static func voices(for language: String) -> [AVSpeechSynthesisVoice] {
        let l = base(language)
        return all().filter { base($0.language) == l }
    }

    /// The voice to use for a language: the one picked in settings, else the best installed one.
    static func defaultVoice(for language: String?, chosen: [String: String]) -> AVSpeechSynthesisVoice? {
        let l = base(language ?? AVSpeechSynthesisVoice.currentLanguageCode())
        if let id = chosen[l], let v = voice(id) { return v }
        let regional = voices(for: l)
        // prefer the main region (tr-TR, en-US) among equal quality
        return regional.first { $0.quality == regional.first?.quality && $0.language.lowercased() == preferredRegion(l) } ?? regional.first
    }

    static func base(_ code: String) -> String { String(code.split(separator: "-").first ?? Substring(code)).lowercased() }

    private static func preferredRegion(_ l: String) -> String {
        ["tr": "tr-tr", "en": "en-us", "de": "de-de", "fr": "fr-fr", "es": "es-es", "ar": "ar-sa"][l] ?? l
    }

    static func languageName(_ code: String) -> String {
        Locale(identifier: "tr").localizedString(forLanguageCode: code)?.localizedCapitalized ?? code
    }

    static func qualityName(_ v: AVSpeechSynthesisVoice) -> String? {
        switch v.quality {
        case .premium: "Premium"
        case .enhanced: "Gelişmiş"
        default: v.voiceTraits.contains(.isPersonalVoice) ? "Kişisel Ses" : nil
        }
    }

    static func regionName(_ v: AVSpeechSynthesisVoice) -> String {
        let parts = v.language.split(separator: "-")
        guard parts.count > 1 else { return "" }
        return Locale(identifier: "tr").localizedString(forRegionCode: String(parts[1])) ?? String(parts[1])
    }
}

private final class VoiceCache: @unchecked Sendable {
    private let lock = NSLock()
    private var loaded: (all: [AVSpeechSynthesisVoice], sorted: [AVSpeechSynthesisVoice], byID: [String: AVSpeechSynthesisVoice])?
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: AVSpeechSynthesizer.availableVoicesDidChangeNotification,
                                                          object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.lock.lock(); self.loaded = nil; self.lock.unlock()
        }
    }

    private func load() -> (all: [AVSpeechSynthesisVoice], sorted: [AVSpeechSynthesisVoice], byID: [String: AVSpeechSynthesisVoice]) {
        lock.lock(); defer { lock.unlock() }
        if let loaded { return loaded }
        let all = AVSpeechSynthesisVoice.speechVoices()
        let sorted = all.filter { !$0.voiceTraits.contains(.isNoveltyVoice) }
            .sorted { ($0.quality.rawValue, $0.name) > ($1.quality.rawValue, $1.name) }
        var byID: [String: AVSpeechSynthesisVoice] = [:]
        for v in all { byID[v.identifier] = v }
        let l = (all, sorted, byID)
        loaded = l
        return l
    }
    var voices: [AVSpeechSynthesisVoice] { load().all }
    var sorted: [AVSpeechSynthesisVoice] { load().sorted }
    var byID: [String: AVSpeechSynthesisVoice] { load().byID }
}
