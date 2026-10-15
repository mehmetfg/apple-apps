// Teoria motoru: olayları oynatıp durumu kurar, kürü planlar, alıştırma üretir, cevabı ölçer.
// Tek kural: durum yalnız olaylardan çıkar. Üç cihaz aynı olayları görürse aynı durumu hesaplar.
import Foundation

// MARK: - Alıştırma

struct Alistirma: Identifiable, Hashable {
    enum Tip: String, Hashable { case sec, diz, bosluk, yaz }

    var id = UUID().uuidString
    let hat: Hat
    let kademe: Int
    let kartAnahtari: String
    let tip: Tip
    let baslik: String
    let soru: String
    var baglam: String? = nil
    var ipuclari: [String] = []
    var secenekler: [String] = []
    var dogru: String = ""
    var parcalar: [String] = []
    var anahtar: [String] = []
    var model: String = ""
    var aciklama: String? = nil
    let kitap: String?
    var kaynak: String = ""
    var rol: String? = nil

    var tahminiSaniye: Double {
        switch tip {
        case .sec: 25
        case .diz: 45
        case .bosluk: 40
        case .yaz: kademe >= 5 ? 120 : 80
        }
    }
}

// MARK: - Durum

struct HatDurumu: Hashable {
    var kademe = 1
    var yukari = 0
    var asagi = 0
    var sonOran: Double?
}

struct KurOzeti: Identifiable, Hashable {
    let id: String
    let gun: String
    let t: Date
    let sure: Double
    let adet: Int
    let ortalama: Double
    var degisim: [Hat: Int] = [:]
    var kazanc: String
}

struct Durum {
    var kartlar: [String: Kart] = [:]
    var hatlar: [Hat: HatDurumu] = Dictionary(uniqueKeysWithValues: Hat.allCases.map { ($0, HatDurumu()) })
    var kurlar: [KurOzeti] = []
    var favoriler: Set<String> = []
    var yerIsaretleri: Set<String> = []
    var hatirlatmalar: Set<String> = []
    var sesNotlari: [Olay] = []
    var kendiCumleler: [Olay] = []
    var yorumSayisi: [String: Int] = [:]          // işaret → kaç yorum/alıntı yazdın

    /// Bir işarete kaç sesli not kaydettin ("2" ya da nil) — akıştaki mikrofonun yanında.
    func sesSayisi(_ hedef: String) -> String? {
        let n = sesNotlari.filter { $0.hedef == hedef }.count
        return n > 0 ? "\(n)" : nil
    }
    var acikKurlar: [String: [Olay]] = [:]      // kapanış olayı gelmemiş kürlerin cevapları
    var sonOlay: Date?

    func kademe(_ h: Hat) -> Int { hatlar[h]?.kademe ?? 1 }

    var bugunDakika: Double { kurlar.filter { $0.gun == Tarih.gun(Date()) }.reduce(0) { $0 + $1.sure } / 60 }
    var bugunKur: Int { kurlar.filter { $0.gun == Tarih.gun(Date()) }.count }

    /// Bu hafta (Pazartesi'den) kaç kür — seri değil, sayım. Kırılan bir şey yok.
    var buHaftaKur: Int {
        let bas = Tarih.takvim.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date().gunBasi
        return kurlar.filter { $0.t >= bas }.count
    }

    /// Son 7 gün (eskiden yeniye) — o gün kür yapıldı mı, kaç dakika.
    var hafta: [Double] {
        (0..<7).reversed().map { g in
            let gun = Tarih.gun(Date().gun(-g))
            return kurlar.filter { $0.gun == gun }.reduce(0) { $0 + $1.sure } / 60
        }
    }

    var sonKur: Date? { kurlar.map(\.t).max() }
    var uzunAra: Bool { guard let s = sonKur else { return false }; return Date().timeIntervalSince(s) > 7 * 86_400 }

    static func kur(_ olaylar: [Olay], zorluk: Zorluk, simdi: Date = Date()) -> Durum {
        var d = Durum()
        // Saati ileri öteki cihazdan gelen olay: geleceğe yazılmış zaman şimdiye çekilir (sıra bozulmasın).
        let sinir = simdi.addingTimeInterval(300)
        var sirali: [Olay] = olaylar
        for i in sirali.indices where sirali[i].t > sinir { sirali[i].t = simdi }
        sirali.sort { (a: Olay, b: Olay) -> Bool in a.t == b.t ? a.id < b.id : a.t < b.t }
        var silinenSes = Set<String>()
        for o in sirali {
            d.sonOlay = o.t
            switch o.tur {
            case .cevap:
                if let k = o.hedef {
                    let n = Not(rawValue: o.not ?? 0) ?? Not.puandan(o.puan ?? 0)
                    d.kartlar[k] = d.kartlar[k].map { FSRS.tekrar($0, n, an: o.t) } ?? FSRS.yeni(n, an: o.t)
                }
                if let k = o.kurId { d.acikKurlar[k, default: []].append(o) }
                if let m = o.metin, !m.isEmpty, (o.kademe ?? 0) >= 5 { d.kendiCumleler.append(o) }
            case .kur:
                let cevaplar = o.kurId.flatMap { d.acikKurlar.removeValue(forKey: $0) } ?? []
                d.kurKapat(o, cevaplar, hedef: zorluk.hedef)
            case .favori:
                if let h = o.hedef { if o.deger ?? true { d.favoriler.insert(h) } else { d.favoriler.remove(h) } }
            case .yerIsareti:
                if let h = o.hedef { if o.deger ?? true { d.yerIsaretleri.insert(h) } else { d.yerIsaretleri.remove(h) } }
            case .hatirlat:
                if let h = o.hedef { if o.deger ?? true { d.hatirlatmalar.insert(h) } else { d.hatirlatmalar.remove(h) } }
            case .sesNot:
                d.sesNotlari.append(o)
            case .sesSil:
                if let h = o.hedef { silinenSes.insert(h) }
            case .kendiCumle:
                d.kendiCumleler.append(o)
                if let h = o.hedef { d.yorumSayisi[h, default: 0] += 1 }
            case .kademe:
                if let h = o.hat, let k = o.kademe { d.hatlar[h] = HatDurumu(kademe: min(max(k, 1), 6)) }
            }
        }
        d.sesNotlari.removeAll { silinenSes.contains($0.id) }
        for o in d.kendiCumleler where silinenSes.contains(o.id) {
            if let h = o.hedef, let n = d.yorumSayisi[h] { d.yorumSayisi[h] = n > 1 ? n - 1 : nil }
        }
        d.kendiCumleler.removeAll { silinenSes.contains($0.id) }
        d.sesNotlari.sort { $0.t > $1.t }
        d.kendiCumleler.sort { $0.t > $1.t }
        return d
    }

    /// +1 kuralı: bir hatta, o hattın kademesindeki asıl alıştırmalar (ısınma/esneme/kapanış hariç)
    /// üç kür üst üste hedefi tutarsa bir kademe çıkar; üç kür üst üste çok altında kalırsa sessizce iner.
    private mutating func kurKapat(_ o: Olay, _ cevaplar: [Olay], hedef: Double) {
        var degisim: [Hat: Int] = [:]
        for h in Hat.allCases {
            var hd = hatlar[h] ?? HatDurumu()
            let asil = cevaplar.filter { $0.hat == h && $0.rol == nil && $0.kademe == hd.kademe }
            guard asil.count >= 2 else { continue }
            let oran = asil.compactMap(\.puan).reduce(0, +) / Double(asil.count)
            hd.sonOran = oran
            if oran >= hedef {
                hd.yukari += 1; hd.asagi = 0
            } else if oran < hedef - 0.25 {
                hd.asagi += 1; hd.yukari = 0
            } else {
                hd.yukari = 0; hd.asagi = 0
            }
            if hd.yukari >= 3, hd.kademe < 6 { hd.kademe += 1; hd.yukari = 0; degisim[h] = 1 }
            if hd.asagi >= 3, hd.kademe > 1 { hd.kademe -= 1; hd.asagi = 0; degisim[h] = -1 }
            hatlar[h] = hd
        }
        let puanlar = cevaplar.compactMap(\.puan)
        let ort = puanlar.isEmpty ? 0 : puanlar.reduce(0, +) / Double(puanlar.count)
        kurlar.append(KurOzeti(id: o.kurId ?? o.id, gun: o.gun, t: o.t, sure: o.sure ?? 0, adet: cevaplar.count,
                               ortalama: ort, degisim: degisim, kazanc: Durum.kazanc(cevaplar)))
    }

    static func kazanc(_ c: [Olay]) -> String {
        let iyi = c.filter { ($0.puan ?? 0) >= 0.7 }
        let kurulan = iyi.filter { $0.hat == .kur }.count
        let hatirlanan = iyi.filter { $0.hat == .hatirla }.count
        let donusen = iyi.filter { $0.hat == .donustur }.count
        var p: [String] = []
        if hatirlanan > 0 { p.append("\(hatirlanan) kavramı kendi zihninden çağırdın") }
        if kurulan > 0 { p.append("\(kurulan) cümleyi yeniden kurdun") }
        if donusen > 0 { p.append("\(donusen) dönüşümü yaptın") }
        if p.isEmpty { return c.isEmpty ? "Masaya oturdun. Bugünün işi bu." : "Zor bir kürdü; zihin tam da böyle çalışır." }
        return p.joined(separator: ", ") + "."
    }

    func oturmusKavramlar(_ p: Paket) -> [Kavram] {
        p.kavramlar.filter { k in kartlar["hatirla:\(k.id)"]?.oturmus ?? false }
    }
}

// MARK: - Kür planı

struct KurPlani: Identifiable {
    let id = UUID().uuidString
    let dakika: Int
    var alistirmalar: [Alistirma]
    var kapanis: Alistirma?
    let hosgeldin: Bool
}

enum Kurgu {
    /// Hatların kürdeki payı. Mobil hatırlamaya, masaüstü yazmaya ağırlık verir.
    static var agirlik: [Hat: Double] {
        #if os(iOS)
        [.hatirla: 0.5, .donustur: 0.25, .kur: 0.25]
        #else
        [.hatirla: 0.3, .donustur: 0.35, .kur: 0.35]
        #endif
    }

    /// Son okuduğun gün: en yeni işaretin günü ve o günün işaretleri (çekirdek iddia önce).
    /// Bugün zaten sorulmuş olanlar düşer; ikinci kürde son gün tekrar edilmez.
    static func sonGun(_ akis: [Isaret], _ d: Durum, simdi: Date = Date()) -> (gun: Date, isaretler: [Isaret])? {
        guard let en = akis.map(\.zaman).filter({ $0 <= simdi.addingTimeInterval(300) }).max() else { return nil }
        let oncelik = [1: 0, 3: 1, 4: 2, 2: 3]
        let l = akis.filter { Tarih.takvim.isDate($0.zaman, inSameDayAs: en) }
            .filter { i in !(d.kartlar["hatirla:isaret:\(i.id)"].map { Tarih.takvim.isDate($0.son, inSameDayAs: simdi) } ?? false) }
            .sorted { (oncelik[$0.renk] ?? 9, $0.zaman) < (oncelik[$1.renk] ?? 9, $1.zaman) }
        return l.isEmpty ? nil : (en, l)
    }

    static func plan(_ p: Paket, _ d: Durum, dakika: Int, akis: [Isaret] = [], simdi: Date = Date()) -> KurPlani {
        let hos = d.uzunAra
        var kullanilan = Set<String>()
        var liste: [Alistirma] = []
        let butce = Double(dakika * 60) * 1.4
        // Tekrar havuzu: "hatırlat" denen işaretler + bir kez kürde sorulmuş her işaret (kendiliğinden kart).
        var havuz = d.hatirlatmalar
        for i in akis where d.kartlar["hatirla:isaret:\(i.id)"] != nil { havuz.insert(i.id) }
        var dd = d
        dd.hatirlatmalar = havuz

        // 1 · Son gün: en son okuduğun günün işaretleri, boşluklu hatırlama olarak. Isınmanın yerini alır (sıra 3b'de zorluğa göre dizilir).
        if let (gun, l) = sonGun(akis, d, simdi: simdi) {
            let adet = dakika <= 5 ? 3 : (dakika <= 10 ? 5 : 7)
            let k = max(1, min(d.kademe(.hatirla), 4) - (hos ? 1 : 0))
            let ad = Tarih.takvim.isDate(gun, inSameDayAs: simdi) ? "bugün" : Tarih.goreli(gun, simdi: simdi)
            for i in l.prefix(adet) {
                guard let aday = Uretec.isaretKarti(i, k, baslik: "Son okuduğun · \(ad)") else { continue }
                var a = aday.yap()
                a.rol = "songun"
                kullanilan.insert(aday.kaynakId)
                liste.append(a)
            }
        }
        // 1b · Son gün yoksa ısınma: en güçlü hattın bir alt kademesinden, kazanılacak bir kart.
        if liste.isEmpty {
            let guclu = Hat.allCases.max { d.kademe($0) < d.kademe($1) } ?? .hatirla
            if var a = uret(p, dd, guclu, max(1, d.kademe(guclu) - 1), &kullanilan, akis: akis, simdi: simdi) {
                a.rol = "isinma"; liste.append(a)
            }
        }
        // 2 · Aralıklı tekrar: vadesi gelen kartlar (en eski vade önce), bütçenin en çok üçte biri.
        var vadeli: [(Aday, Date)] = []
        for h in Hat.allCases {
            for x in Uretec.adaylar(p, h, d.kademe(h), akis: akis, hatirlatmalar: havuz) where !kullanilan.contains(x.kaynakId) {
                if let kart = d.kartlar[x.anahtar], kart.vade <= simdi { vadeli.append((x, kart.vade)) }
            }
        }
        var toplam = liste.reduce(0) { $0 + $1.tahminiSaniye }
        for (x, _) in vadeli.sorted(by: { $0.1 < $1.1 }) {
            guard toplam < butce * 0.6, !kullanilan.contains(x.kaynakId) else { continue }
            var a = x.yap()
            a.rol = "tekrar"
            kullanilan.insert(x.kaynakId)
            liste.append(a)
            toplam += a.tahminiSaniye
        }
        // 3 · Hat işleri: kademende, ağırlığa göre dönüşümlü
        var sayac: [Hat: Double] = [:]
        var deneme = 0
        while toplam < butce && deneme < 60 {
            deneme += 1
            guard let h = Hat.allCases.min(by: { sayac[$0, default: 0] / agirlik[$0, default: 1] < sayac[$1, default: 0] / agirlik[$1, default: 1] }) else { break }
            sayac[h, default: 0] += 1
            let k = hos ? max(1, d.kademe(h) - 1) : d.kademe(h)
            guard let a = uret(p, dd, h, k, &kullanilan, akis: akis, simdi: simdi) else { continue }
            liste.append(a)
            toplam += a.tahminiSaniye
        }
        // 3b · Rampa: kür hep en kolaydan başlar, sona doğru zorlaşır. Zor başlayan kür bırakılır; kolay başlayan sürer.
        func zorlukPuani(_ a: Alistirma) -> Double {
            let tip: Double = switch a.tip { case .sec: 0; case .diz: 1; case .bosluk: 2; case .yaz: 3 }
            return tip + Double(a.kademe) * 0.6
        }
        liste = liste.enumerated().sorted { (x, y) in
            let ax = zorlukPuani(x.element), ay = zorlukPuani(y.element)
            return ax == ay ? x.offset < y.offset : ax < ay
        }.map(\.element)
        if (liste.first.map(zorlukPuani) ?? 0) > 1.5, var a = uret(p, dd, .hatirla, 1, &kullanilan, akis: akis, simdi: simdi) {
            a.rol = "isinma"; liste.insert(a, at: 0)     // en kolayı bile zorsa: önce kolay bir kavram kartı
        }
        // 4 · Esneme: tek kart, bir üst kademe, kürün son üçte birinde
        if !hos, let h = Hat.allCases.filter({ d.kademe($0) < 6 }).randomElement(),
           var a = uret(p, dd, h, d.kademe(h) + 1, &kullanilan, akis: akis, simdi: simdi) {
            a.rol = "esneme"
            liste.insert(a, at: max(1, Int(Double(liste.count) * 0.66)))
        }
        // 5 · Kapanış: süre dolunca gösterilen, kazanılacak kolay kart (kür başarıyla biter)
        var kapanis = uret(p, dd, .hatirla, 1, &kullanilan, akis: akis, simdi: simdi)
        kapanis?.rol = "kapanis"
        return KurPlani(dakika: dakika, alistirmalar: liste, kapanis: kapanis, hosgeldin: hos)
    }

    /// Hat + kademe için bir alıştırma. O kademede malzeme yoksa bir alt kademeye iner.
    static func uret(_ p: Paket, _ d: Durum, _ h: Hat, _ kademe: Int, _ kullanilan: inout Set<String>,
                     akis: [Isaret], simdi: Date) -> Alistirma? {
        var k = min(max(kademe, 1), 6)
        while k >= 1 {
            let adaylar = Uretec.adaylar(p, h, k, akis: akis, hatirlatmalar: d.hatirlatmalar)
                .filter { !kullanilan.contains($0.kaynakId) }
            if let secilen = sirala(adaylar, d, simdi).first {
                kullanilan.insert(secilen.kaynakId)
                return secilen.yap()
            }
            k -= 1
        }
        return nil
    }

    /// Önce vadesi gelenler (en eski vade önce), sonra yeniler, sonra en çok unutulmaya yakın olanlar.
    static func sirala(_ a: [Aday], _ d: Durum, _ simdi: Date) -> [Aday] {
        let karisik = a.shuffled()
        let vadeli = karisik.compactMap { x -> (Aday, Date)? in
            guard let k = d.kartlar[x.anahtar], k.vade <= simdi else { return nil }
            return (x, k.vade)
        }.sorted { $0.1 < $1.1 }.map(\.0)
        let yeni = karisik.filter { d.kartlar[$0.anahtar] == nil }
        let kalan = karisik.filter { x in d.kartlar[x.anahtar].map { $0.vade > simdi } ?? false }
            .sorted { (d.kartlar[$0.anahtar]?.hatirlama(simdi) ?? 1) < (d.kartlar[$1.anahtar]?.hatirlama(simdi) ?? 1) }
        // Yeni kartları kitaplar arasında dengeli dağıt; vadesi gelen yığılmasın diye en çok 4 tanesi öne.
        return Array(vadeli.prefix(4)) + yeni + Array(vadeli.dropFirst(4)) + kalan
    }
}

struct Aday {
    let anahtar: String
    let kaynakId: String
    let yap: () -> Alistirma
}

// MARK: - Üreteç

enum Uretec {
    static func adaylar(_ p: Paket, _ h: Hat, _ k: Int, akis: [Isaret], hatirlatmalar: Set<String>) -> [Aday] {
        switch h {
        case .hatirla: hatirla(p, k, akis: akis.filter { hatirlatmalar.contains($0.id) })
        case .donustur: donustur(p, k)
        case .kur: kur(p, k)
        }
    }

    static func kitapAdi(_ p: Paket, _ id: String?) -> String { p.kitap(id)?.baslik ?? "" }

    // HATIRLA
    static func hatirla(_ p: Paket, _ k: Int, akis: [Isaret]) -> [Aday] {
        var a: [Aday] = []
        for v in p.kavramlar {
            let anahtar = "hatirla:\(v.id)"
            let kaynak = kitapAdi(p, v.kitap)
            let ayni = p.kavramlar.filter { $0.id != v.id && $0.kitap == v.kitap }
            let diger = ayni.isEmpty ? p.kavramlar.filter { $0.id != v.id } : ayni
            switch k {
            case 1:
                guard let c = diger.randomElement() else { continue }
                a.append(Aday(anahtar: anahtar, kaynakId: v.id) {
                    Alistirma(hat: .hatirla, kademe: 1, kartAnahtari: anahtar, tip: .sec, baslik: "Tanımdan kavrama",
                              soru: "Bu tanım hangi kavrama ait?", baglam: v.tanim,
                              secenekler: [v.terim, c.terim].shuffled(), dogru: v.terim, model: v.terim,
                              aciklama: v.ipucu, kitap: v.kitap, kaynak: kaynak)
                })
            case 2:
                let cel = Array(diger.shuffled().prefix(3))
                guard cel.count >= 2 else { continue }
                a.append(Aday(anahtar: anahtar, kaynakId: v.id) {
                    Alistirma(hat: .hatirla, kademe: 2, kartAnahtari: anahtar, tip: .sec, baslik: "Kavramdan tanıma",
                              soru: "‘\(v.terim)’ ne demek?", secenekler: ([v.tanim] + cel.map(\.tanim)).shuffled(),
                              dogru: v.tanim, model: v.tanim, aciklama: v.ipucu, kitap: v.kitap, kaynak: kaynak)
                })
            case 3:
                let bos = v.tanim
                a.append(Aday(anahtar: anahtar, kaynakId: v.id) {
                    Alistirma(hat: .hatirla, kademe: 3, kartAnahtari: anahtar, tip: .bosluk, baslik: "Seçeneksiz hatırla",
                              soru: "Bu tanımın kavramı ne?", baglam: bos,
                              ipuclari: [v.ipucu, "İlk harf: \(v.terim.prefix(1).uppercased(with: Dil.tr))",
                                         "\(v.terim.count) harf · \(String(v.terim.prefix(3)))…"],
                              dogru: v.terim, model: v.terim, kitap: v.kitap, kaynak: kaynak)
                })
            case 4:
                a.append(Aday(anahtar: anahtar, kaynakId: v.id) {
                    Alistirma(hat: .hatirla, kademe: 4, kartAnahtari: anahtar, tip: .yaz, baslik: "Kendi zihninden",
                              soru: "‘\(v.terim)’ nedir? Kendi cümlenle anlat.",
                              ipuclari: [v.ipucu, "Şu kelimeler geçebilir: " + v.anahtar.joined(separator: " · ")],
                              anahtar: v.anahtar, model: v.tanim, aciklama: v.ayirt.map { "Karıştırma: \($0.karsi). \($0.fark)" },
                              kitap: v.kitap, kaynak: kaynak)
                })
            case 5:
                guard let kitap = p.kitap(v.kitap), v.id == p.kavramlar.first(where: { $0.kitap == v.kitap })?.id else { continue }
                let terimler = p.kavramlar.filter { $0.kitap == kitap.id }.map(\.terim)
                let ak = "hatirla:bos-sayfa:\(kitap.id)"
                a.append(Aday(anahtar: ak, kaynakId: "bos-\(kitap.id)") {
                    Alistirma(hat: .hatirla, kademe: 5, kartAnahtari: ak, tip: .yaz, baslik: "Boş sayfa",
                              soru: "‘\(kitap.baslik)’ bölümünden aklında kalan üç kavramı yaz, birini bir cümleyle açıkla.",
                              ipuclari: ["Bölümün özü: \(kitap.oz)", "Bir kavramın ilk harfi: \(terimler.randomElement()?.prefix(1) ?? "")"],
                              anahtar: terimler, model: terimler.joined(separator: " · "), kitap: kitap.id, kaynak: kitap.seri)
                })
            default:
                continue
            }
        }
        if k == 6 {
            for b in p.baglar {
                let ak = "hatirla:\(b.id)"
                let ka = p.kavram(b.a), kb = p.kavram(b.b)
                a.append(Aday(anahtar: ak, kaynakId: b.id) {
                    Alistirma(hat: .hatirla, kademe: 6, kartAnahtari: ak, tip: .yaz, baslik: "Bağ kur",
                              soru: b.soru, ipuclari: [ka?.tanim ?? "", kb?.tanim ?? ""].filter { !$0.isEmpty },
                              anahtar: [ka?.terim, kb?.terim].compactMap { $0 }, model: b.model,
                              kitap: ka?.kitap, kaynak: "Kant ↔ Heidegger")
                })
            }
        }
        // Akıştaki işaretler (hatırlat denenler + daha önce kürde sorulanlar): kendi işaretin, aynı merdivenle
        for i in akis {
            if let x = isaretKarti(i, k) { a.append(x) }
        }
        return a
    }

    /// Kendi işaretinden boşluklu hatırlama kartı: en uzun anlamlı kelime gizlenir.
    /// K1-2 iki şıklı, K3+ seçeneksiz (ipucu: ilk harf, harf sayısı). Çok kısa işaretten kart çıkmaz.
    static func isaretKarti(_ i: Isaret, _ k: Int, baslik: String = "Kendi işaretin") -> Aday? {
        let ak = "hatirla:isaret:\(i.id)"
        let kelimeler = i.metin.split(separator: " ").map(String.init)
        let uzun = kelimeler.filter { Dil.normal($0).count >= 6 && !Dil.bosKelimeler.contains(Dil.normal($0)) }
        guard kelimeler.count >= 5, let hedef = uzun.max(by: { $0.count < $1.count }) else { return nil }
        let temiz = hedef.trimmingCharacters(in: .punctuationCharacters)
        let bosluklu = i.metin.replacingOccurrences(of: temiz, with: "_____")
        return Aday(anahtar: ak, kaynakId: i.id) {
            if k <= 2 {
                let cel = uzun.filter { $0 != hedef }.randomElement()?.trimmingCharacters(in: .punctuationCharacters) ?? "kavram"
                return Alistirma(hat: .hatirla, kademe: k, kartAnahtari: ak, tip: .sec, baslik: baslik,
                                 soru: "Boşluğa ne geliyordu?", baglam: bosluklu, secenekler: [temiz, cel].shuffled(),
                                 dogru: temiz, model: i.metin, kitap: nil, kaynak: i.baslik)
            }
            return Alistirma(hat: .hatirla, kademe: k, kartAnahtari: ak, tip: .bosluk, baslik: baslik,
                             soru: "Boşluğa ne geliyordu?", baglam: bosluklu,
                             ipuclari: ["İlk harf: \(temiz.prefix(1))", "\(temiz.count) harf"],
                             dogru: temiz, model: i.metin, kitap: nil, kaynak: i.baslik)
        }
    }

    // DÖNÜŞTÜR
    static func donustur(_ p: Paket, _ k: Int) -> [Aday] {
        var a: [Aday] = []
        switch k {
        case 1:
            for q in p.questions ?? [] {
                let ak = "donustur:q:\(q.id)"
                let kitap = p.kavram(q.concept)?.kitap
                a.append(Aday(anahtar: ak, kaynakId: q.id) {
                    Alistirma(hat: .donustur, kademe: 1, kartAnahtari: ak, tip: .sec, baslik: "Kavramı işlet",
                              soru: q.question, baglam: q.context, secenekler: q.options.shuffled(),
                              dogru: q.answer, model: q.answer, aciklama: q.explanation,
                              kitap: kitap, kaynak: kitapAdi(p, kitap))
                })
            }
        case 2:
            for v in p.kavramsallar {
                let ak = "donustur:sec:\(v.id)"
                // Distractors: other conceptual rewrites, same book first so the choice turns on meaning.
                let others = p.kavramsallar.filter { $0.id != v.id }
                let distractors = (others.filter { $0.kitap == v.kitap }.shuffled() + others.filter { $0.kitap != v.kitap }.shuffled())
                    .prefix(3).map(\.kavramsal)
                guard distractors.count >= 2 else { continue }
                a.append(Aday(anahtar: ak, kaynakId: "sec-\(v.id)") {
                    Alistirma(hat: .donustur, kademe: 2, kartAnahtari: ak, tip: .sec, baslik: "Gündelikten kavramsala",
                              soru: "Bu gündelik cümlenin kavramsal karşılığı hangisi?", baglam: v.gundelik,
                              secenekler: ([v.kavramsal] + distractors).shuffled(),
                              dogru: v.kavramsal, model: v.kavramsal, aciklama: "Kavramlar: " + v.ipucu,
                              kitap: v.kitap, kaynak: kitapAdi(p, v.kitap))
                })
            }
        case 3:
            for v in p.kavramsallar {
                let ak = "donustur:\(v.id)"
                let an = v.ipucu.components(separatedBy: " · ")
                a.append(Aday(anahtar: ak, kaynakId: v.id) {
                    Alistirma(hat: .donustur, kademe: 3, kartAnahtari: ak, tip: .yaz, baslik: "Gündelikten kavramsala",
                              soru: "Bu cümleyi kavramsal dille yeniden yaz.", baglam: v.gundelik,
                              ipuclari: ["Kullanılacak kavramlar: " + v.ipucu], anahtar: an, model: v.kavramsal,
                              kitap: v.kitap, kaynak: kitapAdi(p, v.kitap))
                })
            }
        case 4:
            for v in p.kavramlar {
                guard let ay = v.ayirt else { continue }
                let ak = "donustur:ayirt:\(v.id)"
                a.append(Aday(anahtar: ak, kaynakId: "ayirt-\(v.id)") {
                    Alistirma(hat: .donustur, kademe: 4, kartAnahtari: ak, tip: .yaz, baslik: "Ayırt et",
                              soru: "‘\(v.terim)’ ile ‘\(ay.karsi)’ arasındaki fark ne?",
                              ipuclari: [v.tanim], anahtar: [v.terim, ay.karsi], model: ay.fark,
                              kitap: v.kitap, kaynak: kitapAdi(p, v.kitap))
                })
            }
        case 5:
            for v in p.kavramlar {
                guard let ay = v.ayirt else { continue }
                let ak = "donustur:arguman:\(v.id)"
                a.append(Aday(anahtar: ak, kaynakId: "arg-\(v.id)") {
                    Alistirma(hat: .donustur, kademe: 5, kartAnahtari: ak, tip: .yaz, baslik: "Kavram çiftiyle argüman",
                              soru: "‘\(v.terim)’ ve ‘\(ay.karsi)’ kavramlarıyla iki-üç cümlelik bir argüman kur: bir iddia, bir gerekçe.",
                              ipuclari: ["Önce iddia: '… değil, … dır.'", ay.fark], anahtar: [v.terim, ay.karsi],
                              model: "\(v.tanim) \(ay.fark)", kitap: v.kitap, kaynak: kitapAdi(p, v.kitap))
                })
            }
        default:
            for v in p.kavramlar {
                let ak = "donustur:aforizma:\(v.id)"
                let ornek = p.aforizmalar.filter { $0.kitap == v.kitap }.randomElement() ?? p.aforizmalar.randomElement()
                a.append(Aday(anahtar: ak, kaynakId: "afo-\(v.id)") {
                    Alistirma(hat: .donustur, kademe: 6, kartAnahtari: ak, tip: .yaz, baslik: "Kendi aforizman",
                              soru: "‘\(v.terim)’ üzerine tek cümlelik kendi aforizmanı yaz.", baglam: v.tanim,
                              ipuclari: ["Örnek ses: “\(ornek?.metin ?? "")”", "Karşıtlık kur: '… değil, …'"],
                              anahtar: [], model: ornek?.metin ?? "", kitap: v.kitap, kaynak: kitapAdi(p, v.kitap))
                })
            }
        }
        return a
    }

    // KUR
    static func kur(_ p: Paket, _ k: Int) -> [Aday] {
        p.cumleler.compactMap { c in
            let ak = "kur:\(c.id)"
            let kaynak = c.kaynak
            switch k {
            case 1:
                let parca = parcala(c.metin)
                guard parca.count >= 3 else { return nil }
                return Aday(anahtar: ak, kaynakId: c.id) {
                    Alistirma(hat: .kur, kademe: 1, kartAnahtari: ak, tip: .diz, baslik: "Cümleyi diz",
                              soru: "Parçaları doğru sıraya koy.", secenekler: parca.shuffled(), dogru: c.metin,
                              parcalar: parca, model: c.metin, aciklama: c.oz, kitap: c.kitap, kaynak: kaynak)
                }
            case 2:
                guard let hedef = c.anahtar.randomElement() else { return nil }
                let cel = p.cumleler.filter { $0.id != c.id }.flatMap(\.anahtar).shuffled().prefix(2)
                let bos = c.metin.replacingOccurrences(of: hedef, with: "_____", options: .caseInsensitive)
                return Aday(anahtar: ak, kaynakId: c.id) {
                    Alistirma(hat: .kur, kademe: 2, kartAnahtari: ak, tip: .sec, baslik: "Eksik parçayı bul",
                              soru: "Boşluğa hangisi gelir?", baglam: bos, secenekler: ([hedef] + cel).shuffled(),
                              dogru: hedef, model: c.metin, aciklama: c.oz, kitap: c.kitap, kaynak: kaynak)
                }
            case 3:
                return Aday(anahtar: ak, kaynakId: c.id) {
                    Alistirma(hat: .kur, kademe: 3, kartAnahtari: ak, tip: .yaz, baslik: "Anahtardan cümleye",
                              soru: "Bu kelimelerle cümleyi yeniden kur.", baglam: c.anahtar.joined(separator: " · "),
                              ipuclari: ["Fikir: \(c.oz)", "İlk kelimeler: " + c.metin.split(separator: " ").prefix(3).joined(separator: " ") + " …"],
                              anahtar: c.anahtar, model: c.metin, kitap: c.kitap, kaynak: kaynak)
                }
            case 4:
                return Aday(anahtar: ak, kaynakId: c.id) {
                    Alistirma(hat: .kur, kademe: 4, kartAnahtari: ak, tip: .yaz, baslik: "Fikirden cümleye",
                              soru: "Yalnız fikir veriliyor. Cümleyi kendi zihninden kur.", baglam: c.oz,
                              ipuclari: ["Anahtar: " + c.anahtar.joined(separator: " · "),
                                         "İlk kelimeler: " + c.metin.split(separator: " ").prefix(3).joined(separator: " ") + " …"],
                              anahtar: c.anahtar, model: c.metin, kitap: c.kitap, kaynak: kaynak)
                }
            case 5:
                return Aday(anahtar: ak + ":taklit", kaynakId: c.id) {
                    Alistirma(hat: .kur, kademe: 5, kartAnahtari: ak + ":taklit", tip: .yaz, baslik: "Taklit et",
                              soru: "Aynı yapıyla, başka bir konuda kendi cümleni kur.", baglam: c.metin,
                              ipuclari: ["Yapı: \(c.yapi)"], anahtar: [], model: c.taklit,
                              aciklama: "Taklit, kendi sesine giden en kısa yoldur.", kitap: c.kitap, kaynak: kaynak)
                }
            default:
                return Aday(anahtar: ak + ":paragraf", kaynakId: c.id) {
                    Alistirma(hat: .kur, kademe: 6, kartAnahtari: ak + ":paragraf", tip: .yaz, baslik: "Fikirden paragrafa",
                              soru: "Bu fikirden yola çıkarak üç cümlelik kendi paragrafını yaz.", baglam: c.oz,
                              ipuclari: ["Birinci cümle iddia, ikincisi gerekçe, üçüncüsü örnek.", "Kaynak cümle: \(c.metin)"],
                              anahtar: c.anahtar, model: c.metin, kitap: c.kitap, kaynak: kaynak)
                }
            }
        }
    }

    /// Cümleyi 3-6 anlamlı parçaya böler (virgül ve iki nokta önce, sonra kelime öbekleri).
    static func parcala(_ s: String) -> [String] {
        let kelime = s.split(separator: " ").map(String.init)
        let hedef = min(6, max(3, kelime.count / 3))
        let boy = Int((Double(kelime.count) / Double(hedef)).rounded(.up))
        var p: [String] = []
        var i = 0
        while i < kelime.count {
            var j = min(kelime.count, i + boy)
            // virgülde kes
            if let v = (i..<j).first(where: { kelime[$0].hasSuffix(",") || kelime[$0].hasSuffix(":") || kelime[$0].hasSuffix(";") }), v + 1 < j, v + 1 - i >= 2 {
                j = v + 1
            }
            p.append(kelime[i..<j].joined(separator: " "))
            i = j
        }
        // aynı metinli iki parça olmasın (sıra belirsizleşir)
        return Set(p).count == p.count ? p : [s]
    }
}

// MARK: - Ölçüm

enum Olcum {
    static func sec(_ secilen: String, _ a: Alistirma) -> Double { secilen == a.dogru ? 1 : 0 }

    static func diz(_ dizilen: [String], _ a: Alistirma) -> Double {
        guard !a.parcalar.isEmpty else { return 0 }
        if dizilen == a.parcalar { return 1 }
        let yerinde = zip(dizilen, a.parcalar).filter { $0 == $1 }.count
        return Double(yerinde) / Double(a.parcalar.count) * 0.8
    }

    static func bosluk(_ cevap: String, _ a: Alistirma, ipucu: Int) -> (Double, Dil.Esleme) {
        let e = Dil.esle(cevap, a.dogru)
        let taban: Double = e == .tam ? 1 : (e == .yakin ? 0.85 : 0)
        guard taban > 0 else { return (0, e) }
        return (max(0.5, taban - 0.15 * Double(ipucu)), e)
    }

    /// Serbest yazının öneri puanı (kullanıcı son kararı verir).
    static func oneri(_ cevap: String, _ a: Alistirma) -> Double {
        let kelime = Dil.kelimeler(cevap).count
        guard kelime >= 3 else { return 0 }
        if a.anahtar.isEmpty { return kelime >= 6 ? 0.85 : 0.5 }
        let k = Dil.kapsam(cevap, a.anahtar).oran
        let b = a.hat == .kur && a.kademe <= 4 ? Dil.benzerlik(cevap, a.model) : 0
        let p = max(k, b * 1.4)
        switch p {
        case ..<0.25: return 0
        case ..<0.6: return 0.5
        case ..<0.95: return 0.85
        default: return 1
        }
    }

    /// Güven + puan → FSRS notu. Şansla bilinen (güven düşük) "zor" sayılır.
    static func not(_ puan: Double, guven: Int?) -> Not {
        let n = Not.puandan(puan)
        if guven == 1 && (n == .iyi || n == .kolay) { return .zor }
        if guven == 3 && n == .iyi && puan >= 0.99 { return .kolay }
        return n
    }
}
