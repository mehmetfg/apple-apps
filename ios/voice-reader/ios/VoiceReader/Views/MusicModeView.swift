// Müzik modu's screen. Three contents (2026-10-28): Cümleler (no voice, the book's sentences with the music), Yalnız
// ritim (no text at all, only the backdrop moving with the beat: time to think) and Dinle (the book read aloud, the
// heard words set as kinetic type). An active wait or a music break opens it on Yalnız ritim and closes it when
// reading goes on. In Cümleler, no voice, only text with the music. Each beat brings the next words of a sentence in (they
// grow out of a blur), the finished sentence stays a few beats, then the next one comes. The background breathes with
// the beat. A tap stops it and shows the sentence calmly with why it matters, its chapter and the book's main idea;
// a sideways swipe goes to the next or the previous sentence.
import SwiftUI

struct MusicModeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var beat = BeatTracker()
    @State private var lines: [MusicLine] = []
    @State private var insight: TeoriaInsight?
    @State private var title = ""
    @State private var loaded = false
    @State private var index = 0
    @State private var shown = 0                 // words of the line on screen
    @State private var hold = 0                  // beats the finished line has stayed
    @State private var paused = false
    @State private var bump = false
    @State private var lastBeat = Date.distantPast
    @State private var phraseIndex = 0           // Kinetik: the phrase on screen
    @State private var phraseShown = 0           // Kinetik: its words landed (one more, its symbol)
    @State private var flash = false             // Kinetik: the key word landed
    @State private var wasReading = false        // reading was paused on opening: it goes on (music behind) on closing

    /// Gündüz: the page turns to warm paper, the text to ink, the amber to a burnt orange (the road screen's day colours).
    private var day: Bool { backdropKind == .day }
    private var amber: Color { day ? Color(red: 0.78, green: 0.36, blue: 0.03) : Color(red: 0.98, green: 0.72, blue: 0.30) }
    private var paper: Color { day ? Color(red: 0.125, green: 0.105, blue: 0.085) : Color(red: 0.97, green: 0.95, blue: 0.90) }
    private var page: Color { day ? Color(red: 0.965, green: 0.945, blue: 0.905) : .black }
    private var chip: Color { day ? Color.black.opacity(0.06) : Color.white.opacity(0.08) }

    private var line: MusicLine? { lines.isEmpty ? nil : lines[index % lines.count] }
    private var words: [String] { line.map { $0.text.split(separator: " ").map(String.init) } ?? [] }
    private var kinetic: Bool { model.settings.musicKinetic }
    /// What is on screen: during a break always the rhythm alone.
    private var content: MusicContent {
        model.musicFromBreak ? .rhythm : MusicContent(rawValue: model.settings.musicContent) ?? .lines
    }
    private var phrases: [KineticPhrase] { line.map { KineticPhrase.phrases($0.text, seed: index) } ?? [] }
    private var phrase: KineticPhrase? { phrases.indices.contains(phraseIndex) ? phrases[phraseIndex] : nil }

    var body: some View {
        GeometryReader { g in
            ZStack {
                backdrop(g.size)
                if content == .listen {
                    KineticListening(size: CGSize(width: g.size.width - 52, height: g.size.height * 0.6), accent: amber, paper: paper, glow: !day, mask: model.settings.kineticMask, page: page)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(model.player.isPlaying ? 1 : 0.45)
                }
                if content == .rhythm, model.musicFromBreak, let ends = model.player.breakEnds, ends < .distantFuture {
                    breakClock(ends)
                }
                if content == .lines, loaded, line == nil { empty }
                if content == .lines, let line {
                    VStack(spacing: 18) {
                        Text(line.label.uppercased())
                            .font(.system(size: 11, weight: .bold, design: .rounded)).tracking(2.4)
                            .foregroundStyle(line.kind == .mark ? amber : paper.opacity(0.55))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().strokeBorder((line.kind == .mark ? amber : paper).opacity(0.35), lineWidth: 1))
                        if kinetic, let p = phrase {
                            KineticPhraseView(phrase: p, shown: phraseShown,
                                              size: CGSize(width: g.size.width - 52, height: g.size.height * 0.6),
                                              accent: amber, paper: paper, glow: !day, mask: model.settings.kineticMask, page: page)
                                .id("\(line.id)-\(p.id)")
                                .transition(.asymmetric(insertion: .opacity,
                                                        removal: model.settings.kineticMask && !reduceMotion ? Rise.leave
                                                            : .modifier(active: FlyPast(t: 1), identity: FlyPast(t: 0))))
                        } else if !kinetic {
                        CenterFlow(spacing: size(for: line) * 0.28, lineSpacing: size(for: line) * 0.18) {
                            ForEach(Array(words.prefix(shown).enumerated()), id: \.offset) { i, w in
                                Text(w)
                                    .font(.system(size: size(for: line), weight: .semibold, design: .serif))
                                    .foregroundStyle(i >= shown - chunk && !paused ? amber : paper)
                                    .shadow(color: amber.opacity(i >= shown - chunk && !day ? 0.55 : 0), radius: 14)
                                    .transition(reduceMotion ? .opacity : .modifier(active: WordIn(t: 0), identity: WordIn(t: 1)))
                            }
                        }
                        .id(line.id)
                        .transition(.opacity.combined(with: .offset(y: -30)))
                        .padding(.horizontal, 26)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(paused ? 0 : 1)
                }
                amber.opacity(flash ? (day ? 0.07 : 0.16) : 0).ignoresSafeArea().allowsHitTesting(false)
                if paused, content == .lines, let line { card(line).transition(.opacity.combined(with: .scale(scale: 0.96))) }
                chrome
            }
            .frame(width: g.size.width, height: g.size.height)
            .contentShape(Rectangle())
            .onTapGesture {
                switch content {
                case .lines: withAnimation(.smooth(duration: 0.35)) { paused.toggle(); beat.paused = paused }
                case .listen: model.player.toggle()
                case .rhythm: break
                }
            }
            .gesture(DragGesture(minimumDistance: 30).onEnded { v in
                guard content == .lines, abs(v.translation.width) > abs(v.translation.height) else { return }
                step(v.translation.width < 0 ? 1 : -1)
            })
        }
        .background(page.ignoresSafeArea())
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task { await load() }
        .onAppear {
            // the music comes to the front: reading pauses (not in a break, which goes on by itself, and not when
            // listening) and the session is let go. The music mode means music is playing, so mixing is turned on
            // (with it off, reading again would stop the music instead of putting it behind the voice).
            if model.settings.musicMix == .off { model.settings.musicMix = .mix; model.applyAudioSettings() }
            if content != .listen, !model.musicFromBreak, model.player.isPlaying { wasReading = true; model.player.pause() }
            if content != .listen { model.player.releaseToMusic() }
            UIApplication.shared.isIdleTimerDisabled = true
            beat.start(microphone: model.settings.musicMic)
        }
        // kept on as long as the screen is up (a pause of reading under it must not let it sleep)
        .task {
            while !Task.isCancelled {
                UIApplication.shared.isIdleTimerDisabled = true
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .onDisappear {
            beat.stop()
            UIApplication.shared.isIdleTimerDisabled = model.player.isPlaying
            model.musicFromBreak = false
            // closing: reading goes on where it stopped and the music goes behind the voice (ducked or mixed, as set)
            if wasReading, !model.player.isPlaying { model.player.resume() }
        }
        .onChange(of: beat.beat) { _, _ in onBeat() }
    }

    // MARK: the beat

    /// Words a beat: short sentences one, long ones up to three, so a line takes about eight to fourteen beats.
    private var chunk: Int { max(1, min(3, words.count / 10)) }

    private func onBeat() {
        guard !paused else { return }
        lastBeat = .now
        if !reduceMotion {
            withAnimation(.easeOut(duration: 0.08)) { bump = true }
            withAnimation(.easeIn(duration: 0.3).delay(0.08)) { bump = false }
        }
        guard content == .lines, line != nil else { return }
        if kinetic { kineticBeat(); return }
        if shown < words.count {
            withAnimation(.spring(duration: 0.38, bounce: 0.3)) { shown = min(words.count, shown + chunk) }
        } else {
            hold += 1
            if hold >= 5 { step(1) }
        }
    }

    /// Kinetik: one word lands on each beat (then the phrase's symbol); a finished phrase stays a beat and flies past;
    /// the last one stays three beats before the next sentence.
    private func kineticBeat() {
        guard let p = phrase else { step(1); return }
        let total = p.beats
        if phraseShown < total {
            withAnimation(.spring(duration: 0.34, bounce: 0.38)) { phraseShown += 1 }
            if phraseShown - 1 == p.key, !reduceMotion {
                withAnimation(.easeOut(duration: 0.06)) { flash = true }
                withAnimation(.easeIn(duration: 0.45).delay(0.06)) { flash = false }
            }
            return
        }
        hold += 1
        let last = phraseIndex >= phrases.count - 1
        if hold >= (last ? 3 : 1) {
            if last { step(1) } else {
                withAnimation(.smooth(duration: 0.35)) { phraseIndex += 1; phraseShown = 0; hold = 0 }
            }
        }
    }

    private func step(_ by: Int) {
        guard !lines.isEmpty else { return }
        withAnimation(.smooth(duration: 0.5)) {
            index = (index + by + lines.count) % lines.count
            shown = 0
            hold = 0
            phraseIndex = 0
            phraseShown = 0
            paused = false
            beat.paused = false
        }
    }

    // MARK: loading

    private func load() async {
        guard let id = model.player.documentID ?? model.openDocumentID, let doc = model.store.document(id),
              let content = await model.store.content(for: id) else { loaded = true; return }
        title = doc.title
        let data = await VaultMirror.shared.teoriaInsight(title: doc.title)
        insight = data.flatMap { try? JSONDecoder().decode(TeoriaInsight.self, from: $0) }
        let chapters = content.chapters
        lines = MusicPool.build(doc: doc, text: content.text, insight: insight) { at in chapters.last { $0.offset <= at }?.title }
        loaded = true
    }

    private func size(for line: MusicLine) -> CGFloat {
        let n = line.text.count
        return n < 70 ? 38 : n < 140 ? 31 : n < 240 ? 26 : 22
    }

    // MARK: layers

    private var beatInput: BeatInput {
        BeatInput(lastBeat: lastBeat, bpm: beat.bpm, level: beat.level, beat: beat.beat, paused: paused || reduceMotion)
    }

    private var backdropKind: MusicBackdrop { MusicBackdrop(rawValue: model.settings.musicBackdrop) ?? .circle }

    @ViewBuilder private func backdrop(_ s: CGSize) -> some View {
        Group {
            switch backdropKind {
            case .glow: glow(s)
            case .black:
                RhythmBars(lastBeat: lastBeat, bpm: beat.bpm, level: beat.level, seed: beat.beat, paused: paused || reduceMotion)
                    .frame(width: s.width, height: s.height * 0.12)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 44)
                    .opacity(paused ? 0.1 : 0.45)
            case .circle:
                RadialBars(lastBeat: lastBeat, bpm: beat.bpm, level: beat.level, seed: beat.beat, paused: paused || reduceMotion)
                    .frame(width: s.width, height: s.width)
                    .opacity(paused ? 0.12 : 0.85)
            case .dusk: dusk(s)
            case .day:
                RadialBars(lastBeat: lastBeat, bpm: beat.bpm, level: beat.level, seed: beat.beat, paused: paused || reduceMotion, day: true)
                    .frame(width: s.width, height: s.width)
                    .opacity(paused ? 0.15 : 0.9)
            case .aurora: AuroraVisual(input: beatInput)
            case .drop: DropVisual(input: beatInput)
            case .pulse: PulseVisual(input: beatInput)
            case .lissajous: LissajousVisual(input: beatInput)
            case .tunnel: TunnelVisual(input: beatInput)
            case .breath: BreathVisual(input: beatInput)
            }
        }
        .frame(width: s.width, height: s.height)
        .clipped()
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// Two slow, warm light pools whose colour drifts with each sentence; they swell on the beat; rhythm bars jump
    /// behind the text.
    private func glow(_ s: CGSize) -> some View {
        let hue = Double((index * 47) % 360) / 360
        return TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color(hue: hue, saturation: 0.75, brightness: 0.55).opacity(0.55), .clear],
                                         center: .center, startRadius: 0, endRadius: s.width * 0.6))
                    .frame(width: s.width * 1.2, height: s.width * 1.2)
                    .offset(x: cos(t / 7) * s.width * 0.18, y: sin(t / 9) * s.height * 0.12 - s.height * 0.12)
                Circle()
                    .fill(RadialGradient(colors: [Color(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.45).opacity(0.5), .clear],
                                         center: .center, startRadius: 0, endRadius: s.width * 0.55))
                    .frame(width: s.width * 1.1, height: s.width * 1.1)
                    .offset(x: sin(t / 8) * s.width * 0.2, y: cos(t / 6) * s.height * 0.1 + s.height * 0.18)
            }
            .scaleEffect(bump ? 1.06 : 1)
            .blur(radius: 30)
            .frame(width: s.width, height: s.height)
        }
        .overlay {
            RhythmBars(lastBeat: lastBeat, bpm: beat.bpm, level: beat.level, seed: beat.beat, paused: paused || reduceMotion)
                .frame(width: s.width, height: s.height * 0.5)
                .opacity(paused ? 0.1 : 0.28)
        }
        .animation(.smooth(duration: 1.6), value: index)
    }

    /// A deep violet-to-ember sky that brightens on the beat.
    private func dusk(_ s: CGSize) -> some View {
        let hue = Double((index * 23) % 60) / 360
        return LinearGradient(colors: [Color(red: 0.07, green: 0.02, blue: 0.14), Color(hue: 0.78 + hue, saturation: 0.6, brightness: 0.28),
                                       Color(hue: 0.04 + hue, saturation: 0.8, brightness: bump ? 0.62 : 0.48)],
                              startPoint: .top, endPoint: .bottom)
            .frame(width: s.width, height: s.height + 120)
            .overlay(alignment: .bottom) {
                RhythmBars(lastBeat: lastBeat, bpm: beat.bpm, level: beat.level, seed: beat.beat, paused: paused || reduceMotion)
                    .frame(width: s.width, height: s.height * 0.16)
                    .padding(.bottom, 40)
                    .opacity(0.35)
            }
            .animation(.easeOut(duration: 0.25), value: bump)
            .animation(.smooth(duration: 1.6), value: index)
    }

    private var chrome: some View {
        VStack {
            // the quiet top, as on the road screen: clock · battery, the mode and the speed, the book
            HStack(alignment: .top, spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(paper.opacity(0.8))
                        .frame(width: 40, height: 40).background(chip, in: Circle())
                }
                .accessibilityLabel("Müzik modundan çık")
                Spacer(minLength: 0)
                RoadStatus(label: model.musicFromBreak ? "Ara · müzik" : "Müzik modu", book: title,
                           ink: paper.opacity(0.6), dim: paper.opacity(0.4))
                    .frame(maxWidth: 230)
                Spacer(minLength: 0)
                tempo.fixedSize()
            }
            .padding(.horizontal, 16).padding(.top, 8)
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button {
                    let all = MusicBackdrop.allCases
                    let next = all[((all.firstIndex(of: backdropKind) ?? 0) + 1) % all.count]
                    withAnimation(.smooth(duration: 0.5)) { model.settings.musicBackdrop = next.rawValue }
                } label: {
                    Image(systemName: backdropKind.symbol).font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(paper.opacity(0.85))
                        .frame(width: 36, height: 36)
                        .background(chip, in: Circle())
                }
                .accessibilityLabel("Arka plan: \(backdropKind.name). Dokun: sonraki")
                if !model.musicFromBreak { contentMenu }
                if content == .lines || content == .listen {
                    // Akış → Kinetik → Perde (Dinle has no Akış: Kinetik ↔ Perde)
                    let name = content == .lines && !kinetic ? "Akış" : (model.settings.kineticMask ? "Perde" : "Kinetik")
                    Button {
                        withAnimation(.smooth) {
                            let st = model.settings
                            if content == .listen { st.kineticMask.toggle() }
                            else if !st.musicKinetic { st.musicKinetic = true; st.kineticMask = false }
                            else if !st.kineticMask { st.kineticMask = true }
                            else { st.musicKinetic = false; st.kineticMask = false }
                            phraseIndex = 0; phraseShown = 0; shown = 0; hold = 0
                        }
                    } label: {
                        Text(name).font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(paper.opacity(0.85))
                            .padding(.horizontal, 12).frame(height: 36)
                            .background(chip, in: Capsule())
                            .fixedSize()
                    }
                    .accessibilityLabel("Yazı biçimi: \(name). Dokun: değiştir")
                }
            }
            .padding(.horizontal, 16)
            .opacity(0.8)
            Spacer()
            HStack {
                switch content {
                case .lines:
                    Text(paused ? "dokun: sürdür" : "dokun: dur · kaydır: sonraki")
                    Spacer()
                    if !lines.isEmpty { Text("\(index % lines.count + 1)/\(lines.count)").monospacedDigit() }
                case .rhythm:
                    Text(model.musicFromBreak ? "ara bitince okuma kendiliğinden sürer" : "yazı yok · yalnız ritim")
                    Spacer()
                case .listen:
                    Text(model.player.isPlaying ? "dokun: duraklat" : "dokun: oku")
                    Spacer()
                    if let ch = model.player.chapterTitle(at: model.player.shownCursor) { Text(ch).lineLimit(1) }
                }
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(paper.opacity(0.35))
            .padding(.horizontal, 20).padding(.bottom, 10)
        }
    }

    /// Cümleler · Yalnız ritim · Dinle. Going to Dinle starts the voice; leaving it stops the voice.
    private var contentMenu: some View {
        Menu {
            ForEach(MusicContent.allCases) { c in
                Button {
                    withAnimation(.smooth(duration: 0.4)) { model.settings.musicContent = c.rawValue; paused = false; beat.paused = false }
                    if c == .listen { if !model.player.isPlaying { model.player.play() } }
                    else if model.player.isPlaying { model.player.pause() }
                } label: { Label(c.name, systemImage: content == c ? "checkmark" : c.symbol) }
            }
        } label: {
            Image(systemName: content.symbol).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(paper.opacity(0.85))
                .frame(width: 36, height: 36)
                .background(chip, in: Circle())
        }
        .accessibilityLabel("İçerik: \(content.name)")
    }

    /// The break's time left, small and quiet under the rhythm.
    private func breakClock(_ ends: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let left = max(0, Int(ends.timeIntervalSince(ctx.date).rounded()))
            Text("\(left / 60):\(String(format: "%02d", left % 60))")
                .font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(paper.opacity(0.45))
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 60)
        .allowsHitTesting(false)
    }

    /// Tap in time to give the tempo; hold for the microphone. The dot blinks on every beat.
    private var tempo: some View {
        Button { beat.tap() } label: {
            HStack(spacing: 6) {
                Circle().fill(amber).frame(width: 7, height: 7).opacity(bump ? 1 : 0.25)
                Image(systemName: beat.source == .microphone ? "mic.fill" : "metronome.fill").font(.system(size: 12, weight: .semibold))
                Text("\(Int(beat.bpm))").font(.system(size: 14, weight: .bold, design: .rounded)).monospacedDigit()
            }
            .foregroundStyle(paper.opacity(0.85))
            .padding(.horizontal, 12).frame(height: 36)
            .background(chip, in: Capsule())
        }
        .contextMenu {
            Toggle(isOn: Binding(get: { model.settings.musicMic }, set: { on in
                model.settings.musicMic = on
                beat.stop(); beat.start(microphone: on)
            })) { Label("Ritmi mikrofondan dinle", systemImage: "mic") }
            Text("Müzik kulaklıktaysa mikrofon duymaz: düğmeye ritimle 4 kez dokun.")
        }
        .accessibilityLabel("Ritim \(Int(beat.bpm)). Ritimle dokun: tempoyu ver")
    }

    /// Stopped: the sentence whole and quiet, why it matters, its chapter, and the book's main idea.
    private func card(_ line: MusicLine) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Text(line.label.uppercased()).font(.system(size: 11, weight: .bold, design: .rounded)).tracking(2)
                        .foregroundStyle(amber)
                    if let ch = line.chapter { Text("· \(ch)").font(.system(size: 12)).foregroundStyle(paper.opacity(0.5)).lineLimit(1) }
                }
                Text(line.text).font(.system(size: 24, weight: .medium, design: .serif)).foregroundStyle(paper)
                    .lineSpacing(5)
                if let why = line.why {
                    Label { Text(why) } icon: { Image(systemName: "lightbulb") }
                        .font(.system(size: 15)).foregroundStyle(paper.opacity(0.75))
                }
                if let core = insight?.core, core.theme != nil || core.claim != nil {
                    Divider().overlay(paper.opacity(0.15))
                    Text("KİTABIN ANA FİKRİ").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(2)
                        .foregroundStyle(paper.opacity(0.45))
                    if let t = core.theme { Text(t).font(.system(size: 17, weight: .semibold, design: .serif)).foregroundStyle(paper.opacity(0.9)) }
                    if let c = core.claim { Text(c).font(.system(size: 15)).foregroundStyle(paper.opacity(0.7)).lineSpacing(3) }
                }
            }
            .padding(22)
            .background(.ultraThinMaterial.opacity(0.6), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, 18)
            .padding(.vertical, 90)
        }
        .scrollIndicators(.hidden)
        .environment(\.colorScheme, day ? .light : .dark)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note.list").font(.system(size: 34)).foregroundStyle(amber)
            Text("Bu kitapta gösterilecek cümle yok").font(.headline).foregroundStyle(paper)
            Text("Okurken işaretlediğin cümleler burada müzikle akar. Kitap Teoria'da özetlendiyse can alıcı cümleleri ve ana fikri de gelir (vault klasörü seçili olmalı).")
                .font(.subheadline).foregroundStyle(paper.opacity(0.6)).multilineTextAlignment(.center)
        }
        .padding(30)
    }
}

enum MusicContent: String, CaseIterable, Identifiable {
    case lines, rhythm, listen
    var id: String { rawValue }
    var name: String {
        switch self {
        case .lines: "Cümleler"
        case .rhythm: "Yalnız ritim"
        case .listen: "Dinle (kitap okunur)"
        }
    }
    var symbol: String {
        switch self {
        case .lines: "text.quote"
        case .rhythm: "waveform"
        case .listen: "headphones"
        }
    }
}

enum MusicBackdrop: String, CaseIterable {
    case circle, day, breath, aurora, drop, pulse, lissajous, tunnel, black, glow, dusk
    var name: String {
        switch self {
        case .circle: "Daire"
        case .day: "Gündüz"
        case .aurora: "Aurora"
        case .drop: "Damla"
        case .pulse: "Nabız"
        case .lissajous: "Lissajous"
        case .tunnel: "Tünel"
        case .breath: "Nefes"
        case .black: "Siyah"
        case .glow: "Işık"
        case .dusk: "Gün batımı"
        }
    }
    var symbol: String {
        switch self {
        case .circle: "circle.dotted.circle"
        case .day: "sun.max"
        case .aurora: "water.waves"
        case .drop: "drop.circle"
        case .pulse: "waveform.path.ecg"
        case .lissajous: "infinity"
        case .tunnel: "sparkles"
        case .breath: "circle.hexagongrid"
        case .black: "square.fill"
        case .glow: "sun.max.fill"
        case .dusk: "sunset.fill"
        }
    }
}

/// How tall bar `i` of `count` is now: full on the beat, settling before the next, a new shape each beat,
/// a slow idle wave, and the microphone's loudness under it all.
private func barValue(_ i: Int, of count: Int, t: Double, since: Double, bpm: Double, seed: Int, level: Double, hump: Bool) -> Double {
    let decay = exp(-since / (60 / bpm) * 3)
    let x = Double(i) / Double(max(1, count - 1))
    let h = hump ? 0.35 + 0.65 * sin(x * .pi) : 1
    let shape = 0.5 + 0.5 * sin(Double(seed) * 12.9898 + Double(i) * 78.233)
    let idle = 0.5 + 0.5 * sin(t * 2.3 + Double(i) * 0.7)
    return min(1, 0.06 + h * (0.7 * decay * (0.4 + 0.6 * shape) + 0.12 * idle + 0.35 * level))
}

/// Bars standing round a circle, on pure black: the circle breathes with the beat, the bars reach out from it.
private struct RadialBars: View {
    let lastBeat: Date
    let bpm: Double
    let level: Double
    let seed: Int
    let paused: Bool
    var day = false                              // on paper: deeper colours, a dark dot at the bar's end
    private static let count = 64
    private var amber: Color { day ? Color(red: 0.78, green: 0.36, blue: 0.03) : Color(red: 0.98, green: 0.72, blue: 0.30) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: paused)) { ctx in
            Canvas { g, size in draw(&g, size: size, at: ctx.date) }
        }
        .allowsHitTesting(false)
    }

    private func draw(_ g: inout GraphicsContext, size: CGSize, at date: Date) {
        let t = date.timeIntervalSinceReferenceDate
        let since = date.timeIntervalSince(lastBeat)
        let decay: Double = exp(-since / (60 / bpm) * 3)
        let cx = size.width / 2, cy = size.height / 2
        let r0: CGFloat = size.width * CGFloat(0.25 + 0.03 * decay)
        let maxLen: CGFloat = size.width * 0.26
        // the core breathes with the beat: a warm light inside the ring
        let core = Path(ellipseIn: CGRect(x: cx - r0, y: cy - r0, width: r0 * 2, height: r0 * 2))
        g.fill(core, with: .radialGradient(Gradient(colors: [amber.opacity(0.05 + 0.22 * decay), .clear]),
                                           center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r0))
        var halo = g
        halo.addFilter(.blur(radius: 6 + 10 * decay))
        halo.stroke(core, with: .color(amber.opacity(0.3 + 0.5 * decay)), lineWidth: 4)
        g.stroke(core, with: .color(amber.opacity(0.45 + 0.45 * decay)), lineWidth: 1.5)
        let spin = t * 0.05                                         // the crown turns slowly
        let half = Self.count / 2
        // each bar twice: blurred (the glow), then sharp; a short echo of it reaches inwards
        var glow = g
        glow.addFilter(.blur(radius: 5))
        for i in 0..<Self.count {
            // mirrored halves, so the shape is balanced left and right
            let k = i < half ? i : Self.count - 1 - i
            let v = barValue(k, of: half, t: t, since: since, bpm: bpm, seed: seed, level: level, hump: false)
            let a = Double(i) / Double(Self.count) * 2 * .pi - .pi / 2 + spin
            let inner = r0 + 6
            let outer = inner + maxLen * CGFloat(v)
            var path = Path()
            path.move(to: CGPoint(x: cx + CGFloat(cos(a)) * inner, y: cy + CGFloat(sin(a)) * inner))
            path.addLine(to: CGPoint(x: cx + CGFloat(cos(a)) * outer, y: cy + CGFloat(sin(a)) * outer))
            // low bars warm amber, high ones turn to rose and violet
            let color = Color(hue: 0.08 - 0.2 * v + (v > 0.6 ? 1 : 0), saturation: day ? 0.9 : 0.8, brightness: day ? 0.72 : 1).opacity(0.6 + 0.4 * v)
            glow.stroke(path, with: .color(color.opacity(0.7)), style: StrokeStyle(lineWidth: 9, lineCap: .round))
            g.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
            // the tip: a bright dot that flies a little further on the beat
            let tip = outer + 10 * CGFloat(decay)
            let dot = CGPoint(x: cx + CGFloat(cos(a)) * tip, y: cy + CGFloat(sin(a)) * tip)
            g.fill(Path(ellipseIn: CGRect(x: dot.x - 2, y: dot.y - 2, width: 4, height: 4)), with: .color((day ? Color.black : Color.white).opacity(0.35 + 0.6 * v)))
            var echo = Path()
            echo.move(to: CGPoint(x: cx + CGFloat(cos(a)) * (r0 - 6), y: cy + CGFloat(sin(a)) * (r0 - 6)))
            echo.addLine(to: CGPoint(x: cx + CGFloat(cos(a)) * (r0 - 6 - maxLen * 0.3 * CGFloat(v)), y: cy + CGFloat(sin(a)) * (r0 - 6 - maxLen * 0.3 * CGFloat(v))))
            g.stroke(echo, with: .color(color.opacity(0.35)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
    }
}

/// Equalizer bars behind the text, mirrored around the middle: they jump on each beat and settle before the next;
/// the microphone's loudness lifts them all. Each beat draws a new shape, so they never look the same twice.
private struct RhythmBars: View {
    let lastBeat: Date
    let bpm: Double
    let level: Double
    let seed: Int
    let paused: Bool
    private static let count = 30

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: paused)) { ctx in
            Canvas { g, size in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let since = ctx.date.timeIntervalSince(lastBeat)
                let gap: CGFloat = 5
                let bw = (size.width - gap * CGFloat(Self.count + 1)) / CGFloat(Self.count)
                for i in 0..<Self.count {
                    let v = barValue(i, of: Self.count, t: t, since: since, bpm: bpm, seed: seed, level: level, hump: true)
                    let h = CGFloat(v) * size.height
                    let r = CGRect(x: gap + CGFloat(i) * (bw + gap), y: (size.height - h) / 2, width: bw, height: h)
                    g.fill(Path(roundedRect: r, cornerRadius: bw / 2),
                           with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.42, blue: 0.25), Color(red: 0.98, green: 0.72, blue: 0.30),
                                                                   Color(red: 1, green: 0.42, blue: 0.25)]),
                                                 startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY)))
                }
            }
        }
        .blur(radius: 1.5)
        .allowsHitTesting(false)
    }
}

/// A finished phrase leaving: it grows past the viewer, blurring away.
struct FlyPast: ViewModifier {
    var t: Double
    func body(content: Content) -> some View {
        content.scaleEffect(1 + t * 1.6).blur(radius: t * 16).opacity(1 - t)
    }
}

/// A word coming in: from large, blurred and clear to its place.
private struct WordIn: ViewModifier {
    var t: Double
    func body(content: Content) -> some View {
        content
            .scaleEffect(1 + (1 - t) * 0.45)
            .blur(radius: (1 - t) * 10)
            .opacity(t)
            .offset(y: (1 - t) * 10)
    }
}

/// Words in centred lines.
private struct CenterFlow: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let rows = arrange(subviews, width: width)
        return CGSize(width: width, height: rows.reduce(0) { $0 + $1.h } + CGFloat(max(0, rows.count - 1)) * lineSpacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX + (bounds.width - row.w) / 2
            for i in row.items {
                let s = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.h - s.height) / 2), proposal: .unspecified)
                x += s.width + spacing
            }
            y += row.h + lineSpacing
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(items: [Int], w: CGFloat, h: CGFloat)] {
        var rows: [(items: [Int], w: CGFloat, h: CGFloat)] = []
        var cur: [Int] = [], w: CGFloat = 0, h: CGFloat = 0
        for i in subviews.indices {
            let s = subviews[i].sizeThatFits(.unspecified)
            let add = (cur.isEmpty ? 0 : spacing) + s.width
            if !cur.isEmpty, w + add > width { rows.append((cur, w, h)); cur = []; w = 0; h = 0 }
            w += cur.isEmpty ? s.width : add
            cur.append(i); h = max(h, s.height)
        }
        if !cur.isEmpty { rows.append((cur, w, h)) }
        return rows
    }
}
