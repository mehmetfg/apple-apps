// Kıvılcım widget uzantısı:
//  • Kilit ekranı / Denetim Merkezi denetimi (iOS 18): tek dokunuş, kilit açılmadan kayıt
//  • Kilit ekranı ve ana ekran widget'ları: kayıt düğmesi + son fikir
//  • Canlı Etkinlik: kayıt sürerken kilit ekranında ve Dynamic Island'da süre, duraklat · bitir
import WidgetKit
import SwiftUI
import AppIntents
import ActivityKit

@main
struct KivilcimWidgetleri: WidgetBundle {
    var body: some Widget {
        KayitDenetimi()
        AcVeKaydetDenetimi()
        GunlukDenetimi()
        SurekliDenetimi()
        KivilcimWidget()
        OpenSparksWidget()
        KayitCanliEtkinligi()
    }
}

// MARK: Denetim (kilit ekranının alt köşeleri, Denetim Merkezi, Eylem Düğmesi)

struct KayitDenetimi: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.fatihgocgun.kivilcim.denetim") {
            ControlWidgetButton(action: KaydiDegistirNiyeti()) {
                Label(WidgetDurumu.kayitta ? "Kaydı bitir" : "Fikir kaydet",
                      systemImage: WidgetDurumu.kayitta ? "stop.circle.fill" : "waveform.badge.mic")
            }
            .tint(.kivilcim)
        }
        .displayName("Fikir kaydet")
        .description("Kıvılcım: kilidi açmadan sesli fikir kaydı.")
    }
}

/// The old "open and record" control (2026-11-10): it opened the app every time. The silent path has worked on every
/// lock-screen press since 2026-11-05 (tani.log: 19 of 19 in the background), so this control now records without
/// opening the app too, and only steps into the app when the microphone cannot open in the background. Same kind,
/// so a control already placed on the lock screen or in Control Center keeps working without being re-added.
struct AcVeKaydetDenetimi: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.fatihgocgun.kivilcim.ac") {
            ControlWidgetButton(action: KaydiDegistirNiyeti()) {
                Label(WidgetDurumu.kayitta ? "Kaydı bitir" : "Kaydet",
                      systemImage: WidgetDurumu.kayitta ? "stop.circle.fill" : "mic.circle.fill")
            }
            .tint(.kivilcim)
        }
        .displayName("Kaydet (sessiz)")
        .description("Kıvılcım: uygulamayı açmadan kaydeder; mikrofon açılamazsa uygulamaya geçer.")
    }
}

/// Long spoken diary from the lock screen, Control Center or the Action Button.
struct GunlukDenetimi: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.fatihgocgun.kivilcim.gunluk") {
            ControlWidgetButton(action: StartJournalIntent()) {
                Label(WidgetDurumu.kayitta ? "Kaydı bitir" : "Sesli günlük", systemImage: WidgetDurumu.kayitta ? "stop.circle.fill" : "book.pages.fill")
            }
            .tint(.indigo)
        }
        .displayName("Sesli günlük")
        .description("Kıvılcım: uzun sesli günlük; o günün günlüğüne yazılır.")
    }
}

/// All-day listening: one press starts it, the next ends it.
struct SurekliDenetimi: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.fatihgocgun.kivilcim.surekli") {
            ControlWidgetButton(action: StartContinuousIntent()) {
                Label(WidgetDurumu.kayitta ? "Kaydı bitir" : "Sürekli dinle", systemImage: WidgetDurumu.kayitta ? "stop.circle.fill" : "ear.badge.waveform")
            }
            .tint(.teal)
        }
        .displayName("Sürekli dinle")
        .description("Kıvılcım: gün boyu dinler, yalnız konuşulan yerleri saklar.")
    }
}

// MARK: Open items widget — urgent first; ✓ marks done without opening the app

struct OpenEntry: TimelineEntry {
    let date: Date
    let items: [ItemSnapshot]
    let total: Int
}

struct OpenProvider: TimelineProvider {
    func entry() -> OpenEntry {
        let all = SharedStore.openItems()
        return OpenEntry(date: Date(), items: Array(all.prefix(12)), total: all.count)
    }
    func placeholder(in context: Context) -> OpenEntry {
        OpenEntry(date: Date(), items: [
            ItemSnapshot(id: "a", title: "Kan testi randevusu al", priority: 3, status: "open", kind: "spark", area: "Sağlık", color: "#E0565B", date: "", noteCount: 0),
            ItemSnapshot(id: "b", title: "Wise Path'e okuma yedeği", priority: 2, status: "open", kind: "extract", area: "Yazılım", color: "#2BB673", date: "", noteCount: 1),
            ItemSnapshot(id: "c", title: "Kant ve zaman üzerine deneme", priority: 1, status: "open", kind: "spark", area: "Felsefe", color: "#8E6FD8", date: "", noteCount: 0),
        ], total: 3)
    }
    func getSnapshot(in context: Context, completion: @escaping (OpenEntry) -> Void) {
        let e = entry(); completion(context.isPreview && e.items.isEmpty ? placeholder(in: context) : e)
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<OpenEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(Date().addingTimeInterval(1800))))
    }
}

struct OpenSparksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.fatihgocgun.kivilcim.acik", provider: OpenProvider()) { e in
            OpenSparksView(e: e).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Açık işler")
        .description("Öncelik sırasıyla açık kıvılcımlar; ✓ ile uygulamayı açmadan bitir.")
        .supportedFamilies(tallFamilies([.systemMedium, .systemLarge, .accessoryRectangular]))
    }
}

struct OpenSparksView: View {
    @Environment(\.widgetFamily) var family
    /// The tall size of iOS 27 counts as large, with room for twice as many.
    private var isTall: Bool {
        #if compiler(>=6.3)  // the iOS 27 SDK; Xcode 26 does not know this size
        if #available(iOS 27.0, *) { return family == .systemExtraLargePortrait }
        #endif
        return false
    }
    private var isBig: Bool { family == .systemLarge || isTall }
    let e: OpenEntry
    var body: some View {
        if family == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(e.total) açık").font(.headline).widgetAccentable()
                ForEach(e.items.prefix(2)) { s in
                    Text((s.priority == 3 ? "‼︎ " : "") + s.title).font(.caption).lineLimit(1)
                }
            }
        } else {
            let n = isTall ? 12 : isBig ? 6 : 3
            VStack(alignment: .leading, spacing: isBig ? 10 : 6) {
                HStack {
                    Label("Açık · \(e.total)", systemImage: "flame.fill").font(.subheadline.weight(.bold)).foregroundStyle(Color.kivilcim)
                    Spacer()
                    Button(intent: KaydiDegistirNiyeti()) { Image(systemName: "mic.fill").font(.subheadline.weight(.semibold)) }
                        .buttonStyle(.plain).foregroundStyle(Color.kivilcim)
                }
                if e.items.isEmpty {
                    Spacer(); Text("Açık iş yok 🎉").font(.subheadline).foregroundStyle(.secondary); Spacer()
                }
                ForEach(e.items.prefix(n)) { s in
                    HStack(spacing: 8) {
                        Button(intent: MarkDoneIntent(id: s.id)) {
                            Image(systemName: "circle").font(.system(size: 18)).foregroundStyle(Color(hex: s.prio.hex))
                        }.buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(s.title).font(.footnote.weight(.semibold)).lineLimit(1)
                            if isBig { Text(s.area).font(.caption2).foregroundStyle(Color(hex: s.color)) }
                        }
                        Spacer(minLength: 0)
                        if s.priority >= 2 { Image(systemName: s.prio.symbol).font(.caption2.weight(.heavy)).foregroundStyle(Color(hex: s.prio.hex)) }
                    }
                    .widgetURL(URL(string: "kivilcim://isler"))
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: Widget

struct Anlik: TimelineEntry {
    let date: Date
    let kayitta: Bool
    let baslik: String
    let alan: String
    let renk: String
    let zaman: Date?
    let bugun: Int
}

struct Saglayici: TimelineProvider {
    func anlik() -> Anlik {
        Anlik(date: Date(), kayitta: WidgetDurumu.kayitta, baslik: WidgetDurumu.sonBaslik, alan: WidgetDurumu.sonAlan,
              renk: WidgetDurumu.sonRenk, zaman: WidgetDurumu.sonZaman, bugun: WidgetDurumu.bugun)
    }
    func placeholder(in context: Context) -> Anlik {
        Anlik(date: Date(), kayitta: false, baslik: "Kant ve zaman üzerine kısa deneme", alan: "Felsefe", renk: "#8E6FD8", zaman: Date(), bugun: 3)
    }
    func getSnapshot(in context: Context, completion: @escaping (Anlik) -> Void) {
        completion(context.isPreview && WidgetDurumu.sonBaslik.isEmpty ? placeholder(in: context) : anlik())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Anlik>) -> Void) {
        completion(Timeline(entries: [anlik()], policy: .after(Date().addingTimeInterval(1800))))
    }
}

struct KivilcimWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.fatihgocgun.kivilcim.widget", provider: Saglayici()) { a in
            WidgetGorunumu(a: a).containerBackground(for: .widget) { ArkaPlan() }
        }
        .configurationDisplayName("Kıvılcım")
        .description("Tek dokunuşla fikir kaydı ve son fikrin.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct ArkaPlan: View {
    @Environment(\.widgetRenderingMode) var kip
    var body: some View {
        if kip == .fullColor {
            LinearGradient(colors: [Color(hex: "#2A1712"), Color(hex: "#160C0A")], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else { Color.clear }
    }
}

struct WidgetGorunumu: View {
    @Environment(\.widgetFamily) var aile
    let a: Anlik

    var body: some View {
        switch aile {
        case .accessoryCircular:
            Button(intent: KaydiDegistirNiyeti()) {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: a.kayitta ? "stop.fill" : "mic.fill").font(.system(size: 22, weight: .semibold))
                }
            }.buttonStyle(.plain).widgetAccentable()
        case .accessoryRectangular:
            Button(intent: KaydiDegistirNiyeti()) {
                HStack(spacing: 8) {
                    Image(systemName: a.kayitta ? "stop.circle.fill" : "mic.circle.fill").font(.system(size: 30))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(a.kayitta ? "Kaydediyor…" : "Fikir kaydet").font(.headline).widgetAccentable()
                        Text(a.baslik.isEmpty ? "Kıvılcım" : a.baslik).font(.caption).lineLimit(2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }.buttonStyle(.plain)
        case .systemMedium:
            HStack(spacing: 16) {
                kayitDugmesi(84)
                VStack(alignment: .leading, spacing: 6) {
                    Text(a.kayitta ? "Kaydediyor" : "Aklına geleni söyle").font(.headline).foregroundStyle(.white)
                    if !a.baslik.isEmpty {
                        Text(a.alan.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(Color(hex: a.renk))
                        Text(a.baslik).font(.subheadline).foregroundStyle(.white.opacity(0.85)).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Text("Bugün \(a.bugun) fikir").font(.caption2).foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 0)
            }
            .widgetURL(URL(string: "kivilcim://arsiv"))
        default:
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    kayitDugmesi(62)
                    Spacer()
                    if a.bugun > 0 {
                        Text("\(a.bugun)").font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(.white.opacity(0.9))
                    }
                }
                Spacer(minLength: 0)
                Text(a.kayitta ? "Kaydediyor…" : (a.baslik.isEmpty ? "Fikir kaydet" : a.baslik))
                    .font(.footnote.weight(.semibold)).foregroundStyle(.white).lineLimit(2)
                if !a.kayitta, let z = a.zaman {
                    Text(z, style: .relative).font(.caption2).foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }

    private func kayitDugmesi(_ boy: CGFloat) -> some View {
        Button(intent: KaydiDegistirNiyeti()) {
            ZStack {
                Circle().fill(LinearGradient(colors: [Color(hex: "#FF8A4C"), .kivilcimKoyu], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: a.kayitta ? "stop.fill" : "mic.fill").font(.system(size: boy * 0.38, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(width: boy, height: boy)
            .shadow(color: .kivilcim.opacity(0.5), radius: 10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: Live Activity — the recording popup on the lock screen, in the Dynamic Island and (on a phone without an
// island) as a banner. 2026-11-10 rework: it no longer redraws every second. The app updates it only when the state
// changes (start, pause, resume); the clock is the system timer, which runs on its own without updates. The old card
// sent a waveform every second, and the system throttles Live Activity updates, so it moved in jerks. When the
// recording ends the popup goes away at once: no "saved" card and no priority buttons.

struct KayitCanliEtkinligi: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: KayitEtkinligi.self) { c in
            LockScreenRecording(d: c.state)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { c in
            let d = c.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    StatusBadge(d: d, size: 40).padding(.leading, 6).padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RecordingTimer(d: d).font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white).multilineTextAlignment(.trailing)
                        .frame(width: 100, alignment: .trailing).padding(.trailing, 6).padding(.top, 8)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(durumYazisi(d)).font(.caption.weight(.bold)).foregroundStyle(etkinlikRengi(d)).padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        PauseButton(d: d, size: 44, wide: true)
                        StopButton(size: 44, wide: true)
                    }
                    .padding(.horizontal, 6).padding(.top, 6)
                }
            } compactLeading: {
                Image(systemName: d.duraklatildi ? "pause.fill" : "mic.fill")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(etkinlikRengi(d)).padding(.leading, 2)
            } compactTrailing: {
                RecordingTimer(d: d).font(.system(.subheadline, design: .rounded).weight(.semibold)).monospacedDigit()
                    .frame(width: 44).foregroundStyle(etkinlikRengi(d))
            } minimal: {
                Image(systemName: d.duraklatildi ? "pause.fill" : "mic.fill")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(etkinlikRengi(d))
            }
            .keylineTint(etkinlikRengi(d))
        }
    }
}

/// The system draws and advances this clock itself; while paused it stands still at the pause moment.
struct RecordingTimer: View {
    let d: KayitEtkinligi.ContentState
    var body: some View {
        if d.bitti { Text(Zaman.sure(d.sure)) }
        else { Text(timerInterval: d.baslangic...Date.distantFuture, pauseTime: d.duraklama, countsDown: false, showsHours: false) }
    }
}

/// Status mark: a still symbol in a tinted circle. No symbol effect: a Live Activity cannot run one smoothly.
struct StatusBadge: View {
    let d: KayitEtkinligi.ContentState
    var size: CGFloat
    var body: some View {
        Image(systemName: d.duraklatildi ? "pause.fill" : "mic.fill")
            .font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(etkinlikRengi(d))
            .frame(width: size, height: size)
            .background { Circle().fill(etkinlikRengi(d).opacity(0.22)) }
    }
}

/// One row, like Voice Memos: status and clock on the left, pause and stop on the right.
struct LockScreenRecording: View {
    let d: KayitEtkinligi.ContentState
    var body: some View {
        HStack(spacing: 12) {
            StatusBadge(d: d, size: 46)
            VStack(alignment: .leading, spacing: 0) {
                Text(durumYazisi(d).uppercased())
                    .font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(etkinlikRengi(d))
                RecordingTimer(d: d).font(.system(size: 32, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            PauseButton(d: d, size: 50)
            StopButton(size: 50)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }
}

/// Pause ↔ resume; runs in the app process (LiveActivityIntent).
struct PauseButton: View {
    let d: KayitEtkinligi.ContentState
    var size: CGFloat
    var wide = false
    var body: some View {
        Button(intent: KaydiDuraklatNiyeti()) {
            Group {
                if wide {
                    Label(d.duraklatildi ? "Devam" : "Duraklat", systemImage: d.duraklatildi ? "play.fill" : "pause.fill")
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
                } else {
                    Image(systemName: d.duraklatildi ? "play.fill" : "pause.fill")
                        .font(.system(size: size * 0.36, weight: .bold)).frame(width: size)
                }
            }
            .foregroundStyle(.white).frame(height: size)
            .background { Capsule().fill(Color.white.opacity(0.18)) }
        }
        .buttonStyle(.plain).accessibilityLabel(d.duraklatildi ? "Devam" : "Duraklat")
    }
}

/// Stop: saves the recording; the popup closes right away.
struct StopButton: View {
    var size: CGFloat
    var wide = false
    var body: some View {
        Button(intent: KaydiBitirNiyeti()) {
            Group {
                if wide {
                    Label("Bitir", systemImage: "stop.fill").font(.subheadline.weight(.bold)).frame(maxWidth: .infinity)
                } else {
                    Image(systemName: "stop.fill").font(.system(size: size * 0.36, weight: .bold)).frame(width: size)
                }
            }
            .foregroundStyle(.white).frame(height: size)
            .background { Capsule().fill(Color.kivilcim) }
        }
        .buttonStyle(.plain).accessibilityLabel("Bitir")
    }
}

/// Adds the tall size of iOS 27 (the largest one on an iPhone) where the system has it.
func tallFamilies(_ base: [WidgetFamily]) -> [WidgetFamily] {
    #if compiler(>=6.3)  // the iOS 27 SDK; Xcode 26 does not know this size
    if #available(iOS 27.0, *) { return base + [.systemExtraLargePortrait] }
    #endif
    return base
}
