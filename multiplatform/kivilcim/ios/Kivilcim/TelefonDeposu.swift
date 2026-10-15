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

    private let kok = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Kivilcim")
    private var kayit: URL { KayitMerkezi.kayitKlasoru }
    private var olayDosyasi: URL { kok.appendingPathComponent("olay-iphone.jsonl") }
    private var dizinKopyasi: URL { kok.appendingPathComponent("dizin.json") }
    private var sinifKopyasi: URL { kok.appendingPathComponent("siniflar.json") }
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
        kur()
    }

    func oge(_ id: String) -> Oge? { ogeler.first { $0.id == id } }

    // MARK: Liste

    func kur() {
        siniflar = Siniflar.yukle(FileManager.default.fileExists(atPath: sinifKopyasi.path) ? sinifKopyasi : Bundle.main.url(forResource: "siniflar", withExtension: "json"))
        var liste = (try? JSONDecoder().decode(Dizin.self, from: Data(contentsOf: dizinKopyasi)))?.ogeler ?? []
        let bilinen = Set(liste.map(\.id))
        let g = gonderilen
        var bekleyen = 0
        for k in yerelKunyeler() {
            if g[k.id] == nil { bekleyen += 1 }
            guard !bilinen.contains(k.id) else { continue }
            let m4a = kayit.appendingPathComponent(k.id + ".m4a")
            var o = Oge(id: k.id, tarih: k.zaman, cihaz: k.cihaz, sure: k.sure, kalite: k.kalite,
                        boyut: (try? m4a.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0,
                        ses: "ses/\(k.zaman.prefix(7))/\(k.id).m4a", metin: k.onMetin ?? "",
                        baslik: "Sesli fikir · \(Zaman.saat(Zaman.coz(k.zaman) ?? Date()))",
                        durum: g[k.id] == nil ? "yerel" : "bekliyor")
            if let m = k.onMetin, !m.isEmpty {
                o.baslik = Kural.baslik(m, siniflar); o.alan = Kural.alan(m, siniflar); o.amac = Kural.amac(m, siniflar)
            }
            liste.append(o)
        }
        if let v = try? Data(contentsOf: olayDosyasi) { Olay.uygula(v, &liste) }
        ogeler = liste.sorted { $0.tarih > $1.tarih }
        gonderilmemis = bekleyen
        widgetiGuncelle()
    }

    private func yerelKunyeler() -> [Kunye] {
        ((try? FileManager.default.contentsOfDirectory(at: kayit, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(Kunye.self, from: Data(contentsOf: $0)) }
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
        let v = Olay.satir(hedef: o.id, tur: tur, deger: deger, cihaz: "iphone")
        if let h = try? FileHandle(forWritingTo: olayDosyasi) { h.seekToEndOfFile(); h.write(v); try? h.close() }
        else { try? v.write(to: olayDosyasi, options: .atomic) }
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
    func gonder() async {
        guard Kasa.shared.bagli, !esitleniyor else { return }
        esitleniyor = true
        defer { esitleniyor = false }
        let kayit = self.kayit, olay = olayDosyasi, dizinK = dizinKopyasi, sinifK = sinifKopyasi
        let g = gonderilen
        let sonuc: ([String: Int], Bool)? = await Kasa.shared.ile { veri in
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
            var cekildi = false
            let d = veri.appendingPathComponent("dizin.json")
            if Kasa.indir(d, bekle: 4), let v = Kasa.koordineliOku(d), (try? JSONDecoder().decode(Dizin.self, from: v)) != nil {
                try? v.write(to: dizinK, options: .atomic); cekildi = true
            }
            let s = veri.appendingPathComponent("siniflar.json")
            if Kasa.indir(s, bekle: 2), let v = Kasa.koordineliOku(s) { try? v.write(to: sinifK, options: .atomic) }
            return (yeni, cekildi)
        }
        if let (yeni, _) = sonuc {
            gonderilen = yeni
            sonEsitleme = Date()
        }
        kur()
    }

    /// Çalınacak dosya: telefondaysa oradan, değilse vault'tan önbelleğe indirilir.
    func sesURL(_ o: Oge) async -> URL? {
        let yerel = kayit.appendingPathComponent(o.id + ".m4a")
        if FileManager.default.fileExists(atPath: yerel.path) { return yerel }
        let ob = onbellek.appendingPathComponent(o.id + ".m4a")
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

    private func widgetiGuncelle() {
        let d = WidgetDurumu.d
        if let s = ogeler.first {
            d.set(s.baslik, forKey: "sonBaslik")
            d.set(siniflar.alan(s.alan).ad, forKey: "sonAlan")
            d.set(siniflar.alan(s.alan).renk, forKey: "sonRenk")
            d.set(s.zaman, forKey: "sonZaman")
        }
        d.set(ogeler.filter { Calendar.current.isDateInToday($0.zaman) }.count, forKey: "bugun")
        WidgetCenter.shared.reloadAllTimelines()
    }

    var toplamMB: Double { Double(ogeler.reduce(0) { $0 + $1.boyut }) / 1_000_000 }
    var toplamDakika: Int { Int(ogeler.reduce(0) { $0 + $1.sure } / 60) }
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
