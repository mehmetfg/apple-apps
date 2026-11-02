// Test hook -finishtest: a finished book stays finished and at its end; play and jumps on it only ask; a new reading
// counts; an automation whose step book is finished waits for a choice. Writes Documents/finish-test.txt.
import Foundation

@MainActor
enum FinishTest {
    static func run(_ model: AppModel) async {
        var log: [String] = []
        func check(_ ok: Bool, _ what: String) { log.append((ok ? "OK   " : "FAIL ") + what) }
        let text = "Kısa bir deneme metni.\nİkinci paragraf burada biter."
        guard let a = DocumentImporter.fromClipboard(text), let b = DocumentImporter.fromClipboard("Öteki kitap.\nBir cümle daha."),
              let da = try? model.store.add(a, original: nil), let db = try? model.store.add(b, original: nil) else {
            log.append("FAIL documents"); write(log); return
        }
        model.addFolder("FinishTest")
        model.setFolder(da.id, "FinishTest"); model.setFolder(db.id, "FinishTest")

        // 1. read to the end
        await model.open(da.id)
        model.player.play()
        for _ in 0..<60 where model.store.document(da.id)?.isFinished != true { try? await Task.sleep(for: .milliseconds(500)) }
        var d = model.store.document(da.id)!
        check(d.isFinished, "finished after reading to the end")
        check(d.position == d.length, "place at the end (\(d.position)/\(d.length))")
        check(d.finishes.count == 1, "one finished reading")

        // 2. play / jump on the finished book: nothing moves, the question comes
        model.player.play()
        try? await Task.sleep(for: .milliseconds(300))
        check(!model.player.isSpeaking, "play does not start")
        check(model.finishedPrompt != nil, "the question is shown")
        model.finishedPrompt = nil
        model.player.moveCursor(to: 0, play: false)
        model.player.skip(forward: false, unit: .sentence)
        d = model.store.document(da.id)!
        check(d.position == d.length && model.player.cursor == d.length, "jumps do not move the place")

        // 3. reopen (as after a restart): still at the end
        model.player.unload()
        await model.open(da.id)
        check(model.player.cursor == d.length, "reopened at the end, not at 0")

        // 4. automation: step book finished → it waits for a choice, ⏭ takes the next unfinished
        model.startAutomation(Automation(name: "t", steps: [.read("FinishTest", minutes: 1)]))
        for _ in 0..<40 where model.automationChoice == nil { try? await Task.sleep(for: .milliseconds(250)) }
        check(model.automationChoice?.nextID == db.id, "automation asks, next = the unfinished book")
        _ = model.answerAutomationChoice(key: 1)
        for _ in 0..<40 where model.player.documentID != db.id { try? await Task.sleep(for: .milliseconds(250)) }
        check(model.player.documentID == db.id, "⏭ goes to the next book")
        model.stopAutomation()
        check(model.store.document(da.id)?.isFinished == true, "finished book untouched by the automation")

        // 5. a new reading
        model.startReadingAgain(da.id)
        d = model.store.document(da.id)!
        check(!d.isFinished && d.position == 0 && d.readingNumber == 2, "Baştan başla = 2. okuma at 0")
        check(model.statusText(d).hasPrefix("2. okuma"), "status: \(model.statusText(d))")
        model.store.saveNow()
        write(log)
    }

    private static func write(_ log: [String]) {
        try? log.joined(separator: "\n").write(to: URL.documentsDirectory.appending(path: "finish-test.txt"), atomically: true, encoding: .utf8)
    }

    /// -marktest2: the mark grows back over three sentences as one highlight; an active wait of 4 s stops reading and
    /// starts it again by itself. Writes Documents/mark-test.txt.
    static func marksAndWait(_ model: AppModel) async {
        var log: [String] = []
        func check(_ ok: Bool, _ what: String) { log.append((ok ? "OK   " : "FAIL ") + what) }
        let text = "Bir. İlk cümle burada. İkinci cümle de burada. Üçüncü cümle geliyor. Dördüncü cümle okunurken işaret konur. Beşinci cümle sonra gelir. Altıncı cümle de var. Yedinci cümle uzun bir cümle olarak yazıldı ki okuma sürsün."
        guard let a = DocumentImporter.fromClipboard(text), let d = try? model.store.add(a, original: nil) else { return }
        await model.open(d.id)
        model.player.moveCursor(to: (text as NSString).range(of: "Dördüncü").location, play: true)
        try? await Task.sleep(for: .seconds(2.5))
        model.markSpokenSentence()
        let n1 = model.extendMarkBack(), n2 = model.extendMarkBack()
        let hs = model.store.document(d.id)?.highlights ?? []
        check(hs.count == 1, "one highlight (\(hs.count))")
        check(n1 == 2 && n2 == 3, "chain grew 1 → 2 → 3")
        check(hs.first?.text.hasPrefix("İkinci") == true, "mark starts two sentences back: \(hs.first?.text.prefix(30) ?? "")")
        model.player.activePause(seconds: 4)
        try? await Task.sleep(for: .milliseconds(400))
        check(model.player.breakEnds != nil && !model.player.isPlaying, "wait started, reading stopped")
        let at = model.player.cursor
        try? await Task.sleep(for: .seconds(6))
        check(model.player.isPlaying && model.player.breakEnds == nil, "reading went on by itself")
        check(model.player.cursor >= at, "from the sentence it stopped in (\(at) → \(model.player.cursor))")
        model.player.pause()
        try? log.joined(separator: "\n").write(to: URL.documentsDirectory.appending(path: "mark-test.txt"), atomically: true, encoding: .utf8)
    }

    /// -movetest bike|walk: the moving mode records the simulator's route for 40 s (simctl location start), then
    /// writes the record's sums to Documents/move-test.txt. The mode stays on (the screen can be looked at).
    static func move(_ model: AppModel, kind: MoveKind) async {
        if model.settings.bodyWeight == 0 { model.settings.bodyWeight = 80 }
        model.startMove(kind)
        try? await Task.sleep(for: .seconds(40))
        model.workout.saveNow()
        let w = model.workout.current
        let lines = [
            "kind \(w?.kind.rawValue ?? "-")",
            "distance m \(Int(w?.distance ?? 0))",
            "moving s \(Int(w?.moving ?? 0))",
            "speed now \(Int(model.workout.speed)) km/h · max \(Int(w?.maxSpeed ?? 0))",
            "kcal \(String(format: "%.1f", w?.calories ?? 0))",
            "route points \(w?.route.count ?? 0)",
            "status \(model.workout.status)",
            "saved \(model.workout.history.contains { $0.id == w?.id })",
        ]
        try? lines.joined(separator: "\n").write(to: URL.documentsDirectory.appending(path: "move-test.txt"), atomically: true, encoding: .utf8)
    }

    /// -kinetictest: a marked book with image words, opened in the music mode.
    static func kinetic(_ model: AppModel) async {
        let text = "Akıl, zamanın içinde yol alan bir ışıktır; insan onu ancak soruyla taşır. Hakikat bir yöntemle değil, bir bakışla başlar. Bellek, geçmişin değil geleceğin haritasıdır."
        guard let a = DocumentImporter.fromClipboard(text), let d = try? model.store.add(a, original: nil) else { return }
        let ns = text as NSString
        for q in ["Akıl, zamanın içinde yol alan bir ışıktır; insan onu ancak soruyla taşır.", "Bellek, geçmişin değil geleceğin haritasıdır."] {
            let r = ns.range(of: q)
            model.store.update(d.id) { $0.highlights.append(Highlight(location: r.location, length: r.length, color: .yellow, text: q)) }
        }
        model.settings.musicMic = false
        await model.open(d.id)
        model.musicModeShown = true
    }

    /// -pagetest: a long unfinished text read on the Yolda screen (the page fills downwards, then turns).
    static func page(_ model: AppModel) async {
        let one = "Okumak, bir metnin içinden yavaş yavaş yürümektir ve her cümle bir öncekinin üstüne bir taş koyar. "
        let text = (1...30).map { "\($0). " + one + "Bu taşlar birikince yol görünür olur, sonra yol kendi yönünü söyler." }.joined(separator: " ")
        guard let a = DocumentImporter.fromClipboard(text), let d = try? model.store.add(a, original: nil) else { return }
        model.settings.speed = 3.5
        await model.open(d.id)
        model.player.play()
    }
}
