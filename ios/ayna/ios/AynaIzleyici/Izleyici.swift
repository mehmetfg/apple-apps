// Ekran Süresi izleyicisi: 15 dakikalık ara bitince kalkanı geri kurar; gece yarısı sayaç sıfırlanıp kalkan döner.
import DeviceActivity
import Foundation

final class Izleyici: DeviceActivityMonitor {
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        if activity == Kapi.araAdi { Kapi.kur() }
    }

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        if activity == Kapi.gunAdi { Kapi.bugun = 0; Kapi.kur() }
    }
}
