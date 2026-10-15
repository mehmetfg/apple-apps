// Türkçe metin yardımcıları: yazılan cevabı ölçmek için normalleştirme, yakınlık ve anahtar kapsamı.
import Foundation

enum Dil {
    static let tr = Locale(identifier: "tr_TR")

    /// Küçük harf (Türkçe kuralıyla), şapkasız, noktalamasız. ı/i ve ş/s farkı yazım hatası sayılmaz.
    static func normal(_ s: String) -> String {
        let k = s.lowercased(with: tr)
        let d = k.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: tr)
            .replacingOccurrences(of: "ı", with: "i")
        let harf = d.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(harf).split(separator: " ").joined(separator: " ")
    }

    static func kelimeler(_ s: String) -> [String] { normal(s).split(separator: " ").map(String.init) }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var onceki = Array(0...y.count)
        for i in 1...x.count {
            var simdi = [i] + Array(repeating: 0, count: y.count)
            for j in 1...y.count {
                simdi[j] = min(onceki[j] + 1, simdi[j - 1] + 1, onceki[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            onceki = simdi
        }
        return onceki[y.count]
    }

    enum Esleme { case tam, yakin, yok }

    /// Tek kelimelik/kısa cevap: tam · bir-iki harf hatayla yakın · yok.
    static func esle(_ cevap: String, _ dogru: String) -> Esleme {
        let c = normal(cevap), d = normal(dogru)
        if c.isEmpty { return .yok }
        if c == d { return .tam }
        let tolerans = max(1, d.count / 6)
        if levenshtein(c, d) <= tolerans { return .yakin }
        // "kendinde şey" yerine "kendinde sey" gibi boşluk farkları
        if c.replacingOccurrences(of: " ", with: "") == d.replacingOccurrences(of: " ", with: "") { return .tam }
        return .yok
    }

    /// Anahtar kelimelerin kaçı cevapta geçiyor (Türkçe ek alır: kökün ilk ~%70'i aranır).
    static func kapsam(_ cevap: String, _ anahtar: [String]) -> (oran: Double, bulunan: [String]) {
        guard !anahtar.isEmpty else { return (0, []) }
        let k = kelimeler(cevap)
        var bulunan: [String] = []
        for a in anahtar {
            let parcalar = kelimeler(a)
            let tamam = parcalar.allSatisfy { p in
                let kok = String(p.prefix(max(3, Int(Double(p.count) * 0.7))))
                return k.contains { $0.hasPrefix(kok) || (p.count <= 4 && $0 == p) }
            }
            if tamam { bulunan.append(a) }
        }
        return (Double(bulunan.count) / Double(anahtar.count), bulunan)
    }

    /// İki cümlenin kelime düzeyinde benzerliği (0…1) — yeniden kurulan cümle için.
    static func benzerlik(_ a: String, _ b: String) -> Double {
        let x = Set(kelimeler(a).map { String($0.prefix(5)) }), y = Set(kelimeler(b).map { String($0.prefix(5)) })
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        return Double(x.intersection(y).count) / Double(x.union(y).count)
    }

    static func dosyaAdi(_ s: String) -> String {
        let n = normal(s).replacingOccurrences(of: " ", with: "-")
        return n.isEmpty ? "cihaz" : String(n.prefix(32))
    }

    /// Gündem için: sık kullanılan ama anlamsız kelimeler.
    static let bosKelimeler: Set<String> = Set("""
    ve ile bir bu da de ki mi mu ne ama icin gibi olarak olan daha cok en her hem ya ise sonra once kadar
    degil var yok olur oldugu olmak oldu sey seyi seyler onu ona onun bunu buna bunun bize biz sen ben o
    sadece bile ancak yani cunku eger zaman artik hep hic hicbir kendi kendini kendisi baska diye uzere
    tum butun ayni olan olani icinde uzerine karsi gore sanki nasil neden niye hangi hangisi kimse kim
    olmayan olmasi olabilir olmaz eder etmek edilir yapar yapmak gerek gerekir zaten aslinda hala bazen
    iki uc dort bes ilk son yeni buyuk kucuk iyi kotu ayri dolayi uzerinden tarafindan belki sizi siz
    onlar onlari bunlar sunlar boyle soyle oyle burada orada simdi
    """.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init))

    /// Ek almış hâlleri de boş sayılan kökler (olduğu, değildi, kendisine…).
    static let bosKokler = ["oldu", "olma", "olan", "olur", "olab", "degil", "kendi", "seyl", "buna", "bunl", "onla", "onun",
                            "asli", "gerek", "yalni", "baska", "herke", "simdi", "zaman", "sonra", "sadec", "ancak",
                            "diyor", "deriz", "diye", "yani", "gibi", "icin", "uzeri", "hangi", "boyle", "soyle", "orada",
                            "burad", "nasil", "neden", "ister", "eder", "edil", "yapar", "yapil", "gore", "kadar", "birbi",
                            "hicbi", "butun", "ilgil", "bakim", "bunun", "sizin", "bizim", "ikinc", "birin", "ucunc"]

    static func sikKelimeler(_ metinler: [String], adet: Int = 8) -> [(String, Int)] {
        var say: [String: Int] = [:]
        var gorunus: [String: String] = [:]
        for m in metinler {
            for ham in m.split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "’" }) {
                let kelime = String(ham).split(separator: "'").first.map(String.init) ?? String(ham)
                let n = normal(kelime)
                guard n.count >= 5, !bosKelimeler.contains(n), !bosKokler.contains(where: { n.hasPrefix($0) }) else { continue }
                let kok = String(n.prefix(6))
                say[kok, default: 0] += 1
                if gorunus[kok] == nil || kelime.count < (gorunus[kok]?.count ?? 99) {
                    gorunus[kok] = kelime.lowercased(with: tr)
                }
            }
        }
        return say.filter { $0.value >= 2 }.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(adet).map { (gorunus[$0.key] ?? $0.key, $0.value) }
    }
}
