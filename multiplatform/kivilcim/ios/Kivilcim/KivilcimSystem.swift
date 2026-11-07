// The system surface of Kıvılcım (2026-11-06): the records in Spotlight, and the waiting recordings sent to the vault
// in the background, so a recording is not stuck on the phone until the app opens again.
import BackgroundTasks
import Foundation
import PDMBus

@MainActor
enum KivilcimSystem {
    static let sendTask = "com.fatihgocgun.kivilcim.send"
    private static var pending: Task<Void, Never>?

    nonisolated static func registerSend() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: sendTask, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            let work = Task { @MainActor in
                scheduleSend()
                await TelefonDeposu.shared.gonder()
                refresh.setTaskCompleted(success: !Task.isCancelled)
            }
            refresh.expirationHandler = { work.cancel() }
        }
    }

    static func scheduleSend() {
        let r = BGAppRefreshTaskRequest(identifier: sendTask)
        r.earliestBeginDate = Date(timeIntervalSinceNow: 1800)
        try? BGTaskScheduler.shared.submit(r)
    }

    /// Two seconds after the last change, so a sync that brings many records writes once.
    static func indexSoon(_ records: [Oge]) {
        pending?.cancel()
        pending = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            let items = records.map { o -> PDMSpotlight.Item in
                let detail = o.ozet.isEmpty ? String(o.metin.prefix(200)) : o.ozet
                return PDMSpotlight.Item(id: o.id, title: o.baslik.isEmpty ? String(o.metin.prefix(60)) : o.baslik,
                                         detail: detail, keywords: o.etiketler + [o.alan])
            }
            await PDMSpotlight.sync(items, scope: "records")
        }
    }
}
