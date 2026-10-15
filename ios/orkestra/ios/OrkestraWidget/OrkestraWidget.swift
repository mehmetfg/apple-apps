// Orkestra widget'ı — uygulamanın App Group'a yazdığı orkestra.json'u okur, motoru her saat için yeniden çalıştırır:
// telefona dokunulmasa da saat ilerledikçe "gecikti"ler doğru anda görünür.
import SwiftUI
import WidgetKit

struct Giris: TimelineEntry {
    var date: Date
    var durum: Durumlar?
}

struct Saglayici: TimelineProvider {
    func placeholder(in context: Context) -> Giris { Giris(date: .now, durum: hesap(.now)) }

    func getSnapshot(in context: Context, completion: @escaping (Giris) -> Void) {
        completion(Giris(date: .now, durum: hesap(.now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Giris>) -> Void) {
        let t = Tarih.takvim
        let simdi = Date.now
        let saatBasi = t.date(bySettingHour: t.component(.hour, from: simdi), minute: 0, second: 0, of: simdi) ?? simdi
        var girisler = [Giris(date: simdi, durum: hesap(simdi))]
        for i in 1...12 {
            let an = saatBasi.addingTimeInterval(Double(i) * 3600)
            girisler.append(Giris(date: an, durum: hesap(an)))
        }
        completion(Timeline(entries: girisler, policy: .after(simdi.addingTimeInterval(3600))))
    }

    func hesap(_ an: Date) -> Durumlar? {
        guard let v = Depo.veriOku() else { return nil }
        return Motor.hesapla(v, simdi: an, ertelenen: Depo.ertelenenler(an))
    }
}

struct OrkestraWidgetGirisi: View {
    @Environment(\.widgetFamily) var aile
    var giris: Giris

    var body: some View {
        OrkestraWidgetGorunumu(d: giris.durum, boy: boy)
            .containerBackground(for: .widget) {
                if aile == .systemLarge || aile == .systemMedium || aile == .systemSmall {
                    WidgetArkaPlan(nabiz: giris.durum?.nabiz ?? 50)
                } else {
                    Color.clear
                }
            }
            .widgetURL(URL(string: "orkestra://bugun"))
    }

    var boy: WBoy {
        switch aile {
        case .systemSmall: .kucuk
        case .systemMedium: .orta
        case .accessoryCircular: .daire
        case .accessoryRectangular: .dikdortgen
        case .accessoryInline: .satir
        default: .buyuk
        }
    }
}

@main
struct OrkestraWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OrkestraWidget", provider: Saglayici()) { OrkestraWidgetGirisi(giris: $0) }
            .configurationDisplayName("Orkestra")
            .description("Bütün süreçlerin nabzı, aksayanlar ve bugünün sırası.")
            .supportedFamilies([.systemLarge, .systemMedium, .systemSmall,
                                .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
