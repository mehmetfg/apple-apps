// Decides who wrote a note and what kind of note it is.
// Mirrors Vault Tezgâhı (Artifacts/_vault/sunucu.py · koken_bul / koken_kural) so both tools agree.
import Foundation

struct OriginOverrides: Decodable {
    var files: [String: String] = [:]
    var folders: [String: String] = [:]
    enum CodingKeys: String, CodingKey { case files = "dosya", folders = "klasor" }
}

enum Classifier {
    static let journalRoot = "03 - Seyir Defteri/Günlükler"

    static let aiTypes: Set<String> = ["kavram", "eser", "ders", "filozof", "meta", "tartışma", "okul", "yazar",
                                       "dinleme-metni", "akım", "dönem", "soru"]
    static let aiTypeEnglish: Set<String> = ["source", "artifact", "concept", "synthesis", "tracking", "dongu",
                                             "vocabulary", "practice", "taxonomy", "report"]
    static let aiPaths = ["/hatlar/", "09 - Claude Sessions/", "/dersler/", "04 - Books/Kütüphane/", "/wiki/",
                          "11 - Kanon Haritası/", "_Tasnif Çalışması/", "Artifacts/", "/_projects/", "/raw/",
                          "/metin/", "/dinleme/", "/orgu/", "/ladder/", "/dongu/", "_araçlar/"]
    static let aiNames: Set<String> = ["CLAUDE.md", "index.md", "log.md", "README.md", "STATE.md", "DURUM.md",
                                       "KARNE.md", "MUFREDAT.md", "MÜFREDAT.md", "BIRIM.md"]
    static let minePaths = ["07 - Şiirler/", "Keep-Notes/", "Inbox/", "05 - Notlar/", "Yazarlık/Makaleler/",
                            "Yazarlık/Denemeler/", "Yazarlık/Kişisel Günlükler/"]
    static let externalPaths = ["Clippings/", "Gmail-Archive/"]

    static func origin(path: String, fm: Frontmatter, overrides: OriginOverrides) -> Origin {
        let fileName = (path as NSString).lastPathComponent
        let name = (fileName as NSString).deletingPathExtension
        switch fm["yazan"]?.text?.lowercased() {
        case "ben": return .me
        case "yz": return .ai
        case "ortak": return .shared
        case "dış", "dis": return .external
        default: break
        }
        if let o = overrides.files[path] { return map(o) }
        if let folder = overrides.folders.keys.filter({ path.hasPrefix($0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/") })
            .max(by: { $0.count < $1.count }) {
            return map(overrides.folders[folder] ?? "?")
        }
        let slashed = "/" + path
        if name.contains("Düşüncelerim") { return .shared }
        if fm["journal"] != nil || path.hasPrefix(journalRoot + "/") || slashed.contains("/Seyir Defteri/Günlükler/") { return .me }
        if externalPaths.contains(where: path.hasPrefix) || fm["tür"]?.text == "highlight-arşivi" { return .external }
        if ["ilk_kaynak", "personal_os", "üretim", "metin_slug"].contains(where: { fm[$0] != nil }) { return .ai }
        if let t = fm["tür"]?.text, aiTypes.contains(t) { return .ai }
        if let t = fm["type"]?.text, aiTypeEnglish.contains(t) { return .ai }
        if aiNames.contains(fileName) || aiPaths.contains(where: { slashed.contains($0) }) { return .ai }
        if minePaths.contains(where: path.hasPrefix) && !path.contains("_ingest") { return .me }
        if !path.contains("/"), let first = name.unicodeScalars.first, !CharacterSet.alphanumerics.contains(first) { return .ai }
        return .unknown
    }

    private static func map(_ s: String) -> Origin {
        switch s {
        case "ben": return .me
        case "yz": return .ai
        case "ortak": return .shared
        case "dış", "dis": return .external
        default: return .unknown
        }
    }

    static func kind(path: String, fm: Frontmatter) -> NoteKind {
        if isJournal(path: path, fm: fm) { return .journal }
        if let t = fm["tür"]?.text, let k = NoteKind.from(vaultType: t) { return k }
        if path.hasPrefix("05 - Notlar/Fikirler/") { return .idea }
        if path.hasPrefix("07 - Şiirler/") { return .poem }
        if path.hasPrefix("Yazarlık/Denemeler/") { return .essay }
        if path.hasPrefix("Yazarlık/Makaleler/") { return .article }
        if path.hasPrefix("05 - Notlar/Kavramlar/") { return .concept }
        if path.hasPrefix("04 - Books/") && !path.contains("/Kütüphane/") { return .book }
        return .note
    }

    static func isJournal(path: String, fm: Frontmatter) -> Bool {
        if let j = fm["journal"]?.text, j == "Kişisel Günlük" || j == "Kişisel daily" { return true }
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        return path.contains("Seyir Defteri/Günlükler/") && TurkishCalendar.parseDay(name) != nil
    }

    static func journalDay(path: String, fm: Frontmatter) -> String? {
        if let t = fm["Günlük Tarihi"]?.text, let d = TurkishCalendar.parseDay(t) { return d }
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        return TurkishCalendar.parseDay(name)
    }
}
