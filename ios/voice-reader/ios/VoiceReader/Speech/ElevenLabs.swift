// ElevenLabs: an outside voice for the reader, carried over from Teoria (2026-11-02). The user's own API key (kept in
// the Keychain, never in the code or the vault), a voice and a model; each paragraph is synthesised once with character
// timings, stored on disk, and played by SpeechPlayer's own engine. Speed and level are applied on the device (WSOLA,
// Level), so a stored paragraph serves every speed and listening to it again costs no credits.
//
// API: POST /v1/text-to-speech/{voice}/with-timestamps (audio as base64 + per-character start times),
//      GET /v1/voices, GET /v1/user/subscription (credits used / limit).
import Foundation
import CryptoKit
import Security
import Observation
import AVFoundation

// MARK: Keychain

/// The API key lives only in this device's Keychain: readable after the first unlock (so reading goes on from the lock
/// screen), not synced to iCloud Keychain and not part of backups.
enum KeyVault {
    private static func base(_ service: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "api"]
    }

    static func read(_ service: String = "wisepath.elevenlabs") -> String? {
        var q = base(service)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let d = result as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    @discardableResult
    static func write(_ key: String, service: String = "wisepath.elevenlabs") -> Bool {
        delete(service)
        var q = base(service)
        q[kSecValueData as String] = Data(key.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ service: String = "wisepath.elevenlabs") { SecItemDelete(base(service) as CFDictionary) }
}

// MARK: settings

enum ElevenModel: String, CaseIterable, Identifiable {
    case flash = "eleven_flash_v2_5"
    case turbo = "eleven_turbo_v2_5"
    case multilingual = "eleven_multilingual_v2"
    var id: String { rawValue }
    var name: String {
        switch self {
        case .flash: "Flash v2.5 · hızlı, yarım kredi"
        case .turbo: "Turbo v2.5 · yarım kredi"
        case .multilingual: "Multilingual v2 · en doğal, tam kredi"
        }
    }
    /// Only the v2.5 models accept `language_code`; the others answer with an error when it is sent.
    var forcesLanguage: Bool { self != .multilingual }
}

/// The stored format decides how much a gigabyte of cache holds.
enum ElevenQuality: String, CaseIterable, Identifiable {
    case low = "mp3_22050_32"
    case medium = "mp3_44100_64"
    case high = "mp3_44100_128"
    var id: String { rawValue }
    var kbps: Int { switch self { case .low: 32; case .medium: 64; case .high: 128 } }
    /// Megabytes per hour of speech.
    var megabytesPerHour: Double { Double(kbps) * 1000 / 8 * 3600 / 1_000_000 }
    var name: String { "\(kbps) kbps · saatte ~\(Int(megabytesPerHour.rounded())) MB" }
}

struct ElevenVoice: Identifiable, Hashable, Sendable { let id: String; let name: String; let category: String }

struct ElevenSubscription: Sendable {
    let tier: String
    let used: Int
    let limit: Int
    let resets: Date?
    var left: Int { max(0, limit - used) }
}

// MARK: a synthesised paragraph

struct ElevenWord: Codable, Sendable {
    let location: Int       // UTF-16 offset in the paragraph
    let length: Int
    let seconds: Double     // where the word starts in the audio
}

struct ElevenRecord: Codable, Sendable {
    var words: [ElevenWord]
    var seconds: Double     // length of the audio
    var characters: Int
}

struct ElevenClip: Sendable {
    let file: URL           // an MP3 in the cache
    let record: ElevenRecord
    let fromCache: Bool
}

enum ElevenError: LocalizedError {
    case noKey, noVoice, undecodable
    case server(Int, String)

    var errorDescription: String? {
        switch self {
        case .noKey: return "API anahtarı kayıtlı değil."
        case .noVoice: return "Ses seçilmedi. ElevenLabs ayarlarında Bağlantıyı dene'ye bas."
        case .undecodable: return "Sunucunun gönderdiği ses okunamadı."
        case .server(let code, let m):
            if m.lowercased().contains("quota") { return "Kredi bitti (\(code)). \(m)" }
            switch code {
            case 401: return "Anahtar geçersiz ya da bu işlem için izni yok (401). \(m)"
            case 429: return "Çok sık istek ya da eşzamanlı istek sınırı (429). \(m)"
            default: return "Sunucu hatası \(code). \(m)"
            }
        }
    }
}

// MARK: client

@MainActor
@Observable
final class ElevenLabs {
    static let shared = ElevenLabs()
    /// The voice id the reader stores when ElevenLabs is the chosen voice (the ElevenLabs voice itself is `voiceID`).
    nonisolated static let readerVoiceID = "vr.eleven"
    /// The disk cache limit (shared by every cloud voice), readable off the main actor.
    nonisolated static var cacheLimitBytes: Int { (UserDefaults.standard.object(forKey: "a.eleven.limitMB") as? Int ?? 500) * 1_000_000 }

    private static let root = "https://api.elevenlabs.io"
    @ObservationIgnored private let d = UserDefaults.standard

    var voiceID: String { didSet { d.set(voiceID, forKey: "a.eleven.voice"); changed() } }
    var voiceName: String { didSet { d.set(voiceName, forKey: "a.eleven.voiceName") } }
    var model: ElevenModel { didSet { d.set(model.rawValue, forKey: "a.eleven.model"); changed() } }
    var quality: ElevenQuality { didSet { d.set(quality.rawValue, forKey: "a.eleven.quality"); changed() } }
    /// Cache limit in megabytes; the least recently heard paragraphs go first.
    var limitMB: Int { didSet { d.set(limitMB, forKey: "a.eleven.limitMB"); Task { await pruneAndRefresh() } } }

    private(set) var hasKey = false
    private(set) var voices: [ElevenVoice] = []
    private(set) var subscription: ElevenSubscription?
    var status: String?
    private(set) var stats: CacheStats?
    /// Characters served from the cache (no credits, no network) and from the server (credits spent).
    private(set) var cachedCharacters: Int
    private(set) var networkCharacters: Int

    /// Called when the voice, model or quality changes, so reading picks up the new sound.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var keyInMemory: String?

    /// How the voice is named in the reader: "ElevenLabs · <voice>".
    var displayName: String { voiceName.isEmpty ? "ElevenLabs" : "ElevenLabs · \(voiceName)" }

    /// A key and a voice: the reader can ask ElevenLabs.
    var ready: Bool { hasKey && !voiceID.isEmpty }

    private init() {
        voiceID = d.string(forKey: "a.eleven.voice") ?? ""
        voiceName = d.string(forKey: "a.eleven.voiceName") ?? ""
        model = ElevenModel(rawValue: d.string(forKey: "a.eleven.model") ?? "") ?? .flash
        quality = ElevenQuality(rawValue: d.string(forKey: "a.eleven.quality") ?? "") ?? .medium
        limitMB = d.object(forKey: "a.eleven.limitMB") as? Int ?? 500
        cachedCharacters = d.integer(forKey: "a.eleven.cachedChars")
        networkCharacters = d.integer(forKey: "a.eleven.networkChars")
        keyInMemory = KeyVault.read()
        hasKey = keyInMemory != nil
    }

    private func changed() { onChange?() }

    // MARK: key

    func saveKey(_ raw: String) {
        let k = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return }
        if KeyVault.write(k) {
            keyInMemory = k; hasKey = true
            status = "Anahtar Keychain'e kaydedildi."
        } else {
            status = "Anahtar kaydedilemedi."
        }
        changed()
    }

    func deleteKey() {
        KeyVault.delete()
        keyInMemory = nil; hasKey = false
        voices = []; subscription = nil
        status = "Anahtar silindi."
        changed()
    }

    private func key() -> String? {
        if keyInMemory == nil { keyInMemory = KeyVault.read() }    // before the first unlock the read fails
        return keyInMemory
    }

    // MARK: account

    /// Check the key: fetch the voices (picks the first if none is chosen) and the credits.
    func test() async {
        guard let k = key() else { status = ElevenError.noKey.errorDescription; return }
        status = "Bağlanıyor…"
        do {
            voices = try await fetchVoices(k)
            if voiceID.isEmpty, let first = voices.first { voiceID = first.id; voiceName = first.name }
            status = "Bağlantı tamam · \(voices.count) ses"
        } catch {
            status = error.localizedDescription
            return
        }
        do {
            subscription = try await fetchSubscription(k)
        } catch {
            subscription = nil
            status = (status ?? "") + " · kota okunamadı (anahtarın User okuma izni kapalı olabilir)"
        }
    }

    func choose(_ id: String) {
        voiceName = voices.first(where: { $0.id == id })?.name ?? voiceName
        voiceID = id
    }

    private func fetchVoices(_ k: String) async throws -> [ElevenVoice] {
        struct Answer: Decodable {
            struct V: Decodable { let voice_id: String; let name: String; let category: String? }
            let voices: [V]
        }
        let data = try await request("/v1/voices", key: k)
        return try JSONDecoder().decode(Answer.self, from: data).voices
            .map { ElevenVoice(id: $0.voice_id, name: $0.name, category: $0.category ?? "") }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func fetchSubscription(_ k: String) async throws -> ElevenSubscription {
        struct Answer: Decodable {
            let tier: String?
            let character_count: Int
            let character_limit: Int
            let next_character_count_reset_unix: Double?
        }
        let a = try JSONDecoder().decode(Answer.self, from: try await request("/v1/user/subscription", key: k))
        return ElevenSubscription(tier: a.tier ?? "?", used: a.character_count, limit: a.character_limit,
                                  resets: a.next_character_count_reset_unix.map { Date(timeIntervalSince1970: $0) })
    }

    // MARK: synthesis

    /// One paragraph: from the cache when it was heard before with the same voice, model and quality; otherwise from
    /// the server, stored for next time.
    func synthesize(_ text: String) async throws -> ElevenClip {
        guard let k = key() else { throw ElevenError.noKey }
        guard !voiceID.isEmpty else { throw ElevenError.noVoice }
        let voice = voiceID, mdl = model, q = quality, limit = Int64(limitMB) * 1_000_000
        let ck = ElevenCache.key(voice: voice, model: mdl.rawValue, quality: q.rawValue, text: text)
        if let clip = await Task.detached(priority: .userInitiated, operation: { ElevenCache.find(ck) }).value {
            count(cached: text.count)
            return clip
        }
        var body: [String: Any] = ["text": text, "model_id": mdl.rawValue]
        if mdl.forcesLanguage { body["language_code"] = "tr" }
        let path = "/v1/text-to-speech/\(voice.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? voice)/with-timestamps"
        let data = try await request(path, query: [URLQueryItem(name: "output_format", value: q.rawValue)],
                                     body: try JSONSerialization.data(withJSONObject: body), key: k)
        let clip = try await Task.detached(priority: .userInitiated) { () throws -> ElevenClip in
            let a = try JSONDecoder().decode(SynthesisAnswer.self, from: data)
            guard let mp3 = Data(base64Encoded: a.audio_base64), !mp3.isEmpty else { throw ElevenError.undecodable }
            return try ElevenCache.write(ck, audio: mp3, record: Self.record(text, a.alignment), limit: limit)
        }.value
        count(network: text.count)
        return clip
    }

    private struct Alignment: Decodable, Sendable {
        let characters: [String]
        let character_start_times_seconds: [Double]
        let character_end_times_seconds: [Double]
    }
    private struct SynthesisAnswer: Decodable, Sendable {
        let audio_base64: String
        let alignment: Alignment?
    }

    /// Character timings → word timings. The characters must spell the paragraph exactly; if they don't (the server
    /// changed the text), no words are kept and the reader follows the paragraph without a word highlight.
    nonisolated private static func record(_ text: String, _ a: Alignment?) -> ElevenRecord {
        let length = text.utf16.count
        guard let a, a.characters.count == a.character_start_times_seconds.count, a.characters.joined() == text else {
            return ElevenRecord(words: [], seconds: a?.character_end_times_seconds.last ?? 0, characters: length)
        }
        var words: [ElevenWord] = []
        var at = 0
        var start: (at: Int, seconds: Double)?
        for (i, c) in a.characters.enumerated() {
            if c.allSatisfy(\.isWhitespace) {
                if let s = start { words.append(ElevenWord(location: s.at, length: at - s.at, seconds: s.seconds)); start = nil }
            } else if start == nil {
                start = (at, a.character_start_times_seconds[i])
            }
            at += c.utf16.count
        }
        if let s = start { words.append(ElevenWord(location: s.at, length: at - s.at, seconds: s.seconds)) }
        return ElevenRecord(words: words, seconds: a.character_end_times_seconds.last ?? 0, characters: length)
    }

    private func request(_ path: String, query: [URLQueryItem] = [], body: Data? = nil, key: String) async throws -> Data {
        var u = URLComponents(string: Self.root)!
        u.percentEncodedPath = path
        if !query.isEmpty { u.queryItems = query }
        var r = URLRequest(url: u.url!)
        r.timeoutInterval = 40
        r.setValue(key, forHTTPHeaderField: "xi-api-key")
        if let body {
            r.httpMethod = "POST"
            r.httpBody = body
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: r)
        guard let h = response as? HTTPURLResponse else { throw ElevenError.undecodable }
        guard (200..<300).contains(h.statusCode) else {
            var m = String(data: data, encoding: .utf8) ?? ""
            if let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let dt = j["detail"] as? [String: Any] { m = (dt["message"] as? String) ?? (dt["status"] as? String) ?? m }
                else if let dt = j["detail"] as? String { m = dt }
            }
            throw ElevenError.server(h.statusCode, String(m.prefix(200)))
        }
        return data
    }

    // MARK: cache numbers

    private func count(cached: Int = 0, network: Int = 0) {
        cachedCharacters += cached; networkCharacters += network
        d.set(cachedCharacters, forKey: "a.eleven.cachedChars")
        d.set(networkCharacters, forKey: "a.eleven.networkChars")
    }

    func refreshStats() async {
        stats = await Task.detached(priority: .utility) { ElevenCache.stats() }.value
    }

    private func pruneAndRefresh() async {
        let s = Int64(limitMB) * 1_000_000
        await Task.detached(priority: .utility) { ElevenCache.prune(s) }.value
        await refreshStats()
    }

    func clearCache() async {
        await Task.detached(priority: .utility) { ElevenCache.clear() }.value
        cachedCharacters = 0; networkCharacters = 0
        count()
        await refreshStats()
    }
}

// MARK: disk cache

struct CacheStats: Sendable {
    let paragraphs: Int
    let bytes: Int64
    let seconds: Double
}

/// Application Support/WisePath/ElevenLabs: <sha256>.mp3 + <sha256>.json per paragraph. Not in Caches, which iOS
/// empties when space runs low, because the point is to listen again offline; excluded from backups.
enum ElevenCache {
    static let folder: URL = {
        var u = URL.applicationSupportDirectory.appending(path: "WisePath/ElevenLabs", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        var v = URLResourceValues()
        v.isExcludedFromBackup = true
        try? u.setResourceValues(v)
        return u
    }()

    static func key(voice: String, model: String, quality: String, text: String) -> String {
        SHA256.hash(data: Data("\(voice)|\(model)|\(quality)|\(text)".utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func find(_ k: String) -> ElevenClip? {
        let mp3 = folder.appending(path: k + ".mp3"), js = folder.appending(path: k + ".json")
        guard FileManager.default.fileExists(atPath: mp3.path),
              let d = try? Data(contentsOf: js), let record = try? JSONDecoder().decode(ElevenRecord.self, from: d) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: mp3.path)   // recently heard
        return ElevenClip(file: mp3, record: record, fromCache: true)
    }

    /// `timing`: for providers without word timings, the words from the audio's measured length (seconds).
    static func write(_ k: String, audio: Data, record: ElevenRecord, limit: Int64,
                      timing: ((Double) -> [ElevenWord])? = nil) throws -> ElevenClip {
        let mp3 = folder.appending(path: k + ".mp3"), js = folder.appending(path: k + ".json")
        try audio.write(to: mp3, options: .atomic)
        var record = record
        if let timing {
            let seconds = (try? AVAudioFile(forReading: mp3)).map { Double($0.length) / $0.processingFormat.sampleRate } ?? 0
            guard seconds > 0 else { try? FileManager.default.removeItem(at: mp3); throw ElevenError.undecodable }
            record.seconds = seconds
            record.words = timing(seconds)
        }
        try JSONEncoder().encode(record).write(to: js, options: .atomic)
        prune(limit, keep: k)
        return ElevenClip(file: mp3, record: record, fromCache: false)
    }

    /// Over the limit: delete the paragraphs heard longest ago (never the one just written).
    static func prune(_ limit: Int64, keep: String? = nil) {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { return }
        var total: Int64 = 0
        var clips: [(name: String, date: Date)] = []
        var sizes: [String: Int64] = [:]
        for u in files {
            let v = try? u.resourceValues(forKeys: Set(keys))
            let size = Int64(v?.fileSize ?? 0)
            total += size
            let name = u.deletingPathExtension().lastPathComponent
            sizes[name, default: 0] += size
            if u.pathExtension == "mp3" { clips.append((name, v?.contentModificationDate ?? .distantPast)) }
        }
        guard total > limit else { return }
        for c in clips.sorted(by: { $0.date < $1.date }) where c.name != keep {
            try? fm.removeItem(at: folder.appending(path: c.name + ".mp3"))
            try? fm.removeItem(at: folder.appending(path: c.name + ".json"))
            total -= sizes[c.name] ?? 0
            if total <= limit { break }
        }
    }

    static func stats() -> CacheStats {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else {
            return CacheStats(paragraphs: 0, bytes: 0, seconds: 0)
        }
        var bytes: Int64 = 0, seconds = 0.0, n = 0
        let dec = JSONDecoder()
        for u in files {
            bytes += Int64((try? u.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            if u.pathExtension == "json", let d = try? Data(contentsOf: u), let r = try? dec.decode(ElevenRecord.self, from: d) {
                seconds += r.seconds; n += 1
            }
        }
        return CacheStats(paragraphs: n, bytes: bytes, seconds: seconds)
    }

    static func clear() {
        let fm = FileManager.default
        for u in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] { try? fm.removeItem(at: u) }
    }

    /// A stored paragraph's audio from `start` (a UTF-16 offset in the spoken text) at `speed`: 48 kHz samples and word
    /// starts, word ranges relative to the spoken text. Nil when the file is unreadable.
    static func render(_ clip: ElevenClip, from start: Int, speed: Double, boost: Double) -> RenderedSpeech? {
        guard var samples = StudioPack.decode(clip.file), !samples.isEmpty else { return nil }
        var words: [(sample: Int, range: NSRange)] = clip.record.words.map {
            (Int($0.seconds * 48_000), NSRange(location: $0.location, length: $0.length))
        }
        // started mid-paragraph (a tap on a word, resume): cut the audio at that word
        if start > 0, let first = words.first(where: { $0.range.location >= start }) {
            let cut = max(0, min(samples.count, first.sample - 480))        // 10 ms before the word
            samples.removeFirst(cut)
            words = words.filter { $0.range.location >= start }.map { ($0.sample - cut, $0.range) }
        }
        let tempo = max(1, speed)
        if tempo > 1.01, samples.count > 4096 {
            let before = samples.count
            samples = TimeStretch.compress(samples, tempo: tempo)
            let k = Double(samples.count) / Double(before)
            words = words.map { (Int(Double($0.sample) * k), $0.range) }
        }
        samples = Level.apply(samples, boost: boost)
        return RenderedSpeech(samples: samples, words: words)
    }
}
