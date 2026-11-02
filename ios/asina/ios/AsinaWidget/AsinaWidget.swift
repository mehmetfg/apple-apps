// VocuTeach (eski Aşina) widget'ları — gün boyu göz ucuyla karşılaşma.
//  Cümle (kilit ekranı · küçük · orta · büyük): Cümle Tezgâhı'nın günün 6 kelimesi 3 dakikada bir döner —
//    telefona her bakışta başka kelime; İngilizce tanım + Türkçe + Tezgâh cümlesi.
//  Kelime (küçük · orta · büyük · kilit ekranı): bugünün kelimeleri 3 dakikada bir döner (Cümle kelimeleri araya karışır);
//    orta boyda "göz" (önce hatırla) ve "sonraki" düğmeleri var.
//  İlerleme (küçük · kilit ekranı yuvarlak): günün halkası + seri.
import WidgetKit
import SwiftUI
import AppIntents

/// Kelime değişme aralığı: telefona her bakışta büyük ihtimalle başka kelime.
let adim: TimeInterval = 3 * 60

struct CumleSaglayici: TimelineProvider {
    func placeholder(in c: Context) -> CumleGiris { ornek }
    func getSnapshot(in c: Context, completion: @escaping (CumleGiris) -> Void) {
        let e = girisler(Date(), adet: 1)
        completion(c.isPreview || e.first?.kelime == nil ? ornek : e[0])
    }

    func getTimeline(in c: Context, completion: @escaping (Timeline<CumleGiris>) -> Void) {
        let e = girisler(Date(), adet: 160)
        let yarin = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400 + 60)
        let son = e.last?.date.addingTimeInterval(adim) ?? yarin
        completion(Timeline(entries: e, policy: .after(min(son, yarin))))
    }

    private var ornek: CumleGiris {
        let l = Anlik.ornek.kelimeler()
        return CumleGiris(date: Date(), kelime: l.first, liste: l, gun: 23, baslik: "The Interview")
    }

    private func girisler(_ bas: Date, adet: Int) -> [CumleGiris] {
        let a = Paylasim.oku()
        let l = a?.cumle ?? []
        guard !l.isEmpty else { return [CumleGiris(date: bas, kelime: nil, liste: [], gun: nil, baslik: nil)] }
        let sira = Paylasim.ayar.integer(forKey: Paylasim.cumleSiraAnahtari)
        return (0..<adet).map { i in
            let n = ((sira + i) % l.count + l.count) % l.count
            return CumleGiris(date: bas.addingTimeInterval(Double(i) * adim), kelime: l[n], liste: l,
                              gun: a?.cumleGun, baslik: a?.cumleBaslik)
        }
    }
}

struct CumleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Paylasim.cumleTuru, provider: CumleSaglayici()) { g in
            CumleGorunumu(g: g).containerBackground(for: .widget) { CumleZemini() }
        }
        .configurationDisplayName("Cümle Tezgâhı kelimeleri")
        .description("Günün 6 yeni kelimesi: İngilizce tanım, Türkçe karşılık ve Tezgâh cümlesi. Her bakışta başka kelime.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .systemSmall, .systemMedium, .systemLarge])
    }
}

struct KelimeSaglayici: TimelineProvider {
    func placeholder(in c: Context) -> Giris { ornek }
    func getSnapshot(in c: Context, completion: @escaping (Giris) -> Void) {
        completion(Paylasim.oku() == nil || c.isPreview ? ornek : girisler(Date(), adet: 1)[0])
    }

    func getTimeline(in c: Context, completion: @escaping (Timeline<Giris>) -> Void) {
        let e = girisler(Date(), adet: 160)
        // Gece yarısı yeni günün listesine geçmek için de yenile.
        let yarin = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400 + 60)
        let son = e.last?.date.addingTimeInterval(adim) ?? yarin
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
            let an = bas.addingTimeInterval(Double(i) * adim)
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
        .description("Bugünün kelimeleri gün boyu döner. Önce hatırla kipi VocuTeach ayarlarında.")
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
        CumleWidget()
        KelimeWidget()
        IlerlemeWidget()
    }
}
