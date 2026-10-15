// Ayna'nın verisi. Uygulama ve bütün uzantılar (widget, Ekran Süresi kapısı) bu dosyayı derler.
// Tek fikir: kendi gününü İngilizce söyle → Mac düzeltir → sabah düzeltilmiş hâlini dinle → kendi hatanı sına → yeniden söyle.
import Foundation

enum Tur: String, Codable, CaseIterable, Sendable {
    case gun, an, prova, metin, kapi, yeniden
    var ad: String {
        switch self { case .gun: "Günün"; case .an: "Bir an"; case .prova: "Yarına prova"; case .metin: "Kenar metni"; case .kapi: "Kapı"; case .yeniden: "Yeniden" }
    }
    var simge: String {
        switch self { case .gun: "sun.horizon"; case .an: "photo"; case .prova: "calendar"; case .metin: "text.book.closed"; case .kapi: "hand.raised"; case .yeniden: "arrow.counterclockwise" }
    }
}

struct Hata: Codable, Hashable, Sendable {
    var yanlis: String
    var dogru: String
    var kural: String
}

struct Soru: Codable, Hashable, Sendable {
    var cumle: String
    var dogru: Bool
    var aciklama: String
}

struct Kayit: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var tarih: Date
    var tur: Tur
    var istem: String                 // ne anlatıldı: "Gününü anlat", "Bu fotoğraf", "Yarın 10:00 Toplantı", Kenar bölümü…
    var sure: Double
    var kenarIs: String?              // Kenar'dan gelen işin kimliği (metin-bölüm)
    var oncekiKayit: String?          // "yeniden" turunda ilk anlatım
    var onDokum: String?              // telefonun kendi dökümü (anında)
    var dokum: String?                // Mac · Whisper
    var duzeltme: String?             // Mac · Claude: aynı anlatımın doğru, doğal İngilizcesi
    var hatalar: [Hata] = []
    var sorular: [Soru] = []
    var sesVar = false                // düzeltilmiş hâlin Kokoro sesi telefona indi mi
    var dinlendi = false
    var vaultta = false

    var durum: String {
        if duzeltme != nil { return dinlendi ? "dinlendi" : "düzeltildi" }
        if dokum != nil { return "Mac döktü · düzeltme bekliyor" }
        return vaultta ? "Mac bekliyor" : "telefonda"
    }
}

/// Kenar'dan gelen iş: biten bölümün Türkçe paragrafı — İngilizce anlatılacak.
struct KenarIsi: Codable, Hashable, Identifiable, Sendable {
    var id: String; var metin: String; var bolumNo: Int; var baslik: String; var iddia: String; var paragraf: String; var tarih: Date
}

struct AynaDurum: Codable, Sendable {
    var surum = 1
    var kayitlar: [Kayit] = []
    var kapiIstemleri: [Date] = []    // kapıda "Söyle" denen anlar — Bugün'de bekler
    var guncelleme = Date()
}

/// Widget'ın gösterdiği tek şey: dünden bir hata ve doğrusu.
struct WidgetOzet: Codable, Sendable {
    var yanlis: String
    var dogru: String
    var kural: String
    var bekleyen: Int
    static let ornek = WidgetOzet(yanlis: "I go to the market yesterday.", dogru: "I went to the market yesterday.", kural: "Past simple: yesterday → went", bekleyen: 1)
}

enum Kimlik { static func yeni() -> String { String(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(12)) } }
