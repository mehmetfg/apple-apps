// Bildirimler: günde en çok iki kez (saatler Ayarlar'da), Kutu'daki en ilgili işaret sorulur — "bu hangi bölüme?".
// Cevap kilit ekranından verilir: bölüm düğmeleri · Metne girmez. Uygulama açılmaz. Bekleyen sayısı, seri, ısrar yok.
import Foundation
import UserNotifications

enum Bildirimci {
    static let kategori = "kenar.isaret"
    static let onEk = "kenar-isaret-"

    static var saatler: [Int] {     // dakika cinsinden gün içi saat
        get { (Depo.ayar.array(forKey: "bildirimSaatleri") as? [Int]) ?? [12 * 60 + 30, 20 * 60 + 30] }
        set { Depo.ayar.set(newValue, forKey: "bildirimSaatleri") }
    }
    static var acik: Bool {
        get { Depo.ayar.object(forKey: "bildirimAcik") as? Bool ?? true }
        set { Depo.ayar.set(newValue, forKey: "bildirimAcik") }
    }

    static func izinIste() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Eylem düğmeleri bölüm adlarını taşır; metin değişince yeniden kurulur.
    static func kategorileriKur(_ m: Metin?) {
        var eylemler: [UNNotificationAction] = (m?.bolumler ?? []).map {
            UNNotificationAction(identifier: "b:" + $0.id, title: "§\($0.no) \($0.baslik)", options: [], icon: UNNotificationActionIcon(systemImageName: "\($0.no).circle"))
        }
        eylemler.append(UNNotificationAction(identifier: "disari", title: "Metne girmez", options: [.destructive], icon: UNNotificationActionIcon(systemImageName: "xmark.circle")))
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: kategori, actions: eylemler, intentIdentifiers: [], options: [])
        ])
    }

    static func planla(_ d: KenarDurum) {
        let m = UNUserNotificationCenter.current()
        m.getPendingNotificationRequests { bekleyen in
            m.removePendingNotificationRequests(withIdentifiers: bekleyen.map(\.identifier).filter { $0.hasPrefix(onEk) })
            guard acik, let metin = d.metin else { return }
            let adaylar = d.kutu.sorted { Ilgi.puan($0.metin, metin) > Ilgi.puan($1.metin, metin) }
            guard !adaylar.isEmpty else { return }
            let tak = Calendar.current
            var sira = 0
            for gun in 0..<3 {
                for dk in saatler.sorted() {
                    guard sira < adaylar.count,
                          let gunBasi = tak.date(byAdding: .day, value: gun, to: tak.startOfDay(for: .now)),
                          let an = tak.date(byAdding: .minute, value: dk, to: gunBasi), an > .now.addingTimeInterval(120) else { continue }
                    let x = adaylar[sira]; sira += 1
                    let c = UNMutableNotificationContent()
                    c.title = "Bu işaret hangi bölüme?"
                    c.subtitle = x.kitapAdi
                    let oneri = Ilgi.oneri(x.metin, metin).map { "\nÖneri: §\($0.no) \($0.baslik)" } ?? ""
                    c.body = "“\(x.metin.prefix(170))\(x.metin.count > 170 ? "…" : "")”" + oneri
                    c.categoryIdentifier = kategori
                    c.threadIdentifier = "kenar"
                    c.interruptionLevel = .passive
                    c.userInfo = ["isaret": x.id]
                    let bilesen = tak.dateComponents([.year, .month, .day, .hour, .minute], from: an)
                    m.add(UNNotificationRequest(identifier: onEk + x.id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: bilesen, repeats: false)))
                }
            }
        }
    }

    static func cevap(_ r: UNNotificationResponse) async -> String? {
        let id = r.notification.request.content.userInfo["isaret"] as? String ?? ""
        guard !id.isEmpty else { return nil }
        switch r.actionIdentifier {
        case let e where e.hasPrefix("b:"):
            await Merkez.arkaPlandaAta(id, String(e.dropFirst(2)), disari: false)
            return nil
        case "disari":
            await Merkez.arkaPlandaAta(id, nil, disari: true)
            return nil
        default:
            return "kenar://kutu"
        }
    }

    static func deneme() {
        let c = UNMutableNotificationContent()
        c.title = "Bu işaret hangi bölüme?"
        c.subtitle = "Deneme"
        c.body = "Kilit ekranında bildirime basılı tut: bölüm düğmeleri burada görünür."
        c.categoryIdentifier = kategori
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "kenar-deneme", content: c, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)))
    }
}
