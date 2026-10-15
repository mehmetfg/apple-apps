// tezgah.json'un Swift karşılığı. Üreten: Artifacts/_pano/ios.py
// Her alan isteğe bağlı: bir bölüm {"hata": "..."} gelirse çözme düşmez, yalnız o bölüm hata gösterir.
import Foundation

struct TezgahVeri: Decodable {
    var surum: Int?
    var uretildi: String?
    var son_calisma: String?
    var makine: String?
    var bugun: BugunBolum?
    var cumle: CumleBolum?
    var muhendis: MuhendisBolum?
    var idrak: IdrakBolum?
    var vault: VaultBolum?
}

// MARK: Bugün

struct BugunBolum: Decodable {
    var hata: String?
    var tarih: String?
    var kartlar: [Kart]?
    var aktivite: [Aktivite]?
}

struct Kart: Decodable, Identifiable {
    var kod: String
    var ad: String?
    var alt: String?
    var hata: String?
    var baslik: String?
    var `is`: String?
    var not: String?
    var durum: String?
    var ilerleme: Ilerleme?
    var sayilar: [Sayi]?
    var id: String { kod }
}

struct Ilerleme: Decodable {
    var a: Double?
    var b: Double?
    var etiket: String?
    var oran: Double { guard let a, let b, b > 0 else { return 0 }; return min(1, max(0, a / b)) }
}

struct Sayi: Decodable, Hashable {
    var deger: String?
    var etiket: String?
}

struct Aktivite: Decodable, Identifiable {
    var kod: String
    var ad: String?
    var gunler: [Int]?
    var toplam: Int?
    var id: String { kod }
}

// MARK: Cümle + İngilizce

struct CumleBolum: Decodable {
    var hata: String?
    var bugun: CumleBugun?
    var gunler: [CumleGun]?
    var hatalar: [AdSayi]?
    var yapilar: [Yapi]?
    var konu_toplam: Int?
    var depo: KelimeDepo?
    var kelime_eki: KelimeEki?
    var kayitlar: [Kayit]?
}

struct CumleBugun: Decodable {
    var gun: Int?
    var baslik: String?
    var tema: String?
    var ozet: String?
    var mod: String?
    var konular: [String]?
    var yeni: [String]?
    var yanki: [String]?
    var cumleler: [Cumle]?
    var yapildi: Bool?
}

struct Cumle: Decodable, Hashable {
    var en: String?
    var tr: String?
    var konu: String?
    var yazim: String?
    var yuzde: Double?
    var baktim: Bool?
}

struct CumleGun: Decodable, Identifiable, Hashable {
    var gun: Int?
    var tarih: String?
    var baslik: String?
    var tema: String?
    var ozet: String?
    var tutma: Double?
    var paragraf: Double?
    var paragraf_metin: String?
    var sure_dk: Double?
    var baktim: Int?
    var cumleler: [Cumle]?
    var id: String { "\(gun ?? 0)-\(tarih ?? "")" }
}

struct AdSayi: Decodable, Identifiable, Hashable {
    var ad: String
    var sayi: Int
    var id: String { ad }
}

struct Yapi: Decodable, Identifiable, Hashable {
    var konu: String
    var skor: Double?
    var kez: Int?
    var id: String { konu }
}

struct KelimeDepo: Decodable {
    var havuz: Int?
    var biliyorum: Int?
    var tanidik: Int?
    var bilmiyorum: Int?
}

struct KelimeEki: Decodable {
    var hata: String?
    var toplam: Int?
    var son: [EkKelime]?
}

struct EkKelime: Decodable, Identifiable, Hashable {
    var tarih: String?
    var kelime: String
    var turkce: String?
    var slot: String?
    var baglam: String?
    var id: String { (tarih ?? "") + kelime }
}

struct Kayit: Decodable, Identifiable, Hashable {
    var tarih: String
    var tur: String?
    var baslik: String
    var ozet: String?
    var kaynak: String?
    var id: String { tarih + baslik }
}

// MARK: Mühendis

struct MuhendisBolum: Decodable {
    var hata: String?
    var bugun: MuhendisBugun?
    var toplam: Int?
    var calisilan: Int?
    var uretilen: Int?
    var alanlar: [Alan]?
}

struct MuhendisBugun: Decodable {
    var id: String?
    var baslik: String?
    var soru: String?
}

struct Alan: Decodable, Identifiable, Hashable {
    var ad: String
    var calisilan: Int
    var toplam: Int
    var id: String { ad }
}

// MARK: İdrak

struct IdrakBolum: Decodable {
    var hata: String?
    var kitaplar: [Kitap]?
    var toplam_isaret: Int?
    var biten: Int?
    var suren: Int?
}

struct Kitap: Decodable, Identifiable, Hashable {
    var id: String
    var baslik: String?
    var kategori: String?
    var kume: String?
    var disiplin: String?
    var yuzde: Int?
    var durum: String?
    var isaret: Int?
    var kelime: Int?
    var son: String?
    var masada: Bool?
    var kapak: String?
    var isaretler: [Isaret]?
    var cumleler: [String]?
    var harita: [HaritaOge]?
    var okumalar: [Okuma]?
    var bitti: Bool { durum == "bitti" }
}

struct Isaret: Decodable, Hashable {
    var alinti: String?
    var baglam: String?
    var renk: String?
}

struct HaritaOge: Decodable, Hashable {
    var kod: String?
    var ad: String?
    var isaret: Int?
}

struct Okuma: Decodable, Hashable {
    var tarih: String?
    var yuzde: Double?
    var yeni: Int?
}

// MARK: Vault

struct VaultBolum: Decodable {
    var hata: String?
    var toplam_not: Int?
    var toplam_kelime: Int?
    var baglar: Int?
    var kirik: Int?
    var koken: [String: Int]?
    var gunler: [VaultGun]?
    var bugun: VaultBugun?
    var son: [VaultNot]?
    var klasorler: [Klasor]?
    var hareketler: [Hareket]?
    var kayitlar: [Kayit]?
}

struct VaultGun: Decodable, Identifiable, Hashable {
    var tarih: String
    var ben: Int
    var yz: Int
    var diger: Int
    var yeni: Int
    var id: String { tarih }
    var toplam: Int { ben + yz + diger }
}

struct VaultBugun: Decodable {
    var yeni: Int?
    var degisen: Int?
    var ben: Int?
    var yz: Int?
}

struct VaultNot: Decodable, Identifiable, Hashable {
    var ad: String
    var yol: String
    var klasor: String?
    var koken: String?
    var zaman: String?
    var yeni: Bool?
    var kelime: Int?
    var tur: String?
    var ozet: String?
    var id: String { yol }
}

struct Klasor: Decodable, Identifiable, Hashable {
    var ad: String
    var not: Int
    var hafta: Int
    var kelime: Int?
    var ben: Int?
    var id: String { ad }
}

struct Hareket: Decodable, Hashable {
    var zaman: String?
    var eylem: String?
    var yol: String?
}
