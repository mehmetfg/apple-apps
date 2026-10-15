// Tek widget, her boyda: tasarımı uygulamada kurarsın, widget'ı düzenlerken "Tasarım" listesinden seçersin (Widgetsmith usulü).
import WidgetKit
import SwiftUI
import AppIntents

struct TasarimVarligi: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Tasarım"
    static var defaultQuery = TasarimSorgusu()
    var id: String
    var ad: String
    var tur: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(ad)", subtitle: "\(tur)") }
}

struct TasarimSorgusu: EntityQuery {
    private func hepsi() -> [TasarimVarligi] {
        (Depo.tasarimOku() ?? Varsayilan.tasarimlar()).widgetlar.map {
            TasarimVarligi(id: $0.id.uuidString, ad: $0.ad, tur: $0.icerik.ad)
        }
    }
    func entities(for ids: [String]) async throws -> [TasarimVarligi] { hepsi().filter { ids.contains($0.id) } }
    func suggestedEntities() async throws -> [TasarimVarligi] { hepsi() }
    func defaultResult() async -> TasarimVarligi? { hepsi().first }
}

struct SecimNiyeti: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Vitrin"
    static var description = IntentDescription("Uygulamada kurduğun bir tasarımı seç.")
    @Parameter(title: "Tasarım") var tasarim: TasarimVarligi?
}

struct Kayit: TimelineEntry {
    let date: Date
    let tasarim: WidgetTasarim
    let g: Gosterilen
    let cevrik: Bool
    let veri: VitrinVeri
    let bilinen: Set<String>
}

struct Saglayici: AppIntentTimelineProvider {
    private func kur(_ niyet: SecimNiyeti?, tarih: Date, ileri: Int? = nil) -> Kayit {
        let kayit = Depo.tasarimOku() ?? Varsayilan.tasarimlar()
        let veri = Depo.veriOku() ?? .bos
        let t = kayit.widgetlar.first { $0.id.uuidString == niyet?.tasarim?.id } ?? kayit.widgetlar.first
            ?? Tema.hepsi[0].widgetlar()[0]
        let bilinen = Set(kayit.bilinen)
        let adim = Secici.dilim(tarih, dongu: t.dongu) + (ileri ?? Depo.ileri(t.id))
        let g = Gosterilen.hesapla(t.icerik, veri: veri, tarih: tarih, adim: adim, bilinen: bilinen, metin: t.metin)
        return Kayit(date: tarih, tasarim: t, g: g, cevrik: Depo.cevrik(t.id), veri: veri, bilinen: bilinen)
    }

    func placeholder(in context: Context) -> Kayit { kur(nil, tarih: .now, ileri: 0) }
    func snapshot(for configuration: SecimNiyeti, in context: Context) async -> Kayit { kur(configuration, tarih: .now) }

    func timeline(for configuration: SecimNiyeti, in context: Context) async -> Timeline<Kayit> {
        let simdi = Date.now
        let ilk = kur(configuration, tarih: simdi)
        let dongu = max(15, ilk.tasarim.dongu)
        // Sonraki dilim sınırlarından başlayarak 12 saatlik akış; gece yarısında gün değişir
        var kayitlar = [ilk]
        let bas = Calendar.current.startOfDay(for: simdi)
        var dilim = Secici.dilim(simdi, dongu: dongu) + 1
        while kayitlar.count < 40 {
            let t = bas.addingTimeInterval(Double(dilim * dongu * 60))
            if t.timeIntervalSince(simdi) > 12 * 3600 { break }
            kayitlar.append(kur(configuration, tarih: t))
            dilim += 1
        }
        let gece = Calendar.current.date(byAdding: .day, value: 1, to: bas) ?? simdi.addingTimeInterval(86400)
        if !kayitlar.contains(where: { $0.date == gece }), gece.timeIntervalSince(simdi) < 12 * 3600 {
            kayitlar.append(kur(configuration, tarih: gece, ileri: 0))
            kayitlar.sort { $0.date < $1.date }
        }
        return Timeline(entries: kayitlar, policy: .atEnd)
    }
}

struct VitrinWidgetGorunumu: View {
    @Environment(\.widgetFamily) var aile
    var k: Kayit

    var body: some View {
        WidgetGorunum(t: k.tasarim, g: k.g, aile: aile, tarih: k.date, cevrik: k.cevrik, veri: k.veri, bilinen: k.bilinen)
            .widgetURL(URL(string: "vitrin://widget/\(k.tasarim.id.uuidString)"))
            .containerBackground(for: .widget) {
                ZeminGorunum(zemin: k.tasarim.zemin, fotoBoyu: aile == .systemSmall ? 520 : 1000)
            }
    }
}

struct VitrinWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Depo.widgetTuru, intent: SecimNiyeti.self, provider: Saglayici()) { k in
            VitrinWidgetGorunumu(k: k)
        }
        .configurationDisplayName("Vitrin")
        .description("Uygulamada kurduğun tasarım: kelime, alıntı, kavram, günün işi, saat, takvim, geri sayım.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct VitrinWidgetPaketi: WidgetBundle {
    var body: some Widget { VitrinWidget() }
}
