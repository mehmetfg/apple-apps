// Ayna widget'ı: dünden bir hatan ve doğrusu — kilit ekranında, her bakışta ikinci karşılaşma. Dokun: sabah dinlemesi.
import SwiftUI
import WidgetKit

@main
struct AynaWidgetleri: WidgetBundle {
    var body: some Widget { HataWidget() }
}

struct Anlik: TimelineEntry { let date: Date; let o: WidgetOzet? }

struct Saglayici: TimelineProvider {
    func placeholder(in context: Context) -> Anlik { Anlik(date: .now, o: .ornek) }
    func getSnapshot(in context: Context, completion: @escaping (Anlik) -> Void) { completion(Anlik(date: .now, o: Depo.ozet ?? (context.isPreview ? .ornek : nil))) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Anlik>) -> Void) {
        completion(Timeline(entries: [Anlik(date: .now, o: Depo.ozet)], policy: .after(.now.addingTimeInterval(3600))))
    }
}

struct HataWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.fatihgocgun.ayna.hata", provider: Saglayici()) { a in
            Gorunum(a: a).containerBackground(for: .widget) { Zemin() }.widgetURL(URL(string: "ayna://dinle"))
        }
        .configurationDisplayName("Dünkü cümlen")
        .description("Kendi anlatımından bir hata ve doğrusu.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct Zemin: View {
    @Environment(\.widgetRenderingMode) var kip
    var body: some View {
        if kip == .fullColor { LinearGradient(colors: [Color(red: 0.07, green: 0.10, blue: 0.16), Color(red: 0.03, green: 0.05, blue: 0.08)], startPoint: .top, endPoint: .bottom) } else { Color.clear }
    }
}

struct Gorunum: View {
    @Environment(\.widgetFamily) var aile
    let a: Anlik
    private let mavi = Color(red: 0.45, green: 0.78, blue: 0.95)

    var body: some View {
        if let o = a.o, !o.dogru.isEmpty {
            switch aile {
            case .accessoryInline: Text("✓ \(o.dogru)")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text(o.yanlis).font(.system(size: 12)).strikethrough().opacity(0.7).lineLimit(1)
                    Text(o.dogru).font(.system(size: 14, weight: .semibold)).lineLimit(2).widgetAccentable()
                }
            default:
                VStack(alignment: .leading, spacing: 6) {
                    Label("Dün dedin", systemImage: "person.wave.2").font(.caption2.weight(.bold)).foregroundStyle(mavi)
                    Text(o.yanlis).font(.system(size: 13)).strikethrough().foregroundStyle(.white.opacity(0.55)).lineLimit(2)
                    Text(o.dogru).font(.system(size: aile == .systemSmall ? 15 : 17, weight: .semibold)).foregroundStyle(.white).lineLimit(3)
                    Spacer(minLength: 0)
                    if aile == .systemMedium { Text(o.kural).font(.caption).foregroundStyle(mavi).lineLimit(1) }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "person.wave.2").foregroundStyle(mavi)
                Text("Bu akşam gününü İngilizce anlat.").font(.system(size: 13, weight: .medium)).foregroundStyle(aile == .accessoryRectangular ? .primary : Color.white)
            }
        }
    }
}
