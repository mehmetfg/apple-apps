// Widget'lar. Uygulamanın yazdığı anlık görüntüyü (widget.json) okur, hesap yapmaz.
//   · Ön çalışma   : paket adı, ① adımları, anahtar cümle; dokun → dinlemeye başla.
//   · Dünün cümlen : önce Türkçesi; İngilizcesi gizli, "Göster" ile açılır (önce hatırla).
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

// MARK: - Ön çalışma

struct AdimNoktalari: View {
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
            .foregroundStyle(dolu ? .white : r)
            .frame(width: 22, height: 22)
            .background(Circle().fill(dolu ? r : r.opacity(0.15)))
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
                    Text(a?.gun.map { "GÜN \($0)" } ?? "MEMORIES").font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    Image(systemName: "play.circle.fill").font(.title3).foregroundStyle(.white)
                }
                Spacer(minLength: 0)
                Text(a?.baslik ?? "Paket bekleniyor").font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.8)
                if let s = a?.sure { Text(Tarih.dakika(s)).font(.caption).foregroundStyle(.white.opacity(0.85)) }
                AdimNoktalari(adim: a?.adim)
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(a?.gun.map { "GÜN \($0) · ÖN ÇALIŞMA" } ?? "MEMORIES").font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    AdimNoktalari(adim: a?.adim)
                }
                Text(a?.baslik ?? "Paket bekleniyor").font(.system(.title2, design: .serif).weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                if let k = a?.anahtar {
                    Text(k).font(.system(.callout, design: .serif)).foregroundStyle(.white.opacity(0.92)).lineLimit(2)
                } else if let o = a?.ozet {
                    Text(o).font(.caption).foregroundStyle(.white.opacity(0.9)).lineLimit(2)
                }
                Spacer(minLength: 0)
                HStack {
                    Label(a?.sure.map { Tarih.dakika($0) } ?? "—", systemImage: "headphones").font(.caption.weight(.semibold))
                    Spacer()
                    Label("Dinle", systemImage: "play.fill").font(.caption.weight(.bold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(.white)).foregroundStyle(Tema.vurguKoyu)
                }
                .foregroundStyle(.white)
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
                .containerBackground(for: .widget) { Tema.egim }
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
                            .font(.caption2.weight(.bold)).foregroundStyle(Tema.kehribar)
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
                Label("Dünün cümlen", systemImage: "sparkles").font(.caption.weight(.bold)).foregroundStyle(Tema.kehribar)
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
                .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("Dünün cümlen")
        .description("Önce Türkçesi; İngilizcesini kafanda kur, sonra aç.")
        .supportedFamilies([.systemMedium, .accessoryRectangular])
    }
}

@main
struct MemoriesWidgetBundle: WidgetBundle {
    var body: some Widget {
        OnCalismaWidget()
        DunWidget()
    }
}
