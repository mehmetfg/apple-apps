// Link layer, Mac side (2026-11-04). links.py (run by isle.py) writes <kok>/links.json: every topic (mostly a Teoria
// book), the spoken and written production tied to it from Kıvılcım, Teoria and Wise Path, and the spoken minutes per
// day and week. The app only reads it; a topic change is an event ("topic") like every other correction.
import Foundation

extension Depo {
    /// A vault-relative path (Teoria / Wise Path note) → file URL; asks iCloud to download it if it is not here.
    func vaultURL(_ rel: String) -> URL? {
        guard !rel.isEmpty else { return nil }
        let u = vault.appendingPathComponent(rel)
        if !FileManager.default.fileExists(atPath: u.path) { try? FileManager.default.startDownloadingUbiquitousItem(at: u) }
        return u
    }

    func segments(_ o: Oge) -> [Segment] {
        struct D: Codable { var parcalar: [Segment]? }
        let u = kok.appendingPathComponent("dokum/\(o.id).json")
        guard let v = try? Data(contentsOf: u), let d = try? JSONDecoder().decode(D.self, from: v) else {
            return o.metin.isEmpty ? [] : [Segment(t: 0, x: o.metin)]
        }
        // Whisper's pieces are a few words each; read as paragraphs (same rule as the day-journal block in isle.py)
        var out: [Segment] = [], words: [String] = [], start: Double?
        for sg in d.parcalar ?? [] {
            if start == nil { start = sg.t }
            words.append(sg.x)
            let n = words.joined(separator: " ").split(separator: " ").count
            if sg.t - (start ?? 0) >= 60 || ("." == sg.x.last.map(String.init) || sg.x.hasSuffix("?") || sg.x.hasSuffix("!")) && n > 70 {
                out.append(Segment(t: start ?? 0, x: words.joined(separator: " "))); words = []; start = nil
            }
        }
        if !words.isEmpty { out.append(Segment(t: start ?? 0, x: words.joined(separator: " "))) }
        return out
    }

    /// Display name of a topic id (book in links.json, recent book, or a free "k:<name>").
    func topicName(_ id: String?) -> String {
        guard let id, !id.isEmpty, id != "-" else { return "Konusuz" }
        if id.hasPrefix("k:") { return String(id.dropFirst(2)) }
        return links.topic(id)?.short ?? links.recent_books.first { $0.id == id }?.short ?? id
    }

}
