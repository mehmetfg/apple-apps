// Ekran önizleyici — uygulama ekranlarını iPhone 6.9" (440×956) ölçüsünde, sahte bir geçmişle çizer.
// Gerçek kayda dokunmaz: TEORIA_KAPSAYICI geçici bir klasör olmalı. zsh mac/ekran.sh
import SwiftUI
import AppKit

@MainActor
func ciz<V: View>(_ v: V, _ ad: String, _ sema: ColorScheme, boy: CGSize = CGSize(width: 440, height: 956)) {
    // Gerçek bir pencerede (ekran dışı) çizer: ScrollView, List, Form da görünür.
    let kok = v.environment(\.colorScheme, sema).environment(\.locale, Dil.tr).preferredColorScheme(sema)
    let h = NSHostingView(rootView: kok)
    h.frame = CGRect(origin: .zero, size: boy)
    let w = NSWindow(contentRect: CGRect(x: -5000, y: -5000, width: boy.width, height: boy.height),
                     styleMask: [.borderless], backing: .buffered, defer: false)
    w.appearance = NSAppearance(named: sema == .dark ? .darkAqua : .aqua)
    w.contentView = h
    w.orderFrontRegardless()
    for _ in 0..<12 { RunLoop.current.run(until: Date().addingTimeInterval(0.05)); h.layoutSubtreeIfNeeded() }
    guard let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds) else { return }
    h.cacheDisplay(in: h.bounds, to: rep)
    w.orderOut(nil)
    let png = rep.representation(using: .png, properties: [:])
    try? png?.write(to: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("\(ad)-\(sema == .dark ? "koyu" : "acik").png"))
}

/// 40 günlük sahte geçmiş: iki günde bir kür, Hatırla kartları, birkaç favori, hatırlatma ve kendi cümle.
func sahteGecmis(_ p: Paket, _ a: Akis) -> [Olay] {
    var o: [Olay] = []
    let kav = p.kavramlar
    for g in stride(from: 40, through: 1, by: -2) {
        let t0 = Date().gunBasi.gun(-g).addingTimeInterval(8.5 * 3600)
        let id = UUID().uuidString
        for i in 0..<6 {
            let k = kav[(g * 3 + i) % 14]
            var x = Olay(tur: .cevap, hedef: "hatirla:\(k.id)", hat: .hatirla, kademe: g > 24 ? 1 : (g > 12 ? 2 : 3),
                         puan: i == 5 ? 0.5 : 1, kurId: id)
            x.t = t0.addingTimeInterval(Double(i) * 40); x.gun = Tarih.gun(x.t); o.append(x)
        }
        for i in 0..<2 {
            var x = Olay(tur: .cevap, hedef: "kur:\(p.cumleler[(g + i) % p.cumleler.count].id)", hat: .kur, kademe: 1, puan: 1, kurId: id)
            x.t = t0.addingTimeInterval(300 + Double(i) * 40); x.gun = Tarih.gun(x.t); o.append(x)
        }
        var k = Olay(tur: .kur, sure: 330, kurId: id); k.t = t0.addingTimeInterval(400); k.gun = Tarih.gun(k.t); o.append(k)
    }
    for i in a.isaretler.prefix(30).enumerated() where i.offset % 4 == 0 { o.append(Olay(tur: .favori, hedef: i.element.id, deger: true)) }
    for i in a.isaretler.prefix(12).enumerated() where i.offset % 5 == 1 { o.append(Olay(tur: .hatirlat, hedef: i.element.id, deger: true)) }
    o.append(Olay(tur: .favori, hedef: "a-2", deger: true))
    var c = Olay(tur: .cevap, hedef: "kur:c-h1:taklit", hat: .kur, kademe: 5, puan: 0.85,
                 metin: "Bir kütüphane, kitapların toplamı değil, birbirine seslenen sorulardan oluşan anlamlı bir bütündür.")
    c.t = Date().addingTimeInterval(-3 * 3600); o.append(c)
    if let i = a.isaretler.sorted(by: { $0.zaman > $1.zaman }).dropFirst(1).first {
        var y = Olay(tur: .kendiCumle, hedef: i.id, metin: "Bu cümle, bilginin sınırını çizerken aslında aklın kendine dönüşünü anlatıyor.", rol: "alinti")
        y.t = Date().addingTimeInterval(-40 * 60); o.append(y)
    }
    return o
}

@main enum Ekran { static func main() { MainActor.assumeIsolated {
    NSApplication.shared.setActivationPolicy(.accessory)
    let kap = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TEORIA_KAPSAYICI"]!)
    let veri = URL(fileURLWithPath: CommandLine.arguments[2])
    let p = try! JSONDecoder().decode(Paket.self, from: Data(contentsOf: veri.appendingPathComponent("kartlar.json")))
    let a = try! JSONDecoder().decode(Akis.self, from: Data(contentsOf: veri.appendingPathComponent("akis.json")))
    try? FileManager.default.createDirectory(at: kap.appendingPathComponent("veri"), withIntermediateDirectories: true)
    try? FileManager.default.copyItem(at: veri.appendingPathComponent("kartlar.json"), to: kap.appendingPathComponent("veri/kartlar.json"))
    try? FileManager.default.copyItem(at: veri.appendingPathComponent("akis.json"), to: kap.appendingPathComponent("veri/akis.json"))
    try! Gunluk.yaz(sahteGecmis(p, a), kap.appendingPathComponent("ilerleme/\(Cihaz.ad).jsonl"))
    let depo = Depo()
    print("olay:", depo.olaylar.count, "kür:", depo.durum.kurlar.count, "Hatırla K\(depo.durum.kademe(.hatirla))")
    for s in [ColorScheme.light, .dark] {
        ciz(BugunEkrani(kurBaslat: { _ in }, sesAc: { _ in }).environmentObject(depo).background(Tema.arka), "e-bugun", s, boy: CGSize(width: 440, height: 1900))
        ciz(AkisEkrani(sesAc: { _ in }).environmentObject(depo), "e-akis", s)
        ciz(KitaplarEkrani(sesAc: { _ in }).environmentObject(depo), "e-kitaplar", s)
        ciz(KurEkrani(dakika: 5, kapat: {}).environmentObject(depo), "e-kur", s)
        ciz(KitaplarEkrani(sesAc: { _ in }, ilkSekme: .sozluk).environmentObject(depo), "e-sozluk", s)
        if let i = a.isaretler.first { ciz(AlintiSayfasi(hedef: AlintiHedefi(isaret: i, rol: "alinti")).environmentObject(depo), "e-alinti", s) }
        let mac = CGSize(width: 1480, height: 900)
        ciz(BugunEkrani(kurBaslat: { _ in }, sesAc: { _ in }, genis: true).environmentObject(depo).background(Tema.arka), "m-bugun", s, boy: mac)
        ciz(AtolyeEkrani().environmentObject(depo), "m-atolye", s, boy: mac)
        ciz(AtolyeEkrani(ilk: .anahtar).environmentObject(depo), "m-atolye-anahtar", s, boy: mac)
        ciz(AtolyeEkrani(ilk: .concept).environmentObject(depo), "m-atolye-concept", s, boy: mac)
        ciz(MacAkis(secili: .constant(a.isaretler.sorted { $0.zaman > $1.zaman }.first), sesAc: { _ in }).environmentObject(depo).background(Tema.arka), "m-akis", s, boy: mac)
        ciz(SozlukEkrani(genis: true).environmentObject(depo).background(Tema.arka), "m-sozluk", s, boy: mac)
        ciz(KitaplarEkrani(sesAc: { _ in }).environmentObject(depo), "m-kitaplar", s, boy: mac)
        ciz(KurOzetEkrani(kurId: depo.durum.kurlar.last?.id ?? "", yapilan: [], oncekiKademe: [:], kapat: {}).environmentObject(depo).background(Tema.arka), "e-ozet", s)
        ciz(SesKayitSayfasi(hedef: a.isaretler.first?.id).environmentObject(depo), "e-ses", s)
    }
    Paylasim.yaz(depo.anlik())
    print("tamam")
}
} }
