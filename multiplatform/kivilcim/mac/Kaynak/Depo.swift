// Mac tarafının deposu: vault'taki Kıvılcım klasörünü okur, düzeltmeleri olay/mac.jsonl'e yazar,
// işleme hattını (isle.py, yerel Whisper) arka planda çalıştırır ve klasörü izler (telefondan gelen kayıtlar).
import Foundation
import AppKit

@MainActor
final class Depo: ObservableObject {
    static let shared = Depo()

    @Published private(set) var ogeler: [Oge] = []
    @Published private(set) var siniflar = Siniflar.varsayilan
    @Published private(set) var isleniyor = false
    @Published private(set) var durumMetni = ""
    @Published var secili: String?
    @Published var hata: String?

    let vault = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Mobile Documents/iCloud~md~obsidian/Documents/Personel Data Management")
    /// KIVILCIM_KOK ile sınama klasörü (gerçek veriye dokunmadan arayüz denemesi)
    var kok: URL {
        if let s = ProcessInfo.processInfo.environment["KIVILCIM_KOK"] { return URL(fileURLWithPath: s) }
        return vault.appendingPathComponent(veriKlasoruYolu)
    }
    var arac: URL { vault.appendingPathComponent("_araçlar/kivilcim") }
    let python = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/share/yanki/.venv/bin/python")
    let yerelKuyruk = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Kivilcim/kuyruk")
    let kayitDosyasi = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs/Kivilcim.log")

    private var izleyici: Timer?
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
            if let m = k.onMetin, !m.isEmpty {
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
    }

    func sesDosyalari() -> [(Kunye, URL)] {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: kok.appendingPathComponent("ses"), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        var r: [(Kunye, URL)] = []
        for case let u as URL in e where u.pathExtension == "m4a" {
            let j = u.deletingPathExtension().appendingPathExtension("json")
            if let v = try? Data(contentsOf: j), let k = try? JSONDecoder().decode(Kunye.self, from: v) { r.append((k, u)) }
            else { r.append((Kunye(id: u.deletingPathExtension().lastPathComponent, cihaz: "?", zaman: Zaman.iso(Date()), sure: 0, kalite: "", dil: "tr"), u)) }
        }
        return r
    }

    func sesURL(_ o: Oge) -> URL? {
        if !o.ses.isEmpty { return kok.appendingPathComponent(o.ses) }
        let y = yerelKuyruk.appendingPathComponent(o.id + ".m4a")
        return FileManager.default.fileExists(atPath: y.path) ? y : nil
    }

    func notURL(_ o: Oge) -> URL? { o.not.isEmpty ? nil : kok.appendingPathComponent(o.not) }

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
        let py = python, log = kayitDosyasi
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
            var cikti = ""
            do {
                try p.run()
                let v = boru.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                cikti = String(decoding: v, as: UTF8.self)
            } catch { cikti = "çalıştırılamadı: \(error)" }
            let son = cikti.split(separator: "\n").last(where: { $0.hasPrefix("tamam") }).map(String.init) ?? ""
            let temiz = cikti.split(separator: "\n").filter { !$0.contains("Fetching") && !$0.contains("Warning") }.joined(separator: "\n")
            await MainActor.run {
                Depo.shared.gunluk(temiz)
                Depo.shared.isleniyor = false
                Depo.shared.durumMetni = son.isEmpty ? "İşleme hatası — günlüğe bak" : ""
                if son.isEmpty { Depo.shared.hata = String(temiz.suffix(300)) } else { Depo.shared.hata = nil }
                Depo.shared.yukle()
                if Depo.shared.tekrarIste {
                    let h = Depo.shared.tekrarHizli
                    Depo.shared.tekrarIste = false; Depo.shared.tekrarHizli = true
                    Depo.shared.isle(hizli: h)
                }
            }
        }
    }

    /// Her 45 sn: yerel kuyruğu boşalt, dökülmemiş kayıt varsa işle, dizin dışarıdan değiştiyse yeniden oku.
    func izle() {
        izleyici?.invalidate()
        izleyici = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { _ in
            Task { @MainActor in Depo.shared.tik() }
        }
        tik()
    }

    private func tik() {
        kuyruguBosalt()
        let dokum = kok.appendingPathComponent("dokum")
        let eksik = sesDosyalari().contains { !FileManager.default.fileExists(atPath: dokum.appendingPathComponent($0.0.id + ".json").path) }
        // telefonun düzeltmeleri dizinden yeni mi?
        let olayYeni = ((try? FileManager.default.contentsOfDirectory(at: kok.appendingPathComponent("olay"), includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            .contains { $0 > max(sonIsleme, dizinTarihi ?? .distantPast) }
        if eksik && !isleniyor { isle() }
        else if olayYeni && !isleniyor { isle(hizli: true) }
        else {
            let t = (try? kok.appendingPathComponent("dizin.json").resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if t != dizinTarihi { yukle() }
        }
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

extension JSONEncoder {
    static let guzel: JSONEncoder = {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]; return e
    }()
}
