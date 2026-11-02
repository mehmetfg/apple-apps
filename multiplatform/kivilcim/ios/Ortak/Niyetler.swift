// Kilit ekranı, Denetim Merkezi, widget, Siri ve Kestirmeler için niyetler + Canlı Etkinlik tanımı.
// Bu dosya uygulamada da widget uzantısında da derlenir; ses niyetlerini sistem UYGULAMANIN sürecinde çalıştırır
// (AudioRecordingIntent / LiveActivityIntent). Uzantıdaki kopya yalnız tanımdır (WIDGET bayrağı).
import Foundation
import AppIntents
import ActivityKit
#if !WIDGET
import UIKit
#endif

let uygulamaGrubu = "group.com.fatihgocgun.kivilcim"

struct KayitEtkinligi: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Sayacın başlangıcı: duraklatılan süre kadar ileri kayar, böylece sistem sayacı doğru akar.
        var baslangic: Date
        var bitti: Bool = false
        var sure: Double = 0
        var baslik: String = ""
        /// Duraklatıldıysa o an; sayaç orada durur.
        var duraklama: Date? = nil
        /// Son ses düzeyleri (0…1), Canlı Etkinlikteki dalga için; saniyede bir tazelenir.
        var seviyeler: [Double] = []
        var duraklatildi: Bool { duraklama != nil }
    }
    var kalite: String
}

/// Kilit ekranındaki ve widget'taki tek düğme: kayıt yoksa başlatır, varsa bitirir. Kilidi açmak gerekmez.
/// LiveActivityIntent uyumu şart: yalnız AudioRecordingIntent olunca sistem niyeti widget uzantısında koşturuyordu
/// (2026-10-10 tanı kaydı: "[widget] … UZANTIDA çalıştı"); uzantı mikrofon açamaz. LiveActivityIntent uygulamayı arka
/// planda uyandırıp perform'u onun içinde çalıştırır. Yine de uzantıya düşerse uygulamayı açıp kaydı başlatır.
struct KaydiDegistirNiyeti: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Fikir kaydet"
    static let description = IntentDescription("Kıvılcım ile sesli fikir kaydını başlatır ya da bitirir.")
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    #if !WIDGET
    func perform() async throws -> some IntentResult {
        Tani.yaz("niyet: degistir (uygulama süreci)")
        if !(await KayitMerkezi.shared.degistir(kaynak: "kilit")) { try await oneGecipBaslat() }
        return .result()
    }
    #else
    func perform() async throws -> some IntentResult & OpensIntent {
        Tani.yaz("niyet: degistir UZANTIDA çalıştı → uygulama açılıp kayıt başlatılıyor")
        return .result(opensIntent: AcVeKaydetNiyeti())
    }
    #endif
}

struct KaydiBaslatNiyeti: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Fikir kaydını başlat"
    static let description = IntentDescription("Kıvılcım ses kaydını hemen başlatır.")
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    #if !WIDGET
    func perform() async throws -> some IntentResult {
        Tani.yaz("niyet: baslat (uygulama süreci)")
        if !(await KayitMerkezi.shared.baslat(kaynak: "kestirme")) { try await oneGecipBaslat() }
        return .result()
    }
    #else
    func perform() async throws -> some IntentResult & OpensIntent {
        Tani.yaz("niyet: baslat UZANTIDA çalıştı → uygulama açılıyor")
        return .result(opensIntent: AcVeKaydetNiyeti())
    }
    #endif
}

struct KaydiBitirNiyeti: LiveActivityIntent {
    static let title: LocalizedStringResource = "Fikir kaydını bitir"
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    func perform() async throws -> some IntentResult {
        #if !WIDGET
        Tani.yaz("niyet: bitir (uygulama süreci)")
        await KayitMerkezi.shared.bitir()
        #else
        Tani.yaz("niyet: bitir UZANTIDA çalıştı")
        #endif
        return .result()
    }
}

/// Canlı Etkinlik / Dynamic Island: duraklat ↔ devam.
struct KaydiDuraklatNiyeti: LiveActivityIntent {
    static let title: LocalizedStringResource = "Fikir kaydını duraklat"
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    func perform() async throws -> some IntentResult {
        #if !WIDGET
        Tani.yaz("niyet: duraklat/devam (uygulama süreci)")
        await KayitMerkezi.shared.duraklatDegistir()
        #endif
        return .result()
    }
}

/// Canlı Etkinlik / Dynamic Island: kaydı silip kapatır.
struct KaydiIptalNiyeti: LiveActivityIntent {
    static let title: LocalizedStringResource = "Fikir kaydından vazgeç"
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    func perform() async throws -> some IntentResult {
        #if !WIDGET
        Tani.yaz("niyet: vazgeç (uygulama süreci)")
        await KayitMerkezi.shared.vazgec()
        #endif
        return .result()
    }
}

#if !WIDGET
extension AppIntent {
    /// iOS uygulama arka plandayken mikrofonu açtırmazsa ("Session activation failed", 2026-10-11'den beri her kilit
    /// ekranı denemesi): kilidi açtırıp (Face ID) uygulamayı öne getirir ve kaydı orada başlatır. Soru sorulmaz.
    func oneGecipBaslat() async throws {
        guard #available(iOS 26.0, *) else { return }
        Tani.yaz("arka planda mikrofon açılmadı → öne geçiliyor")
        try await continueInForeground(nil, alwaysConfirm: false)
        await KayitMerkezi.shared.baslat(kaynak: "kilit→önde")
    }
}
#endif

/// Yedek yol: uygulamayı açıp kaydı başlatır (Face ID ister). Sessiz yol bir gün çalışmazsa bu kesin çalışır.
struct AcVeKaydetNiyeti: AppIntent {
    static let title: LocalizedStringResource = "Kıvılcım'ı aç ve kaydet"
    static let description = IntentDescription("Kıvılcım'ı açar ve kaydı hemen başlatır.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        #if !WIDGET
        Tani.yaz("niyet: aç ve kaydet")
        await KayitMerkezi.shared.baslat(kaynak: "ac")
        #endif
        return .result()
    }
}

/// Tanı kaydı: kilit ekranından gelen her denemenin adımları (App Group/tani.log, son 300 satır).
/// Ayarlar › Tanı'da görünür; Mac'ten `devicectl` ile de okunur.
enum Tani {
    static var dosya: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: uygulamaGrubu)?.appendingPathComponent("tani.log")
    }
    static func yaz(_ s: String) {
        guard let u = dosya else { return }
        let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm:ss"
        let satir = "[\(f.string(from: Date()))] [\(Bundle.main.bundleIdentifier?.components(separatedBy: ".").last ?? "?")] \(s)\n"
        var eski = (try? String(contentsOf: u, encoding: .utf8)) ?? ""
        let satirlar = eski.split(separator: "\n")
        if satirlar.count > 300 { eski = satirlar.suffix(250).joined(separator: "\n") + "\n" }
        try? (eski + satir).write(to: u, atomically: true, encoding: .utf8)
    }
    static func oku() -> String { dosya.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "" }
}

/// Widget'ların okuduğu küçük durum (App Group).
enum WidgetDurumu {
    static var d: UserDefaults { UserDefaults(suiteName: uygulamaGrubu) ?? .standard }
    static var kayitta: Bool { d.bool(forKey: "kayitta") }
    static var sonBaslik: String { d.string(forKey: "sonBaslik") ?? "" }
    static var sonAlan: String { d.string(forKey: "sonAlan") ?? "" }
    static var sonRenk: String { d.string(forKey: "sonRenk") ?? "#FF6A3D" }
    static var sonZaman: Date? { d.object(forKey: "sonZaman") as? Date }
    static var bugun: Int { d.integer(forKey: "bugun") }
}
