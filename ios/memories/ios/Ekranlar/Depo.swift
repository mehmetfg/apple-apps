// Memories deposu: yerel paket önbelleği + olay günlüğü + kayıtlar + vault eşitlemesi + widget anlık görüntüsü.
// Yerel kayıt her zaman önce yazılır; vault erişilemese de hiçbir şey kaybolmaz, sonraki eşitlemede gider.
// Paketin sesi uygulamanın kendi alanına kopyalanır: yolda internet olmadan da çalar.
import Foundation
import PDMBus
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
    /// One store for the whole process. The window, the background refresh and the widget's recording intent all use
    /// it: on a background launch there is no window, so nothing that lives only in a view can be relied on.
    static let shared = Depo()

    // Every value below feeds the derived cache (guncel, listenedDays, hazirlik …): a change drops it.
    @Published private(set) var paketler: [Paket] = [] { didSet { derivedCache = nil } }
    @Published var secilenGun: Int? { didSet { derivedCache = nil } }
    @Published private(set) var cozumler: [Int: Cozum] = [:] { didSet { derivedCache = nil } }
    @Published private(set) var olaylar: [Olay] = [] { didSet { derivedCache = nil } }
    /// False until the local cache has been read (off the main thread, right after launch). Nothing is written
    /// to the widget or to the vault before that.
    @Published private(set) var loaded = false
    @Published private(set) var kayitlar: [KayitBilgisi] = []
    @Published private(set) var sonEsitleme: Date?
    @Published private(set) var esitleniyor = false
    @Published private(set) var inenSes: Set<Int> = []
    @Published var bilgi: String?

    @AppStorage("memories.hiz") var hiz: Double = 1.0
    @AppStorage("memories.haptik") var haptik = true
    @AppStorage(ScreenAwake.settingKey) var keepScreenOn = true

    let kasa = Kasa()

    // Yerel yerler (App Group: widget da görür)
    var yerel: URL { Paylasim.kapsayici }
    private var paketKlasoru: URL { yerel.appendingPathComponent("paket", isDirectory: true) }
    private var benimGunluk: URL { yerel.appendingPathComponent("ilerleme/\(Cihaz.ad).jsonl") }
    private var digerKlasor: URL { yerel.appendingPathComponent("diger", isDirectory: true) }
    var kayitKlasoru: URL { yerel.appendingPathComponent("kayit", isDirectory: true) }
    private var kayitDefteri: URL { yerel.appendingPathComponent("kayitlar.json") }

    private var esitlemeGorevi: Task<Void, Never>?
    static let sentRebuildsKey = "memories.kurma.gonderilen"
    static let tutulan = 16    // yerelde tutulan son paket: tampon (14 açık gün) + 2 geçmiş (kayıtlar ayrı, hep kalır)

    private var loadTask: Task<Void, Never>?

    // MARK: PDM bus (the shared pool of the owner's apps)

    /// One bus for the app. Events wait in the shared App Group and go to `<vault>/_bus` at the next sync.
    let bus = PDMBus(app: "memories", vaultRoot: { Kasa.selectedFolder() })
    /// Words that are known or dropped somewhere in the network (lowercased). Display only.
    @Published private(set) var closedWords: Set<String> = []

    /// Sends waiting events, refreshes the cached network state, then the list of closed words.
    func syncBus(opened: Bool = false) async {
        if opened { bus.emitOpenedToday() }
        await bus.sync()
        await refreshClosedWords()
    }

    private func refreshClosedWords() async {
        let closed = await Task.detached(priority: .utility) { Set(PDMBus.cachedWords()?.closed ?? []) }.value
        if closed != closedWords { closedWords = closed }
    }

    private var playing = false
    private var playingPackage: Paket?
    /// The player started or stopped (Oynatici).
    func playbackChanged(playing: Bool, package: Paket?) {
        self.playing = playing
        playingPackage = package
        publishLive()
    }

    /// What this app shows now, for the other apps on the phone: the open day (the playing one while audio plays).
    /// The bus writes the file only when the content changes.
    private func publishLive() {
        guard loaded, let p = (playing ? playingPackage : nil) ?? guncel else { return }
        bus.publishLive(PDMLive(app: bus.app, kind: "day", id: p.klasorAdi, title: "Gün \(p.gun)",
                                progress: Double(hazirlik(p.gun).adim) / 3, active: playing, link: "memories://dinle"))
    }

    private init() {
        let paths = localPaths
        loadTask = Task { [weak self] in
            let state = await Task.detached(priority: .userInitiated) { Depo.readLocal(paths, recordings: true) }.value
            guard let self else { return }
            self.apply(state)
            self.loaded = true
            self.widgetYaz()
            await self.refreshClosedWords()
        }
    }

    /// Returns once the local cache is in memory (at once, after the first load).
    func whenLoaded() async { await loadTask?.value }

    // MARK: Derived values (cached; rebuilt after the event log, the packages or the selection change)

    private struct Derived {
        var listened = Set<Int>(), written = Set<Int>(), skipped = Set<Int>(), readyMarked = Set<Int>()
        var readiness: [Int: Hazirlik] = [:]
        var current: Paket??                // nil: not worked out yet
    }
    private var derivedCache: Derived?

    /// One pass over the event log instead of one per question asked of it.
    private func derived() -> Derived {
        if let d = derivedCache { return d }
        var d = Derived()
        for o in olaylar {
            switch o.tur {
            case .dinledi: d.listened.insert(o.gun)
            case .bitti: d.written.insert(o.gun)
            case .atladi: d.skipped.insert(o.gun)
            case .hazirim: d.readyMarked.insert(o.gun)
            default: break
            }
        }
        for c in cozumler.values where c.yazim != nil { d.written.insert(c.gun) }
        derivedCache = d
        return d
    }

    // MARK: Okunan durum

    /// Çantadaki paket: seçtiğin gün; seçmediysen ilerlemenin bir sonraki günü. İlerleme = dinlenen, Mac'te yazılan
    /// ya da geçilen en ileri gün; ondan sonraki ilk gün açılır. Geride kalmış eski bir güne geri atılmaz
    /// (2026-10-16, kullanıcı isteği: "dinlenmiş olandan sonrakine geç, geriye doğru atma"). Hepsi bittiyse en yeni gün.
    var guncel: Paket? {
        let d = derived()
        if let c = d.current { return c }
        let p = currentPackage(d)
        derivedCache?.current = .some(p)
        return p
    }
    private func currentPackage(_ d: Derived) -> Paket? {
        if let s = secilenGun, let p = paketler.first(where: { $0.gun == s }) { return p }
        let done = d.written.union(d.skipped).union(d.listened)
        let reached = paketler.map(\.gun).filter { done.contains($0) }.max() ?? Int.min
        return paketler.first { $0.gun > reached } ?? paketler.last
    }
    /// Telefonda en az bir kez tam dinlenmiş günler.
    var listenedDays: Set<Int> { derived().listened }

    /// Günler arasında bir adım: ‹ önceki · › sonraki (yerelde tutulan paketler arasında).
    func neighbor(of gun: Int, _ step: Int) -> Paket? {
        guard let i = paketler.firstIndex(where: { $0.gun == gun }) else { return nil }
        let j = i + step
        return paketler.indices.contains(j) ? paketler[j] : nil
    }
    /// Mac'te yazılmış günler: Tezgâh'ın "bitti" olayı ya da yazım sonucu taşıyan çözüm.
    var yazilanGunler: Set<Int> { derived().written }
    /// «Yaptım, geç» denen günler (telefonda ya da Mac'te).
    var atlananGunler: Set<Int> { derived().skipped }

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
    func hazirlik(_ gun: Int) -> Hazirlik {
        if let h = derived().readiness[gun] { return h }
        let h = Hazirlik.kur(olaylar, gun: gun)
        derivedCache?.readiness[gun] = h
        return h
    }
    func sesURL(_ p: Paket) -> URL? {
        let u = paketKlasoru.appendingPathComponent(p.klasorAdi).appendingPathComponent("ses.m4a")
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }
    func kayitURL(_ k: KayitBilgisi) -> URL { kayitKlasoru.appendingPathComponent(k.ad) }
    func kayitlar(gun: Int) -> [KayitBilgisi] { kayitlar.filter { $0.gun == gun }.sorted { $0.zaman > $1.zaman } }

    // MARK: Yerel yükleme

    /// What the local cache holds, read and decoded away from the main thread.
    struct LocalState: Sendable {
        var paketler: [Paket] = []
        var cozumler: [Int: Cozum] = [:]
        var olaylar: [Olay] = []
        var kayitlar: [KayitBilgisi]?       // nil: not read (the list in memory is the truth after launch)
    }
    struct LocalPaths: Sendable { var packages: URL, myLog: URL, otherLogs: URL, recordingList: URL }
    private var localPaths: LocalPaths {
        LocalPaths(packages: paketKlasoru, myLog: benimGunluk, otherLogs: digerKlasor, recordingList: kayitDefteri)
    }

    nonisolated static func readLocal(_ at: LocalPaths, recordings: Bool) -> LocalState {
        let fm = FileManager.default
        try? fm.createDirectory(at: at.packages, withIntermediateDirectories: true)
        var s = LocalState()
        for ad in (try? fm.contentsOfDirectory(atPath: at.packages.path)) ?? [] where ad.hasPrefix("gun-") {
            let k = at.packages.appendingPathComponent(ad)
            if let v = try? Data(contentsOf: k.appendingPathComponent("paket.json")),
               let x = try? JSONDecoder().decode(Paket.self, from: v) { s.paketler.append(x) }
            if let v = try? Data(contentsOf: k.appendingPathComponent("cozum.json")),
               let x = try? JSONDecoder().decode(Cozum.self, from: v) { s.cozumler[x.gun] = x }
        }
        s.paketler.sort { $0.gun < $1.gun }
        var hepsi = Gunluk.oku(at.myLog)
        for ad in ((try? fm.contentsOfDirectory(atPath: at.otherLogs.path)) ?? []).sorted() where ad.hasSuffix(".jsonl") {
            hepsi += Gunluk.oku(at.otherLogs.appendingPathComponent(ad))
        }
        s.olaylar = Gunluk.tekille(hepsi)
        if recordings {
            s.kayitlar = []
            if let v = try? Data(contentsOf: at.recordingList) {
                let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
                s.kayitlar = (try? d.decode([KayitBilgisi].self, from: v)) ?? []
            }
        }
        return s
    }

    /// Counts events appended in this process: a reload that started before an append must not drop that event.
    private var eventAppends = 0

    /// Takes a freshly read state. Only what differs is assigned, so an unchanged reload redraws nothing.
    /// - Parameter appendsAtStart: `eventAppends` when the read began (nil: read on the main thread, nothing can be missing).
    private func apply(_ s: LocalState, appendsAtStart: Int? = nil) {
        if paketler != s.paketler { paketler = s.paketler }
        if cozumler != s.cozumler { cozumler = s.cozumler }
        var events = s.olaylar
        if let mark = appendsAtStart, mark != eventAppends {
            // appended while the files were being read: on disk, but perhaps not in `s`
            let known = Set(events.map(\.id))
            events += olaylar.filter { $0.cihaz == Cihaz.ad && !known.contains($0.id) }
        }
        if olaylar != events { olaylar = events }
        if let k = s.kayitlar, kayitlar != k { kayitlar = k }
    }

    private func yerelYukle() { apply(Depo.readLocal(localPaths, recordings: true)) }

    private func kayitDefteriniYaz() {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        if let v = try? e.encode(kayitlar) { try? v.write(to: kayitDefteri, options: .atomic) }
    }

    // MARK: Olaylar

    func ekle(_ o: Olay) {
        Gunluk.ekle(o, benimGunluk)         // on disk at once; everything after this can wait a moment
        eventAppends += 1
        olaylar.append(o)
        if o.tur != .hazirim, let p = paketler.first(where: { $0.gun == o.gun }) {
            let h = hazirlik(p.gun)
            if h.dinleme > 0 && h.okuma && !derived().readyMarked.contains(p.gun) {
                var hz = Olay(gun: p.gun, surum: p.surum, tur: .hazirim); hz.rol = "otomatik"
                Gunluk.ekle(hz, benimGunluk); eventAppends += 1; olaylar.append(hz)
                bilgi = "Hazırsın. Yarın Tezgâh'ta yazarken bu metin tanıdık gelecek."
            }
        }
        scheduleSideEffects()
        esitle(gecikme: 3)
    }

    /// The widget snapshot and the notification plan follow an event a moment later, once for a burst of events,
    /// and only if they would come out different (a `takildi` or `listened` event changes neither).
    private var sideEffects: Task<Void, Never>?
    private func scheduleSideEffects() {
        guard sideEffects == nil else { return }        // the pending run covers this event too
        sideEffects = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self else { return }
            self.sideEffects = nil
            self.writeWidget(onlyIfChanged: true)
            await Bildirim.planla(self, onlyIfChanged: true)
        }
    }

    func dinledi(_ p: Paket, oran: Double, sure: Double) {
        var o = Olay(gun: p.gun, surum: p.surum, tur: .dinledi)
        o.oran = (oran * 100).rounded() / 100; o.sure = sure.rounded()
        if secilenGun == p.gun { secilenGun = nil }
        ekle(o)
        let n = hazirlik(p.gun).dinleme
        bilgi = n == 1 ? "Bir kez dinledin." : "\(n). dinleme tamam."
    }

    /// One listening stretch (also partial). Counted on the Mac as listening time; does not change readiness.
    func listened(_ p: Paket, seconds: Double, ratio: Double, sentences: [Int]) {
        var o = Olay(gun: p.gun, surum: p.surum, tur: .listened)
        o.sure = seconds.rounded(); o.oran = (ratio * 1000).rounded() / 1000
        o.sentences = sentences.isEmpty ? nil : sentences
        ekle(o)
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

    func widgetYaz() { writeWidget(onlyIfChanged: false) }

    /// The last snapshot written, without its timestamp.
    private var widgetSignature: Data?
    private func writeWidget(onlyIfChanged: Bool) {
        guard loaded else { return }        // never an empty snapshot over a good one
        publishLive()                       // the same moments the open day or its steps can change
        let a = anlik()
        var plain = a
        plain.guncel = Date(timeIntervalSince1970: 0)
        let signature = try? JSONEncoder().encode(plain)
        if onlyIfChanged, signature != nil, signature == widgetSignature { return }
        widgetSignature = signature
        Paylasim.yaz(a)
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
            a.sentences = p.cumleler.compactMap { c in
                guard let en = c.en, !en.isEmpty else { return nil }
                let z = p.cumleZamani(c.i)
                return .init(i: c.i, en: en, tr: c.tr, start: z?.baslangic, end: z?.bitis)
            }
            a.todayWords = Depo.newWords(p)
            if let y = neighbor(of: p.gun, -1) {
                a.yesterdayDay = y.gun
                a.yesterdayWords = Depo.newWords(y)
            }
        }
        if let c = sonCozum {
            a.dunGun = c.gun
            if let e = c.duzeltme, let d = e.dogrusu { a.dunEn = d; a.dunTr = e.tr }
            else if let e = c.en_iyi { a.dunEn = e.en; a.dunTr = e.tr }
            if let r = c.yol_haritasi?.first { a.rota = "\(r.tur) — \(r.not ?? "")" }
        }
        return a
    }

    /// The package's new words (the echo words are older days' words); if a package has no "yeni", all of them.
    static func newWords(_ p: Paket) -> [WidgetAnlik.WidgetWord] {
        let all = p.sozluk ?? []
        let fresh = all.filter { $0.tur == "yeni" }
        return (fresh.isEmpty ? all : fresh).prefix(6).map { .init(w: $0.w, tr: $0.tr) }
    }

    // MARK: Eşitleme

    func esitle(gecikme: Double = 0) {
        esitlemeGorevi?.cancel()            // only the wait: a sync that has started is never cut short by a newer request
        esitlemeGorevi = Task { [weak self] in
            if gecikme > 0 { try? await Task.sleep(for: .seconds(gecikme)) }
            guard let self, !Task.isCancelled else { return }
            Task { await self.esitleSimdi(localChange: true) }
        }
    }

    struct Gelen: Sendable {
        var paketler: [Int: Data] = [:]
        var cozumler: [Int: Data] = [:]
        var digerler: [String: Data] = [:]
        var inenSes: [Int] = []
        var vaultKayitlari: [Int: [String: Data?]] = [:]   // gün → ad → yan dosya (json)
        var gonderilen: [String] = []
        var sentRebuilds: [String] = []
    }

    typealias SyncResult = (yeniPaket: Int?, yeniCozum: Int?)
    private var joiners: [CheckedContinuation<SyncResult, Never>] = []       // wait for the sync that is running
    private var followers: [CheckedContinuation<SyncResult, Never>] = []     // wait for one more run after it

    /// One sync at a time. A request that arrives while one runs is not dropped:
    ///   · `localChange` (a new event, recording or built sentence may have missed the running sync's snapshot):
    ///     one more run follows the current one, and the caller gets that run's result;
    ///   · otherwise the caller waits for the running sync and gets its result.
    /// Cancelling the task that runs the sync stops the vault work (background refresh, when its time is up).
    /// - Returns: yeni gelen paket ya da çözüm varsa (gün) — arka plan bildirimi için.
    @discardableResult
    func esitleSimdi(localChange: Bool = false) async -> SyncResult {
        await whenLoaded()
        guard kasa.bagli else { return (nil, nil) }
        if esitleniyor {
            return await withCheckedContinuation { c in
                if localChange { followers.append(c) } else { joiners.append(c) }
            }
        }
        esitleniyor = true
        var result = await syncOnce()
        while true {
            let waiting = joiners
            joiners = []
            waiting.forEach { $0.resume(returning: result) }
            guard !followers.isEmpty else { break }
            let next = followers
            followers = []
            if Task.isCancelled {
                // This task may not go on (background time is over); a fresh one does the follow-up run.
                esitleniyor = false
                Task {
                    let r = await self.esitleSimdi(localChange: true)
                    next.forEach { $0.resume(returning: r) }
                }
                return result
            }
            let again = await syncOnce()
            next.forEach { $0.resume(returning: again) }
            result = (again.yeniPaket ?? result.yeniPaket, again.yeniCozum ?? result.yeniCozum)
        }
        esitleniyor = false
        return result
    }

    private func syncOnce() async -> SyncResult {
        let ben = Cihaz.ad
        let benimOlaylar = olaylar.filter { $0.cihaz == ben }
        let benimYerel = benimGunluk
        let yerelPaket = paketKlasoru
        let yerelSurum = Dictionary(paketler.map { ($0.gun, $0.surum ?? "") }, uniquingKeysWith: { a, _ in a })
        let yerelSesVar = Set(paketler.filter { sesURL($0) != nil }.map(\.gun))
        // A stale iCloud must not undo a package in the long-text form that reached this phone by cable
        let yerelUzun = Set(paketler.filter { $0.dinleme != nil }.map(\.gun))
        let gonderilecek = kayitlar.filter { $0.cihaz == ben && !$0.vaultta && $0.yerelde }
        let kayitYerel = kayitKlasoru
        let tutulan = Depo.tutulan
        let bitmisGunler = yazilanGunler.union(atlananGunler)
        let rebuildFolder = RebuildState.folder
        let sentRebuilds = Set(UserDefaults.standard.stringArray(forKey: Depo.sentRebuildsKey) ?? [])

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
            try Task.checkCancellation()
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
                try Task.checkCancellation()
                let k = pk.appendingPathComponent(Paket.klasor(gun))
                let pj = k.appendingPathComponent("paket.json")
                guard Kasa.indir(pj), let v = Kasa.koordineliOku(pj),
                      let p = try? JSONDecoder().decode(Paket.self, from: v) else { continue }
                let eskiBicim = p.dinleme == nil && yerelUzun.contains(gun)
                if !eskiBicim { s.paketler[gun] = v }
                let cj = k.appendingPathComponent("cozum.json")
                let yj = k.appendingPathComponent("yazim.json")     // Mac'te yazınca aynı gün gelir
                if fm.fileExists(atPath: cj.path) || fm.fileExists(atPath: k.appendingPathComponent(".cozum.json.icloud").path) {
                    if Kasa.indir(cj), let c = Kasa.koordineliOku(cj) { s.cozumler[gun] = c }
                } else if fm.fileExists(atPath: yj.path) || fm.fileExists(atPath: k.appendingPathComponent(".yazim.json.icloud").path) {
                    if Kasa.indir(yj), let c = Kasa.koordineliOku(yj) { s.cozumler[gun] = c }
                }
                // Ses: yerelde yoksa ya da paket yeniden üretildiyse (sürüm değişti)
                if p.ses != nil, !eskiBicim, !bitmisGunler.contains(gun), !yerelSesVar.contains(gun) || yerelSurum[gun] != (p.surum ?? "") {
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
                try Task.checkCancellation()
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
            // 5 · Sentences built from the widget (kurma/): m4a + json, for later evaluation
            for ad in (try? fm.contentsOfDirectory(atPath: rebuildFolder.path)) ?? [] where ad.hasSuffix(".m4a") && !sentRebuilds.contains(ad) {
                let side = ad.replacingOccurrences(of: ".m4a", with: ".json")
                guard let day = Int(ad.prefix(3)), let v = try? Data(contentsOf: rebuildFolder.appendingPathComponent(ad)),
                      let j = try? Data(contentsOf: rebuildFolder.appendingPathComponent(side)) else { continue }   // json not written yet
                let target = pk.appendingPathComponent(Paket.klasor(day)).appendingPathComponent("kurma", isDirectory: true)
                do {
                    try Kasa.koordineliYaz(v, target.appendingPathComponent(ad))
                    try Kasa.koordineliYaz(j, target.appendingPathComponent(side))
                    s.sentRebuilds.append(ad)
                } catch { continue }
            }
            return s
        }
        guard let g else { return (nil, nil) }
        if !g.sentRebuilds.isEmpty {
            UserDefaults.standard.set(Array(sentRebuilds.union(g.sentRebuilds)), forKey: Depo.sentRebuildsKey)
        }

        // Yerel önbelleğe al — off the main thread: write what changed, then read the cache back
        let fm = FileManager.default
        let eskiPaket = Set(paketler.map(\.gun)), eskiCozum = Set(cozumler.keys)
        let paths = localPaths
        let appendsAtStart = eventAppends
        let fresh: LocalState = await Task.detached(priority: .utility) {
            let fm = FileManager.default
            func write(_ v: Data, _ u: URL) { if (try? Data(contentsOf: u)) != v { try? v.write(to: u, options: .atomic) } }
            try? fm.createDirectory(at: paths.otherLogs, withIntermediateDirectories: true)
            for (ad, v) in g.digerler { write(v, paths.otherLogs.appendingPathComponent(ad)) }
            for (gun, v) in g.paketler {
                let k = paths.packages.appendingPathComponent(Paket.klasor(gun))
                try? fm.createDirectory(at: k, withIntermediateDirectories: true)
                write(v, k.appendingPathComponent("paket.json"))
            }
            for (gun, v) in g.cozumler {
                write(v, paths.packages.appendingPathComponent(Paket.klasor(gun)).appendingPathComponent("cozum.json"))
            }
            // Eski paketleri yerelden at (kayıtlar ayrı klasörde, kalır)
            if let enKucuk = g.paketler.keys.min() {
                for ad in (try? fm.contentsOfDirectory(atPath: paths.packages.path)) ?? [] {
                    if let n = Int(ad.dropFirst(4)), n < enKucuk { try? fm.removeItem(at: paths.packages.appendingPathComponent(ad)) }
                }
            }
            return Depo.readLocal(paths, recordings: false)
        }.value
        // Kayıt defteri: gönderilenleri işaretle, Mac'in kayıtlarını ekle
        let oncekiKayitlar = kayitlar
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
        if kayitlar != oncekiKayitlar { kayitDefteriniYaz() }
        apply(fresh, appendsAtStart: appendsAtStart)
        sonEsitleme = Date()
        let yeniPaket = Set(paketler.map(\.gun)).subtracting(eskiPaket).max()
        let yeniCozum = Set(cozumler.keys).subtracting(eskiCozum).max()
        if let n = yeniPaket, !eskiPaket.isEmpty { bilgi = "Gün \(n) paketi geldi." }
        widgetYaz()
        await Bildirim.planla(self)
        return (yeniPaket, yeniCozum)
    }
}
