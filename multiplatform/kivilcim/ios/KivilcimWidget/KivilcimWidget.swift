// Kıvılcım widget uzantısı:
//  • Kilit ekranı / Denetim Merkezi denetimi (iOS 18): tek dokunuş, kilit açılmadan kayıt
//  • Kilit ekranı ve ana ekran widget'ları: kayıt düğmesi + son fikir
//  • Canlı Etkinlik: kayıt sürerken kilit ekranında ve Dynamic Island'da süre ve ■ bitir
import WidgetKit
import SwiftUI
import AppIntents
import ActivityKit

@main
struct KivilcimWidgetleri: WidgetBundle {
    var body: some Widget {
        KayitDenetimi()
        AcVeKaydetDenetimi()
        KivilcimWidget()
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

/// Yedek denetim: Face ID ile uygulamayı açar ve kaydı başlatır.
struct AcVeKaydetDenetimi: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.fatihgocgun.kivilcim.ac") {
            ControlWidgetButton(action: AcVeKaydetNiyeti()) {
                Label("Aç ve kaydet", systemImage: "mic.circle.fill")
            }
            .tint(.kivilcim)
        }
        .displayName("Aç ve kaydet")
        .description("Kıvılcım'ı açar ve kaydı başlatır (kilit açılır).")
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

// MARK: Canlı Etkinlik

struct KayitCanliEtkinligi: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: KayitEtkinligi.self) { c in
            KilitEkraniEtkinligi(d: c.state)
                .activityBackgroundTint(Color(hex: "#1B0F0C"))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { c in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(c.state.bitti ? "Kaydedildi" : "Kıvılcım", systemImage: c.state.bitti ? "checkmark.circle.fill" : "waveform")
                        .font(.caption.weight(.semibold)).foregroundStyle(Color.kivilcim).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    sayac(c.state).font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(.white).padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if c.state.bitti {
                        Text(c.state.baslik).font(.subheadline).lineLimit(1).foregroundStyle(.white.opacity(0.8))
                    } else {
                        Button(intent: KaydiBitirNiyeti()) {
                            Label("Bitir ve kaydet", systemImage: "stop.fill").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
                        }.tint(.kivilcim)
                    }
                }
            } compactLeading: {
                Image(systemName: c.state.bitti ? "checkmark" : "record.circle.fill").foregroundStyle(Color.kivilcim)
            } compactTrailing: {
                sayac(c.state).monospacedDigit().frame(width: 44).foregroundStyle(Color.kivilcim)
            } minimal: {
                Image(systemName: "waveform").foregroundStyle(Color.kivilcim)
            }
            .keylineTint(.kivilcim)
        }
    }
}

@ViewBuilder
func sayac(_ d: KayitEtkinligi.ContentState) -> some View {
    if d.bitti { Text(Zaman.sure(d.sure)) }
    else { Text(timerInterval: d.baslangic...Date.distantFuture, countsDown: false) }
}

struct KilitEkraniEtkinligi: View {
    let d: KayitEtkinligi.ContentState
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.kivilcim.opacity(0.18)).frame(width: 46, height: 46)
                Image(systemName: d.bitti ? "checkmark" : "waveform").font(.system(size: 20, weight: .semibold)).foregroundStyle(Color.kivilcim)
                    .symbolEffect(.variableColor.iterative, isActive: !d.bitti)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(d.bitti ? "Kaydedildi" : "Kıvılcım dinliyor").font(.headline).foregroundStyle(.white)
                if d.bitti { Text(d.baslik).font(.subheadline).foregroundStyle(.white.opacity(0.7)).lineLimit(1) }
                else { sayac(d).font(.system(.title2, design: .rounded).weight(.semibold).monospacedDigit()).foregroundStyle(.white) }
            }
            Spacer()
            if !d.bitti {
                Button(intent: KaydiBitirNiyeti()) {
                    Image(systemName: "stop.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 52, height: 52).background(Circle().fill(Color.kivilcim))
                }.buttonStyle(.plain)
            }
        }
        .padding(16)
    }
}
