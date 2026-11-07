// Widget'lar. Uygulamanın yazdığı anlık görüntüyü (widget.json) okur, hesap yapmaz.
//   · Ön çalışma   : paket adı, ① adımları, anahtar cümle; dokun → dinlemeye başla.
//   · Dünün cümlen : önce Türkçesi; İngilizcesi gizli, "Göster" ile açılır (önce hatırla).
//   · Cümle cümle  : günün metni tek tek; ‹ › ile geç, cümleye ya da 🔊'e dokun → uygulama açılmadan çalar.
//                    Büyükte: 🎙 kendin kur (kayıt) · YZ istemi · gizleme merdiveni · günün ve dünün kelimeleri.
//                    En büyükte (iOS 27 dikey dahil): yanında ya da altında günün bütün cümleleri, dokun → geç ve çal.
//   iOS 27: renklendirilmiş ve şeffaf Ana Ekran'da zemin kalkar; dolgular saydamlaşır, yazı dolgunun üstünde kaybolmaz (WidgetPill).
//   Zemin Teoria gibi: gündüz kâğıt beyazı, gece saf siyah, köşede kehribar ışıma (TemaZemin); uzun cümlede yazı küçülür.
import WidgetKit
import SwiftUI
import AppIntents

struct Giris: TimelineEntry {
    let date: Date
    let a: WidgetAnlik?
}

struct Saglayici: TimelineProvider {
    func placeholder(in context: Context) -> Giris { Giris(date: Date(), a: .ornek) }
    func getSnapshot(in context: Context, completion: @escaping (Giris) -> Void) {
        completion(Giris(date: Date(), a: context.isPreview ? .ornek : (Paylasim.oku() ?? .ornek)))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Giris>) -> Void) {
        let simdi = Date()
        completion(Timeline(entries: [Giris(date: simdi, a: Paylasim.oku())],
                            policy: .after(simdi.addingTimeInterval(3600))))
    }
}

// MARK: - Tinted and clear Home Screen

extension WidgetFamily {
    var isLargest: Bool {
        if self == .systemExtraLarge { return true }
        if #available(iOS 27.0, *), self == .systemExtraLargePortrait { return true }
        return false
    }
    var isLargestPortrait: Bool {
        if #available(iOS 27.0, *), self == .systemExtraLargePortrait { return true }
        return false
    }
}

/// Outside full colour the system keeps only alpha: an opaque fill would swallow the text on it.
struct WidgetPill: View {
    @Environment(\.widgetRenderingMode) private var mode
    var color: Color
    var strong = false
    var body: some View {
        Capsule().fill(mode == .fullColor ? color : Color.primary.opacity(strong ? 0.3 : 0.14))
    }
}

/// Text and icons on a filled pill: dark on amber, white on red; plain primary outside full colour.
struct OnFill: ViewModifier {
    @Environment(\.widgetRenderingMode) private var mode
    var alert = false
    func body(content: Content) -> some View {
        content.foregroundStyle(mode == .fullColor ? (alert ? Color.white : Color.black.opacity(0.85)) : Color.primary)
    }
}

// MARK: - Ön çalışma

struct AdimNoktalari: View {
    @Environment(\.widgetRenderingMode) private var mode
    var adim: WidgetAnlik.Adim?
    var body: some View {
        HStack(spacing: 6) {
            nokta("headphones", (adim?.dinleme ?? 0) > 0, Tema.vurgu)
            nokta("text.alignleft", adim?.okuma ?? false, Tema.kehribar)
            nokta("mic.fill", (adim?.kayit ?? 0) > 0, Tema.yesil)
        }
    }
    private func nokta(_ s: String, _ dolu: Bool, _ r: Color) -> some View {
        Image(systemName: dolu ? "checkmark" : s)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(mode != .fullColor ? Color.primary : (dolu ? Color.white : r))
            .frame(width: 22, height: 22)
            .background { Circle().fill(mode != .fullColor ? Color.primary.opacity(dolu ? 0.3 : 0.1) : (dolu ? r : r.opacity(0.15))) }
    }
}

struct OnCalismaGorunum: View {
    @Environment(\.widgetFamily) var aile
    var a: WidgetAnlik?

    var body: some View {
        switch aile {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(a?.gun.map { "Gün \($0) · ön çalışma" } ?? "Memories").font(.caption2.weight(.semibold))
                Text(a?.baslik ?? "Paket bekleniyor").font(.headline).lineLimit(1)
                Text(adimYazi).font(.caption2)
            }
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "headphones").font(.caption)
                    Text("\(adimSayi)/3").font(.caption.weight(.bold))
                }
            }
        case .systemSmall:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(a?.gun.map { "GÜN \($0)" } ?? "MEMORIES").font(.caption2.weight(.bold)).foregroundStyle(Tema.ikincil)
                    Spacer()
                    Image(systemName: "play.circle.fill").font(.title3).foregroundStyle(Tema.metin)
                }
                Spacer(minLength: 0)
                Text(a?.baslik ?? "Paket bekleniyor").font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(Tema.metin).lineLimit(2).minimumScaleFactor(0.8)
                if let s = a?.sure { Text(Tarih.dakika(s)).font(.caption).foregroundStyle(Tema.ikincil) }
                AdimNoktalari(adim: a?.adim)
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(a?.gun.map { "GÜN \($0) · ÖN ÇALIŞMA" } ?? "MEMORIES").font(.caption2.weight(.bold)).foregroundStyle(Tema.ikincil)
                    Spacer()
                    AdimNoktalari(adim: a?.adim)
                }
                Text(a?.baslik ?? "Paket bekleniyor").font(.system(.title2, design: .serif).weight(.semibold)).foregroundStyle(Tema.metin).lineLimit(1)
                if let k = a?.anahtar {
                    Text(k).font(.system(.callout, design: .serif)).foregroundStyle(Tema.ikincil).lineLimit(2)
                } else if let o = a?.ozet {
                    Text(o).font(.caption).foregroundStyle(Tema.ikincil).lineLimit(2)
                }
                Spacer(minLength: 0)
                HStack {
                    Label(a?.sure.map { Tarih.dakika($0) } ?? "—", systemImage: "headphones").font(.caption.weight(.semibold))
                    Spacer()
                    Label("Dinle", systemImage: "play.fill").font(.caption.weight(.bold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background { WidgetPill(color: Tema.kehribar, strong: true) }.modifier(OnFill())
                }
                .foregroundStyle(Tema.metin)
            }
        }
    }

    private var adimSayi: Int {
        guard let d = a?.adim else { return 0 }
        return (d.dinleme > 0 ? 1 : 0) + (d.okuma ? 1 : 0) + (d.kayit > 0 ? 1 : 0)
    }
    private var adimYazi: String {
        guard let d = a?.adim else { return "dinle · oku · sesinle" }
        return [d.dinleme > 0 ? "✓ dinle" : "dinle", d.okuma ? "✓ oku" : "oku", d.kayit > 0 ? "✓ sesinle" : "sesinle"].joined(separator: " · ")
    }
}

struct OnCalismaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MemoriesOnCalisma", provider: Saglayici()) { g in
            OnCalismaGorunum(a: g.a)
                .widgetURL(URL(string: "memories://dinle"))
                .containerBackground(for: .widget) { TemaZemin() }
        }
        .configurationDisplayName("Ön çalışma")
        .description("Yarın yazacağın metnin paketi: dinle, oku, kendi sesinle oku.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

// MARK: - Dünün cümlen (önce hatırla)

struct DunGoster: AppIntent {
    static var title: LocalizedStringResource = "Dünün cümlesini göster"
    func perform() async throws -> some IntentResult {
        Paylasim.ayar.set(!Paylasim.ayar.bool(forKey: Paylasim.dunAcik), forKey: Paylasim.dunAcik)
        return .result()
    }
}

struct DunGorunum: View {
    @Environment(\.widgetFamily) var aile
    var a: WidgetAnlik?
    var acik: Bool

    var body: some View {
        if let tr = a?.dunTr, let en = a?.dunEn {
            if aile == .accessoryRectangular {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Dünün cümlen").font(.caption2.weight(.semibold))
                    Text(acik ? en : tr).font(.caption).lineLimit(3)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(a?.dunGun.map { "Gün \($0) · dünün cümlen" } ?? "Dünün cümlen", systemImage: "sparkles")
                            .font(.caption2.weight(.bold)).foregroundStyle(Tema.kehribarYazi)
                        Spacer()
                        Button(intent: DunGoster()) {
                            Image(systemName: acik ? "eye.slash" : "eye").font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain).foregroundStyle(Tema.vurgu)
                    }
                    Text(tr).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    if acik {
                        Text(en).font(.system(.callout, design: .serif).weight(.medium)).lineLimit(3)
                    } else {
                        Text("İngilizcesini kafanda kur, sonra göz'e dokun.").font(.caption).foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                    if let r = a?.rota {
                        Label("Yarın dikkat: \(r)", systemImage: "signpost.right").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Label("Dünün cümlen", systemImage: "sparkles").font(.caption.weight(.bold)).foregroundStyle(Tema.kehribarYazi)
                Text("Mac'te yazdığın günün çözümü gelince burada bir cümlen durur.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct DunWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MemoriesDun", provider: Saglayici()) { g in
            DunGorunum(a: g.a, acik: Paylasim.ayar.bool(forKey: Paylasim.dunAcik))
                .widgetURL(URL(string: "memories://cozum"))
                .containerBackground(for: .widget) { TemaZemin() }
        }
        .configurationDisplayName("Dünün cümlen")
        .description("Önce Türkçesi; İngilizcesini kafanda kur, sonra aç.")
        .supportedFamilies([.systemMedium, .accessoryRectangular])
    }
}

// MARK: - Cümle cümle (geç · seslendir · kendin kur · YZ istemi, uygulama açılmadan)

/// Sentence size by length: a long sentence gets a smaller font so it fits whole, its last words are never cut.
enum SentenceFont {
    static func large(_ s: String) -> Font {
        s.count <= 80 ? .system(.title3, design: .serif).weight(.medium)
            : s.count <= 140 ? .system(.body, design: .serif).weight(.medium)
            : .system(.callout, design: .serif).weight(.medium)
    }
    static func medium(_ s: String) -> Font {
        s.count <= 70 ? .system(.callout, design: .serif).weight(.medium)
            : s.count <= 120 ? .system(.subheadline, design: .serif).weight(.medium)
            : .system(.footnote, design: .serif).weight(.medium)
    }
}

struct SentenceView: View {
    @Environment(\.widgetFamily) var family
    var a: WidgetAnlik?
    var index: Int

    private var list: [WidgetAnlik.WidgetSentence] { a?.sentences ?? [] }

    var body: some View {
        if let gun = a?.gun, list.indices.contains(index) {
            let s = list[index]
            switch family {
            case .accessoryRectangular:
                // Kilit ekranı: dokun → çalar ve sıradakine geçer (her dokunuş bir cümle).
                Button(intent: SpeakSentence(day: gun, index: s.i, advance: true)) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(index + 1)/\(list.count) · dokun, dinle").font(.caption2.weight(.semibold))
                        Text(s.en).font(.caption).lineLimit(3).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            case .systemLarge:
                LargeSentence(a: a, gun: gun, s: s, index: index, count: list.count)
            case _ where family.isLargest:
                LargestSentence(a: a, gun: gun, s: s, index: index, list: list, portrait: family.isLargestPortrait)
            default:
                let recording = RebuildState.isRecording(gun, s.i)
                let text = recording ? (s.tr ?? "Söyle…") : s.en
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("GÜN \(gun) · \(index + 1)/\(list.count)")
                            .font(.caption2.weight(.bold)).tracking(0.6).foregroundStyle(Tema.ikincil)
                        Spacer()
                        MicButton(gun: gun, i: s.i, compact: true)
                        WidgetControl(intent: PreviousSentence(), icon: "chevron.left", label: "Önceki cümle")
                        WidgetControl(intent: NextSentence(), icon: "chevron.right", label: "Sonraki cümle")
                    }
                    Button(intent: SpeakSentence(day: gun, index: s.i)) {
                        HStack(alignment: .top, spacing: 8) {
                            Text(text)
                                .font(SentenceFont.medium(text))
                                .foregroundStyle(Tema.metin)
                                .lineLimit(5)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            SpeakerBadge()
                        }
                    }
                    .buttonStyle(.plain)
                    .layoutPriority(1)
                    .accessibilityLabel("Cümleyi seslendir")
                    // Türkçesi yalnız yer varsa: uzun cümlede İngilizcenin sonu kesilmesin
                    if let tr = s.tr, !recording, s.en.count <= 110 {
                        Text(tr).font(.caption).foregroundStyle(Tema.ikincil).lineLimit(2).minimumScaleFactor(0.85)
                    }
                    Spacer(minLength: 0)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Label("Cümle cümle", systemImage: "text.alignleft").font(.caption.weight(.bold))
                Text("Paket telefona inince günün cümleleri burada durur.").font(.caption)
            }
            .foregroundStyle(family == .accessoryRectangular ? Color.primary : Tema.metin)
        }
    }
}

/// Large widget: the sentence (faded by the ladder) · listen · build it yourself · AI prompt · the words of today and yesterday.
struct LargeSentence: View {
    var a: WidgetAnlik?
    var gun: Int
    var s: WidgetAnlik.WidgetSentence
    var index: Int
    var count: Int
    var showsWords = true

    private var recording: Bool { RebuildState.isRecording(gun, s.i) }
    private var rung: Int { RebuildState.rung(gun, s.i) }
    private var revealed: Bool { RebuildState.isRevealed(gun, s.i) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("GÜN \(gun) · CÜMLE \(index + 1)/\(count)")
                    .font(.caption2.weight(.bold)).tracking(0.6).foregroundStyle(Tema.ikincil).widgetAccentable()
                Spacer()
                Button(intent: StepRung(day: gun, index: s.i)) { RungDots(rung: rung) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Gizleme: \(Fade.label(rung))")
                WidgetControl(intent: PreviousSentence(), icon: "chevron.left", label: "Önceki cümle")
                WidgetControl(intent: NextSentence(), icon: "chevron.right", label: "Sonraki cümle")
            }
            sentence.layoutPriority(2)
            actions
            statusLine
            if showsWords {
                Spacer(minLength: 0)
                // Kelimeler kalan yere sığdığı kadar: önce tam ızgara, sığmazsa tek satır, o da sığmazsa hiç.
                ViewThatFits(in: .vertical) {
                    WordsPanel(a: a, grid: true)
                    WordsPanel(a: a, grid: false)
                    Color.clear.frame(height: 0)
                }
            }
        }
    }

    // The sentence: while recording only the Turkish (you build it, you do not read it); otherwise the ladder's form.
    @ViewBuilder private var sentence: some View {
        let shown: String? = recording ? nil
            : (revealed ? s.en : (RebuildState.isHidden(gun, s.i) ? nil : Fade.text(s.en, rung: rung)))
        HStack(alignment: .top, spacing: 8) {
            Button(intent: SpeakSentence(day: gun, index: s.i)) {
                VStack(alignment: .leading, spacing: 5) {
                    if let shown {
                        Text(shown)
                            .font(SentenceFont.large(shown))
                            .foregroundStyle(Tema.metin).lineLimit(7).minimumScaleFactor(0.7)
                        if let tr = s.tr {
                            Text(tr).font(.footnote).foregroundStyle(Tema.ikincil).lineLimit(3).minimumScaleFactor(0.85)
                        }
                    } else {
                        Text(recording ? "Şimdi kendin söyle" : (RebuildState.isHidden(gun, s.i) && !revealed ? "Gizli · önce kafanda kur" : "Türkçesinden kur"))
                            .font(.caption2.weight(.bold)).foregroundStyle(Tema.kehribarYazi)
                        Text(s.tr ?? "—")
                            .font(SentenceFont.large(s.tr ?? ""))
                            .foregroundStyle(Tema.metin).lineLimit(7).minimumScaleFactor(0.7)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cümleyi seslendir")
            VStack(spacing: 6) {
                Button(intent: SpeakSentence(day: gun, index: s.i)) { SpeakerBadge() }.buttonStyle(.plain)
                    .accessibilityLabel("Cümleyi seslendir")
                if !recording {
                    Button(intent: RevealSentence(day: gun, index: s.i)) {
                        Image(systemName: shown == nil || (shown != s.en && !revealed) ? "eye" : "eye.slash")
                            .font(.caption.weight(.bold)).foregroundStyle(Tema.metin)
                            .frame(width: 34, height: 30).background { WidgetPill(color: Tema.yuzey2) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(shown == s.en ? "Cümleyi gizle" : "Cümleyi göster")
                }
            }
        }
    }

    /// Kur fills the row (the main act); the AI prompt sits beside it. One copy button only: the prompt.
    private var actions: some View {
        HStack(spacing: 8) {
            MicButton(gun: gun, i: s.i, compact: false)
            Button(intent: CopyPrompt(index: s.i)) {
                Label(RebuildState.recentCopy ? "Panoda" : "YZ istemi", systemImage: RebuildState.recentCopy ? "checkmark" : "sparkles")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Tema.metin).lineLimit(1)
                    .padding(.horizontal, 14).frame(height: 44)
                    .background { WidgetPill(color: Tema.yuzey2) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("YZ istemini kopyala (uygulamayı açar)")
        }
    }

    @ViewBuilder private var statusLine: some View {
        let line: (String, String, Color)? = {
            if RebuildState.recentCopy { return ("checkmark.circle.fill", "İstem panoda: YZ uygulamasına yapıştır", Tema.yesil) }
            if recording { return ("waveform", "Türkçesine bak, İngilizcesini söyle · bitince Bitir", Tema.metin) }
            if let e = RebuildState.d.string(forKey: RebuildState.errorKey) { return ("exclamationmark.triangle.fill", e, Tema.kehribarYazi) }
            if let t = RebuildState.attempt(gun, s.i) {
                guard let r = t.ratio else { return ("checkmark", "Kaydedildi · Mac'te değerlendirilecek", Tema.metin) }
                let pct = "%\(Int((r * 100).rounded()))"
                let tail = t.missed.isEmpty ? "tam oturdu" : "takıldın: " + t.missed.prefix(3).joined(separator: ", ")
                return (r >= 0.85 ? "checkmark.seal.fill" : "arrow.triangle.2.circlepath", "Son denemen \(pct) · \(tail)",
                        r >= 0.85 ? Tema.yesil : Tema.kehribarYazi)
            }
            return nil
        }()
        if let line {
            Label(line.1, systemImage: line.0).font(.caption2.weight(.semibold)).foregroundStyle(line.2).lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }
}

/// The words of today and yesterday, a tap speaks one.
struct WordsPanel: View {
    var a: WidgetAnlik?
    var grid: Bool

    var body: some View {
        let today = a?.todayWords ?? []
        let y = a?.yesterdayWords ?? []
        if !today.isEmpty || !y.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Divider().overlay(Tema.cizgi)
                if !today.isEmpty {
                    if grid {
                        Text("BUGÜNÜN KELİMELERİ").font(.caption2.weight(.bold)).tracking(0.5).foregroundStyle(Tema.kehribarYazi)
                        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 5) {
                            ForEach(0..<((today.count + 2) / 3), id: \.self) { row in
                                GridRow {
                                    ForEach(0..<3, id: \.self) { col in
                                        let k = row * 3 + col
                                        if today.indices.contains(k) { WordChip(word: today[k]) } else { Color.clear.frame(height: 1) }
                                    }
                                }
                            }
                        }
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("BUGÜN").font(.caption2.weight(.bold)).tracking(0.5).foregroundStyle(Tema.kehribarYazi).fixedSize()
                            Text(today.map(\.w).joined(separator: " · ")).font(.caption).foregroundStyle(Tema.ikincil)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                    }
                }
                if !y.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(a?.yesterdayDay.map { "DÜN · GÜN \($0)" } ?? "DÜN").font(.caption2.weight(.bold)).tracking(0.5)
                            .foregroundStyle(Tema.soluk).fixedSize()
                        Text(y.map(\.w).joined(separator: " · ")).font(.caption).foregroundStyle(Tema.ikincil).lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
        }
    }
}

/// The largest size: the working sentence with all its tools, and beside it (below it when portrait) the whole day.
struct LargestSentence: View {
    var a: WidgetAnlik?
    var gun: Int
    var s: WidgetAnlik.WidgetSentence
    var index: Int
    var list: [WidgetAnlik.WidgetSentence]
    var portrait: Bool

    var body: some View {
        let day = DayList(gun: gun, list: list, current: index)
        if portrait {
            // The sentence and the words keep their height; the day takes what is left.
            VStack(alignment: .leading, spacing: 10) {
                LargeSentence(a: a, gun: gun, s: s, index: index, count: list.count, showsWords: false)
                    .fixedSize(horizontal: false, vertical: true)
                Divider().overlay(Tema.cizgi)
                day
                WordsPanel(a: a, grid: true).fixedSize(horizontal: false, vertical: true)
            }
        } else {
            HStack(alignment: .top, spacing: 16) {
                LargeSentence(a: a, gun: gun, s: s, index: index, count: list.count).frame(maxWidth: .infinity)
                Divider().overlay(Tema.cizgi)
                day.frame(maxWidth: .infinity)
            }
        }
    }
}

/// The day's sentences, as many as fit, kept around the current one. A tap selects and plays without opening the app.
struct DayList: View {
    @Environment(\.widgetRenderingMode) private var mode
    var gun: Int
    var list: [WidgetAnlik.WidgetSentence]
    var current: Int

    private static let rowHeight: CGFloat = 40
    private static let headerHeight: CGFloat = 20

    var body: some View {
        GeometryReader { g in
            let rows = min(list.count, max(1, Int((g.size.height - Self.headerHeight) / Self.rowHeight)))
            let start = min(max(0, current - rows / 2), list.count - rows)
            VStack(alignment: .leading, spacing: 0) {
                Text("BÜTÜN METİN · \(list.count) CÜMLE")
                    .font(.caption2.weight(.bold)).tracking(0.5).foregroundStyle(Tema.kehribarYazi).widgetAccentable()
                    .frame(height: Self.headerHeight, alignment: .topLeading)
                ForEach(start..<(start + rows), id: \.self) { p in row(p) }
            }
        }
    }

    private func row(_ p: Int) -> some View {
        let on = p == current
        return Button(intent: PlayDaySentence(day: gun, index: list[p].i, position: p)) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(p + 1)").font(.caption2.weight(.bold).monospacedDigit()).foregroundStyle(on ? Tema.kehribarYazi : Tema.soluk)
                    .frame(width: 18, alignment: .trailing)
                Text(list[p].en)
                    .font(.system(.footnote, design: .serif).weight(on ? .semibold : .regular))
                    .foregroundStyle(on ? Tema.metin : Tema.ikincil).lineLimit(2).minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 6)
            .frame(height: Self.rowHeight - 2)
            .background {
                if on {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(mode == .fullColor ? Tema.kehribar.opacity(0.14) : Color.primary.opacity(0.14))
                }
            }
            .frame(height: Self.rowHeight)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cümle \(p + 1): \(list[p].en)")
    }
}

struct RungDots: View {
    var rung: Int
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<RebuildState.rungs, id: \.self) { k in
                Circle().fill(k <= rung ? Tema.kehribar : Tema.soluk.opacity(0.45)).frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 8).frame(height: 30)
        .background { WidgetPill(color: Tema.yuzey2) }
    }
}

struct SpeakerBadge: View {
    var body: some View {
        Image(systemName: "speaker.wave.2.fill")
            .font(.subheadline.weight(.semibold)).foregroundStyle(Tema.vurgu)
            .frame(width: 34, height: 34)
            .background { Circle().fill(Tema.vurgu.opacity(0.14)) }
    }
}

/// 🎙 Kur. Large: a wide 44-pt button with the running time while recording; medium: a labelled capsule.
struct MicButton: View {
    var gun: Int
    var i: Int
    var compact: Bool
    var body: some View {
        let on = RebuildState.isRecording(gun, i)
        Button(intent: RebuildSentence(day: gun, index: i)) {
            if compact {
                Label(on ? "Bitir" : "Kur", systemImage: on ? "stop.fill" : "mic.fill")
                    .font(.caption.weight(.bold))
                    .modifier(OnFill(alert: true))
                    .padding(.horizontal, 10).frame(height: 30)
                    .background { WidgetPill(color: on ? Color.red : Tema.koyuMavi, strong: true) }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: on ? "stop.fill" : "mic.fill").font(.headline)
                    Text(on ? "Bitir" : "Kur").font(.headline)
                    if on, let t = RebuildState.activeStart {
                        Text(timerInterval: t...t.addingTimeInterval(RebuildState.tavan), countsDown: false)
                            .font(.subheadline.monospacedDigit()).opacity(0.85)
                            .frame(width: 40)
                    } else if !on {
                        Text("kendin söyle").font(.caption.weight(.medium)).opacity(0.7).lineLimit(1)
                    }
                }
                .modifier(OnFill(alert: true))
                .frame(maxWidth: .infinity).frame(height: 44)
                .background { WidgetPill(color: on ? Color.red : Tema.koyuMavi, strong: true) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(on ? "Kaydı bitir" : "Cümleyi kendin kur, kaydet")
    }
}

struct WordChip: View {
    @Environment(\.widgetRenderingMode) private var mode
    var word: WidgetAnlik.WidgetWord
    var body: some View {
        Button(intent: SpeakWord(word: word.w)) {
            VStack(alignment: .leading, spacing: 0) {
                Text(word.w).font(.system(.caption, design: .serif).weight(.semibold)).foregroundStyle(Tema.metin).lineLimit(1)
                if let tr = word.tr {
                    Text(tr).font(.system(size: 9)).foregroundStyle(Tema.soluk).lineLimit(1)
                }
            }
            .padding(.horizontal, 7).padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(mode == .fullColor ? Tema.yuzey2 : Color.primary.opacity(0.1)) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(word.w), seslendir")
    }
}

struct WidgetControl<I: AppIntent>: View {
    var intent: I
    var icon: String
    var label: String
    var body: some View {
        Button(intent: intent) {
            Image(systemName: icon).font(.subheadline.weight(.bold)).foregroundStyle(Tema.metin)
                .frame(width: 34, height: 30)
                .background { WidgetPill(color: Tema.yuzey2) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct SentenceProvider: TimelineProvider {
    func placeholder(in context: Context) -> Giris { Giris(date: Date(), a: .ornek) }
    func getSnapshot(in context: Context, completion: @escaping (Giris) -> Void) {
        completion(Giris(date: Date(), a: context.isPreview ? .ornek : (Paylasim.oku() ?? .ornek)))
    }
    /// A copy confirmation fades after 6 s: a second entry redraws the widget without it.
    func getTimeline(in context: Context, completion: @escaping (Timeline<Giris>) -> Void) {
        let now = Date()
        let a = Paylasim.oku()
        var entries = [Giris(date: now, a: a)]
        if let t = RebuildState.d.object(forKey: RebuildState.copyDateKey) as? Date, now.timeIntervalSince(t) < 6 {
            entries.append(Giris(date: t.addingTimeInterval(6.2), a: a))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3600))))
    }
}

struct SentenceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Paylasim.sentenceKind, provider: SentenceProvider()) { g in
            SentenceView(a: g.a, index: Paylasim.sentenceIndex(g.a))
                .widgetURL(URL(string: "memories://oku"))
                .containerBackground(for: .widget) { TemaZemin() }
        }
        .configurationDisplayName("Cümle cümle")
        .description("Günün metni tek tek: dinle, kendin kur (🎙), YZ istemi al. Büyükte kelimeler, en büyükte bütün metin.")
        .supportedFamilies(families)
    }

    private var families: [WidgetFamily] {
        var f: [WidgetFamily] = [.systemMedium, .systemLarge, .systemExtraLarge, .accessoryRectangular]
        if #available(iOS 27.0, *) { f.append(.systemExtraLargePortrait) }
        return f
    }
}

// MARK: - Live Activity: building a sentence (iOS requires it while the microphone records from a widget)

struct RebuildLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RebuildActivity.self) { c in
            RebuildLockScreen(tr: c.attributes.tr, d: c.state)
                .activityBackgroundTint(Tema.gece)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { c in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(c.state.done ? "Kaydedildi" : "Kendin kur", systemImage: c.state.done ? "checkmark.circle.fill" : "mic.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(Tema.kehribar).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RebuildTimer(d: c.state).font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(.white).padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if c.state.done {
                        Text(RebuildResult.text(c.state)).font(.subheadline).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                    } else {
                        VStack(spacing: 6) {
                            Text(c.attributes.tr).font(.footnote).foregroundStyle(.white.opacity(0.85)).lineLimit(2)
                            Button(intent: StopRebuild()) {
                                Label("Bitir", systemImage: "stop.fill").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
                            }.tint(.red)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: c.state.done ? "checkmark" : "mic.fill").foregroundStyle(Tema.kehribar)
            } compactTrailing: {
                RebuildCompactTimer(d: c.state)
            } minimal: {
                Image(systemName: "mic.fill").foregroundStyle(Tema.kehribar)
            }
            .keylineTint(Tema.kehribar)
        }
    }
}

enum RebuildResult {
    static func text(_ d: RebuildActivity.ContentState) -> String {
        guard let r = d.ratio else { return "Kayıt saklandı" }
        let pct = "%\(Int((r * 100).rounded()))"
        return d.missed.isEmpty ? "\(pct) · tam oturdu" : "\(pct) · takıldın: " + d.missed.prefix(3).joined(separator: ", ")
    }
}

struct RebuildTimer: View {
    var d: RebuildActivity.ContentState
    var body: some View {
        if d.done { Image(systemName: (d.ratio ?? 0) >= 0.85 ? "checkmark.seal.fill" : "checkmark") }
        else { Text(timerInterval: d.start...d.start.addingTimeInterval(RebuildState.tavan), countsDown: false) }
    }
}

/// iOS 27 can narrow the island: the timer then drops, the leading mic still says it is recording.
struct RebuildCompactTimer: View {
    var d: RebuildActivity.ContentState
    var body: some View {
        if #available(iOS 27.0, *) { WidthAwareTimer(d: d) } else { timer }
    }
    private var timer: some View {
        RebuildTimer(d: d).monospacedDigit().frame(width: 44).foregroundStyle(Tema.kehribar)
    }
}

@available(iOS 27.0, *)
struct WidthAwareTimer: View {
    @Environment(\.isDynamicIslandLimitedInWidth) private var limited
    var d: RebuildActivity.ContentState
    var body: some View {
        if limited {
            Image(systemName: d.done ? "checkmark" : "waveform").foregroundStyle(Tema.kehribar)
        } else {
            RebuildTimer(d: d).monospacedDigit().frame(width: 44).foregroundStyle(Tema.kehribar)
        }
    }
}

struct RebuildLockScreen: View {
    var tr: String
    var d: RebuildActivity.ContentState
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: d.done ? "checkmark.circle.fill" : "mic.fill").font(.title2).foregroundStyle(Tema.kehribar)
            VStack(alignment: .leading, spacing: 3) {
                Text(d.done ? "Memories · kaydedildi" : "Memories · cümleyi kendin kur").font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Text(d.done ? RebuildResult.text(d) : tr).font(.subheadline).foregroundStyle(.white).lineLimit(2)
            }
            Spacer()
            if d.done {
                RebuildTimer(d: d).foregroundStyle(.white)
            } else {
                VStack(spacing: 6) {
                    RebuildTimer(d: d).font(.headline.monospacedDigit()).foregroundStyle(.white)
                    Button(intent: StopRebuild()) { Image(systemName: "stop.fill") }.tint(.red)
                }
            }
        }
        .padding(16)
    }
}

@main
struct MemoriesWidgetBundle: WidgetBundle {
    var body: some Widget {
        OnCalismaWidget()
        SentenceWidget()
        DunWidget()
        RebuildLiveActivity()
        if #available(iOS 18.0, *) { ListenTodayControl() }
    }
}

@available(iOS 18.0, *)
struct ListenTodayControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.fatihgocgun.memories.control.listen") {
            ControlWidgetButton(action: OpenMemoriesIntent(.dinle)) { Label("Bugünü dinle", systemImage: "headphones") }
        }
        .displayName("Bugünü dinle")
        .description("Memories'i açar ve bugünün sesini başlatır.")
    }
}
