// PDM bus (shared/PDMBus): one client for the app. App target only: the widget and share targets do not link
// the package. Kıvılcım writes no native events here (a Mac adapter reports idea.captured from the vault files);
// it marks the day it was opened, keeps the cached state fresh, and tells the other apps on the phone what it
// is doing now (live state: recording or the last record).
import Foundation
import PDMBus

enum KivilcimBus {
    static let shared = PDMBus(app: "kivilcim", vaultRoot: {
        // The folder connected in Ayarlar › Vault. The bus needs the vault root (it has _bus). When the user
        // connected a subfolder (Kıvılcım, Fikirler, 05 - Notlar), the folder chosen in the PDM Ağı section is
        // used; with none chosen the subfolder is passed anyway and the package reports that it has no _bus.
        let own = PDMVault.resolveBookmark(UserDefaults.standard.data(forKey: Kasa.bookmarkKey))
        if let own, Kasa.isVaultRoot(own.lastPathComponent) { return own }
        return PDMVault.resolve() ?? own
    })

    /// The app came to the front: one app.opened a day, then outbox → vault and state → App Group.
    static func becameActive() async {
        await Task.detached(priority: .utility) { shared.emitOpenedToday() }.value
        await shared.sync()
    }

    private static let liveQueue = DispatchQueue(label: "kivilcim.bus.live", qos: .utility)

    /// What Kıvılcım does now, for the other apps on this phone (App Group file; no vault, no iCloud).
    /// Written off the main thread, in call order.
    static func publishLive(id: String?, active: Bool) {
        liveQueue.async {
            shared.publishLive(PDMLive(app: "kivilcim", kind: "idea", id: id, title: nil, active: active, link: "kivilcim://arsiv"))
        }
    }
}
