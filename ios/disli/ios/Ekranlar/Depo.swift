// Uygulamanın durumu: gömülü veri + cihazdaki ilerleme (Documents/durum.json).
//
// Kurallar (vault'tan):
//  • Vade yok. Bir konunun geri dönüşü takvime değil oturum sayısına bağlı (N+1 · N+3 · N+7 · N+16).
//    Ara verirsen oturum sayısı ilerlemez; hiçbir şey birikmez, "bekleyen" sayısı hiçbir yerde gösterilmez.
//  • Seri yok, puan tablosu yok. Oyun puanı oyunun içinde kalır.
//  • Tanıma → kurma merdiveni: bir konu tanımada 3 kez tutunca ona artık şık sorusu sorulmaz, yalnız kurdurulur.
import SwiftUI
import WidgetKit

struct KonuDurum: Codable {
    var goruldu = false
    var tanima = 0          // seçmeli / hata bulma doğruları
    var kurma = 0           // taşla kurma doğruları
    var yazma = 0           // klavyeyle yazma doğruları
    var yazmaOturum: [Int] = []
    var takildi = 0
    var donus: [Int] = []   // hangi oturumlarda geri gelecek

    var kademe: Int {
        if Set(yazmaOturum).count >= 2 && kurma >= 3 { return 4 }
        if kurma >= 3 { return 3 }
        if tanima >= 3 { return 2 }
        if goruldu || tanima + kurma + yazma + takildi > 0 { return 1 }
        return 0
    }
}

struct Ayarlar: Codable {
    var ses = true
    var haptik = true
    var gorunum = 0     // 0 sistem · 1 açık · 2 koyu
    var sesHizi = 0.46
}

struct Durum: Codable {
    var konular: [String: KonuDurum] = [:]
    var oturum = 0
    var gununKonusu: String?
    var gununTarihi: String?
    var bugunBitti: [String] = []   // "kart", "quiz", "oyun" — yalnız bugünün işaretleri, ertesi gün silinir
    var ayar = Ayarlar()
}

enum SoruKipi: String { case sec, bul, diz, yaz }

struct QuizOgesi: Identifiable, Hashable {
    let id = UUID()
    let konu: Konu
    let soru: Soru
    let kip: SoruKipi
}

@Observable
final class Depo {
    let veri: Veri
    var durum: Durum { didSet { kaydet() } }

    @ObservationIgnored private let konuSozluk: [String: Konu]
    @ObservationIgnored private let dosya: URL

    init() {
        let url = Bundle.main.url(forResource: "konular", withExtension: "json")!
        veri = try! JSONDecoder().decode(Veri.self, from: Data(contentsOf: url))
        konuSozluk = Dictionary(uniqueKeysWithValues: veri.konular.map { ($0.id, $0) })
        dosya = URL.documentsDirectory.appending(path: "durum.json")
        if let d = try? Data(contentsOf: dosya), let x = try? JSONDecoder().decode(Durum.self, from: d) {
            durum = x
        } else {
            durum = Durum()
        }
        gunuYenile()
    }

    private func kaydet() {
        if let d = try? JSONEncoder().encode(durum) { try? d.write(to: dosya, options: .atomic) }
    }

    // MARK: - Erişim

    func konu(_ id: String) -> Konu? { konuSozluk[id] }
    func yasa(_ id: String) -> Yasa? { veri.yasalar.first { $0.id == id } }
    func bolge(_ id: String) -> Bolge? { veri.bolgeler.first { $0.id == id } }
    func kd(_ id: String) -> KonuDurum { durum.konular[id] ?? KonuDurum() }
    func kademe(_ id: String) -> Int { kd(id).kademe }
    func renk(_ k: Konu) -> Color { Tema.renk(bolge(k.bolge)?.renk ?? "mavi") }
    func konular(bolge: String) -> [Konu] { veri.konular.filter { $0.bolge == bolge } }

    /// Bu konuyla en az bir yasayı paylaşan konular, yasaya göre gruplu.
    func baglar(_ k: Konu) -> [(Yasa, [Konu])] {
        k.yasalar.compactMap { ky in
            guard let y = yasa(ky.id) else { return nil }
            return (y, y.konular.filter { $0 != k.id }.compactMap { konu($0) })
        }
    }

    /// Aynı yasayı kullanan konular, yakınlık sırasıyla: aynı bölge → ortak yasa sayısı → önerilen yol.
    func komsular(_ k: Konu, yasa y: Yasa) -> [Konu] {
        let benim = Set(k.yasalar.map(\.id))
        let yol = Dictionary(uniqueKeysWithValues: veri.yol.enumerated().map { ($1, $0) })
        return y.konular.filter { $0 != k.id }.compactMap { konu($0) }.sorted { a, b in
            let ab = a.bolge == k.bolge ? 0 : 1, bb = b.bolge == k.bolge ? 0 : 1
            if ab != bb { return ab < bb }
            let ao = benim.intersection(a.yasalar.map(\.id)).count, bo = benim.intersection(b.yasalar.map(\.id)).count
            if ao != bo { return ao > bo }
            return (yol[a.id] ?? 999) < (yol[b.id] ?? 999)
        }
    }

    var gorulenler: [Konu] { veri.konular.filter { kademe($0.id) > 0 } }

    // MARK: - Günün dişlisi

    private static var bugunMetni: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: .now)
    }

    func gunuYenile() {
        let bugun = Self.bugunMetni
        guard durum.gununTarihi != bugun || durum.gununKonusu == nil else { return }
        durum.gununTarihi = bugun
        durum.bugunBitti = []
        // Yoldaki ilk görülmemiş konu; hepsi görüldüyse en düşük kademedeki
        let siradaki = veri.yol.first { kademe($0) == 0 }
            ?? veri.yol.min { kademe($0) < kademe($1) }
        durum.gununKonusu = siradaki
        widgetiYaz()
    }

    var gununKonusu: Konu? { durum.gununKonusu.flatMap { konu($0) } }

    func bugunuDegistir(_ id: String) {
        durum.gununKonusu = id
        durum.bugunBitti.removeAll { $0 == "kart" || $0 == "quiz" }
        widgetiYaz()
    }

    func bitti(_ adim: String) {
        if !durum.bugunBitti.contains(adim) { durum.bugunBitti.append(adim) }
    }

    func widgetiYaz() {
        guard let k = gununKonusu else { return }
        let y = k.yasalar.first.flatMap { yasa($0.id) }
        WidgetVerisi(id: k.id, ad: k.ad, tr: k.tr, formul: k.formul, tuzakY: k.tuzakAyrik.y, tuzakD: k.tuzakAyrik.d,
                     imge: k.imge, renk: bolge(k.bolge)?.renk ?? "mavi", yasaAd: y?.ad ?? "", yasaSembol: y?.sembol ?? "circle", yasaId: y?.id).yaz()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - İlerleme

    func gordu(_ id: String) {
        var d = kd(id)
        guard !d.goruldu else { return }
        d.goruldu = true
        d.donus = [1, 3, 7, 16].map { durum.oturum + $0 }
        durum.konular[id] = d
    }

    func kaydet(konu id: String, kip: SoruKipi, dogru: Bool) {
        var d = kd(id)
        if dogru {
            switch kip {
            case .sec, .bul: d.tanima += 1
            case .diz: d.kurma += 1
            case .yaz:
                d.yazma += 1; d.kurma += 1
                if !d.yazmaOturum.contains(durum.oturum) { d.yazmaOturum.append(durum.oturum) }
            }
        } else {
            d.takildi += 1
            // takılan konu yakında yine gelir — takvime değil oturuma bağlı
            d.donus = Array(Set(d.donus + [durum.oturum + 1, durum.oturum + 3])).sorted()
        }
        durum.konular[id] = d
    }

    /// Bugünün mini quiz'i bitince oturum bir ilerler; dönüş listesinden geçmiş olanlar düşer (borç birikmez).
    func oturumuKapat(sunulanlar: [String]) {
        durum.oturum += 1
        for id in Set(sunulanlar) {
            var d = kd(id)
            d.donus.removeAll { $0 <= durum.oturum }
            durum.konular[id] = d
        }
    }

    // MARK: - Soru seçimi

    /// Konunun kademesine göre soru kipi. Tanıma tuttuysa (kademe ≥ 2) şık ve hata-bulma sorulmaz.
    func kip(_ k: Konu, _ s: Soru) -> SoruKipi? {
        let kad = kademe(k.id)
        switch s.tur {
        case .bosluk:
            if kad < 2 { return .sec }
            if kad == 2 { return .diz }
            return .yaz
        case .hata: return kad < 2 ? .bul : nil
        case .sirala: return .diz
        case .donustur: return kad >= 4 ? .yaz : .diz
        }
    }

    func sorular(_ k: Konu, adet: Int) -> [QuizOgesi] {
        let adaylar = k.sorular.shuffled().compactMap { s in kip(k, s).map { QuizOgesi(konu: k, soru: s, kip: $0) } }
        // Düşük kademede önce tanıma, sonra bir kurma; yüksek kademede karışık
        let sirali = adaylar.sorted { a, b in
            let oa = (a.kip == .sec || a.kip == .bul) ? 0 : 1, ob = (b.kip == .sec || b.kip == .bul) ? 0 : 1
            return oa < ob
        }
        if kademe(k.id) < 2, sirali.count > adet {
            // en az bir kurma sorusu kalsın
            var secim = Array(sirali.prefix(adet - 1))
            if let kur = sirali.first(where: { $0.kip == .diz }) { secim.append(kur) } else { secim.append(sirali[adet - 1]) }
            return secim
        }
        return Array(sirali.prefix(adet))
    }

    /// Günün mini quiz'i: günün konusundan 2 soru + geri dönen konulardan birer soru (en çok 3), toplam 5.
    func gununQuizi() -> [QuizOgesi] {
        guard let bugun = gununKonusu else { return [] }
        var liste = sorular(bugun, adet: 2)
        let donenler = veri.konular
            .filter { $0.id != bugun.id && kd($0.id).donus.contains { $0 <= durum.oturum } }
            .sorted { (kd($0.id).donus.min() ?? 0) < (kd($1.id).donus.min() ?? 0) }
            .prefix(3)
        for k in donenler { liste += sorular(k, adet: 1) }
        // dönen az ise görülen başka konulardan, o da yoksa günün konusundan tamamla
        var havuz = gorulenler.filter { $0.id != bugun.id && !donenler.contains($0) }.shuffled()
        while liste.count < 5, let k = havuz.popLast() { liste += sorular(k, adet: 1) }
        if liste.count < 5 {
            let kalan = sorular(bugun, adet: 6).filter { o in !liste.contains { $0.soru.id == o.soru.id } }
            liste += kalan.prefix(5 - liste.count)
        }
        return Array(liste.prefix(5))
    }

    var donenKonular: [Konu] {
        veri.konular.filter { $0.id != durum.gununKonusu && kd($0.id).donus.contains { $0 <= durum.oturum } }
    }

    /// Oyunlar için konu havuzu: görülenler yeterliyse onlar, değilse hepsi.
    func oyunHavuzu(enAz: Int = 6) -> [Konu] {
        let g = gorulenler
        return g.count >= enAz ? g : veri.konular
    }

    func sifirla() {
        let ayar = durum.ayar
        durum = Durum(ayar: ayar)
        gunuYenile()
    }
}
