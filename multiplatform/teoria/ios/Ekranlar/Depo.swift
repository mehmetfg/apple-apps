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
    var sembol: String { switch self { case .sistem: "circle.lefthalf.filled"; case .acik: "sun.max"; case .koyu: "moon" } }
    var sema: ColorScheme? { switch self { case .sistem: nil; case .acik: .light; case .koyu: .dark } }
}

/// Volatile sync status, kept out of Depo: a sync starting or ending must not invalidate every screen that takes
/// Depo as an environment object. The few places that show it observe it through `SyncAware`.
@MainActor
final class SyncStatus: ObservableObject {
    @Published fileprivate(set) var syncing = false
    @Published fileprivate(set) var updating = false
    @Published fileprivate(set) var lastSync: Date?
}

/// Rebuilds only its content when the sync status changes.
struct SyncAware<Content: View>: View {
    @ObservedObject var status: SyncStatus
    @ViewBuilder var content: (SyncStatus) -> Content
    var body: some View { content(status) }
}

/// Size and modification date of a file: enough to tell that a vault file has not changed since the last sync.
struct FileStamp: Equatable, Sendable {
    let size: Int
    let modified: Date
    static func of(_ u: URL) -> FileStamp? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: u.path),
              let n = a[.size] as? NSNumber, let m = a[.modificationDate] as? Date else { return nil }
        return FileStamp(size: n.intValue, modified: m)
    }
}

@MainActor
final class Depo: ObservableObject {
    /// The one store of the process, for the background refresh (it runs with no window).
    static weak var current: Depo?
    @Published private(set) var paket: Paket = .bos { didSet { revision += 1 } }
    @Published private(set) var akis: Akis = .bos {
        didSet {
            isaretIndeksi = Dictionary(akis.isaretler.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            revision += 1
        }
    }
    private var isaretIndeksi: [String: Isaret] = [:]   // id → işaret: bildirim, widget ve sesli notlar O(1) bulur
    @Published private(set) var mufredat: Mufredat = .bos
    @Published private(set) var olaylar: [Olay] = []
    @Published private(set) var durum = Durum() { didSet { revision += 1 } }
    @Published private(set) var sesler: [String: SesBilgisi] = [:]
    let sync = SyncStatus()
    var sonEsitleme: Date? { sync.lastSync }
    var esitleniyor: Bool { sync.syncing }
    var guncelleniyor: Bool { sync.updating }
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
    private var syncAgain = false                       // a sync was asked for while one was running
    private var vaultStamps: [String: FileStamp] = [:]  // vault files as last read in this run (unchanged → skipped)
    private var bundleSurum: [String: String] = [:]     // version of the content shipped with the app
    private var bozukBen = 0
    private var bozukDiger: [String: Int] = [:]
    private var revision = 0                            // bumps when what the widget snapshot is built from changes
    private var snapshotCache: (revision: Int, minutes: Int, day: String, at: Date, value: WidgetAnlik)?

    init() {
        Depo.current = self
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
            if u != adaylar[0] { bundleSurum[ad] = s }
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
        var hepsi = ben.olaylar
        bozukBen = ben.bozuk
        bozukDiger = [:]
        for ad in (try? FileManager.default.contentsOfDirectory(atPath: digerKlasor.path)) ?? [] where ad.hasSuffix(".jsonl") {
            let r = Gunluk.oku(digerKlasor.appendingPathComponent(ad))
            hepsi += r.olaylar
            bozukDiger[ad] = r.bozuk
        }
        bozukSatir = bozukBen + bozukDiger.values.reduce(0, +)
        olaylar = Gunluk.tekille(hepsi)
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
            if !hemen { try? await Task.sleep(for: .milliseconds(800)) }
            guard let self, !Task.isCancelled else { return }
            Paylasim.yaz(self.anlik())
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// The widget snapshot. Built once per change: the widget write, the notification planner and the Mac's menu bar
    /// ask for it within moments of each other, and nothing in it moves faster than a minute.
    func anlik() -> WidgetAnlik {
        let now = Date(), day = Tarih.gun(now)
        if let c = snapshotCache, c.revision == revision, c.minutes == kurDakika, c.day == day,
           now.timeIntervalSince(c.at) < 60 { return c.value }
        let v = buildSnapshot()
        snapshotCache = (revision, kurDakika, day, now, v)
        return v
    }

    private func buildSnapshot() -> WidgetAnlik {
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
        // The ring and the week also count a finished morning session (the daily Kür, Sabah): the phone writes no
        // `kur` event for it. Levels (kademeler) still come from `kur` events only.
        let morningToday = d.morningSessionSeconds(Tarih.gun(simdi)) / 60
        let morningWeek = (0..<7).reversed().map { d.morningSessionSeconds(Tarih.gun(simdi.gun(-$0))) / 60 }
        let weekStart = Tarih.takvim.dateInterval(of: .weekOfYear, for: simdi)?.start ?? simdi.gunBasi
        var morningCount = 0
        var cursor = weekStart
        while cursor <= simdi {
            if d.morningSessionSeconds(Tarih.gun(cursor)) > 0 { morningCount += 1 }
            cursor = cursor.gun(1)
        }
        return WidgetAnlik(guncel: simdi, aforizmalar: afo, hatirla: Array(hat.prefix(16)), kitaplar: Array(kitaplar),
                           bugunDakika: d.bugunDakika + morningToday, hedefDakika: kurDakika,
                           hafta: zip(d.hafta, morningWeek).map { $0 + $1 },
                           kademeler: Dictionary(uniqueKeysWithValues: Hat.allCases.map { ($0.rawValue, d.kademe($0)) }),
                           buHaftaKur: d.buHaftaKur + morningCount, isaretHafta: hafta8,
                           gundem: Dil.sikKelimeler(ay, adet: 5).map(\.0), gecmisteBugun: gecmis,
                           oturmus: d.oturmusKavramlar(p).count, toplamKavram: p.kavramlar.count)
    }

    // MARK: Eşitleme

    func esitle(gecikme: Double = 0) {
        esitlemeGorevi?.cancel()
        esitlemeGorevi = Task { [weak self] in
            if gecikme > 0 { try? await Task.sleep(for: .seconds(gecikme)) }
            guard let self, !Task.isCancelled else { return }
            await self.esitleSimdi()
        }
    }

    /// Akış güncelleme düğmesi. Mac: Voice Dream senkronu + akis.py'yi çalıştırır (o da mufredat.py'yi), sonra eşitler.
    /// iPhone: Python çalışmaz; yalnızca vault'taki en son akışı çeker (üretimi Mac'teki sabah görevi yapar).
    func guncelle() async {
        guard !guncelleniyor else { return }
        sync.updating = true
        defer { sync.updating = false }
        #if os(macOS)
        let teoria = Kasa.macYolu
        let pdm = teoria.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let hata: String? = await Task.detached(priority: .userInitiated) { () -> String? in
            let adimlar: [(URL, [String], URL)] = [
                (pdm.appendingPathComponent("Artifacts/_tezgah/kutuphane.py"), ["--gun", "3"], pdm),
                (teoria.appendingPathComponent("veri/library.py"), [], teoria),   // Voice Dream + Voice Reader → kütüphane
                (teoria.appendingPathComponent("veri/akis.py"), [], teoria),      // akış kütüphaneyi okur, sonra kütüphaneyi bir kez daha kurar
                (teoria.appendingPathComponent("veri/sabah.py"), [], teoria),     // Sabah: dinlenen günler → bölümler → kartlar
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
        while esitleniyor { try? await Task.sleep(for: .milliseconds(200)) }   // süren eşitleme bitsin, sonra çek
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
        var restored: [Olay] = []               // this device's events found only in the vault copy of its log
        var others: [Olay] = []                 // events of other devices' logs that changed since the last look
        var otherBroken: [String: Int] = [:]    // broken lines per changed log
        var stamps: [String: FileStamp] = [:]
        var paket: Paket?                       // content, decoded here (off the main actor), only when it changed
        var akis: Akis?
        var mufredat: Mufredat?
        var dokumler: [String: String] = [:]
        var degerlendirmeler: [String: Data] = [:]
        var vaulttakiSesler: Set<String> = []
        var genel: [Data] = []
    }

    /// One sync at a time. A request that arrives while one runs is not dropped: the sync runs once more after it
    /// (an event added during a sync would otherwise wait for the next foreground).
    func esitleSimdi() async {
        guard kasa.bagli else { return }
        if sync.syncing { syncAgain = true; return }
        sync.syncing = true
        defer { sync.syncing = false }
        repeat {
            syncAgain = false
            await esitleBirKez()
        } while syncAgain
        await LibraryStore.shared.sync(kasa)
        await NotesStore.shared.sync(kasa)
    }

    private func esitleBirKez() async {
        let ben = Cihaz.ad
        let benimOlaylar = olaylar.filter { $0.cihaz == ben }
        let bilinen = Set(olaylar.map(\.id))
        let damgalar = vaultStamps
        let digerYerel = digerKlasor
        let veriYerel = yerel.appendingPathComponent("veri", isDirectory: true)
        let sesYerel = sesKlasoru
        let gonderilecekSes = durum.sesNotlari.compactMap(\.metin)

        let sonuc: EsitlemeSonucu? = await kasa.ile { kok in
            var s = EsitlemeSonucu()
            let fm = FileManager.default
            let ilerleme = kok.appendingPathComponent("ilerleme", isDirectory: true)
            try fm.createDirectory(at: ilerleme, withIntermediateDirectories: true)
            // 1 · Kendi günlüğüm: vault'takiyle birleştir, vault'a yaz. Yerel günlük burada asla yeniden yazılmaz:
            // bu eşitleme sürerken eklenen olaylar yalnız orada durur. Vault'ta olup bu cihazda olmayanlar
            // (yeniden kurulumda yerel boş kalmış olabilir) liste olarak döner, ana aktör kimliğe göre ekler.
            let benimVault = ilerleme.appendingPathComponent("\(ben).jsonl")
            if !fm.fileExists(atPath: benimVault.path) { Kasa.indir(benimVault) }
            let vaultBenim = Kasa.koordineliOku(benimVault).map { Gunluk.coz($0).olaylar } ?? []
            let birlesik = Gunluk.tekille(benimOlaylar + vaultBenim)
            if Set(birlesik.map(\.id)) != Set(vaultBenim.map(\.id)) {
                var v = Data(); for o in birlesik.sorted(by: { $0.t < $1.t }) { v.append(Gunluk.satir(o)) }
                try Kasa.koordineliYaz(v, benimVault)
            }
            s.restored = vaultBenim.filter { !bilinen.contains($0.id) }
            // 2 · Öteki cihazların günlükleri (çakışma kopyaları dahil): yalnız değişen dosya okunur ve çözülür
            try? fm.createDirectory(at: digerYerel, withIntermediateDirectories: true)
            for ad in (try? fm.contentsOfDirectory(atPath: ilerleme.path)) ?? [] {
                if ad.hasPrefix("."), ad.hasSuffix(".icloud") {
                    try? fm.startDownloadingUbiquitousItem(at: ilerleme.appendingPathComponent(String(ad.dropFirst().dropLast(7))))
                    continue
                }
                guard ad.hasSuffix(".jsonl"), ad != "\(ben).jsonl" else { continue }
                let u = ilerleme.appendingPathComponent(ad), anahtar = "ilerleme/\(ad)"
                let damga = FileStamp.of(u)
                if let damga, damgalar[anahtar] == damga { continue }          // unchanged since the last sync
                guard let v = Kasa.koordineliOku(u) else { continue }
                if let damga { s.stamps[anahtar] = damga }
                let kopya = digerYerel.appendingPathComponent(ad)
                if (try? Data(contentsOf: kopya)) == v { continue }            // same bytes as the copy already loaded
                try? v.write(to: kopya, options: .atomic)
                let r = Gunluk.coz(v)
                s.others += r.olaylar
                s.otherBroken[ad] = r.bozuk
            }
            // 3 · İçerik: değişmeyen dosya atlanır; değişen burada (ana aktörün dışında) çözülür
            try? fm.createDirectory(at: veriYerel, withIntermediateDirectories: true)
            func icerik<T: Decodable>(_ ad: String, _ tur: T.Type) -> T? {
                let u = kok.appendingPathComponent("veri/\(ad)"), anahtar = "veri/\(ad)"
                Kasa.indir(u)
                let damga = FileStamp.of(u)
                if let damga, damgalar[anahtar] == damga { return nil }
                guard let v = Kasa.koordineliOku(u) else { return nil }
                if let damga { s.stamps[anahtar] = damga }
                let kopya = veriYerel.appendingPathComponent(ad)
                if (try? Data(contentsOf: kopya)) == v { return nil }
                guard let x = try? JSONDecoder().decode(T.self, from: v) else { return nil }   // half-synced file: keep the good copy
                try? v.write(to: kopya, options: .atomic)
                return x
            }
            s.paket = icerik("kartlar.json", Paket.self)
            s.akis = icerik("akis.json", Akis.self)
            s.mufredat = icerik("mufredat.json", Mufredat.self)
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
        let genel = s.genel.compactMap { try? JSONDecoder().decode(GenelDegerlendirme.self, from: $0) }
            .sorted { $0.tarih > $1.tarih }
        if genel != genelDegerlendirmeler { genelDegerlendirmeler = genel }
        vaultStamps.merge(s.stamps) { _, yeni in yeni }

        // Günlükler kimliğe göre birleşir: bellekte ve yerel dosyada olan hiçbir olay eski bir kopyayla ezilmez.
        var kimlikler = Set(olaylar.map(\.id))
        var gelen: [Olay] = []
        for o in s.restored where kimlikler.insert(o.id).inserted { Gunluk.ekle(o, benimGunluk); gelen.append(o) }
        for o in s.others where kimlikler.insert(o.id).inserted { gelen.append(o) }
        if !gelen.isEmpty { olaylar.append(contentsOf: gelen) }
        for (ad, n) in s.otherBroken { bozukDiger[ad] = n }
        let bozuk = bozukBen + bozukDiger.values.reduce(0, +)
        if bozuk != bozukSatir { bozukSatir = bozuk }

        // İçerik: paketle gelen sürüm daha yeniyse o kalır (açılıştaki kuralla aynı: eşitlikte vault kazanır).
        let eskiSurum = paket.surum
        var degisti = !gelen.isEmpty
        if let p = s.paket, p.surum >= (bundleSurum["kartlar.json"] ?? "") { paket = p; degisti = true }
        if let a = s.akis, a.surum >= (bundleSurum["akis.json"] ?? "") { akis = a; degisti = true }
        if let m = s.mufredat, m.surum >= (bundleSurum["mufredat.json"] ?? "") { mufredat = m }
        if !gelen.isEmpty { yenidenHesapla() }

        var yeni: [String: SesBilgisi] = [:]
        for o in durum.sesNotlari {
            let id = (o.metin ?? "").replacingOccurrences(of: ".m4a", with: "")
            let deg = s.degerlendirmeler[id].flatMap { try? JSONDecoder().decode(SesDegerlendirme.self, from: $0) }
            yeni[o.id] = SesBilgisi(dokum: s.dokumler[id], degerlendirme: deg,
                                    vaultta: s.vaulttakiSesler.contains(o.metin ?? "") || sesler[o.id]?.vaultta == true)
        }
        if yeni != sesler { sesler = yeni }
        sync.lastSync = Date()
        if eskiSurum != paket.surum && eskiSurum != "0" { bildirim = "Yeni kart paketi geldi." }
        if degisti { widgetYaz() }      // nothing new: the snapshot written on the way in still stands
    }
}
