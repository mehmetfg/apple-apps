// Cloud voices beside ElevenLabs (2026-11-02): Google Cloud Text-to-Speech, Azure AI Speech and OpenAI. ElevenLabs'
// free API tier is 10,000 characters (about four minutes at 330 words a minute); the first two have large free monthly
// allowances, so heavy listening can stay free:
//
//   Google  WaveNet / Standard 4 M characters a month free, Neural2 and Chirp 3: HD 1 M (then $4 / $16 / $30 per M)
//   Azure   neural voices 0.5 M characters a month free on the F0 key (it stops at the cap, it does not bill)
//   OpenAI  no free allowance, about 1.5 cents a minute of audio (gpt-4o-mini-tts)
//
// One provider is chosen; its key sits in this device's Keychain. Each paragraph is synthesised once and stored in the
// same disk cache as ElevenLabs (ElevenCache), so listening again costs nothing. Characters sent are counted per month
// and, with "Ücretsiz kotada kal" on, a paragraph that would go past the free allowance is read by the iPhone voice.
//
// Word timings: Google's WaveNet / Neural2 / Standard voices return them through SSML marks (marks are not billed);
// Chirp 3: HD, Azure's REST endpoint and OpenAI return none, so words are spread over the audio by their length.
import Foundation
import AVFoundation
import Observation

enum CloudProvider: String, CaseIterable, Identifiable, Sendable {
    case google, azure, openai
    var id: String { rawValue }
    var name: String {
        switch self {
        case .google: "Google Cloud"
        case .azure: "Microsoft Azure"
        case .openai: "OpenAI"
        }
    }
    var keyHelp: String {
        switch self {
        case .google: "console.cloud.google.com › Text-to-Speech API'yi etkinleştir › Kimlik bilgileri › API anahtarı. Ücretsiz kota için bile faturalandırma hesabı ister."
        case .azure: "portal.azure.com › Speech kaynağı oluştur (ücretsiz F0) › Anahtarlar ve uç nokta: Anahtar 1 ve Bölge (örn. westeurope)."
        case .openai: "platform.openai.com › API keys. Ücretsiz kota yok; dakikası yaklaşık 1,5 sent."
        }
    }
    var service: String { "wisepath.cloud.\(rawValue)" }
}

struct CloudVoiceInfo: Identifiable, Hashable, Sendable {
    let id: String          // the provider's voice name
    let name: String
    let detail: String
}

@MainActor
@Observable
final class CloudVoice {
    static let shared = CloudVoice()
    nonisolated static let readerVoiceID = "vr.cloud"

    @ObservationIgnored private let d = UserDefaults.standard

    var provider: CloudProvider { didSet { d.set(provider.rawValue, forKey: "a.cloud.provider"); loadProvider(); changed() } }
    /// The chosen voice per provider.
    var voiceID: String { didSet { d.set(voiceID, forKey: "a.cloud.voice.\(provider.rawValue)"); changed() } }
    var voiceName: String { didSet { d.set(voiceName, forKey: "a.cloud.voiceName.\(provider.rawValue)") } }
    var azureRegion: String { didSet { d.set(azureRegion, forKey: "a.cloud.azureRegion") } }
    /// Stop before the free monthly allowance runs out (the paragraph is read by the iPhone voice instead).
    var stayFree: Bool { didSet { d.set(stayFree, forKey: "a.cloud.stayFree") } }

    private(set) var hasKey = false
    private(set) var voices: [CloudVoiceInfo] = []
    var status: String?
    /// Characters sent to the chosen provider this month (for the chosen voice's tier on Google).
    private(set) var usedThisMonth = 0

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var keys: [CloudProvider: String] = [:]

    var ready: Bool { hasKey && !voiceID.isEmpty && (provider != .azure || !azureRegion.isEmpty) }
    var displayName: String { voiceName.isEmpty ? provider.name : "\(provider.name) · \(voiceName)" }

    private init() {
        provider = CloudProvider(rawValue: d.string(forKey: "a.cloud.provider") ?? "") ?? .google
        azureRegion = d.string(forKey: "a.cloud.azureRegion") ?? "westeurope"
        stayFree = d.object(forKey: "a.cloud.stayFree") as? Bool ?? true
        voiceID = ""; voiceName = ""
        loadProvider()
    }

    private func loadProvider() {
        voiceID = d.string(forKey: "a.cloud.voice.\(provider.rawValue)") ?? ""
        voiceName = d.string(forKey: "a.cloud.voiceName.\(provider.rawValue)") ?? ""
        if keys[provider] == nil { keys[provider] = KeyVault.read(provider.service) }
        hasKey = keys[provider] != nil
        voices = []
        usedThisMonth = d.integer(forKey: usageKey)
    }

    private func changed() { onChange?() }

    // MARK: free allowance

    /// Free characters a month for the chosen voice; 0 when there is none.
    var freeAllowance: Int {
        switch provider {
        case .google:
            let v = voiceID.lowercased()
            if v.contains("chirp") || v.contains("neural2") || v.contains("studio") { return 1_000_000 }
            return 4_000_000                           // WaveNet, Standard
        case .azure: return 500_000
        case .openai: return 0
        }
    }

    /// Google counts each voice family on its own; the others count everything together.
    private var usageKey: String {
        let month = Date.now.formatted(.iso8601.year().month())
        let tier = provider == .google ? "." + googleTier : ""
        return "a.cloud.usage.\(provider.rawValue)\(tier).\(month)"
    }
    private var googleTier: String {
        let v = voiceID.lowercased()
        for t in ["chirp", "neural2", "studio", "wavenet", "standard"] where v.contains(t) { return t }
        return "other"
    }

    private func count(_ n: Int) {
        usedThisMonth = d.integer(forKey: usageKey) + n
        d.set(usedThisMonth, forKey: usageKey)
    }

    // MARK: key

    func saveKey(_ raw: String) {
        let k = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return }
        if KeyVault.write(k, service: provider.service) {
            keys[provider] = k; hasKey = true
            status = "Anahtar Keychain'e kaydedildi."
        } else { status = "Anahtar kaydedilemedi." }
        changed()
    }

    func deleteKey() {
        KeyVault.delete(provider.service)
        keys[provider] = nil; hasKey = false; voices = []
        status = "Anahtar silindi."
        changed()
    }

    private func key() -> String? {
        if keys[provider] == nil { keys[provider] = KeyVault.read(provider.service) }
        return keys[provider]
    }

    func choose(_ id: String) {
        voiceName = voices.first(where: { $0.id == id })?.name ?? id
        voiceID = id
        usedThisMonth = d.integer(forKey: usageKey)
    }

    // MARK: voices

    func test() async {
        guard let k = key() else { status = "API anahtarı kayıtlı değil."; return }
        status = "Bağlanıyor…"
        do {
            voices = try await fetchVoices(k)
            if voiceID.isEmpty || !voices.contains(where: { $0.id == voiceID }), let first = voices.first { choose(first.id) }
            status = "Bağlantı tamam · \(voices.count) ses"
        } catch {
            status = error.localizedDescription
        }
    }

    private func fetchVoices(_ k: String) async throws -> [CloudVoiceInfo] {
        switch provider {
        case .google:
            struct A: Decodable { struct V: Decodable { let name: String; let ssmlGender: String? }; let voices: [V]? }
            var u = URLComponents(string: "https://texttospeech.googleapis.com/v1/voices")!
            u.queryItems = [URLQueryItem(name: "languageCode", value: "tr-TR"), URLQueryItem(name: "key", value: k)]
            let data = try await Self.send(URLRequest(url: u.url!))
            let rank = ["chirp3-hd": 0, "wavenet": 1, "neural2": 2, "standard": 3]
            return (try JSONDecoder().decode(A.self, from: data).voices ?? [])
                .map { v -> CloudVoiceInfo in
                    let family = v.name.split(separator: "-").dropFirst(2).dropLast().joined(separator: "-")
                    let price = family.lowercased().contains("chirp") ? "en doğal · ayda 1 M ücretsiz"
                        : family.lowercased().contains("wavenet") || family.lowercased().contains("standard") ? "ayda 4 M ücretsiz"
                        : "ayda 1 M ücretsiz"
                    let gender = v.ssmlGender == "FEMALE" ? "Kadın" : v.ssmlGender == "MALE" ? "Erkek" : ""
                    return CloudVoiceInfo(id: v.name, name: v.name.replacingOccurrences(of: "tr-TR-", with: ""),
                                          detail: [gender, price].filter { !$0.isEmpty }.joined(separator: " · "))
                }
                .sorted { a, b in
                    let ra = rank.first { a.id.lowercased().contains($0.key) }?.value ?? 9
                    let rb = rank.first { b.id.lowercased().contains($0.key) }?.value ?? 9
                    return ra != rb ? ra < rb : a.id < b.id
                }
        case .azure:
            struct V: Decodable { let ShortName: String; let LocalName: String?; let Gender: String?; let Locale: String }
            var r = URLRequest(url: try Self.azureURL(azureRegion, "cognitiveservices/voices/list"))
            r.setValue(k, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
            let all = try JSONDecoder().decode([V].self, from: try await Self.send(r))
            return all.filter { $0.Locale == "tr-TR" || $0.ShortName.contains("Multilingual") }
                .map { CloudVoiceInfo(id: $0.ShortName, name: $0.LocalName ?? $0.ShortName,
                                      detail: [$0.Gender == "Female" ? "Kadın" : $0.Gender == "Male" ? "Erkek" : nil,
                                               $0.Locale == "tr-TR" ? "Türkçe" : "çok dilli"].compactMap { $0 }.joined(separator: " · ")) }
                .sorted { ($0.detail.contains("Türkçe") ? 0 : 1, $0.name) < ($1.detail.contains("Türkçe") ? 0 : 1, $1.name) }
        case .openai:
            // OpenAI has no voice list endpoint; its voices speak every language
            return ["alloy", "ash", "ballad", "coral", "echo", "fable", "nova", "onyx", "sage", "shimmer", "verse"]
                .map { CloudVoiceInfo(id: $0, name: $0.capitalized, detail: "çok dilli") }
        }
    }

    // MARK: synthesis

    /// One paragraph, from the cache or the provider.
    func synthesize(_ text: String) async throws -> ElevenClip {
        guard let k = key() else { throw ElevenError.noKey }
        guard !voiceID.isEmpty else { throw ElevenError.noVoice }
        let p = provider, voice = voiceID, region = azureRegion
        let ck = ElevenCache.key(voice: "\(p.rawValue):\(voice)", model: "", quality: "", text: text)
        if let clip = await Task.detached(priority: .userInitiated, operation: { ElevenCache.find(ck) }).value { return clip }
        let n = text.count
        if stayFree, usedThisMonth + n > freeAllowance {
            throw CloudError.freeAllowance(p == .openai ? "OpenAI'nin ücretsiz kotası yok; \"Ücretsiz kotada kal\" kapalı olmalı."
                                                        : "Bu ayın ücretsiz kotası doldu (\(freeAllowance.formatted()) karakter).")
        }
        let (audio, marks) = try await Self.fetch(text, provider: p, voice: voice, key: k, region: region)
        count(n)
        return try await Task.detached(priority: .userInitiated) {
            try ElevenCache.write(ck, audio: audio, record: ElevenRecord(words: [], seconds: 0, characters: text.utf16.count),
                                  limit: Int64(ElevenLabs.cacheLimitBytes), timing: { seconds in Self.words(text, marks: marks, seconds: seconds) })
        }.value
    }

    /// The Azure address for a region the user typed; a region that does not make a host name is an error to show,
    /// not a crash.
    nonisolated private static func azureURL(_ region: String, _ path: String) throws -> URL {
        let host = region.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !host.isEmpty, host.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
              let url = URL(string: "https://\(host).tts.speech.microsoft.com/\(path)") else { throw CloudError.badRegion(region) }
        return url
    }

    /// Audio (MP3) and, when the provider gives them, the start of every word in seconds.
    nonisolated private static func fetch(_ text: String, provider: CloudProvider, voice: String, key: String,
                                          region: String) async throws -> (Data, [Double]?) {
        switch provider {
        case .google:
            let chirp = voice.lowercased().contains("chirp")
            let (ssml, count) = chirp ? ("", 0) : marked(text)
            let useMarks = !chirp && ssml.utf8.count < 4800
            var body: [String: Any] = [
                "voice": ["languageCode": "tr-TR", "name": voice],
                "audioConfig": ["audioEncoding": "MP3", "sampleRateHertz": 24000],
            ]
            body["input"] = useMarks ? ["ssml": ssml] : ["text": text]
            if useMarks { body["enableTimePointing"] = ["SSML_MARK"] }
            var u = URLComponents(string: "https://texttospeech.googleapis.com/v1beta1/text:synthesize")!
            u.queryItems = [URLQueryItem(name: "key", value: key)]
            var r = URLRequest(url: u.url!)
            r.httpMethod = "POST"; r.timeoutInterval = 40
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
            struct A: Decodable { struct T: Decodable { let markName: String; let timeSeconds: Double }; let audioContent: String; let timepoints: [T]? }
            let a = try JSONDecoder().decode(A.self, from: try await send(r))
            guard let mp3 = Data(base64Encoded: a.audioContent) else { throw ElevenError.undecodable }
            var starts: [Double]?
            if useMarks, let t = a.timepoints, t.count == count {
                starts = t.sorted { (Int($0.markName.dropFirst()) ?? 0) < (Int($1.markName.dropFirst()) ?? 0) }.map(\.timeSeconds)
            }
            return (mp3, starts)
        case .azure:
            var r = URLRequest(url: try azureURL(region, "cognitiveservices/v1"))
            r.httpMethod = "POST"; r.timeoutInterval = 40
            r.setValue(key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
            r.setValue("application/ssml+xml", forHTTPHeaderField: "Content-Type")
            r.setValue("audio-24khz-48kbitrate-mono-mp3", forHTTPHeaderField: "X-Microsoft-OutputFormat")
            r.setValue("WisePath", forHTTPHeaderField: "User-Agent")
            r.httpBody = Data("<speak version='1.0' xml:lang='tr-TR'><voice name='\(voice)'><lang xml:lang='tr-TR'>\(escape(text))</lang></voice></speak>".utf8)
            return (try await send(r), nil)
        case .openai:
            var r = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
            r.httpMethod = "POST"; r.timeoutInterval = 60
            r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": "gpt-4o-mini-tts", "voice": voice, "input": text, "response_format": "mp3",
                "instructions": "Metni Türkçe, sakin ve kararlı bir anlatıcı gibi oku: ses yüksekliği ve hız baştan sona aynı kalsın, tonlama dar olsun, duygu ve abartılı vurgu katma, her cümlenin sonunda sesi belirgin biçimde indir, nefes ve uzun duraklama ekleme.",
            ])
            return (try await send(r), nil)
        }
    }

    /// The paragraph as SSML with a mark before every word (w0, w1…), and the number of words.
    nonisolated static func marked(_ text: String) -> (String, Int) {
        var out = "<speak>", n = 0, word = "", inWord = false
        for ch in text {
            if ch.isWhitespace {
                if inWord { out += escape(word); word = ""; inWord = false }
                out.append(ch)
            } else {
                if !inWord { out += "<mark name=\"w\(n)\"/>"; n += 1; inWord = true }
                word.append(ch)
            }
        }
        if inWord { out += escape(word) }
        return (out + "</speak>", n)
    }

    nonisolated static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&apos;")
    }

    /// Word ranges of the paragraph with their start times: from the provider's marks, or spread over the audio by the
    /// length of each word (a pause after , ; : . counts as a few letters more).
    nonisolated static func words(_ text: String, marks: [Double]?, seconds: Double) -> [ElevenWord] {
        var ranges: [(Int, Int, Int)] = []           // location, length, weight
        let ns = text as NSString
        var i = 0
        while i < ns.length {
            while i < ns.length, CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(ns.character(at: i)) ?? " ") { i += 1 }
            let start = i
            while i < ns.length, !CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(ns.character(at: i)) ?? " ") { i += 1 }
            if i > start {
                let w = ns.substring(with: NSRange(location: start, length: i - start))
                let pause = w.last.map { ".!?…".contains($0) ? 6 : ",;:".contains($0) ? 3 : 0 } ?? 0
                ranges.append((start, i - start, w.count + 1 + pause))
            }
        }
        if let m = marks, m.count == ranges.count {
            return zip(ranges, m).map { ElevenWord(location: $0.0, length: $0.1, seconds: $1) }
        }
        let total = Double(max(1, ranges.reduce(0) { $0 + $1.2 }))
        let lead = min(0.15, seconds * 0.02)
        let span = max(0, seconds - lead * 2)
        var at = 0
        return ranges.map { r in
            defer { at += r.2 }
            return ElevenWord(location: r.0, length: r.1, seconds: lead + span * Double(at) / total)
        }
    }

    nonisolated private static func send(_ r: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: r)
        guard let h = response as? HTTPURLResponse else { throw ElevenError.undecodable }
        guard (200..<300).contains(h.statusCode) else {
            var m = String(data: data, encoding: .utf8) ?? ""
            if let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let e = j["error"] as? [String: Any], let msg = e["message"] as? String { m = msg }
            throw ElevenError.server(h.statusCode, String(m.prefix(200)))
        }
        return data
    }
}

enum CloudError: LocalizedError {
    case freeAllowance(String)
    case badRegion(String)
    var errorDescription: String? {
        switch self {
        case .freeAllowance(let m): m
        case .badRegion(let r): "Azure bölgesi geçersiz: “\(r)”. Örnek: westeurope."
        }
    }
}
