// Widget yüzü — hem gerçek widget'ta hem uygulamadaki önizlemede aynı görünüm çizilir.
// Ana ekran: küçük · orta · büyük. Kilit ekranı: daire · dikdörtgen · satır (sistem tek renge çevirir).
import SwiftUI
import WidgetKit
import AppIntents

enum WidgetOlcu {
    static func boy(_ a: WidgetFamily) -> CGSize {
        switch a {
        case .systemSmall: CGSize(width: 170, height: 170)
        case .systemMedium: CGSize(width: 364, height: 170)
        case .systemLarge: CGSize(width: 364, height: 382)
        case .accessoryCircular: CGSize(width: 76, height: 76)
        case .accessoryRectangular: CGSize(width: 172, height: 76)
        case .accessoryInline: CGSize(width: 250, height: 26)
        default: CGSize(width: 170, height: 170)
        }
    }
    static let ana: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]
    static let kilit: [WidgetFamily] = [.accessoryCircular, .accessoryRectangular, .accessoryInline]
    static func ad(_ a: WidgetFamily) -> String {
        switch a {
        case .systemSmall: "Küçük"
        case .systemMedium: "Orta"
        case .systemLarge: "Büyük"
        case .accessoryCircular: "Daire"
        case .accessoryRectangular: "Dikdörtgen"
        case .accessoryInline: "Satır"
        default: ""
        }
    }
}

struct WidgetGorunum: View {
    var t: WidgetTasarim
    var g: Gosterilen
    var aile: WidgetFamily
    var tarih: Date
    var cevrik: Bool
    var veri: VitrinVeri
    var bilinen: Set<String>
    var canli = true          // false: uygulama önizlemesi (düğmeler çizilir ama niyet çalıştırmaz)

    private var y: YaziStili { t.yazi }
    private var o: CGFloat { y.olcek }
    private var renk: Color { Color(hex: y.renk) }
    private var vurgu: Color { Color(hex: y.vurgu) }
    private var gizli: Bool { (t.icerik == .kelime || t.icerik == .kavram) && (t.gizliBasla ? !cevrik : cevrik) }
    private var tr: Locale { Locale(identifier: "tr_TR") }

    var body: some View {
        switch aile {
        case .accessoryCircular: daire
        case .accessoryRectangular: dikdortgen
        case .accessoryInline: satir
        default: ana.foregroundStyle(renk).multilineTextAlignment(y.hiza.metin)
        }
    }

    // MARK: - Ana ekran

    @ViewBuilder private var ana: some View {
        switch t.icerik {
        case .kelime: kelime
        case .alinti: alinti
        case .kavram: kavram
        case .odak: odak
        case .saat: saat
        case .tarih: takvim
        case .geriSayim: geriSayim(ad: t.hedefAd, hedef: t.hedefTarih)
        case .ilerleme: geriSayim(ad: "Sonraki ölçüm", hedef: olcumTarihi ?? t.hedefTarih)
        case .metin:
            Text(g.ana).font(y.aile.font(aile == .systemSmall ? 20 * o : 26 * o))
                .minimumScaleFactor(0.5).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: y.hiza.cerceve)
        case .yok:
            Color.clear
        }
    }

    private func ust(_ s: String) -> some View {
        Text(s.uppercased(with: Locale(identifier: "tr")))
            .font(.system(size: 10 * o, weight: .bold, design: .rounded)).tracking(1.4)
            .foregroundStyle(vurgu).lineLimit(1)
    }

    private var kelime: some View {
        let kucuk = aile == .systemSmall
        return VStack(alignment: y.hiza.yatay, spacing: kucuk ? 3 : 5) {
            HStack {
                ust(g.ust)
                Spacer(minLength: 0)
                if !kucuk, t.dugmeler { dugmeler(dikey: false) }
            }
            Text(g.ana)
                .font(y.aile.font((kucuk ? 28 : 34) * o)).lineLimit(1).minimumScaleFactor(0.45)
                .id(g.ana).transition(.push(from: .bottom))
            if !g.ara.isEmpty { Text(g.ara).font(.system(size: 12 * o)).opacity(0.75).lineLimit(1) }
            anlam(g.alt, boy: (kucuk ? 15 : 18) * o)
            if !kucuk, t.ikincil, !g.ornek.isEmpty, !gizli {
                Text(g.ornek).font(y.aile.font(13 * o, ikincil: true)).italic().opacity(0.8)
                    .lineLimit(aile == .systemLarge ? 3 : 2).padding(.top, 2)
            }
            if aile == .systemLarge { gununListesi.padding(.top, 8) }
            Spacer(minLength: 0)
            if kucuk, t.dugmeler { dugmeler(dikey: false) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Alignment(horizontal: y.hiza.yatay, vertical: .top))
    }

    @ViewBuilder private func anlam(_ s: String, boy: CGFloat) -> some View {
        if gizli {
            HStack(spacing: 5) {
                Image(systemName: "eye.slash").font(.system(size: boy * 0.7))
                Text("anlamı hatırla").font(.system(size: boy * 0.7, weight: .medium))
            }
            .opacity(0.65)
            .padding(.vertical, 3).padding(.horizontal, 8)
            .background(Capsule().stroke(renk.opacity(0.35), lineWidth: 1))
        } else {
            Text(s).font(y.aile.font(boy, ikincil: true)).lineLimit(2).minimumScaleFactor(0.7)
                .transition(.opacity)
        }
    }

    private var gununListesi: some View {
        let liste = Secici.gununKelimeleri(veri, tarih, bilinen: bilinen)
        return VStack(alignment: .leading, spacing: 5) {
            Rectangle().fill(renk.opacity(0.25)).frame(height: 0.7)
            ForEach(liste, id: \.w) { k in
                HStack(alignment: .firstTextBaseline) {
                    Text(k.w).font(y.aile.font(14 * o)).foregroundStyle(k.w == g.ana ? vurgu : renk)
                    Spacer(minLength: 6)
                    Text(gizli ? "· · ·" : k.tr).font(.system(size: 12 * o)).opacity(0.75).lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder private func dugmeler(dikey: Bool) -> some View {
        // AnyLayout widget arşivinde düğmeleri dokunulamaz yapıyordu; düz HStack
        HStack(spacing: 8) {
            if t.icerik == .kelime || t.icerik == .kavram {
                dugme(gizli ? "eye" : "eye.slash", CevirNiyeti(t.id))
            }
            dugme("arrow.forward", SonrakiNiyeti(t.id))
            if t.icerik == .kelime {
                dugme("speaker.wave.2.fill", SeslendirNiyeti(metin: g.ana, ses: g.ses))
            }
        }
    }

    @ViewBuilder private func dugme<N: AppIntent>(_ simge: String, _ niyet: N) -> some View {
        let yuz = Image(systemName: simge)
            .font(.system(size: 11, weight: .bold))
            .frame(width: 26, height: 26)
            .background(Circle().fill(renk.opacity(0.16)))
            .foregroundStyle(renk)
        if canli {
            Button(intent: niyet) { yuz }.buttonStyle(.plain)
        } else { yuz }
    }

    private var alinti: some View {
        let kucuk = aile == .systemSmall
        return VStack(alignment: y.hiza.yatay, spacing: 6) {
            HStack(alignment: .top) {
                Text("“").font(.system(size: 34, weight: .bold, design: .serif)).foregroundStyle(vurgu).frame(height: 18, alignment: .top)
                Spacer(minLength: 0)
                if t.dugmeler, !kucuk { dugmeler(dikey: false) }
            }
            Text(g.ana)
                .font(y.aile.font((kucuk ? 14 : aile == .systemLarge ? 22 : 16) * o, ikincil: y.aile == .ince))
                .lineSpacing(2).minimumScaleFactor(0.55)
                .id(g.ana).transition(.push(from: .bottom))
            Spacer(minLength: 0)
            if t.ikincil, !g.alt.isEmpty {
                Text("— " + g.alt).font(.system(size: 10 * o, weight: .medium)).opacity(0.7).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Alignment(horizontal: y.hiza.yatay, vertical: .top))
    }

    private var kavram: some View {
        let kucuk = aile == .systemSmall
        return VStack(alignment: y.hiza.yatay, spacing: 5) {
            HStack {
                ust("Kavram")
                Spacer(minLength: 0)
                if t.dugmeler, !kucuk { dugmeler(dikey: false) }
            }
            Text(g.ana).font(y.aile.font((kucuk ? 22 : 28) * o)).lineLimit(1).minimumScaleFactor(0.5)
                .id(g.ana).transition(.push(from: .bottom))
            anlam(g.alt, boy: (kucuk ? 12 : aile == .systemLarge ? 18 : 14) * o)
            Spacer(minLength: 0)
            if t.ikincil, !kucuk, !g.ornek.isEmpty {
                Text(g.ornek).font(.system(size: 10 * o, weight: .medium)).opacity(0.65).lineLimit(1)
            }
            if kucuk, t.dugmeler { dugmeler(dikey: false) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Alignment(horizontal: y.hiza.yatay, vertical: .top))
    }

    private var odak: some View {
        let kucuk = aile == .systemSmall
        return VStack(alignment: y.hiza.yatay, spacing: 5) {
            ust(tarih.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(tr)))
            Text(g.ana).font(y.aile.font((kucuk ? 16 : 20) * o)).lineLimit(kucuk ? 3 : 2).minimumScaleFactor(0.6)
            if !kucuk {
                ForEach(g.satirlar.prefix(aile == .systemLarge ? 6 : 2), id: \.self) { s in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Circle().fill(vurgu).frame(width: 5, height: 5)
                        Text(s).font(.system(size: 12 * o)).lineLimit(aile == .systemLarge ? 2 : 1).opacity(0.88)
                    }
                }
            }
            Spacer(minLength: 0)
            if !g.alt.isEmpty {
                Text(g.alt).font(.system(size: 10 * o, weight: .semibold)).foregroundStyle(vurgu).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Alignment(horizontal: y.hiza.yatay, vertical: .top))
    }

    /// Canlı saat: gece yarısından beri geçen süre sayacı = şimdiki saat. Sistem saniye saniye günceller.
    private var saat: some View {
        let gece = Calendar.current.startOfDay(for: tarih)
        let kucuk = aile == .systemSmall
        let k = Secici.kelime(veri, tarih, bilinen: bilinen)
        return VStack(alignment: y.hiza.yatay, spacing: 4) {
            ust(tarih.formatted(.dateTime.weekday(.wide).locale(tr)))
            Text(tarih.formatted(.dateTime.day().month(.wide).locale(tr)))
                .font(y.aile.font((kucuk ? 15 : 18) * o, ikincil: true)).opacity(0.85)
            Spacer(minLength: 0)
            Text(gece, style: .timer)
                .font(y.aile.font((kucuk ? 30 : 46) * o).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, alignment: y.hiza.cerceve)
            if t.ikincil, let k {
                Text("\(k.w) · \(k.tr)").font(.system(size: 11 * o, weight: .medium)).opacity(0.75).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Alignment(horizontal: y.hiza.yatay, vertical: .top))
    }

    private var takvim: some View {
        let k = Calendar(identifier: .gregorian)
        let gun = k.component(.day, from: tarih)
        return Group {
            if aile == .systemSmall {
                VStack(alignment: y.hiza.yatay, spacing: 0) {
                    ust(tarih.formatted(.dateTime.weekday(.wide).locale(tr)))
                    Spacer(minLength: 0)
                    Text("\(gun)").font(y.aile.font(64 * o)).minimumScaleFactor(0.5)
                    Text(tarih.formatted(.dateTime.month(.wide).year().locale(tr))).font(.system(size: 13 * o, weight: .medium)).opacity(0.8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Alignment(horizontal: y.hiza.yatay, vertical: .top))
            } else {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 0) {
                        ust(tarih.formatted(.dateTime.weekday(.wide).locale(tr)))
                        Text("\(gun)").font(y.aile.font(52 * o)).minimumScaleFactor(0.5)
                        Text(tarih.formatted(.dateTime.month(.wide).locale(tr))).font(.system(size: 13 * o, weight: .medium)).opacity(0.8)
                        Spacer(minLength: 0)
                        if aile == .systemLarge, !veri.odak.ana.isEmpty {
                            Text(veri.odak.ana).font(.system(size: 12 * o, weight: .semibold)).foregroundStyle(vurgu).lineLimit(2)
                        }
                    }
                    .frame(width: 100)
                    AyIzgarasi(tarih: tarih, renk: renk, vurgu: vurgu, o: o, buyuk: aile == .systemLarge)
                }
            }
        }
    }

    private var olcumTarihi: Date? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: veri.odak.sonraki_olcum)
    }

    private func geriSayim(ad: String, hedef: Date) -> some View {
        let k = Calendar.current
        let kalan = max(0, k.dateComponents([.day], from: k.startOfDay(for: tarih), to: k.startOfDay(for: hedef)).day ?? 0)
        let toplam = 30.0
        let oran = 1 - min(1, Double(kalan) / toplam)
        return VStack(alignment: y.hiza.yatay, spacing: 4) {
            ust(ad)
            Spacer(minLength: 0)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(kalan)").font(y.aile.font((aile == .systemSmall ? 52 : 64) * o)).contentTransition(.numericText())
                Text("gün").font(.system(size: 15 * o, weight: .medium)).opacity(0.8)
            }
            .frame(maxWidth: .infinity, alignment: y.hiza.cerceve)
            ZStack(alignment: .leading) {
                Capsule().fill(renk.opacity(0.2))
                GeometryReader { g in Capsule().fill(vurgu).frame(width: max(6, g.size.width * oran)) }
            }
            .frame(height: 6)
            Text(hedef.formatted(.dateTime.day().month(.wide).locale(tr))).font(.system(size: 11 * o, weight: .medium)).opacity(0.75)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Alignment(horizontal: y.hiza.yatay, vertical: .top))
    }

    // MARK: - Kilit ekranı

    private var kalanGun: Int {
        let hedef = t.icerik == .ilerleme ? (olcumTarihi ?? t.hedefTarih) : t.hedefTarih
        let k = Calendar.current
        return max(0, k.dateComponents([.day], from: k.startOfDay(for: tarih), to: k.startOfDay(for: hedef)).day ?? 0)
    }

    @ViewBuilder private var daire: some View {
        ZStack {
            AccessoryWidgetBackground()
            switch t.icerik {
            case .saat:
                Text(Calendar.current.startOfDay(for: tarih), style: .timer)
                    .font(.system(size: 13, weight: .semibold, design: .rounded)).minimumScaleFactor(0.5).padding(6)
                    .multilineTextAlignment(.center)
            case .tarih:
                VStack(spacing: -2) {
                    Text(tarih.formatted(.dateTime.weekday(.abbreviated).locale(tr)).uppercased(with: Locale(identifier: "tr")))
                        .font(.system(size: 10, weight: .bold))
                    Text("\(Calendar.current.component(.day, from: tarih))").font(.system(size: 26, weight: .bold, design: .rounded))
                }
            case .geriSayim, .ilerleme:
                Gauge(value: max(0, 30 - Double(kalanGun)), in: 0...30) {
                    Text("gün")
                } currentValueLabel: {
                    Text("\(kalanGun)").font(.system(size: 20, weight: .bold, design: .rounded))
                }
                .gaugeStyle(.accessoryCircularCapacity)
            default:
                VStack(spacing: 0) {
                    Text(g.ana).font(.system(size: 15, weight: .bold, design: y.aile == .serif ? .serif : .rounded))
                        .minimumScaleFactor(0.4).lineLimit(2)
                    if t.icerik == .kelime { Text(g.ust.components(separatedBy: " ").first ?? "").font(.system(size: 9, weight: .bold)).opacity(0.7) }
                }
                .padding(7)
                .multilineTextAlignment(.center)
            }
        }
        .widgetAccentable()
    }

    @ViewBuilder private var dikdortgen: some View {
        let govde = VStack(alignment: .leading, spacing: 1) {
            switch t.icerik {
            case .kelime:
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(g.ana).font(.system(size: 17, weight: .bold, design: y.aile == .serif ? .serif : .rounded)).widgetAccentable()
                    Text(g.ara).font(.system(size: 11)).opacity(0.7).lineLimit(1)
                }
                .lineLimit(1).minimumScaleFactor(0.6)
                Text(gizli ? "dokun · anlamı aç" : g.alt).font(.system(size: 14, weight: .medium)).lineLimit(1)
                if !g.ornek.isEmpty { Text(gizli ? " " : g.ornek).font(.system(size: 11)).opacity(0.75).lineLimit(1) }
            case .alinti:
                Text(g.ana).font(.system(size: 13, weight: .medium, design: .serif)).lineLimit(3).minimumScaleFactor(0.7)
            case .kavram:
                Text(g.ana).font(.system(size: 16, weight: .bold, design: .serif)).widgetAccentable()
                Text(gizli ? "dokun · tanımı aç" : g.alt).font(.system(size: 12)).lineLimit(2)
            case .odak:
                Text(g.ana).font(.system(size: 14, weight: .bold)).lineLimit(1).widgetAccentable()
                ForEach(g.satirlar.prefix(2), id: \.self) { Text($0).font(.system(size: 11)).lineLimit(1) }
            case .geriSayim, .ilerleme:
                Text(t.icerik == .ilerleme ? "Sonraki ölçüm" : t.hedefAd).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text("\(kalanGun) gün").font(.system(size: 22, weight: .bold, design: .rounded)).widgetAccentable()
                ProgressView(value: max(0, 30 - Double(kalanGun)), total: 30)
            case .saat, .tarih:
                Text(tarih.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(tr))).font(.system(size: 13, weight: .semibold))
                if let k = Secici.kelime(veri, tarih, bilinen: bilinen) {
                    Text(k.w).font(.system(size: 17, weight: .bold, design: .serif)).widgetAccentable()
                    Text(k.tr).font(.system(size: 12)).lineLimit(1)
                }
            case .metin:
                Text(g.ana).font(.system(size: 14, weight: .medium)).lineLimit(3)
            case .yok:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if canli, t.icerik == .kelime || t.icerik == .kavram {
            Button(intent: CevirNiyeti(t.id)) { govde }.buttonStyle(.plain)
        } else { govde }
    }

    @ViewBuilder private var satir: some View {
        switch t.icerik {
        case .kelime: Text("\(g.ana) — \(gizli ? "?" : g.alt)")
        case .kavram: Text("\(g.ana): \(g.alt)")
        case .alinti, .metin: Text(g.ana)
        case .odak: Text(g.ana)
        case .geriSayim, .ilerleme: Text("\(kalanGun) gün · \(t.icerik == .ilerleme ? "ölçüm" : t.hedefAd)")
        default:
            if let k = Secici.kelime(veri, tarih, bilinen: bilinen) { Text("\(k.w) — \(k.tr)") } else { Text(tarih, style: .date) }
        }
    }
}

struct AyIzgarasi: View {
    var tarih: Date
    var renk: Color
    var vurgu: Color
    var o: CGFloat
    var buyuk: Bool

    var body: some View {
        var k = Calendar(identifier: .gregorian)
        k.firstWeekday = 2
        let ayBasi = k.date(from: k.dateComponents([.year, .month], from: tarih)) ?? tarih
        let gunSayisi = k.range(of: .day, in: .month, for: tarih)?.count ?? 30
        let bosluk = (k.component(.weekday, from: ayBasi) + 5) % 7
        let bugun = k.component(.day, from: tarih)
        let hucreler: [Int] = Array(repeating: 0, count: bosluk) + Array(1...gunSayisi)
        let sutun = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        return LazyVGrid(columns: sutun, spacing: buyuk ? 9 : 3) {
            ForEach(["P", "S", "Ç", "P", "C", "C", "P"].indices, id: \.self) { i in
                Text(["P", "S", "Ç", "P", "C", "C", "P"][i]).font(.system(size: 9 * o, weight: .bold)).opacity(0.55)
            }
            ForEach(hucreler.indices, id: \.self) { i in
                let g = hucreler[i]
                Text(g == 0 ? "" : "\(g)")
                    .font(.system(size: (buyuk ? 13 : 10) * o, weight: g == bugun ? .bold : .regular))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 1)
                    .background(g == bugun ? Circle().fill(vurgu).frame(width: (buyuk ? 24 : 17) * o, height: (buyuk ? 24 : 17) * o) : nil)
                    .opacity(g != 0 && g < bugun ? 0.5 : 1)
            }
        }
    }
}
