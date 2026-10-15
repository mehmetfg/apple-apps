// İngilizce: Cümle Tezgâhı'nın bugünü (çevrilen kartlar), tutma grafiği, hatalar, gramer,
// kelime deposu, geçmiş günler, Kelime Eki ve son kayıtlar.
import SwiftUI
import Charts

struct IngilizceEkrani: View {
    @EnvironmentObject var depo: VeriDeposu
    @State private var gramerAcik = false

    var body: some View {
        let c = depo.veri?.cumle
        Ekran {
            EkranBasligi(ust: "Cümle Tezgâhı", baslik: "İngilizce", alt: altYazi(c))
            if let h = c?.hata {
                BolumHatasi(ad: "Cümle", hata: h)
            } else if let c {
                if let b = c.bugun { GunKahramani(b: b, son: c.gunler?.last).belirerek() }
                if let cs = c.bugun?.cumleler, !cs.isEmpty {
                    BolumBasligi(baslik: "Bugünün cümleleri", alt: "dokun → çevir")
                    CumleDestesi(cumleler: cs)
                }
                KelimeCipleri(b: c.bugun).belirerek()
                TutmaGrafigi(gunler: c.gunler ?? []).belirerek()
                HataGrafigi(hatalar: c.hatalar ?? []).belirerek()
                GramerKarti(c: c) { gramerAcik = true }.belirerek()
                DepoKarti(d: c.depo).belirerek()
                GecmisGunler(gunler: c.gunler ?? [])
                if let e = c.kelime_eki, e.hata == nil { KelimeEkiKarti(e: e).belirerek() }
                if let k = c.kayitlar, !k.isEmpty { KayitListesi(baslik: "Son kayıtlar", kayitlar: k, renk: T.cumle) }
            }
        }
        .sheet(isPresented: $gramerAcik) {
            GramerSayfasi(yapilar: depo.veri?.cumle?.yapilar ?? [], toplam: depo.veri?.cumle?.konu_toplam ?? 0)
                .presentationDetents([.large]).presentationCornerRadius(28)
        }
        .navigationDestination(for: CumleGun.self) { GunDetayi(gun: $0) }
    }

    func altYazi(_ c: CumleBolum?) -> String? {
        guard let g = c?.gunler, !g.isEmpty else { return nil }
        let ort = g.suffix(7).compactMap(\.tutma).reduce(0, +) / Double(max(1, g.suffix(7).compactMap(\.tutma).count))
        return "\(g.count) gün yazıldı · son 7 gün ort. %\(Int(ort.rounded()))"
    }
}

// MARK: - Günün kartı

struct GunKahramani: View {
    let b: CumleBugun
    let son: CumleGun?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("GÜN \(b.gun ?? 0)").font(.caption.weight(.heavy)).tracking(1).foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text(b.yapildi == true ? "bitti ✓" : (b.mod ?? "bugün"))
                    .font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.white.opacity(0.2), in: Capsule()).foregroundStyle(.white)
            }
            Text(b.baslik ?? "—").font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
            if let t = b.tema { Text(t).font(.callout).foregroundStyle(.white.opacity(0.9)) }
            if let k = b.konular, !k.isEmpty {
                Akis {
                    ForEach(k, id: \.self) {
                        Text($0).font(.caption.weight(.medium)).padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.white.opacity(0.18), in: Capsule()).foregroundStyle(.white)
                    }
                }
                .padding(.top, 4)
            }
            if let s = son, let t = s.tutma {
                Text("Dün: \(s.baslik ?? "") · tutma %\(Int(t))")
                    .font(.footnote).foregroundStyle(.white.opacity(0.8)).padding(.top, 2)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color.hex(0xB98A45), Color.hex(0x8A5F22)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "quote.opening").font(.system(size: 120, weight: .black))
                        .foregroundStyle(.white.opacity(0.08)).offset(x: 20, y: -10)
                }
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Color.hex(0x8A5F22).opacity(0.3), radius: 18, y: 10)
    }
}

// MARK: - Çevrilen cümle kartları

struct CumleDestesi: View {
    let cumleler: [Cumle]
    @State private var konum: Int?

    var body: some View {
        VStack(spacing: 8) {
            Serit(ogeler: numarali, konum: $konum) { x in
                CevrilenKart(cumle: x.cumle, sira: x.id + 1, toplam: cumleler.count)
                    .modifier(SeritGenisligi())
                    .modifier(SeritGecisi(olcek: 0.9, donus: 0, solma: 0.5))
            }
            Text("\((konum ?? 0) + 1) / \(cumleler.count)")
                .font(.caption.monospacedDigit()).foregroundStyle(T.soluk)
                .contentTransition(.numericText())
                .animation(T.yay, value: konum)
        }
        .padding(.horizontal, -16)
    }

    var numarali: [NumaraliCumle] { cumleler.enumerated().map { NumaraliCumle(id: $0.offset, cumle: $0.element) } }
}

struct NumaraliCumle: Identifiable {
    let id: Int
    let cumle: Cumle
}

struct CevrilenKart: View {
    let cumle: Cumle
    let sira: Int
    let toplam: Int
    @State private var cevrik = false

    var body: some View {
        ZStack {
            yuz(ust: "TÜRKÇE · \(sira)", metin: cumle.tr ?? "", alt: cumle.konu, renk: T.yuzey, yazi: T.murekkep)
                .opacity(cevrik ? 0 : 1)
            yuz(ust: "ENGLISH · \(sira)", metin: cumle.en ?? "", alt: "tekrar dokun → Türkçe", renk: T.cumle, yazi: .white)
                .rotation3DEffect(.degrees(180), axis: (0, 1, 0))
                .opacity(cevrik ? 1 : 0)
        }
        .rotation3DEffect(.degrees(cevrik ? 180 : 0), axis: (0, 1, 0), perspective: 0.6)
        .onTapGesture { withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) { cevrik.toggle() } }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: cevrik)
    }

    func yuz(ust: String, metin: String, alt: String?, renk: Color, yazi: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ust).font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(yazi.opacity(0.6))
            Spacer(minLength: 0)
            Text(metin).font(.system(size: 22, weight: .semibold, design: .serif)).foregroundStyle(yazi)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let alt { Text(alt).font(.caption).foregroundStyle(yazi.opacity(0.6)) }
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 210, maxHeight: 210, alignment: .leading)
        .background(renk, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(T.cizgi))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 6)
    }
}

// MARK: - Kelimeler

struct KelimeCipleri: View {
    let b: CumleBugun?
    var body: some View {
        if let b, !(b.yeni ?? []).isEmpty || !(b.yanki ?? []).isEmpty {
            KartKutu {
                if let y = b.yeni, !y.isEmpty {
                    Text("Yeni kelimeler").font(.caption.weight(.semibold)).foregroundStyle(T.soluk)
                    Akis { ForEach(y, id: \.self) { Cip(metin: $0, renk: T.cumle) } }.padding(.top, 6)
                }
                if let y = b.yanki, !y.isEmpty {
                    Text("Yankı · önceki günlerden").font(.caption.weight(.semibold)).foregroundStyle(T.soluk).padding(.top, 12)
                    Akis { ForEach(y, id: \.self) { Cip(metin: $0) } }.padding(.top, 6)
                }
            }
        }
    }
}

// MARK: - Grafikler

struct TutmaGrafigi: View {
    let gunler: [CumleGun]
    @State private var ciz = false
    @Environment(\.statik) private var statik

    var body: some View {
        let g = Array(gunler.suffix(14)).filter { $0.tutma != nil }
        let ciz = self.ciz || statik
        KartKutu {
            HStack(alignment: .firstTextBaseline) {
                Text("Tutma").font(.headline)
                Spacer()
                if let s = g.last?.tutma {
                    Text("%\(Int(s))").font(.system(.title2, design: .rounded).weight(.bold)).foregroundStyle(T.cumle)
                }
            }
            Chart(g) { x in
                AreaMark(x: .value("Gün", x.gun ?? 0), yStart: .value("t", 80), yEnd: .value("Tutma", ciz ? (x.tutma ?? 80) : 80))
                    .foregroundStyle(LinearGradient(colors: [T.cumle.opacity(0.3), T.cumle.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Gün", x.gun ?? 0), y: .value("Tutma", ciz ? (x.tutma ?? 80) : 80))
                    .foregroundStyle(T.cumle)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("Gün", x.gun ?? 0), y: .value("Tutma", ciz ? (x.tutma ?? 80) : 80))
                    .foregroundStyle(T.cumle).symbolSize(x.id == g.last?.id ? 60 : 18)
            }
            .chartYScale(domain: 80...100)
            .chartXScale(domain: (g.first?.gun ?? 0)...(max((g.first?.gun ?? 0) + 1, g.last?.gun ?? 1)))
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { v in
                AxisValueLabel { if let n = v.as(Int.self) { Text("G\(n)") } }
            } }
            .chartYAxis { AxisMarks(position: .leading, values: [80, 90, 100]) { _ in
                AxisGridLine().foregroundStyle(T.cizgi); AxisValueLabel()
            } }
            .frame(height: 170)
            .padding(.top, 6)
            Text("Son \(g.count) gün · cümle başına tutturma yüzdesi")
                .font(.caption).foregroundStyle(T.soluk)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.9).delay(0.1)) { self.ciz = true } }
    }
}

struct HataGrafigi: View {
    let hatalar: [AdSayi]
    @State private var ciz = false
    @Environment(\.statik) private var statik

    var body: some View {
        let ciz = self.ciz || statik
        if !hatalar.isEmpty {
            KartKutu {
                Text("Hata türleri").font(.headline)
                Chart(hatalar.prefix(6)) { h in
                    BarMark(x: .value("Sayı", ciz ? h.sayi : 0), y: .value("Tür", h.ad))
                        .foregroundStyle(T.cumle.gradient)
                        .cornerRadius(6)
                        .annotation(position: .trailing) {
                            Text("\(h.sayi)").font(.caption.monospacedDigit()).foregroundStyle(T.yumusak)
                        }
                }
                .chartXAxis(.hidden)
                .chartYAxis { AxisMarks { _ in AxisValueLabel().font(.subheadline) } }
                .frame(height: CGFloat(min(6, hatalar.count)) * 34)
                .padding(.top, 6)
            }
            .onAppear { withAnimation(.spring(response: 0.8, dampingFraction: 0.8).delay(0.1)) { self.ciz = true } }
        }
    }
}

// MARK: - Gramer

struct GramerKarti: View {
    let c: CumleBolum
    let tumu: () -> Void

    var body: some View {
        let y = c.yapilar ?? []
        let toplam = max(1, c.konu_toplam ?? 41)
        KartKutu {
            HStack(spacing: 16) {
                ZStack {
                    Halka(oran: Double(y.count) / Double(toplam), renk: T.cumle, kalinlik: 9)
                    VStack(spacing: 0) {
                        Text("\(y.count)").font(.system(.title2, design: .rounded).weight(.bold))
                        Text("/\(toplam)").font(.caption2).foregroundStyle(T.soluk)
                    }
                }
                .frame(width: 76, height: 76)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Gramer yapıları").font(.headline)
                    Text("\(y.count) konu çalışıldı · en zayıflar aşağıda").font(.footnote).foregroundStyle(T.yumusak)
                }
            }
            VStack(spacing: 6) {
                ForEach(y.prefix(4)) { x in
                    OranSatiri(ad: x.konu, deger: "%\(Int(x.skor ?? 0))", oran: ((x.skor ?? 0) - 60) / 40, renk: T.cumle)
                }
            }
            .padding(.top, 12)
            Button(action: tumu) {
                HStack { Text("Tüm yapılar"); Spacer(); Image(systemName: "chevron.right") }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(T.cumle)
                    .padding(12).background(T.cumle.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
    }
}

struct GramerSayfasi: View {
    let yapilar: [Yapi]
    let toplam: Int
    var body: some View {
        NavigationStack {
            List(yapilar) { y in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(y.konu).font(.subheadline.weight(.medium))
                        Spacer()
                        Text("%\(Int(y.skor ?? 0))").font(.subheadline.monospacedDigit().weight(.semibold)).foregroundStyle(T.cumle)
                    }
                    Cubuk(oran: ((y.skor ?? 0) - 60) / 40, renk: T.cumle, kalinlik: 4)
                    Text("\(y.kez ?? 1) kez çalışıldı").font(.caption).foregroundStyle(T.soluk)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("\(yapilar.count)/\(toplam) yapı")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}

// MARK: - Kelime deposu

struct DepoKarti: View {
    let d: KelimeDepo?
    @State private var ciz = false
    @Environment(\.statik) private var statik

    var body: some View {
        let ciz = self.ciz || statik
        let b = d?.biliyorum ?? 0, t = d?.tanidik ?? 0, x = d?.bilmiyorum ?? 0
        let havuz = max(d?.havuz ?? 0, b + t + x)
        let kalan = max(0, havuz - b - t - x)
        let dilimler: [(String, Int, Color)] = [("kullanırım", b, T.muhendis), ("tanırım", t, T.cumle),
                                                ("bilmem", x, T.idrak), ("işlenmedi", kalan, T.tint)]
        KartKutu {
            Text("Kelime deposu").font(.headline)
            HStack(spacing: 18) {
                ZStack {
                    Chart(dilimler, id: \.0) { d in
                        SectorMark(angle: .value("n", ciz ? d.1 : (d.0 == "işlenmedi" ? 1 : 0)),
                                   innerRadius: .ratio(0.64), angularInset: 1.5)
                            .foregroundStyle(d.2).cornerRadius(4)
                    }
                    VStack(spacing: 0) {
                        Text(Bicim.sayi(havuz)).font(.system(.headline, design: .rounded).weight(.bold))
                        Text("kelime").font(.caption2).foregroundStyle(T.soluk)
                    }
                }
                .frame(width: 120, height: 120)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(dilimler, id: \.0) { d in
                        HStack(spacing: 8) {
                            Circle().fill(d.2).frame(width: 9, height: 9)
                            Text(d.0).font(.subheadline)
                            Spacer()
                            Text(Bicim.sayi(d.1)).font(.subheadline.monospacedDigit()).foregroundStyle(T.yumusak)
                        }
                    }
                }
            }
            .padding(.top, 8)
        }
        .onAppear { withAnimation(.easeInOut(duration: 1.0).delay(0.1)) { self.ciz = true } }
    }
}

// MARK: - Geçmiş günler

struct GecmisGunler: View {
    let gunler: [CumleGun]
    @State private var hepsi = false

    var body: some View {
        let liste = Array(gunler.reversed())
        BolumBasligi(baslik: "Geçmiş günler", alt: "\(gunler.count) gün")
        KartKutu(dolgu: 6) {
            VStack(spacing: 0) {
                ForEach(Array((hepsi ? liste : Array(liste.prefix(6))).enumerated()), id: \.element.id) { i, g in
                    NavigationLink(value: g) {
                        HStack(spacing: 12) {
                            Text("\(g.gun ?? 0)")
                                .font(.system(.subheadline, design: .rounded).weight(.bold))
                                .frame(width: 38, height: 38)
                                .background(T.cumle.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                                .foregroundStyle(T.cumle)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(g.baslik ?? "—").font(.subheadline.weight(.medium)).foregroundStyle(T.murekkep).lineLimit(1)
                                Text(Bicim.kisaTarih(g.tarih) + ((g.sure_dk).map { " · \(Int($0)) dk" } ?? ""))
                                    .font(.caption).foregroundStyle(T.soluk)
                            }
                            Spacer()
                            if let t = g.tutma {
                                Text("%\(Int(t))").font(.subheadline.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(t >= 95 ? T.muhendis : t >= 90 ? T.cumle : T.idrak)
                            }
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(T.soluk)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if i < (hepsi ? liste.count : min(6, liste.count)) - 1 { Divider().padding(.leading, 62) }
                }
                if liste.count > 6 {
                    Button(hepsi ? "Daha az" : "Tümünü göster (\(liste.count))") { withAnimation(T.yay) { hepsi.toggle() } }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(T.cumle).padding(12)
                }
            }
        }
    }
}

struct GunDetayi: View {
    let gun: CumleGun
    var body: some View {
        Kaydir {
            VStack(alignment: .leading, spacing: 14) {
                Text("GÜN \(gun.gun ?? 0) · \(Bicim.kisaTarih(gun.tarih))".uppercased(with: Bicim.tr))
                    .font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(T.cumle)
                Text(gun.baslik ?? "").font(.system(size: 30, weight: .bold))
                if let o = gun.ozet ?? gun.tema { Text(o).foregroundStyle(T.yumusak) }
                HStack {
                    BuyukSayi(deger: gun.tutma.map { "%\(Int($0))" } ?? "—", etiket: "tutma", renk: T.cumle)
                    BuyukSayi(deger: gun.paragraf.map { "%\(Int($0))" } ?? "—", etiket: "paragraf")
                    BuyukSayi(deger: "\(gun.baktim ?? 0)", etiket: "bakılan")
                    BuyukSayi(deger: gun.sure_dk.map { "\(Int($0))" } ?? "—", etiket: "dakika")
                }
                .padding(.vertical, 6)
                if let p = gun.paragraf_metin, !p.isEmpty {
                    KartKutu {
                        Text("KENDİ PARAGRAFIN").font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(T.cumle)
                        Text(p).font(.system(.callout, design: .serif)).padding(.top, 6)
                    }
                }
                ForEach(Array((gun.cumleler ?? []).enumerated()), id: \.offset) { i, c in
                    KartKutu(dolgu: 14) {
                        HStack(alignment: .top) {
                            Text("\(i + 1)").font(.caption.bold()).foregroundStyle(T.soluk)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(c.tr ?? "").font(.subheadline).foregroundStyle(T.yumusak)
                                Text(c.en ?? "").font(.system(.body, design: .serif).weight(.semibold))
                                if let y = c.yazim, y != c.en {
                                    Text(y).font(.footnote).foregroundStyle(T.idrak)
                                }
                            }
                            Spacer(minLength: 6)
                            VStack(alignment: .trailing, spacing: 4) {
                                if let y = c.yuzde {
                                    Text("%\(Int(y))").font(.caption.monospacedDigit().weight(.bold))
                                        .foregroundStyle(y >= 95 ? T.muhendis : y >= 85 ? T.cumle : T.idrak)
                                }
                                if c.baktim == true { Image(systemName: "eye").font(.caption2).foregroundStyle(T.soluk) }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(T.zemin.ignoresSafeArea())
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Kelime Eki

struct KelimeEkiKarti: View {
    let e: KelimeEki
    var body: some View {
        KartKutu {
            HStack {
                Text("🪶 Kelime Eki").font(.headline)
                Spacer()
                Text("\(e.toplam ?? 0) kelime").font(.footnote).foregroundStyle(T.soluk)
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach((e.son ?? []).prefix(6)) { k in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(k.kelime).font(.system(.subheadline, design: .serif).weight(.semibold))
                        Text(k.turkce ?? "").font(.footnote).foregroundStyle(T.yumusak).lineLimit(2)
                        Spacer(minLength: 0)
                        if let s = k.slot { Text(s).font(.caption2).foregroundStyle(T.soluk) }
                    }
                }
            }
            .padding(.top, 8)
        }
    }
}

// MARK: - Kayıtlar (log)

struct KayitListesi: View {
    let baslik: String
    let kayitlar: [Kayit]
    var renk: Color
    @State private var acik: String?

    var body: some View {
        BolumBasligi(baslik: baslik)
        KartKutu(dolgu: 6) {
            VStack(spacing: 0) {
                ForEach(Array(kayitlar.enumerated()), id: \.element.id) { i, k in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 10) {
                            Circle().fill(renk).frame(width: 7, height: 7).padding(.top, 6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(k.baslik).font(.subheadline.weight(.medium)).lineLimit(acik == k.id ? nil : 2)
                                Text([Bicim.kisaTarih(k.tarih), k.kaynak, k.tur].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(T.soluk)
                                if acik == k.id, let o = k.ozet, !o.isEmpty {
                                    Text(o).font(.footnote).foregroundStyle(T.yumusak).padding(.top, 4)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(12)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(T.yay) { acik = acik == k.id ? nil : k.id } }
                    if i < kayitlar.count - 1 { Divider().padding(.leading, 29) }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: acik)
    }
}
