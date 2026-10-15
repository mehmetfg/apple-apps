// Uygulamanın tek durumu. Her değişiklik: ortak dolaba yaz → widget'ı tazele → (2 sn sonra) vault'a yaz.
// Vault'tan okunanlar: tohum (ilk metin), Teoria'nın akis.json'u (Voice Dream işaretleri), Mac'in anlatım dökümleri.
// Vault'a yazılanlar: telefon/kenar.json (tek yazar telefon), telefon/ses/*.m4a, metin/<başlık> — taslak.md.
import ActivityKit
import CoreSpotlight
import Foundation
import SwiftUI
import UIKit
import UserNotifications
import WidgetKit

@MainActor
final class Merkez: ObservableObject {
    static weak var paylasilan: Merkez?

    @Published var d: KenarDurum
    @Published private(set) var bagli = false
    @Published private(set) var esitleniyor = false
    @Published private(set) var sonEsitleme: Date?
    @Published var hata: String?
    @Published var vdKitaplar: [KitapKaydi] = []
    @Published var kutuphane: [Isaret] = []           // akis.json'daki bütün işaretler (Kütüphaneden ekle)
    @Published var odak = false

    private let yerImiAnahtari = "kenar.kasa.yerimi"
    private var kok: URL?
    private var yazmaGorevi: Task<Void, Never>?

    static let proje = "00 - Philosophy/_projects/kenar"
    static let akisYolu = "00 - Philosophy/_projects/teoria/veri/akis.json"

    init() {
        d = Depo.durumOku() ?? KenarDurum()
        if let v = ProcessInfo.processInfo.environment["KENAR_VAULT"] {
            kok = URL(fileURLWithPath: v); bagli = true
        } else if let v = Depo.ayar.data(forKey: yerImiAnahtari) {
            var eski = false
            if let u = try? URL(resolvingBookmarkData: v, options: [], relativeTo: nil, bookmarkDataIsStale: &eski) {
                kok = u; bagli = true
                if eski { yerImi(u) }
            }
        }
        if let veri = Depo.ayar.data(forKey: "vdKitaplar"), let k = try? Depo.cozucu.decode([KitapKaydi].self, from: veri) { vdKitaplar = k }
        odak = Depo.ayar.bool(forKey: "odak")
        Merkez.paylasilan = self
    }

    // MARK: vault klasörü
    func klasorSecildi(_ url: URL) {
        let e = url.startAccessingSecurityScopedResource()
        defer { if e { url.stopAccessingSecurityScopedResource() } }
        yerImi(url)
        kok = url; bagli = true; hata = nil
        Task { await esitle() }
    }

    private func yerImi(_ url: URL) {
        if let v = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            Depo.ayar.set(v, forKey: yerImiAnahtari)
        }
    }

    // MARK: kaydet
    func kaydet(vault: Bool = true) {
        d.guncelleme = .now
        Depo.durumYaz(d)
        WidgetCenter.shared.reloadAllTimelines()
        guard vault else { return }
        yazmaGorevi?.cancel()
        yazmaGorevi = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.vaultaYaz()
        }
    }

    // MARK: eşitle (öne gelişte, ↻ ile, klasör seçilince)
    func esitle() async {
        gelenleriAl()
        aynaDonusunuAl()
        guard let kok, !esitleniyor else { kaydet(vault: false); return }
        esitleniyor = true
        defer { esitleniyor = false }
        let mevcut = d
        let sonuc = await Task.detached { () -> Result<Okunan, Error> in
            let e = kok.startAccessingSecurityScopedResource()
            defer { if e { kok.stopAccessingSecurityScopedResource() } }
            return Result { try Merkez.oku(Vault.kokBul(kok), mevcut) }
        }.value
        switch sonuc {
        case .failure(let h): hata = h.localizedDescription
        case .success(let o):
            hata = nil
            birlestir(o)
            sonEsitleme = .now
        }
        kaydet(vault: false)
        await vaultaYaz()
        Bildirimci.planla(d)
        Spotlight.dizinle(d)
    }

    struct Okunan: Sendable {
        var tohum: Metin?
        var yedek: KenarDurum?
        var vdYeni: [Isaret]
        var vdGorulen: [String]
        var vdKitaplar: [KitapKaydi]
        var kutuphane: [Isaret]
        var anlatim: [String: MacAnlatim]
    }

    struct MacAnlatim: Codable, Sendable { var id: String; var dokum: String?; var kapsanan: [String]?; var atlanan: [String]?; var claude: String? }

    nonisolated static func oku(_ kok: URL, _ mevcut: KenarDurum) throws -> Okunan {
        let proje = kok.appendingPathComponent(proje)
        var o = Okunan(tohum: nil, yedek: nil, vdYeni: [], vdGorulen: [], vdKitaplar: [], kutuphane: [], anlatim: [:])
        guard FileManager.default.fileExists(atPath: kok.appendingPathComponent("00 - Philosophy").path) else {
            throw NSError(domain: "Kenar", code: 1, userInfo: [NSLocalizedDescriptionKey: "Seçilen klasör vault değil. iCloud Drive › Obsidian › Personel Data Management'ı seç."])
        }
        // ilk açılış: önce telefonun eski yedeği (yeniden kurulum), yoksa Mac'in tohumu
        if mevcut.metin == nil {
            let yedekURL = proje.appendingPathComponent("telefon/kenar.json")
            if Vault.indir(yedekURL), let veri = Vault.koordineliOku(yedekURL), let y = try? Depo.cozucu.decode(KenarDurum.self, from: veri), y.metin != nil {
                o.yedek = y
            } else {
                let tk = proje.appendingPathComponent("veri/tohum")
                let dosyalar = (try? FileManager.default.contentsOfDirectory(at: tk, includingPropertiesForKeys: nil)) ?? []
                for f in dosyalar.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where f.pathExtension == "json" {
                    _ = Vault.indir(f)
                    if let veri = Vault.koordineliOku(f), let m = try? JSONDecoder().decode(Metin.self, from: veri) { o.tohum = m; break }
                }
                if o.tohum == nil { throw NSError(domain: "Kenar", code: 2, userInfo: [NSLocalizedDescriptionKey: "Tohum yok. Mac'te: python3 \"\(Merkez.proje)/veri/kenar.py\" tohum"]) }
            }
        }
        let metin = mevcut.metin ?? o.yedek?.metin ?? o.tohum
        let gorulen = Set(mevcut.gorulenVD + (o.yedek?.gorulenVD ?? []))

        // Voice Dream işaretleri (Teoria'nın akışı) — metinle ilgisi yeterli olan Kutu'ya düşer
        let akis = kok.appendingPathComponent(akisYolu)
        _ = Vault.indir(akis)
        if let veri = Vault.koordineliOku(akis), let a = try? JSONDecoder().decode(Akis.self, from: veri) {
            let adlar = Dictionary(a.kitaplar.map { ($0.id, $0.baslik) }, uniquingKeysWith: { x, _ in x })
            for i in a.isaretler {
                let z = Tarih.coz(i.tarih) ?? .now
                let isaret = Isaret(id: "vd-" + i.id, metin: i.metin, kaynak: .vd, kitap: i.kitap, kitapAdi: adlar[i.kitap] ?? i.baslik, tarih: z)
                o.kutuphane.append(isaret)
                if gorulen.contains(i.id) { continue }
                o.vdGorulen.append(i.id)
                if Ilgi.puan(i.metin, metin) >= 1.5 { o.vdYeni.append(isaret) }
            }
            o.kutuphane.sort { $0.tarih > $1.tarih }
            o.vdKitaplar = a.kitaplar.sorted { ($0.son ?? "") > ($1.son ?? "") }.map { KitapKaydi(id: $0.id, ad: $0.baslik, kagit: false) }
        }
        // Mac'in anlatım dökümleri
        let ak = proje.appendingPathComponent("mac/anlatim")
        for an in mevcut.anlatimlar where an.claude == nil {
            let f = ak.appendingPathComponent(an.id + ".json")
            guard Vault.indir(f, bekle: 2), let veri = Vault.koordineliOku(f), let m = try? JSONDecoder().decode(MacAnlatim.self, from: veri) else { continue }
            o.anlatim[an.id] = m
        }
        return o
    }

    private func birlestir(_ o: Okunan) {
        if d.metin == nil {
            if let y = o.yedek { d = y } else if let t = o.tohum { d.metin = t }
            Bildirimci.kategorileriKur(d.metin)
        }
        let var_olan = Set(d.isaretler.map(\.id))
        d.isaretler += o.vdYeni.filter { !var_olan.contains($0.id) }
        d.gorulenVD += o.vdGorulen
        if !o.vdKitaplar.isEmpty {
            vdKitaplar = o.vdKitaplar
            if let veri = try? Depo.kodlayici.encode(o.vdKitaplar) { Depo.ayar.set(veri, forKey: "vdKitaplar") }
        }
        kutuphane = o.kutuphane
        for (id, m) in o.anlatim {
            guard let i = d.anlatimlar.firstIndex(where: { $0.id == id }) else { continue }
            d.anlatimlar[i].dokum = m.dokum ?? d.anlatimlar[i].dokum
            if let k = m.kapsanan { d.anlatimlar[i].kapsanan = k }
            if let a = m.atlanan { d.anlatimlar[i].atlanan = a }
            d.anlatimlar[i].claude = m.claude ?? d.anlatimlar[i].claude
        }
    }

    // MARK: vault'a yaz (telefon tek yazar)
    func vaultaYaz() async {
        guard let kok else { return }
        let durum = d
        let ses = Depo.sesKlasoru
        let yazilan = await Task.detached { () -> [String] in
            let e = kok.startAccessingSecurityScopedResource()
            defer { if e { kok.stopAccessingSecurityScopedResource() } }
            let k = Vault.kokBul(kok).appendingPathComponent(Merkez.proje)
            var tasinan: [String] = []
            for an in durum.anlatimlar where !an.vaultta {
                let kaynak = ses.appendingPathComponent(an.id + ".m4a")
                guard let veri = try? Data(contentsOf: kaynak) else { continue }
                if Vault.koordineliYaz(veri, k.appendingPathComponent("telefon/ses/\(an.id).m4a")) { tasinan.append(an.id) }
            }
            var son = durum
            for i in son.anlatimlar.indices where tasinan.contains(son.anlatimlar[i].id) { son.anlatimlar[i].vaultta = true }
            if let veri = try? Depo.kodlayici.encode(son) { _ = Vault.koordineliYaz(veri, k.appendingPathComponent("telefon/kenar.json")) }
            if let m = son.metin {
                _ = Vault.koordineliYaz(Data(Taslak.md(m, son).utf8), k.appendingPathComponent("metin/\(m.baslik) — taslak.md"))
            }
            return tasinan
        }.value
        if !yazilan.isEmpty {
            for i in d.anlatimlar.indices where yazilan.contains(d.anlatimlar[i].id) { d.anlatimlar[i].vaultta = true }
            Depo.durumYaz(d)
        }
    }

    // MARK: dışarıdan gelenler
    func gelenleriAl() {
        let g = Depo.gelenleriAl()
        guard !g.isEmpty else { return }
        for x in g {
            let kaynakAd = x.kaynakUygulama ?? x.adres.flatMap { URL(string: $0)?.host() } ?? "Paylaşılan"
            d.isaretler.append(Isaret(id: Kimlik.yeni(), metin: x.metin, kaynak: .paylas, kitap: "paylas-" + kaynakAd.tr, kitapAdi: kaynakAd, tarih: x.tarih))
        }
        kaydet()
    }

    func aynaDonusunuAl() {
        guard var m = d.metin else { return }
        var degisti = false
        for x in Depo.aynadanGelen() {
            if let i = m.bolumler.firstIndex(where: { "\(m.id)-\($0.id)" == x.id }), m.bolumler[i].ingilizce != x.ingilizce {
                m.bolumler[i].ingilizce = x.ingilizce; degisti = true
            }
        }
        if degisti { d.metin = m; kaydet() }
    }

    func odakDegisti() { odak = Depo.ayar.bool(forKey: "odak") }

    // MARK: işaretler
    func ata(_ id: String, _ bolum: String?) {
        guard let i = d.isaretler.firstIndex(where: { $0.id == id }) else { return }
        d.isaretler[i].bolum = bolum
        d.isaretler[i].disarida = false
        if bolum == nil { d.isaretler[i].x = nil; d.isaretler[i].y = nil }
        Haptik.orta()
        kaydet()
    }

    func disariAt(_ id: String) {
        guard let i = d.isaretler.firstIndex(where: { $0.id == id }) else { return }
        d.isaretler[i].disarida = true; d.isaretler[i].bolum = nil
        d.baglar.removeAll { $0.kaynak == id || $0.hedef == id }
        Haptik.hafif(); kaydet()
    }

    func geriAl(_ id: String) {
        guard let i = d.isaretler.firstIndex(where: { $0.id == id }) else { return }
        d.isaretler[i].disarida = false; kaydet()
    }

    func sil(_ id: String) {
        d.isaretler.removeAll { $0.id == id }
        d.baglar.removeAll { $0.kaynak == id || $0.hedef == id }
        kaydet()
    }

    func rol(_ id: String, _ r: Rol?) {
        guard let i = d.isaretler.firstIndex(where: { $0.id == id }) else { return }
        d.isaretler[i].rol = r; Haptik.secim(); kaydet()
    }

    func notYaz(_ id: String, _ s: String) {
        guard let i = d.isaretler.firstIndex(where: { $0.id == id }) else { return }
        d.isaretler[i].not = s; kaydet()
    }

    func konum(_ id: String, _ p: CGPoint) {
        guard let i = d.isaretler.firstIndex(where: { $0.id == id }) else { return }
        d.isaretler[i].x = p.x; d.isaretler[i].y = p.y; kaydet()
    }

    func bagla(_ a: String, _ b: String) {
        guard a != b else { return }
        if let i = d.baglar.firstIndex(where: { ($0.kaynak == a && $0.hedef == b) || ($0.kaynak == b && $0.hedef == a) }) {
            d.baglar.remove(at: i); Haptik.hafif()
        } else {
            d.baglar.append(Bag(kaynak: a, hedef: b)); Haptik.basari()
        }
        kaydet()
    }

    @discardableResult
    func isaretEkle(_ metin: String, kaynak: Kaynak, kitap: String? = nil, kitapAdi: String? = nil, bolum: String? = nil) -> Isaret? {
        let t = metin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let o = d.aktifOturum
        let x = Isaret(id: Kimlik.yeni(), metin: t, kaynak: kaynak, kitap: kitap ?? o?.kitap ?? "elle", kitapAdi: kitapAdi ?? o?.kitapAdi ?? "Kendi notum",
                       tarih: .now, bolum: bolum)
        d.isaretler.append(x)
        if let o, let i = d.oturumlar.firstIndex(where: { $0.id == o.id }) {
            d.oturumlar[i].isaret += 1
            Canli.guncelle(d.oturumlar[i])
        }
        Haptik.basari()
        kaydet()
        return x
    }

    func kutuphanedenEkle(_ x: Isaret) {
        guard !d.isaretler.contains(where: { $0.id == x.id }) else { return }
        d.isaretler.append(x); Haptik.orta(); kaydet()
    }

    // MARK: bölümler
    func bolumGuncelle(_ b: Bolum) {
        guard var m = d.metin, let i = m.bolumler.firstIndex(where: { $0.id == b.id }) else { return }
        m.bolumler[i] = b
        d.metin = m
        kaydet()
    }

    func bolumBitti(_ id: String, _ deger: Bool) {
        guard var m = d.metin, let i = m.bolumler.firstIndex(where: { $0.id == id }) else { return }
        m.bolumler[i].bitti = deger
        d.metin = m
        if deger { Haptik.basari() } else { Haptik.hafif() }
        aynaKuyrugunuYaz()
        kaydet()
    }

    /// Biten bölümler Ayna'nın kuyruğuna gider: Ayna onları İngilizce anlattırır, düzeltilmiş paragrafı geri yazar.
    func aynaKuyrugunuYaz() {
        guard let m = d.metin else { return }
        Depo.aynayaGonder(m.bolumler.filter { $0.bitti && $0.ingilizce == nil }.map {
            Depo.AynaIsi(id: "\(m.id)-\($0.id)", metin: m.baslik, bolumNo: $0.no, baslik: $0.baslik, iddia: $0.iddia, paragraf: $0.paragraf, tarih: .now)
        })
    }

    func metinGuncelle(baslik: String? = nil, soru: String? = nil) {
        guard var m = d.metin else { return }
        if let baslik { m.baslik = baslik }
        if let soru { m.soru = soru }
        d.metin = m; kaydet()
    }

    /// Beş bölüm bitince: metin Üretim klasörüne bitmiş iş olarak yazılır (taslak orada değil, projede durur).
    func uretimeGonder() async -> String? {
        guard let kok, var m = d.metin else { return "Vault bağlı değil." }
        let durum = d
        let tamam = await Task.detached { () -> Bool in
            let e = kok.startAccessingSecurityScopedResource()
            defer { if e { kok.stopAccessingSecurityScopedResource() } }
            let hedef = Vault.kokBul(kok).appendingPathComponent("02 - Eudomonia/Üretim/\(m.baslik).md")
            if FileManager.default.fileExists(atPath: hedef.path) { return false }
            return Vault.koordineliYaz(Data(Taslak.uretim(m, durum).utf8), hedef)
        }.value
        guard tamam else { return "Üretim'de aynı adla bir dosya var; başlığı değiştir ya da eskisini kaldır." }
        m.uretimeGitti = .now
        d.metin = m
        Haptik.basari()
        kaydet()
        return nil
    }

    // MARK: okuma oturumu
    func oturumBaslat(kitap: KitapKaydi, soru: String) {
        if d.aktifOturum != nil { oturumuBitir() }
        if kitap.kagit, !d.kitaplar.contains(where: { $0.id == kitap.id }) { d.kitaplar.append(kitap) }
        let o = Oturum(id: Kimlik.yeni(), kitap: kitap.id, kitapAdi: kitap.ad, soru: soru, baslangic: .now)
        d.oturumlar.append(o)
        Canli.baslat(o)
        Haptik.basari()
        kaydet()
    }

    func oturumuBitir() {
        guard let o = d.aktifOturum, let i = d.oturumlar.firstIndex(where: { $0.id == o.id }) else { return }
        d.oturumlar[i].bitis = .now
        Canli.bitir()
        Haptik.orta()
        kaydet()
    }

    func kitapEkle(_ k: KitapKaydi) {
        guard !d.kitaplar.contains(where: { $0.id == k.id }) else { return }
        d.kitaplar.append(k); kaydet()
    }

    // MARK: anlatım
    func anlatimEkle(id: String, sure: Double, bolum: String?, kitap: String?) {
        d.anlatimlar.append(Anlatim(id: id, tarih: .now, bolum: bolum, kitap: kitap, sure: sure))
        kaydet()
    }

    func onDokumYaz(_ id: String, _ metin: String) {
        guard let i = d.anlatimlar.firstIndex(where: { $0.id == id }) else { return }
        d.anlatimlar[i].onDokum = metin
        let ilgili = d.isaretler.filter { x in
            if let b = d.anlatimlar[i].bolum { return x.bolum == b }
            if let k = d.anlatimlar[i].kitap { return x.kitap == k }
            return false
        }
        let (kap, atl) = Kapsam.hesapla(metin, ilgili)
        if d.anlatimlar[i].dokum == nil { d.anlatimlar[i].kapsanan = kap; d.anlatimlar[i].atlanan = atl }
        kaydet()
    }

    func anlatimSil(_ id: String) {
        d.anlatimlar.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: Depo.sesKlasoru.appendingPathComponent(id + ".m4a"))
        kaydet()
    }

    // MARK: bildirim eylemi uygulama kapalıyken gelirse
    nonisolated static func arkaPlandaAta(_ id: String, _ bolum: String?, disari: Bool) async {
        if let m = await Merkez.paylasilan {
            await MainActor.run { disari ? m.disariAt(id) : m.ata(id, bolum) }
            return
        }
        guard var d = Depo.durumOku(), let i = d.isaretler.firstIndex(where: { $0.id == id }) else { return }
        if disari { d.isaretler[i].disarida = true; d.isaretler[i].bolum = nil } else { d.isaretler[i].bolum = bolum }
        d.guncelleme = .now
        Depo.durumYaz(d)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: Teoria'nın akış dosyası (yalnız gereken alanlar)

struct Akis: Decodable, Sendable {
    struct I: Decodable, Sendable { var id: String; var kitap: String; var baslik: String; var metin: String; var tarih: String }
    struct K: Decodable, Sendable { var id: String; var baslik: String; var son: String? }
    var isaretler: [I]
    var kitaplar: [K]
}

enum Tarih {
    /// akis.json saatleri yerel saattir ve saat dilimi taşımaz: "2026-10-10T14:31:02" ya da yalnız "2026-10-10".
    static func coz(_ s: String) -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = s.count >= 19 ? "yyyy-MM-dd'T'HH:mm:ss" : "yyyy-MM-dd"
        return f.date(from: String(s.prefix(19)))
    }
}

// MARK: Kapsam — anlatımda hangi işaret geçti (Mac'teki kenar.py ile aynı kaba ölçü)

enum Kapsam {
    static let durak: Set<String> = Set("ve ile bir bu şu o da de ki mi için gibi ama çünkü daha çok en olan olarak ise hem ya veya değil kadar sonra önce her şey bunu bunun onun onu ne nasıl neden var yok yani ancak artık bütün".split(separator: " ").map(String.init))

    static func kokler(_ s: String) -> Set<String> {
        Set(s.tr.split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count >= 5 && !durak.contains($0) }.map { String($0.prefix(5)) })
    }

    static func hesapla(_ anlatim: String, _ isaretler: [Isaret]) -> ([String], [String]) {
        let a = kokler(anlatim)
        var sayim: [String: Int] = [:]
        for i in isaretler { for k in kokler(i.metin) { sayim[k, default: 0] += 1 } }
        var kap: [String] = [], atl: [String] = []
        for i in isaretler {
            let k = kokler(i.metin).sorted { (sayim[$0] ?? 0, -$0.count) < (sayim[$1] ?? 0, -$1.count) }.prefix(4)
            if k.filter({ a.contains($0) }).count >= min(2, k.count) { kap.append(i.id) } else { atl.append(i.id) }
        }
        return (kap, atl)
    }
}

// MARK: vault dosya yardımcıları

enum Vault {
    nonisolated static func kokBul(_ kok: URL) -> URL {
        var u = kok
        for _ in 0..<4 {
            if FileManager.default.fileExists(atPath: u.appendingPathComponent("00 - Philosophy").path) { return u }
            u = u.deletingLastPathComponent()
        }
        return kok
    }

    nonisolated static func indir(_ u: URL, bekle: Double = 6) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: u.path), (try? u.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?.ubiquitousItemDownloadingStatus != .notDownloaded { return true }
        try? fm.startDownloadingUbiquitousItem(at: u)
        var i = 0.0
        while i < bekle {
            let s = (try? u.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?.ubiquitousItemDownloadingStatus
            if s == .current || (s == nil && fm.fileExists(atPath: u.path)) { return true }
            Thread.sleep(forTimeInterval: 0.25); i += 0.25
        }
        return false
    }

    nonisolated static func koordineliOku(_ u: URL) -> Data? {
        var veri: Data?; var h: NSError?
        NSFileCoordinator().coordinate(readingItemAt: u, options: [], error: &h) { x in veri = try? Data(contentsOf: x) }
        return veri
    }

    nonisolated static func koordineliYaz(_ veri: Data, _ u: URL) -> Bool {
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        var tamam = false; var h: NSError?
        NSFileCoordinator().coordinate(writingItemAt: u, options: .forReplacing, error: &h) { x in
            tamam = (try? veri.write(to: x, options: .atomic)) != nil
        }
        return tamam
    }
}

// MARK: Obsidian'da okunan taslak + Üretim'e giden bitmiş metin

enum Taslak {
    static func md(_ m: Metin, _ d: KenarDurum) -> String {
        var s = "---\nbaşlık: \(m.baslik)\ntür: taslak\ndisiplin: \(m.disiplin)\nyazan: ben\naraç: Kenar\ngüncelleme: \(ISO8601DateFormatter().string(from: .now))\n---\n\n"
        s += "# \(m.baslik)\n\n> **Soru:** \(m.soru)\n> \(m.kelime)/\(m.hedef) kelime · \(m.bittiSayisi)/\(m.bolumler.count) bölüm bitti\n\n"
        s += "_Bu dosyayı Kenar yazar; elle düzeltme bir sonraki eşitlemede ezilir. Yazı telefonda, Kenar › Metin › bölüm._\n\n"
        for b in m.bolumler {
            s += "## §\(b.no) \(b.baslik)\(b.bitti ? " ✓" : "")\n\n*İddia:* \(b.iddia)\n\n"
            s += b.paragraf.isEmpty ? "_(henüz yazılmadı)_\n\n" : b.paragraf + "\n\n"
            let k = d.kanitlar(b.id)
            if !k.isEmpty {
                s += "**Kanıtlar**\n\n"
                for x in k { s += "- \(x.rol.map { "[\($0.ad)] " } ?? "")\"\(x.metin.prefix(400))\" — *\(x.kitapAdi)*\(x.not.isEmpty ? " · \(x.not)" : "")\n" }
                s += "\n"
            }
            if let e = b.ingilizce { s += "**English (Ayna)**\n\n\(e)\n\n" }
        }
        return s
    }

    static func uretim(_ m: Metin, _ d: KenarDurum) -> String {
        var s = "---\nbaşlık: \(m.baslik)\ntür: deneme\ndisiplin: \(m.disiplin)\nyazan: ben\ndurum: bitti\ntarih: \(String(ISO8601DateFormatter().string(from: .now).prefix(10)))\nkelime: \(m.kelime)\n---\n\n"
        s += "# \(m.baslik)\n\n*\(m.soru)*\n\n"
        for b in m.bolumler { s += "## \(b.baslik)\n\n\(b.paragraf)\n\n" }
        let kaynaklar = Set(d.isaretler.filter { $0.bolum != nil }.map(\.kitapAdi)).sorted()
        if !kaynaklar.isEmpty { s += "---\n\n**Dayandığı okumalar:** " + kaynaklar.joined(separator: " · ") + "\n" }
        if m.bolumler.allSatisfy({ $0.ingilizce != nil }) {
            s += "\n---\n\n# English version\n\n" + m.bolumler.map { "## \($0.baslik)\n\n\($0.ingilizce ?? "")" }.joined(separator: "\n\n") + "\n"
        }
        return s
    }
}

// MARK: Canlı Etkinlik

enum Canli {
    static func baslat(_ o: Oturum) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        for a in Activity<OkumaEtkinligi>.activities { Task { await a.end(nil, dismissalPolicy: .immediate) } }
        let ic = ActivityContent(state: OkumaEtkinligi.ContentState(baslangic: o.baslangic, isaret: o.isaret), staleDate: nil)
        _ = try? Activity.request(attributes: OkumaEtkinligi(kitapAdi: o.kitapAdi, soru: o.soru), content: ic, pushType: nil)
    }

    static func guncelle(_ o: Oturum) {
        for a in Activity<OkumaEtkinligi>.activities {
            Task { await a.update(ActivityContent(state: .init(baslangic: o.baslangic, isaret: o.isaret), staleDate: nil)) }
        }
    }

    static func bitir() {
        for a in Activity<OkumaEtkinligi>.activities { Task { await a.end(nil, dismissalPolicy: .immediate) } }
    }
}

// MARK: Spotlight — işaretler ve bölümler telefonun aramasında çıkar

enum Spotlight {
    static func dizinle(_ d: KenarDurum) {
        var ogeler: [CSSearchableItem] = []
        if let m = d.metin {
            for b in m.bolumler {
                let a = CSSearchableItemAttributeSet(contentType: .text)
                a.title = "§\(b.no) \(b.baslik) — \(m.baslik)"
                a.contentDescription = b.iddia
                ogeler.append(CSSearchableItem(uniqueIdentifier: "bolum/\(b.id)", domainIdentifier: "bolum", attributeSet: a))
            }
        }
        for x in d.isaretler where !x.disarida {
            let a = CSSearchableItemAttributeSet(contentType: .text)
            a.title = x.kitapAdi
            a.contentDescription = String(x.metin.prefix(300))
            ogeler.append(CSSearchableItem(uniqueIdentifier: "isaret/\(x.id)", domainIdentifier: "isaret", attributeSet: a))
        }
        CSSearchableIndex.default().deleteAllSearchableItems { _ in CSSearchableIndex.default().indexSearchableItems(ogeler) }
    }
}

// MARK: dokunsal geri bildirim

enum Haptik {
    static func hafif() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func orta() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func secim() { UISelectionFeedbackGenerator().selectionChanged() }
    static func basari() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func uyari() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
