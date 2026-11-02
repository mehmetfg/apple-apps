// Voice Reader — reads your documents aloud, Voice Dream style.
import SwiftUI
import AVFoundation

@main
struct VoiceReaderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            LibraryScreen()
                .environment(model)
                // the road screen is always dark (the status bar too: its clock and battery stand for the ones the screen dropped)
                .preferredColorScheme(model.readerOpen && model.settings.bikeMode && model.settings.bikeLook.road ? .dark : model.settings.colorScheme)
                .environment(\.accent, model.settings.accent)
                .tint(model.settings.accent.ink)
                .task {
                    if CommandLine.arguments.contains("-voicebench") { await VoiceBench.run() }
                    if CommandLine.arguments.contains("-voicedump") { await VoiceDump.run() }
                    if CommandLine.arguments.contains("-sysdump") { await SystemDump.run() }
                    if CommandLine.arguments.contains("-skiptest") { await SkipTest.run(model); return }
                    // which voices the phone has (Library/voices.txt), so a missing voice can be told from a bug
                    let list = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("tr") || $0.language.hasPrefix("en") }
                        .map { "\($0.identifier)\t\($0.name)\t\($0.language)\t\($0.quality.rawValue)" }.joined(separator: "\n")
                    try? list.write(to: URL.libraryDirectory.appending(path: "voices.txt"), atomically: true, encoding: .utf8)
                    // test hook: -vaulttest <folder> runs the same steps as picking that folder in Ayarlar › PDM vault
                    if let i = CommandLine.arguments.firstIndex(of: "-vaulttest"), i + 1 < CommandLine.arguments.count {
                        _ = await VaultMirror.shared.choose(URL(fileURLWithPath: CommandLine.arguments[i + 1]))
                        await model.sync.mirrorLibrary()
                        model.sync.positionsChanged()
                    }
                    // test hook: -playtest <document id> opens the document, reads for 40 s, writes Library/play-test.txt
                    if let i = CommandLine.arguments.firstIndex(of: "-playtest"), i + 1 < CommandLine.arguments.count,
                       let id = UUID(uuidString: CommandLine.arguments[i + 1]) {
                        await model.open(id)
                        model.player.play()
                        var log: [String] = ["voice \(model.player.voiceID) · studio \(model.player.studio?.segments.count ?? -1) segments"]
                        for _ in 0..<20 {
                            try? await Task.sleep(for: .seconds(2))
                            let w = model.player.spokenWord.map { model.player.excerptWord($0) } ?? "-"
                            let b = model.player.breakEnds.map { " · break \(Int($0.timeIntervalSinceNow)) s left" } ?? ""
                            log.append("cursor \(model.player.cursor) word \(w)\(b)")
                        }
                        model.player.pause()
                        try? log.joined(separator: "\n").write(to: URL.libraryDirectory.appending(path: "play-test.txt"), atomically: true, encoding: .utf8)
                    }
                    // test hook: -autotest <n> runs the pilot automation with every step n times shorter and logs each
                    // second to Library/auto-test.txt; -marktest marks the sentence being read twice (the bicycle toggle)
                    if let i = CommandLine.arguments.firstIndex(of: "-autotest"), i + 1 < CommandLine.arguments.count,
                       let n = Int(CommandLine.arguments[i + 1]), n > 0 {
                        await AutomationTest.run(model, scale: n)
                    }
                    if let i = CommandLine.arguments.firstIndex(of: "-resumetest"), i + 1 < CommandLine.arguments.count,
                       let n = Int(CommandLine.arguments[i + 1]), n > 0 {
                        await AutomationTest.resume(model, scale: n)
                    }
                    if CommandLine.arguments.contains("-marktest") { await AutomationTest.mark(model) }
                    if CommandLine.arguments.contains("-cardtest") { await AutomationTest.card(model) }
                    if CommandLine.arguments.contains("-finishtest") { await FinishTest.run(model); return }
                    if CommandLine.arguments.contains("-marktest2") { await FinishTest.marksAndWait(model); return }
                    if CommandLine.arguments.contains("-kinetictest") { await FinishTest.kinetic(model); return }
                    if CommandLine.arguments.contains("-pagetest") { await FinishTest.page(model) }
                    if let i = CommandLine.arguments.firstIndex(of: "-movetest"), i + 1 < CommandLine.arguments.count {
                        await FinishTest.move(model, kind: MoveKind(rawValue: CommandLine.arguments[i + 1]) ?? .bike); return
                    }
                    await model.restoreLastDocument()
                    model.sync.start()
                    WidgetFeed.publish(model)
                }
                .onChange(of: phase) { _, p in
                    if p == .active { Task { await model.scanDropFolder(); await model.sync.sync() } } else { model.store.saveNow(); model.saveAutomationProgress(); model.workout.saveNow(); WidgetFeed.publish(model, now: true) }
                }
        }
    }
}
