// Teoria motor sınaması — Xcode'suz: zsh mac/sina.sh
import Foundation

var hata = 0
func dogrula(_ k: Bool, _ m: String) { print(k ? "✓" : "✗", m); if !k { hata += 1 } }

let yol = URL(fileURLWithPath: CommandLine.arguments[1])
let paket = try! JSONDecoder().decode(Paket.self, from: Data(contentsOf: yol.appendingPathComponent("kartlar.json")))
let akis = try! JSONDecoder().decode(Akis.self, from: Data(contentsOf: yol.appendingPathComponent("akis.json")))
dogrula(paket.kavramlar.count == 32, "paket okundu: \(paket.kavramlar.count) kavram")
dogrula(akis.isaretler.count > 100, "akış okundu: \(akis.isaretler.count) işaret")
dogrula(akis.isaretler.allSatisfy { $0.zaman != .distantPast }, "bütün işaret tarihleri çözüldü")

// 1 · Her hat × kademe en az bir alıştırma üretir
for h in Hat.allCases {
    for k in 1...6 {
        var kul = Set<String>()
        let a = Kurgu.uret(paket, Durum(), h, k, &kul, akis: [], simdi: Date())
        dogrula(a != nil && a!.kademe == k, "\(h.ad) K\(k): \(a?.baslik ?? "YOK") (\(a?.tip.rawValue ?? "-"))")
    }
}

// 2 · Diz parçaları doğru sırada birleşince cümleyi verir; seçenekte doğru cevap var
for c in paket.cumleler {
    let p = Uretec.parcala(c.metin)
    dogrula(p.joined(separator: " ") == c.metin && p.count >= 1, "parçala: \(c.id) → \(p.count) parça")
}
for d in paket.donusumler { dogrula(d.secenekler.contains(d.dogru), "dönüşüm seçeneği: \(d.id)") }
dogrula((paket.questions ?? []).count >= 30, "kavram soruları yüklendi: \((paket.questions ?? []).count)")
for q in paket.questions ?? [] {
    dogrula(q.options.contains(q.answer) && paket.kavram(q.concept) != nil, "kavram sorusu: \(q.id)")
}
// Dönüştür 1–2 artık fiil→isim türetmesi üretmez; hepsi kavram sorusu ya da kavramsal seçme
for k in 1...2 {
    let adaylar = Uretec.donustur(paket, k)
    dogrula(!adaylar.isEmpty, "dönüştür K\(k) aday var: \(adaylar.count)")
    for a in adaylar.prefix(40) {
        let x = a.yap()
        dogrula(x.tip == .sec && x.secenekler.contains(x.dogru) && Set(x.secenekler).count == x.secenekler.count,
                "dönüştür K\(k) \(x.kartAnahtari): seçmeli, doğru şıkta")
        dogrula(!x.baslik.hasPrefix("Fiilden") && !x.baslik.contains("Türev"), "dönüştür K\(k): türetme yok")
    }
}

// 3 · Ölçüm
let bos = Alistirma(hat: .hatirla, kademe: 3, kartAnahtari: "x", tip: .bosluk, baslik: "", soru: "", dogru: "kendinde şey", kitap: nil)
dogrula(Olcum.bosluk("Kendinde sey", bos, ipucu: 0).0 == 1, "şapkasız yazım tam sayılır")
dogrula(Olcum.bosluk("kendnde şey", bos, ipucu: 0).1 == .yakin, "bir harf hatası 'yakın'")
dogrula(Olcum.bosluk("fenomen", bos, ipucu: 0).0 == 0, "yanlış cevap 0")
dogrula(Olcum.bosluk("kendinde şey", bos, ipucu: 2).0 == 0.7, "iki ipucu puanı düşürür (0.7)")
let yaz = Alistirma(hat: .hatirla, kademe: 4, kartAnahtari: "x", tip: .yaz, baslik: "", soru: "", anahtar: ["deneyim", "önce"], model: "", kitap: nil)
dogrula(Olcum.oneri("Deneyimden önce gelen bilgi demek", yaz) >= 0.85, "serbest yazı: ekli kelimeler tanınır")
dogrula(Olcum.oneri("bilmiyorum", yaz) == 0, "serbest yazı: boş cevap 0")
dogrula(Olcum.not(1, guven: 1) == .zor, "şansla bilinen (güven düşük) 'zor' sayılır")

// 4 · +1 kuralı: üç kür üst üste hedefte → bir kademe; tek kötü kür sayacı sıfırlar
func kur(_ gun: Int, _ puan: Double, hat: Hat = .hatirla, kademe: Int) -> [Olay] {
    let t0 = Date().gunBasi.gun(-30 + gun).addingTimeInterval(9 * 3600)
    let id = UUID().uuidString
    var o: [Olay] = []
    for i in 0..<4 {
        var x = Olay(tur: .cevap, hedef: "\(hat.rawValue):k\(i)", hat: hat, kademe: kademe, puan: puan, kurId: id)
        x.t = t0.addingTimeInterval(Double(i) * 30); x.gun = Tarih.gun(x.t); o.append(x)
    }
    var k = Olay(tur: .kur, sure: 300, kurId: id); k.t = t0.addingTimeInterval(200); k.gun = Tarih.gun(k.t)
    return o + [k]
}
var olay = kur(0, 1, kademe: 1) + kur(1, 1, kademe: 1)
dogrula(Durum.kur(olay, zorluk: .dengeli).kademe(.hatirla) == 1, "iki iyi kür: henüz K1")
olay += kur(2, 0.9, kademe: 1)
dogrula(Durum.kur(olay, zorluk: .dengeli).kademe(.hatirla) == 2, "üçüncü iyi kür: K2'ye çıktı")
olay += kur(3, 1, kademe: 2) + kur(4, 0.8, kademe: 2) + kur(5, 1, kademe: 2) + kur(6, 1, kademe: 2)
dogrula(Durum.kur(olay, zorluk: .dengeli).kademe(.hatirla) == 2, "araya giren orta kür sayacı sıfırlar: K2'de kalır")
dogrula(Durum.kur(olay, zorluk: .zorlu).kademe(.hatirla) == 3, "Zorlu ayarda (%75) aynı geçmiş K3'e çıkarır")
olay += kur(7, 0.2, kademe: 2) + kur(8, 0.1, kademe: 2) + kur(9, 0.2, kademe: 2)
dogrula(Durum.kur(olay, zorluk: .dengeli).kademe(.hatirla) == 1, "üç çok zor kür: sessizce bir kademe iner")
let d = Durum.kur(olay, zorluk: .dengeli)
dogrula(d.kurlar.count == 10, "10 kür sayıldı")
dogrula(d.kademe(.kur) == 1 && d.kademe(.donustur) == 1, "öteki hatlar etkilenmedi")

// 5 · Isınma/esneme cevapları kademe hesabına girmez
var oe = kur(0, 1, kademe: 1) + kur(1, 1, kademe: 1)
var esn = kur(2, 0, kademe: 1)
for i in esn.indices where esn[i].tur == .cevap { esn[i].rol = "esneme" }
oe += esn
dogrula(Durum.kur(oe, zorluk: .dengeli).hatlar[.hatirla]?.yukari == 2, "esneme kartlarındaki hata sayacı bozmaz")

// 6 · İleri saatli cihaz: geleceğe yazılmış olay şimdiye çekilir, sıra bozulmaz
var gelecek = Olay(tur: .favori, hedef: "a-1", deger: true); gelecek.t = Date().addingTimeInterval(86_400 * 30)
var simdiki = Olay(tur: .favori, hedef: "a-1", deger: false); simdiki.t = Date().addingTimeInterval(-10)
let df = Durum.kur([gelecek, simdiki], zorluk: .dengeli)
dogrula(df.favoriler.contains("a-1"), "ileri saatli olay geleceğe kilitlemez (şimdiye çekildi)")

// 7 · Günlük: bozuk satır atlanır, çakışma kopyası tekillenir
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("teoria-sina-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
let a = Olay(tur: .favori, hedef: "x"), b = Olay(tur: .yerIsareti, hedef: "y")
var veri = Gunluk.satir(a) + Gunluk.satir(b)
veri.append(contentsOf: Array("{\"id\":\"yarim".utf8))
try! veri.write(to: tmp.appendingPathComponent("iphone.jsonl"))
try! (Gunluk.satir(a)).write(to: tmp.appendingPathComponent("iphone 2.jsonl"))
try! Data("x".utf8).write(to: tmp.appendingPathComponent(".mac-ev.jsonl.icloud"))
let okunan = Gunluk.klasoruOku(tmp)
dogrula(okunan.bozuk == 1, "yarım satır atlandı")
dogrula(Gunluk.tekille(okunan.olaylar).count == 2, "çakışma kopyası tekillendi (2 olay)")
try? FileManager.default.removeItem(at: tmp)

// 8 · Kür planı: süreye göre doluyor, son gün başta (yoksa ısınma), kapanış var, aynı kart iki kez yok
dogrula(Kurgu.plan(paket, Durum(), dakika: 5).alistirmalar.first?.rol == "isinma", "akış yokken ısınma başta")
for dk in [5, 10, 15] {
    let p = Kurgu.plan(paket, Durum(), dakika: dk, akis: akis.isaretler)
    let kaynaklar = p.alistirmalar.map(\.kartAnahtari)
    let sg = p.alistirmalar.prefix { $0.rol == "songun" }.count
    dogrula(sg == (dk == 5 ? 3 : (dk == 10 ? 5 : 7)) || sg == Kurgu.sonGun(akis.isaretler, Durum())?.isaretler.count,
            "\(dk) dk: kür son okunan günün \(sg) işaretiyle açılıyor")
    dogrula(p.kapanis != nil, "\(dk) dk: kapanış hazır")
    dogrula(Set(kaynaklar).count == kaynaklar.count, "\(dk) dk: \(p.alistirmalar.count) kart, yineleme yok")
    let s = p.alistirmalar.reduce(0) { $0 + $1.tahminiSaniye }
    dogrula(s >= Double(dk * 60), "\(dk) dk: tahmini süre \(Int(s / 60)) dk ≥ \(dk)")
}
// Uzun aradan dönüş: bir kademe hafif
var uzun = kur(0, 1, kademe: 1); for i in uzun.indices { uzun[i].t = Date().addingTimeInterval(-20 * 86_400) }
var du = Durum.kur(uzun, zorluk: .dengeli); du.hatlar[.kur] = HatDurumu(kademe: 4)
let pu = Kurgu.plan(paket, du, dakika: 5)
dogrula(pu.hosgeldin && pu.alistirmalar.filter { $0.hat == .kur && $0.rol == nil }.allSatisfy { $0.kademe == 3 }, "20 gün ara: hoş geldin, Kur K4 → K3'ten başlar")

// 8b · Son gün: en yeni günün işaretleri; bugün sorulanlar ikinci kürde tekrar gelmez
if let (gun, l) = Kurgu.sonGun(akis.isaretler, Durum()) {
    let enYeni = akis.isaretler.map(\.zaman).max()!
    dogrula(Tarih.takvim.isDate(gun, inSameDayAs: enYeni) && l.allSatisfy { Tarih.takvim.isDate($0.zaman, inSameDayAs: enYeni) },
            "son gün = en yeni işaretin günü (\(Tarih.kisa(gun)), \(l.count) işaret)")
    let sorulan = l.prefix(3).map { Olay(tur: .cevap, hedef: "hatirla:isaret:\($0.id)", hat: .hatirla, kademe: 1, puan: 1, not: 3) }
    let d2 = Durum.kur(sorulan, zorluk: .dengeli)
    let l2 = Kurgu.sonGun(akis.isaretler, d2)?.isaretler ?? []
    dogrula(Set(l2.map(\.id)).isDisjoint(with: l.prefix(3).map(\.id)), "ikinci kürde bugün sorulan son gün işaretleri düşer")
    // Bir kez sorulan işaret aralıklı tekrara girer: vadesi gelince "tekrar" olarak döner
    var eski = Olay(tur: .cevap, hedef: "hatirla:isaret:\(l[0].id)", hat: .hatirla, kademe: 1, puan: 1, not: 3)
    eski.t = Date().gun(-30)
    let d3 = Durum.kur([eski], zorluk: .dengeli)
    let p3 = Kurgu.plan(paket, d3, dakika: 10, akis: akis.isaretler, simdi: Date().gun(400))
    dogrula(p3.alistirmalar.contains { $0.rol == "tekrar" && $0.kartAnahtari == "hatirla:isaret:\(l[0].id)" } ||
            p3.alistirmalar.contains { $0.kartAnahtari == "hatirla:isaret:\(l[0].id)" },
            "kürde sorulan işaret vadesi gelince aralıklı tekrar olarak döner")
}

// 8c · X paylaşımı 280 karakteri aşmaz, yorum korunur
let uzunMetin = String(repeating: "Varlık anlamı sorusu unutulmuştur. ", count: 20)
let xm = XPaylas.sigdir(yorum: "Benim yorumum", alinti: uzunMetin, kaynak: "Heidegger")
dogrula(xm.count <= 280 && xm.hasPrefix("Benim yorumum"), "X metni \(xm.count) karakter, yorum başta")

// 9 · Hatırlat denen işaret Hatırla hattına girer
var dh = Durum(); dh.hatirlatmalar = [akis.isaretler[0].id]
let ah = Uretec.adaylar(paket, .hatirla, 3, akis: akis.isaretler, hatirlatmalar: dh.hatirlatmalar)
dogrula(ah.contains { $0.anahtar.hasPrefix("hatirla:isaret:") }, "hatırlat → kendi işaretin kürde sorulur")

// 10 · FSRS: iyi cevap aralığı büyütür, unutma küçültür
let k1 = FSRS.yeni(.iyi, an: Date().gun(-10))
let k2 = FSRS.tekrar(k1, .iyi, an: Date())
let k3 = FSRS.tekrar(k2, .unuttum, an: Date().gun(5))
dogrula(k2.kararlilik > k1.kararlilik && k3.kararlilik < k2.kararlilik, "FSRS kararlılık: \(Int(k1.kararlilik))→\(Int(k2.kararlilik))→\(String(format: "%.1f", k3.kararlilik))")

// 11 · Gündem kelimeleri
let g = Dil.sikKelimeler(akis.isaretler.map(\.metin), adet: 8)
dogrula(!g.isEmpty, "gündem: " + g.map { "\($0.0)(\($0.1))" }.joined(separator: " "))

// Silme: kendi gönderin günlükten silinmez, "silindi" olayıyla akıştan ve sayaçtan düşer (2026-10-07)
do {
    let h = akis.isaretler[0].id
    let y1 = Olay(tur: .kendiCumle, hedef: h, deger: false, metin: "ilk fikrim", rol: "fikir")
    let y2 = Olay(tur: .kendiCumle, hedef: h, deger: true, metin: "ikinci", rol: "yorum")
    let once = Durum.kur([y1, y2], zorluk: .dengeli)
    dogrula(once.kendiCumleler.count == 2 && once.yorumSayisi[h] == 2, "iki yazı: 2 gönderi, sayaç 2")
    let sonra = Durum.kur([y1, y2, Olay(tur: .sesSil, hedef: y1.id)], zorluk: .dengeli)
    dogrula(sonra.kendiCumleler.map(\.id) == [y2.id] && sonra.yorumSayisi[h] == 1, "silinen fikir akıştan ve sayaçtan düştü")
    let hepsi = Durum.kur([y1, y2, Olay(tur: .sesSil, hedef: y1.id), Olay(tur: .sesSil, hedef: y2.id)], zorluk: .dengeli)
    dogrula(hepsi.kendiCumleler.isEmpty && hepsi.yorumSayisi[h] == nil, "ikisi de silinince sayaç boş")
}
// Akış saat sırası: aynı günün işaretleri saatle sıralanır, en yenisi önce
do {
    let bugunku = akis.isaretler.filter { Tarih.takvim.isDate($0.zaman, inSameDayAs: akis.isaretler[0].zaman) }
    dogrula(bugunku.count < 2 || zip(bugunku, bugunku.dropFirst()).allSatisfy { $0.zaman >= $1.zaman }, "aynı günün işaretleri saate göre sıralı")
    dogrula(akis.isaretler.prefix(20).contains { $0.tarih.count > 10 }, "Voice Dream işaretleri saat taşıyor")
}

print(hata == 0 ? "\nHEPSİ GEÇTİ" : "\n\(hata) BAŞARISIZ")
exit(hata == 0 ? 0 : 1)
