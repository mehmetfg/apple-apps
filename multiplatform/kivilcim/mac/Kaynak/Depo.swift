// Mac tarafının deposu: vault'taki Kıvılcım klasörünü okur, düzeltmeleri olay/mac.jsonl'e yazar,
// işleme hattını (isle.py, yerel Whisper) arka planda çalıştırır ve klasörü izler (telefondan gelen kayıtlar).
import Foundation
import AppKit

@MainActor
final class Depo: ObservableObject {
    static let shared = Depo()

    @Published private(set) var ogeler: [Oge] = []
    @Published private(set) var siniflar = Siniflar.varsayilan
    @Published private(set) var links = Links.empty
    private var linksDate: Date?
    @Published private(set) var tatbik = TatbikState.empty
    private var tatbikDate: Date?
    @Published private(set) var feed = FeedIssue.empty
    private var feedDate: Date?
    @Published private(set) var isleniyor = false
    @Published private(set) var durumMetni = ""
    @Published var secili: String?
    /// Multi-selection in the archive list (⌘/⇧ click, ⌘A); with 2+ the detail shows the bulk panel.
    @Published var coklu: Set<String> = []
    @Published var hata: String?
    /// A Tatbik item to show (set from a record's detail; the window switches to Tatbik).
    @Published var openTatbik: String?

    let vault = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Mobile Documents/iCloud~md~obsidian/Documents/Personel Data Management")
    /// KIVILCIM_KOK ile sınama klasörü (gerçek veriye dokunmadan arayüz denemesi)
    var kok: URL {
        if let s = ProcessInfo.processInfo.environment["KIVILCIM_KOK"] { return URL(fileURLWithPath: s) }
        return vault.appendingPathComponent(veriKlasoruYolu)
    }
    var arac: URL { vault.appendingPathComponent("_araçlar/kivilcim") }
    /// The first Python environment that actually has mlx_whisper. The yanki env lost it on 2026-10-30 and every
    /// recording failed with "No module named 'mlx_whisper'" until 2026-11-02; ema has it.
    let python: URL = {
        let ev = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/share")
        for ad in ["ema", "yanki", "insan-ses"] {
            let v = ev.appendingPathComponent("\(ad)/.venv")
            let lib = v.appendingPathComponent("lib")
            let surumler = (try? FileManager.default.contentsOfDirectory(atPath: lib.path)) ?? []
            if surumler.contains(where: { FileManager.default.fileExists(atPath: lib.appendingPathComponent("\($0)/site-packages/mlx_whisper").path) }) {
                return v.appendingPathComponent("bin/python")
            }
        }
        return ev.appendingPathComponent("ema/.venv/bin/python")
    }()
    let yerelKuyruk = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Kivilcim/kuyruk")
    let kayitDosyasi = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs/Kivilcim.log")

    private var izleyici: Timer?
    private var sonTelefon = Date.distantPast       // isle.py'nin telefondan doğrudan alma bakışı (10 dk'da bir)
    private var tekrarIste = false
    private var tekrarHizli = true
    private var dizinTarihi: Date?
    private var sonClaude = Date.distantPast
    private var sonIsleme = Date.distantPast

    private init() {
        try? FileManager.default.createDirectory(at: kok.appendingPathComponent("ses"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: yerelKuyruk, withIntermediateDirectories: true)
        yukle()
    }

    // MARK: Okuma

    func yukle() {
        let s = Siniflar.yukle(kok.appendingPathComponent("siniflar.json"))
        let dizinU = kok.appendingPathComponent("dizin.json")
        dizinTarihi = (try? dizinU.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        var liste = (try? JSONDecoder().decode(Dizin.self, from: Data(contentsOf: dizinU)))?.ogeler ?? []
        // henüz işlenmemiş kayıtlar (telefondan yeni inmiş ya da az önce kaydedilmiş)
        let bilinen = Set(liste.map(\.id))
        for (k, m4a) in sesDosyalari() where !bilinen.contains(k.id) {
            var o = Oge(id: k.id, tarih: k.zaman, cihaz: k.cihaz, sure: k.sure, kalite: k.kalite,
                        boyut: (try? m4a.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0,
                        ses: String(m4a.path.dropFirst(kok.path.count + 1)), metin: k.onMetin ?? "",
                        durum: "bekliyor")
            o.kind = k.kind ?? "spark"
            if let m = k.onMetin, !m.isEmpty, !o.isJournal {
                o.baslik = Kural.baslik(m, s); o.alan = Kural.alan(m, s); o.amac = Kural.amac(m, s)
            }
            liste.append(o)
        }
        for k in kuyruktakiler() where !liste.contains(where: { $0.id == k.id }) {
            liste.append(Oge(id: k.id, tarih: k.zaman, cihaz: k.cihaz, sure: k.sure, kalite: k.kalite, boyut: 0, ses: "", durum: "yerel"))
        }
        // kendi düzeltmelerimiz isle.py'den önce de görünsün
        if let v = try? Data(contentsOf: kok.appendingPathComponent("olay/mac.jsonl")) { Olay.uygula(v, &liste) }
        siniflar = s
        ogeler = liste.sorted { $0.tarih > $1.tarih }
        loadLinks()
        loadTatbik()
        loadFeed()
    }

    /// Feed/feed.json (feed.py). A broken file keeps the last state.
    func loadFeed() {
        let u = kok.appendingPathComponent("Feed/feed.json")
        let t = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard t != feedDate || feed.items.isEmpty else { return }
        feedDate = t
        if let v = try? Data(contentsOf: u), let s = try? JSONDecoder().decode(FeedIssue.self, from: v) { feed = s }
    }

    /// A touch on a feed item: appended to Feed/olay/mac.jsonl, shown at once; the next pass makes the Dikkat mark.
    func feedTouch(_ item: String, _ status: String) {
        let u = kok.appendingPathComponent("Feed/olay/mac.jsonl")
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        let v = Olay.satir(hedef: item, tur: "status", deger: status, cihaz: "mac")
        if let h = try? FileHandle(forWritingTo: u) { h.seekToEndOfFile(); h.write(v); try? h.close() }
        else { try? v.write(to: u, options: .atomic) }
        if let i = feed.items.firstIndex(where: { $0.id == item }) { feed.items[i].status = status }
        isle(hizli: true)
    }

    /// The Güncelle button: the next pass goes to the network whatever the hour, and fills what is missing.
    func feedRefresh() {
        let u = kok.appendingPathComponent("Feed/olay/mac.jsonl")
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        let v = Olay.satir(hedef: "feed", tur: "refresh", deger: "1", cihaz: "mac")
        if let h = try? FileHandle(forWritingTo: u) { h.seekToEndOfFile(); h.write(v); try? h.close() }
        else { try? v.write(to: u, options: .atomic) }
        isle(hizli: true)
    }

    /// Tatbik/tatbik.json (tatbik.py merges Claude's review and the user's touches). A broken file keeps the last state.
    func loadTatbik() {
        let u = kok.appendingPathComponent("Tatbik/tatbik.json")
        let t = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard t != tatbikDate || tatbik.maddeler.isEmpty else { return }
        tatbikDate = t
        if let v = try? Data(contentsOf: u), let s = try? JSONDecoder().decode(TatbikState.self, from: v) { tatbik = s }
    }

    /// A touch on an item (status or note): appended to Tatbik/olay/mac.jsonl, shown at once, merged by the next pass.
    func tatbikDuzelt(_ item: String, _ tur: String, _ deger: String) {
        let u = kok.appendingPathComponent("Tatbik/olay/mac.jsonl")
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        let v = TatbikEvent.line(item: item, kind: tur, value: deger, device: "mac")
        if let h = try? FileHandle(forWritingTo: u) { h.seekToEndOfFile(); h.write(v); try? h.close() }
        else { try? v.write(to: u, options: .atomic) }
        if let i = tatbik.maddeler.firstIndex(where: { $0.id == item }) {
            if tur == "status" { tatbik.maddeler[i].durum = deger; tatbik.maddeler[i].kaynak_durum = "elle" }
            if tur == "note" {
                tatbik.maddeler[i].notlar = (tatbik.maddeler[i].notlar ?? []) + [TatbikNote(t: Zaman.iso(Date()), text: deger, device: "mac")]
            }
        }
        isle(hizli: true)
    }

    func loadLinks() {
        let u = kok.appendingPathComponent("links.json")
        let t = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard t != linksDate || links.topics.isEmpty else { return }
        linksDate = t
        // a broken file keeps the last good state on screen
        if let v = try? Data(contentsOf: u), let l = try? JSONDecoder().decode(Links.self, from: v) { links = l }
    }

    /// Sidecars already decoded, by path, with the modification date and size they had: an unchanged file is not read again.
    private var kunyeOnbellek: [String: CachedSidecar] = [:]

    func sesDosyalari() -> [(Kunye, URL)] {
        let (r, c) = Depo.sesTara(kok, kunyeOnbellek)
        kunyeOnbellek = c
        return r
    }

    /// Walks ses/ and returns every recording with its sidecar. Safe off the main thread (the 45 s tick runs it there).
    nonisolated static func sesTara(_ kok: URL, _ onbellek: [String: CachedSidecar]) -> ([(Kunye, URL)], [String: CachedSidecar]) {
        let fm = FileManager.default
        let anahtarlar: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let e = fm.enumerator(at: kok.appendingPathComponent("ses"), includingPropertiesForKeys: anahtarlar, options: [.skipsHiddenFiles]) else { return ([], [:]) }
        var sesler: [URL] = []
        var damgalar: [String: (Date, Int)] = [:]
        for case let u as URL in e {
            if u.pathExtension == "m4a" { sesler.append(u) }
            else if u.pathExtension == "json", let v = try? u.resourceValues(forKeys: Set(anahtarlar)),
                    let t = v.contentModificationDate, let b = v.fileSize { damgalar[u.path] = (t, b) }
        }
        var r: [(Kunye, URL)] = []
        var yeni: [String: CachedSidecar] = [:]
        for u in sesler {
            let j = u.deletingPathExtension().appendingPathExtension("json")
            let d = damgalar[j.path]
            if let d, let c = onbellek[j.path], c.modified == d.0, c.size == d.1 { yeni[j.path] = c; r.append((c.kunye, u)); continue }
            if let v = try? Data(contentsOf: j), let k = try? JSONDecoder().decode(Kunye.self, from: v) {
                if let d { yeni[j.path] = CachedSidecar(modified: d.0, size: d.1, kunye: k) }
                r.append((k, u))
            }
            else { r.append((Kunye(id: u.deletingPathExtension().lastPathComponent, cihaz: "?", zaman: Zaman.iso(Date()), sure: 0, kalite: "", dil: "tr"), u)) }
        }
        return (r, yeni)
    }

    func sesURL(_ o: Oge) -> URL? {
        if !o.ses.isEmpty { return kok.appendingPathComponent(o.ses) }
        let y = yerelKuyruk.appendingPathComponent(o.id + ".m4a")
        return FileManager.default.fileExists(atPath: y.path) ? y : nil
    }

    func notURL(_ o: Oge) -> URL? {
        if !o.journal_note.isEmpty { return vault.appendingPathComponent(o.journal_note) }
        return o.not.isEmpty ? nil : kok.appendingPathComponent(o.not)
    }

    // MARK: Yeni kayıt

    /// Kaydedicinin bitirdiği dosyayı vault'a taşır. Taşınamazsa yerel kuyrukta bekler (kayıt asla kaybolmaz).
    func kayitEkle(gecici: URL, kunye: Kunye) {
        let hedefKlasor = kok.appendingPathComponent("ses/" + String(kunye.zaman.prefix(7)))
        let hedef = hedefKlasor.appendingPathComponent(kunye.id + ".m4a")
        let kunyeVeri = (try? JSONEncoder.guzel.encode(kunye)) ?? Data()
        do {
            try FileManager.default.createDirectory(at: hedefKlasor, withIntermediateDirectories: true)
            try kunyeVeri.write(to: hedef.deletingPathExtension().appendingPathExtension("json"), options: .atomic)
            try FileManager.default.moveItem(at: gecici, to: hedef)
        } catch {
            let y = yerelKuyruk.appendingPathComponent(kunye.id + ".m4a")
            try? FileManager.default.moveItem(at: gecici, to: y)
            try? kunyeVeri.write(to: y.deletingPathExtension().appendingPathExtension("json"))
            hata = "Vault'a yazılamadı, kayıt Mac'te bekliyor: \(error.localizedDescription)"
            gunluk("kuyruğa alındı \(kunye.id): \(error)")
        }
        yukle()
        isle()
    }

    private func kuyruktakiler() -> [Kunye] {
        let fm = FileManager.default
        return ((try? fm.contentsOfDirectory(at: yerelKuyruk, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(Kunye.self, from: Data(contentsOf: $0)) }
    }

    private func kuyruguBosalt() {
        for k in kuyruktakiler() {
            let m4a = yerelKuyruk.appendingPathComponent(k.id + ".m4a")
            let j = m4a.deletingPathExtension().appendingPathExtension("json")
            let hk = kok.appendingPathComponent("ses/" + String(k.zaman.prefix(7)))
            do {
                try FileManager.default.createDirectory(at: hk, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: j, to: hk.appendingPathComponent(j.lastPathComponent))
                try FileManager.default.moveItem(at: m4a, to: hk.appendingPathComponent(m4a.lastPathComponent))
                gunluk("kuyruktan vault'a: \(k.id)")
            } catch { gunluk("kuyruk hâlâ bekliyor \(k.id): \(error)") }
        }
    }

    // MARK: Düzeltme

    func duzelt(_ o: Oge, _ tur: String, _ deger: Any) {
        let u = kok.appendingPathComponent("olay/mac.jsonl")
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        let v = Olay.satir(hedef: o.id, tur: tur, deger: deger, cihaz: "mac")
        if let h = try? FileHandle(forWritingTo: u) { h.seekToEndOfFile(); h.write(v); try? h.close() }
        else { try? v.write(to: u, options: .atomic) }
        yukle()
        isle(hizli: true)
    }

    /// One correction for many records: events are written together, the pipeline runs once.
    func duzeltToplu(_ ids: [String], _ tur: String, _ deger: Any) {
        guard !ids.isEmpty else { return }
        let u = kok.appendingPathComponent("olay/mac.jsonl")
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        var v = Data()
        for id in ids { v.append(Olay.satir(hedef: id, tur: tur, deger: deger, cihaz: "mac")) }
        if let h = try? FileHandle(forWritingTo: u) { h.seekToEndOfFile(); h.write(v); try? h.close() }
        else { try? v.write(to: u, options: .atomic) }
        yukle()
        isle(hizli: true)
    }

    // MARK: İşleme hattı

    func isle(hizli: Bool = false) {
        if isleniyor { tekrarIste = true; tekrarHizli = tekrarHizli && hizli; return }
        guard FileManager.default.isExecutableFile(atPath: python.path) else {
            hata = "Whisper ortamı yok: \(python.path)"; return
        }
        isleniyor = true
        sonIsleme = Date()
        durumMetni = hizli ? "Güncelleniyor…" : "Yazıya dökülüyor…"
        let claude = !hizli && UserDefaults.standard.bool(forKey: "claudeBaslik") && Date().timeIntervalSince(sonClaude) > 1800
        if claude { sonClaude = Date() }
        var arg = [arac.appendingPathComponent("isle.py").path, "--kok", kok.path]
        if hizli { arg.append("--hizli") }
        if claude { arg.append("--claude") }
        let py = python
        // A hung child (a stuck download, devicectl, claude) used to leave `isleniyor` true for good: nothing was
        // transcribed again until the app was restarted. Past the limit the run is stopped and the state is freed.
        let sinir = hizli ? Depo.quickRunLimit : Depo.fullRunLimit
        Task.detached {
            let p = Process()
            p.executableURL = py
            p.arguments = arg
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:" + NSHomeDirectory() + "/.local/bin:/opt/homebrew/bin"
            env["PYTHONUNBUFFERED"] = "1"
            p.environment = env
            let boru = Pipe()
            p.standardOutput = boru; p.standardError = boru
            let kapi = RunGate()
            let asim = "isle.py \(Int(sinir / 60)) dk içinde bitmedi → durduruldu"
            var cikti = ""
            do {
                try p.run()
                let bekci = DispatchWorkItem {
                    kapi.markTimedOut()
                    if p.isRunning {
                        // its children first: they keep the pipe open after python is gone
                        Depo.signalChildren(of: p.processIdentifier, "TERM"); p.terminate()
                        Thread.sleep(forTimeInterval: 5)
                        if p.isRunning { Depo.signalChildren(of: p.processIdentifier, "KILL"); kill(p.processIdentifier, SIGKILL) }
                    }
                    Thread.sleep(forTimeInterval: 5)
                    // the reader below normally returns now and finishes the run; if something still holds the pipe, finish here
                    guard kapi.first() else { return }
                    Task { @MainActor in Depo.shared.islemeBitti(asim) }
                }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + sinir, execute: bekci)
                let v = boru.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                bekci.cancel()
                cikti = String(decoding: v, as: UTF8.self)
                if kapi.timedOut { cikti += "\n" + asim }
            } catch { cikti = "çalıştırılamadı: \(error)" }
            guard kapi.first() else { return }
            let sonCikti = cikti
            await MainActor.run { Depo.shared.islemeBitti(sonCikti) }
        }
    }

    static let quickRunLimit: TimeInterval = 20 * 60
    static let fullRunLimit: TimeInterval = 2 * 3600

    /// The end of one isle.py run (called once per run).
    private func islemeBitti(_ cikti: String) {
        let son = cikti.split(separator: "\n").last(where: { $0.hasPrefix("tamam") }).map(String.init) ?? ""
        let temiz = cikti.split(separator: "\n").filter { !$0.contains("Fetching") && !$0.contains("Warning") }.joined(separator: "\n")
        gunluk(temiz)
        isleniyor = false
        durumMetni = son.isEmpty ? "İşleme hatası — günlüğe bak" : ""
        if son.isEmpty { hata = String(temiz.suffix(300)) } else { hata = nil }
        yukle()
        if tekrarIste {
            let h = tekrarHizli
            tekrarIste = false; tekrarHizli = true
            isle(hizli: h)
        }
    }

    nonisolated static func signalChildren(of pid: Int32, _ signal: String) {
        let k = Process()
        k.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        k.arguments = ["-\(signal)", "-P", String(pid)]
        k.standardOutput = FileHandle.nullDevice; k.standardError = FileHandle.nullDevice
        if (try? k.run()) != nil { k.waitUntilExit() }
    }

    /// Her 45 sn: yerel kuyruğu boşalt, dökülmemiş kayıt varsa işle, dizin dışarıdan değiştiyse yeniden oku; 10 dk'da bir
    /// telefonda kalmış kayıt var mı diye de bak (isle.py).
    func izle() {
        izleyici?.invalidate()
        izleyici = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { _ in
            Task { @MainActor in Depo.shared.tik() }
        }
        tik()
    }

    private var tikKosuyor = false

    private func tik() {
        kuyruguBosalt()
        guard !tikKosuyor else { return }       // the last walk is still going (slow iCloud): do not stack another
        tikKosuyor = true
        let kok = self.kok, onbellek = kunyeOnbellek
        Task {
            // the walk over ses/ (iCloud) and the file checks run off the main thread; the decisions stay here
            let d = await Task.detached(priority: .utility) { Depo.klasoruTara(kok, onbellek) }.value
            tikKosuyor = false
            kunyeOnbellek = d.onbellek
            // telefonun düzeltmeleri dizinden yeni mi?
            let olayYeni = d.olayTarihleri.contains { $0 > max(sonIsleme, dizinTarihi ?? .distantPast) }
            if d.eksik && !isleniyor { isle() }
            else if olayYeni && !isleniyor { isle(hizli: true) }
            // iCloud telefondan getirmezse: telefon eşleşikken isle.py kayıtları devicectl ile kendisi alır
            else if !isleniyor, Date().timeIntervalSince(sonTelefon) > 600 { sonTelefon = Date(); isle() }
            else if !isleniyor, tatbikInputsNewer() || feedInputsNewer() { isle(hizli: true) }
            else if d.dizinTarihi != dizinTarihi { yukle() } else { loadLinks(); loadTatbik(); loadFeed() }
            if #available(macOS 26.0, *) { await FeedTranslator.inBackground(self) }
        }
    }

    /// Claude's review or the phone's touches changed after the merged file was written: tatbik.py should run.
    private func tatbikInputsNewer() -> Bool {
        let t = kok.appendingPathComponent("Tatbik")
        func date(_ u: URL) -> Date { (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast }
        let merged = date(t.appendingPathComponent("tatbik.json"))
        var inputs = [t.appendingPathComponent("claude/tatbik.json")]
        inputs += ((try? FileManager.default.contentsOfDirectory(at: t.appendingPathComponent("olay"), includingPropertiesForKeys: nil)) ?? [])
        return inputs.contains { date($0) > merged.addingTimeInterval(1) }
    }

    /// The phone's touches on the feed arrived after the merged file was written.
    private func feedInputsNewer() -> Bool {
        let f = kok.appendingPathComponent("Feed")
        func date(_ u: URL) -> Date { (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast }
        let merged = date(f.appendingPathComponent("feed.json"))
        let logs = (try? FileManager.default.contentsOfDirectory(at: f.appendingPathComponent("olay"), includingPropertiesForKeys: nil)) ?? []
        return (logs + [f.appendingPathComponent("translations.json")]).contains {
            ($0.pathExtension == "jsonl" || $0.lastPathComponent == "translations.json") && date($0) > merged.addingTimeInterval(1)
        }
    }

    nonisolated static func klasoruTara(_ kok: URL, _ onbellek: [String: CachedSidecar]) -> FolderScan {
        let fm = FileManager.default
        let (sesler, yeni) = sesTara(kok, onbellek)
        let dokum = kok.appendingPathComponent("dokum")
        let eksik = sesler.contains { !fm.fileExists(atPath: dokum.appendingPathComponent($0.0.id + ".json").path) }
        let olay = ((try? fm.contentsOfDirectory(at: kok.appendingPathComponent("olay"), includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
        let t = (try? kok.appendingPathComponent("dizin.json").resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return FolderScan(eksik: eksik, olayTarihleri: olay, dizinTarihi: t, onbellek: yeni)
    }

    func gunluk(_ s: String) {
        guard !s.isEmpty else { return }
        let satir = "[\(Zaman.iso(Date()))] \(s)\n"
        if let h = try? FileHandle(forWritingTo: kayitDosyasi) { h.seekToEndOfFile(); h.write(Data(satir.utf8)); try? h.close() }
        else { try? Data(satir.utf8).write(to: kayitDosyasi) }
    }

    // MARK: Özet

    var toplamDakika: Int { Int(ogeler.reduce(0) { $0 + $1.sure } / 60) }
    var toplamMB: Double { Double(ogeler.reduce(0) { $0 + $1.boyut }) / 1_000_000 }
    var bekleyenSayisi: Int { ogeler.filter { !$0.islendi }.count }
}

struct CachedSidecar: Sendable {
    var modified: Date
    var size: Int
    var kunye: Kunye
}

/// What one idle tick needs to know about the data folder.
struct FolderScan: Sendable {
    var eksik: Bool
    var olayTarihleri: [Date]
    var dizinTarihi: Date?
    var onbellek: [String: CachedSidecar]
}

/// One isle.py run ends once: by the reader when the pipe closes, or by the watchdog if it never does.
final class RunGate: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private var late = false
    func first() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
    func markTimedOut() { lock.lock(); late = true; lock.unlock() }
    var timedOut: Bool { lock.lock(); defer { lock.unlock() }; return late }
}

extension JSONEncoder {
    static let guzel: JSONEncoder = {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]; return e
    }()
}
