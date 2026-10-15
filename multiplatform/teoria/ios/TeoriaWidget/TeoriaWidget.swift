// Teoria widget paketi: dört widget (her boyut) + iki Denetim Merkezi düğmesi.
//  · Aforizma  — dönen aforizmalar ve kendi işaretlerin, kaynağıyla; ♥ ve → düğmeleri
//  · Hatırla   — önce hatırla, sonra bak; Hatırladım / Bilemedim
//  · Okuma     — süren kitapların ilerlemesi: halka, çubuk, haftalık işaret grafiği
//  · Kür       — bugünün halkası, üç hattın kademesi, hafta, kavram gökyüzü
import WidgetKit
import SwiftUI
import AppIntents

struct Giris: TimelineEntry {
    let date: Date
    let anlik: WidgetAnlik
    var sira: Int = 0
    var acik: Bool = false
}

private func anlik() -> WidgetAnlik { Paylasim.oku() ?? .ornek }

// MARK: - Sağlayıcılar

struct AforizmaSaglayici: TimelineProvider {
    func placeholder(in context: Context) -> Giris { Giris(date: Date(), anlik: .ornek) }
    func getSnapshot(in context: Context, completion: @escaping (Giris) -> Void) {
        completion(Giris(date: Date(), anlik: context.isPreview ? .ornek : anlik(), sira: Paylasim.ayar.integer(forKey: Paylasim.afoSira)))
    }
    /// 12 saat boyunca yarım saatte bir yeni aforizma; uygulama açılmasa da döner.
    func getTimeline(in context: Context, completion: @escaping (Timeline<Giris>) -> Void) {
        let a = anlik(), bas = Paylasim.ayar.integer(forKey: Paylasim.afoSira), simdi = Date()
        let girisler = (0..<24).map { i in Giris(date: simdi.addingTimeInterval(Double(i) * 1800), anlik: a, sira: bas + i) }
        completion(Timeline(entries: girisler, policy: .atEnd))
    }
}

struct HatirlaSaglayici: TimelineProvider {
    func placeholder(in context: Context) -> Giris { Giris(date: Date(), anlik: .ornek) }
    func getSnapshot(in context: Context, completion: @escaping (Giris) -> Void) {
        completion(Giris(date: Date(), anlik: context.isPreview ? .ornek : anlik(), sira: Paylasim.ayar.integer(forKey: Paylasim.hatSira)))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Giris>) -> Void) {
        let a = Paylasim.ayar
        let g = Giris(date: Date(), anlik: anlik(), sira: a.integer(forKey: Paylasim.hatSira), acik: a.bool(forKey: Paylasim.hatAcik))
        completion(Timeline(entries: [g], policy: .after(Date().addingTimeInterval(3600))))
    }
}

struct DuzSaglayici: TimelineProvider {
    var aralik: TimeInterval = 3600
    func placeholder(in context: Context) -> Giris { Giris(date: Date(), anlik: .ornek) }
    func getSnapshot(in context: Context, completion: @escaping (Giris) -> Void) {
        completion(Giris(date: Date(), anlik: context.isPreview ? .ornek : anlik()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Giris>) -> Void) {
        // Gece yarısında halka sıfırlansın diye yarın 00:01'de de yenilenir.
        let yarin = Date().gunBasi.gun(1).addingTimeInterval(60)
        let sonraki = min(Date().addingTimeInterval(aralik), yarin)
        completion(Timeline(entries: [Giris(date: Date(), anlik: anlik())], policy: .after(sonraki)))
    }
}

// MARK: - Zemin

private struct Zemin: ViewModifier {
    let renk: Color
    @Environment(\.widgetFamily) private var aile
    func body(content: Content) -> some View {
        switch aile {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            content.containerBackground(for: .widget) { Color.clear }
        default:
            content.containerBackground(for: .widget) { WZemin(renk: renk) }
        }
    }
}

// MARK: - Widget'lar

struct AforizmaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Paylasim.aforizmaTuru, provider: AforizmaSaglayici()) { g in
            AforizmaWidgetGorunum(anlik: g.anlik, sira: g.sira)
                .modifier(Zemin(renk: AforizmaWidgetGorunum.renk(g.anlik, g.sira)))
                .widgetURL(AforizmaWidgetGorunum.adres(g.anlik, g.sira))
        }
        .configurationDisplayName("Aforizma")
        .description("Dönen aforizmalar ve kendi işaretlerin, kaynağıyla.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
                            .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

struct HatirlaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Paylasim.hatirlaTuru, provider: HatirlaSaglayici()) { g in
            HatirlaWidgetGorunum(anlik: g.anlik, sira: g.sira, acik: g.acik)
                .modifier(Zemin(renk: Tema.hat(.hatirla)))
        }
        .configurationDisplayName("Hatırla")
        .description("Önce hatırla, sonra bak. Cevabın aralıklı tekrara işlenir.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

struct OkumaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Paylasim.okumaTuru, provider: DuzSaglayici(aralik: 7200)) { g in
            OkumaWidgetGorunum(anlik: g.anlik)
                .modifier(Zemin(renk: OkumaWidgetGorunum.renk(g.anlik)))
                .widgetURL(URL(string: "teoria://kitaplar"))
        }
        .configurationDisplayName("Okuma")
        .description("Süren kitapların ilerlemesi ve haftalık işaretlerin.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct KurWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Paylasim.kurTuru, provider: DuzSaglayici(aralik: 3600)) { g in
            KurWidgetGorunum(anlik: g.anlik)
                .modifier(Zemin(renk: Tema.vurgu))
        }
        .configurationDisplayName("Kür")
        .description("Bugünün halkası, merdiven ve kavram gökyüzü. Dokun, kür başlasın.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Denetim Merkezi / Eylem düğmesi (iOS 18+)

@available(iOS 18.0, *)
struct KurKontrol: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "TeoriaKurKontrol") {
            ControlWidgetButton(action: TeoriaAc(.kur)) {
                Label("Kür", systemImage: "circle.dashed.inset.filled")
            }
        }
        .displayName("Teoria kürü")
        .description("Kürü tek dokunuşla başlatır.")
    }
}

@available(iOS 18.0, *)
struct SesKontrol: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "TeoriaSesKontrol") {
            ControlWidgetButton(action: TeoriaAc(.ses)) {
                Label("Sesli not", systemImage: "waveform")
            }
        }
        .displayName("Teoria sesli not")
        .description("Aklındakini kendi sesinle hemen kaydet.")
    }
}

@main
struct TeoriaWidgetPaketi: WidgetBundle {
    var body: some Widget {
        AforizmaWidget()
        HatirlaWidget()
        OkumaWidget()
        KurWidget()
        if #available(iOS 18.0, *) {
            KurKontrol()
            SesKontrol()
        }
    }
}
