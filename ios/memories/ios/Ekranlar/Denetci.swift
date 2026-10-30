// Telefonda üretilen metnin denetimi — gun.py derle_kurma'nın ve oncalisma olc'nin (K3) Swift karşılığı.
// Ölçüler brief.json › sinirlar'dan, kelime havuzu paket/bilinen.json'dan gelir (gun.py brief --json yazar).
// Python'daki kurallar değişirse burası da değişir: govdeler · gramer_gecisi · birim.kokler.
import Foundation

// MARK: - brief.json · bilinen.json

struct Brief: Codable {
    struct Sinirlar: Codable {
        var cumle: [Int]                // hedef (brief bütçesi) 12-15
        var kelime: [Int]               // hedef 140-170
        var cumle_derle: [Int]          // derle_kurma kabul bandı 11-16
        var kelime_derle: [Int]         // 130-185
        var tanidik_oran: Double        // K3 ≥ 0,90
        var yeni_gecis_cumle: Int       // yeni kelime ≥2 ayrı cümlede
        var yanki_gecis: Int
        var tanidik_gecis: Int
        var konu_gecis: Int             // sahne yapısı metinde ≥3 kez
        var konulu_cumle: Int           // ≥4 cümlede konu etiketi
        var ozet_min: Int               // Türkçe özet ≥60 harf
    }
    var gun: Int
    var mod: String?
    var faz: Int?
    var sahne_konulari: [String]
    var yeni: [Sozcuk]
    var yedek: [Sozcuk]?
    var yanki: [Sozcuk]
    var tanidik: [Sozcuk]
    var sinirlar: Sinirlar
    var bilinen: String?
    var uretildi: String?

    var hedefler: [Sozcuk] { yeni + yanki + tanidik }
}

struct Bilinen: Codable {
    var bilinen: [String]               // K3: kullanıcının bildiği + Oxford 3000
    var havuz: [String]                 // derle_kurma: henüz öğrenilmemiş Oxford kelimeleri
    var yardimci: [String]
    var cogul: [String: String]
    var duzensiz: [String: [String]]    // kök → biçimler
    var onek: [String]
}

// MARK: - Denetçi

struct Denetci {
    let brief: Brief
    let bilinenKume: Set<String>
    let havuz: Set<String>
    let yardimci: Set<String>
    let cogul: [String: String]
    let duzensizKok: [String: [String]]  // biçim → kökler
    let onek: [String]
    let hedef: Set<String>

    init(brief: Brief, bilinen b: Bilinen) {
        self.brief = brief
        bilinenKume = Set(b.bilinen)
        havuz = Set(b.havuz)
        yardimci = Set(b.yardimci)
        cogul = b.cogul
        var d: [String: [String]] = [:]
        for (kok, bicimler) in b.duzensiz { for x in bicimler { d[x, default: []].append(kok) } }
        duzensizKok = d
        onek = b.onek
        hedef = Set(brief.hedefler.map { $0.w.lowercased() })
    }

    // gun.py KELIME_RE
    static func kelimeler(_ s: String) -> [String] {
        eslesmeler(#"[A-Za-z]+(?:['’][A-Za-z]+)*"#, s)
    }

    static func eslesmeler(_ desen: String, _ s: String) -> [String] {
        guard let r = try? NSRegularExpression(pattern: desen) else { return [] }
        let ns = s as NSString
        return r.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    /// gun.py govdeler: motor'un çekim çözümünün kısa hâli.
    static func govdeler(_ w: String) -> Set<String> {
        var g: Set<String> = [w]
        let ekler: [(String, String)] = [("ies", "y"), ("ied", "y"), ("ier", "y"), ("iest", "y"), ("es", ""), ("s", ""),
                                        ("ed", ""), ("ed", "e"), ("ing", ""), ("ing", "e"), ("er", ""), ("est", ""), ("ly", "")]
        for (son, yerine) in ekler where w.hasSuffix(son) && w.count - son.count > 1 {
            g.insert(String(w.dropLast(son.count)) + yerine)
        }
        if w.count > 3, w.last == w.dropLast().last { g.insert(String(w.dropLast())) }
        return g
    }

    /// gun.py gecis_sayisi — çok kelimeli maddeler (so-called, make-up) kelime kelime değil, metin içinde aranır.
    static func gecis(_ metin: String, _ kelime: String) -> Int {
        let k = kelime.lowercased()
        if k.contains("-") || k.contains(" ") {
            return eslesmeler("\\b" + NSRegularExpression.escapedPattern(for: k) + "\\b", metin.lowercased()).count
        }
        return kelimeler(metin.lowercased()).filter { govdeler($0).contains(k) }.count
    }

    /// gun.py gramer_gecisi — kaba ama aynı sayım; -1 = bilinmeyen konu.
    static func gramer(_ metin: String, _ konu: String) -> Int {
        let m = metin.lowercased(), ad = konu.lowercased()
        func say(_ d: String) -> Int { eslesmeler(d, m).count }
        if ad.contains("present perfect") { return say(#"\b(have|has|haven't|hasn't)\s+(\w+\s+){0,2}\w+(ed|en|t)\b"#) }
        if ad.contains("past simple") || ad.contains("past perfect") { return say(#"\b(had|was|were|went|came|got|said|took|made|saw)\b"#) }
        if ad.contains("article") { return say(#"\b(a|an|the)\b"#) }
        if ad.contains("passive") { return say(#"\b(is|are|was|were|been)\s+\w+(ed|en)\b"#) }
        if ad.contains("relative") { return say(#"\b(who|which|that|whose|where)\b"#) }
        if ad.contains("conditional") { return say(#"\bif\b"#) }
        if ad.contains("question") { return metin.filter { $0 == "?" }.count }
        if ad.contains("reported speech") || ad.contains("indirect") {
            return say(#"\b(said|told|asked|explained|wondered|replied|promised|mentioned|thought)\b\s+\w*\s*(that|if|whether|why|what|where|when|how|who)\b"#)
        }
        if ad.contains("comparative") || ad.contains("superlative") { return say(#"\b(more|most|less|least|\w+er than|\w+est)\b"#) }
        if ad.contains("gerund") || ad.contains("infinitive") { return say(#"\b(to\s+\w+|\w+ing)\b"#) }
        if ad.contains("future") { return say(#"\b(will|going to|shall)\b"#) }
        if ad.contains("modal") { return say(#"\b(must|should|have to|has to|ought)\b"#) }
        return -1
    }

    /// Tek cümlenin taşıması gereken yapının kesin işareti. Sayım (yukarısı) gevşektir: "future" her `will`i sayar;
    /// üretimde cümleyi istenen yapıya zorlamak için daha dar desen kullanılır.
    static func yapiVar(_ cumle: String, _ yapi: Yapi) -> Bool {
        let m = cumle.lowercased()
        switch yapi {
        case .futurePerfect: return !eslesmeler(#"\bwill( not|n't)? have\s+\w+(ed|en|t|wn|ne)\b"#, m).isEmpty
        case .futureContinuous: return !eslesmeler(#"\bwill( not|n't)? be\s+\w+ing\b"#, m).isEmpty
        case .passive: return !eslesmeler(#"\b(is|are|was|were|been)\s+\w+(ed|en)\b"#, m).isEmpty
        case .konu(let k): return gramer(cumle, k) != 0
        }
    }

    /// birim.kokler — K3 tanıdıklık ölçümü için olası sözlük maddeleri.
    func kokler(_ dt: String) -> [String] {
        var k = [dt]
        if let c = cogul[dt] { k.append(c) }
        k += duzensizKok[dt] ?? []
        if dt.contains("'") { k.append(String(dt.split(separator: "'").first ?? "")) }
        for o in onek where dt.hasPrefix(o) && dt.count > o.count + 3 { k.append(String(dt.dropFirst(o.count))) }
        for ek in ["s", "es", "ed", "ing", "ly", "d", "er", "est", "n", "ies", "ied"] where dt.hasSuffix(ek) && dt.count >= ek.count + 3 {
            let kok = String(dt.dropLast(ek.count))
            k += [kok, kok + "e"]
            if ek == "ies" || ek == "ied" { k.append(kok + "y") }
            if kok.count > 2, kok.last == kok.dropLast().last { k.append(String(kok.dropLast())) }
        }
        return k
    }

    /// yanki.olc: tanıdık oran (K3) ve listede olmayanlar.
    func k3(_ metin: String) -> (oran: Double, yabanci: [String]) {
        let toks = Denetci.eslesmeler(#"[A-Za-z][A-Za-z']*"#, metin).map { $0.lowercased() }
        let yabanci = toks.filter { t in !kokler(t).contains { bilinenKume.contains($0) } }
        let oran = 1 - Double(yabanci.count) / Double(max(toks.count, 1))
        return (oran, Array(Set(yabanci)).sorted())
    }

    /// derle_kurma 1: hedef olmayan havuz kelimesi (bilinmeyen) kaçmasın.
    func bilinmeyenler(_ metin: String) -> [String] {
        var b: [String] = []
        for w in Denetci.kelimeler(metin.lowercased()) where !yardimci.contains(w) {
            let g = Denetci.govdeler(w)
            if !g.isDisjoint(with: havuz) && g.isDisjoint(with: hedef) && !b.contains(w) { b.append(w) }
        }
        return b
    }

    // MARK: Tek cümle (üretim sırasında)

    struct Plan {
        var kelimeler: [String]         // bu cümlede geçmesi gereken hedefler
        var yapi: Yapi?
        var konu: String?               // paket.json'daki etiket
    }

    func cumleSorunlari(_ c: String, _ plan: Plan) -> [String] {
        var s: [String] = []
        let n = Denetci.kelimeler(c).count
        if n < 6 { s.append("çok kısa (\(n))") }
        if n > 22 { s.append("çok uzun (\(n))") }
        if c.unicodeScalars.contains(where: { $0.value > 0x2FF && !"’‘“”—–".unicodeScalars.contains($0) }) { s.append("İngilizce değil") }
        for w in plan.kelimeler where Denetci.gecis(c, w) == 0 { s.append("'\(w)' yok") }
        if let y = plan.yapi, !Denetci.yapiVar(c, y) { s.append("\(y.ad) yok") }
        let b = bilinmeyenler(c)
        if !b.isEmpty { s.append("bilinmeyen: " + b.joined(separator: ", ")) }
        return s
    }

    // MARK: Bütün metin (derle_kurma)

    struct Sonuc {
        var uyari: [String]
        var kelime: Int
        var cumle: Int
        var k3: Double
        var gecis: [String: (Int, Int)]     // kelime → (kez, cümle)
        var gramer: [String: Int]
        var tamam: Bool { uyari.isEmpty }
    }

    func denetle(_ cumleler: [(en: String, tr: String?, konu: String?)], ozet: String?) -> Sonuc {
        let sn = brief.sinirlar
        let metin = cumleler.map(\.en).joined(separator: " ")
        let kelime = Denetci.kelimeler(metin).count
        var u: [String] = []
        let b = bilinmeyenler(metin)
        if !b.isEmpty { u.append("havuzdan \(b.count) bilinmeyen kelime kaçmış: " + b.joined(separator: ", ")) }
        var gecis: [String: (Int, Int)] = [:]
        for w in brief.hedefler.map({ $0.w.lowercased() }) {
            gecis[w] = (Denetci.gecis(metin, w), cumleler.filter { Denetci.gecis($0.en, w) > 0 }.count)
        }
        let azYeni = brief.yeni.map { $0.w.lowercased() }.filter { (gecis[$0]?.1 ?? 0) < sn.yeni_gecis_cumle }
        if !azYeni.isEmpty { u.append("\(azYeni.count) yeni kelime \(sn.yeni_gecis_cumle) ayrı cümlede geçmiyor: " + azYeni.joined(separator: ", ")) }
        let yokTanidik = brief.tanidik.map { $0.w.lowercased() }.filter { (gecis[$0]?.0 ?? 0) < sn.tanidik_gecis }
        if !yokTanidik.isEmpty { u.append("\(yokTanidik.count) tanıdık kelime metinde yok: " + yokTanidik.joined(separator: ", ")) }
        let yokYanki = brief.yanki.map { $0.w.lowercased() }.filter { (gecis[$0]?.0 ?? 0) < sn.yanki_gecis }
        if !yokYanki.isEmpty { u.append("\(yokYanki.count) yankı kelimesi metinde yok: " + yokYanki.joined(separator: ", ")) }
        var gramer: [String: Int] = [:]
        for k in brief.sahne_konulari {
            let n = Denetci.gramer(metin, k)
            gramer[k] = n
            if n >= 0 && n < sn.konu_gecis { u.append("'\(k)' metinde yalnız \(n) kez geçiyor — en az \(sn.konu_gecis) olmalı") }
        }
        let trsiz = cumleler.enumerated().filter { ($0.element.tr ?? "").isEmpty }.map { $0.offset + 1 }
        if !trsiz.isEmpty { u.append("\(trsiz.count) cümlenin Türkçesi yok") }
        if (ozet ?? "").trimmingCharacters(in: .whitespaces).count < sn.ozet_min { u.append("ozet yok ya da çok kısa") }
        if !(sn.kelime_derle[0]...sn.kelime_derle[1]).contains(kelime) { u.append("metin \(kelime) kelime — hedef \(sn.kelime[0])-\(sn.kelime[1])") }
        if !(sn.cumle_derle[0]...sn.cumle_derle[1]).contains(cumleler.count) { u.append("\(cumleler.count) cümle — hedef \(sn.cumle[0])-\(sn.cumle[1])") }
        let konulu = cumleler.filter { $0.konu != nil }.count
        if konulu < sn.konulu_cumle { u.append("yalnız \(konulu) cümlede konu etiketi var — en az \(sn.konulu_cumle)") }
        // K3 (≥ %90) Mac'te anlatımın tamamı üstünden ölçülür (oncalisma olc), metnin yalnızı değil: paketle'de bakılır.
        return Sonuc(uyari: u, kelime: kelime, cumle: cumleler.count, k3: k3(metin).oran, gecis: gecis, gramer: gramer)
    }
}

/// Bir cümleye verilen yapı. Sahne konusu adından çıkarılır ("Future Perfect & Future Continuous" iki yapı verir).
enum Yapi: Hashable {
    case futurePerfect, futureContinuous, passive
    case konu(String)

    var ad: String {
        switch self {
        case .futurePerfect: "Future Perfect"
        case .futureContinuous: "Future Continuous"
        case .passive: "Passive Voice"
        case .konu(let k): k
        }
    }
    /// Modele verilen kısa kalıp.
    var kalip: String {
        switch self {
        case .futurePerfect: "Future Perfect: will have + past participle (e.g. \"will have finished\")"
        case .futureContinuous: "Future Continuous: will be + -ing (e.g. \"will be waiting\")"
        // derle'nin sayımı yalnız -ed/-en ortacı tanır ("was built" sayılmaz)
        case .passive: "Passive Voice: is/are/was/were + past participle ending in -ed or -en (e.g. \"was cleaned\", \"were taken\")"
        case .konu(let k): k
        }
    }

    static func cikar(_ konu: String) -> [Yapi] {
        let a = konu.lowercased()
        var y: [Yapi] = []
        if a.contains("future perfect") { y.append(.futurePerfect) }
        if a.contains("future continuous") { y.append(.futureContinuous) }
        if a.contains("passive") { y.append(.passive) }
        return y.isEmpty ? [.konu(konu)] : y
    }
}
