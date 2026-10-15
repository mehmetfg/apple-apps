// Memories deposu: yerel paket önbelleği + olay günlüğü + kayıtlar + vault eşitlemesi + widget anlık görüntüsü.
// Yerel kayıt her zaman önce yazılır; vault erişilemese de hiçbir şey kaybolmaz, sonraki eşitlemede gider.
// Paketin sesi uygulamanın kendi alanına kopyalanır: yolda internet olmadan da çalar.
import Foundation
import SwiftUI
import WidgetKit

struct KayitBilgisi: Codable, Hashable, Identifiable {
    var ad: String              // 021-iphone-a1b2c3d4.m4a
    var gun: Int
    var cihaz: String
    var zaman: Date
    var sure: Double?
    var tanima: Double?
    var takilan: [String]?
    var vaultta: Bool = false
    var yerelde: Bool = true
    var id: String { ad }
    var cihazAdi: String { cihaz == "iphone" ? "iPhone" : cihaz.hasPrefix("mac") ? "Mac" : cihaz }
}

@MainActor
final class Depo: ObservableObject {
    @Published private(set) var paketler: [Paket] = []
    @Published var secilenGun: Int?
    @Published private(set) var cozumler: [Int: Cozum] = [:]
    @Published private(set) var olaylar: [Olay] = []
    @Published private(set) var kayitlar: [KayitBilgisi] = []
    @Published private(set) var sonEsitleme: Date?
    @Published private(set) var esitleniyor = false
    @Published private(set) var inenSes: Set<Int> = []
    @Published var bilgi: String?

    @AppStorage("memories.hiz") var hiz: Double = 1.0
    @AppStorage("memories.haptik") var haptik = true

    let kasa = Kasa()

    // Yerel yerler (App Group: widget da görür)
    var yerel: URL { Paylasim.kapsayici }
    private var paketKlasoru: URL { yerel.appendingPathComponent("paket", isDirectory: true) }
    private var benimGunluk: URL { yerel.appendingPathComponent("ilerleme/\(Cihaz.ad).jsonl") }
    private var digerKlasor: URL { yerel.appendingPathComponent("diger", isDirectory: true) }
    var kayitKlasoru: URL { yerel.appendingPathComponent("kayit", isDirectory: true) }
    private var kayitDefteri: URL { yerel.appendingPathComponent("kayitlar.json") }

    private var esitlemeGorevi: Task<Void, Never>?
    static let tutulan = 9     // yerelde tutulan son paket: haftalık tampon (7 açık gün) + 2 geçmiş (kayıtlar ayrı, hep kalır)

    init() {
        yerelYukle()
        widgetYaz()
    }

    // MARK: Okunan durum

    /// Çantadaki paket: seçtiğin gün; seçmediysen yazılmamış ve geçilmemiş EN ESKİ gün. Sabah görevi haftalık
    /// tampon (7 açık gün) tutar; sıra atlanmasın diye en yeni değil sıradaki gün açılır. Hepsi bittiyse en yeni gün.
    var guncel: Paket? {
        if let s = secilenGun, let p = paketler.first(where: { $0.gun == s }) { return p }
        return paketler.first { !yazilanGunler.contains($0.gun) && !atlananGunler.contains($0.gun) } ?? paketler.last
    }
    /// Mac'te yazılmış günler: Tezgâh'ın "bitti" olayı ya da yazım sonucu taşıyan çözüm.
    var yazilanGunler: Set<Int> {
        Set(olaylar.filter { $0.tur == .bitti }.map(\.gun))
            .union(cozumler.values.filter { $0.yazim != nil }.map(\.gun))
    }
    /// «Yaptım, geç» denen günler (telefonda ya da Mac'te).
    var atlananGunler: Set<Int> { Set(olaylar.filter { $0.tur == .atladi }.map(\.gun)) }

    func gunSec(_ gun: Int?) {
        secilenGun = gun
        widgetYaz()
    }

    /// Bu günü başka yerde yaptın ya da geçmek istiyorsun: sicile girmez, sıradaki gün açılır.
    func atla(_ p: Paket) {
        ekle(Olay(gun: p.gun, surum: p.surum, tur: .atladi))
        secilenGun = nil
        bilgi = guncel.map { $0.gun != p.gun ? "Gün \(p.gun) geçildi · sıradaki: Gün \($0.gun)" : "Gün \(p.gun) geçildi" } ?? "Gün \(p.gun) geçildi"
    }

    /// Dünün çözümü: yazım sonucu olan en yeni gün (yalnız okuması çözümlenmiş gün, yazılmadıysa "dün" sayılmaz).
    var sonCozum: Cozum? {
        let yazilan = cozumler.values.filter { $0.yazim != nil }
        return (yazilan.isEmpty ? Array(cozumler.values) : yazilan).max { $0.gun < $1.gun }
    }
    func hazirlik(_ gun: Int) -> Hazirlik { Hazirlik.kur(olaylar, gun: gun) }
    func sesURL(_ p: Paket) -> URL? {
        let u = paketKlasoru.appendingPathComponent(p.klasorAdi).appendingPathComponent("ses.m4a")
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }
    func kayitURL(_ k: KayitBilgisi) -> URL { kayitKlasoru.appendingPathComponent(k.ad) }
    func kayitlar(gun: Int) -> [KayitBilgisi] { kayitlar.filter { $0.gun == gun }.sorted { $0.zaman > $1.zaman } }

    // MARK: Yerel yükleme

    private func yerelYukle() {
        let fm = FileManager.default
        try? fm.createDirectory(at: paketKlasoru, withIntermediateDirectories: true)
        var p: [Paket] = []
        var c: [Int: Cozum] = [:]
        for ad in (try? fm.contentsOfDirectory(atPath: paketKlasoru.path)) ?? [] where ad.hasPrefix("gun-") {
            let k = paketKlasoru.appendingPathComponent(ad)
            if let v = try? Data(contentsOf: k.appendingPathComponent("paket.json")),
               let x = try? JSONDecoder().decode(Paket.self, from: v) { p.append(x) }
            if let v = try? Data(contentsOf: k.appendingPathComponent("cozum.json")),
               let x = try? JSONDecoder().decode(Cozum.self, from: v) { c[x.gun] = x }
        }
        paketler = p.sorted { $0.gun < $1.gun }
        cozumler = c
        var hepsi = Gunluk.oku(benimGunluk)
        for ad in (try? fm.contentsOfDirectory(atPath: digerKlasor.path)) ?? [] where ad.hasSuffix(".jsonl") {
            hepsi += Gunluk.oku(digerKlasor.appendingPathComponent(ad))
        }
        olaylar = Gunluk.tekille(hepsi)
        if let v = try? Data(contentsOf: kayitDefteri) {
            let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
            kayitlar = (try? d.decode([KayitBilgisi].self, from: v)) ?? []
        }
    }

    private func kayitDefteriniYaz() {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        if let v = try? e.encode(kayitlar) { try? v.write(to: kayitDefteri, options: .atomic) }
    }

    // MARK: Olaylar

    func ekle(_ o: Olay) {
        Gunluk.ekle(o, benimGunluk)
        olaylar.append(o)
        if o.tur != .hazirim, let p = paketler.first(where: { $0.gun == o.gun }) {
            let h = hazirlik(p.gun)
            if h.dinleme > 0 && h.okuma && !olaylar.contains(where: { $0.gun == p.gun && $0.tur == .hazirim }) {
                var hz = Olay(gun: p.gun, surum: p.surum, tur: .hazirim); hz.rol = "otomatik"
                Gunluk.ekle(hz, benimGunluk); olaylar.append(hz)
                bilgi = "Hazırsın. Yarın Tezgâh'ta yazarken bu metin tanıdık gelecek."
            }
        }
        widgetYaz()
        Task { await Bildirim.planla(self) }
        esitle(gecikme: 3)
    }

    func dinledi(_ p: Paket, oran: Double, sure: Double) {
        var o = Olay(gun: p.gun, surum: p.surum, tur: .dinledi)
        o.oran = (oran * 100).rounded() / 100; o.sure = sure.rounded()
        ekle(o)
        let n = hazirlik(p.gun).dinleme
        bilgi = n == 1 ? "Bir kez dinledin." : "\(n). dinleme tamam."
    }

    func okudu(_ p: Paket) {
        guard !hazirlik(p.gun).okuma else { return }
        ekle(Olay(gun: p.gun, surum: p.surum, tur: .okudu))
    }

    /// Cümlede takıldın (yineledin · geri sardın · tek başına dinledin · Türkçesine baktın). Mac'te Cümle bu
    /// cümleleri metin haritasında işaretler. Aynı cümle için yarım dakikada bir kez yazılır.
    private var sonTakilma: [String: Date] = [:]
    func takildi(_ p: Paket, cumle: Int, nasil: String) {
        let k = "\(p.gun)-\(cumle)"
        if let t = sonTakilma[k], Date().timeIntervalSince(t) < 30 { return }
        sonTakilma[k] = Date()
        var o = Olay(gun: p.gun, surum: p.surum, tur: .takildi)
        o.cumle = cumle; o.rol = nasil
        ekle(o)
    }

    func hazirim(_ p: Paket) {
        guard !hazirlik(p.gun).hazir else { return }
        var o = Olay(gun: p.gun, surum: p.surum, tur: .hazirim); o.rol = "elle"
        ekle(o)
    }

    // MARK: Kayıtlar

    func kayitEklendi(_ k: KayitBilgisi, paket p: Paket) {
        kayitlar.append(k)
        kayitDefteriniYaz()
        var o = Olay(gun: p.gun, surum: p.surum, tur: .kaydetti)
        o.dosya = k.ad; o.sure = k.sure.map { $0.rounded() }; o.tanima = k.tanima; o.takilan = k.takilan
        ekle(o)
    }

    /// Kullanıcı kendi kaydını siler: cihazdan ve (gönderildiyse) vault'tan.
    func kayitSil(_ k: KayitBilgisi) {
        try? FileManager.default.removeItem(at: kayitURL(k))
        kayitlar.removeAll { $0.ad == k.ad }
        kayitDefteriniYaz()
        let ad = k.ad, gun = k.gun
        Task {
            _ = await kasa.ile { kok in
                let u = kok.appendingPathComponent("paket/\(Paket.klasor(gun))/kayit")
                var h: NSError?
                for x in [ad, ad.replacingOccurrences(of: ".m4a", with: ".json")] {
                    let f = u.appendingPathComponent(x)
                    NSFileCoordinator().coordinate(writingItemAt: f, options: .forDeleting, error: &h) { y in
                        try? FileManager.default.removeItem(at: y)
                    }
                }
                return true
            }
        }
    }

    /// Mac'in kaydı (yalnız vault'ta): dinlemek için bir kez indirilir.
    func kayitIndir(_ k: KayitBilgisi) async -> URL? {
        let hedef = kayitURL(k)
        if FileManager.default.fileExists(atPath: hedef.path) { return hedef }
        let ad = k.ad, gun = k.gun
        let tamam = await kasa.ile { kok -> Bool in
            let u = kok.appendingPathComponent("paket/\(Paket.klasor(gun))/kayit/\(ad)")
            guard Kasa.indir(u, bekle: 20) else { return false }
            return Kasa.koordineliKopyala(u, hedef)
        } ?? false
        if tamam, let i = kayitlar.firstIndex(where: { $0.ad == ad }) { kayitlar[i].yerelde = true; kayitDefteriniYaz() }
        return tamam ? hedef : nil
    }

    // MARK: Widget

    func widgetYaz() {
        Paylasim.yaz(anlik())
        WidgetCenter.shared.reloadAllTimelines()
    }

    func anlik() -> WidgetAnlik {
        var a = WidgetAnlik(guncel: Date())
        if let p = guncel {
            let h = hazirlik(p.gun)
            a.gun = p.gun; a.baslik = p.ad; a.ozet = p.ozet; a.sure = p.sure_sn
            a.adim = .init(dinleme: h.dinleme, okuma: h.okuma, kayit: h.kayit)
            // Anahtar cümle: günün yapısını taşıyan ilk cümle, gün içinde sabit
            let aday = p.cumleler.filter { $0.konu != nil && ($0.en?.count ?? 0) < 90 }
            let c = aday.isEmpty ? p.cumleler.first : aday[p.gun % aday.count]
            a.anahtar = c?.en; a.anahtarTr = c?.tr
        }
        if let c = sonCozum {
            a.dunGun = c.gun
            if let e = c.duzeltme, let d = e.dogrusu { a.dunEn = d; a.dunTr = e.tr }
            else if let e = c.en_iyi { a.dunEn = e.en; a.dunTr = e.tr }
            if let r = c.yol_haritasi?.first { a.rota = "\(r.tur) — \(r.not ?? "")" }
        }
        return a
    }

    // MARK: Eşitleme

    func esitle(gecikme: Double = 0) {
        esitlemeGorevi?.cancel()
        esitlemeGorevi = Task { [weak self] in
            if gecikme > 0 { try? await Task.sleep(nanoseconds: UInt64(gecikme * 1_000_000_000)) }
            guard let self, !Task.isCancelled else { return }
            await self.esitleSimdi()
        }
    }

    struct Gelen: Sendable {
        var paketler: [Int: Data] = [:]
        var cozumler: [Int: Data] = [:]
        var digerler: [String: Data] = [:]
        var inenSes: [Int] = []
        var vaultKayitlari: [Int: [String: Data?]] = [:]   // gün → ad → yan dosya (json)
        var gonderilen: [String] = []
    }

    /// - Returns: yeni gelen paket ya da çözüm varsa (gün) — arka plan bildirimi için.
    @discardableResult
    func esitleSimdi() async -> (yeniPaket: Int?, yeniCozum: Int?) {
        guard kasa.bagli, !esitleniyor else { return (nil, nil) }
        esitleniyor = true
        defer { esitleniyor = false }

        let ben = Cihaz.ad
        let benimOlaylar = olaylar.filter { $0.cihaz == ben }
        let benimYerel = benimGunluk
        let yerelPaket = paketKlasoru
        let yerelSurum = Dictionary(paketler.map { ($0.gun, $0.surum ?? "") }, uniquingKeysWith: { a, _ in a })
        let yerelSesVar = Set(paketler.filter { sesURL($0) != nil }.map(\.gun))
        let gonderilecek = kayitlar.filter { $0.cihaz == ben && !$0.vaultta && $0.yerelde }
        let kayitYerel = kayitKlasoru
        let tutulan = Depo.tutulan
        let bitmisGunler = yazilanGunler.union(atlananGunler)

        let g: Gelen? = await kasa.ile { kok in
            var s = Gelen()
            let fm = FileManager.default
            // 1 · Kendi günlüğüm (vault'takiyle birleşir: yeniden kurulumda yerel boş kalmış olabilir)
            let ilerleme = kok.appendingPathComponent("ilerleme", isDirectory: true)
            try fm.createDirectory(at: ilerleme, withIntermediateDirectories: true)
            let benimVault = ilerleme.appendingPathComponent("\(ben).jsonl")
            _ = Kasa.indir(benimVault, bekle: 3)
            let vaultBenim = Kasa.koordineliOku(benimVault).map { Gunluk.coz($0).olaylar } ?? []
            let birlesik = Gunluk.tekille(benimOlaylar + vaultBenim)
            if Set(birlesik.map(\.id)) != Set(vaultBenim.map(\.id)) {
                try Kasa.koordineliYaz(Gunluk.veri(birlesik), benimVault)
            }
            if !Set(vaultBenim.map(\.id)).subtracting(benimOlaylar.map(\.id)).isEmpty {
                try? Gunluk.veri(birlesik).write(to: benimYerel, options: .atomic)
            }
            // 2 · Öteki cihazlar (Mac'teki Tezgâh) — çakışma kopyaları dahil
            for ad in (try? fm.contentsOfDirectory(atPath: ilerleme.path)) ?? [] {
                if ad.hasPrefix("."), ad.hasSuffix(".icloud") {
                    try? fm.startDownloadingUbiquitousItem(at: ilerleme.appendingPathComponent(String(ad.dropFirst().dropLast(7))))
                    continue
                }
                guard ad.hasSuffix(".jsonl"), ad != "\(ben).jsonl" else { continue }
                if let v = Kasa.koordineliOku(ilerleme.appendingPathComponent(ad)) { s.digerler[ad] = v }
            }
            // 3 · Paketler: son `tutulan` gün
            let pk = kok.appendingPathComponent("paket", isDirectory: true)
            let adlar = ((try? fm.contentsOfDirectory(atPath: pk.path)) ?? [])
                .map { $0.hasPrefix(".") && $0.hasSuffix(".icloud") ? String($0.dropFirst().dropLast(7)) : $0 }
                .filter { $0.hasPrefix("gun-") }
            let gunler = Set(adlar.compactMap { Int($0.dropFirst(4)) }).sorted().suffix(tutulan)
            for gun in gunler {
                let k = pk.appendingPathComponent(Paket.klasor(gun))
                let pj = k.appendingPathComponent("paket.json")
                guard Kasa.indir(pj), let v = Kasa.koordineliOku(pj),
                      let p = try? JSONDecoder().decode(Paket.self, from: v) else { continue }
                s.paketler[gun] = v
                let cj = k.appendingPathComponent("cozum.json")
                let yj = k.appendingPathComponent("yazim.json")     // Mac'te yazınca aynı gün gelir
                if fm.fileExists(atPath: cj.path) || fm.fileExists(atPath: k.appendingPathComponent(".cozum.json.icloud").path) {
                    if Kasa.indir(cj), let c = Kasa.koordineliOku(cj) { s.cozumler[gun] = c }
                } else if fm.fileExists(atPath: yj.path) || fm.fileExists(atPath: k.appendingPathComponent(".yazim.json.icloud").path) {
                    if Kasa.indir(yj), let c = Kasa.koordineliOku(yj) { s.cozumler[gun] = c }
                }
                // Ses: yerelde yoksa ya da paket yeniden üretildiyse (sürüm değişti)
                if p.ses != nil, !bitmisGunler.contains(gun), !yerelSesVar.contains(gun) || yerelSurum[gun] != (p.surum ?? "") {
                    let kaynak = k.appendingPathComponent("ses.m4a")
                    let hedef = yerelPaket.appendingPathComponent(Paket.klasor(gun)).appendingPathComponent("ses.m4a")
                    if Kasa.indir(kaynak, bekle: 30), Kasa.koordineliKopyala(kaynak, hedef) { s.inenSes.append(gun) }
                }
                // Kayıtlar klasörü: Mac'te yapılanlar listede görünsün
                let kk = k.appendingPathComponent("kayit", isDirectory: true)
                var liste: [String: Data?] = [:]
                for a in (try? fm.contentsOfDirectory(atPath: kk.path)) ?? [] {
                    let ad = a.hasPrefix(".") && a.hasSuffix(".icloud") ? String(a.dropFirst().dropLast(7)) : a
                    guard ad.hasSuffix(".m4a") else { continue }
                    let yan = kk.appendingPathComponent(ad.replacingOccurrences(of: ".m4a", with: ".json"))
                    liste[ad] = fm.fileExists(atPath: yan.path) ? Kasa.koordineliOku(yan) : nil
                }
                s.vaultKayitlari[gun] = liste
            }
            // 4 · Kendi kayıtlarımı gönder (m4a + yan dosya)
            for k in gonderilecek {
                let hedefK = pk.appendingPathComponent(Paket.klasor(k.gun)).appendingPathComponent("kayit", isDirectory: true)
                let kaynak = kayitYerel.appendingPathComponent(k.ad)
                guard let v = try? Data(contentsOf: kaynak) else { continue }
                let hedef = hedefK.appendingPathComponent(k.ad)
                if !fm.fileExists(atPath: hedef.path) { try? Kasa.koordineliYaz(v, hedef) }
                let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]
                if let yan = try? e.encode(k) {
                    try? Kasa.koordineliYaz(yan, hedefK.appendingPathComponent(k.ad.replacingOccurrences(of: ".m4a", with: ".json")))
                }
                let a = (try? fm.attributesOfItem(atPath: hedef.path)[.size] as? Int) ?? -1
                if a == v.count { s.gonderilen.append(k.ad) }
            }
            return s
        }
        guard let g else { return (nil, nil) }

        // Yerel önbelleğe al
        let fm = FileManager.default
        let eskiPaket = Set(paketler.map(\.gun)), eskiCozum = Set(cozumler.keys)
        try? fm.createDirectory(at: digerKlasor, withIntermediateDirectories: true)
        for (ad, v) in g.digerler { try? v.write(to: digerKlasor.appendingPathComponent(ad), options: .atomic) }
        for (gun, v) in g.paketler {
            let k = paketKlasoru.appendingPathComponent(Paket.klasor(gun))
            try? fm.createDirectory(at: k, withIntermediateDirectories: true)
            try? v.write(to: k.appendingPathComponent("paket.json"), options: .atomic)
        }
        for (gun, v) in g.cozumler {
            try? v.write(to: paketKlasoru.appendingPathComponent(Paket.klasor(gun)).appendingPathComponent("cozum.json"), options: .atomic)
        }
        // Eski paketleri yerelden at (kayıtlar ayrı klasörde, kalır)
        let tut = Set(g.paketler.keys)
        if !tut.isEmpty, let enKucuk = tut.min() {
            for ad in (try? fm.contentsOfDirectory(atPath: paketKlasoru.path)) ?? [] {
                if let n = Int(ad.dropFirst(4)), n < enKucuk { try? fm.removeItem(at: paketKlasoru.appendingPathComponent(ad)) }
            }
        }
        // Kayıt defteri: gönderilenleri işaretle, Mac'in kayıtlarını ekle
        for ad in g.gonderilen { if let i = kayitlar.firstIndex(where: { $0.ad == ad }) { kayitlar[i].vaultta = true } }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        for (gun, liste) in g.vaultKayitlari {
            for (ad, yan) in liste {
                if let i = kayitlar.firstIndex(where: { $0.ad == ad }) { kayitlar[i].vaultta = true; continue }
                var k = yan.flatMap { try? d.decode(KayitBilgisi.self, from: $0) }
                    ?? KayitBilgisi(ad: ad, gun: gun, cihaz: ad.split(separator: "-").dropFirst().first.map(String.init) ?? "?", zaman: Date())
                k.vaultta = true; k.yerelde = fm.fileExists(atPath: kayitKlasoru.appendingPathComponent(ad).path)
                kayitlar.append(k)
            }
        }
        kayitDefteriniYaz()
        yerelYukle()
        sonEsitleme = Date()
        let yeniPaket = Set(paketler.map(\.gun)).subtracting(eskiPaket).max()
        let yeniCozum = Set(cozumler.keys).subtracting(eskiCozum).max()
        if let n = yeniPaket, !eskiPaket.isEmpty { bilgi = "Gün \(n) paketi geldi." }
        widgetYaz()
        await Bildirim.planla(self)
        return (yeniPaket, yeniCozum)
    }
}
