// Sabah zaman kutusu (Kurultay kararı 2026-11-05, 1. adım): İngilizce 09–10, en çok 60 dk.
// Sayaç ilk dokunuşta başlar; 55. dakikada "5 dakika kaldı", 60'ta yumuşak sınır (bitir ya da bir kez +10 dk);
// bitince "tamamlandı" kartı ve sıradaki blok (Teoria Sabah). Bileşen: shared/TimeBox/TimeBox.swift.
import AppKit
import SwiftUI

@MainActor
enum SabahSaati {
    static let plan = TimeBoxPlan.load(vault: Yol.vault)
    static let saat: TimeBoxClock = {
        let b = plan.block("english") ?? TimeBoxPlan.standard.blocks[0]
        let c = TimeBoxClock(block: b, plan: plan, state: TimeBoxDay.read(vault: Yol.vault)[b.id] ?? TimeBoxState())
        c.onChange = { s, tur in
            TimeBoxDay.write(vault: Yol.vault, id: b.id, s)
            TimeBoxBus.emit(vault: Yol.vault, app: "cumle", device: Makine.ad, type: tur, block: b, state: s)
        }
        return c
    }()

    static func teoriayiAc() {
        let u = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Teoria.app")
        NSWorkspace.shared.openApplication(at: u, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }
}

/// Bugün ekranını sarar: üstte süre şeridi, süre dolunca yumuşak sınır kartı.
struct SabahCercevesi<I: View>: View {
    @EnvironmentObject var t: Tezgah
    @ObservedObject var saat = SabahSaati.saat
    @ViewBuilder var icerik: I

    private var gorunur: Bool { (t.o != nil && t.o?.tekrar == false) || saat.phase == .done }

    var body: some View {
        VStack(spacing: 0) {
            if gorunur && saat.phase != .done { TimeBoxBar(clock: saat) }
            icerik
        }
        .overlay {
            if gorunur && saat.showOver {
                ZStack {
                    Color.black.opacity(0.18).ignoresSafeArea()
                    TimeBoxOverCard(clock: saat) { t.bitis() }
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: saat.showOver)
    }
}
