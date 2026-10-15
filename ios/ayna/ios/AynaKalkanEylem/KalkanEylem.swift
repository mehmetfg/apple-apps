// Kalkanın düğmeleri. Söyle: Ayna'ya bir an bırakır, bildirim düşer (dokununca kayıt açılır), kalkan 15 dk kalkar.
// Geç: kalkan 15 dk kalkar, uygulama açılır. İkisi de günlük sayaca girer (tavan 3).
import ManagedSettings
import UserNotifications

final class KalkanEylem: ShieldActionDelegate {
    override func handle(action: ShieldAction, for application: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void) { isle(action, completionHandler) }
    override func handle(action: ShieldAction, for webDomain: WebDomainToken, completionHandler: @escaping (ShieldActionResponse) -> Void) { isle(action, completionHandler) }
    override func handle(action: ShieldAction, for category: ActivityCategoryToken, completionHandler: @escaping (ShieldActionResponse) -> Void) { isle(action, completionHandler) }

    private func isle(_ a: ShieldAction, _ bitti: @escaping (ShieldActionResponse) -> Void) {
        switch a {
        case .primaryButtonPressed:
            Depo.kapiAniBirak()
            Kapi.gecildi()
            let c = UNMutableNotificationContent()
            c.title = "Ayna: tek cümle"
            c.body = Kapi.istem + " Dokun, kayıt açılsın."
            c.userInfo = ["rota": "ayna://kaydet/kapi"]
            c.interruptionLevel = .timeSensitive
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "ayna-kapi-\(Date().timeIntervalSince1970)", content: c, trigger: nil))
            bitti(.close)
        case .secondaryButtonPressed:
            Kapi.gecildi()
            bitti(.defer)
        @unknown default:
            bitti(.close)
        }
    }
}
