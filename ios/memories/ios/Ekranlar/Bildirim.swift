// Bildirimler — hepsi Ayarlar'dan (kullanıcı kararı, 2026-10-06).
//   · Paket hazır   : her paket için EN FAZLA BİR kez, seçilen saatte. Dinlemeye başladıysan hiç gelmez.
//   · Akşam         : isteğe bağlı (varsayılan kapalı). O gün paket hiç açılmadıysa, yalnız o gün.
//   · Çözüm geldi   : ertesi sabah Mac'te yazılan çözüm telefona inince (arka plan yenilemesi ya da açılış).
// Kural: suçluluk yok. Kaçan bildirim birikmez, seri yok, "N gün oldu" yok.
import Foundation
import UserNotifications

enum Bildirim {
    static let onek = "memories."
    private static var d: UserDefaults { .standard }

    static var paketAcik: Bool { get { d.object(forKey: "bil.paket") as? Bool ?? true } set { d.set(newValue, forKey: "bil.paket") } }
    static var paketSaat: Int { get { d.object(forKey: "bil.paket.saat") as? Int ?? 8 } set { d.set(newValue, forKey: "bil.paket.saat") } }
    static var paketDakika: Int { get { d.object(forKey: "bil.paket.dk") as? Int ?? 30 } set { d.set(newValue, forKey: "bil.paket.dk") } }
    static var aksamAcik: Bool { get { d.object(forKey: "bil.aksam") as? Bool ?? false } set { d.set(newValue, forKey: "bil.aksam") } }
    static var aksamSaat: Int { get { d.object(forKey: "bil.aksam.saat") as? Int ?? 20 } set { d.set(newValue, forKey: "bil.aksam.saat") } }
    static var cozumAcik: Bool { get { d.object(forKey: "bil.cozum") as? Bool ?? true } set { d.set(newValue, forKey: "bil.cozum") } }
    static var sesli: Bool { get { d.object(forKey: "bil.ses") as? Bool ?? false } set { d.set(newValue, forKey: "bil.ses") } }

    enum Izin { case reddedildi, sorulmadi, verildi }

    static func izin() async -> Izin {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: .verildi
        case .notDetermined: .sorulmadi
        default: .reddedildi
        }
    }

    static func izinIste() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    private static func icerik(_ baslik: String, _ govde: String, rota: String) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = baslik
        c.body = govde
        c.interruptionLevel = .active
        c.sound = sesli ? .default : nil
        c.userInfo = ["rota": rota]
        c.threadIdentifier = "memories"
        return c
    }

    private static func sonraki(_ saat: Int, _ dk: Int, bugunOlsun: Bool = false) -> DateComponents? {
        let tk = Calendar.current
        let simdi = Date()
        guard var hedef = tk.date(bySettingHour: saat, minute: dk, second: 0, of: simdi) else { return nil }
        if hedef <= simdi {
            if bugunOlsun { return nil }
            hedef = tk.date(byAdding: .day, value: 1, to: hedef) ?? hedef
        }
        return tk.dateComponents([.year, .month, .day, .hour, .minute], from: hedef)
    }

    @MainActor private static var lastPlan: String?

    /// Bekleyen bütün Memories bildirimlerini durumdan yeniden kurar. Her açılışta ve her olayda çağrılır.
    /// - Parameter onlyIfChanged: after an event — skip the work when the plan would come out the same
    ///   (same package, same "started" state, same settings, same trigger times).
    @MainActor
    static func planla(_ depo: Depo, onlyIfChanged: Bool = false) async {
        await depo.whenLoaded()
        let mrk = UNUserNotificationCenter.current()
        var izinDurumu = await izin()
        if izinDurumu == .sorulmadi, paketAcik || cozumAcik {
            izinDurumu = await izinIste() ? .verildi : .reddedildi
        }
        let key: String = {
            guard izinDurumu == .verildi, let p = depo.guncel else { return "-" }
            let z1 = paketAcik ? sonraki(paketSaat, paketDakika) : nil
            let z2 = aksamAcik ? sonraki(aksamSaat, 0, bugunOlsun: true) : nil
            return "\(p.gun)|\(p.ad)|\(p.sure)|\(depo.hazirlik(p.gun).basladi)|\(sesli)|\(String(describing: z1))|\(String(describing: z2))"
        }()
        if onlyIfChanged, key == lastPlan { return }
        lastPlan = key
        let bekleyen = await mrk.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(onek) && !$0.hasPrefix(onek + "cozum") }
        mrk.removePendingNotificationRequests(withIdentifiers: bekleyen)
        guard izinDurumu == .verildi, let p = depo.guncel else { return }
        let h = depo.hazirlik(p.gun)

        if paketAcik, !h.basladi, let z = sonraki(paketSaat, paketDakika) {
            let c = icerik("Gün \(p.gun) · \(p.ad)",
                           "Ön çalışma hazır · \(Tarih.dakika(p.sure)). Dinle, ekrandan oku, kendi sesinle oku.", rota: "dinle")
            try? await mrk.add(UNNotificationRequest(identifier: onek + "paket.\(p.gun)", content: c,
                                                     trigger: UNCalendarNotificationTrigger(dateMatching: z, repeats: false)))
        }
        if aksamAcik, !h.basladi, let z = sonraki(aksamSaat, 0, bugunOlsun: true) {
            let c = icerik("\(p.ad)", "İstersen dinleme seni bekliyor (\(Tarih.dakika(p.sure))). Yarın yazarken tanıdık gelir.", rota: "dinle")
            try? await mrk.add(UNNotificationRequest(identifier: onek + "aksam.\(p.gun)", content: c,
                                                     trigger: UNCalendarNotificationTrigger(dateMatching: z, repeats: false)))
        }
    }

    /// Yeni çözüm telefona indi: hemen, bir kez.
    static func cozumGeldi(_ c: Cozum) async {
        guard cozumAcik, await izin() == .verildi else { return }
        var govde = "Dünkü yazımın çözümü hazır."
        if let y = c.yazim, let o = y.ilk_yazim_ort { govde = "İlk yazım ortalaması %\(o)."
            if let t = y.tam_isabet, let n = y.cumle { govde += " \(n) cümlenin \(t)'i tam isabet." } }
        if let r = c.yol_haritasi?.first { govde += " Yarın dikkat: \(r.tur)." }
        let i = icerik("Gün \(c.gun) çözümü", govde, rota: "cozum")
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: onek + "cozum.\(c.gun)", content: i,
                                  trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)))
    }

    static func dene() async {
        let c = icerik("Memories", "Bildirimler böyle görünecek.", rota: "bugun")
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: onek + "deneme", content: c,
                                  trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)))
    }
}
