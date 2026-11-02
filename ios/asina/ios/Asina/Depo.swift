// Uygulamanın tek durumu: kelime verisi + öğrenme kaydı + ayarlar.
//
// Tasarım kuralı (vault'tan): vade borcu üretme. Günlük tekrar tavanı aşılırsa fazlası sessizce
// ertesi güne kayar; "234 kelime bekliyor" diye bir sayı hiçbir yerde gösterilmez. Gün atlanırsa
// yeni kelime birikmez — aynı sıradaki kelimeler kaldığı yerden gelir.
import Foundation
import SwiftUI
import WidgetKit
import PDMBus

struct Ayarlar: Codable, Equatable {
    var yeniSayisi = 10
    /// Her gün, kelimelerin yanında kaç yeni deyimsel fiil (phrasal verb) gelsin
    var pvSayisi = 3
    var tekrarTavani = 60
    var bildirimSayisi = 6
    var bildirimBas = 9
    var bildirimSon = 21
    var hatirlatma = true
    var hatirlatmaSaati = 20
    var oxfordSesi = true
    var otomatikSes = true
    var onceHatirla = false
    /// Cümle Tezgâhı'nın günün 6 kelimesinin her biri günde kaç kez bildirim olarak gelsin
    var cumleTekrar = 2
    /// Ayar göçü: 1 = VocuTeach (bildirim sayısı 6 → 10)
    var ayarSurum = 1

    init() {}

    // Sonradan eklenen ayarlar eski kayıt dosyasını bozmasın: eksik alan varsayılanı alır.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let v = Ayarlar()
        yeniSayisi = try c.decodeIfPresent(Int.self, forKey: .yeniSayisi) ?? v.yeniSayisi
        pvSayisi = try c.decodeIfPresent(Int.self, forKey: .pvSayisi) ?? v.pvSayisi
        tekrarTavani = try c.decodeIfPresent(Int.self, forKey: .tekrarTavani) ?? v.tekrarTavani
        bildirimSayisi = try c.decodeIfPresent(Int.self, forKey: .bildirimSayisi) ?? v.bildirimSayisi
        bildirimBas = try c.decodeIfPresent(Int.self, forKey: .bildirimBas) ?? v.bildirimBas
        bildirimSon = try c.decodeIfPresent(Int.self, forKey: .bildirimSon) ?? v.bildirimSon
        hatirlatma = try c.decodeIfPresent(Bool.self, forKey: .hatirlatma) ?? v.hatirlatma
        hatirlatmaSaati = try c.decodeIfPresent(Int.self, forKey: .hatirlatmaSaati) ?? v.hatirlatmaSaati
        oxfordSesi = try c.decodeIfPresent(Bool.self, forKey: .oxfordSesi) ?? v.oxfordSesi
        otomatikSes = try c.decodeIfPresent(Bool.self, forKey: .otomatikSes) ?? v.otomatikSes
        onceHatirla = try c.decodeIfPresent(Bool.self, forKey: .onceHatirla) ?? v.onceHatirla
        cumleTekrar = try c.decodeIfPresent(Int.self, forKey: .cumleTekrar) ?? v.cumleTekrar
        ayarSurum = try c.decodeIfPresent(Int.self, forKey: .ayarSurum) ?? 0
        if ayarSurum < 1 {
            // VocuTeach: daha çok maruz kalma — eski varsayılan 6 bildirim 10'a çıkar.
            bildirimSayisi = max(bildirimSayisi, 10)
            ayarSurum = 1
        }
    }
}

struct Kayit: Codable {
    var kartlar: [String: Kart] = [:]
    var kararlar: [String: Karar] = [:]
    var gunler: [String: GunKaydi] = [:]
    /// gün → o günün yeni kelimeleri (sabit kalsın diye bir kez seçilir)
    var gunYenileri: [String: [Int]] = [:]
    /// Bildirimden "oturumda sor" denenler
    var oneAlinan: [Int] = []
    /// Bildirimde "biliyordum" denen karşılaşmalar
    var maruz: Int = 0
    /// Ayıklamada "bilmiyorum" denenler — ayıklama destesine bir daha gelmez, öğrenme sırası değişmez
    var ayiklandi: Set<String> = []
    var ayar = Ayarlar()
    var olusturma = Date()
    /// Cümle Tezgâhı günü elle seçildiyse (vault bağlı değilken masa ilerlemezse)
    var cumleSecim: Int? = nil

    init() {}

    // Yeni alan eklendiğinde eski kayıt dosyası okunabilsin diye her alan isteğe bağlı çözülür.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        kartlar = try c.decodeIfPresent([String: Kart].self, forKey: .kartlar) ?? [:]
        kararlar = try c.decodeIfPresent([String: Karar].self, forKey: .kararlar) ?? [:]
        gunler = try c.decodeIfPresent([String: GunKaydi].self, forKey: .gunler) ?? [:]
        gunYenileri = try c.decodeIfPresent([String: [Int]].self, forKey: .gunYenileri) ?? [:]
        oneAlinan = try c.decodeIfPresent([Int].self, forKey: .oneAlinan) ?? []
        maruz = try c.decodeIfPresent(Int.self, forKey: .maruz) ?? 0
        ayiklandi = try c.decodeIfPresent(Set<String>.self, forKey: .ayiklandi) ?? []
        ayar = (try? c.decodeIfPresent(Ayarlar.self, forKey: .ayar)) ?? Ayarlar()
        olusturma = try c.decodeIfPresent(Date.self, forKey: .olusturma) ?? Date()
        cumleSecim = try c.decodeIfPresent(Int.self, forKey: .cumleSecim)
    }
}

@MainActor
final class Depo: ObservableObject {
    @Published private(set) var kelimeler: [Kelime] = []
    @Published private(set) var yuklendi = false
    @Published var kayit = Kayit()
    @Published var acilacakKelime: Kelime?
    @Published var paketSurum = ""
    @Published private(set) var cumlePaket: CumlePaket?

    let kasa = Kasa()
    /// PDM Ağı: kararlar `_bus/events/vocuteach/` altına olay olarak gider; odak `_bus/state/words.json`'dan gelir.
    let bus = PDMBus(app: "vocuteach", vaultRoot: { Kasa.kokCoz() })
    @Published private(set) var busRapor: PDMBus.Report?
    /// Ağın bugünkü odak kelimeleri (Cümle'nin günü, zorlandıkların, Kelime Eki) — App Group önbelleğinden
    @Published private(set) var agOdak: [PDMFocusWord] = []
    private var dizin: [Int: Int] = [:]
    private var adDizin: [String: Int] = [:]
    private var depoSirali: [Kelime] = []
    private var pvSirali: [Kelime] = []
    private var kayitGorevi: Task<Void, Never>?

    var ayar: Ayarlar {
        get { kayit.ayar }
        set { kayit.ayar = newValue; kaydet(); planla() }
    }

    // MARK: Yükleme

    nonisolated private static var kayitURL: URL { Paylasim.kapsayici.appendingPathComponent("kayit.json") }
    nonisolated private static var paketURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("kelimeler.json")
    }

    func yukle() async {
        if yuklendi { return }
        let kayit = await Task.detached { () -> Kayit in
            let dec = JSONDecoder()
            if let v = try? Data(contentsOf: Self.kayitURL), let k = try? dec.decode(Kayit.self, from: v) { return k }
            return Kayit()
        }.value
        self.kayit = kayit
        if let p = await Self.paketOku() { paketKur(p) }
        agOdak = PDMBus.cachedWords()?.openFocus() ?? []
        yuklendi = true
        // Uygulama kapalıyken bildirimden gelen eylemler
        if let l = UserDefaults.standard.array(forKey: "bekleyenEylem") as? [String] {
            UserDefaults.standard.removeObject(forKey: "bekleyenEylem")
            for s in l {
                let p = s.split(separator: "|")
                if p.count == 2, let id = Int(p[1]) { bildirimEylemi(String(p[0]), id: id) }
            }
        }
        planla()
        await eslestir()
    }

    nonisolated private static func paketOku() async -> Paket? {
        await Task.detached {
            let dec = JSONDecoder()
            // Vault'tan gelmiş daha yeni kopya varsa o, yoksa uygulamaya gömülü olan.
            var adaylar: [Paket] = []
            if let v = try? Data(contentsOf: paketURL), let p = try? dec.decode(Paket.self, from: v) { adaylar.append(p) }
            if let u = Bundle.main.url(forResource: "kelimeler", withExtension: "json"),
               let v = try? Data(contentsOf: u), let p = try? dec.decode(Paket.self, from: v) { adaylar.append(p) }
            return adaylar.max { $0.surum < $1.surum }
        }.value
    }

    private func paketKur(_ p: Paket) {
        kelimeler = p.kelimeler
        paketSurum = p.surum
        dizin = Dictionary(p.kelimeler.enumerated().map { ($1.i, $0) }, uniquingKeysWith: { ilk, _ in ilk })   // a word listed twice must not crash
        adDizin = Dictionary(p.kelimeler.enumerated().map { ($1.w, $0) }, uniquingKeysWith: { a, _ in a })
        depoSirali = p.kelimeler.filter { $0.s == "d" && !$0.isPV }.sorted { ($0.o ?? 0) < ($1.o ?? 0) }
        pvSirali = p.kelimeler.filter { $0.isPV }.sorted { ($0.o ?? 0) < ($1.o ?? 0) }
        cumlePaket = p.cumle
        // Masa elle seçilen günü geçtiyse seçim düşer; masa artık doğru günü gösteriyor.
        if let s = kayit.cumleSecim, let m = p.cumle?.masa, m >= s { kayit.cumleSecim = nil }
    }

    // MARK: Cümle Tezgâhı

    /// Bugün gösterilen Cümle günü: elle seçilen, yoksa masadaki.
    var cumleGunu: CumleGun? {
        guard let p = cumlePaket else { return nil }
        let hedef = kayit.cumleSecim ?? p.masa
        return p.gunler.first { $0.gun == hedef } ?? p.gunler.first
    }

    var cumleGunNumaralari: [Int] { cumlePaket?.gunler.map(\.gun) ?? [] }

    func cumleGunuSec(_ n: Int) {
        kayit.cumleSecim = n == cumlePaket?.masa ? nil : n
        // Bugünün listesi yeni günün kelimeleriyle yeniden kurulsun
        if let g = cumleGunu { cumleyiOneAl(g) }
        kaydet()
    }

    /// Bugünün Cümle kelimeleri: (Oxford kaydı, Tezgâh cümlesi)
    var cumleKelimeleri: [(Kelime, CumleKelime)] {
        (cumleGunu?.kelimeler ?? []).compactMap { c in kelime(ad: c.w).map { ($0, c) } }
    }

    /// Cümle kelimelerini bugünün yeni kelimelerinin başına koyar (bilinen/zaten öğrenilen hariç).
    private func cumleyiOneAl(_ g: CumleGun) {
        let gun = Date().gunAnahtari
        var l = kayit.gunYenileri[gun] ?? []
        let ekle = g.kelimeler.compactMap { kelime(ad: $0.w) }
            .filter { kayit.kararlar[$0.w] == nil && !l.contains($0.i) }
            .map(\.i)
        guard !ekle.isEmpty else { return }
        l = ekle + l
        kayit.gunYenileri[gun] = l
    }

    func kelime(_ id: Int) -> Kelime? { dizin[id].map { kelimeler[$0] } }
    func kelime(ad: String) -> Kelime? { adDizin[ad].map { kelimeler[$0] } }
    func kart(_ k: Kelime) -> Kart? { kayit.kartlar[k.w] }

    // MARK: Kayıt

    func kaydet() {
        let k = kayit
        kayitGorevi?.cancel()
        kayitGorevi = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
            if let v = try? JSONEncoder().encode(k) { try? v.write(to: Self.kayitURL, options: .atomic) }
        }
    }

    // MARK: Günün destesi

    private func dokunulmamis(_ k: Kelime) -> Bool {
        kayit.kartlar[k.w] == nil && kayit.kararlar[k.w] == nil
    }

    /// Bugün ve sonraki günlerin yeni kelimeleri. Bugünkü liste bir kez seçilir ve gün boyu sabit kalır.
    func yeniler(gun: Date = Date()) -> [Kelime] {
        let bugun = Date().gunAnahtari
        if gun.gunAnahtari == bugun, let ids = kayit.gunYenileri[bugun] {
            return ids.compactMap(kelime)
        }
        let ofset = max(0, Calendar.current.dateComponents([.day], from: Date().gunBasi, to: gun.gunBasi).day ?? 0)
        let bugunkuler = Set(kayit.gunYenileri[bugun] ?? [])
        let aday = depoSirali.lazy.filter { self.dokunulmamis($0) && !bugunkuler.contains($0.i) }
        let pvAday = pvSirali.lazy.filter { self.dokunulmamis($0) && !bugunkuler.contains($0.i) }
        let n = ayar.yeniSayisi, m = ayar.pvSayisi
        if ofset == 0 {
            let cumle = cumleKelimeleri.map(\.0).filter { self.dokunulmamis($0) }
            let cs = Set(cumle.map(\.i))
            // Ağın odağı günlük sayının içinden yer alır; toplam değişmez.
            let odak = Array(agOdakKelimeleri.filter { !cs.contains($0.i) }.prefix(n))
            let os = cs.union(odak.map(\.i))
            return cumle + odak + Array(aday.filter { !os.contains($0.i) }.prefix(n - odak.count)) + Array(pvAday.prefix(m))
        }
        // Gelecek günler (widget/bildirim için): bugünkülerin ardından gelenler
        let k = ofset - 1
        return Array(aday.dropFirst(k * n).prefix(n)) + Array(pvAday.dropFirst(k * m).prefix(m))
    }

    /// Ağın odak kelimelerinden VocuTeach deposunda karşılığı olan ve henüz dokunulmamışlar, ağın sırasıyla.
    var agOdakKelimeleri: [Kelime] {
        agOdak.compactMap { kelime(ad: $0.word) ?? kelime(ad: $0.word.lowercased()) }.filter { dokunulmamis($0) && !$0.isPV }
    }

    /// Bugünün sabit listesine sonradan gelen odak kelimelerini koyar; yerlerine sıradan depo kelimeleri çıkar.
    private func agOdaginiOneAl() {
        let g = Date().gunAnahtari
        guard var l = kayit.gunYenileri[g] else { return }
        let ekle = agOdakKelimeleri.filter { !l.contains($0.i) }.prefix(ayar.yeniSayisi).map(\.i)
        guard !ekle.isEmpty else { return }
        let korunan = Set(cumleKelimeleri.map(\.0.i) + agOdakKelimeleri.map(\.i))
        var cikar = ekle.count
        for i in stride(from: l.count - 1, through: 0, by: -1) where cikar > 0 {
            if let k = kelime(l[i]), dokunulmamis(k), !k.isPV, !korunan.contains(k.i) { l.remove(at: i); cikar -= 1 }
        }
        kayit.gunYenileri[g] = Array(ekle) + l
        kaydet()
    }

    func bugunuSabitle() {
        let g = Date().gunAnahtari
        if kayit.gunYenileri[g] == nil {
            kayit.gunYenileri[g] = yeniler().map(\.i)
            // Eski günlerin listeleri gereksiz; son 14 gün kalsın.
            let esik = Date().gun(-14).gunAnahtari
            kayit.gunYenileri = kayit.gunYenileri.filter { $0.key >= esik }
            kaydet()
        } else if let cg = cumleGunu, let l = kayit.gunYenileri[g],
                  cg.kelimeler.contains(where: { c in
                      kelime(ad: c.w).map { !l.contains($0.i) && kayit.kararlar[$0.w] == nil } ?? false }) {
            // Cümle Tezgâhı'nın günü değişti ya da bu özellikten önce sabitlenmiş liste
            cumleyiOneAl(cg)
            kaydet()
        } else if ayar.pvSayisi > 0, var l = kayit.gunYenileri[g],
                  !l.contains(where: { kelime($0)?.isPV == true }) {
            // Deyimsel fiil özelliğinden önce sabitlenmiş bugünün listesine bir kez ekle
            let mevcut = Set(l)
            l += pvSirali.lazy.filter { self.dokunulmamis($0) && !mevcut.contains($0.i) }
                .prefix(ayar.pvSayisi).map(\.i)
            kayit.gunYenileri[g] = l
            kaydet()
        }
    }

    /// Bugün tanışılmamış yeni kelimeler
    var bekleyenYeniler: [Kelime] {
        yeniler().filter { dokunulmamis($0) }
    }

    /// Bugün sorulacak tekrarlar — en çok unutulmak üzere olandan başlayarak, tavanla.
    var bekleyenTekrarlar: [Kelime] {
        let son = Date().gunSonu
        let yapilan = bugunKaydi.tekrar
        let kalanHak = max(0, ayar.tekrarTavani - yapilan)
        let one = Set(kayit.oneAlinan)
        let vadeli = kayit.kartlar.filter { $0.value.vade <= son && $0.value.son < Date().gunBasi }
            .compactMap { (ad, kart) -> (Kelime, Double)? in
                guard let k = kelime(ad: ad) else { return nil }
                return (k, one.contains(k.i) ? -1 : kart.hatirlama())
            }
            .sorted { $0.1 < $1.1 }
        return Array(vadeli.prefix(kalanHak).map(\.0))
    }

    var bugunKaydi: GunKaydi { kayit.gunler[Date().gunAnahtari] ?? GunKaydi() }

    var bugunHedef: Int {
        let k = bugunKaydi
        return k.yeni + k.tekrar + bekleyenYeniler.count + bekleyenTekrarlar.count
    }

    var bugunYapilan: Int { bugunKaydi.yeni + bugunKaydi.tekrar }

    var seri: Int {
        var n = 0
        var g = Date()
        if (kayit.gunler[g.gunAnahtari].map { $0.yeni + $0.tekrar } ?? 0) == 0 { g = g.gun(-1) }
        while let k = kayit.gunler[g.gunAnahtari], k.yeni + k.tekrar > 0 {
            n += 1
            g = g.gun(-1)
        }
        return n
    }

    func sayim(_ a: Asama) -> Int { kayit.kartlar.values.filter { $0.asama == a }.count }
    var depoKalan: Int { depoSirali.filter { dokunulmamis($0) }.count }
    var depoToplam: Int { depoSirali.count }
    var pvToplam: Int { pvSirali.count }
    var pvDokunulan: Int { pvSirali.filter { !dokunulmamis($0) }.count }

    // MARK: Deyimsel fiil grupları

    /// Aynı fiilden türeyen deyimsel fiiller ("take off · take on · take up …") — ayırt etmek için yan yana.
    func ayniFiil(_ k: Kelime) -> [Kelime] {
        pvSirali.filter { $0.taban == k.taban && $0.w != k.w }
    }

    /// Tabana göre gruplar: en kalabalık fiil önce
    var pvGruplari: [(taban: String, kelimeler: [Kelime])] {
        Dictionary(grouping: pvSirali, by: \.taban)
            .map { ($0.key, $0.value) }
            .sorted { $0.1.count != $1.1.count ? $0.1.count > $1.1.count : $0.0 < $1.0 }
    }
    var biliyorumSayisi: Int { kayit.kararlar.values.filter { $0 == .biliyorum }.count }

    // MARK: Cevaplar

    func tanis(_ k: Kelime, _ n: Not) {
        guard kayit.kartlar[k.w] == nil else { return cevap(k, n) }
        kayit.kartlar[k.w] = FSRS.yeni(n)
        gunuIsle { $0.yeni += 1; if n != .unuttum { $0.dogru += 1 } }
        degisti()
    }

    func cevap(_ k: Kelime, _ n: Not) {
        guard let eski = kayit.kartlar[k.w] else { return tanis(k, n) }
        let ayniGun = eski.son >= Date().gunBasi
        kayit.kartlar[k.w] = FSRS.tekrar(eski, n)
        // Kart "tanıdık" eşiğini (21 gün) ilk kez geçti: ağa word.learning (eski köprünün `tanidik` listesi)
        if eski.kararlilik < 21, (kayit.kartlar[k.w]?.kararlilik ?? 0) >= 21 { olay("word.learning", k, ["stability": .int(21)]) }
        kayit.oneAlinan.removeAll { $0 == k.i }
        if !ayniGun { gunuIsle { $0.tekrar += 1; if n != .unuttum { $0.dogru += 1 } } }
        degisti()
    }

    func biliyorum(_ k: Kelime) {
        kayit.kararlar[k.w] = .biliyorum
        kayit.kartlar[k.w] = nil
        olay("word.known", k)
        degisti()
    }

    /// Ayıklama destesi: bugünün listesinden sonra gelen, henüz ayıklanmamış depo kelimeleri.
    func ayiklamaDestesi(_ n: Int = 20) -> [Kelime] {
        let bugunku = Set(kayit.gunYenileri[Date().gunAnahtari] ?? [])
        return Array(depoSirali.lazy.filter {
            self.dokunulmamis($0) && !bugunku.contains($0.i) && !self.kayit.ayiklandi.contains($0.w)
        }.prefix(n))
    }

    func ayikla(_ k: Kelime, biliyor: Bool) {
        if biliyor { kayit.kararlar[k.w] = .biliyorum; olay("word.known", k, ["via": "ayikla"]) } else { kayit.ayiklandi.insert(k.w) }
        degisti()
    }

    func ayiklamaGeriAl(_ k: Kelime) {
        if kayit.kararlar[k.w] == .biliyorum { kayit.kararlar[k.w] = nil; olay("word.learning", k, ["via": "undo"]) }
        kayit.ayiklandi.remove(k.w)
        degisti()
    }

    func geriAl(_ k: Kelime) {
        if kayit.kararlar[k.w] == .biliyorum { olay("word.learning", k, ["via": "undo"]) }
        kayit.kararlar[k.w] = nil
        kayit.kartlar[k.w] = nil
        degisti()
    }

    /// Depodan bir kelimeyi bugünün listesine alır.
    func simdiOgren(_ k: Kelime) {
        if kayit.kararlar[k.w] == .biliyorum { olay("word.learning", k, ["via": "learn-now"]) }
        kayit.kararlar[k.w] = nil
        let g = Date().gunAnahtari
        var l = kayit.gunYenileri[g] ?? yeniler().map(\.i)
        if !l.contains(k.i) { l.insert(k.i, at: 0) }
        kayit.gunYenileri[g] = l
        degisti()
    }

    /// "Bugün biraz daha" — sıradaki n kelimeyi bugünün listesine ekler. Yarının sayısını değiştirmez.
    func dahaFazla(_ n: Int) {
        let g = Date().gunAnahtari
        var l = kayit.gunYenileri[g] ?? []
        let mevcut = Set(l)
        l += depoSirali.lazy.filter { self.dokunulmamis($0) && !mevcut.contains($0.i) }.prefix(n).map(\.i)
        kayit.gunYenileri[g] = l
        degisti()
    }

    func oneAl(_ id: Int) {
        if !kayit.oneAlinan.contains(id) { kayit.oneAlinan.append(id) }
        if let k = kelime(id), kayit.kartlar[k.w] != nil {
            kayit.kartlar[k.w]?.vade = Date().gunBasi
            kayit.kartlar[k.w]?.son = min(kayit.kartlar[k.w]!.son, Date().gun(-1))
        } else if let k = kelime(id) {
            simdiOgren(k)
        }
        degisti()
    }

    func oturumSuresi(_ sn: Double) {
        gunuIsle { $0.sure += sn; $0.bitti = self.bekleyenYeniler.isEmpty && self.bekleyenTekrarlar.isEmpty }
        degisti()
    }

    private func gunuIsle(_ f: (inout GunKaydi) -> Void) {
        let g = Date().gunAnahtari
        var k = kayit.gunler[g] ?? GunKaydi()
        f(&k)
        kayit.gunler[g] = k
    }

    private var planGorevi: Task<Void, Never>?
    private func degisti() {
        objectWillChange.send()
        kaydet()
        planGorevi?.cancel()
        planGorevi = Task {
            try? await Task.sleep(for: .milliseconds(1500))
            if Task.isCancelled { return }
            planla()
        }
    }

    // MARK: Widget + bildirim + vault

    /// Widget'ın anlık görüntüsünü ve bildirimleri yeniden kurar.
    func planla() {
        guard yuklendi else { return }
        bugunuSabitle()
        var gunler: [String: [WKelime]] = [:]
        let ogrenilen = kayit.kartlar
            .filter { $0.value.kararlilik < 21 }
            .sorted { $0.value.hatirlama() < $1.value.hatirlama() }
            .compactMap { kelime(ad: $0.key) }
        for ofset in 0..<3 {
            let gun = Date().gun(ofset)
            let yeniK = yeniler(gun: gun)
            let yeniAd = Set(yeniK.map(\.w))
            var l = yeniK.filter { kayit.kartlar[$0.w] == nil }.map { wk($0, asama: -1) }
            let ek = ogrenilen.filter { !yeniAd.contains($0.w) || kayit.kartlar[$0.w] != nil }
                .dropFirst(ofset * 4).prefix(max(4, 12 - l.count))
            l += ek.map { wk($0, asama: kayit.kartlar[$0.w]?.asama.rawValue ?? 0) }
            gunler[gun.gunAnahtari] = karistir(l, tohum: ofset)
        }
        let hafta = (0..<7).reversed().map { i -> Int in
            let k = kayit.gunler[Date().gun(-i).gunAnahtari]
            return (k?.yeni ?? 0) + (k?.tekrar ?? 0)
        }
        let cg = cumleGunu
        let cumle = cumleKelimeleri.map { k, c -> WKelime in
            var w = wk(k, asama: kayit.kartlar[k.w]?.asama.rawValue ?? -1)
            w.cg = cg?.gun
            w.cu = c.en.isEmpty ? nil : c.en
            w.ct = c.tr.isEmpty ? nil : c.tr
            return w
        }
        // Widget'ın kelime listesinde de Cümle kelimeleri her iki kelimeden birinde gelsin.
        if !cumle.isEmpty {
            for (anahtar, l) in gunler {
                let cs = Set(cumle.map(\.w))
                let geri = l.filter { !cs.contains($0.w) }
                var out: [WKelime] = []
                for i in 0..<max(cumle.count, geri.count) {
                    out.append(cumle[i % cumle.count])
                    if i < geri.count { out.append(geri[i]) }
                }
                gunler[anahtar] = out
            }
        }
        var a = Anlik(guncel: Date(), gunler: gunler, bugunHedef: bugunHedef, bugunYapilan: bugunYapilan,
                      seri: seri, asina: sayim(.asina), oturmus: sayim(.oturmus) + sayim(.kalici),
                      depoKalan: depoKalan, hafta: hafta)
        a.cumle = cumle
        a.cumleGun = cg?.gun
        a.cumleBaslik = cg?.baslik
        Paylasim.yaz(a)
        Paylasim.ayar.set(ayar.onceHatirla, forKey: Paylasim.hatirlaAnahtari)
        Paylasim.ayar.set(ayar.oxfordSesi, forKey: Paylasim.oxfordAnahtari)
        WidgetCenter.shared.reloadAllTimelines()
        Bildirim.planla(a, ayar: ayar, bugunBitti: bekleyenYeniler.isEmpty && bekleyenTekrarlar.isEmpty)
    }

    private func wk(_ k: Kelime, asama: Int) -> WKelime {
        WKelime(i: k.i, w: k.w, ipa: k.ipa, tr: k.tr, d: k.d, x: k.x.first, c: k.c, p: k.turAdi, asama: asama,
                au: k.au.isEmpty ? nil : k.au)
    }

    /// Yeni ve tekrar kelimeleri dönüşümlü diz — widget aynı türü üst üste göstermesin.
    private func karistir(_ l: [WKelime], tohum: Int) -> [WKelime] {
        let yeni = l.filter { $0.asama < 0 }, eski = l.filter { $0.asama >= 0 }
        var out: [WKelime] = []
        for i in 0..<max(yeni.count, eski.count) {
            if i < yeni.count { out.append(yeni[i]) }
            if i < eski.count { out.append(eski[i]) }
        }
        return out
    }

    func eslestir() async {
        if kasa.bagli {
            if let p = await kasa.paketAl(mevcut: paketSurum) {
                if let v = try? JSONEncoder().encode(p) { try? v.write(to: Self.paketURL, options: .atomic) }
                paketKur(p)
                planla()
            }
            await kasa.ilerlemeYaz(ilerleme())
        }
        // PDM Ağı: bekleyen olaylar vault'a, ağın durumu App Group'a (vault yoksa olaylar telefonda bekler)
        let r = await bus.sync()
        busRapor = r
        let odak = PDMBus.cachedWords()?.openFocus() ?? []
        if odak != agOdak {
            agOdak = odak
            agOdaginiOneAl()
            planla()
        }
    }

    /// Bir kelime kararını ağa yazar. Deyimsel fiiller Örgü'nün kelime havuzuna ait değil; ağa gitmez.
    private func olay(_ tur: String, _ k: Kelime, _ ek: [String: PDMValue] = [:]) {
        guard !k.isPV else { return }
        var d = ek
        if !k.c.isEmpty { d["cefr"] = .string(k.c) }
        bus.emit(tur, subject: PDMSubject.word(k.w), data: d)
    }

    /// Vault'a giden özet — Örgü motorunun `ice-aktar` biçimiyle uyumlu.
    func ilerleme() -> [String: Any] {
        // Deyimsel fiiller Örgü'nün kelime havuzuna ait değil; vault'a ayrı anahtarla gider.
        let pvAd: (String) -> Bool = { self.kelime(ad: $0)?.isPV == true }
        let bil = kayit.kararlar.filter { $0.value == .biliyorum && !pvAd($0.key) }.map(\.key).sorted()
        let tanidik = kayit.kartlar.filter { $0.value.kararlilik >= 21 && !pvAd($0.key) }.map(\.key).sorted()
        let ogren = kayit.kartlar.filter { $0.value.kararlilik < 21 && !pvAd($0.key) }.map(\.key).sorted()
        let pvKart = kayit.kartlar.filter { pvAd($0.key) }
        let pvOzet: [String: [String]] = [
            "ogreniliyor": pvKart.filter { $0.value.kararlilik < 21 }.map(\.key).sorted(),
            "oturmus": pvKart.filter { $0.value.kararlilik >= 21 }.map(\.key).sorted(),
            "biliyorum": kayit.kararlar.filter { $0.value == .biliyorum && pvAd($0.key) }.map(\.key).sorted(),
        ]
        let gunler = kayit.gunler.filter { $0.key >= Date().gun(-60).gunAnahtari }
            .mapValues { ["yeni": $0.yeni, "tekrar": $0.tekrar, "dogru": $0.dogru, "dakika": Int($0.sure / 60)] }
        return [
            "kaynak": "VocuTeach (iPhone)",
            "tarih": Date().gunAnahtari,
            "an": ISO8601DateFormatter().string(from: Date()),
            "paket": paketSurum,
            "biliyorum": bil,
            "tanidik": tanidik,
            "ogreniliyor": ogren,
            "deyimsel": pvOzet,
            "sayim": ["tanisma": sayim(.tanisma), "asina": sayim(.asina), "oturmus": sayim(.oturmus),
                      "kalici": sayim(.kalici), "biliyorum": bil.count, "depo_kalan": depoKalan,
                      "seri": seri, "bildirim_maruz": kayit.maruz],
            "gunler": gunler,
        ]
    }

    // MARK: Bildirim eylemleri

    func bildirimEylemi(_ eylem: String, id: Int) {
        switch eylem {
        case Bildirim.sorEylemi: oneAl(id)
        case Bildirim.biliyordumEylemi: kayit.maruz += 1; kaydet()
        case Bildirim.dinleEylemi, Bildirim.cumleDinleEylemi: break   // ses AsinaApp temsilcisinde, uygulama açılmadan çalar
        default:
            if let k = kelime(id) {
                acilacakKelime = k
                Ses.ortak.soyle(k, oxford: ayar.oxfordSesi)
            }
        }
    }

    func ac(_ url: URL) {
        guard url.scheme == "asina", url.host == "kelime", let id = Int(url.lastPathComponent),
              let k = kelime(id) else { return }
        acilacakKelime = k
    }

    // MARK: Çeldiriciler

    /// Aynı türden, anlamı farklı üç kelime — aynı banttan olanlar önce.
    func celdiriciler(_ k: Kelime, adet: Int = 3) -> [Kelime] {
        var rng = SystemRandomNumberGenerator()
        if k.isPV {
            // Aynı fiilin öteki deyimleri en güçlü çeldirici: take off ↔ take on ↔ take up
            var secilen = Array(ayniFiil(k).filter { $0.tr != k.tr }.shuffled().prefix(2))
            var diger = pvSirali.filter { $0.taban != k.taban && $0.tr != k.tr }
            while secilen.count < adet, !diger.isEmpty {
                let c = diger.remove(at: Int.random(in: 0..<diger.count, using: &rng))
                if !secilen.contains(where: { $0.tr == c.tr }) { secilen.append(c) }
            }
            return secilen
        }
        let ayniTur = kelimeler.filter { $0.p == k.p && $0.w != k.w && !$0.tr.isEmpty && $0.tr != k.tr }
        let ayniBant = ayniTur.filter { $0.c == k.c }
        var havuz = (ayniBant.count >= 12 ? ayniBant : ayniTur)
        if havuz.count < adet { havuz = kelimeler.filter { $0.w != k.w && !$0.tr.isEmpty } }
        var secilen: [Kelime] = []
        while secilen.count < adet, !havuz.isEmpty {
            let c = havuz.remove(at: Int.random(in: 0..<havuz.count, using: &rng))
            if !secilen.contains(where: { $0.tr == c.tr || $0.w == c.w }) { secilen.append(c) }
        }
        return secilen
    }
}
