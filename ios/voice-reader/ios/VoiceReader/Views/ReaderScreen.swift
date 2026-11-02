// The reading screen, laid out like Voice Dream: a flat top bar (icons, then ◀◀ title ▶▶), the page, and a flat bottom
// bar (contents · back · play · forward · search, the progress bar, % · chapter · skip unit). Settings open as popovers
// from the icons that own them: speaker → Ses Ayarları, Aa → Görsel Ayarlar, list → Konumlar.
import SwiftUI
import AVFoundation

struct ReaderScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accent) private var accent
    let initialID: UUID
    @State private var shownID: UUID?
    private var documentID: UUID { shownID ?? initialID }

    init(documentID: UUID) { initialID = documentID }

    @State private var content: DocumentContent?
    @State private var following = true
    @State private var scrollRequest = 0
    @State private var popover: Popover?
    @State private var searching = false
    @State private var noteSheet: NoteSheetItem?
    @State private var goTo: GoToKind?
    @State private var goToText = ""
    @State private var chromeHidden = false
    @State private var visibleOffset = 0          // the first character on screen (which way the speech cursor is)
    @State private var bikeContents = false
    @State private var moving = false             // the page is being scrolled (and a moment after it stops)
    @State private var restTask: Task<Void, Never>?
    @State private var browsing = false           // looking at a place picked from the contents or search, by choice
    @State private var rewindAsked = false
    @State private var moveDetails = false

    enum Popover { case audio, visual }
    enum GoToKind: String, Identifiable { case page, percent; var id: String { rawValue } }

    private var player: SpeechPlayer { model.player }
    private var doc: DocumentRecord? { model.store.document(documentID) }
    private var theme: ReaderTheme { model.settings.effectiveTheme(systemDark: scheme == .dark) }
    /// The Klasik page of the moving modes (big text, the three glass keys).
    private var bike: Bool { model.settings.bikeMode && model.settings.bikeLook == .classic }
    /// The dark road screen (Yolda or Kinetik).
    private var ride: Bool { model.settings.bikeMode && model.settings.bikeLook.road }
    /// The ordinary reader while the moving mode goes on (Tam metin): the whole book to browse and mark.
    private var roadBehind: Bool { model.settings.bikeMode && model.settings.bikeLook == .reader }

    @State private var peek: Peek?
    struct Peek: Identifiable { var offset: Int; var id: Int { offset } }

    var body: some View {
        Group {
            if ride {
                RideView(title: doc?.title ?? "", content: content, onBack: { dismiss() }, onContents: { bikeContents = true },
                         onJump: { o, p in jump(o, play: p) })
                    .transition(.opacity)
            } else {
                classic
            }
        }
        .animation(.smooth(duration: 0.35), value: ride)
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if roadBehind { RoadPill().transition(.move(edge: .top).combined(with: .opacity)) }
                if let d = doc, d.isFinished, !ride { FinishedBand(doc: d).transition(.opacity) }
            }
            .padding(.top, 104)
        }
        .confirmationDialog("Başa sarılsın mı?", isPresented: $rewindAsked, titleVisibility: .visible) {
            Button("Başa sar") { model.rewindToBeginning(documentID) }
            Button("Vazgeç", role: .cancel) {}
        } message: { Text("Kaldığın yer başa döner.") }
        .sheet(item: $peek) { RidePeek(offset: $0.offset, onJump: { o, p in jump(o, play: p) }) }
        .background(Color(uiColor: theme.background).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .statusBarHidden(ride || (chromeHidden && !bike))
        .animation(.smooth(duration: 0.3), value: bike)
        .animation(.smooth(duration: 0.25), value: model.recorder.isRecording)
        .animation(.smooth(duration: 0.25), value: model.noteToast)
        .sheet(item: $noteSheet) { NoteSheet(item: $0).presentationDetents([.medium, .large]) }
        .alert("Kayıt", isPresented: Binding(get: { model.recorder.error != nil }, set: { if !$0 { model.recorder.error = nil } })) {
            Button("Tamam", role: .cancel) { model.recorder.error = nil }
        } message: { Text(model.recorder.error ?? "") }
        // the screen stays on only while the text is being read (or a note recorded); paused, it sleeps as usual
        .onAppear { model.readerOpen = true; keepAwake() }
        .onDisappear {
            model.readerOpen = false
            UIApplication.shared.isIdleTimerDisabled = false
            if model.recorder.isRecording { model.finishVoiceNote() }
        }
        .onChange(of: following) { _, f in
            // bicycle: a stray touch on the page comes back to the voice by itself
            if f { browsing = false }
            guard bike, !f, !browsing else { return }
            Task {
                try? await Task.sleep(for: .seconds(4))
                if bike, !following { goToCursor() }
            }
        }
        .onChange(of: model.openNoteID) { _, id in
            guard let id else { return }
            model.openNoteID = nil
            Task { try? await Task.sleep(for: .milliseconds(350)); noteSheet = .existing(id) }
        }
        .onChange(of: bike) { _, b in if b { goToCursor(); chromeHidden = false } }
        // starting to read always brings the page back to the voice
        .onChange(of: player.isPlaying) { _, playing in
            keepAwake()
            if playing, !following { goToCursor() }
        }
        .onChange(of: model.recorder.isRecording) { _, _ in keepAwake() }
        .onChange(of: model.musicModeShown) { _, _ in keepAwake() }
        .sheet(isPresented: $bikeContents) {
            NavigationSheet(onJump: { o, p in jump(o, play: p) }, onShow: { o in if ride { peek = Peek(offset: o) } else { show(o) } }, large: true)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $searching) { SearchSheet(text: content?.text ?? "", onJump: show) }
        .alert(goTo == .page ? "Sayfaya git" : "Yüzdeye git", isPresented: Binding(get: { goTo != nil }, set: { if !$0 { goTo = nil } })) {
            TextField(goTo == .page ? "Sayfa (1–\(content?.pages.count ?? 1))" : "Yüzde (0–100)", text: $goToText)
                .keyboardType(.numberPad)
            Button("Git") { performGoTo() }
            Button("Vazgeç", role: .cancel) { goTo = nil }
        }
        .onChange(of: switchTo) { _, n in if let n { shownID = n; switchTo = nil } }
        // the moving modes' quick switch: another book, without leaving the mode
        .onChange(of: model.switchRequest) { _, n in
            guard let n else { return }
            model.switchRequest = nil
            shownID = n
            Task { try? await Task.sleep(for: .milliseconds(400)); if model.player.documentID == n { model.player.play() } }
        }
        .task(id: documentID) {
            await model.open(documentID)
            content = await model.store.content(for: documentID)
            following = true
            scrollRequest = player.cursor
            if let r = model.revealRequest, r.doc == documentID {
                model.revealRequest = nil
                try? await Task.sleep(for: .milliseconds(250))
                show(r.offset)
            }
        }
    }

    private var classic: some View {
        VStack(spacing: 0) {
            if bike {
                VStack(spacing: 4) {
                    BikeTopBar(title: doc?.title ?? "", theme: theme, onBack: { dismiss() }, onContents: { bikeContents = true },
                               onDetails: { withAnimation(.smooth(duration: 0.35)) { moveDetails.toggle() } })
                    MoveDetails(shown: $moveDetails, ink: Color(uiColor: theme.text), dim: Color(uiColor: theme.text).opacity(0.55),
                                background: Color(uiColor: theme.chrome))
                }
            } else if !chromeHidden {
                TopBar(title: doc?.title ?? "", theme: theme, popover: $popover, onBack: { dismiss() }, onSibling: go,
                       hasPrevious: model.neighbor(of: documentID, forward: false) != nil,
                       hasNext: model.neighbor(of: documentID, forward: true) != nil,
                       options: { options })
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            page
            if bike {
                BikeBar(theme: theme)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if !chromeHidden {
                PlayerBar(theme: theme, onJump: jump, onShow: show, onSearch: { searching = true })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    /// The page, with the "go to speech cursor" pill and, when the bars are hidden, the small play button.
    private var page: some View {
        ZStack(alignment: .bottom) {
            if let content, let doc {
                ReaderTextView(
                    documentID: documentID, text: content.text, style: style, highlights: doc.highlights,
                    notes: model.currentNotes.map { NoteMark(id: $0.id, range: $0.range, voice: $0.hasVoice) }, player: player,
                    following: $following, scrollRequest: scrollRequest,
                    onTap: { _ in if !bike { withAnimation(.smooth(duration: 0.32)) { chromeHidden.toggle() } } },
                    onDoubleTap: { i in tapped(i) },
                    onHighlight: { r, c, t in model.addHighlight(r, color: c, text: t) },
                    onRemoveHighlight: { id in model.removeHighlight(id) },
                    onNote: { r, t in
                        if !(doc.highlights.contains { NSIntersectionRange($0.range, r).length > 0 }) { model.addHighlight(r, color: .yellow, text: t) }
                        noteSheet = .new(range: r, quote: t)
                    },
                    onVoiceNote: { r in model.startVoiceNote(anchor: r) },
                    onOpenNote: { id in noteSheet = .existing(id) },
                    onBookmark: { i in model.addBookmark(at: i) },
                    onPlayFrom: { i in player.moveCursor(to: i, play: true); following = true },
                    onVisibleOffset: { visibleOffset = $0 },
                    onScrolling: scrolling)
            } else {
                ProgressView().tint(Color(uiColor: style.foreground)).frame(maxHeight: .infinity)
            }
            VStack(spacing: 10) {
                NoteToastView(onOpen: { noteSheet = .existing($0) })
                if !bike {
                    // Nothing sits on the text while you read: the way back to the voice (and, with the bars hidden,
                    // the microphone and play) shows only while the page moves and fades a moment after it stops.
                    let recording = model.recorder.isRecording
                    ZStack {
                        HStack {
                            if !chromeHidden || moving || recording {
                                MicButton(size: chromeHidden ? 50 : 58).padding(.leading, 18)
                                    .transition(.opacity)
                            }
                            Spacer()
                            if chromeHidden && moving {
                                MiniPlayButton().padding(.trailing, 18)
                                    .transition(.opacity)
                            }
                        }
                        if !following && moving {
                            // the arrow points to where the voice is
                            Button(action: goToCursor) {
                                Label("Konuşma imlecine git", systemImage: player.cursor < visibleOffset ? "arrow.up.to.line" : "arrow.down.to.line")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16).padding(.vertical, 11)
                                    .background(accent.ink.opacity(0.62), in: Capsule())
                                    .contentShape(Capsule().inset(by: -10))
                            }
                            .buttonStyle(.plain)
                            .sensoryFeedback(.impact(weight: .light), trigger: scrollRequest)
                            .transition(.opacity)
                            .accessibilityLabel("Konuşma imlecine git")
                        }
                    }
                }
            }
            .padding(.bottom, 10)
            .animation(.smooth(duration: 0.25), value: following)
            .animation(.easeInOut(duration: 0.35), value: moving)
        }
        .overlay(alignment: .top) { RecordingStrip().padding(.top, 8) }
    }

    private var style: ReaderStyle {
        let s = model.settings
        let t = theme
        let line: UIColor? = !s.showSpokenLine ? nil
            : s.lineColor == .paper ? t.band
            : s.lineColor.uiColor.withAlphaComponent(t.isDark ? 0.34 : 0.26)
        return ReaderStyle(
            font: s.font, size: bike ? s.fontSize * 1.35 : s.fontSize, lineSpacing: s.lineSpacing, kern: s.characterSpacing,
            background: t.background, foreground: t.text,
            wordColor: s.showSpokenWord ? s.wordColor.uiColor : nil, lineColor: line,
            focus: s.focusMode, cursorFraction: s.cursorPosition.fraction, bookLayout: s.bookLayout)
    }

    /// The boxed button's menu: what is not a setting but an action on this document.
    @ViewBuilder private var options: some View {
        Menu {
            Button("Kapalı") { player.setSleepTimer(.off) }
            ForEach([5, 10, 15, 30, 45, 60, 90], id: \.self) { m in Button("\(m) dakika") { player.setSleepTimer(.minutes(m)) } }
            Button("Bölümün sonunda") { player.setSleepTimer(.endOfChapter) }
        } label: { Label("Uyku zamanlayıcısı", systemImage: player.sleepTimer == .off ? "moon.zzz" : "moon.zzz.fill") }
        Section {
            if let c = content, !c.pages.isEmpty {
                Button { goToText = ""; goTo = .page } label: { Label("Sayfaya git…", systemImage: "doc") }
            }
            Button { goToText = ""; goTo = .percent } label: { Label("Yüzdeye git…", systemImage: "percent") }
            Button { rewindAsked = true } label: { Label("Başa sar", systemImage: "backward.end") }
        }
        if let d = doc, !d.highlights.isEmpty {
            ShareLink(item: model.highlightsExport(d)) { Label("İşaretleri dışa aktar", systemImage: "square.and.arrow.up") }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var switchTo: UUID?

    /// Previous/next document in the same folder, keeping the reader open.
    private func go(forward: Bool) {
        guard let next = model.neighbor(of: documentID, forward: forward)?.id else { return }
        let wasPlaying = player.isPlaying
        Task {
            await model.open(next)
            if wasPlaying { player.play() }
            switchTo = next
        }
    }

    /// Double tap: the reading position moves to this word and reading starts from it.
    private func tapped(_ i: Int) {
        guard player.documentID == documentID else { return }
        player.moveCursor(to: player.wordRange(around: i).location, play: true)
        following = true
    }

    /// Music mode over the page keeps the screen on too: it pauses reading, and that pause used to let the screen
    /// sleep under it (2026-10-28).
    private func keepAwake() {
        UIApplication.shared.isIdleTimerDisabled = player.isPlaying || model.recorder.isRecording || model.musicModeShown
    }

    /// The finger moved the page: show the floating buttons; once it rests, let them fade after a moment.
    private func scrolling(_ on: Bool) {
        restTask?.cancel()
        if on { moving = true; return }
        restTask = Task {
            try? await Task.sleep(for: .seconds(1.8))
            if !Task.isCancelled { moving = false }
        }
    }

    /// Contents, search: bring that place on screen and leave the reading position where it is. Reading moves there
    /// only by ▶ in the list or a double tap on the page; "Konuşma imlecine git" comes back.
    private func show(_ offset: Int) {
        browsing = true
        following = false
        visibleOffset = offset                    // the pill's arrow points from here to the voice
        scrolling(true); scrolling(false)         // show the way back for a moment
        scrollRequest = offset == scrollRequest ? offset + 1 : offset
    }

    /// Move to an offset (contents, search, slider); keeps playing if it was playing.
    /// Back to the voice: always scrolls, even when the cursor has not moved since the last request.
    private func goToCursor() {
        following = true
        let c = player.cursor
        scrollRequest = c == scrollRequest ? c + 1 : c
    }

    private func jump(_ offset: Int, play: Bool?) {
        player.moveCursor(to: offset, play: play)
        following = true
        scrollRequest = offset == scrollRequest ? offset + 1 : offset
    }

    private func performGoTo() {
        guard let c = content, let n = Int(goToText.trimmingCharacters(in: .whitespaces)) else { goTo = nil; return }
        if goTo == .page, !c.pages.isEmpty {
            jump(c.pages[min(max(n, 1), c.pages.count) - 1], play: nil)
        } else {
            let len = (c.text as NSString).length
            jump(player.sentenceStart(before: Int(Double(len) * Double(min(max(n, 0), 100)) / 100) + 1), play: nil)
        }
        goTo = nil
    }
}

// MARK: - top bar

private struct TopBar<Options: View>: View {
    @Environment(\.accent) private var accent
    let title: String
    let theme: ReaderTheme
    @Binding var popover: ReaderScreen.Popover?
    var onBack: () -> Void
    var onSibling: (Bool) -> Void
    var hasPrevious: Bool
    var hasNext: Bool
    @ViewBuilder var options: () -> Options
    @Environment(AppModel.self) private var model

    private func shown(_ p: ReaderScreen.Popover) -> Binding<Bool> {
        Binding(get: { popover == p }, set: { if !$0 && popover == p { popover = nil } })
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                icon("books.vertical.fill", "Kütüphane", action: onBack)
                Menu { options() } label: { glyph("switch.2") }
                    .accessibilityLabel("Okuma seçenekleri")
                Spacer(minLength: 0)
                icon("speaker.wave.2.fill", "Ses ayarları: \(model.currentVoiceName)") { popover = .audio }
                    .popover(isPresented: shown(.audio), attachmentAnchor: .point(.bottom), arrowEdge: .top) {
                        AudioSettingsView().frame(minWidth: 340, idealWidth: 360, minHeight: 440, idealHeight: 560)
                            .presentationCompactAdaptation(.popover)
                    }
                Button { popover = .visual } label: {
                    Text("Aa").font(.system(size: 25, weight: .semibold, design: .rounded)).foregroundStyle(accent.ink)
                        .frame(width: 48, height: 40)
                }
                .accessibilityLabel("Görsel ayarlar")
                .popover(isPresented: shown(.visual), attachmentAnchor: .point(.bottom), arrowEdge: .top) {
                    VisualSettingsView().frame(minWidth: 340, idealWidth: 360, minHeight: 440, idealHeight: 560)
                        .presentationCompactAdaptation(.popover)
                }
                Menu {
                    Button { model.startMove(.bike) } label: { Label("Bisiklet modu", systemImage: "bicycle") }
                    Button { model.startMove(.walk) } label: { Label("Yürüyüş modu", systemImage: "figure.walk") }
                    Button { model.musicModeShown = true } label: { Label("Müzik modu", systemImage: "music.note") }
                } label: { glyph(model.settings.moveKind.symbol) }
                .accessibilityLabel("Bisiklet, yürüyüş ya da müzik modu")
                icon("bookmark.fill", "Yer imi ekle") { model.addBookmark() }
                    .sensoryFeedback(.success, trigger: model.currentDocument?.bookmarks.count ?? 0)
            }
            HStack(spacing: 8) {
                Button { onSibling(false) } label: { Image(systemName: "backward.fill").font(.system(size: 21)).frame(width: 40, height: 40) }
                    .disabled(!hasPrevious).opacity(hasPrevious ? 1 : 0.3)
                    .accessibilityLabel("Önceki belge")
                // the book and, under it, the chapter being read (2026-10-28: "hangi bölümde olduğumu tam olarak görmem lazım")
                VStack(spacing: 1) {
                    Text(title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                        .foregroundStyle(Color(uiColor: theme.text))
                    if let ch = model.player.chapterTitle(at: model.player.spokenSentence?.location ?? model.player.cursor) {
                        Text(ch).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            .foregroundStyle(accent.ink)
                            .contentTransition(.opacity)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                Button { onSibling(true) } label: { Image(systemName: "forward.fill").font(.system(size: 21)).frame(width: 40, height: 40) }
                    .disabled(!hasNext).opacity(hasNext ? 1 : 0.3)
                    .accessibilityLabel("Sonraki belge")
            }
            .foregroundStyle(accent.ink)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .padding(.bottom, 4)
        .background(Color(uiColor: theme.chrome).ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) { Rectangle().fill(Color(uiColor: theme.hairline)).frame(height: 0.5) }
    }

    private func glyph(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 22, weight: .semibold)).foregroundStyle(accent.ink).frame(width: 48, height: 40)
    }

    private func icon(_ name: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { glyph(name) }.accessibilityLabel(label)
    }
}

/// Bicycle mode's top: back, the title, and the way out of the mode.
private struct BikeTopBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accent) private var accent
    let title: String
    let theme: ReaderTheme
    var onBack: () -> Void
    var onContents: () -> Void
    var onDetails: () -> Void = {}
    @State private var visual = false

    var body: some View {
        HStack(spacing: 2) {
            Button(action: onBack) {
                Image(systemName: "books.vertical.fill").font(.system(size: 20, weight: .semibold)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Kütüphane")
            // the contents: where you are, and a jump to another chapter
            Button(action: onContents) {
                Image(systemName: "list.bullet").font(.system(size: 21, weight: .semibold)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("İçindekiler")
            VStack(spacing: 1) {
            Button(action: onDetails) {
                RoadStatus(ink: Color(uiColor: theme.text).opacity(0.6), dim: Color(uiColor: theme.text).opacity(0.45))
                    .frame(maxWidth: .infinity).contentShape(Rectangle())
            }
            .accessibilityHint("Dokun: km, süre, kalori")
            Button(action: onContents) {
                VStack(spacing: 1) {
                    Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        .foregroundStyle(Color(uiColor: theme.text))
                    if let ch = model.player.chapterTitle(at: model.player.cursor) {
                        Text(ch).font(.system(size: 12)).lineLimit(1).foregroundStyle(Color(uiColor: theme.text).opacity(0.6))
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("İçindekiler: \(title)")
            }
            SpeedChip(large: true)
            Button { visual = true } label: {
                Text("Aa").font(.system(size: 22, weight: .semibold, design: .rounded)).frame(width: 40, height: 44)
            }
            .accessibilityLabel("Görsel ayarlar")
            .popover(isPresented: $visual, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
                VisualSettingsView().frame(minWidth: 340, idealWidth: 360, minHeight: 440, idealHeight: 560)
                    .presentationCompactAdaptation(.popover)
            }
            Button { model.settings.bikeLook = .focus } label: {
                Image(systemName: "moon.stars.fill").font(.system(size: 20, weight: .semibold)).frame(width: 40, height: 40)
            }
            .accessibilityLabel("Yolda görünümüne geç")
            MoveModeMenu(size: 26, color: accent.ink)
        }
        .foregroundStyle(accent.ink)
        .buttonStyle(.plain)
        .padding(.horizontal, 6).padding(.bottom, 4)
        .background(Color(uiColor: theme.chrome).ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) { Rectangle().fill(Color(uiColor: theme.hairline)).frame(height: 0.5) }
    }
}

// MARK: - bottom bar

struct PlayerBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accent) private var accent
    let theme: ReaderTheme
    var onJump: (Int, Bool?) -> Void
    var onShow: (Int) -> Void
    var onSearch: () -> Void
    @State private var showLocations = false
    @State private var scrubbing: Double?

    private var player: SpeechPlayer { model.player }
    private var unit: NavigationUnit { model.settings.navigationUnit }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                bar("list.bullet", "Konumlar: başlıklar, yer imleri, işaretler") { showLocations = true }
                    .popover(isPresented: $showLocations, attachmentAnchor: .point(.top), arrowEdge: .bottom) {
                        NavigationSheet(onJump: { o, p in onJump(o, p) }, onShow: onShow)
                    }
                skip(forward: false)
                PlayButton().frame(maxWidth: .infinity)
                skip(forward: true)
                bar("magnifyingglass", "Belgede ara", action: onSearch)
            }
            .padding(.top, 6)
            ProgressRow(scrubbing: $scrubbing, onJump: onJump)
            StatusRow()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .foregroundStyle(accent.ink)
        .buttonStyle(.plain)
        .background(Color(uiColor: theme.chrome).ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Color(uiColor: theme.hairline)).frame(height: 0.5) }
    }

    private func bar(_ name: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 21, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 48)
        }
        .accessibilityLabel(label)
    }

    /// ↺ / ↻ with the navigation unit's symbol inside, so you see what a skip moves by.
    private func skip(forward: Bool) -> some View {
        Button { player.skip(forward: forward, unit: unit) } label: {
            SkipGlyph(forward: forward, unit: unit, size: 36).frame(maxWidth: .infinity, minHeight: 56)
        }
        .accessibilityLabel((forward ? "İleri: " : "Geri: ") + unit.name)
    }
}

/// The play / pause button: flat, Voice Dream's orange-red. Only this view reads `isPlaying`.
private struct PlayButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let playing = model.player.isPlaying
        Button { model.player.toggle() } label: {
            ZStack {
                Circle().fill(Palette.play)
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: playing ? 0 : 2)
                    .contentTransition(.symbolEffect(.replace.downUp))
            }
            .frame(width: 52, height: 52)
            .scaleEffect(playing ? 1 : 0.97)
            .animation(.smooth(duration: 0.2), value: playing)
        }
        .contextMenu { ActivePauseMenu() }
        .sensoryFeedback(.impact(weight: .light), trigger: playing)
        .accessibilityLabel(playing ? "Duraklat" : "Oynat")
    }
}

/// Time elapsed · progress bar · time left. Only this row follows the cursor word by word.
private struct ProgressRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accent) private var accent
    @Binding var scrubbing: Double?
    var onJump: (Int, Bool?) -> Void

    var body: some View {
        let player = model.player
        let len = max(1, player.length)
        let value = scrubbing ?? Double(player.cursor) / Double(len)
        let total = player.totalSeconds
        let elapsed = total * value
        HStack(spacing: 10) {
            Text(Format.clock(elapsed)).frame(width: 58, alignment: .leading)
            Scrubber(value: value, fill: accent.fill, knob: accent.ink, onChanging: { scrubbing = $0 }, onEnded: { s in
                onJump(player.sentenceStart(before: Int(Double(len) * s) + 1), nil)
                scrubbing = nil
            })
            Text(Format.clock(max(0, total - elapsed))).frame(width: 58, alignment: .trailing)
        }
        .font(.system(size: 14).monospacedDigit())
        .foregroundStyle(.primary)
    }
}

/// % · chapter · skip unit, one quiet line.
private struct StatusRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accent) private var accent

    var body: some View {
        let player = model.player
        let value = Double(player.cursor) / Double(max(1, player.length))
        let unit = model.settings.navigationUnit
        HStack(spacing: 10) {
            Text("%\(Int(value * 100))").monospacedDigit().frame(width: 58, alignment: .leading)
            Group {
                if player.breakEnds != nil {
                    BreakBadge()
                } else {
                    Text(player.chapterTitle(at: player.cursor) ?? model.currentDocument?.author ?? "").lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            SpeedChip()
            Menu {
                Picker("Gezinme birimi", selection: Binding(get: { model.settings.navigationUnit }, set: { model.settings.navigationUnit = $0 })) {
                    ForEach(NavigationUnit.allCases) { u in Label(u.name, systemImage: u.symbol).tag(u) }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                    Image(systemName: unit.symbol).font(.system(size: 15, weight: .bold))
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                }
                .frame(width: 58, height: 30, alignment: .trailing)
            }
            .accessibilityLabel("Gezinme birimi: \(unit.name)")
        }
        .font(.system(size: 14))
        .foregroundStyle(accent.ink)
        .frame(height: 30)
    }
}

/// Quick speed: each tap moves to the next of four speeds (words a minute). The fine setting stays in Ses Ayarları;
/// this only sets the same value (for the document when it has its own speed).
struct SpeedChip: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accent) private var accent
    var large = false
    static let choices = [260, 330, 380, 430]

    var body: some View {
        let now = SpeechPlayer.wpm(model.player.speed)
        Button {
            let next = Self.choices.first { $0 > now + 2 } ?? Self.choices[0]
            model.setSpeed(Double(next) / SpeechPlayer.wordsAtOneX, documentOnly: model.speedIsDocumentSpecific)
        } label: {
            Text("\(now)")
                .font(.system(size: large ? 17 : 14, weight: .bold).monospacedDigit())
                .contentTransition(.numericText(value: Double(now)))
                .foregroundStyle(accent.ink)
                .padding(.horizontal, large ? 12 : 9).padding(.vertical, large ? 7 : 4)
                .background(Color.primary.opacity(0.10), in: Capsule())
                .animation(.smooth(duration: 0.2), value: now)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: now)
        .accessibilityLabel("Hız: dakikada \(now) kelime. Dokun: sonraki hız")
    }
}

enum Format {
    static func clock(_ t: TimeInterval) -> String {
        let s = Int(max(0, t).rounded())
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    static func duration(_ t: TimeInterval) -> String {
        let m = Int((t / 60).rounded())
        if m < 1 { return "1 dk'dan az" }
        if m < 60 { return "\(m) dk" }
        return m % 60 == 0 ? "\(m / 60) sa" : "\(m / 60) sa \(m % 60) dk"
    }
}

/// With the bars hidden: one small glass button that plays / pauses, with the progress as a ring.
struct MiniPlayButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let p = model.player
        let progress = Double(p.cursor) / Double(max(1, p.length))
        Button { p.toggle() } label: {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.15), lineWidth: 3)
                Circle().trim(from: 0, to: progress).stroke(Palette.play, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: p.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .offset(x: p.isPlaying ? 0 : 1.5)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 50, height: 50)
            .padding(6)
            .modifier(GlassPanel(cornerRadius: 31))
        }
        .contextMenu { ActivePauseMenu() }
        .buttonStyle(.plain)
        .accessibilityLabel(p.isPlaying ? "Duraklat" : "Oynat")
    }
}

/// The skip arrow: SF's closed ring (goforward / gobackward), drawn for a label in its middle. 15 and 30 seconds use
/// the numbered symbols; the other units sit their own small symbol in the ring's centre.
struct SkipGlyph: View {
    let forward: Bool
    let unit: NavigationUnit
    var size: CGFloat

    var body: some View {
        switch unit {
        case .seconds15, .seconds30:
            Image(systemName: (forward ? "goforward." : "gobackward.") + (unit == .seconds15 ? "15" : "30"))
                .font(.system(size: size, weight: .regular))
        default:
            Image(systemName: forward ? "goforward" : "gobackward")
                .font(.system(size: size, weight: .regular))
                .overlay {
                    Image(systemName: unit.symbol)
                        .font(.system(size: size * 0.32, weight: .semibold))
                        .offset(y: size * 0.04)
                }
        }
    }
}

/// Tam metin while the moving mode goes on: a slim pill over the page saying the way is being recorded, and the way
/// back to the road screen. The GPS record does not stop here; only "modundan çık" in the mode's menu stops it.
private struct RoadPill: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(spacing: 10) {
            MoveModeMenu(size: 20, color: accent.ink)
            Text(model.settings.moveKind.name + " sürüyor").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button { withAnimation(.smooth(duration: 0.35)) { model.settings.bikeLook = .focus } } label: {
                Label("Yolda", systemImage: "moon.stars.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12).frame(height: 34)
                    .background(accent.ink.opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(accent.ink)
            .accessibilityLabel("Yolda ekranına dön")
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .padding(.horizontal, 12)
    }
}
