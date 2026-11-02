// Ties the library, the settings and the player together; everything the screens do goes through here.
import SwiftUI
import AVFoundation
import Observation

@MainActor
@Observable
final class AppModel {
    let store = LibraryStore()
    let settings = Settings()
    let player = SpeechPlayer()
    @ObservationIgnored private(set) var sync: SyncEngine!

    var openDocumentID: UUID?               // the document shown in the reader
    var readerOpen = false                  // the reading screen is on screen (screen stays awake, bicycle buttons)
    let notes = NoteStore(device: SyncEngine.device)
    let recorder = NoteRecorder()
    let listening = ListeningLog(device: SyncEngine.device)    // what was heard each day (İstatistik)
    var noteToast: NoteToast?
    /// Notlarım › "Kitapta aç": the reader brings this place on screen once it has the book (reading stays put).
    @ObservationIgnored var revealRequest: (doc: UUID, offset: Int)?
    var openNoteID: String?                 // a note asked to open (from Konumlar › Notlar)               // "note saved" with its text once it is written
    @ObservationIgnored var pendingNote: (doc: UUID, title: String, range: NSRange, quote: String, chapter: String?)?
    @ObservationIgnored var resumeAfterNote = false
    var importing = false
    var importMessage: String?              // shown as an alert after an import with failures
    var finishedPrompt: FinishedPrompt?     // play / a jump was asked on a finished book: start a new reading?
    var marksSheetDoc: UUID?                // the library's quick look at a book's marks
    var musicModeShown = false              // Müzik modu: the book's sentences with the music, no voice
    var musicFromBreak = false              // Müzik modu opened by an active wait or a music break (closes with it)
    var switchRequest: UUID?                // Yolda's quick switch: the reader opens this book (and reads on)
    var markChain: MarkChain?               // the mark just made, which holding (or ⏭ again) grows backwards
    var automationChoice: AutomationChoice? // automation: the step's book is finished, what now?
    @ObservationIgnored var automationChoiceWaiter: CheckedContinuation<AutomationChoice.Answer, Never>?
    var folder: String?                     // library folder being viewed (nil = all)
    let automations = AutomationStore()
    let workout = WorkoutRecorder()          // Yolda: the ride or walk recorded while the moving mode is on
    var automationRun: AutomationRun?       // the automation playing now (Otomasyon)
    @ObservationIgnored var automationTask: Task<Void, Never>?
    @ObservationIgnored var automationWaiter: CheckedContinuation<SegmentOutcome, Never>?
    @ObservationIgnored var automationSavedAt = Date.distantPast    // the running automation's place was last written
    @ObservationIgnored let announcer = Announcer()
    var searchText = ""

    init() {
        player.onPosition = { [weak self] id, offset in
            self?.store.setPosition(id, offset)
            self?.sync.positionsChanged()
            if let p = self?.player { self?.listening.position(id, offset, length: p.length, text: p.excerptWord) }
            self?.automationTick()
        }
        listening.start(player)
        player.onFinished = { [weak self] id in self?.documentFinished(id) }
        ElevenLabs.shared.onChange = { [weak self] in self?.player.elevenChanged() }
        CloudVoice.shared.onChange = { [weak self] in self?.player.elevenChanged() }
        // a finished book does not move and does not play until the reader starts a new reading of it
        player.mayMove = { [weak self] id, offset in
            guard let self, let d = self.store.document(id), d.isFinished else { return true }
            self.finishedPrompt = FinishedPrompt(id: id, title: d.title, finishedAt: d.finishedAt ?? .now,
                                                 times: d.finishes.count, target: offset < d.length - 1 && offset > 0 ? offset : nil)
            return false
        }
        player.remoteChoice = { [weak self] key in self?.answerAutomationChoice(key: key) ?? false }
        player.onSegmentEnd = { [weak self] in self?.segmentEnded(.timeUp) }
        player.marks = { [weak self] unit in
            guard let self, let id = self.player.documentID, let d = self.store.document(id) else { return [] }
            return unit == .bookmark ? d.bookmarks.map(\.offset) : d.highlights.map(\.location)
        }
        sync = SyncEngine(model: self)
        // bicycle mode: the headphone's ⏭ marks the sentence being read, ⏮ starts / stops a voice note
        player.remoteSkip = { [weak self] forward in
            guard let self, self.settings.bikeMode, self.readerOpen, self.player.documentID != nil else { return false }
            if forward {
                // ⏭ again within four seconds: the mark takes in the sentence before it
                if let c = self.markChain, Date.now.timeIntervalSince(c.at) < 4, self.extendMarkBack() != nil { return true }
                self.markSpokenSentence()
            } else { self.toggleVoiceNote() }
            return true
        }
        notes.mirror()
        UIDevice.current.isBatteryMonitoringEnabled = true      // the moving modes show the battery from the first second
        workout.weight = { [weak self] in self?.settings.bodyWeight ?? 0 }
        workout.nowListening = { [weak self] in self?.player.isPlaying == true ? self?.player.documentID : nil }
        if settings.bikeMode { workout.start(settings.moveKind) }     // the app was closed on the way: go on recording
        applyAudioSettings()
        setUpSeriesFolders()
        if !UserDefaults.standard.bool(forKey: "voiceDefaults.v2") {      // the approved voice set: Ema Tok for Turkish
            UserDefaults.standard.set(true, forKey: "voiceDefaults.v2")
            settings.voiceByLanguage["tr"] = VoiceProfile.emaTok.id
        }
        if store.isEmpty, !UserDefaults.standard.bool(forKey: "quickStartAdded") {
            UserDefaults.standard.set(true, forKey: "quickStartAdded")
            if let qs = DocumentImporter.fromClipboard(QuickStart.text) {
                var d = qs
                d.title = "Hızlı Başlangıç"
                d.sourceName = "Voice Reader"
                try? store.add(d, original: nil)
            }
        }
    }

    // MARK: series folders

    /// The listening series, plus literature. Created once; a document whose title starts with a series name
    /// ("Bilimler 01 — Alet") is filed there when it arrives.
    static let seriesFolders = ["Felsefe", "Bilimler", "Mühendislik", "Edebiyat"]

    private func setUpSeriesFolders() {
        guard !UserDefaults.standard.bool(forKey: "seriesFolders.v1") else { return }
        UserDefaults.standard.set(true, forKey: "seriesFolders.v1")
        for f in Self.seriesFolders { store.addFolder(f) }
        for d in store.documents where d.folder == nil {
            if let f = Self.seriesFolder(for: d.title) { store.update(d.id) { $0.folder = f } }
        }
    }

    static func seriesFolder(for title: String) -> String? {
        let t = title.trimmingCharacters(in: .whitespaces)
        for f in ["Felsefe", "Bilimler", "Mühendislik"] where t.range(of: f, options: [.anchored, .caseInsensitive], locale: Locale(identifier: "tr")) != nil {
            return f
        }
        return nil
    }

    // MARK: library view

    func visibleDocuments() -> [DocumentRecord] {
        var list = store.documents
        if let f = folder { list = list.filter { $0.folder == f } }
        switch settings.filter {
        case .all: break
        case .unread: list = list.filter(\.isUnread)
        case .inProgress: list = list.filter { !$0.isUnread && !$0.isFinished }
        case .finished: list = list.filter(\.isFinished)
        case .flagged: list = list.filter { $0.flag != nil }
        }
        let q = searchText.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            list = list.filter { $0.title.localizedStandardContains(q) || ($0.author ?? "").localizedStandardContains(q) }
        }
        switch settings.sortOrder {
        case .lastOpened: list.sort { ($0.lastOpenedAt ?? $0.addedAt) > ($1.lastOpenedAt ?? $1.addedAt) }
        case .addDate: list.sort { $0.addedAt > $1.addedAt }
        case .title: list.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .author: list.sort { ($0.author ?? "~").localizedStandardCompare($1.author ?? "~") == .orderedAscending }
        case .duration: list.sort { $0.length < $1.length }
        case .progress: list.sort { $0.progress > $1.progress }
        }
        return list
    }

    /// Documents in a folder (or all / unfiled), sorted and filtered as set in the folder screen.
    func documents(in scope: FolderScope, applyFilter: Bool) -> [DocumentRecord] {
        var list: [DocumentRecord]
        switch scope {
        case .all: list = store.documents
        case .unfiled: list = store.documents.filter { $0.folder == nil }
        case .named(let n): list = store.documents.filter { $0.folder == n }
        }
        if applyFilter {
            switch settings.filter {
            case .all: break
            case .unread: list = list.filter(\.isUnread)
            case .inProgress: list = list.filter { !$0.isUnread && !$0.isFinished }
            case .finished: list = list.filter(\.isFinished)
            case .flagged: list = list.filter { $0.flag != nil }
            }
        }
        let q = searchText.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            list = list.filter { $0.title.localizedStandardContains(q) || ($0.author ?? "").localizedStandardContains(q) }
        }
        switch settings.sortOrder {
        case .lastOpened: list.sort { ($0.lastOpenedAt ?? $0.addedAt) > ($1.lastOpenedAt ?? $1.addedAt) }
        case .addDate: list.sort { $0.addedAt > $1.addedAt }
        case .title: list.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .author: list.sort { ($0.author ?? "~").localizedStandardCompare($1.author ?? "~") == .orderedAscending }
        case .duration: list.sort { $0.length < $1.length }
        case .progress: list.sort { $0.progress > $1.progress }
        }
        return list
    }

    /// The document before/after this one in its folder, in the library's sort order.
    func neighbor(of id: UUID, forward: Bool) -> DocumentRecord? {
        guard let d = store.document(id) else { return nil }
        let list = documents(in: d.folder.map { .named($0) } ?? .all, applyFilter: false)
        guard let i = list.firstIndex(where: { $0.id == id }) else { return nil }
        let j = forward ? i + 1 : i - 1
        return list.indices.contains(j) ? list[j] : nil
    }

    /// The last documents listened to, newest first (home screen).
    func recentDocuments(limit: Int) -> [DocumentRecord] {
        Array(store.documents.filter { $0.lastOpenedAt != nil }
            .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
            .prefix(limit))
    }

    /// Home screen folder tiles: every document, each folder, and the unfiled ones if any.
    func folderScopes() -> [FolderScope] {
        var l: [FolderScope] = [.all]
        let series = Self.seriesFolders.filter { store.folders.contains($0) }
        l += (series + store.folders.filter { !series.contains($0) }).map { .named($0) }
        if store.documents.contains(where: { $0.folder == nil }) && !store.folders.isEmpty { l.append(.unfiled) }
        return l
    }

    func statusText(_ d: DocumentRecord) -> String {
        if d.isFinished { return d.finishes.count >= 2 ? "Bitti · \(d.finishes.count) kez" : "Bitti" }
        let left = duration(characters: d.length - d.position, speed: d.speed)
        let pass = d.readingNumber >= 2 ? "\(d.readingNumber). okuma · " : ""
        return d.isUnread ? Format.duration(left) : "\(pass)%\(Int(d.progress * 100)) · \(Format.duration(left)) kaldı"
    }

    /// Listening time for a number of characters at the current speed.
    func duration(characters: Int, speed: Double? = nil) -> TimeInterval {
        Double(characters) / (player.charsPerSecond * (speed ?? settings.speed))
    }

    // MARK: opening

    /// `automated`: an automation step opens it (the session is handed over, the automation goes on); any other
    /// opening of a different document ends a running automation.
    func open(_ id: UUID, automated: Bool = false) async {
        guard let doc = store.document(id) else { return }
        if !automated, automationRun != nil, player.documentID != id { stopAutomation() }
        openDocumentID = id
        if player.documentID != id {
            guard let content = await store.content(for: id) else { return }
            player.load(id: id, title: doc.title, author: doc.author, content: content, at: doc.position, handover: automated)
            player.studio = store.studioPack(id)
        }
        store.update(id) { $0.lastOpenedAt = .now }
        UserDefaults.standard.set(id.uuidString, forKey: "lastDocument")
        applyAudioSettings()
        if let profile = VoiceProfile.with(id: currentVoiceID) { ProfileRenderer.shared.warmUp(profile) }
    }

    /// After a restart the last document is back in the mini player, at its place, not playing.
    func restoreLastDocument() async {
        guard player.documentID == nil,
              let raw = UserDefaults.standard.string(forKey: "lastDocument"), let id = UUID(uuidString: raw),
              let doc = store.document(id), let content = await store.content(for: id) else { return }
        player.load(id: id, title: doc.title, author: doc.author, content: content, at: doc.position)
        player.studio = store.studioPack(id)
        applyAudioSettings()
    }

    /// Settings screens call this: changes are gathered for a moment and applied once, after the finger stops,
    /// so dragging a slider while reading never makes the reader restart its sentence on every step.
    func applyAudioSettingsSoon() {
        applyTask?.cancel()
        applyTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            self?.applyAudioSettings()
        }
    }
    @ObservationIgnored private var applyTask: Task<Void, Never>?

    func applyAudioSettings() {
        let doc = player.documentID.flatMap { store.document($0) }
        let lang = Voices.base(doc?.language ?? "tr")
        player.speed = doc?.speed ?? settings.speed
        player.pitch = settings.pitch
        player.startAtSentence = settings.startAtSentence
        player.options = SpokenText.Options(simplifyLinks: settings.simplifyLinks, skipCitations: settings.skipCitations)
        player.baseLanguage = lang == "en" ? "en" : "tr"
        player.mixedLanguage = settings.mixedLanguage && (lang == "tr" || lang == "en")
        player.musicMix = settings.musicMix
        player.musicLevel = settings.musicLevel
        player.clearVoice = settings.clearVoice
        player.systemSpeech = settings.systemSpeech
        player.breakEvery = settings.musicBreak ? settings.breakMinutes * 60 : 0
        player.breakLength = settings.breakSeconds
        player.remotePauseWaits = settings.remotePauseWaits
        player.remotePauseSeconds = settings.waitSeconds > 0 ? settings.waitSeconds : nil
        player.voiceDepth = settings.voiceDepth
        player.voiceTune = settings.voiceTune
        player.voiceID = currentVoiceID
        player.otherVoiceID = voiceID(forLanguage: lang == "en" ? "tr" : "en")
    }

    var currentDocument: DocumentRecord? { player.documentID.flatMap { store.document($0) } }

    /// The voice chosen for a language: settings, else Ema Tok for Turkish, else the best installed voice.
    func voiceID(forLanguage l: String) -> String {
        let l = Voices.base(l)
        if let id = settings.voiceByLanguage[l], id == ElevenLabs.readerVoiceID || id == CloudVoice.readerVoiceID || (VoiceProfile.with(id: id)?.isAvailable ?? (Voices.voice(id) != nil)) {
            return id
        }
        if l == "tr" { return VoiceProfile.emaTok.id }
        return Voices.defaultVoice(for: l, chosen: [:])?.identifier ?? ""
    }

    /// The open document's voice id: a Voice Reader profile ("vr.…") or a system voice identifier.
    var currentVoiceID: String {
        if let id = currentDocument?.voiceID, id == ElevenLabs.readerVoiceID || id == CloudVoice.readerVoiceID || VoiceProfile.with(id: id) != nil || Voices.voice(id) != nil { return id }
        return voiceID(forLanguage: currentDocument?.language ?? "tr")
    }

    var currentVoiceName: String {
        let id = currentVoiceID
        if id == ElevenLabs.readerVoiceID { return ElevenLabs.shared.displayName }
        if id == CloudVoice.readerVoiceID { return CloudVoice.shared.displayName }
        return VoiceProfile.with(id: id)?.name ?? Voices.voice(id)?.name ?? "Ses"
    }

    func setVoice(id: String, language: String, documentOnly: Bool) {
        if documentOnly, let doc = player.documentID {
            store.update(doc) { $0.voiceID = id }
        } else {
            settings.voiceByLanguage[Voices.base(language)] = id
            if let doc = player.documentID, Voices.base(language) == Voices.base(currentDocument?.language ?? "tr") {
                store.update(doc) { $0.voiceID = nil }
            }
        }
        applyAudioSettings()
    }

    /// The current voice is a system voice (Yelda, Cem…): its speed is shown in words a minute, as in Voice Dream.
    var isSystemVoice: Bool { VoiceProfile.with(id: currentVoiceID) == nil && currentVoiceID != ElevenLabs.readerVoiceID && currentVoiceID != CloudVoice.readerVoiceID }

    func tune(_ id: String) -> VoiceTune {
        settings.voiceTune[id] ?? VoiceTune(pitch: VoiceProfile.with(id: id) == nil ? settings.pitch : 1, volume: 1)
    }
    func setTune(_ id: String, _ t: VoiceTune) {
        settings.voiceTune[id] = t
        applyAudioSettingsSoon()
    }

    /// Voice Dream's setting for a system voice, as the user's Voice Dream has it for Yelda: Hız 330, Ses Miktarı 100,
    /// Kalınlık 50, and nothing else. Voice Dream has no equalizer or other processing (its code sets only the
    /// utterance's rate, volume and pitchMultiplier), so Düzlük and Net ve gür ses go off: the voice plays as made.
    func applyVoiceDreamSetting() {
        guard isSystemVoice else { return }
        settings.voiceTune[currentVoiceID] = VoiceTune(pitch: 0.5, volume: 1, steady: 0)
        settings.clearVoice = false
        setSpeed(330 / SpeechPlayer.wordsAtOneX, documentOnly: false)
    }

    func setSpeed(_ s: Double, documentOnly: Bool) {
        // system voices move in steps of 5 words a minute, Voice Reader's own voices in steps of 0.05×
        let unit = isSystemVoice ? 5 / SpeechPlayer.wordsAtOneX : 0.05
        let v = (s / unit).rounded() * unit
        if documentOnly, let id = player.documentID {
            store.update(id) { $0.speed = v }
        } else {
            settings.speed = v
            if let id = player.documentID { store.update(id) { $0.speed = nil } }
        }
        applyAudioSettings()
    }

    var speedIsDocumentSpecific: Bool { currentDocument?.speed != nil }

    /// The reading was heard to its end: the book is finished, at its end, and stays there. Nothing takes it back to
    /// the start except the reader's own "Baştan başla" (a new reading, counted).
    private func documentFinished(_ id: UUID) {
        if let d = store.document(id) {
            store.setPosition(id, d.length)
            if !d.isFinished {
                let now = Date.now
                store.update(id) { $0.finishedAt = now; $0.finishes.append(now) }
                store.saveNow()
            }
        }
        if automationRun != nil { segmentEnded(.finished); return }
        switch settings.endBehavior {
        case .stopAtEnd: break
        case .keepGoing:
            let list = visibleDocuments()
            guard let i = list.firstIndex(where: { $0.id == id }),
                  let next = list[(i + 1)...].first(where: { !$0.isFinished })?.id else { return }
            Task {
                await open(next)
                player.play()
            }
        }
    }

    // MARK: importing

    func importFiles(_ urls: [URL], fromSync: Bool = false) async {
        importing = true
        defer { importing = false }
        var failures: [String] = []
        var lastAdded: UUID?
        let tmp = FileManager.default.temporaryDirectory.appending(path: "import-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            let copy = tmp.appending(path: url.lastPathComponent)
            try? FileManager.default.removeItem(at: copy)
            let copied = (try? FileManager.default.copyItem(at: url, to: copy)) != nil
            if scoped { url.stopAccessingSecurityScopedResource() }
            guard copied else { failures.append("“\(url.lastPathComponent)” kopyalanamadı."); continue }
            let result = await Task.detached(priority: .userInitiated) { () -> Result<ImportedDocument, Error> in
                Result { try DocumentImporter.importFile(at: copy) }
            }.value
            switch result {
            case .success(let doc):
                if let rec = try? store.add(doc, original: copy) {
                    lastAdded = rec.id
                    if let f = folder ?? Self.seriesFolder(for: rec.title) { store.update(rec.id) { $0.folder = f } }
                    sync.publish(rec.id)
                }
            case .failure(let e):
                failures.append((e as? LocalizedError)?.errorDescription ?? "“\(url.lastPathComponent)” eklenemedi.")
            }
        }
        if !failures.isEmpty { importMessage = failures.joined(separator: "\n") }
        _ = lastAdded
    }

    /// Files dropped into "On My iPhone › Voice Reader" (the app's Documents folder, visible in the Files app) join the
    /// library on launch and whenever the app comes back to the foreground; the dropped copy is then removed.
    func scanDropFolder() async {
        let docs = URL.documentsDirectory
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: docs, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return }
        for pack in items where pack.pathExtension == "vrstudio" { importStudio(pack) }
        let files = items.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        guard !files.isEmpty, !importing else { return }
        await importFiles(files)
        for f in files { try? fm.removeItem(at: f) }
    }

    /// A book voiced on the Mac (Voice Reader Studio, `<name>.vrstudio` dropped into the Documents folder): added as a
    /// document with the Anlatıcı voice, or, if it is already in the library (same id), its audio is replaced, so a
    /// longer render of the same book simply updates it. The dropped folder is removed once it is in place.
    func importStudio(_ pack: URL) {
        // a pack that is still being copied in (book.json or some audio not there yet): wait for the next scan
        guard let book = try? StudioPack.readDocument(pack), let files = StudioPack.load(pack)?.segments.map(\.file),
              !files.isEmpty else { return }
        let audio = Set((try? FileManager.default.contentsOfDirectory(atPath: pack.appending(path: "audio").path)) ?? [])
        guard files.allSatisfy(audio.contains) else { return }
        let id = book.id ?? UUID()
        do {
            if store.document(id) == nil {
                let words = book.content.text.split(whereSeparator: { $0 == " " || $0 == "\n" }).count
                var rec = DocumentRecord(title: book.title, author: book.author, format: .txt, sourceName: pack.lastPathComponent,
                                         length: book.content.text.utf16.count, wordCount: words, language: "tr")
                rec.id = id
                rec.voiceID = VoiceProfile.studio.id
                rec.folder = Self.seriesFolder(for: book.title)
                try store.insert(rec, content: book.content, cover: nil)
            }
            try store.installStudio(id, from: pack)
            try? FileManager.default.removeItem(at: pack)
            if player.documentID == id { player.studio = store.studioPack(id) }
        } catch {
            importMessage = "Stüdyo kitabı eklenemedi: \(error.localizedDescription)"
        }
    }

    /// A file handed over by another app ("Open in Voice Reader", AirDrop): import it, then open it.
    func handleOpen(_ url: URL) async {
        let before = Set(store.documents.map(\.id))
        await importFiles([url])
        if url.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: url) }
        if let new = store.documents.first(where: { !before.contains($0.id) }) {
            await open(new.id)
        }
    }

    func importClipboard() {
        guard let s = UIPasteboard.general.string, let doc = DocumentImporter.fromClipboard(s) else {
            importMessage = "Panoda metin yok."
            return
        }
        if let rec = try? store.add(doc, original: nil) {
            if let f = folder { store.update(rec.id) { $0.folder = f } }
            sync.publish(rec.id)
        }
    }

    // MARK: document actions

    func delete(_ ids: [UUID], fromSync: Bool = false) {
        if let cur = player.documentID, ids.contains(cur) { player.unload() }
        if let o = openDocumentID, ids.contains(o) { openDocumentID = nil }
        store.delete(ids)
        var gone = UserDefaults.standard.stringArray(forKey: "sync.deleted") ?? []
        gone += ids.map(\.uuidString)
        UserDefaults.standard.set(gone, forKey: "sync.deleted")
        guard !fromSync else { return }
        for id in ids {
            sync.record(SyncEvent(kind: .docDelete, doc: id))
            if let files = sync.files { Task { await files.removeDocument(id) } }
        }
    }

    /// "Başa sar" on a book being read (asked first in the menus). A finished book goes back only through
    /// `startReadingAgain`.
    func rewindToBeginning(_ id: UUID) {
        guard let d = store.document(id) else { return }
        if d.isFinished { startReadingAgain(id); return }
        store.setPosition(id, 0)
        sync.positionsChanged()
        if player.documentID == id { player.moveCursor(to: 0, play: false) }
    }

    /// The reader started a finished book again: a new reading (2., 3.…) from the start or from the place chosen.
    /// The readings already finished stay in `finishes`.
    func startReadingAgain(_ id: UUID, at offset: Int = 0, play: Bool = false) {
        guard let d = store.document(id) else { return }
        let at = min(max(0, offset), max(0, d.length - 1))
        store.update(id) { $0.finishedAt = nil }
        store.setPosition(id, at)
        store.saveNow()
        sync.positionsChanged()
        if player.documentID == id { player.moveCursor(to: at, play: play) }
    }

    func addBookmark() {
        guard let id = player.documentID else { return }
        let at = player.cursor
        let ex = player.excerpt(at: at)
        guard store.document(id)?.bookmarks.contains(where: { abs($0.offset - at) < 5 }) != true else { return }
        let b = Bookmark(offset: at, excerpt: ex)
        store.update(id) { d in
            d.bookmarks.append(b)
            d.bookmarks.sort { $0.offset < $1.offset }
        }
        sync.record(SyncEvent(kind: .bookmarkAdd, doc: id, bookmark: b))
    }

    func addBookmark(at offset: Int) {
        guard let id = player.documentID else { return }
        let b = Bookmark(offset: offset, excerpt: player.excerpt(at: offset))
        store.update(id) { d in
            d.bookmarks.append(b)
            d.bookmarks.sort { $0.offset < $1.offset }
        }
        sync.record(SyncEvent(kind: .bookmarkAdd, doc: id, bookmark: b))
    }

    func addHighlight(_ range: NSRange, color: HighlightColor, text: String, note: String? = nil) {
        guard let id = player.documentID, range.length > 0 else { return }
        let replaced = store.document(id)?.highlights.filter { NSIntersectionRange($0.range, range).length == $0.length } ?? []
        // a recolour or a merge keeps the notes of the marks it replaces
        let kept = replaced.compactMap(\.note).filter { !$0.isEmpty }
        let h = Highlight(location: range.location, length: range.length, color: color, text: text,
                          note: note ?? (kept.isEmpty ? nil : kept.joined(separator: "\n")))
        store.update(id) { d in
            d.highlights.removeAll { r in replaced.contains { $0.id == r.id } }      // fully covered: replace
            d.highlights.append(h)
            d.highlights.sort { $0.location < $1.location }
        }
        for old in replaced { sync.record(SyncEvent(kind: .highlightRemove, doc: id, ref: old.id)) }
        sync.record(SyncEvent(kind: .highlightAdd, doc: id, highlight: h))
    }

    func removeHighlight(_ hid: UUID) {
        guard let id = player.documentID else { return }
        store.update(id) { $0.highlights.removeAll { $0.id == hid } }
        sync.record(SyncEvent(kind: .highlightRemove, doc: id, ref: hid))
    }

    func setNote(_ hid: UUID, _ note: String?) {
        guard let id = player.documentID else { return }
        store.update(id) { d in
            if let i = d.highlights.firstIndex(where: { $0.id == hid }) { d.highlights[i].note = note?.isEmpty == true ? nil : note }
        }
        sync.record(SyncEvent(kind: .highlightNote, doc: id, ref: hid, text: note))
    }

    func removeBookmark(_ bid: UUID) {
        guard let id = player.documentID else { return }
        store.update(id) { $0.bookmarks.removeAll { $0.id == bid } }
        sync.record(SyncEvent(kind: .bookmarkRemove, doc: id, ref: bid))
    }

    // MARK: library edits (recorded for the other devices)

    func setFolder(_ id: UUID, _ folder: String?) {
        store.update(id) { $0.folder = folder }
        sync.record(SyncEvent(kind: .docFolder, doc: id, text: folder))
    }

    func setFlag(_ id: UUID, _ flag: HighlightColor?) {
        store.update(id) { $0.flag = flag }
        sync.record(SyncEvent(kind: .docFlag, doc: id, text: flag?.rawValue))
    }

    func rename(_ id: UUID, to title: String) {
        guard !title.isEmpty else { return }
        store.update(id) { $0.title = title }
        sync.record(SyncEvent(kind: .docTitle, doc: id, text: title))
    }

    func addFolder(_ name: String) {
        store.addFolder(name)
        sync.record(SyncEvent(kind: .folderAdd, text: name))
    }

    func removeFolder(_ name: String) {
        store.removeFolder(name)
        sync.record(SyncEvent(kind: .folderRemove, text: name))
    }

    func renameFolder(_ old: String, to new: String) {
        store.renameFolder(old, to: new)
        sync.record(SyncEvent(kind: .folderRename, text: old, text2: new))
    }

    /// A change made on another device; applied here without being recorded again.
    func apply(_ e: SyncEvent) {
        switch e.kind {
        case .highlightAdd:
            guard let id = e.doc, let h = e.highlight else { return }
            store.update(id) { d in
                guard !d.highlights.contains(where: { $0.id == h.id }) else { return }
                d.highlights.append(h); d.highlights.sort { $0.location < $1.location }
            }
        case .highlightRemove:
            guard let id = e.doc, let r = e.ref else { return }
            store.update(id) { $0.highlights.removeAll { $0.id == r } }
        case .highlightNote:
            guard let id = e.doc, let r = e.ref else { return }
            store.update(id) { d in if let i = d.highlights.firstIndex(where: { $0.id == r }) { d.highlights[i].note = e.text } }
        case .bookmarkAdd:
            guard let id = e.doc, let b = e.bookmark else { return }
            store.update(id) { d in
                guard !d.bookmarks.contains(where: { $0.id == b.id }) else { return }
                d.bookmarks.append(b); d.bookmarks.sort { $0.offset < $1.offset }
            }
        case .bookmarkRemove:
            guard let id = e.doc, let r = e.ref else { return }
            store.update(id) { $0.bookmarks.removeAll { $0.id == r } }
        case .docFolder:
            guard let id = e.doc else { return }
            if let f = e.text { store.addFolder(f) }
            store.update(id) { $0.folder = e.text }
        case .docFlag:
            guard let id = e.doc else { return }
            store.update(id) { $0.flag = e.text.flatMap(HighlightColor.init(rawValue:)) }
        case .docTitle:
            guard let id = e.doc, let t = e.text else { return }
            store.update(id) { $0.title = t }
        case .docDelete:
            guard let id = e.doc, store.document(id) != nil else { return }
            delete([id], fromSync: true)
        case .folderAdd:
            if let n = e.text { store.addFolder(n) }
        case .folderRemove:
            if let n = e.text { store.removeFolder(n) }
        case .folderRename:
            if let a = e.text, let b = e.text2 { store.renameFolder(a, to: b) }
        }
    }

    /// Pages appended to a document (Claude, via Library/<id>/parts): added to the end of the text, so every
    /// earlier position, highlight and bookmark keeps its place.
    func appendParts(_ pages: [String], to id: UUID) async {
        guard var content = await store.content(for: id) else { return }
        var text = content.text
        var length = (text as NSString).length
        for page in pages {
            let (paragraphs, headings) = DocumentImporter.parseMarkdown(page)
            var offsets: [Int] = []
            for p in paragraphs {
                offsets.append(length)
                text += p + "\n"
                length += (p as NSString).length + 1
            }
            for h in headings where h.paragraph < offsets.count {
                content.chapters.append(Chapter(title: h.title, offset: offsets[h.paragraph], level: h.level))
            }
        }
        content.text = text
        var words = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in words += 1 }
        store.replaceContent(id, with: content, wordCount: words)
        store.update(id) { $0.partsApplied = ($0.partsApplied ?? 0) + pages.count }
        if player.documentID == id { player.extend(content) }
    }

    /// Highlights and notes as Markdown, for sharing.
    func highlightsExport(_ doc: DocumentRecord) -> String {
        var s = "# \(doc.title)\n"
        if let a = doc.author { s += "_\(a)_\n" }
        s += "\n"
        for h in doc.highlights {
            s += "> \(h.text)\n"
            if let n = h.note { s += "\n\(n)\n" }
            s += "\n"
        }
        return s
    }
}
