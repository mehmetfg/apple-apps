import Foundation

// Yazılı Türkçeyi modelin harf dizisine çevirir ve 10 saniyelik parçalara böler.
// Python eşi: _araçlar/ema/model/referans.py (harfler, parcala) — ikisi aynı sonucu vermeli.
enum Metin {
    /// Modelin harf tablosu (ema.json) — motor açmadan; bütün sesler aynı metin hazırlığını kullanır.
    static let sozluk: Set<Unicode.Scalar> = {
        struct T: Decodable { let vocab: [String] }
        guard let u = Bundle(for: Motor.self).url(forResource: "ema", withExtension: "json"),
              let d = try? Data(contentsOf: u), let t = try? JSONDecoder().decode(T.self, from: d) else { return [] }
        return Set(t.vocab.compactMap { $0.unicodeScalars.count == 1 ? $0.unicodeScalars.first : nil })
    }()

    // MARK: sayılar

    private static let birler = ["", "bir", "iki", "üç", "dört", "beş", "altı", "yedi", "sekiz", "dokuz"]
    private static let onlar = ["", "on", "yirmi", "otuz", "kırk", "elli", "altmış", "yetmiş", "seksen", "doksan"]
    private static let buyuk: [(UInt64, String)] = [(1_000_000_000_000, "trilyon"), (1_000_000_000, "milyar"),
                                                   (1_000_000, "milyon"), (1000, "bin")]

    private static func yuzler(_ n: UInt64) -> [String] {
        let y = Int(n / 100), o = Int(n % 100 / 10), b = Int(n % 10)
        var p: [String] = y == 0 ? [] : (y == 1 ? ["yüz"] : [birler[y], "yüz"])
        p += [onlar[o], birler[b]].filter { !$0.isEmpty }
        return p
    }

    static func sayi(_ deger: UInt64) -> String {
        if deger == 0 { return "sıfır" }
        var n = deger, cikis: [String] = []
        for (b, ad) in buyuk {
            let q = n / b
            n %= b
            if q == 0 { continue }
            if q < 1000 {
                cikis += (q == 1 && ad == "bin") ? [ad] : yuzler(q) + [ad]
            } else {
                cikis += sayi(q).split(separator: " ").map(String.init) + [ad]
            }
        }
        return (cikis + yuzler(n)).joined(separator: " ")
    }

    // MARK: kısaltmalar ve rakamlar

    private static let kisaltmalar: [(String, String)] = [
        ("\\bTL\\b", "Türk lirası"), ("\\bvb\\.", "ve benzeri"), ("\\bvs\\.", "vesaire"),
        ("\\börn\\.", "örneğin"), ("\\bDr\\.", "doktor"), ("\\bProf\\.", "profesör"),
    ]

    private static func degistir(_ s: String, _ desen: String, _ yerine: String) -> String {
        s.replacingOccurrences(of: desen, with: yerine, options: .regularExpression)
    }

    static func rakamlariOku(_ girdi: String) -> String {
        var s = girdi
        for (d, y) in kisaltmalar { s = degistir(s, d, y) }
        s = degistir(s, "%\\s*([0-9])", "yüzde $1")
        s = degistir(s, "([0-9])\\.([0-9]{3})(?![0-9])", "$1$2")
        s = degistir(s, "([0-9])\\.([0-9]{3})(?![0-9])", "$1$2")
        s = degistir(s, "([0-9]+),([0-9]+)", "$1 virgül $2")
        let ns = NSMutableString(string: s)
        let re = try! NSRegularExpression(pattern: "[0-9]+")
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
            let r = ns.substring(with: m.range)
            let soz: String
            if r.count <= 15, let v = UInt64(r) {
                soz = sayi(v)
            } else {
                soz = r.compactMap { $0.wholeNumberValue }.map { sayi(UInt64($0)) }.joined(separator: " ")
            }
            ns.replaceCharacters(in: m.range, with: " " + soz + " ")
        }
        return ns as String
    }

    // MARK: harf dizisi

    private static let tipo: [Character: String] = [
        "’": "'", "‘": "'", "ʼ": "'", "´": "'", "`": "'", "“": "\"", "”": "\"", "„": "\"",
        "«": "\"", "»": "\"", "–": "-", "—": "-", "−": "-", "…": "...",
    ]
    private static let turkce = Set("çğıöşüÇĞİÖŞÜ".unicodeScalars)

    static func harfler(_ girdi: String, sozluk: Set<Unicode.Scalar>) -> String {
        var s = String(rakamlariOku(girdi).map { tipo[$0] ?? String($0) }.joined())
        s = s.replacingOccurrences(of: "İ", with: "i").replacingOccurrences(of: "I", with: "ı").lowercased()
        var cikis = String.UnicodeScalarView()
        for sk in s.unicodeScalars {
            var parca: [Unicode.Scalar] = [sk]
            if !turkce.contains(sk) {
                parca = String(sk).decomposedStringWithCompatibilityMapping.unicodeScalars
                    .filter { $0.properties.canonicalCombiningClass == .notReordered }
            }
            if !parca.isEmpty && parca.allSatisfy(sozluk.contains) {
                cikis.append(contentsOf: parca)
            } else {
                cikis.append(" ")
            }
        }
        return String(cikis).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: imleç haritası

    /// Modelin okuyacağı her kelime için asıl metindeki karşılığının aralığı (UTF-16, NSRange).
    /// "1971" gibi bir sözcük birkaç model kelimesine açılır; hepsi aynı aralığı gösterir.
    /// Sözcük sözcük açınca toplam tutmazsa (birden çok sözcüğe yayılan bir kalıp), orantılı dağıtılır.
    static func kelimeHaritasi(_ orijinal: String, sozluk: Set<Unicode.Scalar>) -> [NSRange] {
        let ns = orijinal as NSString
        let re = try! NSRegularExpression(pattern: "\\S+")
        let sozcukler = re.matches(in: orijinal, range: NSRange(location: 0, length: ns.length)).map(\.range)
        let toplam = harfler(orijinal, sozluk: sozluk).split(separator: " ").count
        var harita: [NSRange] = []
        for r in sozcukler {
            let n = harfler(ns.substring(with: r), sozluk: sozluk).split(separator: " ").count
            harita += Array(repeating: r, count: n)
        }
        if harita.count == toplam || sozcukler.isEmpty { return harita }
        return (0..<toplam).map { i in sozcukler[min(sozcukler.count - 1, i * sozcukler.count / max(toplam, 1))] }
    }

    // MARK: parçalama (chunker.py)

    private static let kesimler: [(NSRegularExpression, Double)] = [
        (try! NSRegularExpression(pattern: "[.!?]+[\"')]*(?= )"), 0.25),
        (try! NSRegularExpression(pattern: "[,;:](?= )"), 0.12),
        (try! NSRegularExpression(pattern: "\\S(?= )"), 0.12),
    ]
    private static let harf = try! NSRegularExpression(pattern: "\\p{L}")

    /// [(parça, ardından gelen sessizlik saniyesi)]; her parça cümle sonu işaretiyle biter.
    /// `ilkSinir`: ilk parça yalnız cümle sonu ya da yan cümle işaretinde, bu kadar harfin içinde kesilir —
    /// ilk ses erken gelsin, geri kalanı o çalarken üretilsin. Uygun yer yoksa normal kesim.
    static func parcala(_ metin: String, hiz: Double, ilkSinir: Int? = nil) -> [(String, Double)] {
        let sinir = Int(min(250, 18.0 * 10.0 * hiz))
        var parcalar: [(String, Double)] = []
        var kalan = metin.trimmingCharacters(in: .whitespaces) as NSString
        var ilk = true
        while kalan.length > 0 {
            var kes = kalan.length, ara = 0.0
            if ilk, let k = ilkSinir, kalan.length > k {
                let on = kalan.substring(to: k + 1)
                for (re, bosluk) in kesimler.prefix(2) {
                    if let son = re.matches(in: on, range: NSRange(location: 0, length: (on as NSString).length)).last {
                        kes = son.range.location + son.range.length
                        ara = bosluk
                        break
                    }
                }
            }
            ilk = false
            if kes == kalan.length && kalan.length > sinir {
                kes = sinir
                let on = kalan.substring(to: sinir + 1)
                for (re, bosluk) in kesimler {
                    if let son = re.matches(in: on, range: NSRange(location: 0, length: (on as NSString).length)).last {
                        kes = son.range.location + son.range.length
                        ara = bosluk
                        break
                    }
                }
            }
            var p = kalan.substring(to: kes).trimmingCharacters(in: .whitespaces)
            kalan = kalan.substring(from: kes).trimmingCharacters(in: .whitespaces) as NSString
            if harf.firstMatch(in: p, range: NSRange(location: 0, length: (p as NSString).length)) != nil {
                let govde = p.trimmingCharacters(in: CharacterSet(charactersIn: "\"')"))
                if !(govde.hasSuffix(".") || govde.hasSuffix("!") || govde.hasSuffix("?")) {
                    while let c = p.last, ",;:- ".contains(c) { p.removeLast() }
                    p += "."
                }
                parcalar.append((p, ara))
            }
        }
        if !parcalar.isEmpty { parcalar[parcalar.count - 1].1 = 0 }
        return parcalar
    }
}
