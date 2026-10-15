// Metin araçları — Cümle Tezgâhı (HTML) ile birebir aynı kurallar; sicil ve arşiv bu sonuçlara göre
// hesaplandığı için değiştirilmez: kelime ayıklama, gövde, fark (LCS), hata türü, gramer sezici, iskelet.
import Foundation

struct FarkOp: Hashable, Codable { var t: String; var s: String }   // t: ok · eksik · fazla

struct Fark: Hashable {
    var ops: [FarkOp]
    var ayni: Int
    var toplam: Int
    var yuzde: Int
    var metin: String
    var tam: Bool { !ops.isEmpty && ops.allSatisfy { $0.t == "ok" } }
    var atlanan: [String] { ops.filter { $0.t == "eksik" }.map(\.s) }
    var fazladan: [String] { ops.filter { $0.t == "fazla" }.map(\.s) }
}

enum Metin {
    static let kelimeRE = try! NSRegularExpression(pattern: "[A-Za-zÀ-ÖØ-öø-ÿ]+(?:['’][A-Za-zÀ-ÖØ-öø-ÿ]+)*")

    static func kelimeler(_ m: String) -> [String] { araliklar(m).map(\.0) }

    /// Kelimeler ve metindeki yerleri (UTF-16 aralığı).
    static func araliklar(_ m: String) -> [(String, NSRange)] {
        let ns = m as NSString
        return kelimeRE.matches(in: m, range: NSRange(location: 0, length: ns.length)).map { (ns.substring(with: $0.range), $0.range) }
    }

    static func sadele(_ w: String) -> String {
        var s = w.lowercased()
        if s.hasSuffix("'s") || s.hasSuffix("’s") { s = String(s.dropLast(2)) }
        return String(s.unicodeScalars.filter { u in
            (u.value >= 0x61 && u.value <= 0x7A) || (u.value >= 0xE0 && u.value <= 0xF6) || (u.value >= 0xF8 && u.value <= 0xFF) || u == "'"
        }.map(Character.init))
    }

    static func govdeler(_ w: String) -> [String] {
        var g: [String] = []
        func ekle(_ x: String) { if x.count > 1 { g.append(x) } }
        func kes(_ n: Int) -> String { String(w.dropLast(n)) }
        if w.hasSuffix("ies") { ekle(kes(3) + "y"); ekle(kes(2)) }
        if w.hasSuffix("es") { ekle(kes(2)); ekle(kes(1)) }
        if w.hasSuffix("s") { ekle(kes(1)) }
        if w.hasSuffix("ied") { ekle(kes(3) + "y") }
        if w.hasSuffix("ed") { ekle(kes(2)); ekle(kes(1)) }
        if w.hasSuffix("ing") { ekle(kes(3)); ekle(kes(3) + "e") }
        if w.hasSuffix("er") { ekle(kes(2)); ekle(kes(1)) }
        if w.hasSuffix("est") { ekle(kes(3)); ekle(kes(2)) }
        if w.hasSuffix("ly") { ekle(kes(2)); ekle(kes(2) + "e") }
        if w.hasSuffix("ily") { ekle(kes(3) + "y") }
        if w.hasSuffix("ness") { ekle(kes(4)) }
        // çift ünsüz: stopped -> stop, running -> run
        if let m = ciftUnsuz.firstMatch(in: w, range: NSRange(location: 0, length: (w as NSString).length)) {
            let ns = w as NSString
            ekle(ns.substring(with: m.range(at: 1)) + ns.substring(with: m.range(at: 2)))
        }
        return g
    }
    private static let ciftUnsuz = try! NSRegularExpression(pattern: "^(.*?)([bcdfglmnprstz])\\2(ed|ing|er|est|y)$")

    /// Damerau-Levenshtein, `sinir`da kesilir.
    static func mesafe(_ a: String, _ b: String, _ sinir: Int) -> Int {
        let a = Array(a), b = Array(b)
        let n = a.count, m = b.count
        if abs(n - m) > sinir { return sinir + 1 }
        if n == 0 || m == 0 { return max(n, m) }
        var onceki2: [Int] = []
        var onceki = Array(0...m)
        for i in 1...n {
            var simdi = Array(repeating: 0, count: m + 1)
            simdi[0] = i
            var enAz = i
            for j in 1...m {
                let bedel = a[i - 1] == b[j - 1] ? 0 : 1
                var d = min(simdi[j - 1] + 1, onceki[j] + 1, onceki[j - 1] + bedel)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] { d = min(d, onceki2[j - 2] + 1) }
                simdi[j] = d
                enAz = min(enAz, d)
            }
            if enAz > sinir { return sinir + 1 }
            onceki2 = onceki; onceki = simdi
        }
        return onceki[m]
    }

    /// Kelime kelime fark (en uzun ortak alt dizi). Aşırı uzun metinde kilitlenmesin diye 600 kelimede kesilir.
    static func fark(_ asil: String, _ deneme: String) -> Fark {
        let A = Array(kelimeler(asil).prefix(600)), B = Array(kelimeler(deneme).prefix(600))
        let a = A.map(sadele), b = B.map(sadele)
        let n = a.count, m = b.count
        var L = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    L[i][j] = a[i] == b[j] ? L[i + 1][j + 1] + 1 : max(L[i + 1][j], L[i][j + 1])
                }
            }
        }
        var ops: [FarkOp] = []
        var i = 0, j = 0, ayni = 0
        while i < n && j < m {
            if a[i] == b[j] { ops.append(.init(t: "ok", s: A[i])); ayni += 1; i += 1; j += 1 }
            else if L[i + 1][j] >= L[i][j + 1] { ops.append(.init(t: "eksik", s: A[i])); i += 1 }
            else { ops.append(.init(t: "fazla", s: B[j])); j += 1 }
        }
        while i < n { ops.append(.init(t: "eksik", s: A[i])); i += 1 }
        while j < m { ops.append(.init(t: "fazla", s: B[j])); j += 1 }
        return Fark(ops: ops, ayni: ayni, toplam: n, yuzde: n > 0 ? Int((100.0 * Double(ayni) / Double(n)).rounded()) : 0, metin: asil)
    }

    // MARK: Hata türleri (tezgah_arsiv.py'deki hata_turleri() ile aynı kural)

    static let artikel: Set<String> = ["a", "an", "the"]
    static let edat = Set(("at on in to for of with from by about into onto over under after before during until since " +
        "through across behind between near next around up down off out without within against among towards toward per like upon beside beyond").split(separator: " ").map(String.init))
    static let yardimci = Set("is are was were be been being am have has had do does did will would shall should can could may might must 's 're 've 'd 'll".split(separator: " ").map(String.init))
    static let htAd: [String: String] = ["artikel": "artikel", "edat": "edat", "zaman": "yardımcı fiil · zaman",
                                         "biçim": "biçim · çekim", "yazım": "yazım", "kelime": "kelime"]

    static let duzensiz: [String: String] = {
        var d: [String: String] = [:]
        let tablo = "be was were been|begin began begun|break broke broken|bring brought|build built|buy bought|catch caught|choose chose chosen|come came|do did done|draw drew drawn|drink drank drunk|drive drove driven|eat ate eaten|fall fell fallen|feel felt|find found|fly flew flown|forget forgot forgotten|get got gotten|give gave given|go went gone|grow grew grown|have had|hear heard|hold held|keep kept|know knew known|leave left|lend lent|lose lost|make made|mean meant|meet met|pay paid|ride rode ridden|ring rang rung|rise rose risen|run ran|say said|see saw seen|sell sold|send sent|sing sang sung|sit sat|sleep slept|speak spoke spoken|spend spent|stand stood|steal stole stolen|swim swam swum|take took taken|teach taught|tell told|think thought|throw threw thrown|understand understood|wake woke woken|wear wore worn|win won|write wrote written|lead led|feed fed|hide hid hidden|bite bit bitten|shake shook shaken|hang hung|shine shone|shoot shot|show showed shown|fight fought|seek sought|beat beaten|become became|bend bent|blow blew blown|deal dealt|dig dug|lie lay lain|stick stuck|strike struck|tear tore torn|forgive forgave forgiven|freeze froze frozen|bear bore born|light lit|feel felt|bring brought|is are am"
        for g in tablo.split(separator: "|") {
            let p = g.split(separator: " ").map(String.init)
            for w in p { d[w] = p[0] }
        }
        return d
    }()

    static func govdeKume(_ w: String) -> Set<String> {
        var k = Set([w] + govdeler(w))
        if let d = duzensiz[w] { k.insert(d) }
        return k
    }

    static func hataTurleri(_ atlanan: [String], _ fazladan: [String]) -> [String: Int] {
        var E = atlanan.map(sadele).filter { !$0.isEmpty }
        var F = fazladan.map(sadele).filter { !$0.isEmpty }
        var say: [String: Int] = [:]
        func ekle(_ k: String) { say[k, default: 0] += 1 }
        for e in E {
            let ge = govdeKume(e)
            if let j = F.firstIndex(where: { $0 != e && !govdeKume($0).isDisjoint(with: ge) }) {
                ekle("biçim"); if let k = E.firstIndex(of: e) { E.remove(at: k) }; F.remove(at: j)
            }
        }
        for e in E {
            if e.count < 4 { continue }
            if let j = F.firstIndex(where: { abs($0.count - e.count) <= 2 && mesafe(e, $0, 2) <= (e.count <= 5 ? 1 : 2) }) {
                ekle("yazım"); if let k = E.firstIndex(of: e) { E.remove(at: k) }; F.remove(at: j)
            }
        }
        for w in E + F { ekle(artikel.contains(w) ? "artikel" : edat.contains(w) ? "edat" : yardimci.contains(w) ? "zaman" : "kelime") }
        return say
    }

    static func iskelet(_ en: String) -> String {
        var s = en
        for (w, r) in araliklar(en).reversed() {
            let yeni = String(w.prefix(1)) + String(repeating: "·", count: max(0, w.count - 1))
            s = (s as NSString).replacingCharacters(in: r, with: yeni)
        }
        return s
    }

    static func hedefe(_ ham: String, _ kume: Set<String>) -> String? {
        let w = sadele(ham)
        if kume.contains(w) { return w }
        return govdeler(w).first { kume.contains($0) }
    }

    static let dolguDisi: Set<String> = Set(("the a an and or but if of to in on at for with from by as is are was were be been being it its this that " +
        "these those i you he she we they me him her us them my your his our their not no so too very can will would do does did have has " +
        "had there here when then than only also about up out all one").split(separator: " ").map(String.init))
}

// MARK: - Gramer sezici — kalıptan hızlı, KESİN OLMAYAN etiketleme

struct GramerTespit { var etiket: String; var aciklama: String; var parca: String?; var indis: Int?; var guven: String }

enum Sezici {
    static let ppDuzensiz = "written done made given taken seen known shown built sent bought brought caught taught thought found held kept left lost meant paid read said sold told understood won broken chosen driven eaten fallen forgotten frozen grown hidden ridden risen spoken stolen thrown worn woken begun drunk rung sung sunk swum gone come become run put cut hit let set cost hurt spent felt slept met sat stood born".split(separator: " ").joined(separator: "|")
    static var pp: String { "(?:\\w+ed|\(ppDuzensiz))" }
    static let edSifat: Set<String> = Set("tired interested bored excited worried confused surprised pleased satisfied frightened scared annoyed embarrassed disappointed amazed relaxed married engaged involved located based crowded closed opened used supposed allowed known concerned prepared determined experienced qualified advanced complicated detailed limited related dedicated educated organized".split(separator: " ").map(String.init))

    struct Kural { var ad: String; var ac: String; var re: NSRegularExpression; var kosul: ((String, NSTextCheckingResult, NSString) -> Bool)? }
    static func r(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p, options: [.caseInsensitive]) }

    static let kurallar: [Kural] = [
        Kural(ad: "Reported Speech", ac: "Başkasının sözü aktarılıyor — zaman bir adım geri kayar",
              re: r("\\b(said|told|explained|replied|mentioned)\\b[^.?!]*\\bthat\\b|\\b(asked|wondered)\\s+(if|whether)\\b"), kosul: nil),
        Kural(ad: "Third Conditional", ac: "Geçmişte gerçekleşmemiş bir durumun sonucu",
              re: r("\\bif\\b[^.?!]*\\bhad\\b[^.?!]*\\bwould have\\b|\\bwould have\\s+\\w+"),
              kosul: { c, _, _ in c.range(of: "\\bif\\b", options: .regularExpression) != nil && c.range(of: "\\bhad\\b", options: .regularExpression) != nil }),
        Kural(ad: "Second Conditional", ac: "Gerçek dışı ya da hayali bir durum", re: r("\\bif\\b[^.?!]*\\bwould\\b"), kosul: nil),
        Kural(ad: "First Conditional", ac: "Gerçekleşmesi mümkün bir koşul", re: r("\\bif\\b[^.?!]*\\bwill\\b"), kosul: nil),
        Kural(ad: "Modal + have", ac: "Geçmişe dair bir tahmin ya da çıkarım",
              re: r("\\b(must|might|could|may|can'?t|cannot)\\s+have\\s+\(pp)\\b"), kosul: nil),
        Kural(ad: "Present Perfect Continuous", ac: "Geçmişte başlayıp hâlâ süren eylem", re: r("\\b(have|has)\\s+been\\s+\\w+ing\\b"), kosul: nil),
        Kural(ad: "Past Perfect Continuous", ac: "Geçmişte bir ana kadar sürmüş eylem", re: r("\\bhad\\s+been\\s+\\w+ing\\b"), kosul: nil),
        Kural(ad: "Past Perfect", ac: "Geçmişte başka bir andan önce biten eylem",
              re: r("\\bhad\\s+(?:just\\s+|already\\s+|never\\s+|ever\\s+|recently\\s+)?\(pp)\\b"), kosul: nil),
        Kural(ad: "Passive Voice", ac: "Eylemi yapan değil, eylemden etkilenen özne",
              re: r("\\b(?:is|are|was|were|been|being)\\s+(\(pp))\\b"),
              kosul: { _, m, ns in !edSifat.contains(ns.substring(with: m.range(at: 1)).lowercased()) }),
        Kural(ad: "Present Perfect", ac: "Geçmişte olan ama şimdiyle bağlantılı bir eylem",
              re: r("\\b(?:have|has)\\s+(?:just\\s+|already\\s+|never\\s+|ever\\s+|recently\\s+)?\(pp)\\b"), kosul: nil),
        Kural(ad: "Relative Clause", ac: "Bir ismi tanımlayan ek cümlecik", re: r("\\b(?:who|which|whose|whom)\\b"),
              kosul: { c, _, _ in c.range(of: "^\\s*(who|which|whose|whom)\\b", options: [.regularExpression, .caseInsensitive]) == nil }),
        Kural(ad: "Superlative", ac: "En üstün olanı belirtme", re: r("\\bthe\\s+\\w+est\\b|\\bthe most\\s+\\w+"), kosul: nil),
        Kural(ad: "Comparative", ac: "İki şeyi karşılaştırma", re: r("\\b\\w+er than\\b|\\bmore\\s+\\w+\\s+than\\b"), kosul: nil),
        Kural(ad: "Future", ac: "Gelecek zaman", re: r("\\b(?:will|won'?t|going to)\\b\\s*\\w*"), kosul: nil),
    ]

    static func tespit(_ cumle: String) -> GramerTespit {
        if cumle.trimmingCharacters(in: .whitespaces).isEmpty { return .init(etiket: "—", aciklama: "Henüz cümle yok", parca: nil, indis: nil, guven: "yok") }
        let ns = cumle as NSString
        for k in kurallar {
            guard let m = k.re.firstMatch(in: cumle, range: NSRange(location: 0, length: ns.length)) else { continue }
            if let ks = k.kosul, !ks(cumle.lowercased(), m, ns) { continue }
            return .init(etiket: k.ad, aciklama: k.ac, parca: ns.substring(with: m.range), indis: m.range.location, guven: "tahmin")
        }
        return .init(etiket: "Temel yapı", aciklama: "Belirgin bir kalıp tespit edilmedi", parca: nil, indis: nil, guven: "yok")
    }
}

extension String {
    /// UTF-16 konumuyla dilim (JS'in slice'ı gibi).
    func u16(_ bas: Int, _ son: Int? = nil) -> String {
        let ns = self as NSString
        let b = max(0, min(bas, ns.length)), e = max(b, min(son ?? ns.length, ns.length))
        return ns.substring(with: NSRange(location: b, length: e - b))
    }
}
