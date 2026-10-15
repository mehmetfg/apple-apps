// GramerApp widget'ı: bugünün konusu. Küçük: konu + yasa · Orta: formül + tuzak · Kilit ekranı: konu + formül.
// Veri uygulamanın App Group'a yazdığı tek JSON'dan gelir; uygulama hiç açılmadıysa örnek konu görünür.
import WidgetKit
import SwiftUI

struct Giris: TimelineEntry {
    let date: Date
    let v: WidgetVerisi
}

struct Saglayici: TimelineProvider {
    func placeholder(in context: Context) -> Giris { Giris(date: .now, v: .ornek) }
    func getSnapshot(in context: Context, completion: @escaping (Giris) -> Void) {
        completion(Giris(date: .now, v: WidgetVerisi.oku() ?? .ornek))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Giris>) -> Void) {
        let yarin = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400))
        completion(Timeline(entries: [Giris(date: .now, v: WidgetVerisi.oku() ?? .ornek)], policy: .after(yarin)))
    }
}

struct DisliGorunum: View {
    @Environment(\.widgetFamily) private var aile
    let g: Giris
    private var renk: Color { Tema.renk(g.v.renk) }
    private var yasa: String { g.v.yasaId ?? "" }

    var body: some View {
        switch aile {
        case .accessoryRectangular:
            HStack(spacing: 6) {
                Cizim(ad: yasa, renk: .primary, boy: 26, zemin: false)
                VStack(alignment: .leading, spacing: 1) {
                    Text(g.v.tr).font(.headline).lineLimit(1)
                    Text(g.v.formul).font(.caption2).lineLimit(2)
                }
            }
        case .accessoryInline:
            Text(g.v.tr)
        case .systemMedium:
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bugünün konusu").font(.caption2.weight(.bold)).foregroundStyle(renk)
                    Text(g.v.tr).font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(.primary).lineLimit(2)
                    Text(g.v.formul).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(3)
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        Cizim(ad: yasa, renk: renk, boy: 18, zemin: false)
                        Text(g.v.yasaAd).font(.caption2.weight(.semibold)).foregroundStyle(renk).lineLimit(1)
                    }
                }
                if !g.v.tuzakY.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("✗ " + g.v.tuzakY).font(.system(.caption, design: .serif)).strikethrough().foregroundStyle(.secondary)
                        Text("✓ " + g.v.tuzakD).font(.system(.caption, design: .serif).weight(.semibold)).foregroundStyle(.primary)
                    }
                    .padding(10)
                    .frame(maxWidth: 150, maxHeight: .infinity, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Tema.yuzey.opacity(0.75)))
                }
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                Cizim(ad: yasa, renk: renk, boy: 40)
                Spacer(minLength: 0)
                Text(g.v.tr).font(.system(.headline, design: .rounded).weight(.bold)).foregroundStyle(.primary).lineLimit(3)
                Text(g.v.ad).font(.system(.caption2, design: .serif).italic()).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct DisliWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DisliGunun", provider: Saglayici()) { g in
            DisliGorunum(g: g)
                .containerBackground(for: .widget) {
                    ZStack {
                        Tema.kagit
                        LinearGradient(colors: [Tema.renk(g.v.renk).opacity(0.22), Tema.renk(g.v.renk).opacity(0.06)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
                .widgetURL(URL(string: "disli://konu/\(g.v.id)"))
        }
        .configurationDisplayName("Bugünün konusu")
        .description("GramerApp: bugünün gramer konusu, kalıbı ve Türk konuşurun tuzağı.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct DisliWidgetPaketi: WidgetBundle {
    var body: some Widget { DisliWidget() }
}
