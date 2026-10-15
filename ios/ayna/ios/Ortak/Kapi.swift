// Ekran Süresi kapısı. Seçtiğin uygulamaları (X, Instagram, YouTube…) açınca önce Ayna'nın kalkanı çıkar:
// "Şu an ne yapıyorsun? Tek cümle, İngilizce." Söyle → kalkan 15 dk kalkar, Ayna'da kayıt bekler. Geç → yine 15 dk kalkar.
// Günde en çok 3 kez çıkar; üçüncüden sonra gün bitene kadar kapalı. Ayarlar'dan tek dokunuşla kapanır.
import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

enum Kapi {
    static let magaza = ManagedSettingsStore(named: ManagedSettingsStore.Name("ayna.kapi"))
    static let araAdi = DeviceActivityName("ayna.ara")
    static let gunAdi = DeviceActivityName("ayna.gun")

    static var acik: Bool {
        get { Depo.ayar.bool(forKey: "kapiAcik") }
        set { Depo.ayar.set(newValue, forKey: "kapiAcik") }
    }
    static var tavan: Int {
        get { max(1, Depo.ayar.object(forKey: "kapiTavan") as? Int ?? 3) }
        set { Depo.ayar.set(newValue, forKey: "kapiTavan") }
    }

    static var secim: FamilyActivitySelection {
        get { Depo.ayar.data(forKey: "kapiSecim").flatMap { try? JSONDecoder().decode(FamilyActivitySelection.self, from: $0) } ?? FamilyActivitySelection() }
        set { Depo.ayar.set(try? JSONEncoder().encode(newValue), forKey: "kapiSecim") }
    }

    /// Bugün kaç kez çıktı (gün değişince sıfırlanır).
    static var bugun: Int {
        get {
            let g = Calendar.current.startOfDay(for: .now).timeIntervalSince1970
            return Depo.ayar.double(forKey: "kapiGun") == g ? Depo.ayar.integer(forKey: "kapiSayi") : 0
        }
        set {
            Depo.ayar.set(Calendar.current.startOfDay(for: .now).timeIntervalSince1970, forKey: "kapiGun")
            Depo.ayar.set(newValue, forKey: "kapiSayi")
        }
    }

    /// Kalkanı kur (açık, seçim dolu ve günlük tavan dolmadıysa); değilse kaldır.
    static func kur() {
        let s = secim
        guard acik, bugun < tavan, !(s.applicationTokens.isEmpty && s.categoryTokens.isEmpty) else { kaldir(); return }
        magaza.shield.applications = s.applicationTokens.isEmpty ? nil : s.applicationTokens
        magaza.shield.applicationCategories = s.categoryTokens.isEmpty ? nil : .specific(s.categoryTokens)
        magaza.shield.webDomains = s.webDomainTokens.isEmpty ? nil : s.webDomainTokens
    }

    static func kaldir() { magaza.clearAllSettings() }

    /// Bir kalkan geçildi: sayaç +1, kalkan 15 dk kalkar (Ekran Süresi'nin en kısa aralığı), sonra izleyici yeniden kurar.
    static func gecildi() {
        bugun += 1
        kaldir()
        let simdi = Date()
        let bas = Calendar.current.dateComponents([.hour, .minute, .second], from: simdi)
        let son = Calendar.current.dateComponents([.hour, .minute, .second], from: simdi.addingTimeInterval(15 * 60 + 5))
        let merkez = DeviceActivityCenter()
        merkez.stopMonitoring([araAdi])
        try? merkez.startMonitoring(araAdi, during: DeviceActivitySchedule(intervalStart: bas, intervalEnd: son, repeats: false))
    }

    /// Her gün yeniden başlayan izleme: gece yarısı sayaç sıfırlanır ve kalkan geri gelir.
    static func gunlukIzlemeyiKur() {
        let merkez = DeviceActivityCenter()
        merkez.stopMonitoring([gunAdi])
        guard acik else { return }
        try? merkez.startMonitoring(gunAdi, during: DeviceActivitySchedule(intervalStart: DateComponents(hour: 0, minute: 0), intervalEnd: DateComponents(hour: 23, minute: 59), repeats: true))
    }

    static let istemler = [
        "What are you doing right now? Say it in one English sentence.",
        "Why are you opening this app? One sentence, in English.",
        "Describe the room around you in one sentence.",
        "What did you do in the last hour? Say it in English.",
        "How do you feel right now? One honest English sentence.",
    ]
    static var istem: String { istemler[(bugun + Calendar.current.component(.hour, from: .now)) % istemler.count] }
}
