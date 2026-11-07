// Telefonun deposu. Kayıtlar önce telefonda durur, vault bağlıysa ses/<ay>/'a gönderilir (gidemeyen bekler, kaybolmaz).
// Mac'in ürettiği dizin.json (Whisper dökümü, başlık, alan, amaç) çekilip yerel kopyası tutulur — yolda internet yoksa
// arşiv yine açılır. Düzeltmeler telefonda olay-iphone.jsonl'e yazılır ve vault'ta olay/iphone.jsonl olarak durur.
import Foundation
import WidgetKit

@MainActor
final class TelefonDeposu: ObservableObject {
    static let shared = TelefonDeposu()

    @Published private(set) var ogeler: [Oge] = []
    @Published private(set) var siniflar = Siniflar.varsayilan
    @Published private(set) var esitleniyor = false
    @Published private(set) var sonEsitleme: Date?
    @Published private(set) var gonderilmemis = 0
    /// Vault'a yazılmış ama iCloud'un henüz Mac'e yüklemediği kayıtlar (son 14 gün) ve iCloud'un kendi hata metni.
    /// 2026-10: telefon kayıtları "gönderildi" sayıyordu, iCloud ise günlerce hiçbirini yüklemedi; artık görünür.
    @Published private(set) var bulutBekleyen = 0
    @Published private(set) var bulutHata: String?
    /// Tatbik (2026-11-05): the merged items the Mac writes (Tatbik/tatbik.json); the phone's touches go to
    /// tatbik-olay-iphone.jsonl here and to Tatbik/olay/iphone.jsonl in the vault.
    @Published private(set) var tatbik = TatbikState.empty
    /// Daily feed (2026-11-06): the Mac writes Feed/feed.json; touches go to feed-events-iphone.jsonl and Feed/olay/iphone.jsonl.
    @Published private(set) var feed = FeedIssue.empty
    /// Merkez (2026-11-07): links.py's links.json (Yön, Konular), read-only; the Mac also pushes it over USB/Wi-Fi.
    @Published private(set) var links = Links.empty

    private let kok = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Kivilcim")
    private var kayit: URL { KayitMerkezi.kayitKlasoru }
    /// Edit log in the App Group (widget buttons and Shortcuts write here too); moved from Application Support 2026-11-02.
    private var olayDosyasi: URL { SharedStore.eventsFile ?? kok.appendingPathComponent("olay-iphone.jsonl") }
    private var dizinKopyasi: URL { kok.appendingPathComponent("dizin.json") }
    private var sinifKopyasi: URL { kok.appendingPathComponent("siniflar.json") }
    private var tatbikKopyasi: URL { kok.appendingPathComponent("tatbik.json") }
    private var tatbikOlay: URL { kok.appendingPathComponent("tatbik-olay-iphone.jsonl") }
    private var feedKopyasi: URL { kok.appendingPathComponent("feed.json") }
    private var feedOlay: URL { kok.appendingPathComponent("feed-events-iphone.jsonl") }
    private var linksKopyasi: URL { kok.appendingPathComponent("links.json") }
    private var onbellek: URL {
        let u = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ses")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true); return u
    }
    /// gönderilen künyenin içeriği (yeniden gönderim gerekiyor mu?)
    private var gonderilen: [String: Int] {
        get { UserDefaults.standard.dictionary(forKey: "gonderilen") as? [String: Int] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "gonderilen") }
    }

    private init() {
        try? FileManager.default.createDirectory(at: kok, withIntermediateDirectories: true)
        let eski = kok.appendingPathComponent("olay-iphone.jsonl")
        if let yeni = SharedStore.eventsFile, FileManager.default.fileExists(atPath: eski.path) {
            if let v = try? Data(contentsOf: eski) {
                var birlesik = (try? Data(contentsOf: yeni)) ?? Data()
                birlesik.insert(contentsOf: v, at: 0)
                if (try? birlesik.write(to: yeni, options: .atomic)) != nil { try? FileManager.default.removeItem(at: eski) }
            }
        }
        // the list was read on a background thread while the app was launching (preload); take it, then check once
        // more on the spot: that is only a few file stamps unless something changed in between
        if let (c, b) = TelefonDeposu.preloadBox.take() {
            cache = c
            if let b { uygula(b) }
        }
        kur()
        loadTatbik()
        loadFeed()
        loadLinks()
    }

    // MARK: Bağlar (Yön, Konular)

    func loadLinks() {
        guard let v = try? Data(contentsOf: linksKopyasi), let l = try? JSONDecoder().decode(Links.self, from: v),
              l.built != links.built || links.topics.isEmpty else { return }
        links = l
    }

    /// Display name of a topic id (book in links.json, recent book, or a free "k:<name>").
    func topicName(_ id: String?) -> String {
        guard let id, !id.isEmpty, id != "-" else { return "Konusuz" }
        if id.hasPrefix("k:") { return String(id.dropFirst(2)) }
        return links.topic(id)?.short ?? links.recent_books.first { $0.id == id }?.short ?? id
    }

    func oge(_ id: String) -> Oge? { ogeler.first { $0.id == id } }

    // MARK: Akış

    func loadFeed() {
        guard let v = try? Data(contentsOf: feedKopyasi), var s = try? JSONDecoder().decode(FeedIssue.self, from: v) else { return }
        // own touches the Mac has not merged yet show at once
        if let e = try? Data(contentsOf: feedOlay) {
            for part in e.split(separator: 0x0A) {
                guard let o = try? JSONSerialization.jsonObject(with: Data(part)) as? [String: Any],
                      let h = o["hedef"] as? String, let d = o["deger"] as? String, let t = o["t"] as? String,
                      let i = s.items.firstIndex(where: { $0.id == h }), t > (s.items[i].touched ?? "") else { continue }
                s.items[i].status = d
                s.items[i].touched = t
            }
        }
        feed = s
    }

    func feedTouch(_ item: String, _ status: String) {
        let v = Olay.satir(hedef: item, tur: "status", deger: status, cihaz: "iphone")
        if let h = try? FileHandle(forWritingTo: feedOlay) { h.seekToEndOfFile(); h.write(v); try? h.close() }
        else { try? v.write(to: feedOlay, options: .atomic) }
        loadFeed()
        Task { await gonder() }
    }

    /// The Güncelle button: only the Mac can fetch. The request goes with the touches, then the phone looks again
    /// twice, because the Mac notices within 45 seconds and needs a little while to answer.
    func feedRefresh() async {
        let v = Olay.satir(hedef: "feed", tur: "refresh", deger: "1", cihaz: "iphone")
        if let h = try? FileHandle(forWritingTo: feedOlay) { h.seekToEndOfFile(); h.write(v); try? h.close() }
        else { try? v.write(to: feedOlay, options: .atomic) }
        await gonder()
        for _ in 0..<2 {
            try? await Task.sleep(for: .seconds(60))
            await gonder()
        }
    }

    // MARK: Tatbik

    func loadTatbik() {
        guard let v = try? Data(contentsOf: tatbikKopyasi), var s = try? JSONDecoder().decode(TatbikState.self, from: v) else { return }
        // own touches not yet merged by the Mac show at once
        if let e = try? Data(contentsOf: tatbikOlay) {
            for part in e.split(separator: 0x0A) {
                guard let o = try? JSONSerialization.jsonObject(with: Data(part)) as? [String: Any],
                      let h = o["hedef"] as? String, let tur = o["tur"] as? String, let d = o["deger"] as? String,
                      let t = o["t"] as? String, t > (s.guncelleme ?? ""),
                      let i = s.maddeler.firstIndex(where: { $0.id == h }) else { continue }
                if tur == "status" { s.maddeler[i].durum = d; s.maddeler[i].kaynak_durum = "elle" }
                if tur == "note", !(s.maddeler[i].notlar ?? []).contains(where: { $0.t == t }) {
                    s.maddeler[i].notlar = (s.maddeler[i].notlar ?? []) + [TatbikNote(t: t, text: d, device: "iphone")]
                }
            }
        }
        tatbik = s
    }

    func tatbikDuzelt(_ item: String, _ tur: String, _ deger: String) {
        let v = TatbikEvent.line(item: item, kind: tur, value: deger, device: "iphone")
        if let h = try? FileHandle(forWritingTo: tatbikOlay) { h.seekToEndOfFile(); h.write(v); try? h.close() }
        else { try? v.write(to: tatbikOlay, options: .atomic) }
        loadTatbik()
        Task { await gonder() }
    }

    // MARK: Liste

    /// What the last rebuild read, with the file stamps that tell whether a file must be read again.
    private var cache = StoreCache()

    /// Rebuilds the list from the local files. Cheap to call after every edit: a file whose modification date and
    /// size are unchanged is not read again, and when no input changed at all nothing is rebuilt or published.
    /// The heavy reads happen elsewhere: dizin.json is decoded in gonder()'s background work, the first read of
    /// everything in preload().
    func kur() {
        guard let b = TelefonDeposu.build(.standard, gonderilen: gonderilen, cache: &cache) else { return }
        uygula(b)
    }

    private func uygula(_ b: StoreBuild) {
        siniflar = b.siniflar
        if ogeler != b.ogeler { ogeler = b.ogeler }
        if gonderilmemis != b.bekleyen { gonderilmemis = b.bekleyen }
        widgetiGuncelle()
    }

    /// The whole rebuild as a function of the files: runs on the main actor for an edit (warm cache) and on a
    /// background thread for the first read. Returns nil when no input changed since `cache` was filled.
    nonisolated static func build(_ p: StorePaths, gonderilen g: [String: Int], cache: inout StoreCache) -> StoreBuild? {
        let fm = FileManager.default
        let sinifU = fm.fileExists(atPath: p.sinifKopyasi.path) ? p.sinifKopyasi : p.paketSiniflari
        let kunyeDosyalari = ((try? fm.contentsOfDirectory(at: p.kayit, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? [])
            .filter { $0.pathExtension == "json" }
        var damgalar: [String: FileStamp] = [:]
        for u in kunyeDosyalari { if let d = FileStamp(u) { damgalar[u.lastPathComponent] = d } }
        let imza = StoreSignature(dizin: FileStamp(p.dizinKopyasi), sinifYolu: sinifU?.path, sinif: sinifU.flatMap { FileStamp($0) },
                                  olay: FileStamp(p.olayDosyasi), kunyeler: damgalar, gonderilen: g,
                                  gun: String(Zaman.iso(Date()).prefix(10)))     // "today" counts change at midnight
        if imza == cache.imza { return nil }
        var tam = true      // false when a file that is there could not be read: the next call reads again

        let siniflar = Siniflar.yukle(sinifU)
        var liste: [Oge]
        if let d = imza.dizin, d == cache.dizinDamgasi { liste = cache.dizinOgeler }
        else if let v = try? Data(contentsOf: p.dizinKopyasi), let d = try? JSONDecoder().decode(Dizin.self, from: v) {
            liste = d.ogeler
            cache.dizinDamgasi = imza.dizin; cache.dizinOgeler = d.ogeler; cache.dizinUretim = d.uretim
        } else {
            liste = []
            cache.dizinDamgasi = nil; cache.dizinOgeler = []; cache.dizinUretim = nil
            if imza.dizin != nil { tam = false }
        }

        var kunyeler: [String: CachedKunye] = [:]
        var sirali: [Kunye] = []
        for u in kunyeDosyalari {
            let ad = u.lastPathComponent
            if let d = damgalar[ad], let c = cache.kunyeler[ad], c.damga == d { kunyeler[ad] = c; sirali.append(c.kunye); continue }
            guard let k = try? JSONDecoder().decode(Kunye.self, from: Data(contentsOf: u)) else { tam = false; continue }
            if let d = damgalar[ad] { kunyeler[ad] = CachedKunye(damga: d, kunye: k) } else { tam = false }
            sirali.append(k)
        }
        cache.kunyeler = kunyeler

        let bilinen = Set(liste.map(\.id))
        var bekleyen = 0
        for k in sirali {
            if g[k.id] == nil { bekleyen += 1 }
            guard !bilinen.contains(k.id) else { continue }
            let m4a = p.kayit.appendingPathComponent(k.id + ".m4a")
            var o = Oge(id: k.id, tarih: k.zaman, cihaz: k.cihaz, sure: k.sure, kalite: k.kalite,
                        boyut: (try? m4a.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0,
                        ses: "ses/\(k.zaman.prefix(7))/\(k.id).m4a", metin: k.onMetin ?? "",
                        baslik: "Sesli fikir · \(Zaman.saat(Zaman.coz(k.zaman) ?? Date()))",
                        durum: g[k.id] == nil ? "yerel" : "bekliyor")
            o.kind = k.kind ?? "spark"
            if o.isJournal { o.baslik = "Sesli günlük · \(Zaman.saat(Zaman.coz(k.zaman) ?? Date()))" }
            if let m = k.onMetin, !m.isEmpty, !o.isJournal {
                o.baslik = Kural.baslik(m, siniflar); o.alan = Kural.alan(m, siniflar); o.amac = Kural.amac(m, siniflar)
            }
            liste.append(o)
        }
        if let v = try? Data(contentsOf: p.olayDosyasi) { Olay.uygula(v, &liste) } else if imza.olay != nil { tam = false }
        cache.imza = tam ? imza : nil
        return StoreBuild(ogeler: liste.sorted { $0.tarih > $1.tarih }, siniflar: siniflar, bekleyen: bekleyen)
    }

    /// Cold start: KivilcimApp.init calls this, so dizin.json, the sidecars and the edit log are read and decoded
    /// on a background thread while the app is still launching. init() takes the result (and waits only for what
    /// is not finished yet). Nothing here touches audio.
    nonisolated static func preload() { preloadBox.start() }
    nonisolated fileprivate static let preloadBox = PreloadBox()
    nonisolated fileprivate static var kayitliGonderilen: [String: Int] {
        UserDefaults.standard.dictionary(forKey: "gonderilen") as? [String: Int] ?? [:]
    }

    // MARK: Yeni kayıt

    func yeniKayit(_ k: Kunye) {
        try? JSONEncoder.guzel.encode(k).write(to: kayit.appendingPathComponent(k.id + ".json"), options: .atomic)
        kur()
    }

    func onMetin(_ id: String, _ metin: String) {
        let u = kayit.appendingPathComponent(id + ".json")
        guard var k = try? JSONDecoder().decode(Kunye.self, from: Data(contentsOf: u)) else { return }
        k.onMetin = metin
        try? JSONEncoder.guzel.encode(k).write(to: u, options: .atomic)
        kur()
    }

    // MARK: Düzeltme

    func duzelt(_ o: Oge, _ tur: String, _ deger: Any) {
        SharedStore.appendEvent(target: o.id, type: tur, value: deger)
        if tur == "sil", o.cihaz == "iphone" {
            // telefondaki kopyayı da kaldır; vault'taki ses Mac'te _silinen'e taşınır (geri alınabilir)
            if gonderilen[o.id] != nil {
                try? FileManager.default.removeItem(at: kayit.appendingPathComponent(o.id + ".m4a"))
                try? FileManager.default.removeItem(at: kayit.appendingPathComponent(o.id + ".json"))
            }
        }
        kur()
        Task { await gonder() }
    }

    // MARK: Eşitleme

    /// Gönderilmemiş kayıtları ve düzeltmeleri vault'a yazar, sonra Mac'in dizinini çeker.
    /// A call that arrives while a run is in flight does not get lost: the run may already be past the step that
    /// would have picked the new recording or edit up, so one more pass follows it, and the caller waits for that pass.
    func gonder() async {
        guard Kasa.shared.bagli else { return }
        if let t = syncTask { syncAgain = true; await t.value; return }
        esitleniyor = true
        let t = Task { @MainActor in
            repeat { syncAgain = false; await gonderBirKez() } while syncAgain
            syncTask = nil
            esitleniyor = false
        }
        syncTask = t
        await t.value
    }
    private var syncTask: Task<Void, Never>?
    private var syncAgain = false

    private func gonderBirKez() async {
        let kayit = self.kayit, olay = olayDosyasi, dizinK = dizinKopyasi, sinifK = sinifKopyasi
        let tatbikK = tatbikKopyasi, tatbikO = tatbikOlay
        let feedK = feedKopyasi, feedO = feedOlay
        let linksK = linksKopyasi
        let g = gonderilen
        // the local copy's "uretim" comes from the last rebuild: no need to decode the copy again just to compare
        let simdikiUretim = cache.dizinDamgasi == nil ? "" : (cache.dizinUretim ?? "")
        let isaretK = SharedStore.container?.appendingPathComponent("isaret")
        let sonuc: SyncResult? = await Kasa.shared.ile { veri in
            // Paylaş › Kıvılcım'dan gelen işaretler (2026-11-04): App Group → vault isaret/<ay>/;
            // gidenler App Group'ta gonderildi/'ye kayar (iCloud takılırsa Mac oradan da alır)
            if let ik = isaretK { TelefonDeposu.isaretleriGonder(ik, veri) }
            var yeni = g
            for u in (try? FileManager.default.contentsOfDirectory(at: kayit, includingPropertiesForKeys: nil)) ?? [] where u.pathExtension == "json" {
                guard let v = try? Data(contentsOf: u), let k = try? JSONDecoder().decode(Kunye.self, from: v) else { continue }
                let imza = v.imza
                if yeni[k.id] == imza { continue }
                let hedef = veri.appendingPathComponent("ses/\(k.zaman.prefix(7))")
                let m4a = kayit.appendingPathComponent(k.id + ".m4a")
                guard FileManager.default.fileExists(atPath: m4a.path) else { continue }
                // ses bir kez gider; künye (ön döküm eklenince) yeniden gidebilir
                if yeni[k.id] == nil {
                    guard Kasa.koordineliKopyala(m4a, hedef.appendingPathComponent(k.id + ".m4a")) else { continue }
                }
                guard (try? Kasa.koordineliYaz(v, hedef.appendingPathComponent(k.id + ".json"))) != nil else { continue }
                yeni[k.id] = imza
            }
            if let v = try? Data(contentsOf: olay) {
                try? Kasa.koordineliYaz(v, veri.appendingPathComponent("olay/iphone.jsonl"))
            }
            var cekilen: Dizin?
            var cekilenDamga: FileStamp?
            let d = veri.appendingPathComponent("dizin.json")
            // iCloud may hand back a stale copy while the Mac pushes a fresh one over USB/Wi-Fi: keep the newer
            if Kasa.indir(d, bekle: 4), let v = Kasa.koordineliOku(d), let yeni = try? JSONDecoder().decode(Dizin.self, from: v) {
                if (yeni.uretim ?? "") >= simdikiUretim, (try? v.write(to: dizinK, options: .atomic)) != nil {
                    // decoded here, off the main thread: the rebuild that follows takes this list instead of decoding again
                    cekilen = yeni; cekilenDamga = FileStamp(dizinK)
                }
            }
            if let v = try? Data(contentsOf: tatbikO) {
                try? Kasa.koordineliYaz(v, veri.appendingPathComponent("Tatbik/olay/iphone.jsonl"))
            }
            let tb = veri.appendingPathComponent("Tatbik/tatbik.json")
            // the Mac may also push it straight over USB/Wi-Fi (isle.py); a file that does not decode is not kept
            if Kasa.indir(tb, bekle: 2), let v = Kasa.koordineliOku(tb), (try? JSONDecoder().decode(TatbikState.self, from: v)) != nil,
               v != (try? Data(contentsOf: tatbikK)) {
                try? v.write(to: tatbikK, options: .atomic)
            }
            if let v = try? Data(contentsOf: feedO) {
                try? Kasa.koordineliYaz(v, veri.appendingPathComponent("Feed/olay/iphone.jsonl"))
            }
            let fd = veri.appendingPathComponent("Feed/feed.json")
            // the Mac may push it straight too: iCloud's copy replaces ours only if it is not older
            if Kasa.indir(fd, bekle: 2), let v = Kasa.koordineliOku(fd), let yeni = try? JSONDecoder().decode(FeedIssue.self, from: v) {
                let eski = (try? Data(contentsOf: feedK)).flatMap { try? JSONDecoder().decode(FeedIssue.self, from: $0) }
                if (yeni.updated ?? "") >= (eski?.updated ?? "") { try? v.write(to: feedK, options: .atomic) }
            }
            let ln = veri.appendingPathComponent("links.json")
            // keep the newer of iCloud's copy and the one the Mac pushed straight (both carry "built")
            if Kasa.indir(ln, bekle: 2), let v = Kasa.koordineliOku(ln), let yeni = try? JSONDecoder().decode(Links.self, from: v) {
                let eski = (try? Data(contentsOf: linksK)).flatMap { try? JSONDecoder().decode(Links.self, from: $0) }
                if yeni.built >= (eski?.built ?? "") { try? v.write(to: linksK, options: .atomic) }
            }
            let s = veri.appendingPathComponent("siniflar.json")
            if Kasa.indir(s, bekle: 2), let v = Kasa.koordineliOku(s) { try? v.write(to: sinifK, options: .atomic) }
            // yazdık; iCloud gerçekten yükledi mi? (son 14 günün kayıtları)
            let sinir = Zaman.iso(Date().addingTimeInterval(-14 * 86400)).prefix(10).replacingOccurrences(of: "-", with: "")
            var bekleyen = 0
            var hata: String?
            for id in yeni.keys where id.prefix(8) >= sinir {
                let u = veri.appendingPathComponent("ses/\(id.prefix(4))-\(id.dropFirst(4).prefix(2))/\(id).m4a")
                guard let d = try? u.resourceValues(forKeys: [.ubiquitousItemIsUploadedKey, .ubiquitousItemUploadingErrorKey]) else { continue }
                if d.ubiquitousItemIsUploaded == false { bekleyen += 1 }
                if hata == nil, let e = d.ubiquitousItemUploadingError { hata = e.localizedDescription }
            }
            return SyncResult(gonderilen: yeni, bekleyen: bekleyen, hata: hata, dizin: cekilen, dizinDamgasi: cekilenDamga)
        }
        if let sonuc {
            gonderilen = sonuc.gonderilen
            sonEsitleme = Date()
            if sonuc.bekleyen != bulutBekleyen || sonuc.hata != bulutHata {
                Tani.yaz("iCloud: yüklenmeyi bekleyen \(sonuc.bekleyen) kayıt" + (sonuc.hata.map { " · hata: \($0)" } ?? ""))
            }
            bulutBekleyen = sonuc.bekleyen
            bulutHata = sonuc.hata
            loadTatbik()
            loadFeed()
            loadLinks()
            if let d = sonuc.dizin, let damga = sonuc.dizinDamgasi {
                cache.dizinDamgasi = damga; cache.dizinOgeler = d.ogeler; cache.dizinUretim = d.uretim
            }
        }
        kur()
    }

    nonisolated static func isaretleriGonder(_ ik: URL, _ veri: URL) {
        let fm = FileManager.default
        for ay in (try? fm.contentsOfDirectory(at: ik, includingPropertiesForKeys: nil)) ?? [] where ay.lastPathComponent != "gonderildi" {
            for f in (try? fm.contentsOfDirectory(at: ay, includingPropertiesForKeys: nil)) ?? [] where f.pathExtension == "json" {
                let id = f.deletingPathExtension().lastPathComponent
                let hedef = veri.appendingPathComponent("isaret/\(ay.lastPathComponent)")
                let ses = ay.appendingPathComponent(id + ".m4a")
                if fm.fileExists(atPath: ses.path) {
                    guard Kasa.koordineliKopyala(ses, hedef.appendingPathComponent(id + ".m4a")) else { continue }
                }
                guard let v = try? Data(contentsOf: f), (try? Kasa.koordineliYaz(v, hedef.appendingPathComponent(id + ".json"))) != nil else { continue }
                let arsiv = ik.appendingPathComponent("gonderildi/\(ay.lastPathComponent)")
                try? fm.createDirectory(at: arsiv, withIntermediateDirectories: true)
                for x in [f, ses] where fm.fileExists(atPath: x.path) {
                    try? fm.removeItem(at: arsiv.appendingPathComponent(x.lastPathComponent))
                    try? fm.moveItem(at: x, to: arsiv.appendingPathComponent(x.lastPathComponent))
                }
                Tani.yaz("işaret gönderildi \(id)")
            }
        }
    }

    /// Çalınacak dosya: telefondaysa oradan, değilse vault'tan önbelleğe indirilir.
    /// A vault-relative sound (Teoria / Wise Path note in links.json) → a local cached copy.
    func vaultSes(_ rel: String) async -> URL? {
        guard !rel.isEmpty else { return nil }
        let ob = onbellek.appendingPathComponent("v-" + rel.replacingOccurrences(of: "/", with: "_"))
        if FileManager.default.fileExists(atPath: ob.path) { return ob }
        let tamam: Bool? = await Kasa.shared.ile { veri in
            // veri = <vault>/05 - Notlar/Fikirler/Kıvılcım
            let vault = veri.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let u = vault.appendingPathComponent(rel)
            guard Kasa.indir(u, bekle: 15) else { return false }
            return Kasa.koordineliKopyala(u, ob)
        }
        return tamam == true ? ob : nil
    }

    func sesURL(_ o: Oge) async -> URL? {
        let fid = o.parent.isEmpty ? o.id : o.parent      // an idea pulled out of a journal plays the journal's audio
        let yerel = kayit.appendingPathComponent(fid + ".m4a")
        if FileManager.default.fileExists(atPath: yerel.path) { return yerel }
        let ob = onbellek.appendingPathComponent(fid + ".m4a")
        if FileManager.default.fileExists(atPath: ob.path) { return ob }
        let yol = o.ses
        let tamam: Bool? = await Kasa.shared.ile { veri in
            let u = veri.appendingPathComponent(yol)
            guard Kasa.indir(u, bekle: 15) else { return false }
            return Kasa.koordineliKopyala(u, ob)
        }
        return tamam == true ? ob : nil
    }

    // MARK: Widget

    /// What the widgets show, as last written by this process. The snapshot file and the timelines are touched
    /// only when this changes (the first rebuild of a process always writes).
    private var sonWidgetDurumu: WidgetContent?

    private func widgetiGuncelle() {
        let son = ogeler.first
        let sonAlan = son.map { siniflar.alan($0.alan) }
        let icerik = WidgetContent(
            items: ogeler.map { o in
                let al = siniflar.alan(o.alan)
                return ItemSnapshot(id: o.id, title: o.baslik, priority: o.priority, status: o.status, kind: o.kind,
                                    area: al.ad, color: al.renk, date: o.tarih, noteCount: o.notes.count)
            },
            sonBaslik: son?.baslik, sonAlan: sonAlan?.ad, sonRenk: sonAlan?.renk, sonZaman: son?.zaman,
            bugun: ogeler.filter { Calendar.current.isDateInToday($0.zaman) }.count)
        guard icerik != sonWidgetDurumu else { return }
        sonWidgetDurumu = icerik
        let d = WidgetDurumu.d
        if son != nil {
            d.set(icerik.sonBaslik, forKey: "sonBaslik")
            d.set(icerik.sonAlan, forKey: "sonAlan")
            d.set(icerik.sonRenk, forKey: "sonRenk")
            d.set(icerik.sonZaman, forKey: "sonZaman")
        }
        d.set(icerik.bugun, forKey: "bugun")
        SharedStore.writeItems(icerik.items)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Lists

    /// Open items: urgent first, then newest first.
    var acik: [Oge] { ogeler.filter { !$0.isDone && !$0.isJournal }.sorted { ($0.priority, $0.tarih) > ($1.priority, $1.tarih) } }
    var biten: [Oge] { ogeler.filter { $0.isDone && !$0.isJournal }.sorted { $0.done_at > $1.done_at } }
    var gunlukler: [Oge] { ogeler.filter(\.isJournal) }
    func cocuklar(_ j: Oge) -> [Oge] { ogeler.filter { $0.parent == j.id }.sorted { $0.offset < $1.offset } }

    var toplamMB: Double { Double(ogeler.reduce(0) { $0 + $1.boyut }) / 1_000_000 }
    var toplamDakika: Int { Int(ogeler.reduce(0) { $0 + $1.sure } / 60) }
}

// MARK: Rebuild cache

/// Modification date and size of a file: with the same stamp the file is not read again.
struct FileStamp: Hashable, Sendable {
    var modified: Date
    var size: Int
    init?(_ u: URL) {
        guard let v = try? u.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let m = v.contentModificationDate, let s = v.fileSize else { return nil }
        modified = m; size = s
    }
}

/// Where the store's local files are (the same places TelefonDeposu's own properties point at).
struct StorePaths: Sendable {
    var dizinKopyasi: URL
    var sinifKopyasi: URL
    var paketSiniflari: URL?
    var kayit: URL
    var olayDosyasi: URL

    static var standard: StorePaths {
        let kok = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Kivilcim")
        return StorePaths(dizinKopyasi: kok.appendingPathComponent("dizin.json"), sinifKopyasi: kok.appendingPathComponent("siniflar.json"),
                          paketSiniflari: Bundle.main.url(forResource: "siniflar", withExtension: "json"),
                          kayit: KayitMerkezi.kayitKlasoru,
                          olayDosyasi: SharedStore.eventsFile ?? kok.appendingPathComponent("olay-iphone.jsonl"))
    }
}

/// Every input of a rebuild. Equal signatures mean the rebuild would give the same list.
struct StoreSignature: Equatable, Sendable {
    var dizin: FileStamp?
    var sinifYolu: String?
    var sinif: FileStamp?
    var olay: FileStamp?
    var kunyeler: [String: FileStamp]
    var gonderilen: [String: Int]
    var gun: String
}

struct CachedKunye: Sendable {
    var damga: FileStamp
    var kunye: Kunye
}

struct StoreCache: Sendable {
    var imza: StoreSignature?
    var dizinDamgasi: FileStamp?
    var dizinOgeler: [Oge] = []
    var dizinUretim: String?
    var kunyeler: [String: CachedKunye] = [:]
}

struct StoreBuild: Sendable {
    var ogeler: [Oge]
    var siniflar: Siniflar
    var bekleyen: Int
}

struct SyncResult: Sendable {
    var gonderilen: [String: Int]
    var bekleyen: Int
    var hata: String?
    var dizin: Dizin?
    var dizinDamgasi: FileStamp?
}

struct WidgetContent: Equatable {
    var items: [ItemSnapshot]
    var sonBaslik: String?
    var sonAlan: String?
    var sonRenk: String?
    var sonZaman: Date?
    var bugun: Int
}

/// Runs the first rebuild on a background thread and hands it over once.
final class PreloadBox: @unchecked Sendable {
    private let lock = NSLock()
    private var work: DispatchWorkItem?
    private var cache = StoreCache()
    private var built: StoreBuild?

    func start() {
        lock.lock(); defer { lock.unlock() }
        guard work == nil else { return }
        let w = DispatchWorkItem { [self] in
            var c = StoreCache()
            let b = TelefonDeposu.build(.standard, gonderilen: TelefonDeposu.kayitliGonderilen, cache: &c)
            lock.lock(); cache = c; built = b; lock.unlock()
        }
        work = w
        // low priority so a recording started from the lock screen is not slowed; take() raises it while it waits
        DispatchQueue.global(qos: .utility).async(execute: w)
    }

    /// nil when preload() was never called; otherwise waits for the read to finish.
    func take() -> (StoreCache, StoreBuild?)? {
        lock.lock(); let w = work; lock.unlock()
        guard let w else { return nil }
        w.wait()
        lock.lock(); defer { lock.unlock() }
        return (cache, built)
    }
}

extension JSONEncoder {
    static let guzel: JSONEncoder = {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]; return e
    }()
}

extension Data {
    /// Kalıcı imza (FNV-1a); hashValue her açılışta değişir.
    var imza: Int {
        var h: UInt64 = 0xcbf29ce484222325
        for b in self { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return Int(truncatingIfNeeded: h >> 1)
    }
}
