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
        /// Set on the finished card of a spark: the lock screen shows priority / done buttons for this id.
        var kimlik: String? = nil
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
        if !(await KayitMerkezi.shared.degistir(kaynak: "kilit", tur: "spark")) { try await oneGecipBaslat() }
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
        if !(await KayitMerkezi.shared.baslat(kaynak: "kestirme", tur: "spark")) { try await oneGecipBaslat() }
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
    func oneGecipBaslat(tur: String = "spark") async throws {
        guard #available(iOS 26.0, *) else { return }
        Tani.yaz("arka planda mikrofon açılmadı → öne geçiliyor")
        try await continueInForeground(nil, alwaysConfirm: false)
        await KayitMerkezi.shared.baslat(kaynak: "kilit→önde", tur: tur)
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
    /// Resolved once per process: yaz() runs several times on the way to a recording.
    static let dosya: URL? =
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: uygulamaGrubu)?.appendingPathComponent("tani.log")
    private static let stamp: DateFormatter = {
        let f = DateFormatter(); f.timeZone = .autoupdatingCurrent; f.dateFormat = "MM-dd HH:mm:ss"; return f
    }()
    private static let process = Bundle.main.bundleIdentifier?.components(separatedBy: ".").last ?? "?"

    /// Adds one line. The app, the widget extension and the share extension write the same file, so the line goes out
    /// as a single write on an O_APPEND descriptor: the kernel puts it at the end whole, and no process reads and
    /// rewrites the file here (the old read-modify-write could drop another process's lines). Trimming is in kirp().
    static func yaz(_ s: String) {
        guard let u = dosya else { return }
        let satir = Array("[\(stamp.string(from: Date()))] [\(process)] \(s)\n".utf8)
        let fd = open(u.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { return }
        flock(fd, LOCK_SH)          // only kirp() takes it exclusively; close() releases it
        _ = satir.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        close(fd)
    }

    /// Keeps the last 250 lines once the log has more than 300. Called off the main thread and away from the record
    /// path (app comes to the front, a recording has been saved). Writers wait on the lock, so no line is lost.
    static func kirp() {
        guard let u = dosya else { return }
        let fd = open(u.path, O_RDWR)
        guard fd >= 0 else { return }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0, let eski = try? String(contentsOf: u, encoding: .utf8) else { return }
        let satirlar = eski.split(separator: "\n")
        guard satirlar.count > 300 else { return }
        let yeni = Array((satirlar.suffix(250).joined(separator: "\n") + "\n").utf8)
        guard ftruncate(fd, 0) == 0 else { return }
        _ = yeni.withUnsafeBytes { pwrite(fd, $0.baseAddress, $0.count, 0) }
    }
    /// Copies the log into the app's own container (2026-11-10): the Mac can read it there with devicectl
    /// (App Group files are outside what devicectl may copy), so a failed lock-screen recording can be diagnosed.
    static func mirror() {
        guard let u = dosya, let v = try? Data(contentsOf: u) else { return }
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Kivilcim")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try? v.write(to: d.appendingPathComponent("tani.log"), options: .atomic)
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
