import Foundation

// MARK: - Adapter file (vault: _araçlar/kurultay/adapters.json)

struct ThinkConfig: Codable, Hashable {
    /// Regex for the label of the button that turns on the thinking mode.
    var match: String
    /// Class fragment that marks the button as "on". Without it the state is unknown and the button is not clicked.
    var onClass: String?
    var note: String?
}

struct ApiConfig: Codable, Hashable {
    var provider: String
    var model: String
}

struct SeatConfig: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var maker: String?
    var url: String
    var newChatUrl: String?
    var input: [String]
    var send: [String]?
    var stop: [String]?
    var answer: [String]
    var answerExclude: String?
    var think: ThinkConfig?
    var api: ApiConfig?
    var enabled: Bool?
    /// Longest question the site accepts (characters); longer ones fail with a clear reason.
    var maxChars: Int?
    var color: String?
    var symbol: String?
}

struct ProviderConfig: Codable, Hashable {
    var base: String
    var name: String?
    var keyUrl: String?
    /// "openrouter" | "gemini" | "groq" | "openai": decides how the thinking effort is asked for.
    var style: String?
}

struct AdapterFile: Codable {
    var version: Int
    /// "chrome" (default when Chrome is installed) or "webkit"
    var engine: String?
    var seats: [SeatConfig]
    var providers: [String: ProviderConfig]?
}

// MARK: - Sessions (vault: 05 - Notlar/Kurultay/<id>/oturum.json)

enum AnswerState: String, Codable {
    case waiting, sending, thinking, writing, done, timeout, failed, skipped

    var finished: Bool { [.done, .timeout, .failed, .skipped].contains(self) }
    var label: String {
        switch self {
        case .waiting: "Sırada"
        case .sending: "Gönderiliyor"
        case .thinking: "Düşünüyor"
        case .writing: "Yazıyor"
        case .done: "Tamam"
        case .timeout: "Süre doldu"
        case .failed: "Olmadı"
        case .skipped: "Atlandı"
        }
    }
}

struct Answer: Codable, Hashable {
    var seat: String
    var state: AnswerState
    var text: String = ""
    /// "web" or "api"
    var via: String = "web"
    /// "on" | "off" | "unknown" | "missing" | "none" | "api"
    var thinking: String?
    var started: Date?
    var finished: Date?
    var error: String?
    /// Address of the conversation, so a follow-up lands in the same chat.
    var chatUrl: String?

    var seconds: Int? {
        guard let s = started else { return nil }
        return Int((finished ?? Date()).timeIntervalSince(s))
    }
}

struct Round: Codable, Identifiable, Hashable {
    var id: Int
    var text: String
    var asked: Date
    var answers: [String: Answer]
    /// The user's own question when `text` also carries attached sources (Kıvılcım transcripts).
    var question: String? = nil

    var shownText: String { question ?? text }

    var done: Bool { answers.values.allSatisfy { $0.state.finished } }
    var doneCount: Int { answers.values.filter { $0.state == .done }.count }
}

struct Session: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var created: Date
    var seats: [String]
    var rounds: [Round]
    /// Where the question came from: "mac" | "claude" | "iphone" | "kivilcim"
    var origin: String?
    /// Recordings attached as context (Kıvılcım).
    var sources: [SourceRef]? = nil
    /// Claude follows the session: when a round finishes it writes the report and the arrangement (tertip.json).
    var follow: Bool? = nil
}

struct SourceRef: Codable, Hashable {
    /// "kivilcim"
    var app: String
    var id: String
    var title: String
    var date: String?
    var seconds: Double?
}

/// Claude's arrangement of a session: written to 05 - Notlar/Kurultay/<id>/tertip.json.
struct Arrangement: Codable, Hashable {
    struct ModelNote: Codable, Hashable {
        var oz: String?
        var hukum: String?
    }
    struct RoundNote: Codable, Hashable {
        var tur: Int
        var baslik: String?
        var soru_ozeti: String?
        var ortak: [String]?
        var ayrisan: [String]?
        var oneriler: [String]?
        var claude: String?
        var modeller: [String: ModelNote]?
    }
    var ozet: String?
    var turlar: [RoundNote]?
    var yazildi: String?

    func round(_ n: Int) -> RoundNote? { turlar?.first { $0.tur == n } }
}

/// Follow state written by takip.py: _araçlar/kurultay/durum/takip/<id>.json
struct FollowState: Codable, Hashable {
    var session: String
    var state: String
    var round: Int?
    var updated: String?
    var note: String?

    var label: String {
        switch state {
        case "bekliyor": "Claude takipte · cevaplar bekleniyor"
        case "sirada": "Claude sırada"
        case "calisiyor": "Claude değerlendiriyor…"
        case "hazir": "Claude raporu yazdı"
        case "giris-yok": "Claude komut satırında giriş yok · sohbette \"Kurultay'ı değerlendir\" de"
        case "hata": "Claude takibi hata verdi"
        default: state
        }
    }
}

struct Decision: Codable, Hashable {
    /// "bekliyor" | "onaylandi" | "duzelt" | "reddedildi" | "uygulandi"
    var state: String
    var note: String?
    var date: Date
    var by: String?

    var label: String {
        switch state {
        case "onaylandi": "Onaylandı"
        case "duzelt": "Düzeltme istendi"
        case "reddedildi": "Reddedildi"
        case "uygulandi": "Uygulandı"
        default: "Onay bekliyor"
        }
    }
}

/// A request written by the iPhone (or any tool) into _araçlar/kurultay/durum/istek/.
struct InboxRequest: Codable {
    var text: String
    var session: String?
    var title: String?
    var seats: [String]?
    /// Kıvılcım record ids to attach as context.
    var kivilcim: [String]?
    var follow: Bool?
}

extension JSONEncoder {
    static let kurultay: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    static let kurultay: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

func slug(_ s: String) -> String {
    let map: [Character: String] = ["ç": "c", "ğ": "g", "ı": "i", "ö": "o", "ş": "s", "ü": "u", "Ç": "c", "Ğ": "g", "İ": "i", "Ö": "o", "Ş": "s", "Ü": "u"]
    var out = ""
    for ch in s.lowercased() {
        if let m = map[ch] { out += m } else if ch.isLetter || ch.isNumber { out.append(ch) } else { out += "-" }
    }
    while out.contains("--") { out = out.replacingOccurrences(of: "--", with: "-") }
    out = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return String(out.prefix(48))
}

/// File-name safe title for Obsidian notes.
func noteTitle(_ s: String) -> String {
    let bad = CharacterSet(charactersIn: "/\\:*?\"<>|#^[]")
    return String(s.components(separatedBy: bad).joined(separator: " ").prefix(80)).trimmingCharacters(in: .whitespaces)
}
