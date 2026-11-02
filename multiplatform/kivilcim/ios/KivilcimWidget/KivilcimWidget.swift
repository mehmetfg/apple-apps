// Kıvılcım widget uzantısı:
//  • Kilit ekranı / Denetim Merkezi denetimi (iOS 18): tek dokunuş, kilit açılmadan kayıt
//  • Kilit ekranı ve ana ekran widget'ları: kayıt düğmesi + son fikir
//  • Canlı Etkinlik: kayıt sürerken kilit ekranında ve Dynamic Island'da süre, canlı dalga, vazgeç · duraklat · bitir
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

// MARK: Canlı Etkinlik — yarı saydam sistem zemini, düz düğmeler: kilit ekranı, Dynamic Island ve adasız telefonda (13 Pro Max) şerit.
// Uygulama saniyede bir sayaç/duraklama/dalga yollar; düğmeler (vazgeç · duraklat · bitir) uygulamanın sürecinde çalışır.

struct KayitCanliEtkinligi: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: KayitEtkinligi.self) { c in
            KilitEkraniEtkinligi(d: c.state)
                // yarı saydam zemin: duvar kâğıdının bulanığı arkadan geçer, panel cam gibi durur
                .activityBackgroundTint(Color.black.opacity(0.32))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { c in
            let d = c.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Kure(d: d, boy: 38).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    sayac(d).font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white).multilineTextAlignment(.trailing)
                        .frame(width: 96, alignment: .trailing).padding(.trailing, 4).padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(durumYazisi(d)).font(.caption.weight(.bold)).foregroundStyle(etkinlikRengi(d)).padding(.top, 2)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if d.bitti {
                        Text(d.baslik).font(.subheadline.weight(.medium)).lineLimit(2)
                            .foregroundStyle(.white.opacity(0.85)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
                    } else {
                        VStack(spacing: 8) {
                            Dalga(seviyeler: d.seviyeler, duraklatildi: d.duraklatildi, adet: 24).frame(height: 18)
                            DenetimSirasi(d: d, boy: 34)
                        }
                        .padding(.horizontal, 4)
                    }
                }
            } compactLeading: {
                Image(systemName: d.bitti ? "checkmark" : (d.duraklatildi ? "pause.fill" : "waveform"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(etkinlikRengi(d))
                    .symbolEffect(.variableColor.iterative, isActive: !d.bitti && !d.duraklatildi)
                    .padding(.leading, 2)
            } compactTrailing: {
                sayac(d).font(.system(.subheadline, design: .rounded).weight(.semibold)).monospacedDigit()
                    .frame(width: 44).foregroundStyle(etkinlikRengi(d))
            } minimal: {
                Image(systemName: d.bitti ? "checkmark" : (d.duraklatildi ? "pause.fill" : "waveform"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(etkinlikRengi(d))
                    .symbolEffect(.variableColor.iterative, isActive: !d.bitti && !d.duraklatildi)
            }
            .keylineTint(etkinlikRengi(d))
        }
    }
}

@ViewBuilder
func sayac(_ d: KayitEtkinligi.ContentState) -> some View {
    if d.bitti { Text(Zaman.sure(d.sure)) }
    else { Text(timerInterval: d.baslangic...Date.distantFuture, pauseTime: d.duraklama, countsDown: false, showsHours: false) }
}

struct KilitEkraniEtkinligi: View {
    let d: KayitEtkinligi.ContentState
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Kure(d: d, boy: 52)
                VStack(alignment: .leading, spacing: 1) {
                    Text("KIVILCIM · \(durumYazisi(d).uppercased())")
                        .font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(etkinlikRengi(d))
                    if d.bitti {
                        Text(d.baslik).font(.headline).foregroundStyle(.white).lineLimit(2)
                    } else {
                        sayac(d).font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if d.bitti {
                    Text(Zaman.sure(d.sure)).font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.75))
                } else {
                    Dalga(seviyeler: d.seviyeler, duraklatildi: d.duraklatildi, adet: 14).frame(width: 92, height: 36)
                }
            }
            if !d.bitti { DenetimSirasi(d: d, boy: 46) }
        }
        .padding(16)
    }
}

/// Kilit ekranında ve adada aynı üç düğme: ✕ vazgeç · ‖ duraklat / ▶ devam · ■ bitir.
struct DenetimSirasi: View {
    let d: KayitEtkinligi.ContentState
    var boy: CGFloat = 44
    var body: some View {
        HStack(spacing: 10) {
            Button(intent: KaydiIptalNiyeti()) {
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white.opacity(0.9))
                    .frame(width: boy, height: boy).background { DugmeZemini() }
            }
            .buttonStyle(.plain).accessibilityLabel("Vazgeç")
            Button(intent: KaydiDuraklatNiyeti()) {
                Label(d.duraklatildi ? "Devam" : "Duraklat", systemImage: d.duraklatildi ? "play.fill" : "pause.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: boy).background { DugmeZemini() }
            }
            .buttonStyle(.plain)
            Button(intent: KaydiBitirNiyeti()) {
                Label("Bitir", systemImage: "stop.fill")
                    .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: boy).background { DugmeZemini(renk: .kivilcim) }
            }
            .buttonStyle(.plain)
        }
    }
}
