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
    // Lifecycle (2026-11-02): open → done → archived (isle.py moves the note to Arşiv/ 30 days after done).
    var status: String = "open"
    var priority: Int = Priority.normal.rawValue
    var done_at: String = ""
    /// spark = short idea · journal = long spoken diary (goes to the day's journal) · extract = idea pulled out of a journal
    var kind: String = "spark"
    var parent: String = ""
    var offset: Double = 0
    var notes: [NoteEntry] = []
    /// Vault-relative path of the day journal a journal recording was written into.
    var journal_note: String = ""
    /// Dikkat marks (kind "isaret", 2026-11-04): the link, its type, and Claude's "look now" reason.
    var url: String = ""
    var tur: String = ""
    var simdi: String = ""
    /// Link layer (links.py, 2026-11-04): the book/topic this record is about. topic_source: elle · soz · gunluk.
    var topic: String = ""
    var topic_name: String = ""
    var topic_source: String = ""
    /// A long journal can touch several topics; seconds spoken on each.
    var topics: [TopicShare] = []
    /// The part before this one when a long talk rolled over into a new file.
    var devam: String = ""

    enum CodingKeys: String, CodingKey {
        case id, tarih, cihaz, sure, kalite, boyut, ses, metin, metin_kaynak, baslik, baslik_kaynak, ozet, alan, amac, etiketler, yildiz, durum, not
        case status, priority, done_at, kind, parent, offset, notes, journal_note, url, tur, simdi
        case topic, topic_name, topic_source, topics, devam
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
        status = (try? c.decode(String.self, forKey: .status)) ?? "open"
        priority = (try? c.decode(Int.self, forKey: .priority)) ?? Priority.normal.rawValue
        done_at = (try? c.decode(String.self, forKey: .done_at)) ?? ""
        kind = (try? c.decode(String.self, forKey: .kind)) ?? "spark"
        parent = (try? c.decode(String.self, forKey: .parent)) ?? ""
        offset = (try? c.decode(Double.self, forKey: .offset)) ?? 0
        notes = (try? c.decode([NoteEntry].self, forKey: .notes)) ?? []
        journal_note = (try? c.decode(String.self, forKey: .journal_note)) ?? ""
        url = (try? c.decode(String.self, forKey: .url)) ?? ""
        tur = (try? c.decode(String.self, forKey: .tur)) ?? ""
        simdi = (try? c.decode(String.self, forKey: .simdi)) ?? ""
        topic = (try? c.decode(String.self, forKey: .topic)) ?? ""
        topic_name = (try? c.decode(String.self, forKey: .topic_name)) ?? ""
        topic_source = (try? c.decode(String.self, forKey: .topic_source)) ?? ""
        topics = (try? c.decode([TopicShare].self, forKey: .topics)) ?? []
        devam = (try? c.decode(String.self, forKey: .devam)) ?? ""
    }

    var zaman: Date { Zaman.coz(tarih) ?? .distantPast }
    var isDone: Bool { status == "done" }
    var isJournal: Bool { kind == "journal" }
    var prio: Priority { Priority(rawValue: priority) ?? .normal }
    var doneDate: Date? { done_at.isEmpty ? nil : Zaman.coz(done_at) }
    /// Days left before isle.py moves a done item to the vault archive.
    var daysToArchive: Int? {
        guard isDone, let d = doneDate else { return nil }
        return max(0, Priority.archiveDays - Int(Date().timeIntervalSince(d) / 86400))
    }
    var sureMetni: String { Zaman.sure(sure) }
    var islendi: Bool { durum == "hazir" }
}

struct TopicShare: Codable, Hashable, Sendable {
    var id: String
    var name: String
    var seconds: Int
}

struct NoteEntry: Codable, Hashable, Sendable {
    var t: String
    var text: String
}

enum Priority: Int, CaseIterable, Identifiable, Sendable {
    case low = 0, normal = 1, high = 2, urgent = 3
    static let archiveDays = 30
    var id: Int { rawValue }
    var name: String { ["Düşük", "Normal", "Yüksek", "Acil"][rawValue] }
    var symbol: String { ["arrow.down", "minus", "exclamationmark", "exclamationmark.3"][rawValue] }
    var hex: String { ["#8A8F98", "#4C8DF6", "#FF9500", "#FF3B30"][rawValue] }
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

    // A class file from the vault may arrive with an empty list; fall back to the built-in defaults instead of crashing.
    func alan(_ id: String) -> Alan { alanlar.first { $0.id == id } ?? alanlar.last ?? Self.varsayilan.alanlar[Self.varsayilan.alanlar.count - 1] }
    func amac(_ id: String) -> Amac { amaclar.first { $0.id == id } ?? amaclar.last ?? Self.varsayilan.amaclar[Self.varsayilan.amaclar.count - 1] }

    static func yukle(_ u: URL?) -> Siniflar {
        if let u, let v = try? Data(contentsOf: u), let s = try? JSONDecoder().decode(Siniflar.self, from: v),
           !s.alanlar.isEmpty, !s.amaclar.isEmpty { return s }
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
    /// spark (default) · journal
    var kind: String?
    /// When a recording passes its cap it goes on in a new part; this is the id of the part before it (2026-11-04).
    var devam: String? = nil
    /// Mac (2026-11-04): the book/topic chosen before recording (Teoria book id or "k:<name>").
    var topic: String? = nil
}

enum Kimlik {
    private static let stampFormat = Zaman.formatter("yyyyMMdd-HHmmss", posix: true)
    private static let monthFormat = Zaman.formatter("yyyy-MM", posix: true)
    static func yeni(_ cihaz: String, _ t: Date = Date()) -> String {
        let ek = String(UUID().uuidString.prefix(4)).lowercased()
        return "\(stampFormat.string(from: t))-\(cihaz)-\(ek)"
    }
    static func ay(_ t: Date) -> String { monthFormat.string(from: t) }
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
        // one pass over the log: last-write-wins fields and the accumulating notes are collected together
        var son: [String: [String: (String, Any)]] = [:]
        var notlar: [String: [NoteEntry]] = [:]
        for parca in satirlar.split(separator: 0x0A) {
            guard let o = try? JSONSerialization.jsonObject(with: Data(parca)) as? [String: Any],
                  let h = o["hedef"] as? String, let tur = o["tur"] as? String, let d = o["deger"] else { continue }
            let t = o["t"] as? String ?? ""
            if tur == "note", let x = d as? String, !x.isEmpty { notlar[h, default: []].append(NoteEntry(t: t, text: x)) }
            if let e = son[h]?[tur], e.0 > t { continue }
            son[h, default: [:]][tur] = (t, d)
        }
        for i in ogeler.indices {
            guard let d = son[ogeler[i].id] else { continue }
            if let v = d["baslik"]?.1 as? String, !v.isEmpty { ogeler[i].baslik = v; ogeler[i].baslik_kaynak = "elle" }
            if let v = d["alan"]?.1 as? String, !v.isEmpty { ogeler[i].alan = v }
            if let v = d["amac"]?.1 as? String, !v.isEmpty { ogeler[i].amac = v }
            if let v = d["yildiz"]?.1 as? Bool { ogeler[i].yildiz = v }
            if let v = d["status"] {
                ogeler[i].status = (v.1 as? String) ?? "open"
                ogeler[i].done_at = ogeler[i].status == "done" ? (ogeler[i].done_at.isEmpty ? v.0 : ogeler[i].done_at) : ""
            }
            if let v = d["priority"]?.1 as? Int { ogeler[i].priority = v }
            if let v = d["kind"]?.1 as? String, !v.isEmpty { ogeler[i].kind = v }
        }
        // notes accumulate (every "note" event is a new line); the rest are last-write-wins
        for i in ogeler.indices {
            guard let yeni = notlar[ogeler[i].id] else { continue }
            let var_ = Set(ogeler[i].notes.map { $0.t + $0.text })
            ogeler[i].notes += yeni.filter { !var_.contains($0.t + $0.text) }
            ogeler[i].notes.sort { $0.t < $1.t }
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
        let alan = [o.baslik, o.metin, o.ozet, o.etiketler.joined(separator: " "), s.alan(o.alan).ad, s.amac(o.amac).ad,
                    o.notes.map(\.text).joined(separator: " ")].joined(separator: " ")
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
    /// Formatters are built once and shared. A DateFormatter may be read from several threads; none of these is
    /// changed after it is set up. The time zone follows the device (a cached formatter would otherwise keep the old one).
    static func formatter(_ format: String, posix: Bool = false, turkish: Bool = false) -> DateFormatter {
        let f = DateFormatter()
        if posix { f.locale = Locale(identifier: "en_US_POSIX") } else if turkish { f.locale = Locale(identifier: "tr_TR") }
        f.timeZone = .autoupdatingCurrent
        f.dateFormat = format
        return f
    }
    private static let isoFormat = formatter("yyyy-MM-dd'T'HH:mm:ss", posix: true)
    private static let clockFormat = formatter("HH:mm")
    private static let weekdayClockFormat = formatter("EEEE HH:mm", turkish: true)
    private static let dayClockFormat = formatter("d MMM HH:mm", turkish: true)
    private static let dayTitleFormat = formatter("d MMMM EEEE", turkish: true)

    static func iso(_ t: Date) -> String { isoFormat.string(from: t) }
    static func coz(_ s: String) -> Date? { isoFormat.date(from: String(s.prefix(19))) }
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
        return (fark < 6 * 86400 ? weekdayClockFormat : dayClockFormat).string(from: t)
    }
    static func saat(_ t: Date) -> String { clockFormat.string(from: t) }
    static func gunBasligi(_ t: Date) -> String {
        let tk = Calendar.current
        if tk.isDateInToday(t) { return "Bugün" }
        if tk.isDateInYesterday(t) { return "Dün" }
        return dayTitleFormat.string(from: t)
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

// MARK: Tatbik (2026-11-05)
// What was said in Kıvılcım, item by item, per program: Claude writes Tatbik/claude/tatbik.json, the user's touches go
// to Tatbik/olay/<device>.jsonl, tatbik.py merges both into Tatbik/tatbik.json (this is what the apps read).

enum TatbikStatus: String, CaseIterable, Identifiable, Sendable {
    case acik, kismen, tamam, gerekYok = "gerek-yok"
    var id: String { rawValue }
    var name: String {
        switch self { case .acik: "Açık"; case .kismen: "Kısmen"; case .tamam: "Tamamlandı"; case .gerekYok: "Gerek görülmedi" }
    }
    var short: String {
        switch self { case .acik: "Açık"; case .kismen: "Kısmen"; case .tamam: "Tamam"; case .gerekYok: "Gerek yok" }
    }
    var symbol: String {
        switch self { case .acik: "circle"; case .kismen: "circle.lefthalf.filled"; case .tamam: "checkmark.circle.fill"; case .gerekYok: "minus.circle" }
    }
    var hex: String {
        switch self { case .acik: "#2F6FEB"; case .kismen: "#E09B2D"; case .tamam: "#23915E"; case .gerekYok: "#8E8C86" }
    }
    var isClosed: Bool { self == .tamam || self == .gerekYok }
}

struct TatbikProgram: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var ad: String
    var renk: String?
    var aciklama: String?
}

struct TatbikNote: Codable, Hashable, Sendable {
    var t: String
    var text: String
    var device: String?
}

struct TatbikItem: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var program: String
    var durum: String
    var baslik: String
    var kaynaklar: [String]?
    var ayrinti: String?
    var kanit: String?
    var tarih: String?
    var eksik: String?
    var gerekce: String?
    var oncelik: String?
    var buyukluk: String?
    var kaynak_durum: String?
    var notlar: [TatbikNote]?
    var status: TatbikStatus { TatbikStatus(rawValue: durum) ?? .acik }
    var sources: [String] { kaynaklar ?? [] }
    var byUser: Bool { kaynak_durum == "elle" }
    var priorityName: String? {
        switch oncelik { case "yuksek": "yüksek"; case "normal": "normal"; case "dusuk": "düşük"; default: nil }
    }
    var sizeName: String? {
        switch buyukluk { case "kucuk": "küçük iş"; case "orta": "orta iş"; case "buyuk": "büyük iş"; default: nil }
    }
    var priorityRank: Int { ["yuksek": 0, "normal": 1, "dusuk": 2][oncelik ?? ""] ?? 1 }

    /// The text to paste into Claude Code: what to do, why, what is already there, where it came from.
    func prompt(_ program: TatbikProgram?, _ records: [Oge]) -> String {
        var s = "Kıvılcım › Tatbik maddesi \(id) · \(program?.ad ?? self.program)\n\nYapılacak: \(baslik)\n"
        if let a = ayrinti, !a.isEmpty { s += "Ayrıntı: \(a)\n" }
        if let k = kanit, !k.isEmpty { s += "Şu an var olan: \(k)\n" }
        if let e = eksik, !e.isEmpty { s += "Eksik kalan: \(e)\n" }
        for n in notlar ?? [] { s += "Notum (\(n.t.prefix(10))): \(n.text)\n" }
        if !records.isEmpty {
            s += "\nKaynak kayıtlar (Kıvılcım):\n"
            for o in records { s += "- \(o.tarih.prefix(16).replacingOccurrences(of: "T", with: " ")) · \(o.baslik) · \(o.id)\n" }
        }
        s += "\nÖnce kaynak kaydın metnini oku, sonra işi yap. Bitince Kıvılcım/Tatbik/claude/tatbik.json'da bu maddeyi \"tamam\" yap ve kanıtını yaz."
        return s
    }
}

struct TatbikState: Codable, Sendable {
    var guncelleme: String?
    var programlar: [TatbikProgram]
    var maddeler: [TatbikItem]
    var incelenmemis: [String]?
    static let empty = TatbikState(guncelleme: nil, programlar: [], maddeler: [], incelenmemis: [])
    func program(_ id: String) -> TatbikProgram? { programlar.first { $0.id == id } }
    func items(of program: String) -> [TatbikItem] { maddeler.filter { $0.program == program } }
    func items(for record: String) -> [TatbikItem] { maddeler.filter { $0.sources.contains(record) } }
    func count(_ s: TatbikStatus, in list: [TatbikItem]? = nil) -> Int { (list ?? maddeler).filter { $0.status == s }.count }
    var openCount: Int { maddeler.filter { !$0.status.isClosed }.count }
    /// Done share: closed items over all items (gerek-yok counts as decided).
    func progress(_ list: [TatbikItem]? = nil) -> Double {
        let l = list ?? maddeler
        return l.isEmpty ? 0 : Double(l.filter { $0.status.isClosed }.count) / Double(l.count)
    }
}

enum TatbikEvent {
    /// Same line format as the record edit log, aimed at an item id.
    static func line(item: String, kind: String, value: String, device: String) -> Data {
        Olay.satir(hedef: item, tur: kind, deger: value, cihaz: device)
    }
}

// MARK: Daily feed (2026-11-06)
// A finite daily issue in place of the X timeline: feed.py (Mac) picks at most 10 items from Hacker News, Reddit and the
// posts liked on X, and writes Feed/feed.json. Touches go to Feed/olay/<device>.jsonl; a marked item becomes a Dikkat mark.
// An issue from another day is never shown: nothing here carries over.

struct FeedItem: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var source: String
    var community: String
    var topic: String
    var title: String
    var url: String
    var discussion: String?
    var points: Int?
    var comments: Int?
    var excerpt: String?
    var author: String?
    var status: String
    /// When the merged status was last touched, on any device: the phone's own newer touch still wins on its screen.
    var touched: String?
    var image: String?
    var body: String?
    /// Turkish, from Apple's on-device translation on the Mac (Feed/translations.json). Empty until it is done.
    var title_tr: String?
    var body_tr: String?
    var imageLink: URL? { image.flatMap { $0.isEmpty ? nil : URL(string: $0) } }
    var shownTitle: String { (title_tr ?? "").isEmpty ? title : title_tr! }
    /// The original under the Turkish title; nil when there is no translation or it is the same text.
    var originalTitle: String? { shownTitle == title ? nil : title }
    var shownBody: String { let t = body_tr ?? ""; return t.isEmpty ? (body ?? excerpt ?? "") : t }
    var hasTurkishBody: Bool { !(body_tr ?? "").isEmpty && body_tr != body }
    var isOpen: Bool { status == "open" }
    var isMarked: Bool { status == "marked" }
    var isSkipped: Bool { status == "skipped" }
    /// "412 puan · 130 yorum" where the source gives numbers; Reddit's feed does not.
    var numbers: String? {
        guard let points else { return nil }
        return "\(points) puan" + (comments.map { " · \($0) yorum" } ?? "")
    }
    var link: URL? { URL(string: url) }
    var discussionLink: URL? { discussion.flatMap { $0 == url ? nil : URL(string: $0) } }
}

struct FeedTopic: Codable, Hashable, Sendable {
    var id: String
    var name: String
}

struct FeedIssue: Codable, Sendable {
    var date: String
    var built_at: String?
    var ready_at: String?
    var updated: String?
    var topics: [FeedTopic]
    var items: [FeedItem]
    var errors: [String]?
    static let empty = FeedIssue(date: "", topics: [], items: [])
    var isToday: Bool { date == String(Zaman.iso(Date()).prefix(10)) }
    var readyAt: String { ready_at ?? "12:30" }
    var openCount: Int { isToday ? items.filter(\.isOpen).count : 0 }
    var markedCount: Int { items.filter(\.isMarked).count }
    var skipped: [FeedItem] { items.filter(\.isSkipped) }
    /// Topics in the issue's order, with what is left to read in each.
    var sections: [(topic: FeedTopic, items: [FeedItem])] {
        topics.compactMap { t in
            let l = items.filter { $0.topic == t.id && !$0.isSkipped }
            return l.isEmpty ? nil : (t, l)
        }
    }
}
