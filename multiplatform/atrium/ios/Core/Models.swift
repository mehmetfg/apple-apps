// Core data types shared by the iPhone and Mac targets.
import Foundation

enum Origin: String, Codable, CaseIterable, Identifiable {
    case me, ai, shared, external, unknown
    var id: String { rawValue }

    var label: String {
        switch self {
        case .me: return "Sen"
        case .ai: return "Yapay zekâ"
        case .shared: return "Ortak"
        case .external: return "Dış kaynak"
        case .unknown: return "Belirsiz"
        }
    }
}

enum NoteKind: String, Codable, CaseIterable, Identifiable {
    case journal, idea, essay, article, poem, book, concept, note
    var id: String { rawValue }

    var label: String {
        switch self {
        case .journal: return "Günlük"
        case .idea: return "Fikir"
        case .essay: return "Deneme"
        case .article: return "Makale"
        case .poem: return "Şiir"
        case .book: return "Kitap notu"
        case .concept: return "Kavram"
        case .note: return "Not"
        }
    }

    var symbol: String {
        switch self {
        case .journal: return "book.closed.fill"
        case .idea: return "lightbulb.fill"
        case .essay: return "text.alignleft"
        case .article: return "doc.richtext.fill"
        case .poem: return "quote.opening"
        case .book: return "books.vertical.fill"
        case .concept: return "circle.hexagongrid.fill"
        case .note: return "note.text"
        }
    }

    var hint: String {
        switch self {
        case .journal: return "Bugünün sayfası. Varsa açılır, yoksa şablonla kurulur."
        case .idea: return "Tek düşünce. Sonra makaleye dönüşebilir."
        case .essay: return "Serbest, kişisel düşünce yazısı."
        case .article: return "Bitmesi, dışarı çıkması beklenen yazı."
        case .poem: return "Başlıksızsa adı tarihtir."
        case .book: return "Ad biçimi: Eser - Yazar."
        case .concept: return "İki ayrı metinde geçtiyse ayrı not olur."
        case .note: return "Klasörü sen seçersin."
        }
    }

    /// Vault value written to the `tür:` front-matter field (data contract with Vault Tezgâhı).
    var vaultType: String {
        switch self {
        case .journal: return "gunluk"
        case .idea: return "fikir"
        case .essay: return "deneme"
        case .article: return "makale"
        case .poem: return "siir"
        case .book: return "kitap"
        case .concept: return "kavram"
        case .note: return "serbest"
        }
    }

    static func from(vaultType: String) -> NoteKind? {
        allCases.first { $0.vaultType == vaultType }
    }
}

/// One Markdown file in the vault, as remembered by the index.
struct NoteRecord: Codable, Identifiable, Hashable {
    var path: String            // vault-relative, NFC
    var modified: Date
    var created: Date
    var size: Int
    var words: Int?             // nil until the file has been downloaded and read
    var origin: Origin
    var kind: NoteKind
    var journalDay: String?     // yyyy-MM-dd for journal pages
    var links: [String]         // outgoing wikilink targets (lowercased names)
    var discipline: String?

    var id: String { path }
    var name: String { ((path as NSString).lastPathComponent as NSString).deletingPathExtension }
    var folder: String { (path as NSString).deletingLastPathComponent }
    var area: String { path.split(separator: "/").first.map(String.init).flatMap { $0.hasSuffix(".md") ? nil : $0 } ?? "Kök" }
}

/// What happened on one calendar day, recorded by the app from the moment it is installed.
struct DayLedger: Codable {
    var touched: Set<String> = []
    var created: Set<String> = []
    var wordsAdded: Int = 0
    var wordsAddedMine: Int = 0
}

/// One entry of the Kıvılcım voice archive (`dizin.json`). Keys follow Kıvılcım's own format.
struct SparkItem: Codable, Identifiable {
    var id: String
    var date: String
    var device: String?
    var duration: Double?
    var text: String?
    var title: String?
    var summary: String?
    var area: String?
    var intent: String?
    var state: String?
    var notePath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case date = "tarih"
        case device = "cihaz"
        case duration = "sure"
        case text = "metin"
        case title = "baslik"
        case summary = "ozet"
        case area = "alan"
        case intent = "amac"
        case state = "durum"
        case notePath = "not"
    }
}

struct SparkIndex: Codable {
    var items: [SparkItem]
    enum CodingKeys: String, CodingKey { case items = "ogeler" }
}

// MARK: - App catalog (_araçlar/atrium/catalog/apps.json)

struct CatalogOption: Codable, Identifiable, Hashable {
    var id: String
    var label: String
    var color: String?
    var symbol: String?
}

struct CatalogApp: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var domain: String
    var role: String
    var status: String
    var platforms: [String]
    var bundleId: String?
    var source: String?
    var readme: String?
    var purpose: String
    var since: String?
}

struct AppCatalog: Codable {
    var version: Int
    var note: String?
    var domains: [CatalogOption]
    var roles: [CatalogOption]
    var statuses: [CatalogOption]
    var apps: [CatalogApp]

    func domain(_ id: String) -> CatalogOption? { domains.first { $0.id == id } }
    func role(_ id: String) -> CatalogOption? { roles.first { $0.id == id } }
    func status(_ id: String) -> CatalogOption? { statuses.first { $0.id == id } }
}

// MARK: - Navigation routes

struct NoteRoute: Hashable { var path: String }
struct FolderRoute: Hashable { var path: String }
struct AppRoute: Hashable { var id: String }
struct DayRoute: Hashable { var day: String }
