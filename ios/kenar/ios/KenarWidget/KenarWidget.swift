// Kenar widget uzantısı:
//  • Metin iskeleti (küçük · orta · büyük) — beş bölüm, kelime, sıradaki hamle
//  • Kilit ekranı (dikdörtgen: hamle · yuvarlak: kelime halkası · satır)
//  • Okuma oturumu Canlı Etkinliği — kitap, soru, süre, işaret; "İşaretle" ve "Bitir"
//  • Denetim Merkezi / kilit ekranı denetimleri (iOS 18): Okumaya başla · Kamerayla işaretle · Feynman dakikası
import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct KenarWidgetleri: WidgetBundle {
    var body: some Widget {
        MetinWidget()
        OkumaCanliEtkinligi()
        OkumaDenetimi()
        KameraDenetimi()
        AnlatDenetimi()
    }
}

// MARK: metin iskeleti

struct Anlik: TimelineEntry {
    let date: Date
    let ozet: WidgetOzet?
}

struct Saglayici: TimelineProvider {
    func placeholder(in context: Context) -> Anlik { Anlik(date: .now, ozet: .ornek) }
    func getSnapshot(in context: Context, completion: @escaping (Anlik) -> Void) {
        completion(Anlik(date: .now, ozet: Depo.ozet ?? (context.isPreview ? .ornek : nil)))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Anlik>) -> Void) {
        completion(Timeline(entries: [Anlik(date: .now, ozet: Depo.ozet)], policy: .after(.now.addingTimeInterval(3600))))
    }
}

struct MetinWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.fatihgocgun.kenar.metin", provider: Saglayici()) { a in
            MetinWidgetGorunumu(a: a).containerBackground(for: .widget) { Zemin() }
        }
        .configurationDisplayName("Tek metin")
        .description("Metnin beş bölümü, kelime sayısı ve sıradaki tek hamle.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct Zemin: View {
    @Environment(\.widgetRenderingMode) var kip
    var body: some View { if kip == .fullColor { Color.kagit } else { Color.clear } }
}

struct MetinWidgetGorunumu: View {
    @Environment(\.widgetFamily) var aile
    let a: Anlik

    var body: some View {
        if let o = a.ozet {
            icerik(o).widgetURL(URL(string: o.hamle.adres))
        } else {
            VStack(spacing: 6) {
                Image(systemName: "text.book.closed").font(.title2).foregroundStyle(Color.kalem)
                Text("Kenar'ı aç, vault'u seç.").font(.caption).multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder private func icerik(_ o: WidgetOzet) -> some View {
        switch aile {
        case .accessoryCircular:
            Gauge(value: Double(min(o.kelime, o.hedef)), in: 0...Double(o.hedef)) {
                Image(systemName: "text.book.closed")
            } currentValueLabel: { Text("\(o.kelime)").font(.system(size: 13, weight: .semibold)) }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
        case .accessoryInline:
            Text("§ \(o.parcalar.filter(\.bitti).count)/5 · \(o.kelime)/\(o.hedef) kelime")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 3) {
                    ForEach(o.parcalar, id: \.no) { p in
                        Capsule().fill(.primary.opacity(p.bitti ? 1 : (p.kelime > 0 ? 0.55 : 0.2))).frame(height: 4)
                    }
                }
                .widgetAccentable()
                Text(o.hamle.cumle).font(.system(size: 13, weight: .medium)).lineLimit(3)
            }
        case .systemSmall:
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    halka(o).frame(width: 46, height: 46)
                    Spacer()
                    Text("§").font(.serif(22, .bold)).foregroundStyle(Color.kalem)
                }
                Spacer(minLength: 0)
                Text(o.hamle.cumle).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.murekkep).lineLimit(4)
            }
        case .systemMedium:
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(o.baslik).font(.serif(15, .semibold)).foregroundStyle(Color.murekkep).lineLimit(2)
                    Spacer(minLength: 0)
                    Text(o.hamle.cumle).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.kalem).lineLimit(3)
                }
                VStack(spacing: 5) {
                    ForEach(o.parcalar, id: \.no) { p in serit(p, kisa: true) }
                }
                .frame(width: 130)
            }
        default:
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TEK METİN").font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(Color.kalem)
                        Text(o.baslik).font(.serif(19, .semibold)).foregroundStyle(Color.murekkep)
                        Text(o.soru).font(.serif(12).italic()).foregroundStyle(Color.soluk).lineLimit(2)
                    }
                    Spacer()
                    halka(o).frame(width: 58, height: 58)
                }
                VStack(spacing: 9) { ForEach(o.parcalar, id: \.no) { p in serit(p, kisa: false) } }
                Spacer(minLength: 0)
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.turn.down.right").foregroundStyle(Color.kalem)
                    Text(o.hamle.cumle).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.murekkep).lineLimit(2)
                    Spacer(minLength: 0)
                    if o.kutu > 0 {
                        Link(destination: URL(string: "kenar://kutu")!) {
                            Label("\(o.kutu)", systemImage: "tray").font(.caption.weight(.bold)).foregroundStyle(Color.soluk)
                        }
                    }
                }
            }
        }
    }

    private func halka(_ o: WidgetOzet) -> some View {
        ZStack {
            Circle().stroke(Color.cizgi, lineWidth: 5)
            Circle().trim(from: 0, to: min(1, Double(o.kelime) / Double(max(1, o.hedef)))).stroke(Color.kalem, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
            Text("\(o.kelime)").font(.system(size: 13, weight: .bold, design: .serif)).foregroundStyle(Color.murekkep).minimumScaleFactor(0.6)
        }
    }

    private func serit(_ p: WidgetOzet.Parca, kisa: Bool) -> some View {
        HStack(spacing: 6) {
            Text("§\(p.no)").font(.system(size: 10, weight: .bold, design: .serif)).foregroundStyle(Color.bolum(p.no)).frame(width: 18, alignment: .leading)
            if !kisa { Text(p.baslik).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.murekkep).lineLimit(1).frame(width: 128, alignment: .leading) }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.cizgi)
                    Capsule().fill(Color.bolum(p.no)).frame(width: max(p.kelime > 0 ? 4 : 0, g.size.width * min(1, Double(p.kelime) / Double(max(1, p.hedef)))))
                }
            }
            .frame(height: 5)
            if p.bitti { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.bolum(p.no)) }
            else { Text("\(p.kanit)").font(.system(size: 9, weight: .semibold).monospacedDigit()).foregroundStyle(Color.soluk).frame(width: 12) }
        }
    }
}

// MARK: Canlı Etkinlik

struct OkumaCanliEtkinligi: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OkumaEtkinligi.self) { c in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(c.attributes.kitapAdi, systemImage: "book.fill").font(.headline).lineLimit(1)
                    Spacer()
                    Text(c.state.baslangic, style: .timer).font(.system(.title3, design: .serif).weight(.semibold)).monospacedDigit().frame(width: 80, alignment: .trailing)
                }
                Text(c.attributes.soru).font(.serif(14).italic()).foregroundStyle(.secondary).lineLimit(2)
                HStack {
                    Label("\(c.state.isaret) işaret", systemImage: "bookmark.fill").font(.caption.weight(.semibold))
                    Spacer()
                    Button(intent: KamerayaIsaretNiyeti()) { Label("İşaretle", systemImage: "camera.viewfinder") }.tint(Color.kalem)
                    Button(intent: OturumuBitirNiyeti()) { Label("Bitir", systemImage: "stop.fill") }.tint(.gray)
                }
                .font(.caption.weight(.semibold))
            }
            .padding(14)
            .activityBackgroundTint(Color.kagit)
            .activitySystemActionForegroundColor(Color.kalem)
            .widgetURL(URL(string: "kenar://oku"))
        } dynamicIsland: { c in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Label(c.attributes.kitapAdi, systemImage: "book.fill").font(.caption).lineLimit(1) }
                DynamicIslandExpandedRegion(.trailing) { Text(c.state.baslangic, style: .timer).monospacedDigit().frame(width: 60) }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(c.attributes.soru).font(.caption.italic()).lineLimit(2)
                }
            } compactLeading: { Image(systemName: "book.fill").foregroundStyle(Color.kalem) }
              compactTrailing: { Text("\(c.state.isaret)").monospacedDigit() }
              minimal: { Image(systemName: "book.fill") }
            .widgetURL(URL(string: "kenar://oku"))
        }
    }
}

// MARK: denetimler

struct OkumaDenetimi: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.fatihgocgun.kenar.oku") {
            ControlWidgetButton(action: OkumayaBaslaNiyeti()) { Label("Okumaya başla", systemImage: "book") }.tint(Color.kalem)
        }
        .displayName("Okumaya başla")
        .description("Kenar: soru yaz, oturumu aç.")
    }
}

struct KameraDenetimi: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.fatihgocgun.kenar.kamera") {
            ControlWidgetButton(action: KamerayaIsaretNiyeti()) { Label("Kamerayla işaretle", systemImage: "camera.viewfinder") }.tint(Color.kalem)
        }
        .displayName("Kamerayla işaretle")
        .description("Kâğıt kitaptaki cümleyi seç.")
    }
}

struct AnlatDenetimi: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.fatihgocgun.kenar.anlat") {
            ControlWidgetButton(action: AnlatNiyeti()) { Label("Feynman dakikası", systemImage: "waveform") }.tint(Color.kalem)
        }
        .displayName("Feynman dakikası")
        .description("Kitabı kapat, 60 saniye anlat.")
    }
}
