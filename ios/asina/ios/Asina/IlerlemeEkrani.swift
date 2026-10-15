// İlerleme: kelimeler kafanda nerede, depo ne kadar eridi, son 12 hafta.
import SwiftUI
import Charts

struct IlerlemeEkrani: View {
    @EnvironmentObject var depo: Depo

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    asamaKarti
                    depoKarti
                    takvim
                    bantKarti
                    gelecek
                }
                .padding(18)
            }
            .background(R.zemin.ignoresSafeArea())
            .navigationTitle("İlerleme")
        }
    }

    private var asamaKarti: some View {
        let sayilar = Asama.allCases.map { ($0, depo.sayim($0)) }
        let toplam = max(1, sayilar.map(\.1).reduce(0, +))
        return VStack(alignment: .leading, spacing: 14) {
            Text("Kafandaki kelimeler").font(.headline)
            GeometryReader { g in
                HStack(spacing: 3) {
                    ForEach(sayilar, id: \.0) { a, n in
                        if n > 0 {
                            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(R.asama(a))
                                .frame(width: max(6, (g.size.width - 9) * CGFloat(n) / CGFloat(toplam)))
                        }
                    }
                    if sayilar.allSatisfy({ $0.1 == 0 }) {
                        RoundedRectangle(cornerRadius: 5).fill(R.cizgi)
                    }
                }
            }
            .frame(height: 14)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(sayilar, id: \.0) { a, n in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Circle().fill(R.asama(a)).frame(width: 8, height: 8)
                            Text(a.ad).font(.subheadline.weight(.semibold))
                        }
                        Text("\(n)").font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
                        Text(a.aciklama).font(.caption2).foregroundStyle(R.soluk).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .kart(18)
    }

    private var depoKarti: some View {
        let toplam = max(1, depo.depoToplam)
        let kalan = depo.depoKalan
        let eriyen = toplam - kalan
        let gun = depo.ayar.yeniSayisi > 0 ? kalan / depo.ayar.yeniSayisi : 0
        return HStack(spacing: 18) {
            ZStack {
                Halka(oran: Double(eriyen) / Double(toplam), kalinlik: 10, renk: R.bant("B1"))
                Text("%\(Int(Double(eriyen) / Double(toplam) * 100))").font(.headline.monospacedDigit())
            }
            .frame(width: 76, height: 76)
            VStack(alignment: .leading, spacing: 4) {
                Text("Bilmediğim depo").font(.headline)
                Text("\(eriyen.formatted()) / \(toplam.formatted()) kelimeye dokunuldu")
                    .font(.subheadline).foregroundStyle(R.ikincil)
                Text("\(depo.biliyorumSayisi) tanesini zaten biliyormuşsun. Bu hızla kalan \(kalan.formatted()) kelime ~\(gun) gün.")
                    .font(.caption).foregroundStyle(R.soluk)
            }
        }
        .kart(18)
    }

    /// GitHub tarzı 12 haftalık takvim
    private var takvim: some View {
        let bugun = Date().gunBasi
        let haftaGunu = (Calendar.current.component(.weekday, from: bugun) + 5) % 7   // Pzt = 0
        let bas = bugun.gun(-(11 * 7 + haftaGunu))
        let degerler = (0..<84).map { i -> (Date, Int) in
            let g = bas.gun(i)
            let k = depo.kayit.gunler[g.gunAnahtari]
            return (g, (k?.yeni ?? 0) + (k?.tekrar ?? 0))
        }
        let enCok = max(10, degerler.map(\.1).max() ?? 0)
        let aktif = degerler.filter { $0.1 > 0 }.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Son 12 hafta").font(.headline)
                Spacer()
                Text("\(aktif) gün çalıştın").font(.footnote).foregroundStyle(R.soluk)
            }
            HStack(spacing: 4) {
                ForEach(0..<12, id: \.self) { h in
                    VStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { d in
                            let (g, n) = degerler[h * 7 + d]
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(g > bugun ? Color.clear : n == 0 ? R.cizgi
                                      : R.vurgu.opacity(0.25 + 0.75 * Double(n) / Double(enCok)))
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
        }
        .kart(18)
    }

    private var bantKarti: some View {
        let bantlar = ["A1", "A2", "B1", "B2", "C1"]
        let veri = bantlar.map { b -> (String, Int, Int) in
            let hepsi = depo.kelimeler.filter { $0.c == b && $0.s == "d" && !$0.isPV }
            let dokunulan = hepsi.filter { depo.kart($0) != nil || depo.kayit.kararlar[$0.w] != nil }.count
            return (b, dokunulan, hepsi.count)
        }.filter { $0.2 > 0 }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Bantlara göre depo").font(.headline)
            HStack(spacing: 10) {
                Text("PV").font(.caption2.weight(.heavy)).foregroundStyle(R.pv)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(R.pv.opacity(0.14), in: Capsule()).frame(width: 36)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(R.pv.opacity(0.12))
                        Capsule().fill(R.pv)
                            .frame(width: max(4, g.size.width * CGFloat(depo.pvDokunulan) / CGFloat(max(1, depo.pvToplam))))
                    }
                }
                .frame(height: 8)
                Text("\(depo.pvDokunulan)/\(depo.pvToplam)").font(.caption.monospacedDigit())
                    .foregroundStyle(R.ikincil).frame(width: 74, alignment: .trailing)
            }
            ForEach(veri, id: \.0) { b, n, t in
                HStack(spacing: 10) {
                    BantRozeti(bant: b).frame(width: 36)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(R.bant(b).opacity(0.12))
                            Capsule().fill(R.bant(b)).frame(width: max(4, g.size.width * CGFloat(n) / CGFloat(max(1, t))))
                        }
                    }
                    .frame(height: 8)
                    Text("\(n)/\(t)").font(.caption.monospacedDigit()).foregroundStyle(R.ikincil).frame(width: 74, alignment: .trailing)
                }
            }
        }
        .kart(18)
    }

    /// Önümüzdeki 14 günün tekrar yükü — tavanla kesilmiş, borç olarak değil plan olarak.
    private var gelecek: some View {
        let gunler = (0..<14).map { Date().gun($0) }
        let veri = gunler.map { g -> (Date, Int) in
            let n = depo.kayit.kartlar.values.filter { Calendar.current.isDate($0.vade, inSameDayAs: g) || (g == gunler[0] && $0.vade < g) }.count
            return (g, min(n, depo.ayar.tekrarTavani))
        }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Önümüzdeki iki hafta").font(.headline)
            Text("Her gün kaç kelime tekrar edecek. Tavanı (\(depo.ayar.tekrarTavani)) aşan kayar, birikmez.")
                .font(.caption).foregroundStyle(R.soluk)
            Chart(veri, id: \.0) { g, n in
                BarMark(x: .value("Gün", g, unit: .day), y: .value("Tekrar", n))
                    .foregroundStyle(R.asama(.asina).gradient)
                    .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.day())
                }
            }
            .frame(height: 140)
        }
        .kart(18)
    }
}
