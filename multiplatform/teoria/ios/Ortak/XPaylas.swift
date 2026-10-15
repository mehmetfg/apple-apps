// X'e paylaşım metni ve adresi (uygulama, Mac ve sınamalar ortak).
import Foundation

/// X'in paylaşım sayfasını hazır metinle açar; gönder düğmesine kullanıcı kendisi basar.
enum XPaylas {
    static let sinir = 280

    static func metin(yorum: String, alinti: String, kaynak: String) -> String {
        let y = yorum.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = "“\(alinti)” — \(kaynak)"
        return y.isEmpty ? a : "\(y)\n\n\(a)"
    }

    /// X 280 karakter sayar; aşıyorsa alıntı kısaltılır, yorum korunur.
    static func sigdir(yorum: String, alinti: String, kaynak: String) -> String {
        var m = metin(yorum: yorum, alinti: alinti, kaynak: kaynak)
        guard m.count > sinir else { return m }
        let y = yorum.trimmingCharacters(in: .whitespacesAndNewlines)
        let sabit = (y.isEmpty ? 0 : y.count + 2) + kaynak.count + 6
        let kalan = max(20, sinir - sabit)
        let kisa = alinti.count > kalan ? String(alinti.prefix(kalan - 1)) + "…" : alinti
        m = metin(yorum: y, alinti: kisa, kaynak: kaynak)
        return String(m.prefix(sinir))
    }

    static func adres(_ metin: String) -> URL? {
        var c = URLComponents(string: "https://x.com/intent/post")
        c?.queryItems = [URLQueryItem(name: "text", value: metin)]
        return c?.url
    }
}
