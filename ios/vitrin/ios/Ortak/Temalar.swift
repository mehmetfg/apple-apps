// Hazır paletler ve tema takımları. Tema = bir duvar + üç widget + bir kilit ekranı widget'ı; tek dokunuşla eklenir.
import Foundation

struct Palet: Identifiable, Hashable {
    var id: String { ad }
    var ad: String
    var renkler: [String]

    static let hepsi: [Palet] = [
        Palet(ad: "Gece Kütüphanesi", renkler: ["#0E1726", "#1F3A5F", "#7A5C3A", "#E9D9B8"]),
        Palet(ad: "Kâğıt", renkler: ["#F4EFE6", "#E4D8C4", "#B5523B", "#2E2B26"]),
        Palet(ad: "Kuzey Işığı", renkler: ["#050B18", "#0B6E6E", "#4BD6A8", "#6E56F7"]),
        Palet(ad: "Mermer", renkler: ["#EEEBE6", "#CFCAC2", "#8E8A84", "#2A2826"]),
        Palet(ad: "Bauhaus", renkler: ["#F1E8D9", "#E63946", "#1D3557", "#F4A261"]),
        Palet(ad: "Zeytin", renkler: ["#232B20", "#5D6B40", "#C2BD94", "#EFE9D8"]),
        Palet(ad: "Gün Batımı", renkler: ["#2A1735", "#C8553D", "#F2A541", "#F7E9D7"]),
        Palet(ad: "Okyanus", renkler: ["#03123B", "#0A4F8F", "#21A6C8", "#D2F1F7"]),
        Palet(ad: "Gül", renkler: ["#2E0D18", "#9E2F45", "#E7A6BE", "#FFF0F3"]),
        Palet(ad: "Grafit", renkler: ["#0D0D0E", "#222326", "#5E6066", "#EDEDED"]),
        Palet(ad: "Çöl", renkler: ["#3B2414", "#A0612E", "#E2B07A", "#F8EBDA"]),
        Palet(ad: "Lavanta", renkler: ["#1E1A33", "#5B4B9A", "#B8A6E8", "#F2EEFF"]),
    ]
}

struct Tema: Identifiable, Hashable {
    var id: String { ad }
    var ad: String
    var not: String
    var palet: [String]
    var aile: YaziAilesi
    var zeminTuru: ZeminTuru
    var desen: DesenTuru = .noktalar
    var tane: Double = 0.25
    var duvarIcerik: IcerikTuru
    var kart: KartStili = .yok

    var yaziRengi: String { RenkHesap.yaziRengi(palet, tur: zeminTuru, kart: kart) }
    var vurgu: String { RenkHesap.vurgu(palet, yazi: yaziRengi, tur: zeminTuru, kart: kart) }

    func zemin(_ tohum: Int = 0) -> Zemin {
        var z = Zemin()
        z.tur = zeminTuru; z.renkler = palet; z.desen = desen; z.tane = tane; z.tohum = tohum
        z.vinyet = zeminTuru == .duz ? 0.2 : 0.35
        return z
    }

    func yazi(_ olcek: Double = 1, hiza: Hiza = .orta) -> YaziStili {
        YaziStili(aile: aile, renk: yaziRengi, vurgu: vurgu, olcek: olcek, hiza: hiza, golge: zeminTuru != .duz, buyukHarf: aile == .siyah)
    }

    func duvar() -> Duvar {
        Duvar(ad: "\(ad) · Kilit", zemin: zemin(), icerik: duvarIcerik, yazi: yazi(), kart: kart, konum: 0.64, hedef: .kilit)
    }

    func widgetlar() -> [WidgetTasarim] {
        var a = WidgetTasarim(ad: "\(ad) · Kelime", zemin: zemin(1), icerik: .kelime, yazi: yazi(1, hiza: .bas))
        a.dongu = 60
        var b = WidgetTasarim(ad: "\(ad) · Alıntı", zemin: zemin(2), icerik: .alinti, yazi: yazi(1, hiza: .bas))
        b.dongu = 180
        let c = WidgetTasarim(ad: "\(ad) · Saat", zemin: zemin(3), icerik: .saat, yazi: yazi(1))
        let d = WidgetTasarim(ad: "\(ad) · Günün işi", zemin: zemin(4), icerik: .odak, yazi: yazi(1, hiza: .bas))
        var hepsi = [a, b, c, d]
        // Bauhaus'un iri biçimleri küçük yüzeyde yazıyı boğar: saat dışındakiler düz zemin + tane
        if desen == .bauhaus { for i in [0, 1, 3] { hepsi[i].zemin.tur = .duz; hepsi[i].zemin.tane = 0.35 } }
        return hepsi
    }

    static let hepsi: [Tema] = [
        Tema(ad: "Gece Kütüphanesi", not: "Serif, sıcak lacivert; kilitte alıntı", palet: Palet.hepsi[0].renkler,
             aile: .serif, zeminTuru: .mesh, duvarIcerik: .alinti),
        Tema(ad: "Kâğıt", not: "Fildişi, nokta deseni; kilitte kelime", palet: Palet.hepsi[1].renkler,
             aile: .serif, zeminTuru: .desen, desen: .noktalar, tane: 0.45, duvarIcerik: .kelime),
        Tema(ad: "Kuzey Işığı", not: "Karanlıkta akan yeşil-mor; kelime", palet: Palet.hepsi[2].renkler,
             aile: .yuvarlak, zeminTuru: .mesh, duvarIcerik: .kelime),
        Tema(ad: "Bauhaus", not: "Geometri, yoğun renk; günün işi", palet: Palet.hepsi[4].renkler,
             aile: .siyah, zeminTuru: .desen, desen: .bauhaus, tane: 0.3, duvarIcerik: .odak, kart: .duz),
        Tema(ad: "Zeytin", not: "Toprak tonları, topografya; kavram", palet: Palet.hepsi[5].renkler,
             aile: .serif, zeminTuru: .desen, desen: .topografya, duvarIcerik: .kavram),
        Tema(ad: "Grafit", not: "Siyah, mono, film tanesi; kelime", palet: Palet.hepsi[9].renkler,
             aile: .mono, zeminTuru: .gradyan, tane: 0.6, duvarIcerik: .kelime, kart: .cizgi),
        Tema(ad: "Gün Batımı", not: "Sıcak mesh, yuvarlak harf; alıntı", palet: Palet.hepsi[6].renkler,
             aile: .yuvarlak, zeminTuru: .mesh, duvarIcerik: .alinti, kart: .cam),
        Tema(ad: "Okyanus", not: "Derin mavi, dalgalar; kelime", palet: Palet.hepsi[7].renkler,
             aile: .ince, zeminTuru: .desen, desen: .dalga, duvarIcerik: .kelime),
        Tema(ad: "Yıldızlı", not: "Gece gökyüzü, ince harf; kavram", palet: Palet.hepsi[11].renkler,
             aile: .ince, zeminTuru: .desen, desen: .yildizlar, tane: 0.1, duvarIcerik: .kavram),
    ]

    /// Fotoğraftan çıkarılan paletle tema: zemin fotoğrafın kendisi
    static func fotograftan(palet: [String], foto: String) -> (Duvar, [WidgetTasarim]) {
        let t = Tema(ad: "Fotoğraf", not: "", palet: palet, aile: .serif, zeminTuru: .mesh, duvarIcerik: .kelime, kart: .cam)
        var d = t.duvar()
        d.ad = "Fotoğraf · Kilit"
        d.zemin.tur = .foto; d.zemin.foto = foto; d.zemin.karartma = 0.15; d.zemin.vinyet = 0.4
        d.yazi.renk = "#FFFFFF"
        var w = t.widgetlar()
        w[0].zemin.tur = .foto; w[0].zemin.foto = foto; w[0].zemin.karartma = 0.35; w[0].yazi.renk = "#FFFFFF"
        for i in w.indices { w[i].ad = w[i].ad.replacingOccurrences(of: "Fotoğraf", with: "Foto") }
        return (d, w)
    }
}

enum Varsayilan {
    static func tasarimlar() -> Tasarimlar {
        let t = Tema.hepsi[0]
        var k = Tema.hepsi[2]
        k.ad = "Kuzey Işığı"
        var d2 = k.duvar(); d2.ad = "Kuzey Işığı · Kelime"
        var s = Tasarimlar()
        s.duvarlar = [t.duvar(), d2]
        s.widgetlar = t.widgetlar() + [k.widgetlar()[0]]
        s.gunlukListe = s.duvarlar.map(\.id)
        return s
    }
}
