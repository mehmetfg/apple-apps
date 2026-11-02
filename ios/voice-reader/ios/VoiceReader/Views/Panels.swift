// The reader's panels, all in the Voice Dream manner: contents / bookmarks / highlights (Konumlar), search, and the two
// settings popovers: Ses Ayarları and Görsel Ayarlar. Each setting has exactly one home: speed, language, voice, tuning,
// music and reading behaviour in Ses Ayarları; fonts, colours and the speech cursor in Görsel Ayarlar.
import SwiftUI
import AVFoundation

// MARK: - contents, bookmarks, highlights

/// "Konumlar": headings, bookmarks and highlights in a popover over the contents button. Tapping a row moves there;
/// the play button on the right starts reading from it.
struct NavigationSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent
    var onJump: (Int, Bool?) -> Void
    /// A tap on a row only shows that place; the reading position stays where it is until ▶ is pressed.
    var onShow: (Int) -> Void
    var large = false                       // bicycle mode: bigger rows and a previous/next chapter pair
    @State private var tab = 0

    private var player: SpeechPlayer { model.player }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Konumlar").font(.headline)
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).frame(width: 34, height: 34)
                            .background(Color.primary.opacity(0.10), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Kapat")
                }
            }
            .padding(.horizontal, 14).padding(.top, 14)
            Picker("", selection: $tab) {
                Image(systemName: "list.bullet").tag(0).accessibilityLabel("Başlıklar")
                Image(systemName: "bookmark.fill").tag(1).accessibilityLabel("Yer imleri")
                Image(systemName: "highlighter").tag(2).accessibilityLabel("İşaretler")
                Image(systemName: "waveform").tag(3).accessibilityLabel("Notlar")
            }
            .pickerStyle(.segmented)
            .frame(width: 236)
            .padding(.vertical, 12)
            if large && tab == 0 && !player.chapters.isEmpty { chapterSteps }
            Divider().opacity(0.4)
            list
        }
        .frame(minWidth: 330, idealWidth: 340, minHeight: 420, idealHeight: 470)
        .background(Color(uiColor: .systemBackground))
        .presentationBackground(Color(uiColor: .systemBackground))
        .presentationCompactAdaptation(.popover)
    }

    /// Bicycle: one big press to the chapter before or after the one being read.
    private var chapterSteps: some View {
        HStack(spacing: 10) {
            ForEach([false, true], id: \.self) { fwd in
                Button {
                    let cur = player.chapters.lastIndex { $0.offset <= player.cursor } ?? -1
                    let j = fwd ? cur + 1 : (cur >= 0 && player.cursor - player.chapters[cur].offset > 40 ? cur : cur - 1)
                    guard player.chapters.indices.contains(j) else { return }
                    onJump(player.chapters[j].offset, player.isPlaying ? true : false)
                    dismiss()
                } label: {
                    Label(fwd ? "Sonraki bölüm" : "Önceki bölüm", systemImage: fwd ? "forward.end.fill" : "backward.end.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(accent.wash, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(accent.ink)
            }
        }
        .padding(.horizontal, 14).padding(.bottom, 10)
    }

    private func percent(_ o: Int) -> String {
        let v = Double(o) / Double(max(1, player.length)) * 100
        return "%" + String(format: v < 10 ? "%.1f" : "%.0f", v).replacingOccurrences(of: ".", with: ",")
    }

    private func row<Content: View>(_ offset: Int, current: Bool, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Button { onShow(offset); dismiss() } label: {
                content().frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text(percent(offset)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Button { onJump(offset, true); dismiss() } label: {
                Image(systemName: "play.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Palette.play, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Buradan oku")
        }
        .padding(.horizontal, 16).padding(.vertical, large ? 16 : 12)
        .background(current ? accent.wash : Color.clear)
    }

    /// A note's row: tap opens the note (listen, read, correct); ▶ reads from its place.
    private func noteRow<Content: View>(_ n: ReaderNote, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Button { dismiss(); model.openNoteID = n.id } label: {
                content().frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text(percent(n.location)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Button { onJump(n.location, true); dismiss() } label: {
                Image(systemName: "play.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Palette.play, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Buradan oku")
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    @ViewBuilder private var list: some View {
        let doc = model.currentDocument
        switch tab {
        case 0:
            let chapters = player.chapters
            if chapters.isEmpty {
                ContentUnavailableView("Başlık yok", systemImage: "list.bullet.indent", description: Text("Bu belgede içindekiler bulunamadı."))
            } else {
                let current = chapters.lastIndex { $0.offset <= player.cursor }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(chapters.enumerated()), id: \.offset) { i, c in
                                row(c.offset, current: i == current) {
                                    Text(c.title).font(large ? .body.weight(i == current ? .semibold : .regular) : .subheadline).lineLimit(3)
                                        .padding(.leading, CGFloat(max(0, c.level - 1)) * 18)
                                }
                                .id(i)
                                Divider().opacity(0.25).padding(.leading, 16)
                            }
                        }
                    }
                    .onAppear { if let current { proxy.scrollTo(current, anchor: .center) } }
                }
            }
        case 1:
            if let doc, !doc.bookmarks.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(doc.bookmarks) { b in
                            row(b.offset, current: false) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(b.excerpt).font(.subheadline).lineLimit(2)
                                    Text(b.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .contextMenu { Button(role: .destructive) { model.removeBookmark(b.id) } label: { Label("Sil", systemImage: "trash") }
                            }
                            Divider().opacity(0.25).padding(.leading, 16)
                        }
                    }
                }
            } else {
                ContentUnavailableView("Yer imi yok", systemImage: "bookmark", description: Text("Menüden ya da metni seçerek ekleyebilirsin."))
            }
        case 3:
            let notes = model.currentNotes
            if notes.isEmpty {
                ContentUnavailableView("Not yok", systemImage: "mic", description: Text("Okurken 🎙 düğmesine dokun: not, okunan cümleye bağlanır."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(notes) { n in
                            noteRow(n) {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: n.hasVoice ? "waveform" : "note.text")
                                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(accent.ink).frame(width: 18)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(n.text.isEmpty ? "Sesli not · \(Format.clock(n.seconds ?? 0))" : n.text)
                                            .font(.subheadline).lineLimit(3)
                                        Text(n.quote).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive) { model.notes.delete(n.id) } label: { Label("Sil", systemImage: "trash") }
                            }
                            Divider().opacity(0.25).padding(.leading, 16)
                        }
                    }
                }
            }
        default:
            if let doc, !doc.highlights.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(doc.highlights) { h in
                            row(h.location, current: false) {
                                HStack(alignment: .top, spacing: 8) {
                                    RoundedRectangle(cornerRadius: 2).fill(h.color.color).frame(width: 4)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(h.text).font(.subheadline).lineLimit(3)
                                        if let n = h.note { Text(n).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                                    }
                                }
                            }
                            .contextMenu {
                                ForEach(HighlightColor.allCases.filter { $0 != h.color }, id: \.self) { c in
                                    Button { model.addHighlight(h.range, color: c, text: h.text, note: h.note) } label: { Label(c.name, systemImage: "circle.fill") }
                                }
                                Button(role: .destructive) { model.removeHighlight(h.id) } label: { Label("Sil", systemImage: "trash") } }
                            Divider().opacity(0.25).padding(.leading, 16)
                        }
                    }
                }
            } else {
                ContentUnavailableView("İşaret yok", systemImage: "highlighter", description: Text("Metni seç: parmağını kaldırdığında sarı olur."))
            }
        }
    }
}

// MARK: - search

struct SearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    let text: String
    var onJump: (Int) -> Void
    @State private var query = ""
    @State private var results: [(offset: Int, excerpt: AttributedString)] = []

    var body: some View {
        NavigationStack {
            List(results, id: \.offset) { r in
                Button { onJump(r.offset); dismiss() } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(r.excerpt).lineLimit(3)
                        Text("%\(Int(Double(r.offset) / Double(max(1, (text as NSString).length)) * 100))")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                .tint(.primary)
            }
            .listStyle(.plain)
            .overlay {
                if !query.isEmpty && results.isEmpty { ContentUnavailableView.search(text: query) }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Belgede ara")
            .navigationTitle("Ara")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                let q = query, t = text
                results = await Task.detached { Self.search(q, in: t) }.value
            }
        }
    }

    nonisolated static func search(_ q: String, in text: String) -> [(offset: Int, excerpt: AttributedString)] {
        let q = q.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        let ns = text as NSString
        var out: [(Int, AttributedString)] = []
        var from = 0
        let opts: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let tr = Locale(identifier: "tr")
        while from < ns.length, out.count < 300 {
            let r = ns.range(of: q, options: opts, range: NSRange(location: from, length: ns.length - from), locale: tr)
            guard r.location != NSNotFound else { break }
            let a = max(0, r.location - 50), z = min(ns.length, NSMaxRange(r) + 70)
            let before = ns.substring(with: NSRange(location: a, length: r.location - a)).replacingOccurrences(of: "\n", with: " ")
            let hit = ns.substring(with: r)
            let after = ns.substring(with: NSRange(location: NSMaxRange(r), length: z - NSMaxRange(r))).replacingOccurrences(of: "\n", with: " ")
            var s = AttributedString((a > 0 ? "…" : "") + before)
            var h = AttributedString(hit); h.font = .body.bold(); h.backgroundColor = .yellow.opacity(0.4)
            s += h
            s += AttributedString(after + "…")
            out.append((r.location, s))
            from = NSMaxRange(r)
        }
        return out
    }
}

// MARK: - shared bits

/// The round ✕ at the top right of a popover / sheet root.
struct PopoverClose: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).frame(width: 30, height: 30)
                .background(Color.primary.opacity(0.10), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Kapat")
    }
}

/// A − / + pair in a capsule, as in Voice Dream's cards.
private struct StepButtons: View {
    var canDecrease: Bool
    var canIncrease: Bool
    var decrease: () -> Void
    var increase: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: decrease) { Image(systemName: "minus").frame(width: 46, height: 34) }
                .disabled(!canDecrease).accessibilityLabel("Azalt")
            Divider().frame(height: 20)
            Button(action: increase) { Image(systemName: "plus").frame(width: 46, height: 34) }
                .disabled(!canIncrease).accessibilityLabel("Artır")
        }
        .buttonStyle(.borderless)
        .background(Color.primary.opacity(0.08), in: Capsule())
    }
}

// MARK: - Ses Ayarları (speaker icon)

/// Speed, language, voice and the advanced page, one popover. Every audio setting lives here and nowhere else.
struct AudioSettingsView: View {
    @Environment(AppModel.self) private var model
    /// nil = the document's own language (Turkish unless the document says otherwise).
    @State private var language: String?

    private var documentLanguage: String { Voices.base(model.currentDocument?.language ?? "tr") }
    private var shownLanguage: String { language ?? documentLanguage }

    var body: some View {
        NavigationStack {
            List {
                Section { SpeedCard() }
                Section {
                    NavigationLink { LanguagePage(language: $language, documentLanguage: documentLanguage) } label: {
                        LabeledContent("Dil", value: Voices.languageName(shownLanguage))
                    }
                    NavigationLink { VoicePage(language: shownLanguage) } label: {
                        LabeledContent("Ses", value: voiceName(for: shownLanguage))
                    }
                }
                Section {
                    NavigationLink("Gelişmiş Ses Ayarları") { AdvancedAudioPage() }
                }
            }
            .navigationTitle("Ses Ayarları")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { PopoverClose() } }
        }
        .presentationBackground(Color(uiColor: .systemGroupedBackground))
    }

    private func voiceName(for l: String) -> String {
        let id = l == documentLanguage ? model.currentVoiceID : model.voiceID(forLanguage: l)
        if id == ElevenLabs.readerVoiceID { return ElevenLabs.shared.displayName }
        return VoiceProfile.with(id: id)?.name ?? Voices.voice(id)?.name ?? "—"
    }
}

/// Konuşma Hızı: the only place the speed is set. Words a minute for system voices, ≈ words a minute for Voice Reader's
/// own voices (which move in 0.05× steps).
private struct SpeedCard: View {
    @Environment(AppModel.self) private var model
    @State private var value = 1.0
    @State private var documentOnly = false
    @State private var loaded = false

    var body: some View {
        let sys = model.isSystemVoice
        let unit = sys ? 5 / SpeechPlayer.wordsAtOneX : 0.05
        let words = sys ? SpeechPlayer.wpm(value) : model.player.wordsPerMinute(value)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Konuşma Hızı").font(.headline)
                Spacer()
                if documentOnly { Text("Belgeye özel").font(.footnote).foregroundStyle(.secondary) }
            }
            HStack(spacing: 10) {
                Image(systemName: "tortoise.fill").foregroundStyle(.secondary)
                Slider(value: $value, in: SpeechPlayer.speedRange, step: unit) { editing in if !editing { commit() } }
                    .accessibilityLabel("Konuşma hızı")
                Image(systemName: "hare.fill").foregroundStyle(.secondary)
            }
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text((sys ? "" : "≈ ") + "\(words)").font(.title2.weight(.semibold)).monospacedDigit()
                    Text("Dakikada okunacak kelime sayısı").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                StepButtons(canDecrease: value > SpeechPlayer.speedRange.lowerBound + 0.001,
                            canIncrease: value < SpeechPlayer.speedRange.upperBound - 0.001,
                            decrease: { value = max(SpeechPlayer.speedRange.lowerBound, value - unit); commit() },
                            increase: { value = min(SpeechPlayer.speedRange.upperBound, value + unit); commit() })
            }
            if model.currentDocument != nil {
                Toggle("Yalnız bu belge için", isOn: $documentOnly).font(.subheadline)
                    .onChange(of: documentOnly) { if loaded { commit() } }
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            value = model.currentDocument?.speed ?? model.settings.speed
            documentOnly = model.speedIsDocumentSpecific
            DispatchQueue.main.async { loaded = true }
        }
    }

    private func commit() { model.setSpeed(value, documentOnly: documentOnly) }
}

/// Dil: which language's voice is being chosen. Turkish and English are always there; every other language the phone
/// has a voice for stays folded away until it is opened.
private struct LanguagePage: View {
    @Binding var language: String?
    let documentLanguage: String
    @Environment(\.dismiss) private var dismiss
    @State private var more = false

    var body: some View {
        List {
            Section {
                row("tr")
                row("en")
            } footer: {
                Text("Dil, hangi dilin sesini seçtiğini belirler. Türkçe bir metindeki İngilizce cümleler İngilizce için seçtiğin sesle okunur.")
            }
            Section {
                DisclosureGroup("Diğer diller", isExpanded: $more) {
                    ForEach(Voices.languages(first: nil).filter { $0 != "tr" && $0 != "en" }, id: \.self) { l in row(l) }
                }
            }
        }
        .navigationTitle("Dil")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ l: String) -> some View {
        Button {
            language = l == documentLanguage ? nil : l
            dismiss()
        } label: {
            HStack {
                Text(Voices.languageName(l))
                Spacer()
                if (language ?? documentLanguage) == l { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
        .tint(.primary)
    }
}

/// Ses: the voices of the chosen language, nothing else. Turkish shows Voice Reader's own voices first.
private struct VoicePage: View {
    @Environment(AppModel.self) private var model
    let language: String
    @State private var documentOnly = false

    private var documentLanguage: String { Voices.base(model.currentDocument?.language ?? "tr") }

    var body: some View {
        List {
            if language == "tr" {
                if model.player.studio != nil {
                    Section {
                        profileRow(.studio)
                    } header: { Text("Stüdyo") } footer: {
                        Text("Bu kitap Mac'te büyük bir ses modeliyle önceden seslendirildi. Hazır olmayan yerleri Ema okur.")
                    }
                }
                ElevenVoiceSection(isSelected: isSelected(ElevenLabs.readerVoiceID)) {
                    model.setVoice(id: ElevenLabs.readerVoiceID, language: "tr", documentOnly: documentOnly)
                }
                Section {
                    ForEach(VoiceProfile.all) { profileRow($0) }
                } header: { Text("Wise Path sesleri") } footer: {
                    Text("Telefonda üretilir; hızlı dinleme için ayarlı.")
                }
            }
            Section {
                ForEach(Voices.voices(for: language), id: \.identifier) { systemRow($0) }
            } header: { Text(language == "tr" ? "iPhone sesleri" : Voices.languageName(language)) } footer: {
                if language == "en" {
                    Text("Türkçe metindeki İngilizce cümleler bu sesle okunur.")
                } else {
                    Text("Daha doğal sesler: iPhone Ayarlar › Erişilebilirlik › Seslendirilen İçerik › Sesler.")
                }
            }
            if model.currentDocument != nil, language == documentLanguage {
                Section { Toggle("Yalnız bu belge için", isOn: $documentOnly) }
            }
        }
        .navigationTitle("Ses")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { documentOnly = model.currentDocument?.voiceID != nil }
    }

    private func isSelected(_ id: String) -> Bool {
        language == documentLanguage ? model.currentVoiceID == id : model.voiceID(forLanguage: language) == id
    }

    private func check(_ on: Bool) -> some View {
        Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? Color.accentColor : .secondary)
    }

    private func profileRow(_ p: VoiceProfile) -> some View {
        HStack {
            Button { model.setVoice(id: p.id, language: "tr", documentOnly: documentOnly) } label: {
                HStack {
                    check(isSelected(p.id))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).fontWeight(.semibold)
                        Text(p.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .tint(.primary)
            .disabled(!p.isAvailable)
            Spacer()
            PreviewButton(profile: p)
        }
    }

    private func systemRow(_ v: AVSpeechSynthesisVoice) -> some View {
        HStack {
            Button { model.setVoice(id: v.identifier, language: language, documentOnly: documentOnly && language == documentLanguage) } label: {
                HStack {
                    check(isSelected(v.identifier))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(v.name)
                        HStack(spacing: 6) {
                            if let q = Voices.qualityName(v) {
                                Text(q).font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                            }
                            Text(Voices.regionName(v)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .tint(.primary)
            Spacer()
            Button { model.player.previewVoice(v) } label: { Image(systemName: "play.circle") }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(v.name) sesini dinle")
        }
    }
}

/// Gelişmiş Ses Ayarları: everything else about sound, once each.
private struct AdvancedAudioPage: View {
    @Environment(AppModel.self) private var model

    static func breakName(_ seconds: Double) -> String {
        let m = Int(seconds) / 60, r = Int(seconds) % 60
        return m == 0 ? "\(r) sn" : r == 0 ? "\(m) dk" : "\(m) dk \(r) sn"
    }

    var body: some View {
        @Bindable var s = model.settings
        List {
            VoiceTuningSection(voiceID: model.currentVoiceID, system: model.isSystemVoice)
            if !s.systemSpeech { Section {
                Toggle("Net ve gür ses", isOn: $s.clearVoice)
            } header: { Text("Ses gücü") } footer: {
                Text(s.clearVoice
                     ? "iPhone sesleri (Yelda, Cem…) Voice Dream'deki tınısıyla, biraz daha güçlü çalar: ünsüzler hafifçe öne çıkar, iğne gibi çıtırtılar ayıklanır, hiçbir yerde kırpılmaz."
                     : "iPhone sesleri sentezleyicinin ürettiği gibi, Voice Dream'deki gibi işlenmeden çalar.")
            } }
            Section {
                Toggle("Arka planda müzik (Spotify vb.)", isOn: Binding(get: { s.musicMix != .off }, set: { s.musicMix = $0 ? .mix : .off }))
                if s.musicMix != .off { MusicLevelSlider(value: $s.musicLevel) }
            } header: { Text("Arka plan müziği") } footer: {
                Text(s.musicMix == .off
                     ? "Kapalıyken okumaya başlamak müziği durdurur."
                     : "Sürgü müziğin okumaya göre ne kadar duyulacağını ayarlar: solda müzik hafif bir fon, sağda öne çıkar. Genel düzeyi telefonun ses tuşları belirler. Duraklat'a bastığın anda müzik öne çıkar.")
            }
            Section {
                Toggle("Müzik arası", isOn: $s.musicBreak)
                if s.musicBreak {
                    VStack(alignment: .leading) {
                        HStack { Text("Ne sıklıkla"); Spacer(); Text("\(Int(s.breakMinutes)) dakikada bir").foregroundStyle(.secondary).monospacedDigit() }
                        Slider(value: $s.breakMinutes, in: 3...15, step: 1) { Text("Ne sıklıkla") } minimumValueLabel: {
                            Text("3").font(.caption)
                        } maximumValueLabel: { Text("15").font(.caption) }
                    }
                    VStack(alignment: .leading) {
                        HStack { Text("Ara süresi"); Spacer(); Text(Self.breakName(s.breakSeconds)).foregroundStyle(.secondary).monospacedDigit() }
                        Slider(value: $s.breakSeconds, in: 30...120, step: 15) { Text("Ara süresi") } minimumValueLabel: {
                            Text("30 sn").font(.caption)
                        } maximumValueLabel: { Text("2 dk").font(.caption) }
                    }
                }
                Toggle("Arada müzik ekranını aç", isOn: $s.musicOnPause)
                Toggle("Kulaklıkla duraklatınca bekle, sonra sür", isOn: $s.remotePauseWaits)
                if s.remotePauseWaits {
                    Picker("Bekleme", selection: $s.waitSeconds) {
                        ForEach(ActivePauseChoice.all, id: \.seconds) { Text($0.name).tag($0.seconds) }
                    }
                }
            } header: { Text("Dinlenme") } footer: {
                Text("Belirlediğin süre kadar dinledikten sonra okuma bir cümlenin başında durur; ara bitince o cümleden kendiliğinden sürer. Ara sırasında oynat'a basarsan hemen sürer. Aktif bekleme: kulaklıkta ⏯ okumayı durdurur, seçtiğin süre sonunda (ya da müzik durunca) kendisi sürer; beklerken ⏯ hemen sürdürür. Ekranda oynat düğmesine basılı tutunca süreyi seçersin. Arada müzik ekranı: ara ya da bekleme boyunca müzik modu yazısız, yalnız ritimle açılır; okuma sürünce kendisi kapanır.")
            }
            Section("Okuma") {
                Picker("Belgenin sonunda", selection: $s.endBehavior) {
                    ForEach(EndBehavior.allCases) { Text($0.name).tag($0) }
                }
                Toggle("Cümle başından başla", isOn: $s.startAtSentence)
            }
            Section {
                Toggle("İngilizce cümleleri İngilizce sesle oku", isOn: $s.mixedLanguage)
                Toggle("Web ve e-posta adreslerini sadeleştir", isOn: $s.simplifyLinks)
                Toggle("Metin içi kaynak göstermelerini atla", isOn: $s.skipCitations)
            } header: { Text("Metin") } footer: {
                Text("Dört kelimeden uzun bir cümle açıkça İngilizceyse İngilizce sesle okunur. “https://www.ornek.com/yol” yalnız “ornek.com” diye okunur; “[12]” ya da “(Kant, 1781)” sesle okunmaz, sayfada kalır.")
            }
        }
        .navigationTitle("Gelişmiş Ses Ayarları")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: s.startAtSentence) { model.applyAudioSettingsSoon() }
        .onChange(of: s.simplifyLinks) { model.applyAudioSettingsSoon() }
        .onChange(of: s.skipCitations) { model.applyAudioSettingsSoon() }
        .onChange(of: s.mixedLanguage) { model.applyAudioSettingsSoon() }
        .onChange(of: s.musicMix) { model.applyAudioSettingsSoon() }
        .onChange(of: s.musicLevel) { model.applyAudioSettingsSoon() }
        .onChange(of: s.clearVoice) { model.applyAudioSettingsSoon() }
        .onChange(of: s.musicBreak) { model.applyAudioSettingsSoon() }
        .onChange(of: s.breakMinutes) { model.applyAudioSettingsSoon() }
        .onChange(of: s.breakSeconds) { model.applyAudioSettingsSoon() }
    }
}

/// The current voice's own tuning, as Voice Dream lays it out: Ses Miktarı 0…100 and Kalınlık 50…200 for a system voice,
/// Kalınlık in half tones for a Voice Reader voice, and Düzlük for both. Changes apply when the finger lifts.
private struct VoiceTuningSection: View {
    @Environment(AppModel.self) private var model
    let voiceID: String
    let system: Bool
    @State private var volume = 100.0
    @State private var pitch = 100.0
    @State private var steady = 0.0

    var body: some View {
        Group {
        if system {
            @Bindable var s = model.settings
            Section {
                Toggle("iPhone'un seslendirme ayarlarıyla oku", isOn: $s.systemSpeech)
                    .onChange(of: s.systemSpeech) { model.applyAudioSettingsSoon() }
            } footer: {
                Text(s.systemSpeech
                     ? "Türkçe ses, iPhone'un kendi Ekranı Seslendir'i gibi okur: ses, hız, perde ve ekolayzer Ayarlar › Erişilebilirlik › Seslendirilen İçerik'teki Türkçe ses ayarlarından gelir. Ses tınısı değişmeden yaklaşık 5 dB güçlendirilir, hiçbir yerde kırpılmaz. Bu kipte Wise Path'in hız düğmesi sesi değiştirmez. iOS 27'de Yelda'yı Voice Dream'deki kalınlığa yalnız bu ayar indirebiliyor."
                     : "Hız, ses miktarı ve kalınlık Wise Path'ten gelir. iOS 27'de kalınlık 50 bile Yelda'yı eskisi kadar kalınlaştırmaz.")
            }
        }
        if system && !model.settings.systemSpeech {
            Section {
                TuneCard(title: "Ses Miktarı", value: $volume, range: 0...100, step: 1, caption: "\(Int(volume))", commit: save)
            }
            Section {
                TuneCard(title: "Kalınlık", value: $pitch, range: 50...200, step: 5, caption: "\(Int(pitch))", commit: save)
            } footer: {
                Text("100 sesin kendisidir; 50 en kalın, 200 en ince. Bu ayarlar seçili sese aittir.")
            }
            Section {
                Button("Voice Dream ayarı: 330 · 100 · 50") { model.applyVoiceDreamSetting(); load() }
            } footer: {
                Text("Voice Dream'in bu sese verdiği ayarın aynısı: hız 330, ses miktarı 100, kalınlık 50. Voice Dream sesi başka hiçbir işlemden geçirmez (ekolayzeri yok); bu yüzden Düzlük ve Net ve gür ses kapanır.")
            }
        } else if let p = VoiceProfile.with(id: voiceID) {
            Section { DepthSlider(profile: p) } footer: { Text("Ses aynı kişi kalır, yalnız daha kalın ya da ince olur.") }
        }
        Section {
            TuneCard(title: "Düzlük", value: $steady, range: 0...70, step: 5,
                     caption: steady < 1 ? "Sesin kendisi" : "Tonlama %\(Int(steady)) daha düz", commit: save)
        } footer: {
            Text("Cümlenin iniş çıkışlarını daraltır: vurgular yönünü korur, boyu kısalır; ses rengi ve hız değişmez.")
        }
        }
        .onAppear(perform: load)
        .onChange(of: voiceID) { load() }
    }

    private func load() {
        let t = model.tune(voiceID)
        volume = (t.volume * 100).rounded()
        pitch = (t.pitch * 100).rounded()
        steady = (t.steady * 100).rounded()
    }

    private func save() { model.setTune(voiceID, VoiceTune(pitch: pitch / 100, volume: volume / 100, steady: steady / 100)) }
}

/// Kalınlık of a Voice Reader voice: −3 … +2 semitones in half steps (PSOLA, formants kept).
struct DepthSlider: View {
    @Environment(AppModel.self) private var model
    let profile: VoiceProfile

    var body: some View {
        let value = model.settings.voiceDepth[profile.id] ?? 0
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Kalınlık").font(.subheadline)
                Spacer()
                Text(Self.name(value)).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(value: Binding(get: { -value }, set: { v in
                model.settings.voiceDepth[profile.id] = abs(v) < 0.01 ? nil : -v
                model.applyAudioSettingsSoon()
            }), in: -2...3, step: 0.5) {
                Text("Kalınlık")
            } minimumValueLabel: { Text("İnce").font(.caption) } maximumValueLabel: { Text("Kalın").font(.caption) }
            .accessibilityValue(Self.name(value))
        }
    }

    static func name(_ v: Double) -> String {
        if abs(v) < 0.01 { return "Sesin kendisi" }
        let t = String(format: "%.1f", abs(v)).replacingOccurrences(of: ".0", with: "").replacingOccurrences(of: ".", with: ",")
        return v < 0 ? "\(t) ton daha kalın" : "\(t) ton daha ince"
    }
}

/// Plays a short sample of a Voice Reader voice (rendered on the spot, at the current speed).
struct PreviewButton: View {
    @Environment(AppModel.self) private var model
    let profile: VoiceProfile
    @State private var busy = false

    var body: some View {
        Button {
            busy = true
            let speed = model.player.speed
            let depth = model.settings.voiceDepth[profile.id] ?? 0
            let calm = model.settings.voiceTune[profile.id]?.steady ?? 0
            ProfileRenderer.shared.queue.async {
                let r = ProfileRenderer.shared.render("Merhaba, ben \(profile.name). Kitaplarını bu sesle, istediğin hızda okuyabilirim.",
                                                      profile: profile, speed: speed, depth: depth, calm: calm, cancelled: { false })
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        busy = false
                        if let r { SamplePlayer.shared.play(r.samples) }
                    }
                }
            }
        } label: {
            if busy { ProgressView() } else { Image(systemName: "play.circle") }
        }
        .buttonStyle(.borderless)
        .disabled(!profile.isAvailable || busy)
        .accessibilityLabel("\(profile.name) sesini dinle")
    }
}

/// One-off sample playback, separate from the reading engine.
@MainActor
final class SamplePlayer {
    static let shared = SamplePlayer()
    private var player: AVAudioPlayer?

    func play(_ samples: [Float]) {
        var data = Data()
        func le<T: FixedWidthInteger>(_ v: T) { var x = v.littleEndian; data.append(Data(bytes: &x, count: MemoryLayout<T>.size)) }
        let n = samples.count
        data.append("RIFF".data(using: .ascii)!); le(UInt32(36 + n * 2)); data.append("WAVEfmt ".data(using: .ascii)!)
        le(UInt32(16)); le(UInt16(1)); le(UInt16(1)); le(UInt32(48_000)); le(UInt32(96_000)); le(UInt16(2)); le(UInt16(16))
        data.append("data".data(using: .ascii)!); le(UInt32(n * 2))
        for v in samples { le(Int16(max(-1, min(1, v)) * 32767)) }
        let mixing = UserDefaults.standard.string(forKey: "a.music").map { $0 != MusicMix.off.rawValue } ?? false
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: mixing ? [.mixWithOthers] : [])
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(data: data)
        player?.play()
    }
}

// MARK: - Görsel Ayarlar (Aa icon)

/// Fonts and spacing, colours (light / dark / sepia / black, accent), the speech cursor. Every visual setting lives
/// here and nowhere else; the library's gear opens this same panel.
struct VisualSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        @Bindable var s = model.settings
        NavigationStack {
            List {
                Section {
                    NavigationLink("Yazı Tipi ve Aralık") { TypographyPage() }
                }
                Section {
                    Toggle("Sistem görünümünü izle", isOn: $s.followSystem)
                    Picker("Renk", selection: Binding(get: { s.effectiveTheme(systemDark: scheme == .dark) }, set: { s.theme = $0; s.followSystem = false })) {
                        ForEach(ReaderTheme.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    NavigationLink("Renk Ayarları") { AccentPage() }
                } header: { Text("Renkler") } footer: {
                    Text(s.followSystem ? "Telefon açıkken Açık, koyuyken Koyu görünür." : "Açık, Sepya, Koyu ve Siyah sayfa ile çubukların rengini birlikte değiştirir.")
                }
                Section {
                    NavigationLink("Konuşma İmleci") { CursorPage() }
                }
                Section {
                    NavigationLink { BikeStylePage() } label: {
                        LabeledContent("Bisiklet Düğmeleri", value: model.settings.bikeStyle.name)
                    }
                }
                Section {
                    Button("Varsayılanlara dön", role: .destructive) { s.restoreVisualDefaults() }
                }
            }
            .navigationTitle("Görsel Ayarlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { PopoverClose() } }
        }
        .presentationBackground(Color(uiColor: .systemGroupedBackground))
    }
}

private struct TypographyPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var s = model.settings
        List {
            Section {
                Picker("Yazı tipi", selection: $s.font) {
                    ForEach(ReaderFont.allCases) { f in Text(f.name).font(Font(f.font(size: 17))).tag(f) }
                }
                stepper("Yazı boyutu", value: $s.fontSize, range: 12...48, step: 1, format: "%.0f")
                stepper("Satır aralığı", value: $s.lineSpacing, range: 0...24, step: 1, format: "%.0f")
                stepper("Harf aralığı", value: $s.characterSpacing, range: -1...4, step: 0.25, format: "%.2f")
            }
            Section {
                Toggle("Kitap düzeni (girintili paragraf)", isOn: $s.bookLayout)
            }
        }
        .navigationTitle("Yazı Tipi ve Aralık")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stepper(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, format: String) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack { Text(title); Spacer(); Text(String(format: format, value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary) }
        }
    }
}

/// Renk Ayarları: the accent that colours the bars, icons, progress and switches. A preset or any colour.
private struct AccentPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var s = model.settings
        List {
            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 14) {
                    ForEach(Accent.presets) { p in
                        let on = s.accentHex == p.ink
                        Button { s.accentHex = p.ink } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle().fill(Accent(hex: p.ink).ink).frame(width: 42, height: 42)
                                    Circle().trim(from: 0.0, to: 0.5).fill(Accent(hex: p.ink).fill).frame(width: 42, height: 42).rotationEffect(.degrees(-45))
                                    if on { Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white) }
                                }
                                .overlay(Circle().strokeBorder(Color.primary.opacity(on ? 0.7 : 0.12), lineWidth: on ? 2.5 : 1).padding(-3))
                                Text(p.name).font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(p.name)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.vertical, 6)
                ColorPicker("Özel renk", selection: Binding(get: { Color(uiColor: Accent.base(hex: s.accentHex)) }, set: { s.accentHex = Accent.hex(of: $0) }), supportsOpacity: false)
            } header: { Text("Uygulama rengi") } footer: {
                Text("Üst ve alt çubuktaki simgeler, ilerleme çubuğu ve anahtarlar bu rengi alır. Oynat düğmesi her zaman turuncu-kırmızıdır.")
            }
        }
        .navigationTitle("Renk Ayarları")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Konuşma İmleci: the chip behind the word, the band behind the line, where the page keeps the line, focus mode.
private struct CursorPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        @Bindable var s = model.settings
        let theme = s.effectiveTheme(systemDark: scheme == .dark)
        List {
            Section { preview(theme) }
            Section {
                Toggle("Okunan kelimeyi işaretle", isOn: $s.showSpokenWord)
                if s.showSpokenWord { swatches("Kelime rengi", selection: $s.wordColor, options: MarkColor.allCases.filter { $0 != .paper }) }
            }
            Section {
                Toggle("Okunan satırı işaretle", isOn: $s.showSpokenLine)
                if s.showSpokenLine { swatches("Satır rengi", selection: $s.lineColor, options: MarkColor.allCases) }
            } footer: { Text("Satır işareti tek bir satırı kaplar ve ekranın iki kenarına uzanır; kelime işareti onun içinde gezer.") }
            Section {
                Picker("Satırın durduğu yer", selection: $s.cursorPosition) {
                    ForEach(CursorPosition.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Odak kipi", isOn: $s.focusMode)
            } header: { Text("Sayfa") } footer: {
                Text("Satır aşağı inince sayfa bir kez kayar ve satır seçtiğin yere döner. Odak kipi okunan cümle dışındaki metni soluklaştırır.")
            }
        }
        .navigationTitle("Konuşma İmleci")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Three lines of the page as it will look.
    private func preview(_ theme: ReaderTheme) -> some View {
        let s = model.settings
        let line: Color? = !s.showSpokenLine ? nil
            : s.lineColor == .paper ? Color(uiColor: theme.band)
            : Color(uiColor: s.lineColor.uiColor).opacity(theme.isDark ? 0.34 : 0.26)
        let font = Font(s.font.font(size: 17))
        let ink = Color(uiColor: theme.text)
        func row(@ViewBuilder _ c: () -> some View) -> some View {
            c().padding(.horizontal, 14).frame(maxWidth: .infinity, alignment: .leading).frame(height: 30)
        }
        return VStack(alignment: .leading, spacing: 0) {
            row { Text("Bu yüzden Berkeley'in sorusuna").font(font).foregroundStyle(ink) }
            row {
                HStack(spacing: 0) {
                    Text("cevabı, Locke'unkinden de ").font(font).foregroundStyle(ink)
                    Text("keskindir").font(font)
                        .foregroundStyle(s.showSpokenWord ? (s.wordColor.uiColor.isDark ? Color.white : Color.black) : ink)
                        .padding(.horizontal, 1)
                        .background(s.showSpokenWord ? Color(uiColor: s.wordColor.uiColor) : .clear, in: RoundedRectangle(cornerRadius: 2))
                    Text(":").font(font).foregroundStyle(ink)
                }
            }
            .background(line ?? .clear)
            row { Text("gözleri yeni açılan adam, küreyi").font(font).foregroundStyle(ink) }
        }
        .background(Color(uiColor: theme.background))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .listRowInsets(EdgeInsets())
        .accessibilityHidden(true)
    }

    private func swatches(_ title: String, selection: Binding<MarkColor>, options: [MarkColor]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(title); Spacer(); Text(selection.wrappedValue.name).foregroundStyle(.secondary) }
            HStack(spacing: 12) {
                ForEach(options) { c in
                    Button { selection.wrappedValue = c } label: {
                        Circle().fill(Color(uiColor: c.uiColor)).frame(width: 28, height: 28)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
                            .overlay(Circle().strokeBorder(Color.primary, lineWidth: selection.wrappedValue == c ? 2.5 : 0).padding(-3))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(c.name)
                    .accessibilityAddTraits(selection.wrappedValue == c ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct TuneCard: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let caption: String
    let commit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
            HStack(spacing: 10) {
                Text(String(format: "%.0f", range.lowerBound)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Slider(value: $value, in: range, step: step) { editing in if !editing { commit() } }
                    .accessibilityLabel(title)
                Text(String(format: "%.0f", range.upperBound)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            HStack {
                Text(caption).monospacedDigit()
                Spacer()
                HStack(spacing: 0) {
                    Button { value = max(range.lowerBound, value - step); commit() } label: {
                        Image(systemName: "minus").frame(width: 44, height: 32)
                    }
                    .disabled(value <= range.lowerBound)
                    .accessibilityLabel("\(title) azalt")
                    Divider().frame(height: 20)
                    Button { value = min(range.upperBound, value + step); commit() } label: {
                        Image(systemName: "plus").frame(width: 44, height: 32)
                    }
                    .disabled(value >= range.upperBound)
                    .accessibilityLabel("\(title) artır")
                }
                .buttonStyle(.borderless)
                .background(Color.primary.opacity(0.08), in: Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}

/// Background music, from barely there to up front, in 5 % steps.
struct MusicLevelSlider: View {
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading) {
            HStack { Text("Arka plan müziği"); Spacer(); Text("%\(Int(value))").foregroundStyle(.secondary).monospacedDigit() }
            Slider(value: $value, in: 0...100, step: 2) { Text("Arka plan müziği") } minimumValueLabel: {
                Image(systemName: "speaker.fill").font(.caption)
            } maximumValueLabel: { Image(systemName: "speaker.wave.3.fill").font(.caption) }
        }
    }
}
