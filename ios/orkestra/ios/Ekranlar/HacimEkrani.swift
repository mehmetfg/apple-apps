// Hacim — ne kadar dinledin, Claude ne kadar üretti. Temel ölçü Claude'un yazdığı metinden dinlenen;
// yayımlanmış kitaplar "diğer" olarak ayrı durur. Kelime → sayfa (225) → kitap (250 sayfa) ve saat.
import Charts
import SwiftUI

enum HacimKapsam: String, CaseIterable, Identifiable {
    case claude = "Claude metni", diger = "Diğer", hepsi = "Hepsi"
    var id: String { rawValue }
    func dinlenen(_ g: HacimGunu) -> Int {
        switch self { case .claude: g.c; case .diger: g.o; case .hepsi: g.c + g.o }
    }
}

enum HacimAdim: String, CaseIterable, Identifiable {
    case gun = "Gün", hafta = "Hafta", ay = "Ay"
    var id: String { rawValue }
    var bilesen: Calendar.Component { switch self { case .gun: .day; case .hafta: .weekOfYear; case .ay: .month } }
}

struct HacimHesap {
    let h: Hacim
    let kapsam: HacimKapsam
    let simdi: Date

    var seri: [HacimGunu] {
        let bas = kapsam == .claude ? h.baslangic : h.ilk_gun
        return h.seri.filter { $0.g >= bas }
    }
    var gunSayisi: Double { Double(max(1, seri.count)) }
    var kelime: Int { seri.reduce(0) { $0 + kapsam.dinlenen($1) } }
    var dakika: Double {
        // dakika belge belge tutuluyor; kapsamın payı kelime oranıyla bölüştürülür
        seri.reduce(0) { t, g in
            let top = g.c + g.o
            return top > 0 ? t + g.dk * Double(kapsam.dinlenen(g)) / Double(top) : t
        }
    }
    var uretilen: Int { h.seri.reduce(0) { $0 + $1.u } }
    var isaret: Int { seri.reduce(0) { $0 + $1.i } }

    func sayfa(_ k: Double) -> Double { k / Double(h.sayfa_kelime) }
    func kitap(_ k: Double) -> Double { k / h.kitapKelime }

    /// tüm zaman / gün / hafta / ay ortalaması — kapsamın ilk gününden bugüne
    func ortalama(_ bolen: Double) -> (kelime: Double, dakika: Double) {
        let n = gunSayisi / bolen
        return (Double(kelime) / max(1, n), dakika / max(1, n))
    }

    /// grafik kovaları: (kovanın ilk günü, dinlenen, üretilen)
    func kovalar(_ adim: HacimAdim) -> [(Date, Int, Int)] {
        let t = Tarih.takvim
        var d: [Date: (Int, Int)] = [:]
        for g in seri {
            guard let gun = g.gun, let k = t.dateInterval(of: adim.bilesen, for: gun)?.start else { continue }
            let e = d[k] ?? (0, 0)
            d[k] = (e.0 + kapsam.dinlenen(g), e.1 + (kapsam == .diger ? 0 : g.u))
        }
        let sirali = d.keys.sorted().map { ($0, d[$0]!.0, d[$0]!.1) }
        switch adim {
        case .gun: return Array(sirali.suffix(35))
        case .hafta: return Array(sirali.suffix(20))
        case .ay: return sirali
        }
    }
}

struct HacimEkrani: View {
    @EnvironmentObject var merkez: Merkez
    @State private var kapsam = HacimKapsam.claude
    @State private var adim = HacimAdim.hafta

    var body: some View {
        ScrollView {
            if let h = merkez.veri?.hacim {
                let x = HacimHesap(h: h, kapsam: kapsam, simdi: Merkez.simdi)
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Kapsam", selection: $kapsam) {
                        ForEach(HacimKapsam.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    toplam(x)
                    ortalamalar(x)
                    grafik(x)
                    if kapsam != .diger { olculer(x) }
                    aciklama(h)
                }
                .padding(.horizontal, 16).padding(.bottom, 30)
            } else {
                ContentUnavailableView("Hacim verisi yok", systemImage: "books.vertical",
                                       description: Text("Mac'te Orkestra toplayıcısı bir kez koşunca gelir."))
            }
        }
        .background(Tema.zemin)
        .navigationTitle("Hacim")
    }

    // MARK: tüm zaman
    func toplam(_ x: HacimHesap) -> some View {
        let k = Double(x.kelime)
        let bas = Tarih.coz(kapsam == .claude ? x.h.baslangic : x.h.ilk_gun).map(Tarih.kisa) ?? ""
        return Kart(baslik: "Tüm zaman · \(bas)'dan beri", simge: "books.vertical") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Bicim.ondalik(x.kitap(k))).font(.yuvarlak(54, .bold)).foregroundStyle(.tint)
                Text("kitap").font(.yuvarlak(20)).foregroundStyle(.secondary)
            }
            Text("250 sayfalık ortalama roman ölçüsüyle dinlediğin").font(.system(size: 12)).foregroundStyle(.tertiary)
            HStack(spacing: 0) {
                sayi(Bicim.tam(k), "kelime")
                sayi(Bicim.tam(x.sayfa(k)), "sayfa")
                sayi(Bicim.ondalik(x.dakika / 60), "saat")
            }
        }
    }

    func sayi(_ deger: String, _ ad: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(deger).font(.yuvarlak(19, .bold)).monospacedDigit()
            Text(ad).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: günlük · haftalık · aylık ortalama
    func ortalamalar(_ x: HacimHesap) -> some View {
        let satirlar: [(String, Double)] = [("Günlük", 1), ("Haftalık", 7), ("Aylık", 30.44)]
        return Kart(baslik: "Ortalama", simge: "chart.bar.xaxis") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 9) {
                GridRow {
                    Text("")
                    ForEach(["kelime", "sayfa", "kitap", "saat"], id: \.self) {
                        Text($0).font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                            .gridColumnAlignment(.trailing)
                    }
                }
                ForEach(satirlar, id: \.0) { ad, gun in
                    let o = x.ortalama(gun)
                    GridRow {
                        Text(ad).font(.system(size: 13, weight: .semibold))
                        Text(Bicim.tam(o.kelime)).monospacedDigit()
                        Text(Bicim.tam(x.sayfa(o.kelime))).monospacedDigit()
                        Text(Bicim.ondalik(x.kitap(o.kelime), 2)).monospacedDigit()
                        Text(Bicim.sure(o.dakika)).monospacedDigit()
                    }
                    .font(.system(size: 13))
                }
            }
            Text("\(Int(x.gunSayisi)) günün ortalaması — dinlemediğin günler de sayılır.")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
        }
    }

    // MARK: zaman grafiği
    func grafik(_ x: HacimHesap) -> some View {
        let k = x.kovalar(adim)
        return Kart(baslik: "Zaman içinde", simge: "waveform.path.ecg") {
            Picker("Adım", selection: $adim) {
                ForEach(HacimAdim.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Chart {
                ForEach(k, id: \.0) { d, dinlenen, uretilen in
                    BarMark(x: .value("Gün", d, unit: adim.bilesen), y: .value("Sayfa", x.sayfa(Double(dinlenen))))
                        .foregroundStyle(by: .value("Tür", "dinlenen"))
                        .cornerRadius(3)
                    if kapsam != .diger {
                        LineMark(x: .value("Gün", d, unit: adim.bilesen), y: .value("Sayfa", x.sayfa(Double(uretilen))))
                            .foregroundStyle(by: .value("Tür", "Claude üretti"))
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    }
                }
                if let kesin = Tarih.coz(x.h.kesin_baslangic), let ilk = k.first?.0, kesin > ilk {
                    RuleMark(x: .value("Kesin", kesin))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("← tahmini · kesin →").font(.system(size: 8)).foregroundStyle(.tertiary)
                        }
                }
            }
            .chartForegroundStyleScale(["dinlenen": Color.accentColor, "Claude üretti": Tema.alan("teknik")])
            .chartYAxisLabel("sayfa")
            .frame(height: 190)
        }
    }

    // MARK: kitap sayısından iyi ölçüler
    func olculer(_ x: HacimHesap) -> some View {
        let uretilen = Double(x.uretilen)
        let sindirim = uretilen > 0 ? Double(x.h.claude_sindirilen) / uretilen : 0
        let bekleyen = max(0, uretilen - Double(x.h.claude_sindirilen))
        let derinlik = x.kelime > 0 ? Double(x.isaret) / Double(x.kelime) * 10_000 : 0
        return Kart(baslik: "Kitap sayısından iyi ölçüler", simge: "scope") {
            olcu("Sindirim", "%\(Int((sindirim * 100).rounded()))",
                 "Claude'un ürettiği \(Bicim.ondalik(x.kitap(uretilen))) kitaplık metnin dinlenen payı. "
                 + "Dinlenmemiş: \(Bicim.ondalik(x.kitap(bekleyen))) kitap. Üretim tüketimi geçiyor mu, bunu söyler.",
                 Tema.nabiz(Int(sindirim * 100)))
            Divider()
            olcu("Dinleme süresi", Bicim.ondalik(x.dakika / 60) + " sa",
                 "Kelime metnin uzunluğunu, saat senin verdiğin zamanı ölçer. Hız değişse de karşılaştırılabilir.",
                 Tema.alan("ingilizce"))
            Divider()
            olcu("Derinlik", Bicim.ondalik(derinlik) + " işaret",
                 "10.000 dinlenen kelime başına işaret. Hacim değil, dikkat: dinlerken ne kadar durdun.",
                 Tema.alan("felsefe"))
        }
    }

    func olcu(_ ad: String, _ deger: String, _ not: String, _ renk: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(deger).font(.yuvarlak(20, .bold)).foregroundStyle(renk).frame(width: 96, alignment: .leading)
                .minimumScaleFactor(0.7).lineLimit(1)
            VStack(alignment: .leading, spacing: 2) {
                Text(ad).font(.system(size: 13, weight: .semibold))
                Text(not).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    func aciklama(_ h: Hacim) -> some View {
        var t = "Kaynak Voice Dream: imlece kadar okunan kelime. 1 sayfa = \(h.sayfa_kelime) kelime (vault'un A5 kitaplarından), "
            + "1 kitap = \(h.kitap_sayfa) sayfa. \(Tarih.coz(h.kesin_baslangic).map(Tarih.kisa) ?? "")'dan önceki günlük dağılım "
            + "tahminidir (belgenin eklenme ve son açılış günleri arasına yayılır); sonrası günlük anlık görüntüden kesin. "
            + "Claude metni: Temmuz'dan beri Voice Dream'e düşen, Claude'un yazdığı \(h.claude_metin) metin."
        if let n = h.arsiv_metin, n > 0 {
            t += " \(n)'i Voice Dream'den silinmiş, işaretleri vault'ta arşivli (\(Bicim.tam(Double(h.arsiv_kelime ?? 0))) kelime): "
                + "işaret dinlemenin kanıtı, son işaret gününe yazıldı."
        }
        if let n = h.beyan_metin, n > 0 {
            t += " \(n)'si işaretsiz silinmiş, senin beyanınla eklendi (\(Bicim.tam(Double(h.beyan_kelime ?? 0))) kelime"
                + ((h.beyan_tahmini ?? 0) > 0 ? "; \(Bicim.tam(Double(h.beyan_tahmini!)))'i tam metni kalmadığı için ortalamayla" : "")
                + ")."
        }
        return Text(t).font(.system(size: 10)).foregroundStyle(.tertiary)
    }

}

/// Partisyon'un başındaki özet kart
struct HacimOzeti: View {
    var h: Hacim
    var body: some View {
        let x = HacimHesap(h: h, kapsam: .claude, simdi: Merkez.simdi)
        let k = Double(x.kelime)
        let hafta = x.ortalama(7).kelime
        Kart(baslik: "Hacim · Claude metni", simge: "books.vertical") {
            HStack(alignment: .firstTextBaseline) {
                Text(Bicim.ondalik(x.kitap(k))).font(.yuvarlak(34, .bold)).foregroundStyle(.tint)
                Text("kitap").foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            Text("\(Bicim.tam(k)) kelime · \(Bicim.tam(x.sayfa(k))) sayfa · haftada \(Bicim.tam(x.sayfa(hafta))) sayfa")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}

enum Bicim {
    static let tr = Locale(identifier: "tr_TR")
    static func tam(_ d: Double) -> String { d.formatted(.number.precision(.fractionLength(0)).locale(tr)) }
    static func ondalik(_ d: Double, _ n: Int = 1) -> String { d.formatted(.number.precision(.fractionLength(n)).locale(tr)) }
    static func sure(_ dk: Double) -> String {
        dk >= 60 ? "\(Int(dk) / 60) sa \(Int(dk) % 60) dk" : "\(Int(dk.rounded())) dk"
    }
}
