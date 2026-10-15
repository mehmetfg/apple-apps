// Cümle — akış. Tezgâh v7'nin adım sırası AYNEN: oku (+ sesli oku) → cümle turu → paragraf → hatırlama testi
// → kendi cümlen → hesap. Sonuç JSON'u v7 alanlarını aynen taşır (gun.py sicil, tezgah_arsiv.py, oncalisma.py
// cozumle okur); yeni olan yalnız hazırlığın bitişte CANLI alınması ve telefona giden yazim.json.
import Foundation
import SwiftUI
import AppKit

// MARK: - Oturum durumu (iCloud'da: öteki Mac kaldığın yerden açar)

struct CumleYazim: Codable, Hashable {
    var metin: String; var yuzde: Int; var ayni: Int; var toplam: Int
    var atlanan: [String]; var fazladan: [String]; var ht: [String: Int]
}
struct Tur: Codable, Hashable {
    var i: Int; var konu: String; var baktim = false; var ipucu = 0; var tekrar = 0; var y: CumleYazim?
}
struct Soru: Codable, Hashable, Identifiable {
    var no: Int; var tip: String; var kaynak: String; var hedef: String; var cumleIdx: Int
    var once: String; var sonra: String; var cevap: String; var tr: String; var aciklama: String?
    var verilen: [String] = []; var sonuc: String?; var deneme = 0
    var id: Int { no }
}
struct Recall: Codable { var sorular: [Soru]; var j = 0; var bitti = false; var bakilan: Int? }
struct Hatirlatma: Codable, Hashable { var konular: [String]; var dongu: Int?; var gun: Int? }
struct Kendi: Codable, Hashable { var konu: String; var metin = ""; var sezildi = false; var yazim: [String] = [] }
struct Sesli: Codable { var kayit = 0; var sure_sn = 0; var tanima_yuzde: Int?; var okunan: Int?; var toplam: Int?; var takilan: [String]? }

enum Adim: String, Codable, CaseIterable, Identifiable {
    case oku, cumle, paragraf, recall, kendi, bitis
    var id: String { rawValue }
    var etiket: String {
        switch self {
        case .oku: "Oku ve dinle"; case .cumle: "Cümle turu"; case .paragraf: "Paragraf"
        case .recall: "Hatırlama testi"; case .kendi: "Kendi cümlen"; case .bitis: "Hesap"
        }
    }
    var simge: String {
        switch self {
        case .oku: "book"; case .cumle: "character.cursor.ibeam"; case .paragraf: "text.alignleft"
        case .recall: "questionmark.square.dashed"; case .kendi: "person.text.rectangle"; case .bitis: "checkmark.seal"
        }
    }
    var sira: Int { Adim.allCases.firstIndex(of: self)! }
}

struct Oturum: Codable {
    var gun: GunVeri
    var tarih: String
    var adim: Adim = .oku
    var i = 0
    var turlar: [Tur] = []
    var paragraf: CumleYazim?
    var paraOdak = 0
    var recall: Recall?
    var enIleri = 0
    var taslakI = -1
    var taslakCumle = ""
    var taslakParagraf = ""
    var hatirlatma: Hatirlatma?
    var tekrar = false
    var sesli: Sesli?
    var kendi: [Kendi]?
    var baslangic: Double = 0          // ms
    var sonDokunus: Double = 0
    var aktifMs: Double = 0
    var indi = false
    var dosya: String?
    var makine = Makine.ad

    func tur(_ i: Int) -> Tur? { turlar.first { $0.i == i } }
    var toplam: Int { gun.cumleler.count }
    func cumle(_ i: Int) -> GunCumle { i >= 0 && i < gun.cumleler.count ? gun.cumleler[i] : GunCumle(en: "") }
    var asil: String { gun.cumleler.map(\.en).joined(separator: " ") }
}

// MARK: - Tezgâh

@MainActor
final class Tezgah: ObservableObject {
    // kaynaklar
    @Published var gunMasa: GunVeri?            // açık gün: seçilen ya da çalışılmamış en küçük gün (Gunler.swift)
    @Published var tumGunler: [GunVeri] = []    // masa + oncalisma/paket/gun-NNN/gun.json
    @Published var secilenGun: Int?
    @Published var atlananGunler: Set<Int> = []
    @Published var arsiv = Arsiv()
    @Published var gramer: [GramerKart] = []
    let sozluk = Sozluk()
    @Published var sozlukHazir = false

    // oturum
    @Published var o: Oturum?
    @Published var gorunum: Gorunum = .bugun

    // telefon
    @Published var hazirlik = Hazirlik()
    @Published var rota: [Rota] = []
    @Published var kayitlar: [VaultKayit] = []

    // ekran
    @Published var ipucuAcik = false
    @Published var cumleAcik = false
    @Published var ipucuSabit: Bool { didSet { UserDefaults.standard.set(ipucuSabit, forKey: "ipucu.sabit") } }
    @Published var bildirim: String?
    @Published var kuizAcik = false
    @Published var gramerSayfa: [String]?
    @Published var gramerI = 0
    @Published var haritaAcik = true
    @Published var editorOdak = UUID()           // değişince yazma alanı odağı alır

    let ses = Ses()
    let calici = Calici()
    let kaydedici = Kaydedici()

    private var yerelGecmis: [[String: Any]] = []
    private var hatirYerel: [GunTarih] = []
    private var kayitZamani: Timer?
    private var tazeleZamani: Timer?
    private var gunTarihi: Date?
    private var arsivTarihi: Date?
    private var gorunurI = -1

    enum Gorunum: Hashable { case bugun, gecmis }

    var gramerMap: [String: GramerKart] { Dictionary(gramer.map { ($0.ad, $0) }, uniquingKeysWith: { a, _ in a }) }

    init() {
        ipucuSabit = UserDefaults.standard.bool(forKey: "ipucu.sabit")
        yukle()
        tazeleZamani = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tazele() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.tazele(hepsi: true) }
        }
    }

    // MARK: Yükleme

    func yukle() {
        try? FileManager.default.createDirectory(at: Yol.durum, withIntermediateDirectories: true)
        tumGunler = Gunler.tara(); gunTarihi = GunVeri.degisti
        gramer = Gramer.yukle()
        arsiv = Arsiv.yukle(); arsivTarihi = Tezgah.tarih(Yol.veri.appendingPathComponent("tezgah-arsiv.js"))
        yerelGecmis = (Tezgah.jsonOku(Yol.durum.appendingPathComponent("gecmis.json")) as? [[String: Any]]) ?? []
        hatirYukle()
        if let v = try? Data(contentsOf: Yol.durum.appendingPathComponent("oturum.json")),
           let x = try? JSONDecoder().decode(Oturum.self, from: v) {
            // bitmiş ve başka güne ait oturum açılışta kapanır (sonucu zaten indi); yarım olan sorulur
            // tekrar çalışma sicile girmez: yarım kalıp 6 saatten uzun dokunulmadıysa açılışı kilitlemesin
            let eskiTekrar = x.tekrar && !x.indi && Date().timeIntervalSince1970 * 1000 - x.sonDokunus > 6 * 3_600_000
            if !(x.indi && x.tarih != Gun.bugun) && !eskiTekrar { o = x }
        }
        let s = sozluk
        Task.detached(priority: .utility) {
            s.yukle()
            await MainActor.run { self.sozlukHazir = true }
        }
        tazele(hepsi: true)
    }

    static func tarih(_ u: URL) -> Date? { (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }
    static func jsonOku(_ u: URL) -> Any? { (try? Data(contentsOf: u)).flatMap { try? JSONSerialization.jsonObject(with: $0) } }

    /// Telefonun olayları, kayıtlar, sabah gelen yeni metin ve arşiv — birkaç saniyede bir.
    func tazele(hepsi: Bool = false) {
        let ol = OnCalisma.olaylar()
        let b = Set(ol.filter { $0.tur == "bitti" }.map(\.gun))
        if b != bittiGunler { bittiGunler = b }
        let atlanan = Set(ol.filter { $0.tur == "atladi" }.map(\.gun))
        if atlanan != atlananGunler { atlananGunler = atlanan }
        let at = Tezgah.tarih(Yol.veri.appendingPathComponent("tezgah-arsiv.js"))
        if at != arsivTarihi { arsivTarihi = at; arsiv = Arsiv.yukle() }
        let tum = Gunler.tara()
        if tum != tumGunler { tumGunler = tum }
        let acik = gunuCoz()
        if acik != gunMasa { gunMasa = acik }
        let g = o?.gun.no ?? gunMasa?.no ?? 0
        if g > 0 {
            let h = OnCalisma.durum(g, olaylar: ol)
            if h != hazirlik { hazirlik = h }
            let k = OnCalisma.kayitlar(g)
            if k.map(\.ad) != kayitlar.map(\.ad) { kayitlar = k }
            if hepsi || rota.isEmpty { rota = OnCalisma.yolHaritasi(gun: g - 1) }
        }
        if hepsi, o == nil || o?.makine != Makine.ad, let v = try? Data(contentsOf: Yol.durum.appendingPathComponent("oturum.json")),
           let x = try? JSONDecoder().decode(Oturum.self, from: v), x.sonDokunus > (o?.sonDokunus ?? 0) {
            o = x      // öteki Mac'te ilerlemiş oturum
        }
    }

    // MARK: Süre — dokunulan süre; 2 dk'dan uzun boşluk sayılmaz

    static let bosEsik: Double = 120_000
    func dokun() {
        guard o != nil else { return }
        let t = Date().timeIntervalSince1970 * 1000
        if o!.baslangic == 0 { o!.baslangic = t }
        if o!.sonDokunus > 0, t - o!.sonDokunus < Tezgah.bosEsik { o!.aktifMs += t - o!.sonDokunus }
        o!.sonDokunus = t
    }
    var aktifDk: Int { max(1, Int(((o?.aktifMs ?? 0) / 60000).rounded())) }
    var sureYazi: String {
        guard let o else { return "" }
        let t = Date().timeIntervalSince1970 * 1000
        let ms = o.aktifMs + (o.sonDokunus > 0 && t - o.sonDokunus < Tezgah.bosEsik ? t - o.sonDokunus : 0)
        return String(format: "%d:%02d", Int(ms / 60000), Int(ms.truncatingRemainder(dividingBy: 60000) / 1000))
    }

    /// Diske yazma — yarım saniye toplanır.
    func kaydet(hemen: Bool = false) {
        kayitZamani?.invalidate()
        let yaz = { [weak self] in
            guard let self else { return }
            let u = Yol.durum.appendingPathComponent("oturum.json")
            if let o = self.o, let v = try? JSONEncoder().encode(o) { _ = OnCalisma.koordineliYaz(v, u) }
        }
        if hemen { yaz() } else {
            kayitZamani = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in Task { @MainActor in yaz() } }
        }
    }

    func duyur(_ m: String) {
        bildirim = m
        let simdi = m
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in if self?.bildirim == simdi { self?.bildirim = nil } }
    }

    // MARK: Başlat

    func baslat(_ veri: GunVeri, tekrar: Bool = false, hatirlatma: Hatirlatma? = nil) {
        ses.dur()
        let t = Date().timeIntervalSince1970 * 1000
        var x = Oturum(gun: veri, tarih: Gun.bugun)
        x.baslangic = t; x.sonDokunus = t
        x.tekrar = tekrar
        x.hatirlatma = hatirlatma ?? hatirAta()
        o = x
        secilenGun = nil
        gorunum = .bugun
        if !tekrar, veri.no > 0, !OnCalisma.olaylar().contains(where: { $0.gun == veri.no && $0.cihaz == Makine.ad && $0.tur == "basladi" }) {
            OnCalisma.olay(veri.no, "basladi")
        }
        tazele(hepsi: true)
        kaydet(hemen: true)
    }

    func birak() {
        ses.dur(); o = nil
        try? FileManager.default.removeItem(at: Yol.durum.appendingPathComponent("oturum.json"))
    }

    /// Bugünün metni çalışıldı mı (arşivde ya da yerel geçmişte).
    func calisildi(_ g: GunVeri) -> ArsivGun? {
        if let a = gecmis().first(where: { $0.gun == g.no && !g.cumleler.isEmpty }) { return a }
        // tarayıcıdaki Tezgâh'ta ya da öteki Mac'te bitirilmiş, sabah görevi henüz işlememiş gün: "bitti" olayı
        if bittiGunler.contains(g.no) { return ArsivGun(["gun": g.no, "tarih": "", "baslik": g.baslik ?? ""]) }
        return nil
    }
    @Published var bittiGunler: Set<Int> = []

    // MARK: Adımlar

    func adimaGit(_ a: Adim) {
        guard var x = o, a.sira <= x.enIleri || a == x.adim else { return }
        ses.dur()
        switch a {
        case .paragraf: paragrafBasla(); return
        case .recall: recallBasla(); return
        case .kendi: kendiBasla(); return
        case .bitis: bitis(); return
        default: break
        }
        x.adim = a
        x.enIleri = max(x.enIleri, a.sira)
        o = x
        if a == .cumle { cumleGit(x.i) }
        kaydet()
    }
    private func ac(_ a: Adim) {
        o?.adim = a
        o?.enIleri = max(o?.enIleri ?? 0, a.sira)
    }
    func sayac(_ a: Adim) -> String {
        guard let o else { return "" }
        switch a {
        case .cumle: return "\(o.turlar.filter { $0.y != nil }.count)/\(o.toplam)"
        case .paragraf: return o.paragraf.map { "%\($0.yuzde)" } ?? ""
        case .recall: return o.recall.map { r in "\(r.sorular.filter { $0.sonuc != nil }.count)/\(r.sorular.count)" } ?? ""
        case .kendi: return o.kendi.map { k in "\(k.filter { !$0.metin.trimmingCharacters(in: .whitespaces).isEmpty }.count)/\(k.count)" } ?? ""
        default: return ""
        }
    }

    // MARK: Cümle turu

    func cumleGit(_ i: Int) {
        guard o != nil else { return }
        if o!.adim != .cumle { ac(.cumle) }
        o!.i = max(0, min(i, o!.toplam - 1))
        if gorunurI != o!.i {
            gorunurI = o!.i
            cumleAcik = false
            ipucuAcik = ipucuSabit && (o!.tur(o!.i)?.ipucu ?? 0) > 0
        }
        editorOdak = UUID()
        kaydet()
    }

    private func turAl() -> Int {
        let i = o!.i
        if let k = o!.turlar.firstIndex(where: { $0.i == i }) { return k }
        o!.turlar.append(Tur(i: i, konu: o!.cumle(i).konu ?? ""))
        return o!.turlar.count - 1
    }
    func ipucuSeviye(_ i: Int) -> Int { guard let t = o?.tur(i) else { return 0 }; return t.baktim ? 3 : min(2, t.ipucu) }

    func ipucuTikla() {
        guard o?.adim == .cumle else { return }
        let k = turAl(); guard o!.turlar[k].y == nil else { return }
        if o!.turlar[k].ipucu == 0 { o!.turlar[k].ipucu = 1; ipucuAcik = true } else { ipucuAcik.toggle() }
        kaydet()
    }
    func ipucuDaha() {
        let k = turAl(); guard o!.turlar[k].y == nil else { return }
        o!.turlar[k].ipucu = min(2, o!.turlar[k].ipucu + 1); ipucuAcik = true
        kaydet()
    }
    func cumleTikla() {
        guard o?.adim == .cumle else { return }
        let k = turAl(); guard o!.turlar[k].y == nil else { return }
        cumleAcik.toggle()
        if cumleAcik { o!.turlar[k].baktim = true }
        kaydet()
    }
    /// Yazmaya başlayınca göz atma kapanır — cevap ekranda durup kopyalanmasın.
    func yaziyor(_ metin: String) {
        dokun()
        o?.taslakI = o?.i ?? -1; o?.taslakCumle = metin
        if !ipucuSabit, ipucuAcik || cumleAcik { ipucuAcik = false; cumleAcik = false }
        kaydet()
    }

    func cumleTamamla(_ metin: String) {
        let m = metin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !m.isEmpty, o != nil else { return }
        let c = o!.cumle(o!.i)
        let f = Metin.fark(c.en, m)
        let k = turAl()
        o!.turlar[k].y = CumleYazim(metin: m, yuzde: f.yuzde, ayni: f.ayni, toplam: f.toplam, atlanan: f.atlanan, fazladan: f.fazladan,
                                    ht: Metin.hataTurleri(f.atlanan, f.fazladan))
        o!.taslakI = -1; o!.taslakCumle = ""
        ipucuAcik = false; cumleAcik = false
        dokun()
        ses.soyle(c.en, zorla: false, cumle: o!.i)
        kaydet()
    }
    func tekrarDene() {
        guard let x = o, let k = x.turlar.firstIndex(where: { $0.i == x.i }) else { return }
        o!.turlar[k].y = nil
        o!.turlar[k].tekrar += 1      // serbest ama iz bırakır — sicil "ilk seferde tuttu" sanmasın
        gorunurI = -1
        cumleGit(x.i)
    }
    func ileri() {
        guard let x = o else { return }
        if x.i >= x.toplam - 1 { paragrafBasla() } else { cumleGit(x.i + 1) }
    }

    // MARK: Paragraf

    func paragrafBasla() {
        guard o != nil else { return }
        ses.dur()
        ac(.paragraf)
        editorOdak = UUID()
        kaydet()
    }
    func paraYaziyor(_ metin: String) {
        dokun()
        o?.taslakParagraf = metin
        // nokta/soru/ünlem sayısı arttıkça odak kendiliğinden ilerler; geri gitmez
        let say = (try? NSRegularExpression(pattern: "[.!?]+(?=\\s|$)"))?.numberOfMatches(in: metin, range: NSRange(location: 0, length: (metin as NSString).length)) ?? 0
        let hedef = min(say, (o?.toplam ?? 1) - 1)
        if hedef > (o?.paraOdak ?? 0) { o?.paraOdak = hedef }
        kaydet()
    }
    /// Yazılan asılın yarısından azsa önce sorulur (`zorla` = "yine de bitir").
    func paragrafBitir(_ metin: String, zorla: Bool = false) -> Double? {
        let m = metin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !m.isEmpty, let x = o else { duyur("Önce paragrafı yaz"); return nil }
        let oran = Double(Metin.kelimeler(m).count) / Double(max(1, Metin.kelimeler(x.asil).count))
        if oran < 0.5 && !zorla { return oran }
        let f = Metin.fark(x.asil, m)
        o!.paragraf = CumleYazim(metin: m, yuzde: f.yuzde, ayni: f.ayni, toplam: f.toplam, atlanan: f.atlanan, fazladan: f.fazladan,
                                 ht: Metin.hataTurleri(f.atlanan, f.fazladan))
        o!.taslakParagraf = ""
        dokun(); kaydet()
        return nil
    }

    // MARK: Hatırlama testi — hepsi boşluk doldurma, seçenek yok

    func hedefKumeleri() -> (yeni: Set<String>, yanki: Set<String>, tanidik: Set<String>) {
        let g = o?.gun
        return (Set((g?.yeni ?? []).map(Metin.sadele)), Set((g?.yanki ?? []).map(Metin.sadele)), Set((g?.tanidik ?? []).map(Metin.sadele)))
    }

    private func kelimeSorusu(_ kok: String, _ kaynak: String, _ kullanilan: inout Set<String>) -> Soru? {
        guard let x = o, !kullanilan.contains(kok) else { return nil }
        for i in 0..<x.toplam {
            let c = x.cumle(i)
            for (m, r) in Metin.araliklar(c.en) {
                let s = Metin.sadele(m)
                if s == kok || Metin.govdeler(s).contains(kok) {
                    kullanilan.insert(kok)
                    return Soru(no: 0, tip: "kelime", kaynak: kaynak, hedef: kok, cumleIdx: i, once: c.en.u16(0, r.location),
                                sonra: c.en.u16(r.location + r.length), cevap: m, tr: c.tr ?? "")
                }
            }
        }
        return nil
    }
    private func yapiSorusu(_ i: Int, _ kullanilan: inout Set<String>) -> Soru? {
        let c = o!.cumle(i)
        let g = Sezici.tespit(c.en)
        guard let p = g.parca, let ix = g.indis, !kullanilan.contains("y\(i)") else { return nil }
        kullanilan.insert("y\(i)")
        return Soru(no: 0, tip: "yapı", kaynak: "yapı", hedef: g.etiket, cumleIdx: i, once: c.en.u16(0, ix),
                    sonra: c.en.u16(ix + (p as NSString).length), cevap: p, tr: c.tr ?? "", aciklama: g.aciklama)
    }

    func recallUret() -> [Soru] {
        guard let x = o else { return [] }
        var kul = Set<String>(), sorular: [Soru] = []
        let (yeni, yanki, tanidik) = hedefKumeleri()
        for (w, _) in zorKelimeler() where sorular.count < 4 { if let s = kelimeSorusu(w, "kaçırdığın", &kul) { sorular.append(s) } }
        let skorlu = x.turlar.sorted { ($0.y?.yuzde ?? 100) < ($1.y?.yuzde ?? 100) }
        var yapiSayi = 0
        for t in skorlu where yapiSayi < 2 { if let s = yapiSorusu(t.i, &kul) { sorular.append(s); yapiSayi += 1 } }
        // JS Set'leri ekleme sırasını korur: aynı sıra, aynı sorular
        func sirali(_ l: [String]?) -> [String] { var g = Set<String>(); return (l ?? []).map(Metin.sadele).filter { g.insert($0).inserted } }
        for w in sirali(x.gun.yeni) + sirali(x.gun.tanidik) + sirali(x.gun.yanki) where sorular.count < 8 {
            if let s = kelimeSorusu(w, yeni.contains(w) ? "yeni" : tanidik.contains(w) ? "tanıdık" : "yankı", &kul) { sorular.append(s) }
        }
        func aday(_ en: String) -> [String] {
            Metin.kelimeler(en).map(Metin.sadele).filter { $0.count > 3 && !Metin.dolguDisi.contains($0) && !kul.contains($0) }
        }
        for t in skorlu where sorular.count < 6 {
            let a = aday(x.cumle(t.i).en)
            if !a.isEmpty, let s = kelimeSorusu(a[a.count / 2], "metin", &kul) { sorular.append(s) }
        }
        var i = 0
        while i < x.toplam && sorular.count < 6 {
            let a = aday(x.cumle(i).en)
            if let w = a.first, let s = kelimeSorusu(w, "metin", &kul) { sorular.append(s) }
            i += 1
        }
        // yapı soruları araya dağılsın
        let kel = sorular.filter { $0.tip == "kelime" }
        var yap = sorular.filter { $0.tip == "yapı" }
        var karisik: [Soru] = []
        for (n, s) in kel.enumerated() {
            karisik.append(s)
            if !yap.isEmpty && (n == 1 || n == 4) { karisik.append(yap.removeFirst()) }
        }
        karisik += yap
        return karisik.prefix(8).enumerated().map { var s = $0.element; s.no = $0.offset + 1; return s }
    }

    func recallBasla() {
        guard o != nil else { return }
        ses.dur()
        if (o!.recall?.sorular ?? []).isEmpty {
            let s = recallUret()
            if s.count < 3 { duyur("Test kurulamadı — kendi cümlene geçiliyor"); kendiBasla(); return }
            o!.recall = Recall(sorular: s)
        }
        ac(.recall)
        editorOdak = UUID()
        kaydet()
    }
    func recallYenidenKur() { o?.recall = nil; recallBasla() }

    static func recallDegerlendir(_ s: Soru, _ verilen: String) -> String {
        if verilen.trimmingCharacters(in: .whitespaces).isEmpty { return "yok" }
        if s.tip == "yapı" {
            let a = Metin.kelimeler(s.cevap).map(Metin.sadele), b = Metin.kelimeler(verilen).map(Metin.sadele)
            if a == b { return "tam" }
            let kume = Set(a)
            return b.filter { kume.contains($0) }.count >= Int((Double(a.count) / 2).rounded(.up)) ? "kismi" : "yok"
        }
        let v = Metin.sadele(verilen), d = Metin.sadele(s.cevap)
        if v == d { return "tam" }
        let gv = Set([v] + Metin.govdeler(v))
        return ([d] + Metin.govdeler(d)).contains { gv.contains($0) } ? "kismi" : "yok"
    }

    /// Dönen: nil = sonuç verildi; "bir kez daha" = ilk deneme tutmadı (ilk harf açılır).
    @discardableResult
    func recallKontrol(_ verilen: String, pas: Bool = false) -> String? {
        guard var r = o?.recall, r.j < r.sorular.count else { return nil }
        var s = r.sorular[r.j]
        s.deneme += 1
        s.verilen.append(verilen)
        let h = pas ? "yok" : Tezgah.recallDegerlendir(s, verilen)
        dokun()
        if h != "tam" && s.deneme == 1 && !pas {
            s.sonuc = nil; r.sorular[r.j] = s; o!.recall = r; kaydet()
            return h == "kismi" ? "Yakın — biçimi düzelt" : "Olmadı, bir kez daha"
        }
        s.sonuc = h; r.sorular[r.j] = s; o!.recall = r
        ses.soyle(o!.cumle(s.cumleIdx).en, zorla: false)
        kaydet()
        return nil
    }
    func recallSonraki() {
        guard o?.recall != nil else { return }
        o!.recall!.bakilan = nil
        o!.recall!.j += 1
        if o!.recall!.j >= o!.recall!.sorular.count { o!.recall!.bitti = true }
        editorOdak = UUID()
        kaydet()
    }

    func recallOzeti() -> [String: Int]? {
        guard let r = o?.recall, !r.sorular.isEmpty else { return nil }
        let tam = r.sorular.filter { $0.sonuc == "tam" }.count, kismi = r.sorular.filter { $0.sonuc == "kismi" }.count
        let ilk = r.sorular.filter { $0.sonuc == "tam" && $0.deneme == 1 }.count
        let n = r.sorular.count
        let puan: Double = Double(tam) + Double(kismi) * 0.5
        let yuzde: Int = Int((100.0 * puan / Double(n)).rounded())
        let yok: Int = n - tam - kismi
        return ["toplam": n, "tam": tam, "kismi": kismi, "yok": yok, "ilk_denemede": ilk, "yuzde": yuzde]
    }

    // MARK: Kendi cümlen — atlanabilir

    func kendiBasla() {
        guard o != nil else { return }
        ses.dur()
        if o!.kendi == nil { o!.kendi = (o!.hatirlatma ?? hatirAta()).konular.map { Kendi(konu: $0) } }
        ac(.kendi)
        kaydet()
    }
    func kendiYaz(_ n: Int, _ metin: String) {
        guard o?.kendi != nil, n < o!.kendi!.count else { return }
        o!.kendi![n].metin = metin
        kendiDegerlendir(n)
        dokun(); kaydet()
    }
    func kendiDegerlendir(_ n: Int) {
        guard let k = o?.kendi?[n] else { return }
        let m = k.metin.trimmingCharacters(in: .whitespacesAndNewlines)
        var sez = false
        if !m.isEmpty, let g = gramerMap[k.konu], let re = try? NSRegularExpression(pattern: g.desen, options: [.caseInsensitive]) {
            sez = re.firstMatch(in: m, range: NSRange(location: 0, length: (m as NSString).length)) != nil
        }
        o!.kendi![n].sezildi = sez
        o!.kendi![n].yazim = Metin.kelimeler(m).filter { !sozluk.dogruMu($0) }
    }
    func kendiKopya(_ k: Kendi) -> Bool {
        guard let g = gramerMap[k.konu] else { return false }
        let m = k.metin.trimmingCharacters(in: .whitespacesAndNewlines)
        let sade = { (s: String) in s.lowercased().filter { $0.isLetter || $0.isNumber } }
        return g.ornek.contains { Metin.sadele($0.first ?? "") == Metin.sadele(m) || sade($0.first ?? "") == sade(m) }
    }

    // MARK: Hesaplar

    private func kelimeSayimi(_ fazla: Bool) -> [(String, Int)] {
        guard let x = o else { return [] }
        let (y, e, t) = hedefKumeleri()
        let hedef = y.union(e).union(t)
        var say: [String: Int] = [:], sira: [String] = []
        func bak(_ l: [String]) {
            for w in l {
                var k: String?
                if !hedef.isEmpty { k = Metin.hedefe(w, hedef) }
                else { let s = Metin.sadele(w); if s.count > 2 && !Metin.dolguDisi.contains(s) { k = s } }
                if let k { if say[k] == nil { sira.append(k) }; say[k, default: 0] += 1 }
            }
        }
        for t in x.turlar { if let yz = t.y { bak(fazla ? yz.fazladan : yz.atlanan) } }
        if let p = x.paragraf { bak(fazla ? p.fazladan : p.atlanan) }
        return sira.map { ($0, say[$0]!) }.enumerated().sorted { a, b in a.element.1 != b.element.1 ? a.element.1 > b.element.1 : a.offset < b.offset }
            .map(\.element).prefix(12).map { $0 }
    }
    func zorKelimeler() -> [(String, Int)] { kelimeSayimi(false) }
    func fazlaKelimeler() -> [(String, Int)] { kelimeSayimi(true) }

    func yapiSkorlari() -> [[String: Any]] {
        guard let x = o else { return [] }
        return x.gun.sahne.compactMap { k in
            let ilgili = x.turlar.filter { $0.konu == k && $0.y != nil }
            guard !ilgili.isEmpty else { return nil }
            let p = ilgili.compactMap { $0.y?.yuzde }
            return ["konu": k, "cumle": ilgili.count, "bakilan": ilgili.filter(\.baktim).count,
                    "skor": p.isEmpty ? NSNull() : Int((Double(p.reduce(0, +)) / Double(p.count)).rounded())]
        }
    }
    func oturumHT() -> [String: Int] {
        var t: [String: Int] = [:]
        for x in o?.turlar ?? [] { for (k, v) in x.y?.ht ?? [:] { t[k, default: 0] += v } }
        return t
    }
    var cumleOrt: Int? {
        let p = (o?.turlar ?? []).compactMap { $0.y?.yuzde }
        return p.isEmpty ? nil : Int((Double(p.reduce(0, +)) / Double(p.count)).rounded())
    }

    // MARK: Bitiş

    func bitis() {
        guard o != nil else { return }
        ses.dur()
        ac(.bitis)
        guard !o!.indi else { kaydet(); return }
        o!.indi = true
        let g = o!.gun.no
        if !o!.tekrar && g > 0 {
            tazele()                                   // hazırlık bitişte CANLI alınır
            if !OnCalisma.olaylar().contains(where: { $0.gun == g && $0.cihaz == Makine.ad && $0.tur == "bitti" }) {
                OnCalisma.olay(g, "bitti")
            }
            yazimYaz()
            hatirKaydet()
        }
        sonucYaz()
        if !o!.tekrar { gecmisKaydet() }
        kaydet(hemen: true)
    }

    var dosyaAdi: String {
        guard let x = o else { return "" }
        return "\(x.tarih)-gun\(x.gun.gun.map(String.init) ?? "")\(x.tekrar ? "-tekrar" : "")-tezgah.json"
    }

    /// Sonuç JSON'u Downloads'a — sabah görevi oradan alıp sicile işler (akış değişmedi, diyalog yok).
    @discardableResult
    func sonucYaz() -> URL? {
        guard o != nil else { return nil }
        let u = Yol.indir.appendingPathComponent(dosyaAdi)
        guard let v = try? JSONSerialization.data(withJSONObject: jsonUret(), options: [.prettyPrinted, .sortedKeys]) else { return nil }
        do { try v.write(to: u, options: .atomic); o!.dosya = u.path; return u }
        catch { duyur("Sonuç yazılamadı: \(error.localizedDescription)"); return nil }
    }

    func jsonUret() -> [String: Any] {
        guard let x = o else { return [:] }
        let g = x.gun
        let rc = recallOzeti()
        let n = { (v: Any?) -> Any in v ?? NSNull() }
        let iso = { (ms: Double) -> Any in ms > 0 ? Gun.iso.string(from: Date(timeIntervalSince1970: ms / 1000)) : NSNull() }
        let cumleler: [[String: Any]] = x.turlar.filter { $0.y != nil }.sorted { $0.i < $1.i }.map { t in
            let c = x.cumle(t.i), y = t.y!, gr = Sezici.tespit(c.en)
            return ["no": t.i + 1, "referans": c.en, "tr": c.tr ?? "", "kip": "tr", "konu": t.konu,
                    "gramer_etiketi": gr.etiket, "gramer_guven": gr.guven, "baktim": t.baktim, "tekrar": t.tekrar,
                    "turlar": [["tur": 1, "metin": y.metin, "tutan": y.ayni, "toplam": y.toplam, "yuzde": y.yuzde,
                                "atlanan": y.atlanan, "fazladan": y.fazladan]],
                    "ipucu": ipucuSeviye(t.i), "hata_turleri": y.ht]
        }
        var ip: [String: Int] = ["0": 0, "1": 0, "2": 0, "3": 0]
        for c in cumleler { ip[String(c["ipucu"] as? Int ?? 0), default: 0] += 1 }
        let par: Any = x.paragraf.map { p -> [String: Any] in
            ["metin": p.metin, "yuzde": p.yuzde, "ayni": p.ayni, "toplam": p.toplam, "atlanan": p.atlanan, "fazladan": p.fazladan]
        } ?? NSNull()
        let recall: Any = x.recall.map { r -> [String: Any] in
            ["ozet": n(rc), "sorular": r.sorular.map { s -> [String: Any] in
                ["no": s.no, "tip": s.tip, "kaynak": s.kaynak, "hedef": s.hedef, "cumle_no": s.cumleIdx + 1,
                 "bosluk": s.once + "____" + s.sonra, "cevap": s.cevap, "verilen": s.verilen, "sonuc": n(s.sonuc), "deneme": s.deneme]
            }]
        } ?? NSNull()
        let hz: Any = (x.tekrar || g.no == 0) ? NSNull() : hazirlik.json
        let rotaJ = rota.map { ["tur": $0.tur, "sayi": $0.sayi, "gun": $0.gun, "not": $0.not] }
        let sure: Any = x.aktifMs > 0 ? aktifDk : NSNull()
        let duvar: Any = (x.baslangic > 0 && x.sonDokunus > 0) ? Int(((x.sonDokunus - x.baslangic) / 60000).rounded()) : NSNull()
        let h = x.hatirlatma
        return [
            "uygulama": "Cümle (Mac)", "surum": 8, "alt_surum": "8.0",
            "tarih": x.tarih, "gun": n(g.gun), "faz": n(g.faz), "baslik": g.baslik ?? "", "tema": g.tema ?? "",
            "sahne_konulari": g.sahne, "yeni": g.yeni ?? [], "yanki": g.yanki ?? [],
            "baslangic": iso(x.baslangic), "bitis": iso(x.sonDokunus), "sure_dk": sure, "sure_duvar_dk": duvar,
            "yazim_sayisi": 1, "cumleler": cumleler, "paragraf": par, "mod": g.mod ?? "kelime",
            "yapi_skorlari": yapiSkorlari(),
            "zor_kelimeler": zorKelimeler().map { ["kelime": $0.0, "hata": $0.1] },
            "fazladan_kelimeler": fazlaKelimeler().map { ["kelime": $0.0, "kez": $0.1] },
            "recall": recall, "kelimeler": [Any](),
            "sonraki_adim": "Yazma sicilini güncelle: gun.py sicil <bu dosya>. zor_kelimeler ve recall.sorular[sonuc!=tam] yarının yankısına girer.",
            "hazirlik": hz,
            "giris": (!x.tekrar && (hazirlik.dinleme > 0 || hazirlik.okuma)) ? "hazirlikli" : "klasik",
            "yol_haritasi": rotaJ, "ozet": g.ozet ?? "", "tanidik": g.tanidik ?? [], "tekrar": x.tekrar,
            "ipucu_ozeti": ip, "hata_turleri": oturumHT(),
            "hatirlatma": h?.konular ?? [],
            "hatirlatma_dongu": h?.dongu != nil ? ["dongu": h!.dongu!, "gun": n(h!.gun)] : NSNull(),
            "kendi_cumleler": (x.kendi ?? []).filter { !$0.metin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map { ["konu": $0.konu, "metin": $0.metin.trimmingCharacters(in: .whitespacesAndNewlines), "sezildi": $0.sezildi, "yazim": $0.yazim] },
            "sesli_okuma": x.sesli.map { s -> [String: Any] in
                var j: [String: Any] = ["kayit": s.kayit, "sure_sn": s.sure_sn]
                if let v = s.tanima_yuzde { j["tanima_yuzde"] = v }; if let v = s.okunan { j["okunan"] = v }
                if let v = s.toplam { j["toplam"] = v }; if let v = s.takilan { j["takilan"] = v }
                return j
            } ?? NSNull(),
        ]
    }

    /// Telefona aynı gün giden özet — cozum.json biçiminde (Memories ikisini aynı okur; sabahki cozum.json üstüne geçer).
    func yazimYaz() {
        guard let x = o, x.gun.no > 0 else { return }
        let yazilan = x.turlar.filter { $0.y != nil }.sorted { $0.i < $1.i }
        guard !yazilan.isEmpty else { return }
        let ilk = yazilan.map { $0.y!.yuzde }
        let isabet = yazilan.filter { $0.y!.yuzde == 100 }
        let kendinden = yazilan.filter { ipucuSeviye($0.i) < 3 && !$0.baktim }
        func duz(_ t: Tur) -> [String: Any] {
            ["yazdigin": t.y!.metin, "dogrusu": x.cumle(t.i).en, "tr": x.cumle(t.i).tr ?? "", "yuzde": t.y!.yuzde]
        }
        let zayif = yazilan.filter { $0.y!.yuzde < 100 }.sorted { $0.y!.yuzde < $1.y!.yuzde }
        var j: [String: Any] = [
            "gun": x.gun.no, "baslik": x.gun.baslik ?? "", "zaman": Gun.isoSaniye.string(from: Date()), "kaynak": "mac",
            "yazim": ["ilk_yazim_ort": Int((Double(ilk.reduce(0, +)) / Double(ilk.count)).rounded()), "cumle": yazilan.count,
                      "tam_isabet": isabet.count, "kendinden": kendinden.count, "hata_turleri": oturumHT(), "sure_dk": aktifDk],
            "zorlar": zayif.prefix(3).map(duz),
            "yol_haritasi": rota.map { ["tur": $0.tur, "sayi": $0.sayi, "gun": $0.gun, "not": $0.not] },
        ]
        if let z = zayif.first { j["duzeltme"] = duz(z) }
        if let e = isabet.first(where: { ipucuSeviye($0.i) < 3 }) ?? isabet.first {
            j["en_iyi"] = ["en": x.cumle(e.i).en, "tr": x.cumle(e.i).tr ?? ""]
        }
        if let v = try? JSONSerialization.data(withJSONObject: j, options: [.prettyPrinted, .sortedKeys]) {
            _ = OnCalisma.koordineliYaz(v, Yol.paketKlasoru(x.gun.no).appendingPathComponent("yazim.json"))
        }
    }

    // MARK: Geçmiş (arşiv + sabah görevi işleyene kadar yerel özet)

    private func ozetle(_ j: [String: Any]) -> [String: Any] {
        let cum: [[String: Any]] = (j["cumleler"] as? [[String: Any]] ?? []).map { c in
            let t = (c["turlar"] as? [[String: Any]])?.last ?? [:]
            return ["no": c["no"] ?? 0, "en": c["referans"] ?? "", "tr": c["tr"] ?? "", "konu": c["konu"] ?? "", "yazim": t["metin"] ?? "",
                    "yuzde": t["yuzde"] ?? NSNull(), "baktim": c["baktim"] ?? false, "ipucu": c["ipucu"] ?? 0, "ht": c["hata_turleri"] ?? [:]]
        }
        let yz = cum.compactMap { $0["yuzde"] as? Int }
        let rc = j["recall"] as? [String: Any]
        return ["gun": j["gun"] ?? 0, "tarih": j["tarih"] ?? "", "surum": 8, "baslik": j["baslik"] ?? "", "tema": j["tema"] ?? "",
                "ozet": j["ozet"] ?? "", "mod": j["mod"] ?? "", "faz": j["faz"] ?? NSNull(), "sahne": j["sahne_konulari"] ?? [],
                "yeni": j["yeni"] ?? [], "yanki": j["yanki"] ?? [], "tanidik": j["tanidik"] ?? [],
                "sure_dk": (j["sure_dk"] as? Int).map { $0 <= 90 ? $0 as Any : NSNull() } ?? NSNull(),
                "tutma": yz.isEmpty ? NSNull() : Int((Double(yz.reduce(0, +)) / Double(yz.count)).rounded()),
                "paragraf": (j["paragraf"] as? [String: Any]).map { ["metin": $0["metin"] ?? "", "yuzde": $0["yuzde"] ?? NSNull()] } ?? NSNull(),
                "recall": rc.map { ["ozet": $0["ozet"] ?? NSNull(), "sorular": ($0["sorular"] as? [[String: Any]] ?? []).map {
                    ["bosluk": $0["bosluk"] ?? "", "cevap": $0["cevap"] ?? "", "verilen": $0["verilen"] ?? [], "sonuc": $0["sonuc"] ?? NSNull(), "tip": $0["tip"] ?? ""]
                }] } ?? NSNull(),
                "zor": (j["zor_kelimeler"] as? [[String: Any]] ?? []).compactMap { $0["kelime"] },
                "cumleler": cum, "hata_turleri": j["hata_turleri"] ?? [:], "hatirlatma": j["hatirlatma"] ?? [],
                "kendi": j["kendi_cumleler"] ?? [], "ipucu": j["ipucu_ozeti"] ?? NSNull()]
    }
    private func gecmisKaydet() {
        guard let x = o else { return }
        var l = yerelGecmis.filter { !($0.i("gun") == x.gun.no && $0.s("tarih") == x.tarih) }
        l.append(ozetle(jsonUret()))
        yerelGecmis = Array(l.suffix(40))
        if let v = try? JSONSerialization.data(withJSONObject: yerelGecmis) { _ = OnCalisma.koordineliYaz(v, Yol.durum.appendingPathComponent("gecmis.json")) }
    }
    func gecmis() -> [ArsivGun] {
        var m: [String: ArsivGun] = [:]
        for g in arsiv.gunler { m[g.id] = g }
        for g in yerelGecmis.map({ ArsivGun($0, yerel: true) }) where m[g.id] == nil { m[g.id] = g }
        return m.values.sorted { $0.gun != $1.gun ? $0.gun > $1.gun : $0.tarih > $1.tarih }
    }
    func seri(_ gunler: [ArsivGun]) -> Int {
        let t = Set(gunler.map(\.tarih))
        var d = Date(), n = 0
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"
        if !t.contains(f.string(from: d)) { d = d.addingTimeInterval(-86400) }
        while t.contains(f.string(from: d)) { n += 1; d = d.addingTimeInterval(-86400) }
        return n
    }

    func yenidenCalis(_ g: ArsivGun) {
        let v = GunVeri(gun: g.gun, mod: g.mod, faz: g.faz, baslik: g.baslik, tema: g.tema, ozet: g.ozet, sahne_konulari: g.sahne,
                        cumleler: g.cumleler.map { GunCumle(en: $0.en, tr: $0.tr, konu: $0.konu.isEmpty ? nil : $0.konu) },
                        yeni: g.yeni, yanki: g.yanki, tanidik: g.tanidik)
        baslat(v, tekrar: true, hatirlatma: g.hatirlatma.isEmpty ? nil : Hatirlatma(konular: g.hatirlatma, dongu: nil, gun: nil))
        duyur("Gün \(g.gun) tekrar çalışma olarak açıldı — sicile işlenmez")
    }

    // MARK: Gramer hatırlatma döngüsü — 60 yuva = 30 çalışma günü × 2 konu; takvime değil çalışılan güne bağlı

    static let yuva = 60
    private func hatirYukle() {
        var l: [GunTarih] = []
        if let a = Tezgah.jsonOku(Yol.durum.appendingPathComponent("hatir.json")) as? [[String: Any]] { l += a.map(GunTarih.init) }
        // tarayıcıdaki Tezgâh'ın yerel listesi (sicile işlenmemiş günler için) — bir kez devralınır
        if let d = Tezgah.jsonOku(Yol.vault.appendingPathComponent("Artifacts/_ortak/durum/tezgah.hatir.json")) as? [String: Any],
           let s = d["deger"] as? String, let a = (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [[String: Any]] {
            for x in a.map(GunTarih.init) where !l.contains(where: { $0.anahtar == x.anahtar }) { l.append(x) }
        }
        hatirYerel = l
    }
    private func hatirGecmis() -> [GunTarih] {
        var m: [String: GunTarih] = [:]
        for g in arsiv.gunler where !g.hatirlatma.isEmpty { m["\(g.gun)|\(g.tarih)"] = GunTarih(gun: g.gun, tarih: g.tarih, konular: g.hatirlatma) }
        for h in hatirYerel where m[h.anahtar] == nil { m[h.anahtar] = h }
        return m.values.sorted { $0.tarih != $1.tarih ? $0.tarih < $1.tarih : ($0.gun ?? 0) < ($1.gun ?? 0) }
    }
    private func zayiflar() -> [String] {
        arsiv.kurmaYapilar.compactMap { ad, g -> (String, Double)? in
            let s = g.compactMap(\.skor)
            guard !s.isEmpty, gramerMap[ad] != nil else { return nil }
            return (ad, (Double(s.reduce(0, +)) / Double(s.count)).rounded())
        }.sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0 < $1.0 }.map(\.0)
    }
    func hatirSira() -> [String] {
        let konular = gramer.map(\.ad)
        var tekrar: [String] = []
        func ekle(_ ad: String) { if tekrar.count < Tezgah.yuva - konular.count && !tekrar.contains(ad) { tekrar.append(ad) } }
        gramer.filter(\.yildiz).forEach { ekle($0.ad) }
        zayiflar().forEach(ekle)
        gramer.forEach { ekle($0.ad) }
        return konular + tekrar
    }
    struct DonguDurum { var duz: [String]; var n: Int; var dongu: Int; var konum: Int; var gun: Int; var buDongu: [String]; var sira: [String] }
    func hatirDurum() -> DonguDurum {
        let duz = hatirGecmis().flatMap(\.konular)
        let n = duz.count, konum = n % Tezgah.yuva
        return DonguDurum(duz: duz, n: n, dongu: n / Tezgah.yuva + 1, konum: konum, gun: konum / 2 + 1, buDongu: Array(duz.suffix(konum)), sira: hatirSira())
    }
    func hatirAta() -> Hatirlatma {
        let d = hatirDurum()
        guard !d.sira.isEmpty else { return Hatirlatma(konular: [], dongu: d.dongu, gun: d.gun) }
        return Hatirlatma(konular: [d.sira[d.konum % d.sira.count], d.sira[(d.konum + 1) % d.sira.count]], dongu: d.dongu, gun: d.gun)
    }
    private func hatirKaydet() {
        guard let x = o, let h = x.hatirlatma, !x.tekrar else { return }
        let a = "\(x.gun.no)|\(x.tarih)"
        guard !hatirYerel.contains(where: { $0.anahtar == a }),
              !arsiv.gunler.contains(where: { $0.gun == x.gun.no && $0.tarih == x.tarih && !$0.hatirlatma.isEmpty }) else { return }
        hatirYerel.append(GunTarih(gun: x.gun.no, tarih: x.tarih, konular: h.konular))
        let j = hatirYerel.suffix(300).map { ["gun": $0.gun ?? NSNull(), "tarih": $0.tarih, "konular": $0.konular] as [String: Any] }
        if let v = try? JSONSerialization.data(withJSONObject: j) { _ = OnCalisma.koordineliYaz(v, Yol.durum.appendingPathComponent("hatir.json")) }
    }

    // MARK: Kuiz promptu (⌘K) — Gemini'ye

    func kuizPrompt() -> String {
        let h = o?.hatirlatma ?? hatirAta()
        let hat = h.konular.map { ad -> String in
            let k = gramerMap[ad]
            return "- **\(ad)**" + (k.map { " — pattern: \($0.formul). Typical error for Turkish speakers: \($0.tuzak)" } ?? "")
        }.joined(separator: "\n")
        func kurallar(_ n: Int) -> [String] {
            ["## Rules", "",
             "- Write **\(n) questions**. Everything — questions, options, explanations — **in English only**. No Turkish.",
             "- Prefer **open gap-fill, transformation and error-correction over multiple choice** — the learner must produce, not recognise.",
             "- Distractors and traps must be the mistakes a **Turkish speaker actually makes** (dropped or extra \"the\", Turkish word order, wrong preposition, present perfect with a finished time).",
             "- Everyday situations, short natural sentences, B1–B2 level.",
             "- Number the questions. Put **all answers with one-line explanations at the very end**, under \"Answers\"."]
        }
        guard let x = o else {
            return (["You are an English teacher. Build a grammar quiz for a Turkish B1–B2 learner on today's two reminder structures:", "", hat, ""]
                    + kurallar(12) + ["- Split the questions evenly between the two structures; at least 2 questions contrast them with a similar structure."]).joined(separator: "\n")
        }
        let g = x.gun
        let ys = yapiSkorlari()
        let sahne = g.sahne.map { k -> String in
            let y = ys.first { $0["konu"] as? String == k }
            return "- **\(k)**" + ((y?["skor"] as? Int).map { " — today \($0)%" } ?? "")
        }.joined(separator: "\n")
        let zorAd = zorKelimeler().map(\.0)
        let rcYok = (x.recall?.sorular ?? []).filter { $0.sonuc != "tam" }.map(\.cevap)
        let ht = oturumHT().sorted { $0.value > $1.value }
        let kd = (x.kendi ?? []).filter { !$0.metin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let hedef = (g.yeni ?? []) + (g.tanidik ?? [])
        let rc = recallOzeti()
        var l: [String?] = [
            "You are an English teacher building a quiz for a Turkish B1–B2 learner who studied the paragraph below today (translated it from Turkish sentence by sentence, then wrote the whole paragraph from memory).",
            "",
            kd.isEmpty ? "## The quiz" : "## Step 1 — check my own sentences first\n\nI wrote these with today's reminder structures. For each: say if it is correct, give the corrected version, and explain the error in one line.\n\n"
                + kd.map { "- (\($0.konu)) \($0.metin.trimmingCharacters(in: .whitespacesAndNewlines))" }.joined(separator: "\n") + "\n\n## Step 2 — the quiz",
            "", "### The studied paragraph", "", x.asil, "",
            "### Structures of the paragraph (weakest first gets most questions)", "", sahne.isEmpty ? "(none)" : sahne, "",
            "### Today's two reminder structures (30-day grammar cycle)", "", hat, "",
            hedef.isEmpty ? nil : "### Target words\n\n" + hedef.joined(separator: ", ") + "\n",
            zorAd.isEmpty ? nil : "### Words I dropped while writing\n\n" + zorAd.joined(separator: ", ") + "\n",
            rc.map { "### In-app recall test\n\nScore \($0["yuzde"]!)%." + (rcYok.isEmpty ? "" : " Still not retained: " + rcYok.joined(separator: ", ") + ".") + "\n" },
            ht.isEmpty ? nil : "### My error profile today\n\n" + ht.map { "\(Metin.htAd[$0.key] ?? $0.key) ×\($0.value)" }.joined(separator: ", ")
                + ". Build at least 2 questions that target my most frequent error type.\n",
            "### Weighting (15 questions)", "",
            "- 6 on the paragraph's structures (weakest first)",
            "- 5 on the two reminder structures (at least 1 contrasts them with a look-alike structure)",
            "- 4 on target words, dropped words and my error profile",
            "- Do not repeat any sentence from the paragraph verbatim.", "",
        ]
        l += kurallar(15)
        return l.compactMap { $0 }.joined(separator: "\n")
    }

    func panoya(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    // MARK: Gramer sayfası

    func gramerAc(_ liste: [String]? = nil, _ i: Int = 0) {
        let l = liste ?? (o?.hatirlatma ?? hatirAta()).konular
        gramerSayfa = l; gramerI = i
    }

    // MARK: Kendi sesinle okuma (Mac)

    func kayitBaslat() async {
        guard let x = o else { return }
        ses.dur(); calici.durdur()
        await kaydedici.baslat(gun: x.gun.no)
    }
    func kayitBitir(tanima: Bool) async {
        guard let x = o, let r = await kaydedici.bitir(metin: x.asil, tanima: tanima) else { return }
        var s = o!.sesli ?? Sesli()
        s.kayit += 1; s.sure_sn += Int(r.sure.rounded())
        if let z = kaydedici.sonuc { s.tanima_yuzde = z.yuzde; s.okunan = z.okunan; s.toplam = z.toplam; s.takilan = z.takilan }
        o!.sesli = s
        if !x.tekrar, x.gun.no > 0 {
            OnCalisma.kayitBildir(gun: x.gun.no, ad: r.ad, sure: r.sure, tanima: kaydedici.sonuc.map { Double($0.yuzde) / 100 },
                                  takilan: kaydedici.sonuc?.takilan)
            duyur("Kayıt telefonla ortak klasöre gitti — ertesi sabah çözümlenir")
        }
        dokun(); kaydet()
        tazele()
    }
}

/// Hatırlatma geçmişinin bir satırı.
struct GunTarih { var gun: Int?; var tarih: String; var konular: [String]; var anahtar: String { "\(gun.map(String.init) ?? "")|\(tarih)" } }
extension GunTarih {
    init(_ d: [String: Any]) { gun = d.i("gun"); tarih = d.s("tarih"); konular = d.l("konular") }
}
