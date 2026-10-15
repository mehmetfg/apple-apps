import Foundation
import os

/// Ayarlar App Group'ta bir plist dosyasında. UserDefaults değil: uzantı klavye korumalı alanında çalışıyor,
/// ortak tercihleri okuyamıyor ama ortak alandaki dosyaları okuyabiliyor (2026-10-09 ölçümü). Yazan yalnız uygulama.
final class DosyaDepo {
    static let ortak = DosyaDepo()
    private var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Ayar.grup)?.appendingPathComponent("ayar.plist")
    }
    private func sozluk() -> [String: Any] {
        guard let u = url, let d = try? Data(contentsOf: u),
              let p = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any] else { return [:] }
        return p
    }
    func object(forKey k: String) -> Any? { sozluk()[k] }
    func double(forKey k: String) -> Double { object(forKey: k) as? Double ?? 0 }
    func bool(forKey k: String) -> Bool { object(forKey: k) as? Bool ?? false }
    func set(_ v: Any?, forKey k: String) {
        guard let u = url else { return }
        var d = sozluk()
        d[k] = v
        if let veri = try? PropertyListSerialization.data(fromPropertyList: d, format: .binary, options: 0) {
            try? veri.write(to: u, options: .atomic)
        }
    }
}

// Uygulama ile uzantının paylaştığı ses ayarı (App Group).
enum Ayar {
    static let grup = "group.com.fatihgocgun.ema"
    static var depo: DosyaDepo { .ortak }

    /// Perde, yarım ton (−6 … +6). 0 = modelin kendi sesi.
    static var perde: Double {
        get { depo.double(forKey: "perde") }
        set { depo.set(newValue, forKey: "perde") }
    }

    /// Ses yüksekliği katı (0.5 … 2). 1 = modelin kendi seviyesi.
    static var yukseklik: Double {
        get { depo.object(forKey: "yukseklik") as? Double ?? 1 }
        set { depo.set(newValue, forKey: "yukseklik") }
    }

    /// Uzantının aldığı son SSML — uygulamaların hız/perde/ses ayarını hangi biçimde gönderdiğini görmek için.
    static func ssmlKaydet(_ ssml: String) {
        guard let k = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: grup) else { return }
        try? String(ssml.prefix(2000)).write(to: k.appendingPathComponent("son-ssml.txt"), atomically: true, encoding: .utf8)
    }

    /// Uzantının tanı kaydı (App Group › uzanti.txt), son 200 satır.
    static func uzantiKaydi(_ satir: String) {
        // Uzantı klavye korumalı alanında çalışır, dosyaya yazamaz: tanı yalnız sistem günlüğüne gider.
        Logger(subsystem: "com.fatihgocgun.ema", category: "tani").notice("EMA-TANI \(satir, privacy: .public)")
    }

    /// Müzik arası: her N dakikalık dinlemeden sonra bir parça (varsayılan açık, 15 dk).
    static var muzikArasi: Bool {
        get { depo.object(forKey: "muzikArasi") as? Bool ?? true }
        set { depo.set(newValue, forKey: "muzikArasi") }
    }
    static var muzikDakika: Int {
        get { depo.object(forKey: "muzikDakika") as? Int ?? 15 }
        set { depo.set(newValue, forKey: "muzikDakika") }
    }
    /// Arka plan müziği: okumanın altında kısık müzik (varsayılan kapalı — deneme).
    static var arkaPlan: Bool {
        get { depo.bool(forKey: "arkaPlan") }
        set { depo.set(newValue, forKey: "arkaPlan") }
    }
    static var arkaPlanSeviye: Double {
        get { depo.object(forKey: "arkaPlanSeviye") as? Double ?? 0.15 }
        set { depo.set(newValue, forKey: "arkaPlanSeviye") }
    }

    /// İmleç işaret birimi: 4 = bayt (Float32), 1 = örnek. Voice Dream'de imleç kayarsa değiştirilir.
    static var isaretCarpani: Int {
        get { depo.object(forKey: "isaretCarpani") as? Int ?? 4 }
        set { depo.set(newValue, forKey: "isaretCarpani") }
    }

    static func uzantiKaydiOku() -> String {
        guard let k = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: grup) else { return "" }
        return (try? String(contentsOf: k.appendingPathComponent("uzanti.txt"), encoding: .utf8)) ?? ""
    }

    static func sonSSML() -> String {
        guard let k = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: grup) else { return "" }
        return (try? String(contentsOf: k.appendingPathComponent("son-ssml.txt"), encoding: .utf8)) ?? ""
    }
}
