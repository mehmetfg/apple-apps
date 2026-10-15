// Telefon ↔ Mac. Memories (iPhone) ile aynı klasörü konuşur: 01 - English Learning/oncalisma/
//   ilerleme/iphone.jsonl          telefon yazar: dinledi · okudu · kaydetti · hazirim · takildi (cümle)
//   ilerleme/mac-<makine>.jsonl    bu uygulama yazar: basladi · bitti · kaydetti
//   paket/gun-NNN/kayit/           iki cihazın kendi sesiyle okumaları
//   paket/gun-NNN/yazim.json       bu uygulama bitişte yazar → telefon aynı gün "Mac'te yazdın" der
// Okuma CANLI: dosyalar birkaç saniyede bir yeniden okunur; kart oturum başında donmaz (Gün 21'de
// telefon dinlemesi sonradan geldiği için sonuçta 0 görünmüştü).
import Foundation

struct Olay: Hashable {
    var id: String
    var cihaz: String
    var t: String
    var gun: Int
    var tur: String
    var cumle: Int?
    var takilan: [String]
    var ham: [String: Any]
    static func == (a: Olay, b: Olay) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct Rota: Hashable { var tur: String; var sayi: Int; var gun: Int; var not: String }

struct Hazirlik: Equatable {
    var paket = false
    var surum: String?
    var dinleme = 0
    var okuma = false
    var kayit = 0
    var hazirim = false
    var cihazlar: [String] = []
    var takilan: [String] = []
    /// Telefonda yinelenen / geri sarılan / tek başına dinlenen / Türkçesine bakılan cümle → kaç kez
    var takildi: [Int: Int] = [:]
    var basladi: Bool { dinleme > 0 || okuma || kayit > 0 }

    /// Sonuç JSON'una giden özet (v7 alanlarıyla aynı + takılan cümleler).
    var json: [String: Any] {
        var j: [String: Any] = ["dinleme": dinleme, "okuma": okuma, "kayit": kayit, "takilan": takilan,
                                "cihazlar": cihazlar, "paket_surum": surum ?? NSNull()]
        if !takildi.isEmpty { j["takilan_cumle"] = takildi.keys.sorted().map { $0 + 1 } }
        return j
    }
}

struct VaultKayit: Hashable, Identifiable {
    var ad: String
    var cihaz: String
    var zaman: Date
    var sure: Double?
    var tanima: Double?
    var url: URL
    var id: String { ad }
    var cihazAdi: String { cihaz == "iphone" ? "iPhone" : cihaz.hasPrefix("mac") ? "Mac" : cihaz }
}

enum OnCalisma {
    static let sesUz = [".m4a", ".mp4", ".webm", ".ogg", ".wav"]
    static let ipucuNotu = [
        "artikel": "a / an / the — tekil sayılabilir isim tek başına durmaz; bilinen şeye the",
        "edat": "in / on / at — gün on, saat at, ay ve yıl in",
        "yazım": "harf harf: çift ünsüz ve sessiz harfler",
        "biçim": "fiilin biçimi: -s, -ed, -ing ve düzensiz geçmiş",
        "zaman": "yardımcı fiil ve zaman uyumu",
        "kelime": "eksik ya da başka kelime — cümlenin tamamını kur",
    ]

    // MARK: Okuma

    /// Bütün cihazların olayları — çakışma kopyaları dahil, kimlikle tekillenir; yarım satır atlanır.
    static func olaylar() -> [Olay] {
        let fm = FileManager.default
        var gorulen = Set<String>(), cikti: [Olay] = []
        for ad in ((try? fm.contentsOfDirectory(atPath: Yol.ilerleme.path)) ?? []).sorted() {
            if ad.hasPrefix("."), ad.hasSuffix(".icloud") {
                try? fm.startDownloadingUbiquitousItem(at: Yol.ilerleme.appendingPathComponent(String(ad.dropFirst().dropLast(7))))
                continue
            }
            guard ad.hasSuffix(".jsonl"), let v = try? String(contentsOf: Yol.ilerleme.appendingPathComponent(ad), encoding: .utf8) else { continue }
            for satir in v.split(separator: "\n") {
                guard let d = satir.data(using: .utf8), let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
                      let id = o["id"] as? String, let gun = o.i("gun"), !gorulen.contains(id) else { continue }
                gorulen.insert(id)
                cikti.append(Olay(id: id, cihaz: o.s("cihaz"), t: o.s("t"), gun: gun, tur: o.s("tur"), cumle: o.i("cumle"),
                                  takilan: o.l("takilan"), ham: o))
            }
        }
        return cikti
    }

    static func paketVar(_ gun: Int) -> [String: Any]? {
        let u = Yol.paketKlasoru(gun).appendingPathComponent("paket.json")
        guard let d = try? Data(contentsOf: u) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    static func kayitlar(_ gun: Int) -> [VaultKayit] {
        let kk = Yol.paketKlasoru(gun).appendingPathComponent("kayit", isDirectory: true)
        let fm = FileManager.default
        var l: [VaultKayit] = []
        for a in (try? fm.contentsOfDirectory(atPath: kk.path)) ?? [] {
            var ad = a
            if a.hasPrefix("."), a.hasSuffix(".icloud") {
                ad = String(a.dropFirst().dropLast(7))
                try? fm.startDownloadingUbiquitousItem(at: kk.appendingPathComponent(ad))
            }
            guard sesUz.contains(where: { ad.hasSuffix($0) }) else { continue }
            let u = kk.appendingPathComponent(ad)
            let yan = kk.appendingPathComponent((ad as NSString).deletingPathExtension + ".json")
            let y = (try? Data(contentsOf: yan)).flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } ?? [:]
            let parca = ad.split(separator: "-")
            let cihaz = y["cihaz"] as? String ?? (parca.count >= 3 ? (parca[1] == "mac" ? "mac" : String(parca[1])) : "?")
            let zaman = (y["zaman"] as? String).flatMap { Gun.isoSaniye.date(from: $0) ?? Gun.iso.date(from: $0) }
                ?? ((try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date())
            l.append(VaultKayit(ad: ad, cihaz: cihaz, zaman: zaman, sure: y.d("sure"), tanima: y.d("tanima"), url: u))
        }
        return l.sorted { $0.zaman > $1.zaman }
    }

    /// Bir günün hazırlık özeti — oncalisma.py durum() ile aynı sayım, artı telefonda takılan cümleler.
    static func durum(_ gun: Int, olaylar hepsi: [Olay]) -> Hazirlik {
        var h = Hazirlik()
        let ol = hepsi.filter { $0.gun == gun }
        if let p = paketVar(gun) { h.paket = true; h.surum = p["surum"] as? String }
        for o in ol {
            switch o.tur {
            case "dinledi": h.dinleme += 1
            case "okudu": h.okuma = true
            case "hazirim": h.hazirim = true
            case "takildi": if let c = o.cumle { h.takildi[c, default: 0] += 1 }
            default: break
            }
            for w in o.takilan where !h.takilan.contains(w) { h.takilan.append(w) }
        }
        h.takilan = Array(h.takilan.prefix(8))
        h.kayit = kayitlar(gun).count
        h.cihazlar = Array(Set(ol.map(\.cihaz).filter { !$0.isEmpty })).sorted()
        return h
    }

    /// Son 5 sonucun hata türlerinden en sık üçü (en az 3 kez) — oncalisma.py yol_haritasi().
    static func yolHaritasi(gun: Int) -> [Rota] {
        let fm = FileManager.default
        let re = try! NSRegularExpression(pattern: "-gun(\\d+)-tezgah\\.json$")
        var adlar: [(String, Int)] = []
        for a in (try? fm.contentsOfDirectory(atPath: Yol.sonuclar.path)) ?? [] {
            let ns = a as NSString
            guard let m = re.firstMatch(in: a, range: NSRange(location: 0, length: ns.length)),
                  let n = Int(ns.substring(with: m.range(at: 1))), n <= gun else { continue }
            adlar.append((a, n))
        }
        adlar.sort { $0.0 < $1.0 }
        var toplam: [String: Int] = [:], gunler: [String: Int] = [:], sira: [String] = []
        for (a, _) in adlar.suffix(5) {
            guard let d = try? Data(contentsOf: Yol.sonuclar.appendingPathComponent(a)),
                  let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
                  let h = o["hata_turleri"] as? [String: Any] else { continue }
            for (k, v) in h {
                guard let n = (v as? NSNumber)?.intValue else { continue }
                if toplam[k] == nil { sira.append(k) }
                toplam[k, default: 0] += n; gunler[k, default: 0] += 1
            }
        }
        return sira.sorted { (toplam[$0]!, -(sira.firstIndex(of: $0) ?? 0)) > (toplam[$1]!, -(sira.firstIndex(of: $1) ?? 0)) }
            .prefix(3).filter { toplam[$0]! >= 3 }
            .map { Rota(tur: $0, sayi: toplam[$0]!, gun: gunler[$0]!, not: ipucuNotu[$0] ?? "") }
    }

    // MARK: Yazma

    static var benimGunluk: URL { Yol.ilerleme.appendingPathComponent(Makine.ad + ".jsonl") }

    /// Olay satırı ekler (dosya koordinasyonuyla — iCloud eşitlemesiyle çakışmasın).
    @discardableResult
    static func olay(_ gun: Int, _ tur: String, ek: [String: Any] = [:]) -> Bool {
        var o: [String: Any] = ["id": String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(24)),
                                "cihaz": Makine.ad, "t": Gun.isoSaniye.string(from: Date()), "gun": gun, "tur": tur]
        for (k, v) in ek where !["id", "cihaz", "t"].contains(k) { o[k] = v }
        guard var satir = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]) else { return false }
        satir.append(0x0A)
        try? FileManager.default.createDirectory(at: Yol.ilerleme, withIntermediateDirectories: true)
        var hata: NSError?, ok = false
        NSFileCoordinator().coordinate(writingItemAt: benimGunluk, options: .forMerging, error: &hata) { u in
            if let h = try? FileHandle(forWritingTo: u) {
                h.seekToEndOfFile(); h.write(satir); try? h.close(); ok = true
            } else {
                ok = (try? satir.write(to: u, options: .atomic)) != nil
            }
        }
        return ok
    }

    static func koordineliYaz(_ v: Data, _ u: URL) -> Bool {
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        var hata: NSError?, ok = false
        NSFileCoordinator().coordinate(writingItemAt: u, options: .forReplacing, error: &hata) { y in
            ok = (try? v.write(to: y, options: .atomic)) != nil
        }
        return ok
    }

    static func kayitKlasoru(_ gun: Int) -> URL { Yol.paketKlasoru(gun).appendingPathComponent("kayit", isDirectory: true) }
    static func yeniKayitAdi(_ gun: Int) -> String {
        String(format: "%03d", gun) + "-\(Makine.ad)-\(UUID().uuidString.prefix(8).lowercased()).m4a"
    }

    /// Mac'te alınan kayıt: yan dosya + "kaydetti" olayı (telefon Kayıtlarım'da görür, sabah Whisper çözümler).
    static func kayitBildir(gun: Int, ad: String, sure: Double, tanima: Double?, takilan: [String]?) {
        var yan: [String: Any] = ["ad": ad, "gun": gun, "cihaz": Makine.ad, "zaman": Gun.isoSaniye.string(from: Date()),
                                  "vaultta": true, "yerelde": false, "sure": sure.rounded()]
        if let t = tanima { yan["tanima"] = t }
        if let t = takilan { yan["takilan"] = t }
        if let v = try? JSONSerialization.data(withJSONObject: yan, options: [.sortedKeys]) {
            _ = koordineliYaz(v, kayitKlasoru(gun).appendingPathComponent((ad as NSString).deletingPathExtension + ".json"))
        }
        var ek: [String: Any] = ["dosya": ad, "sure": sure.rounded()]
        if let t = tanima { ek["tanima"] = t }
        if let t = takilan { ek["takilan"] = t }
        olay(gun, "kaydetti", ek: ek)
    }
}
