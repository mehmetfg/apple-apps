// Kenar'ın veri modeli. Uygulama, widget ve paylaşım uzantısı aynı dosyayı derler.
// Tek kural: okunan her şey tek bir metne hizmet eder. Metin beş bölümdür; işaret ya bir bölüme gider ya dışarıda kalır.
import Foundation

enum Kaynak: String, Codable, CaseIterable, Sendable {
    case vd, kamera, paylas, elle, ses
    var ad: String {
        switch self { case .vd: "Voice Dream"; case .kamera: "Kâğıt kitap"; case .paylas: "Paylaşılan"; case .elle: "Elle"; case .ses: "Sesli kenar" }
    }
    var simge: String {
        switch self { case .vd: "headphones"; case .kamera: "camera.viewfinder"; case .paylas: "square.and.arrow.down"; case .elle: "pencil"; case .ses: "waveform" }
    }
}

enum Rol: String, Codable, CaseIterable, Sendable {
    case oncul, sonuc, itiraz, ornek
    var ad: String { switch self { case .oncul: "Öncül"; case .sonuc: "Sonuç"; case .itiraz: "İtiraz"; case .ornek: "Örnek" } }
    var simge: String { switch self { case .oncul: "arrow.down.circle"; case .sonuc: "flag.checkered"; case .itiraz: "exclamationmark.bubble"; case .ornek: "lightbulb" } }
}

struct Isaret: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var metin: String
    var kaynak: Kaynak
    var kitap: String
    var kitapAdi: String
    var tarih: Date
    var bolum: String?
    var rol: Rol?
    var not: String = ""
    var disarida = false
    var x: Double?
    var y: Double?

    var atanmis: Bool { bolum != nil }
}

struct Bag: Codable, Hashable, Identifiable, Sendable {
    var kaynak: String
    var hedef: String
    var id: String { kaynak + ">" + hedef }
}

struct Bolum: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var no: Int
    var baslik: String
    var iddia: String
    var ham: [String]
    var anahtar: [String]
    var paragraf: String = ""
    var hedef: Int = 300
    var bitti = false
    var ingilizce: String?          // Ayna'dan dönen düzeltilmiş İngilizce paragraf

    var kelime: Int { paragraf.kelimeSayisi }
}

struct Metin: Codable, Identifiable, Sendable {
    var id: String
    var baslik: String
    var soru: String
    var disiplin: String
    var hedef: Int = 1500
    var anahtar: [String: Double]
    var bolumler: [Bolum]
    var uretimeGitti: Date?

    var kelime: Int { bolumler.reduce(0) { $0 + $1.kelime } }
    var bittiSayisi: Int { bolumler.filter(\.bitti).count }
}

struct Oturum: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var kitap: String
    var kitapAdi: String
    var soru: String
    var baslangic: Date
    var bitis: Date?
    var isaret = 0
}

struct Anlatim: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var tarih: Date
    var bolum: String?
    var kitap: String?
    var sure: Double
    var onDokum: String?            // telefonun kendi (cihaz içi) dökümü
    var dokum: String?              // Mac'teki Whisper dökümü
    var kapsanan: [String] = []
    var atlanan: [String] = []
    var claude: String?
    var vaultta = false

    var durum: String {
        if claude != nil { return "değerlendirildi" }
        if dokum != nil { return "Mac döktü" }
        if onDokum != nil { return "ön döküm" }
        return vaultta ? "Mac bekliyor" : "telefonda"
    }
}

struct KitapKaydi: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var ad: String
    var yazar: String?
    var isbn: String?
    var kagit: Bool
}

/// Telefonun tek durum dosyası. Vault'a `telefon/kenar.json` olarak aynen yazılır; Mac yalnız okur.
struct KenarDurum: Codable, Sendable {
    var surum = 1
    var metin: Metin?
    var isaretler: [Isaret] = []
    var baglar: [Bag] = []
    var oturumlar: [Oturum] = []
    var anlatimlar: [Anlatim] = []
    var kitaplar: [KitapKaydi] = []
    var gorulenVD: [String] = []
    var guncelleme = Date()

    var aktifOturum: Oturum? { oturumlar.last(where: { $0.bitis == nil }) }

    func kanitlar(_ bolum: String) -> [Isaret] { isaretler.filter { $0.bolum == bolum } }
    var kutu: [Isaret] { isaretler.filter { !$0.atanmis && !$0.disarida } }
}

// MARK: ilgi — Kutu'nun sıralaması ve "önerilen bölüm"

enum Ilgi {
    static func puan(_ metin: String, _ m: Metin?) -> Double {
        guard let m else { return 0 }
        let t = metin.tr
        return m.anahtar.reduce(0) { $0 + (t.contains($1.key) ? $1.value : 0) }
    }

    static func oneri(_ metin: String, _ m: Metin?) -> Bolum? {
        guard let m else { return nil }
        let t = metin.tr
        let sirali = m.bolumler.map { b in (b, b.anahtar.filter { t.contains($0) }.count) }.filter { $0.1 > 0 }
        return sirali.max { $0.1 < $1.1 }?.0
    }
}

// MARK: sıradaki hamle — widget, kilit ekranı ve Metin ekranının başı aynı cümleyi söyler

struct Hamle: Codable, Hashable, Sendable {
    var cumle: String
    var bolum: String?
    var adres: String     // kenar://…
}

extension KenarDurum {
    var hamle: Hamle {
        guard let m = metin else { return Hamle(cumle: "Vault klasörünü seç; ilk metin Mac'ten gelir.", bolum: nil, adres: "kenar://metin") }
        if let o = aktifOturum { return Hamle(cumle: "Okuyorsun: \(o.kitapAdi). Soru: \(o.soru)", bolum: nil, adres: "kenar://oku") }
        guard let b = m.bolumler.first(where: { !$0.bitti }) else {
            return m.uretimeGitti == nil
                ? Hamle(cumle: "Beş bölüm bitti — metni Üretim'e gönder.", bolum: nil, adres: "kenar://metin")
                : Hamle(cumle: "Metin Üretim'de. Dışarı çıkarmak sende.", bolum: nil, adres: "kenar://metin")
        }
        let kanit = kanitlar(b.id).count
        if kanit == 0 {
            let aday = kutu.filter { Ilgi.oneri($0.metin, m)?.id == b.id }.count
            return Hamle(cumle: aday > 0 ? "§\(b.no) kanıt bekliyor — Kutu'da \(aday) aday var." : "§\(b.no) kanıt bekliyor — oku ya da kamerayla işaretle.",
                         bolum: b.id, adres: aday > 0 ? "kenar://kutu" : "kenar://oku")
        }
        if b.kelime < 40 { return Hamle(cumle: "§\(b.no) \(b.baslik): ilk cümleyi yaz. \(kanit) kanıt hazır.", bolum: b.id, adres: "kenar://bolum/\(b.id)") }
        if b.kelime < b.hedef { return Hamle(cumle: "§\(b.no): \(b.kelime)/\(b.hedef) kelime. Önce 60 sn anlat, sonra yaz.", bolum: b.id, adres: "kenar://bolum/\(b.id)") }
        return Hamle(cumle: "§\(b.no) hedefte — bitti olarak işaretle.", bolum: b.id, adres: "kenar://bolum/\(b.id)")
    }
}

// MARK: widget'ın okuduğu küçük özet

struct WidgetOzet: Codable, Sendable {
    struct Parca: Codable, Hashable, Sendable { var no: Int; var baslik: String; var kelime: Int; var hedef: Int; var kanit: Int; var bitti: Bool }
    var baslik: String
    var soru: String
    var kelime: Int
    var hedef: Int
    var parcalar: [Parca]
    var hamle: Hamle
    var kutu: Int
    var oturumKitap: String?
    var oturumBaslangic: Date?
    var zaman: Date

    static let ornek = WidgetOzet(baslik: "Kant'ın Kopernik Devrimi", soru: "Bilgimiz mi dünyaya uyar, dünya mı bilgimize?",
                                  kelime: 420, hedef: 1500,
                                  parcalar: [.init(no: 1, baslik: "Eski soru", kelime: 310, hedef: 300, kanit: 3, bitti: true),
                                             .init(no: 2, baslik: "Devrim", kelime: 110, hedef: 300, kanit: 2, bitti: false),
                                             .init(no: 3, baslik: "Dört kutu", kelime: 0, hedef: 300, kanit: 1, bitti: false),
                                             .init(no: 4, baslik: "Sentetik a priori", kelime: 0, hedef: 300, kanit: 0, bitti: false),
                                             .init(no: 5, baslik: "Karşı ses", kelime: 0, hedef: 300, kanit: 0, bitti: false)],
                                  hamle: Hamle(cumle: "§2: 110/300 kelime. Önce 60 sn anlat, sonra yaz.", bolum: "b2", adres: "kenar://bolum/b2"),
                                  kutu: 6, oturumKitap: nil, oturumBaslangic: nil, zaman: .now)
}

extension KenarDurum {
    var ozet: WidgetOzet? {
        guard let m = metin else { return nil }
        return WidgetOzet(baslik: m.baslik, soru: m.soru, kelime: m.kelime, hedef: m.hedef,
                          parcalar: m.bolumler.map { .init(no: $0.no, baslik: $0.baslik, kelime: $0.kelime, hedef: $0.hedef, kanit: kanitlar($0.id).count, bitti: $0.bitti) },
                          hamle: hamle, kutu: kutu.count, oturumKitap: aktifOturum?.kitapAdi, oturumBaslangic: aktifOturum?.baslangic, zaman: .now)
    }
}

// MARK: yardımcılar

extension String {
    var tr: String { lowercased(with: Locale(identifier: "tr_TR")) }
    var kelimeSayisi: Int { split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count }
}

enum Kimlik {
    static func yeni() -> String { UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(12).description }
}
