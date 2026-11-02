// Günün içeriği: tarihe bağlı, belirlenimci. Aynı gün aynı kelime; duvar, widget ve kestirme aynı şeyi görür.
// Kelime havuzu vitrin.py'den B2 → B1 → A2 → A1 sırasıyla gelir; sıra günden güne ilerler, bilinenler atlanır.
import Foundation
import PDMBus

/// PDM Ağı'nın odağı: App Group önbelleğindeki `words.json` özeti (uygulama her açılışta tazeler, widget yalnız okur).
/// Odak kelimeleri günün ilk kelimeleridir; "biliyorum" denen ya da ağda bilinen kelime hiç çıkmaz.
enum AgOdak {
    private static var onbellek: (an: Date, ozet: PDMWordSummary?)?

    static var ozet: PDMWordSummary? {
        if let o = onbellek, Date().timeIntervalSince(o.an) < 20 { return o.ozet }
        let s = PDMBus.cachedWords()
        onbellek = (Date(), s)
        return s
    }

    static func sifirla() { onbellek = nil }

    /// Ağda `known` ya da `dropped` olanlar
    static var kapali: Set<String> { Set(ozet?.closed ?? []) }

    static func kelimeler(_ v: VitrinVeri, bilinen: Set<String>) -> [Kelime] {
        guard let s = ozet else { return [] }
        var dizin: [String: Kelime] = [:]
        for k in v.kelimeler where dizin[k.w.lowercased()] == nil { dizin[k.w.lowercased()] = k }
        return s.openFocus(extraClosed: bilinen).map { f in
            var k = dizin[f.word.lowercased()]
                ?? Kelime(w: f.word, ipa: "", tr: f.tr ?? "", trTam: f.tr ?? "", d: "", x: f.example ?? "",
                          c: f.cefr ?? "", p: "", au: "")
            k.neden = f.why
            return k
        }
    }
}

enum Secici {
    static let gunlukKelime = 6          // her gün altı kelime: biri duvarda, hepsi widget'ta sırayla
    private static let baslangic: Date = {
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 12
        return Calendar.current.date(from: c) ?? .now
    }()

    static func gunNo(_ d: Date) -> Int {
        let k = Calendar.current
        return max(0, k.dateComponents([.day], from: k.startOfDay(for: baslangic), to: k.startOfDay(for: d)).day ?? 0)
    }

    static func gunAnahtari(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: d)
    }

    /// Gün içindeki dilim: `dongu` dakikada bir ilerler
    static func dilim(_ d: Date, dongu: Int) -> Int {
        let bas = Calendar.current.startOfDay(for: d)
        return Int(d.timeIntervalSince(bas) / Double(max(1, dongu) * 60))
    }

    /// Günün altı kelimesi: önce PDM Ağı'nın odağı (sırasıyla), kalan yerler depodan gün gün ilerleyen sırayla.
    static func gununKelimeleri(_ v: VitrinVeri, _ d: Date, bilinen: Set<String>) -> [Kelime] {
        let odak = AgOdak.kelimeler(v, bilinen: bilinen)
        var out = Array(odak.prefix(gunlukKelime))
        let disari = AgOdak.kapali.union(bilinen.map { $0.lowercased() }).union(odak.map { $0.w.lowercased() })
        let havuz = v.kelimeler.filter { !disari.contains($0.w.lowercased()) }
        if out.count < gunlukKelime, !havuz.isEmpty {
            let bas = gunNo(d) * gunlukKelime
            for j in 0..<(gunlukKelime - out.count) { out.append(havuz[(bas + j) % havuz.count]) }
        }
        return out
    }

    static func kelime(_ v: VitrinVeri, _ d: Date, adim: Int = 0, bilinen: Set<String>) -> Kelime? {
        let l = gununKelimeleri(v, d, bilinen: bilinen)
        return l.isEmpty ? nil : l[adim % l.count]
    }

    static func alinti(_ v: VitrinVeri, _ d: Date, adim: Int = 0) -> Alinti? {
        guard !v.alintilar.isEmpty else { return nil }
        // Sabit adımlı karıştırma: ardışık günler aynı kitaptan gelmesin
        let i = (gunNo(d) * 7 + adim * 3) % v.alintilar.count
        return v.alintilar[(i * 37) % v.alintilar.count]
    }

    static func kavram(_ v: VitrinVeri, _ d: Date, adim: Int = 0) -> Kavram? {
        guard !v.kavramlar.isEmpty else { return nil }
        return v.kavramlar[(gunNo(d) * 3 + adim) % v.kavramlar.count]
    }
}

/// Bir tasarımın o an göstereceği içerik — görünümler bunu çizer.
struct Gosterilen: Hashable {
    var ust: String = ""          // küçük üst satır (seviye, kaynak türü…)
    var ana: String = ""          // büyük satır
    var ara: String = ""          // telaffuz / ikincil
    var alt: String = ""          // anlam, kaynak
    var ornek: String = ""        // örnek cümle
    var ses: String = ""          // Oxford ses adresi
    var satirlar: [String] = []   // odak listesi

    static func hesapla(_ tur: IcerikTuru, veri v: VitrinVeri, tarih d: Date, adim: Int,
                        bilinen: Set<String>, metin: String) -> Gosterilen {
        var g = Gosterilen()
        switch tur {
        case .kelime:
            if let k = Secici.kelime(v, d, adim: adim, bilinen: bilinen) {
                g.ust = k.neden ?? "\(k.c) · \(k.p)".uppercased(with: Locale(identifier: "en"))
                g.ana = k.w
                g.ara = k.ipa
                g.alt = k.tr
                g.ornek = k.x
                g.ses = k.au
            } else { g.ana = "Kelime yok"; g.alt = "Ayarlar'dan vault'u bağla" }
        case .alinti:
            if let a = Secici.alinti(v, d, adim: adim) {
                g.ust = a.tur == "aforizma" ? "Aforizma" : "İşaretin"
                g.ana = a.metin
                g.alt = a.kaynak
            }
        case .kavram:
            if let k = Secici.kavram(v, d, adim: adim) {
                g.ust = "Kavram"
                g.ana = k.terim
                g.alt = k.tanim
                g.ornek = k.kaynak
            }
        case .odak:
            g.ust = "Bugün"
            g.ana = v.odak.ana.isEmpty ? "Odak" : v.odak.ana
            g.satirlar = v.odak.satirlar.filter { $0.kademe == "ana" }.prefix(2).map { "\($0.ad) — \($0.bugun)" }
                + v.odak.satirlar.filter { $0.kademe == "destek" }.prefix(2).map { "\($0.ad) — \($0.bugun)" }
            if let by = v.odak.biryone, let gun = by.gun {
                g.alt = "Bir Yöne · Gün \(gun)"
            } else { g.alt = v.odak.hedef }
        case .metin:
            g.ana = metin.isEmpty ? "Kendi cümleni yaz" : metin
        default:
            break
        }
        return g
    }
}
