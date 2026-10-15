// Sınama yardımcıları (yalnız DEBUG). Simülatörde:
//   -widgetPNG          widget'ın bütün boylarını Documents/onizleme/*.png olarak çizer (açık + koyu) ve çıkar
//   -sekme <0…4>        uygulamayı o sekmede açar        -surec <id>  süreç ayrıntısını açar
//   -hacim              Partisyon › Hacim ekranını açar
//   ORKESTRA_SIMDI=...  motoru başka bir ânda çalıştırır (ör. 2026-10-12T09:30:00)
import SwiftUI
import UserNotifications

#if DEBUG
enum Onizleme {
    @MainActor
    static func baslat(_ merkez: Merkez, _ rota: Rota) async {
        let arg = CommandLine.arguments
        if let i = arg.firstIndex(of: "-sekme"), i + 1 < arg.count, let n = Int(arg[i + 1]) { rota.sekme = n }
        if let i = arg.firstIndex(of: "-surec"), i + 1 < arg.count {
            try? await Task.sleep(for: .seconds(1.5))
            rota.surec = arg[i + 1]
        }
        if arg.contains("-hacim") {
            try? await Task.sleep(for: .seconds(1.5))
            rota.sekme = 3; rota.hacim = true
        }
        if arg.contains("-bildirimDokum") {
            // bildirim mantığını sına: tazele → olayları işle → kurulan/teslim edilen bildirimleri yaz
            if arg.contains("-sifirla") { Depo.bildirilen = [:] }
            await merkez.tazele(bildir: true)
            if let d = merkez.durum {
                for h in d.hukumler { print("HÜKÜM  \(h.id)  \(h.durum.rawValue)  sessiz=\(h.sessizlik ?? -1)  \(h.neden.prefix(70))") }
                for h in d.hamleler { print("HAMLE  \(Int(h.skor))  \(h.tur.rawValue)  \(h.baslik)") }
            }
            let m = UNUserNotificationCenter.current()
            let f = DateFormatter(); f.dateFormat = "dd.MM HH:mm"
            for r in await m.pendingNotificationRequests().sorted(by: { $0.identifier < $1.identifier }) {
                let an = (r.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate().map(f.string) ?? "hemen"
                print("KURULU  \(an)  \(r.identifier)  | \(r.content.title) — \(r.content.body.prefix(90))")
            }
            for n in await m.deliveredNotifications() {
                print("GELDİ   \(n.request.identifier)  | \(n.request.content.title) — \(n.request.content.body.prefix(90))")
            }
            print("BİLDİRİLEN \(Depo.bildirilen.count) kayıt")
            exit(0)
        }
        guard arg.contains("-widgetPNG") else { return }
        await merkez.tazele(bildir: false)
        guard let d = merkez.durum else { print("onizleme: veri yok"); return }
        let klasor = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("onizleme")
        try? FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
        let boylar: [(String, WBoy, CGSize)] = [("buyuk", .buyuk, CGSize(width: 364, height: 382)),
                                                ("orta", .orta, CGSize(width: 364, height: 170)),
                                                ("kucuk", .kucuk, CGSize(width: 170, height: 170)),
                                                ("dikdortgen", .dikdortgen, CGSize(width: 172, height: 76)),
                                                ("daire", .daire, CGSize(width: 76, height: 76))]
        for (ad, boy, olcu) in boylar {
            let g = ZStack {
                if boy == .buyuk || boy == .orta || boy == .kucuk { WidgetArkaPlan(nabiz: d.nabiz) } else { Color(white: 0.1) }
                OrkestraWidgetGorunumu(d: d, boy: boy).padding(16)
            }
            .frame(width: olcu.width, height: olcu.height)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .environment(\.colorScheme, .dark)
            let r = ImageRenderer(content: g)
            r.scale = 3
            if let img = r.uiImage, let png = img.pngData() {
                try? png.write(to: klasor.appendingPathComponent("\(ad)-koyu.png"))
            }
        }
        print("onizleme: \(klasor.path)")
        exit(0)
    }
}
#endif
