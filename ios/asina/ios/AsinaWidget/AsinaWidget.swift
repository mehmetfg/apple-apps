// Aşina widget'ları — gün boyu göz ucuyla karşılaşma.
//  Kelime (küçük · orta · büyük · kilit ekranı): bugünün kelimeleri 20 dakikada bir döner;
//    orta boyda "göz" (önce hatırla) ve "sonraki" düğmeleri var.
//  İlerleme (küçük · kilit ekranı yuvarlak): günün halkası + seri.
import WidgetKit
import SwiftUI
import AppIntents

struct KelimeSaglayici: TimelineProvider {
    func placeholder(in c: Context) -> Giris { ornek }
    func getSnapshot(in c: Context, completion: @escaping (Giris) -> Void) {
        completion(Paylasim.oku() == nil || c.isPreview ? ornek : girisler(Date(), adet: 1)[0])
    }

    func getTimeline(in c: Context, completion: @escaping (Timeline<Giris>) -> Void) {
        let e = girisler(Date(), adet: 36)
        // Gece yarısı yeni günün listesine geçmek için de yenile.
        let yarin = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400 + 60)
        let son = e.last?.date.addingTimeInterval(20 * 60) ?? yarin
        completion(Timeline(entries: e, policy: .after(min(son, yarin))))
    }

    private var ornek: Giris {
        let a = Anlik.ornek
        let l = a.kelimeler()
        return Giris(date: Date(), kelime: l.first, sonrakiler: Array(l.dropFirst()), anlik: a, acik: true, onceHatirla: false)
    }

    private func girisler(_ bas: Date, adet: Int) -> [Giris] {
        let a = Paylasim.oku()
        let ayar = Paylasim.ayar
        let sira = ayar.integer(forKey: Paylasim.siraAnahtari)
        let acik = ayar.bool(forKey: Paylasim.acikAnahtari)
        let hatirla = ayar.bool(forKey: Paylasim.hatirlaAnahtari)
        guard let a else {
            return [Giris(date: bas, kelime: nil, sonrakiler: [], anlik: nil, acik: true, onceHatirla: false)]
        }
        return (0..<adet).map { i in
            let an = bas.addingTimeInterval(Double(i) * 20 * 60)
            let l = a.kelimeler(an)
            guard !l.isEmpty else {
                return Giris(date: an, kelime: nil, sonrakiler: [], anlik: a, acik: true, onceHatirla: hatirla)
            }
            let n = ((sira + i) % l.count + l.count) % l.count
            let sonra = (1...min(3, max(1, l.count - 1))).map { l[(n + $0) % l.count] }
            // Düğmeyle açılan anlam yalnız o anki girişte açık kalır.
            return Giris(date: an, kelime: l[n], sonrakiler: sonra, anlik: a, acik: i == 0 ? acik : false,
                         onceHatirla: hatirla)
        }
    }
}

// MARK: Kelime widget'ı

struct KelimeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Paylasim.widgetTuru, provider: KelimeSaglayici()) { g in
            KelimeGorunumu(g: g)
                .containerBackground(for: .widget) {
                    KelimeZemini(c: g.kelime?.c ?? "", pv: g.kelime?.pv ?? false,
                                 harf: String((g.kelime?.w.first).map(String.init) ?? "").uppercased())
                }
        }
        .configurationDisplayName("Günün kelimeleri")
        .description("Bugünün kelimeleri gün boyu döner. Önce hatırla kipi Aşina ayarlarında.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

// MARK: İlerleme widget'ı

struct IlerlemeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Paylasim.ilerlemeTuru, provider: KelimeSaglayici()) { g in
            IlerlemeGorunumu(a: g.anlik)
                .containerBackground(for: .widget) { IlerlemeZemini() }
        }
        .configurationDisplayName("Bugünün halkası")
        .description("Günün destesi, seri ve son yedi gün.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

@main
struct AsinaWidgetPaketi: WidgetBundle {
    var body: some Widget {
        KelimeWidget()
        IlerlemeWidget()
    }
}
