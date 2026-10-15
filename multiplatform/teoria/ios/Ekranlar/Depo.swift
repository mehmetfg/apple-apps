// Teoria deposu: içerik + olay günlüğü + durum + eşitleme + widget anlık görüntüsü.
// Yerel kayıt her zaman önce yazılır; vault erişilemese de hiçbir şey kaybolmaz, sonraki eşitlemede gider.
import Foundation
import SwiftUI
import WidgetKit

struct SesDegerlendirme: Codable, Hashable {
    var tarih: String?
    var ozet: String
    var guclu: [String]?
    var eksik: [String]?
    var soru: String?
    var hatirlama: Int?     // 1-5: notta fikri ne kadar kendi zihninden çağırdın
    var yorum: Int?         // 1-5: yorum ve bağ kurma
}

/// Claude'un genel değerlendirmesi: vault'ta degerlendirme/genel-<tarih>.json (oturumda "Teoria değerlendir").
/// Yazdıkların + sesli notların, asıl metinle karşılaştırılarak: ne kadar kendi zihninden ürettin?
struct GenelDegerlendirme: Codable, Hashable, Identifiable {
    var tarih: String
    var kapsam: String?         // "2026-10-01 → 2026-10-07 · 12 yazı, 3 sesli not"
    var ozet: String
    var guclu: [String]?
    var eksik: [String]?
    var oruntu: String?         // tekrar eden düşünce biçimi
    var hatirlama: Int?         // 1-5: asıl metne bakmadan ne kadar çağırdın
    var uretim: Int?            // 1-5: metni tekrarlamak yerine ne kadar yeni düşünce ürettin
    var oneri: [String]?
    var notlar: [Not]?
    struct Not: Codable, Hashable { var hedef: String?; var olay: String?; var yorum: String }
    var id: String { tarih }
}

struct SesBilgisi: Hashable {
    var dokum: String?
    var degerlendirme: SesDegerlendirme?
    var vaultta: Bool
}

enum TemaSecimi: String, CaseIterable, Identifiable {
    case sistem, acik, koyu
    var id: String { rawValue }
    var ad: String { switch self { case .sistem: "Sistem"; case .acik: "Açık"; case .koyu: "Koyu" } }
    var sema: ColorScheme? { switch self { case .sistem: nil; case .acik: .light; case .koyu: .dark } }
}

@MainActor
final class Depo: ObservableObject {
    @Published private(set) var paket: Paket = .bos
    @Published private(set) var akis: Akis = .bos {
        didSet { isaretIndeksi = Dictionary(akis.isaretler.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
    }
    private var isaretIndeksi: [String: Isaret] = [:]   // id → işaret: bildirim, widget ve sesli notlar O(1) bulur
    @Published private(set) var mufredat: Mufredat = .bos
    @Published private(set) var olaylar: [Olay] = []
    @Published private(set) var durum = Durum()
    @Published private(set) var sesler: [String: SesBilgisi] = [:]
    @Published private(set) var sonEsitleme: Date?
    @Published private(set) var esitleniyor = false
    @Published private(set) var guncelleniyor = false
    @Published private(set) var genelDegerlendirmeler: [GenelDegerlendirme] = []
    @Published var bildirim: String?            // ekranın üstünde kısa, sessiz bilgi
    @Published var bozukSatir = 0

    @AppStorage("teoria.zorluk") var zorlukHam = Zorluk.dengeli.rawValue
    @AppStorage("teoria.dakika") var kurDakika = 5
    @AppStorage("teoria.tema") var temaHam = TemaSecimi.sistem.rawValue
    @AppStorage("teoria.haptik") var haptik = true
    @AppStorage("teoria.hareket") var hareket = true
    @AppStorage("teoria.ilk") var ilkGun = ""

    let kasa = Kasa()

    var zorluk: Zorluk { Zorluk(rawValue: zorlukHam) ?? .dengeli }
    var tema: TemaSecimi { TemaSecimi(rawValue: temaHam) ?? .sistem }

    // Yerel yerler (App Group kapsayıcısı: widget da görebilir)
    private var yerel: URL { Paylasim.kapsayici }
    private var benimGunluk: URL { yerel.appendingPathComponent("ilerleme/\(Cihaz.ad).jsonl") }
    private var digerKlasor: URL { yerel.appendingPathComponent("diger", isDirectory: true) }
    var sesKlasoru: URL { yerel.appendingPathComponent("ses", isDirectory: true) }

    private var esitlemeGorevi: Task<Void, Never>?
    private var widgetGorevi: Task<Void, Never>?

    init() {
        if ilkGun.isEmpty { ilkGun = Tarih.gun(Date()) }
        icerigiYukle()
        gunlukYukle()
        kutuyuAl()
        yetimKurlariKapat()
        yenidenHesapla()
        widgetYaz(hemen: true)
    }

    // MARK: İçerik

    private func paketiCoz<T: Decodable>(_ ad: String, _ tur: T.Type) -> T? {
        let fm = FileManager.default
        var adaylar: [URL] = [yerel.appendingPathComponent("veri/\(ad)")]
        if let b = Bundle.main.url(forResource: ad.replacingOccurrences(of: ".json", with: ""), withExtension: "json") { adaylar.append(b) }
        // Vault'taki sürüm burada okunmaz: iCloud izni ana iş parçacığını bekletebilir.
        // Eşitleme onu arka planda yerel kopyaya alır (veri/), sonraki yüklemede o kullanılır.
        var en: (T, String)?
        for u in adaylar where fm.fileExists(atPath: u.path) {
            guard let v = try? Data(contentsOf: u), let x = try? JSONDecoder().decode(T.self, from: v) else { continue }
            let s = (x as? Paket)?.surum ?? (x as? Akis)?.surum ?? (x as? Mufredat)?.surum ?? ""
            if en == nil || s > en!.1 { en = (x, s) }
        }
        return en?.0
    }

    func icerigiYukle() {
        if let p = paketiCoz("kartlar.json", Paket.self) { paket = p }
        if let a = paketiCoz("akis.json", Akis.self) { akis = a }
        if let m = paketiCoz("mufredat.json", Mufredat.self) { mufredat = m }
    }

    // MARK: Günlük

    private func gunlukYukle() {
        let ben = Gunluk.oku(benimGunluk)
        let diger = Gunluk.klasoruOku(digerKlasor)
        bozukSatir = ben.bozuk + diger.bozuk
        olaylar = Gunluk.tekille(ben.olaylar + diger.olaylar)
    }

    /// Widget ve bildirim düğmelerinin bıraktığı olaylar.
    func kutuyuAl() {
        let gelen = Paylasim.kutuyuBosalt()
        guard !gelen.isEmpty else { return }
        let bilinen = Set(olaylar.map(\.id))
        for o in gelen where !bilinen.contains(o.id) {
            Gunluk.ekle(o, benimGunluk)
            olaylar.append(o)
        }
        yenidenHesapla()
        esitle(gecikme: 2)
    }

    /// Kapanış olayı yazılamadan kesilmiş kür (uygulama kapandı, pil bitti): 30 dk sonra kendiliğinden kapanır.
    /// Yarım kür diye bir şey yok — en az bir kart yapıldıysa kür sayılır.
    private func yetimKurlariKapat() {
        let d = Durum.kur(olaylar, zorluk: zorluk)
        for (id, c) in d.acikKurlar {
            guard let son = c.map(\.t).max(), Date().timeIntervalSince(son) > 1800, let ilk = c.map(\.t).min() else { continue }
            var o = Olay(tur: .kur, kurId: id, rol: "otomatik")
            o.t = son.addingTimeInterval(1); o.gun = Tarih.gun(ilk)
            o.sure = min(son.timeIntervalSince(ilk) + 30, 15 * 60)
            Gunluk.ekle(o, benimGunluk)
            olaylar.append(o)
        }
    }

    func ekle(_ o: Olay) {
        Gunluk.ekle(o, benimGunluk)
        olaylar.append(o)
        yenidenHesapla()
        widgetYaz()
        esitle(gecikme: 4)
    }

    func yenidenHesapla() {
        durum = Durum.kur(olaylar, zorluk: zorluk)
    }

    // MARK: Kısa eylemler

    func favori(_ id: String) { ekle(Olay(tur: .favori, hedef: id, deger: !durum.favoriler.contains(id))) }
    func yerIsareti(_ id: String) { ekle(Olay(tur: .yerIsareti, hedef: id, deger: !durum.yerIsaretleri.contains(id))) }
    func hatirlat(_ id: String) {
        let acik = !durum.hatirlatmalar.contains(id)
        ekle(Olay(tur: .hatirlat, hedef: id, deger: acik))
        bildirim = acik ? "Tekrar havuzuna alındı. Kürde ve bildirimde dönecek." : "Tekrar havuzundan çıkarıldı."
    }
    func kademeAyarla(_ h: Hat, _ k: Int) { ekle(Olay(tur: .kademe, hat: h, kademe: k)) }

    // MARK: Akış yardımcıları

    func isaret(_ id: String) -> Isaret? { isaretIndeksi[id] }

    var kendiIsaretleri: [Isaret] { akis.isaretler }

    /// Geçmişte bugün: bir ay, iki ay, bir yıl önceki aynı günün (±2 gün) işareti.
    func gecmisteBugun(_ simdi: Date = Date()) -> (Isaret, String)? {
        for (ay, ad) in [(12, "Bir yıl önce"), (2, "İki ay önce"), (1, "Bir ay önce")] {
            guard let hedef = Tarih.takvim.date(byAdding: .month, value: -ay, to: simdi) else { continue }
            let aday = akis.isaretler.filter { abs($0.zaman.timeIntervalSince(hedef)) < 2.5 * 86_400 }
            if let i = aday.randomElement() { return (i, ad) }
        }
        return nil
    }

    // MARK: Widget

    func widgetYaz(hemen: Bool = false) {
        widgetGorevi?.cancel()
        widgetGorevi = Task { [weak self] in
            if !hemen { try? await Task.sleep(nanoseconds: 800_000_000) }
            guard let self, !Task.isCancelled else { return }
            Paylasim.yaz(self.anlik())
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func anlik() -> WidgetAnlik {
        let p = paket, d = durum
        let gun = Tarih.takvim.ordinality(of: .day, in: .era, for: Date()) ?? 0
        // Alttaki kutu üsttekiyle aynı fikre bağlanır: kendi işaretinde bağlamı, aforizmada aynı kitabın bir kavramı.
        let gunTohumu = gun
        var kavramlar: [String: [Kavram]] = [:]
        for k in p.kavramlar { kavramlar[k.kitap, default: []].append(k) }
        func kavramNotu(_ kitap: String?) -> String? {
            guard let kitap, let l = kavramlar[kitap], !l.isEmpty else { return nil }
            let k = l[Gokyuzu.hashIndeks(gunTohumu, l.count)]
            return "\(k.terim) — \(k.tanim)"
        }
        func kisalt(_ m: String, _ n: Int) -> String { m.count <= n ? m : String(m.prefix(n)).trimmingCharacters(in: .whitespaces) + "…" }
        var afo = p.aforizmalar.map { a in
            WAforizma(id: a.id, metin: a.metin, kaynak: a.kaynak, renk: p.kitap(a.kitap)?.renk ?? "indigo",
                      favori: d.favoriler.contains(a.id), ilgiEtiket: "Kavram", ilgili: kavramNotu(a.kitap).map { kisalt($0, 160) })
        }
        let secilenIsaret = akis.isaretler.filter { d.favoriler.contains($0.id) || d.yerIsaretleri.contains($0.id) }
        let kisaIsaret = akis.isaretler.filter { $0.metin.count < 170 && $0.renk == 1 }.prefix(12)
        for i in (secilenIsaret + Array(kisaIsaret)) where !afo.contains(where: { $0.id == i.id }) && i.metin.count < 220 {
            let bag = i.baglam.flatMap { $0.isEmpty ? nil : kisalt($0, 190) }
            afo.append(WAforizma(id: i.id, metin: i.metin, kaynak: "\(i.baslik) · \(Tarih.kisa(i.zaman))",
                                 renk: Tema.renkAdi(i.kitap), favori: d.favoriler.contains(i.id), isaret: true,
                                 ilgiEtiket: bag != nil ? "Bağlam" : "Kavram",
                                 ilgili: bag ?? kavramNotu(i.kitap).map { kisalt($0, 160) }))
        }
        // Her gün başka bir sıra, ama gün içinde sabit.
        afo = afo.enumerated().sorted { Gokyuzu.hash($0.offset * 31 + gun) < Gokyuzu.hash($1.offset * 31 + gun) }.map(\.element)

        var ornekler: [String: String] = [:]
        for a in p.aforizmalar { if let k = a.kitap, ornekler[k] == nil { ornekler[k] = a.metin } }
        // Hatırla kartları: vadesi gelen önce, sonra yeni, sonra unutulmaya yakın
        let simdi = Date()
        var hat: [WHatirla] = p.kavramlar.map { k in
            WHatirla(id: "hatirla:\(k.id)", soru: k.tanim, baglam: nil, cevap: k.terim,
                     kaynak: p.kitap(k.kitap)?.baslik ?? "", renk: p.kitap(k.kitap)?.renk ?? "mavi",
                     ornek: ornekler[k.kitap].map { kisalt($0, 150) })
        }
        hat.sort { a, b in
            let ka = d.kartlar[a.id], kb = d.kartlar[b.id]
            let va = ka.map { $0.vade <= simdi ? 0 : 2 } ?? 1, vb = kb.map { $0.vade <= simdi ? 0 : 2 } ?? 1
            if va != vb { return va < vb }
            return (ka?.hatirlama(simdi) ?? 1) < (kb?.hatirlama(simdi) ?? 1)
        }
        for i in akis.isaretler where d.hatirlatmalar.contains(i.id) {
            hat.insert(WHatirla(id: "hatirla:isaret:\(i.id)", soru: "Bu işareti hatırla: \(String(i.metin.prefix(60)))…", baglam: nil,
                                cevap: i.metin, kaynak: i.baslik, renk: Tema.renkAdi(i.kitap)), at: min(2, hat.count))
        }

        let kitaplar = akis.kitaplar.sorted { $0.sonZaman > $1.sonZaman }.prefix(8).map {
            WKitap(id: $0.id, baslik: $0.baslik, yuzde: $0.yuzde, isaret: $0.isaret, renk: Tema.renkAdi($0.id),
                   suruyor: $0.suruyor, son: $0.sonZaman)
        }
        let hafta8: [Int] = (0..<8).reversed().map { h in
            let bas = simdi.gunBasi.gun(-(h + 1) * 7 + 1), son = simdi.gunBasi.gun(-h * 7 + 1)
            return akis.isaretler.filter { $0.zaman >= bas && $0.zaman < son }.count
        }
        let ay = akis.isaretler.filter { $0.zaman > simdi.gun(-30) }.map(\.metin)
        let gecmis = gecmisteBugun().map { (i, ad) in
            WAforizma(id: i.id, metin: i.metin, kaynak: "\(ad) · \(i.baslik)", renk: Tema.renkAdi(i.kitap), favori: false, isaret: true)
        }
        return WidgetAnlik(guncel: simdi, aforizmalar: afo, hatirla: Array(hat.prefix(16)), kitaplar: Array(kitaplar),
                           bugunDakika: d.bugunDakika, hedefDakika: kurDakika, hafta: d.hafta,
                           kademeler: Dictionary(uniqueKeysWithValues: Hat.allCases.map { ($0.rawValue, d.kademe($0)) }),
                           buHaftaKur: d.buHaftaKur, isaretHafta: hafta8,
                           gundem: Dil.sikKelimeler(ay, adet: 5).map(\.0), gecmisteBugun: gecmis,
                           oturmus: d.oturmusKavramlar(p).count, toplamKavram: p.kavramlar.count)
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

    /// Akış güncelleme düğmesi. Mac: Voice Dream senkronu + akis.py'yi çalıştırır (o da mufredat.py'yi), sonra eşitler.
    /// iPhone: Python çalışmaz; yalnızca vault'taki en son akışı çeker (üretimi Mac'teki sabah görevi yapar).
    func guncelle() async {
        guard !guncelleniyor else { return }
        guncelleniyor = true
        defer { guncelleniyor = false }
        #if os(macOS)
        let teoria = Kasa.macYolu
        let pdm = teoria.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let hata: String? = await Task.detached(priority: .userInitiated) { () -> String? in
            let adimlar: [(URL, [String], URL)] = [
                (pdm.appendingPathComponent("Artifacts/_tezgah/kutuphane.py"), ["--gun", "3"], pdm),
                (teoria.appendingPathComponent("veri/akis.py"), [], teoria),
            ]
            for (betik, arg, cwd) in adimlar {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
                p.arguments = [betik.path] + arg
                p.currentDirectoryURL = cwd
                let cikti = Pipe(); p.standardOutput = cikti; p.standardError = cikti
                do { try p.run() } catch { return "Python açılamadı: \(error.localizedDescription)" }
                let veri = cikti.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                if p.terminationStatus != 0 {
                    let son = String(decoding: veri, as: UTF8.self).split(separator: "\n").suffix(2).joined(separator: " ")
                    return "\(betik.lastPathComponent) hata verdi: \(son)"
                }
            }
            return nil
        }.value
        if let hata { bildirim = hata; return }
        #endif
        let once = akis
        while esitleniyor { try? await Task.sleep(nanoseconds: 200_000_000) }   // süren eşitleme bitsin, sonra çek
        await esitleSimdi()
        bildirim = Self.guncellemeOzeti(once, akis)
    }

    /// "2 yeni işaret · Kıymet %58→61 · 1 yeni metin" — önceki ve yeni akışın farkı.
    static func guncellemeOzeti(_ a: Akis, _ b: Akis) -> String {
        if a.surum == b.surum { return "Her şey güncel" }
        var p: [String] = []
        let eskiIsaret = Set(a.isaretler.map(\.id))
        let yeniIsaret = b.isaretler.filter { !eskiIsaret.contains($0.id) }.count
        if yeniIsaret > 0 { p.append("\(yeniIsaret) yeni işaret") }
        let eski = Dictionary(a.kitaplar.map { ($0.id, $0) }, uniquingKeysWith: { x, _ in x })
        var ilerleyen: [String] = []
        var yeniMetin = 0
        for k in b.kitaplar {
            if let e = eski[k.id] {
                if k.yuzde > e.yuzde { ilerleyen.append("\(k.baslik.kodsuz.prefix(22)) %\(e.yuzde)→\(k.yuzde)") }
            } else { yeniMetin += 1 }
        }
        p += ilerleyen.prefix(2)
        if ilerleyen.count > 2 { p.append("+\(ilerleyen.count - 2) kitap ilerledi") }
        if yeniMetin > 0 && a.surum != "0" { p.append("\(yeniMetin) yeni metin") }
        return p.isEmpty ? "Akış yenilendi; yeni işaret yok" : p.joined(separator: " · ")
    }

    /// Kendi gönderini (yorum · alıntı · fikir) ya da ses notunu siler. Günlükten satır silinmez: silme de bir olaydır.
    func sil(_ o: Olay) {
        ekle(Olay(tur: .sesSil, hedef: o.id))
        Dokunus.hafif(0.5)
    }

    struct EsitlemeSonucu: Sendable {
        var digerler: [String: Data] = [:]
        var kartlar: Data?
        var akis: Data?
        var mufredat: Data?
        var dokumler: [String: String] = [:]
        var degerlendirmeler: [String: Data] = [:]
        var vaulttakiSesler: Set<String> = []
        var genel: [Data] = []
    }

    func esitleSimdi() async {
        guard kasa.bagli, !esitleniyor else { return }
        esitleniyor = true
        defer { esitleniyor = false }
        let ben = Cihaz.ad
        let benimYerel = benimGunluk
        let benimOlaylar = olaylar.filter { $0.cihaz == ben }
        let sesYerel = sesKlasoru
        let gonderilecekSes = durum.sesNotlari.compactMap(\.metin)

        let sonuc: EsitlemeSonucu? = await kasa.ile { kok in
            var s = EsitlemeSonucu()
            let fm = FileManager.default
            let ilerleme = kok.appendingPathComponent("ilerleme", isDirectory: true)
            try fm.createDirectory(at: ilerleme, withIntermediateDirectories: true)
            // 1 · Kendi günlüğüm: vault'takiyle birleştir (yeniden kurulumda yerel boş kalmış olabilir), yaz.
            let benimVault = ilerleme.appendingPathComponent("\(ben).jsonl")
            if !fm.fileExists(atPath: benimVault.path) { Kasa.indir(benimVault) }
            let vaultBenim = Kasa.koordineliOku(benimVault).map { Gunluk.coz($0).olaylar } ?? []
            let birlesik = Gunluk.tekille(benimOlaylar + vaultBenim)
            if Set(birlesik.map(\.id)) != Set(vaultBenim.map(\.id)) {
                var v = Data(); for o in birlesik.sorted(by: { $0.t < $1.t }) { v.append(Gunluk.satir(o)) }
                try Kasa.koordineliYaz(v, benimVault)
            }
            if vaultBenim.count > 0, Set(vaultBenim.map(\.id)).subtracting(benimOlaylar.map(\.id)).isEmpty == false {
                var v = Data(); for o in birlesik.sorted(by: { $0.t < $1.t }) { v.append(Gunluk.satir(o)) }
                try? v.write(to: benimYerel, options: .atomic)
            }
            // 2 · Öteki cihazların günlükleri (çakışma kopyaları dahil)
            for ad in (try? fm.contentsOfDirectory(atPath: ilerleme.path)) ?? [] {
                if ad.hasPrefix("."), ad.hasSuffix(".icloud") {
                    try? fm.startDownloadingUbiquitousItem(at: ilerleme.appendingPathComponent(String(ad.dropFirst().dropLast(7))))
                    continue
                }
                guard ad.hasSuffix(".jsonl"), ad != "\(ben).jsonl" else { continue }
                if let v = Kasa.koordineliOku(ilerleme.appendingPathComponent(ad)) { s.digerler[ad] = v }
            }
            // 3 · İçerik
            let kart = kok.appendingPathComponent("veri/kartlar.json"), ak = kok.appendingPathComponent("veri/akis.json")
            let mf = kok.appendingPathComponent("veri/mufredat.json")
            Kasa.indir(kart); Kasa.indir(ak); Kasa.indir(mf)
            s.kartlar = Kasa.koordineliOku(kart)
            s.akis = Kasa.koordineliOku(ak)
            s.mufredat = Kasa.koordineliOku(mf)
            // 4 · Ses notları: vault'ta olmayanları gönder; döküm ve değerlendirmeleri al.
            let sesVault = kok.appendingPathComponent("ses", isDirectory: true)
            try? fm.createDirectory(at: sesVault, withIntermediateDirectories: true)
            for ad in gonderilecekSes {
                let hedef = sesVault.appendingPathComponent(ad), kaynak = sesYerel.appendingPathComponent(ad)
                if !fm.fileExists(atPath: hedef.path), let v = try? Data(contentsOf: kaynak) {
                    try? Kasa.koordineliYaz(v, hedef)
                }
                // Gönderim doğrulaması: boyut tutuyorsa vault'ta sayılır.
                let a = (try? fm.attributesOfItem(atPath: hedef.path)[.size] as? Int) ?? -1
                let b = (try? fm.attributesOfItem(atPath: kaynak.path)[.size] as? Int) ?? -2
                if a == b || (a > 0 && b < 0) { s.vaulttakiSesler.insert(ad) }
            }
            let dokum = sesVault.appendingPathComponent("dokum", isDirectory: true)
            for ad in (try? fm.contentsOfDirectory(atPath: dokum.path)) ?? [] where ad.hasSuffix(".txt") {
                s.dokumler[String(ad.dropLast(4))] = try? String(contentsOf: dokum.appendingPathComponent(ad), encoding: .utf8)
            }
            let deg = sesVault.appendingPathComponent("degerlendirme", isDirectory: true)
            for ad in (try? fm.contentsOfDirectory(atPath: deg.path)) ?? [] where ad.hasSuffix(".json") {
                s.degerlendirmeler[String(ad.dropLast(5))] = Kasa.koordineliOku(deg.appendingPathComponent(ad))
            }
            // 5 · Claude'un genel değerlendirmeleri
            let gd = kok.appendingPathComponent("degerlendirme", isDirectory: true)
            for ad in ((try? fm.contentsOfDirectory(atPath: gd.path)) ?? []).sorted() where ad.hasPrefix("genel-") && ad.hasSuffix(".json") {
                if let v = Kasa.koordineliOku(gd.appendingPathComponent(ad)) { s.genel.append(v) }
            }
            return s
        }
        guard let s = sonuc else { return }
        genelDegerlendirmeler = s.genel.compactMap { try? JSONDecoder().decode(GenelDegerlendirme.self, from: $0) }
            .sorted { $0.tarih > $1.tarih }

        // Öteki cihazların günlüklerini yerel önbelleğe al
        try? FileManager.default.createDirectory(at: digerKlasor, withIntermediateDirectories: true)
        for (ad, v) in s.digerler { try? v.write(to: digerKlasor.appendingPathComponent(ad), options: .atomic) }
        for (ad, v) in [("kartlar.json", s.kartlar), ("akis.json", s.akis), ("mufredat.json", s.mufredat)] {
            guard let v else { continue }
            try? FileManager.default.createDirectory(at: yerel.appendingPathComponent("veri"), withIntermediateDirectories: true)
            try? v.write(to: yerel.appendingPathComponent("veri/\(ad)"), options: .atomic)
        }
        let eskiSurum = (paket.surum, akis.surum)
        icerigiYukle()
        gunlukYukle()
        yenidenHesapla()

        var yeni: [String: SesBilgisi] = [:]
        for o in durum.sesNotlari {
            let id = (o.metin ?? "").replacingOccurrences(of: ".m4a", with: "")
            let deg = s.degerlendirmeler[id].flatMap { try? JSONDecoder().decode(SesDegerlendirme.self, from: $0) }
            yeni[o.id] = SesBilgisi(dokum: s.dokumler[id], degerlendirme: deg,
                                    vaultta: s.vaulttakiSesler.contains(o.metin ?? "") || sesler[o.id]?.vaultta == true)
        }
        sesler = yeni
        sonEsitleme = Date()
        if eskiSurum.0 != paket.surum && eskiSurum.0 != "0" { bildirim = "Yeni kart paketi geldi." }
        widgetYaz()
        await LibraryStore.shared.sync(kasa)
    }
}
