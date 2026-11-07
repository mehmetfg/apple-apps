// Ties the library, the settings and the player together; everything the screens do goes through here.
import SwiftUI
import AVFoundation
import Observation
import PDMBus

@MainActor
@Observable
final class AppModel {
    /// The one model of the process, for the system actions (they can run with no window).
    @ObservationIgnored nonisolated(unsafe) static weak var current: AppModel?
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
    /// The PDM bus (the apps' shared folder): one native event (a book finished) and the live state for the other apps.
    @ObservationIgnored let bus = PDMBus(app: "wisepath", vaultRoot: { VaultMirror.connectedRoot })
    @ObservationIgnored private let busQueue = DispatchQueue(label: "voice-reader.bus", qos: .utility)
    /// Each opened book's id in Teoria, once found (absent: not looked up yet or not in Teoria).
    var teoriaIDs: [UUID: String] = [:]
    /// Bumped when a link asks the open reader to show a place (`revealRequest`).
    var revealTick = 0

    init() {
        player.onPosition = { [weak self] id, offset in
            self?.store.setPosition(id, offset)
            self?.sync.positionsChanged()
            self?.publishLive()
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
        installSystemSurface()
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
        Self.statusText(d, charsPerSecond: player.charsPerSecond, speed: settings.speed)
    }

    /// The same text from plain values, for work off the main thread (the widget snapshot).
    nonisolated static func statusText(_ d: DocumentRecord, charsPerSecond: Double, speed: Double) -> String {
        if d.isFinished { return d.finishes.count >= 2 ? "Bitti · \(d.finishes.count) kez" : "Bitti" }
        let left = Double(d.length - d.position) / (charsPerSecond * (d.speed ?? speed))
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
        publishLive()
        findTeoriaID(id, title: doc.title)
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
        publishLive()
        findTeoriaID(id, title: doc.title)
    }

    // MARK: the PDM bus

    /// What is being read now, for the other apps on this phone. Called on opening, play, pause, the end, and with
    /// the player's place reports (every couple of seconds); the bus writes only when something changed, and the
    /// write happens off the main thread.
    func publishLive() {
        guard let id = player.documentID else { return }
        let length = max(1, player.length)
        let live = PDMLive(app: "wisepath", kind: "book", id: id.uuidString, title: player.title,
                           detail: player.chapterTitle(at: player.cursor),
                           progress: min(1, max(0, Double(player.cursor) / Double(length))), active: player.isPlaying,
                           link: "wisepath://book/\(id.uuidString)", refs: teoriaIDs[id].map { ["teoria": $0] })
        let bus = bus
        busQueue.async { bus.publishLive(live) }
        ReadingCard.shared.sync(self)
    }

    private func findTeoriaID(_ id: UUID, title: String) {
        guard teoriaIDs[id] == nil else { return }
        Task {
            guard let found = await VaultMirror.shared.teoriaID(document: id, title: title) else { return }
            teoriaIDs[id] = found
            publishLive()
        }
    }

    /// The app came to the front (after its own sync): today's opening, then the events waiting go to the vault.
    func busActivated() async {
        _ = await VaultMirror.shared.connect()
        let bus = bus
        busQueue.async { bus.emitOpenedToday() }
        await bus.sync()
    }

    /// Teoria's page of this book, when Teoria knows it.
    func openInTeoria(_ id: UUID) {
        guard let t = teoriaIDs[id], let url = URL(string: "teoria://kitap/\(t)") else { return }
        UIApplication.shared.open(url)
    }

    /// Kıvılcım starts a recording about this book.
    func talkAboutBook(_ id: UUID) {
        guard let d = store.document(id) else { return }
        var c = URLComponents()
        c.scheme = "kivilcim"; c.host = "kaydet"
        c.queryItems = [URLQueryItem(name: "topic", value: teoriaIDs[id] ?? "k:\(d.title)")]
        if let url = c.url { UIApplication.shared.open(url) }
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
        player.fastClear = settings.fastClear
        player.systemSpeech = settings.systemSpeech
        player.breakEvery = settings.musicBreak ? settings.breakMinutes * 60 : 0
        player.breakLength = settings.breakSeconds
        player.remotePauseWaits = settings.remotePauseWaits
        player.remotePauseSeconds = settings.waitSeconds > 0 ? settings.waitSeconds : nil
        player.steadyCloud = settings.steadyCloud
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

    /// "Bu tınıyı Wise Path'e al": the Turkish voice is measured as the phone's Spoken Content settings make it, then
    /// Wise Path's own Kalınlık (and speed, when iOS ruled it) are set to the same sound and the phone's settings are
    /// let go, so the speed button and Kalınlık work in the app. Level and cleaning stay as they were in that mode
    /// (VoiceMaster, +4 dB). When this phone's engine cannot reach the pitch, nothing changes.
    func adoptPhoneVoice() async -> String {
        let id = Voices.voice(currentVoiceID)?.language.hasPrefix("tr") == true ? currentVoiceID
            : AVSpeechSynthesisVoice(language: "tr-TR")?.identifier ?? currentVoiceID
        let m = await withCheckedContinuation { (k: CheckedContinuation<PhoneVoice?, Never>) in
            ProfileRenderer.shared.queue.async { k.resume(returning: ProfileRenderer.shared.phoneVoice(voiceID: id)) }
        }
        guard let m else { return "Ölçülemedi: Türkçe ses üretilemedi. Ayar değişmedi." }
        let hz = "iPhone ayarı \(Int(m.phoneHz.rounded())) Hz, Wise Path \(Int(m.ownHz.rounded())) Hz"
        guard m.matched else {
            return "Bu iPhone'da Wise Path aynı kalınlığa inemedi (\(hz)). Ayar değişmedi; iPhone'un ayarıyla okumaya devam."
        }
        var t = tune(id)
        t.pitch = m.kalinlik
        t.volume = 1
        settings.voiceTune[id] = t
        settings.referenceHz = m.phoneHz
        settings.clearVoice = true
        settings.systemSpeech = false
        if let s = m.speed { setSpeed(s, documentOnly: false) } else { applyAudioSettings() }
        let speed = m.speed.map { _ in " · Hız \(SpeechPlayer.wpm(settings.speed))" } ?? ""
        return "Alındı: Kalınlık \(Int((m.kalinlik * 100).rounded()))\(speed) (\(hz)). Artık hız ve kalınlık Wise Path'ten."
    }

    /// "Kararlı ölçüye getir" for an iPhone voice other than the one in use (Cem, a Gelişmiş voice…): its melody is
    /// measured and Düzlük is set so that it comes down toward Yelda's 3.7 semitones (at most 40 % narrower); a voice
    /// that is higher than the reader's own measured pitch is brought down to it with Kalınlık. Level and cleaning
    /// are the same chain as Yelda's (VoiceMaster), so the loudness is the same.
    func steadyVoice() async -> String {
        let id = currentVoiceID
        guard isSystemVoice, Voices.voice(id) != nil else { return "Bu ayar iPhone sesleri içindir." }
        let before = tune(id)
        guard let r = await steadyMeasure(id) else { return "Ölçülemedi; ayar değişmedi." }
        let t = steadyTune(before, hz: r.hz, spread: r.spread)
        settings.systemSpeech = false
        settings.clearVoice = true
        settings.voiceTune[id] = t
        applyAudioSettings()
        let pitch = t.pitch != before.pitch ? " · Kalınlık \(Int((t.pitch * 100).rounded()))" : ""
        return String(format: "Bu ses: %.0f Hz, melodi %.1f yarım ton. Düzlük %%%d%@ olarak ayarlandı (hedef 3,7 yarım ton).",
                      r.hz, r.spread, Int((t.steady * 100).rounded()), pitch)
    }

    /// The same measure for every other Turkish iPhone voice, so that changing the voice keeps the steadiness. A voice
    /// the user has already set (its own Kalınlık or Düzlük) is left as it is, and so is the voice in use.
    func steadyOtherVoices() async -> String {
        let current = currentVoiceID
        let voices = Voices.voices(for: "tr").filter { $0.identifier.hasPrefix("com.apple") && $0.identifier != current }
        guard !voices.isEmpty else { return "Başka Türkçe iPhone sesi kurulu değil." }
        var lines: [String] = []
        for v in voices {
            let name = v.name + (Voices.qualityName(v).map { " (\($0))" } ?? "")
            let before = tune(v.identifier)
            if before.steady > 0.01 || abs(before.pitch - 1) > 0.005 { lines.append("\(name): kendi ayarın duruyor"); continue }
            guard let r = await steadyMeasure(v.identifier) else { lines.append("\(name): ölçülemedi"); continue }
            let t = steadyTune(before, hz: r.hz, spread: r.spread)
            settings.voiceTune[v.identifier] = t
            lines.append(String(format: "%@: %.0f Hz, %.1f yarım ton → Düzlük %%%d%@", name, r.hz, r.spread, Int((t.steady * 100).rounded()),
                                t.pitch != before.pitch ? " · Kalınlık \(Int((t.pitch * 100).rounded()))" : ""))
        }
        applyAudioSettings()
        return lines.joined(separator: "\n")
    }

    /// Median pitch and melody width of an iPhone voice as it is (Kalınlık 100, no Düzlük), at the reading speed.
    private func steadyMeasure(_ id: String) async -> (hz: Double, spread: Double)? {
        let rate = SpeechPlayer.rate(for: player.speed)
        return await withCheckedContinuation { k in
            ProfileRenderer.shared.queue.async {
                let text = "Felsefe, insanın kendi aklını kendi üzerine çevirmesiyle başlar. Sokrates sorgulanmamış bir hayatın yaşanmaya değmediğini söylediğinde, Atina mahkemesi onu ölüme mahkûm etti; yine de bu cümle bugün bile okunuyor."
                let s = ProfileRenderer.shared.renderSystem(text, voiceID: id, rate: rate, tune: VoiceTune(pitch: 1, volume: 1, steady: 0), cancelled: { false })
                k.resume(returning: s.flatMap { Steady.melody($0.samples) })
            }
        }
    }

    /// Düzlük for the measured melody, and Kalınlık down to the reference voice when this one is higher.
    private func steadyTune(_ before: VoiceTune, hz: Double, spread: Double) -> VoiceTune {
        var t = before
        t.steady = ((1 - Steady.keep(for: spread)) * 20).rounded() / 20
        let reference = settings.referenceHz
        if reference > 60, hz > reference * 1.06 {
            t.pitch = min(max((SystemPitch.kalinlik(ratio: reference / hz) * 100).rounded() / 100, SystemPitch.reachesDeep ? 0.2 : 0.5), 1)
        }
        return t
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
                let bus = bus, title = d.title
                busQueue.async { bus.emit("book.finished", subject: "book:\(id.uuidString)", data: ["title": .string(title)]) }
            }
        }
        publishLive()
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

    /// `folder`: where a sync (Loader) import files the document; any other import goes to the folder the library
    /// had chosen when it began. Returns the files that became documents.
    @discardableResult
    func importFiles(_ urls: [URL], fromSync: Bool = false, folder syncFolder: String? = nil) async -> Set<URL> {
        importing = true
        defer { importing = false }
        let destination = fromSync ? syncFolder : folder
        var failures: [String] = []
        var imported: Set<URL> = []
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
                    imported.insert(url)
                    if let f = destination ?? Self.seriesFolder(for: rec.title) { store.update(rec.id) { $0.folder = f } }
                    sync.publish(rec.id)
                } else {
                    failures.append("“\(url.lastPathComponent)” eklenemedi.")
                }
            case .failure(let e):
                failures.append((e as? LocalizedError)?.errorDescription ?? "“\(url.lastPathComponent)” eklenemedi.")
            }
        }
        if !failures.isEmpty { importMessage = failures.joined(separator: "\n") }
        return imported
    }

    /// Files dropped into "On My iPhone › Voice Reader" (the app's Documents folder, visible in the Files app) join the
    /// library on launch and whenever the app comes back to the foreground; the dropped copy is then removed.
    func scanDropFolder() async {
        let docs = URL.documentsDirectory
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: docs, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return }
        for pack in items where pack.pathExtension == "vrstudio" { importStudio(pack) }
        var files = items.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        guard !files.isEmpty, !importing else { return }
        // A file still arriving stays for the next scan: an iCloud placeholder, an empty file, or one whose size
        // is still changing (the Files app is copying it in). A file that failed before is not tried (and reported)
        // again until it changes.
        func signature(_ u: URL) -> String? {
            guard let v = try? u.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isUbiquitousItemKey,
                                                           .ubiquitousItemDownloadingStatusKey]) else { return nil }
            if v.isUbiquitousItem == true, v.ubiquitousItemDownloadingStatus != .current { return nil }
            guard let size = v.fileSize, size > 0 else { return nil }
            return "\(size)-\(Int(v.contentModificationDate?.timeIntervalSince1970 ?? 0))"
        }
        let before = Dictionary(uniqueKeysWithValues: files.compactMap { f in signature(f).map { (f, $0) } })
        try? await Task.sleep(for: .milliseconds(400))
        var failed = UserDefaults.standard.dictionary(forKey: Self.dropFailedKey) as? [String: String] ?? [:]
        files = files.filter { f in
            guard let s = before[f], signature(f) == s else { return false }
            return failed[f.lastPathComponent] != s
        }
        guard !files.isEmpty, !importing else { return }
        let done = await importFiles(files)
        // only a file that became a document is removed; one that could not be read stays where the user put it
        for f in files {
            if done.contains(f) { try? fm.removeItem(at: f); failed[f.lastPathComponent] = nil }
            else if let s = before[f] { failed[f.lastPathComponent] = s }
        }
        let present = Set(items.map(\.lastPathComponent))
        failed = failed.filter { present.contains($0.key) }
        UserDefaults.standard.set(failed, forKey: Self.dropFailedKey)
    }
    private static let dropFailedKey = "drop.failed"

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
