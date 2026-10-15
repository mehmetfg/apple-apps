// Günler: uygulama hangi günü açacağını kendi bilir — masadaki gun.json'u (sabah görevi) beklemez.
//   • Kaynak: Artifacts/_data/gun.json (masa) + oncalisma/paket/gun-NNN/gun.json (haftalık tampon, içe aktarılanlar).
//   • Açık gün: çalışılmamış (geçmiş, "bitti" olayı) ve atlanmamış ("atladi" olayı, telefon da yazar) en küçük gün.
//   • «Yaptım, geç» = atladi olayı; sicile girmez, tamponu boşaltır, kelimeleri başarılı sayılmaz.
//   • İçe aktarma: tek gün JSON'u, {"gunler":[…]} ya da [ … ] — denetler, paket/gun-NNN/'e yazar (sessiz paket:
//     telefon metni ve Türkçesini görür; sesi ve anlatımı sabah görevi ekler).
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct GunHatasi: Error { var neden: String }

enum GunDurumu: Hashable { case acik, yapildi, atlandi }

struct GunSatiri: Identifiable, Hashable {
    var no: Int
    var baslik: String
    var durum: GunDurumu
    var ses: Bool
    var iceAktarildi: Bool
    var secili: Bool
    var id: Int { no }
}

struct IceSonucu {
    var eklenen: [Int] = []
    var degisen: [Int] = []
    var atlanan: [String] = []     // gerekçeli: "Gün 30 zaten var"
    var hatalar: [String] = []
}

enum Gunler {
    static func gunJSON(_ no: Int) -> URL { Yol.paketKlasoru(no).appendingPathComponent("gun.json") }

    /// Masa + paketler; aynı numara bir kez (masa önce). Numara sırasıyla.
    static func tara() -> [GunVeri] {
        var m: [Int: GunVeri] = [:]
        if let g = GunVeri.yukle(), g.no > 0 { m[g.no] = g }
        let fm = FileManager.default
        for ad in (try? fm.contentsOfDirectory(atPath: Yol.paket.path)) ?? [] where ad.hasPrefix("gun-") {
            let u = Yol.paket.appendingPathComponent(ad).appendingPathComponent("gun.json")
            guard m[Int(ad.dropFirst(4)) ?? -1] == nil,
                  let d = try? Data(contentsOf: u), let g = try? JSONDecoder().decode(GunVeri.self, from: d),
                  !g.cumleler.isEmpty, g.no > 0 else { continue }
            m[g.no] = g
        }
        return m.values.sorted { $0.no < $1.no }
    }

    static func sesVar(_ no: Int) -> Bool {
        FileManager.default.fileExists(atPath: Yol.paketKlasoru(no).appendingPathComponent("ses.m4a").path)
    }

    // MARK: İçe aktarma

    private static func gunlerCikar(_ kok: Any) -> [[String: Any]]? {
        if let d = kok as? [String: Any] {
            if let l = d["gunler"] as? [[String: Any]] { return l }
            if d["cumleler"] != nil { return [d] }
        }
        if let l = kok as? [[String: Any]] { return l }
        return nil
    }

    /// Bir gün sözlüğünü denetler ve normalleştirir. Hata: gerekçe metni.
    static func denetle(_ g: [String: Any]) -> Result<[String: Any], GunHatasi> {
        guard let ham = g["cumleler"] as? [Any], !ham.isEmpty else { return .failure(GunHatasi(neden: "cümle listesi boş ya da yok")) }
        var temiz: [[String: Any]] = []
        for (i, c) in ham.enumerated() {
            if let s = c as? String { return .failure(GunHatasi(neden: "\(i + 1). cümlenin Türkçesi yok (“\(s.prefix(30))…”)")) }
            guard let d = c as? [String: Any], let en = (d["en"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !en.isEmpty else {
                return .failure(GunHatasi(neden: "\(i + 1). cümlede “en” yok"))
            }
            guard let tr = (d["tr"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !tr.isEmpty else {
                return .failure(GunHatasi(neden: "\(i + 1). cümlenin Türkçesi (“tr”) yok"))
            }
            var n: [String: Any] = ["en": en, "tr": tr]
            if let k = d["konu"] as? String, !k.isEmpty { n["konu"] = k }
            temiz.append(n)
        }
        var o = g
        o["cumleler"] = temiz
        if (o["mod"] as? String)?.isEmpty != false { o["mod"] = "kurma" }
        if (o["baslik"] as? String)?.isEmpty != false { o["baslik"] = "Gün" }
        return .success(o)
    }

    /// Dosyaları okur; çakışma olmayanları yazar. Çakışanlar `cakisan` olarak döner (kullanıcıya sorulur).
    static func hazirla(_ urls: [URL], mevcut: [GunVeri], sonrakiNo: Int) -> (gunler: [(no: Int, veri: [String: Any])], hatalar: [String]) {
        var cikti: [(Int, [String: Any])] = [], hatalar: [String] = []
        var bos = sonrakiNo
        var kullanilan = Set<Int>()
        for u in urls {
            guard let d = try? Data(contentsOf: u), let kok = try? JSONSerialization.jsonObject(with: d) else {
                hatalar.append("\(u.lastPathComponent): okunamadı ya da JSON değil"); continue
            }
            guard let liste = gunlerCikar(kok) else {
                hatalar.append("\(u.lastPathComponent): gün biçimi tanınmadı (tek gün, {\"gunler\":[…]} ya da dizi beklenir)"); continue
            }
            for g in liste {
                switch denetle(g) {
                case .failure(let hata):
                    let etiket = (g["gun"] as? Int).map { "Gün \($0)" } ?? "bir gün"
                    hatalar.append("\(u.lastPathComponent) · \(etiket): \(hata.neden)")
                case .success(var ok):
                    var no = (ok["gun"] as? Int) ?? Int((ok["gun"] as? String) ?? "") ?? 0
                    if no <= 0 {
                        while kullanilan.contains(bos) || mevcut.contains(where: { $0.no == bos }) { bos += 1 }
                        no = bos; bos += 1
                    }
                    if kullanilan.contains(no) { hatalar.append("\(u.lastPathComponent): Gün \(no) birden çok kez var"); continue }
                    kullanilan.insert(no)
                    ok["gun"] = no
                    ok["kaynak"] = "ice-aktarim"
                    cikti.append((no, ok))
                }
            }
        }
        return (cikti.sorted { $0.0 < $1.0 }.map { (no: $0.0, veri: $0.1) }, hatalar)
    }

    /// Günü pakete yazar. Eski paketin sesi/anlatımı yeni metne uymaz → temizlenir (değişim).
    @discardableResult
    static func yaz(no: Int, veri: [String: Any], degistir: Bool, sozluk: Sozluk) -> Bool {
        let k = Yol.paketKlasoru(no)
        let fm = FileManager.default
        if degistir {
            for ad in ["anlatim.json", "ses.m4a", "paket.json", "denetim.json", "cozum.json"] { try? fm.removeItem(at: k.appendingPathComponent(ad)) }
        }
        guard let v = try? JSONSerialization.data(withJSONObject: veri, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              OnCalisma.koordineliYaz(v, gunJSON(no)) else { return false }
        try? fm.createDirectory(at: k.appendingPathComponent("kayit", isDirectory: true), withIntermediateDirectories: true)
        // sessiz paket: telefon metni + Türkçeyi + sözlüğü okur; ses/anlatım sonra gelir
        if !fm.fileExists(atPath: k.appendingPathComponent("paket.json").path) {
            let cum = (veri["cumleler"] as? [[String: Any]] ?? [])
            func soz(_ tur: String) -> [[String: Any]] {
                (veri[tur] as? [String] ?? []).map { w in
                    var d: [String: Any] = ["w": w, "tur": tur]
                    if let s = sozluk.bul(w) {
                        d["pos"] = s.pos; d["cefr"] = s.cefr; d["ipa"] = s.phon; d["tanim"] = s.def; d["tr"] = s.tr
                        if let e = s.ex.first { d["ornek"] = e }
                    }
                    return d
                }
            }
            let p: [String: Any] = [
                "gun": no, "baslik": veri["baslik"] ?? "Gün \(no)", "surum": "ice-" + String(v.count, radix: 16) + String(abs(v.hashValue) % 0xFFFF, radix: 16),
                "uretildi": Gun.isoSaniye.string(from: Date()), "ses": NSNull(),
                "metin": cum.enumerated().map { ["i": $0.offset, "en": $0.element["en"] ?? "", "tr": $0.element["tr"] ?? "", "konu": $0.element["konu"] ?? NSNull()] as [String: Any] },
                "ozet": veri["ozet"] ?? veri["tema"] ?? NSNull(), "tema": veri["tema"] ?? NSNull(),
                "sahne_konulari": veri["sahne_konulari"] ?? [],
                "sozluk": soz("yeni") + soz("tanidik") + soz("yanki"),
            ]
            if let pv = try? JSONSerialization.data(withJSONObject: p, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
                _ = OnCalisma.koordineliYaz(pv, k.appendingPathComponent("paket.json"))
            }
        }
        return true
    }
}

// MARK: - Tezgâh: gün seçimi, atlama, içe aktarma

@MainActor
extension Tezgah {
    /// Kenar çubuğu ve başlangıç kartı için gün listesi: son çalışılan + bütün açık/atlanan günler.
    var gunSatirlari: [GunSatiri] {
        let tum = tumGunler
        let yapilan = yapilanGunler
        var satirlar: [GunSatiri] = []
        let sonYapilan = tum.last(where: { yapilan.contains($0.no) })?.no
        for g in tum {
            let d: GunDurumu = yapilan.contains(g.no) ? .yapildi : atlananGunler.contains(g.no) ? .atlandi : .acik
            if d == .yapildi && g.no != sonYapilan { continue }
            satirlar.append(GunSatiri(no: g.no, baslik: g.ad, durum: d, ses: Gunler.sesVar(g.no),
                                      iceAktarildi: false, secili: g.no == gunMasa?.no))
        }
        return satirlar
    }

    var yapilanGunler: Set<Int> { Set(gecmis().map(\.gun)).union(bittiGunler) }

    /// Açık gün: seçilmişse o, yoksa çalışılmamış ve atlanmamış en küçük gün; hiçbiri yoksa en yeni gün.
    func gunuCoz() -> GunVeri? {
        let tum = tumGunler
        if let s = secilenGun, let g = tum.first(where: { $0.no == s }) { return g }
        let bitmis = yapilanGunler.union(atlananGunler)
        return tum.first(where: { !bitmis.contains($0.no) }) ?? tum.last
    }

    func gunSec(_ no: Int?) {
        if let x = o, !x.indi {
            if x.tekrar { birak() }      // tekrar çalışma sicile girmez: günü seçmek için kapanır
            else {
                duyur("Gün \(x.gun.no) yarım — önce bitir ya da Çalışma › Oturumu kapat")
                return
            }
        }
        if o?.indi == true { birak() }
        secilenGun = no
        gorunum = .bugun
        tazele(hepsi: true)
    }

    /// «Yaptım, geç»: gün sicile girmez; telefon da görür; sıradaki gün açılır.
    func atla(_ g: GunVeri) {
        guard OnCalisma.olay(g.no, "atladi") else { duyur("Atlama yazılamadı"); return }
        atlananGunler.insert(g.no)
        secilenGun = nil
        tazele(hepsi: true)
        if let s = gunMasa, s.no != g.no { duyur("Gün \(g.no) geçildi · sıradaki: Gün \(s.no)") }
        else { duyur("Gün \(g.no) geçildi · sıradaki gün henüz yok — içe aktar ya da sabah görevini bekle") }
    }

    func sonrakiGun() {
        let tum = tumGunler
        let su = gunMasa?.no ?? 0
        if let s = tum.first(where: { $0.no > su }) { gunSec(s.no) } else { duyur("Sonraki gün henüz yok") }
    }

    func oncekiGun() {
        let tum = tumGunler
        let su = gunMasa?.no ?? 0
        if let s = tum.last(where: { $0.no < su }) { gunSec(s.no) } else { duyur("Önceki gün yok") }
    }

    // MARK: İçe aktarma

    func iceAktarPaneli() {
        let p = NSOpenPanel()
        p.title = "Gün JSON'u seç"
        p.message = "Tek gün, {\"gunler\":[…]} hafta paketi ya da gün dizisi. Birden çok dosya seçebilirsin."
        p.allowedContentTypes = [.json]
        p.allowsMultipleSelection = true
        p.canChooseDirectories = false
        guard p.runModal() == .OK else { return }
        iceAktar(p.urls)
    }

    func iceAktar(_ urls: [URL]) {
        let mevcut = Gunler.tara()
        let enBuyuk = max(mevcut.last?.no ?? 0, arsiv.gunler.map(\.gun).max() ?? 0)
        let (gunler, hatalar) = Gunler.hazirla(urls.filter { $0.pathExtension.lowercased() == "json" }, mevcut: mevcut, sonrakiNo: enBuyuk + 1)
        var s = IceSonucu(hatalar: hatalar)
        var degistirilecek = Set<Int>()
        let var_ = gunler.filter { g in mevcut.contains { $0.no == g.no } }
        if !var_.isEmpty {
            let a = NSAlert()
            a.messageText = "Gün " + var_.map { String($0.no) }.joined(separator: ", ") + " zaten var"
            a.informativeText = "Değiştirirsen o günün anlatımı ve sesi silinir (yeni metne uymaz); sabah görevi yeniden üretir. Atlarsan eski gün kalır."
            a.addButton(withTitle: "Değiştir")
            a.addButton(withTitle: "Atla")
            // sınama (CUMLE_SESSIZ): pencere açmaz, çakışanları değiştirir
            if Yol.env["CUMLE_SESSIZ"] != nil || a.runModal() == .alertFirstButtonReturn { degistirilecek = Set(var_.map(\.no)) }
        }
        for g in gunler {
            let varMi = mevcut.contains { $0.no == g.no }
            if varMi && !degistirilecek.contains(g.no) { s.atlanan.append("Gün \(g.no) zaten var — atlandı"); continue }
            if Gunler.yaz(no: g.no, veri: g.veri, degistir: varMi, sozluk: sozluk) {
                if varMi { s.degisen.append(g.no) } else { s.eklenen.append(g.no) }
            } else { s.hatalar.append("Gün \(g.no) yazılamadı") }
        }
        tazele(hepsi: true)
        iceAktarmaOzeti(s)
    }

    private func iceAktarmaOzeti(_ s: IceSonucu) {
        let ok = s.eklenen + s.degisen
        if s.hatalar.isEmpty && s.atlanan.isEmpty {
            duyur(ok.isEmpty ? "İçe aktarılacak gün bulunamadı" : "\(ok.count) gün içe aktarıldı: Gün \(ok.map(String.init).joined(separator: ", ")) · telefona da iniyor")
            return
        }
        let a = NSAlert()
        a.messageText = ok.isEmpty ? "Hiçbir gün içe aktarılamadı" : "\(ok.count) gün içe aktarıldı, bazıları olmadı"
        var m = ""
        if !ok.isEmpty { m += "İçe aktarılan: Gün \(ok.map(String.init).joined(separator: ", "))\n\n" }
        if !s.atlanan.isEmpty { m += s.atlanan.joined(separator: "\n") + "\n\n" }
        if !s.hatalar.isEmpty { m += "Olmayanlar:\n" + s.hatalar.map { "• " + $0 }.joined(separator: "\n") }
        a.informativeText = m
        if Yol.env["CUMLE_SESSIZ"] != nil { FileHandle.standardError.write(Data((a.messageText + "\n" + m + "\n").utf8)) } else { a.runModal() }
    }
}
