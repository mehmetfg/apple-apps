// Kıvılcım ortak çekirdeği — Mac ve iPhone aynı dosyayı derler (yalnız Foundation).
// Veri klasörü: vault/05 - Notlar/Fikirler/Kıvılcım
//   ses/<ay>/<kimlik>.m4a + .json   cihazın bıraktığı kayıt + künye
//   olay/<cihaz>.jsonl              elle düzeltmeler (her cihaz yalnız kendi dosyasına yazar)
//   dizin.json                      Mac'teki işleme hattının (isle.py) özeti: döküm, başlık, alan, amaç
//   siniflar.json                   alan/amaç sözlüğü (isle.py kopyalar)
import Foundation

let veriKlasoruYolu = "05 - Notlar/Fikirler/Kıvılcım"

// MARK: Dizin

struct Oge: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var tarih: String
    var cihaz: String
    var sure: Double
    var kalite: String
    var boyut: Int
    var ses: String
    var metin: String
    var metin_kaynak: String
    var baslik: String
    var baslik_kaynak: String
    var ozet: String
    var alan: String
    var amac: String
    var etiketler: [String]
    var yildiz: Bool
    var durum: String          // hazir · bekliyor · hata · yerel (henüz Mac'e ulaşmadı)
    var not: String

    enum CodingKeys: String, CodingKey {
        case id, tarih, cihaz, sure, kalite, boyut, ses, metin, metin_kaynak, baslik, baslik_kaynak, ozet, alan, amac, etiketler, yildiz, durum, not
    }

    init(id: String, tarih: String, cihaz: String, sure: Double, kalite: String, boyut: Int, ses: String,
         metin: String = "", baslik: String = "İşleniyor…", alan: String = "genel", amac: String = "dusunce", durum: String = "yerel") {
        self.id = id; self.tarih = tarih; self.cihaz = cihaz; self.sure = sure; self.kalite = kalite; self.boyut = boyut
        self.ses = ses; self.metin = metin; metin_kaynak = metin.isEmpty ? "" : "cihaz"; self.baslik = baslik
        baslik_kaynak = "kural"; ozet = ""; self.alan = alan; self.amac = amac; etiketler = []; yildiz = false
        self.durum = durum; not = ""
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        tarih = (try? c.decode(String.self, forKey: .tarih)) ?? ""
        cihaz = (try? c.decode(String.self, forKey: .cihaz)) ?? "?"
        sure = (try? c.decode(Double.self, forKey: .sure)) ?? 0
        kalite = (try? c.decode(String.self, forKey: .kalite)) ?? ""
        boyut = (try? c.decode(Int.self, forKey: .boyut)) ?? 0
        ses = (try? c.decode(String.self, forKey: .ses)) ?? ""
        metin = (try? c.decode(String.self, forKey: .metin)) ?? ""
        metin_kaynak = (try? c.decode(String.self, forKey: .metin_kaynak)) ?? ""
        baslik = (try? c.decode(String.self, forKey: .baslik)) ?? "Adsız"
        baslik_kaynak = (try? c.decode(String.self, forKey: .baslik_kaynak)) ?? "kural"
        ozet = (try? c.decode(String.self, forKey: .ozet)) ?? ""
        alan = (try? c.decode(String.self, forKey: .alan)) ?? "genel"
        amac = (try? c.decode(String.self, forKey: .amac)) ?? "dusunce"
        etiketler = (try? c.decode([String].self, forKey: .etiketler)) ?? []
        yildiz = (try? c.decode(Bool.self, forKey: .yildiz)) ?? false
        durum = (try? c.decode(String.self, forKey: .durum)) ?? "hazir"
        not = (try? c.decode(String.self, forKey: .not)) ?? ""
    }

    var zaman: Date { Zaman.coz(tarih) ?? .distantPast }
    var sureMetni: String { Zaman.sure(sure) }
    var islendi: Bool { durum == "hazir" }
}

struct Dizin: Codable, Sendable {
    var uretim: String?
    var toplam: Int?
    var toplam_sn: Double?
    var toplam_bayt: Int?
    var ogeler: [Oge]
}

// MARK: Sınıflar

struct Alan: Codable, Identifiable, Hashable, Sendable {
    var id: String; var ad: String; var simge: String; var renk: String; var disiplin: String?; var kelimeler: [String]
}

struct Amac: Codable, Identifiable, Hashable, Sendable {
    var id: String; var ad: String; var simge: String; var aciklama: String; var kelimeler: [String]; var kalip: String?
}

struct Siniflar: Codable, Sendable {
    var alanlar: [Alan]
    var amaclar: [Amac]
    var dolgu: [String]?

    func alan(_ id: String) -> Alan { alanlar.first { $0.id == id } ?? alanlar.last! }
    func amac(_ id: String) -> Amac { amaclar.first { $0.id == id } ?? amaclar.last! }

    static func yukle(_ u: URL?) -> Siniflar {
        if let u, let v = try? Data(contentsOf: u), let s = try? JSONDecoder().decode(Siniflar.self, from: v) { return s }
        return varsayilan
    }

    /// Dosya okunamazsa — yalnız adlar ve renkler (sınıflama sözlüğü boş).
    static let varsayilan = Siniflar(alanlar: [
        Alan(id: "felsefe", ad: "Felsefe", simge: "building.columns", renk: "#8E6FD8", disiplin: "felsefe", kelimeler: ["felsef", "kant", "hegel", "heidegger", "varlık", "ahlak", "etik", "hakikat", "kavram"]),
        Alan(id: "dil", ad: "İngilizce", simge: "character.bubble", renk: "#2F9BD6", disiplin: "dil", kelimeler: ["ingilizce", "english", "kelime", "gramer"]),
        Alan(id: "yazilim", ad: "Yazılım", simge: "chevron.left.forwardslash.chevron.right", renk: "#2BB673", disiplin: "sistem", kelimeler: ["uygulama", "yazılım", "kod", "widget", "telefon", "claude"]),
        Alan(id: "yazarlik", ad: "Yazarlık", simge: "pencil.and.scribble", renk: "#E2884A", disiplin: "edebiyat", kelimeler: ["yazı", "makale", "deneme", "roman", "şiir"]),
        Alan(id: "finans", ad: "Finans & İş", simge: "chart.line.uptrend.xyaxis", renk: "#D4A72C", disiplin: "finans", kelimeler: ["para", "yatırım", "faiz", "bütçe"]),
        Alan(id: "bilim", ad: "Kuantum & Bilim", simge: "atom", renk: "#4C6FE0", disiplin: "fizik", kelimeler: ["kuantum", "fizik", "matematik"]),
        Alan(id: "saglik", ad: "Sağlık & Beden", simge: "heart.text.square", renk: "#E0565B", disiplin: "", kelimeler: ["sağlık", "spor", "uyku", "doktor"]),
        Alan(id: "hayat", ad: "Aile & Hayat", simge: "house", renk: "#C46BB0", disiplin: "", kelimeler: ["aile", "çocuk", "ev", "arkadaş"]),
        Alan(id: "okuma", ad: "Kitap & Okuma", simge: "books.vertical", renk: "#7C8B5A", disiplin: "", kelimeler: ["kitap", "okumak"]),
        Alan(id: "genel", ad: "Genel", simge: "sparkles", renk: "#8A8F98", disiplin: "", kelimeler: []),
    ], amaclar: [
        Amac(id: "fikir", ad: "Fikir", simge: "lightbulb", aciklama: "kurulacak bir şey", kelimeler: ["fikir", "yapabilirim", "proje", "nasıl olur"], kalip: nil),
        Amac(id: "yapilacak", ad: "Yapılacak", simge: "checkmark.circle", aciklama: "eylem, hatırlatma", kelimeler: ["lazım", "gerek", "unutma", "yarın"], kalip: "m[ae]l[ıi]y[ıi]m\\b"),
        Amac(id: "soru", ad: "Soru", simge: "questionmark.bubble", aciklama: "merak, araştırılacak", kelimeler: ["neden", "nasıl", "acaba"], kalip: "\\?"),
        Amac(id: "yazi", ad: "Yazı", simge: "text.quote", aciklama: "metne girecek cümle", kelimeler: ["yazı", "paragraf", "taslak"], kalip: nil),
        Amac(id: "dusunce", ad: "Düşünce", simge: "cloud", aciklama: "gözlem, sezgi", kelimeler: [], kalip: nil),
    ], dolgu: ["şey", "evet", "tamam", "yani", "aklıma bir şey geldi", "aklıma geldi"])
}

// MARK: Kural sınıflayıcı (isle.py'nin aynısı, kısaltılmış — telefonda Mac'ten önce geçici başlık için)

enum Kural {
    static func kucuk(_ s: String) -> String {
        s.replacingOccurrences(of: "I", with: "ı").replacingOccurrences(of: "İ", with: "i").lowercased()
    }

    static func buyukBas(_ s: String) -> String {
        guard let f = s.first else { return s }
        let b = f == "i" ? "İ" : f == "ı" ? "I" : String(f).uppercased()
        return b + s.dropFirst()
    }

    static func kelimeler(_ k: String) -> [String] {
        let ayrac = CharacterSet.letters.union(.decimalDigits).union(CharacterSet(charactersIn: "'’")).inverted
        return k.components(separatedBy: ayrac).filter { !$0.isEmpty }
    }

    static func puan(_ k: String, _ kel: [String], _ liste: [String]) -> Int {
        var p = 0
        for a0 in liste {
            let a = kucuk(a0)
            if a.contains(" ") { if k.contains(a) { p += 2 } } else { p += kel.filter { $0.hasPrefix(a) }.count }
        }
        return p
    }

    static func alan(_ metin: String, _ s: Siniflar) -> String {
        let k = kucuk(metin), kel = kelimeler(k)
        var en = "genel", enp = 0
        for a in s.alanlar { let p = puan(k, kel, a.kelimeler); if p > enp { en = a.id; enp = p } }
        return en
    }

    static func amac(_ metin: String, _ s: Siniflar) -> String {
        let k = kucuk(metin), kel = kelimeler(k)
        var en = "dusunce", enp = 0
        for a in s.amaclar {
            var p = puan(k, kel, a.kelimeler)
            if let kalip = a.kalip, let r = try? NSRegularExpression(pattern: kalip) {
                p += 2 * r.numberOfMatches(in: k, range: NSRange(k.startIndex..., in: k))
            }
            if p > enp { en = a.id; enp = p }
        }
        return en
    }

    static func baslik(_ metin: String, _ s: Siniflar) -> String {
        let m = metin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !m.isEmpty else { return "Boş kayıt" }
        if kucuk(m).hasPrefix("başlık") {
            let geri = m.dropFirst(6).drop { " :,.".contains($0) }
            let ilk = geri.split(whereSeparator: { ",.!?\n".contains($0) }).first.map(String.init) ?? ""
            if !ilk.isEmpty { return buyukBas(ilk.split(separator: " ").prefix(9).joined(separator: " ")) }
        }
        let dolgu = (s.dolgu ?? []).map(kucuk).sorted { $0.count > $1.count }
        let cumleler = m.split(whereSeparator: { ".!?\n".contains($0) }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for (i, c) in cumleler.enumerated() {
            var t = c
            var degisti = true
            while degisti && !t.isEmpty {
                degisti = false
                let tk = kucuk(t)
                for d in dolgu where tk == d || tk.hasPrefix(d + " ") || tk.hasPrefix(d + ",") {
                    t = String(t.dropFirst(d.count)).trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:-")); degisti = true; break
                }
            }
            if let ilk = t.split(separator: ",").first, ilk.split(separator: " ").count >= 3 { t = String(ilk) }
            let kel = t.split(separator: " ")
            if kel.count >= 2 || (i == cumleler.count - 1 && !kel.isEmpty) {
                var b = kel.prefix(7).joined(separator: " ")
                if kel.count > 7 { b += "…" }
                return buyukBas(b)
            }
        }
        return "Adsız fikir"
    }
}

// MARK: Kalite

enum Kalite: String, CaseIterable, Identifiable, Sendable {
    case az, dengeli, net, yuksek
    var id: String { rawValue }
    var ad: String { ["az": "Tasarruf", "dengeli": "Dengeli", "net": "Net", "yuksek": "Yüksek"][rawValue]! }
    var hz: Int { [.az: 16_000, .dengeli: 16_000, .net: 24_000, .yuksek: 44_100][self]! }
    var bit: Int { [.az: 24_000, .dengeli: 32_000, .net: 48_000, .yuksek: 96_000][self]! }
    var kbDk: Int { bit * 60 / 8 / 1000 }
    var aciklama: String {
        switch self {
        case .az: "Whisper'ın rahat çözdüğü en küçük boy"
        case .dengeli: "Konuşma için en iyi denge (önerilen)"
        case .net: "Gürültülü ortam, uzak mikrofon"
        case .yuksek: "Müzik ya da ortam sesi de önemliyse"
        }
    }
    var ozet: String { "\(hz / 1000 == 44 ? "44,1" : String(hz / 1000)) kHz · \(bit / 1000) kbit/sn · ≈\(kbDk) KB/dk" }
}

// MARK: Künye (kaydın yanındaki .json)

struct Kunye: Codable, Sendable {
    var id: String
    var cihaz: String
    var zaman: String
    var sure: Double
    var kalite: String
    var dil: String
    var onMetin: String?
}

enum Kimlik {
    static func yeni(_ cihaz: String, _ t: Date = Date()) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd-HHmmss"
        let ek = String(UUID().uuidString.prefix(4)).lowercased()
        return "\(f.string(from: t))-\(cihaz)-\(ek)"
    }
    static func ay(_ t: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM"; return f.string(from: t)
    }
}

// MARK: Olay (elle düzeltme)

enum Olay {
    static func satir(hedef: String, tur: String, deger: Any, cihaz: String) -> Data {
        let o: [String: Any] = ["id": UUID().uuidString.lowercased(), "t": Zaman.iso(Date()), "hedef": hedef, "tur": tur, "deger": deger, "cihaz": cihaz]
        var v = (try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        v.append(0x0A)
        return v
    }

    /// Düzeltmeleri bir öğeye uygular (Mac henüz işlemediyse ekranda hemen görünsün diye).
    static func uygula(_ satirlar: Data, _ ogeler: inout [Oge]) {
        var son: [String: [String: (String, Any)]] = [:]
        for parca in satirlar.split(separator: 0x0A) {
            guard let o = try? JSONSerialization.jsonObject(with: Data(parca)) as? [String: Any],
                  let h = o["hedef"] as? String, let tur = o["tur"] as? String, let d = o["deger"] else { continue }
            let t = o["t"] as? String ?? ""
            if let e = son[h]?[tur], e.0 > t { continue }
            son[h, default: [:]][tur] = (t, d)
        }
        for i in ogeler.indices {
            guard let d = son[ogeler[i].id] else { continue }
            if let v = d["baslik"]?.1 as? String, !v.isEmpty { ogeler[i].baslik = v; ogeler[i].baslik_kaynak = "elle" }
            if let v = d["alan"]?.1 as? String, !v.isEmpty { ogeler[i].alan = v }
            if let v = d["amac"]?.1 as? String, !v.isEmpty { ogeler[i].amac = v }
            if let v = d["yildiz"]?.1 as? Bool { ogeler[i].yildiz = v }
        }
        ogeler.removeAll { son[$0.id]?["sil"]?.1 as? Bool == true }
    }
}

// MARK: Arama

enum Arama {
    static func katla(_ s: String) -> String {
        Kural.kucuk(s).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i")
    }

    /// Her kelime başlıkta, dökümde, özette, etikette ya da alan adında geçmeli.
    static func eslesir(_ o: Oge, _ sorgu: String, _ s: Siniflar) -> Bool {
        let parcalar = katla(sorgu).split(separator: " ").map(String.init)
        if parcalar.isEmpty { return true }
        let alan = [o.baslik, o.metin, o.ozet, o.etiketler.joined(separator: " "), s.alan(o.alan).ad, s.amac(o.amac).ad].joined(separator: " ")
        let k = katla(alan)
        return parcalar.allSatisfy { k.contains($0) }
    }

    /// Dökümde sorgunun geçtiği yerden kısa bir parça.
    static func parca(_ o: Oge, _ sorgu: String, uzunluk: Int = 110) -> String {
        let m = o.metin
        guard !m.isEmpty else { return o.ozet }
        let ilk = katla(sorgu).split(separator: " ").first.map(String.init) ?? ""
        let k = katla(m)
        guard !ilk.isEmpty, let r = k.range(of: ilk), k.count == m.count else {
            return m.count > uzunluk ? String(m.prefix(uzunluk)) + "…" : m
        }
        let bas = max(0, k.distance(from: k.startIndex, to: r.lowerBound) - 35)
        let b = m.index(m.startIndex, offsetBy: bas)
        let e = m.index(b, offsetBy: min(uzunluk, m.distance(from: b, to: m.endIndex)))
        return (bas > 0 ? "…" : "") + m[b..<e] + (e < m.endIndex ? "…" : "")
    }
}

// MARK: Zaman

enum Zaman {
    static func iso(_ t: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; return f.string(from: t)
    }
    static func coz(_ s: String) -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.date(from: String(s.prefix(19)))
    }
    static func sure(_ sn: Double) -> String {
        let s = Int(sn.rounded()); return "\(s / 60):" + String(format: "%02d", s % 60)
    }
    static func goreli(_ t: Date) -> String {
        let fark = Date().timeIntervalSince(t)
        if fark < 60 { return "az önce" }
        if fark < 3600 { return "\(Int(fark / 60)) dk önce" }
        let tk = Calendar.current
        if tk.isDateInToday(t) { return "bugün " + saat(t) }
        if tk.isDateInYesterday(t) { return "dün " + saat(t) }
        let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = fark < 6 * 86400 ? "EEEE HH:mm" : "d MMM HH:mm"
        return f.string(from: t)
    }
    static func saat(_ t: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: t)
    }
    static func gunBasligi(_ t: Date) -> String {
        let tk = Calendar.current
        if tk.isDateInToday(t) { return "Bugün" }
        if tk.isDateInYesterday(t) { return "Dün" }
        let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR"); f.dateFormat = "d MMMM EEEE"
        return f.string(from: t)
    }
}

extension Array where Element == Oge {
    /// Günlere bölünmüş liste (yeniden eskiye).
    func gunlere() -> [(String, [Oge])] {
        var sira: [String] = [], gr: [String: [Oge]] = [:]
        for o in self.sorted(by: { $0.tarih > $1.tarih }) {
            let g = String(o.tarih.prefix(10))
            if gr[g] == nil { sira.append(g) }
            gr[g, default: []].append(o)
        }
        return sira.map { (Zaman.gunBasligi(gr[$0]![0].zaman), gr[$0]!) }
    }
}
