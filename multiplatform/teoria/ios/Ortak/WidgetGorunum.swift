// Widget görünümleri — dört widget, her boyut ayrı düşünüldü.
// Zemin burada değil: widget'ta `containerBackground`, önizlemede elle verilir (WZemin).
// Kurallar: tek bakışta okunur; serif yalnız fikir taşıyan metinde; renk = kitabın rengi;
// koyu kipte saf siyah zemin; vurgulu (accented / cam) kipte birincil öğeler `widgetAccentable`.
import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Zemin

struct WZemin: View {
    var renk: Color
    @Environment(\.colorScheme) private var cs

    var body: some View {
        ZStack {
            cs == .dark ? Color.black : Color.white
            // Koyu kipte zemin siyah kalır; yalnız köşede kitabın renginde hafif bir ışıma.
            RadialGradient(colors: [renk.opacity(cs == .dark ? 0.20 : 0.13), .clear],
                           center: .topTrailing, startRadius: 2, endRadius: cs == .dark ? 170 : 240)
        }
    }
}

private struct Etiket: View {
    let metin: String
    let sembol: String
    let renk: Color
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: sembol).font(.system(size: 10, weight: .bold))
            Text(metin.uppercased(with: Dil.tr)).font(.system(size: 10, weight: .bold)).tracking(0.6)
        }
        .foregroundStyle(renk)
        .widgetAccentable()
    }
}

private struct YuvarlakDugme<N: AppIntent>: View {
    let niyet: N
    let sembol: String
    var renk: Color = Tema.ikincil
    var boy: CGFloat = 30
    var body: some View {
        Button(intent: niyet) {
            Image(systemName: sembol)
                .font(.system(size: boy * 0.42, weight: .semibold))
                .foregroundStyle(renk)
                .frame(width: boy, height: boy)
                .background(Circle().fill(renk.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 1 · Aforizma

struct AforizmaWidgetGorunum: View {
    let anlik: WidgetAnlik
    let sira: Int
    var zorla: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var ortamAile
    private var aile: WidgetFamily { zorla ?? ortamAile }

    var secili: WAforizma? {
        guard !anlik.aforizmalar.isEmpty else { return nil }
        return anlik.aforizmalar[((sira % anlik.aforizmalar.count) + anlik.aforizmalar.count) % anlik.aforizmalar.count]
    }

    static func renk(_ a: WidgetAnlik, _ sira: Int) -> Color {
        guard !a.aforizmalar.isEmpty else { return Tema.vurgu }
        return Tema.renk(a.aforizmalar[abs(sira) % a.aforizmalar.count].renk)
    }

    /// Dokununca: kendi işaretinse notun odası (bağlamıyla), aforizmaysa Akış.
    static func adres(_ a: WidgetAnlik, _ sira: Int) -> URL? {
        guard !a.aforizmalar.isEmpty else { return URL(string: "teoria://akis") }
        let x = a.aforizmalar[abs(sira) % a.aforizmalar.count]
        return URL(string: x.isaret ? "teoria://isaret/\(x.id)" : "teoria://akis")
    }

    var body: some View {
        if let a = secili {
            switch aile {
            case .accessoryInline:
                Text("❝ \(a.metin)")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.metin).font(.system(.callout, design: .serif)).lineLimit(3).minimumScaleFactor(0.8)
                    Text(a.kaynak).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "quote.opening").font(.title3.weight(.semibold)).widgetAccentable()
                }
            case .systemSmall:
                kucuk(a)
            case .systemMedium:
                orta(a)
            case .systemExtraLarge:
                cokBuyuk(a)
            default:
                buyuk(a)
            }
        } else {
            Text("Aforizmalar uygulama ilk açıldığında gelir.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func kucuk(_ a: WAforizma) -> some View {
        let r = Tema.renk(a.renk)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "quote.opening").font(.system(size: 15, weight: .bold)).foregroundStyle(r).widgetAccentable()
                Spacer()
                if a.favori { Image(systemName: "heart.fill").font(.system(size: 11)).foregroundStyle(r) }
            }
            Text(a.metin)
                .font(.system(size: 15, weight: .medium, design: .serif))
                .foregroundStyle(Tema.metin)
                .lineSpacing(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Text(a.kaynak.components(separatedBy: " · ").first ?? a.kaynak)
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Tema.ikincil).lineLimit(1)
        }
    }

    private func orta(_ a: WAforizma) -> some View {
        let r = Tema.renk(a.renk)
        return HStack(alignment: .top, spacing: 14) {
            Capsule().fill(r.gradient).frame(width: 4).widgetAccentable()
            VStack(alignment: .leading, spacing: 8) {
                Etiket(metin: a.isaret ? "Senin işaretin" : "Aforizma", sembol: a.isaret ? "highlighter" : "quote.opening", renk: r)
                Text(a.metin)
                    .font(.system(size: 18, weight: .medium, design: .serif))
                    .foregroundStyle(Tema.metin)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                HStack(alignment: .center) {
                    Text(a.kaynak).font(.system(size: 11, weight: .medium)).foregroundStyle(Tema.ikincil).lineLimit(1)
                    Spacer(minLength: 6)
                    YuvarlakDugme(niyet: AforizmaFavori(kimlik: a.id), sembol: a.favori ? "heart.fill" : "heart", renk: r, boy: 28)
                    YuvarlakDugme(niyet: SonrakiAforizma(), sembol: "arrow.right", renk: Tema.ikincil, boy: 28)
                }
            }
        }
    }

    private func buyuk(_ a: WAforizma) -> some View {
        let r = Tema.renk(a.renk)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Etiket(metin: "Teoria", sembol: "sparkle", renk: r)
                Spacer()
                Text(Tarih.kisa(anlik.guncel)).font(.system(size: 11, weight: .medium)).foregroundStyle(Tema.soluk)
            }
            Image(systemName: "quote.opening").font(.system(size: 26, weight: .bold)).foregroundStyle(r.opacity(0.9)).widgetAccentable()
            Text(a.metin)
                .font(.system(size: 25, weight: .medium, design: .serif))
                .foregroundStyle(Tema.metin)
                .lineSpacing(2)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("— " + a.kaynak).font(.system(size: 12, weight: .medium)).foregroundStyle(Tema.ikincil)
            Spacer(minLength: 4)
            if let ilgili = a.ilgili, !ilgili.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Label((a.ilgiEtiket ?? "Bağlam").uppercased(with: Dil.tr), systemImage: a.ilgiEtiket == "Kavram" ? "lightbulb" : "text.alignleft")
                        .font(.system(size: 10, weight: .bold)).tracking(0.6).foregroundStyle(r)
                    Text(ilgili).font(.system(size: 13, design: .serif)).foregroundStyle(Tema.metin.opacity(0.85)).lineLimit(4)
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(r.opacity(0.09)))
            }
            HStack {
                if a.isaret {
                    Label("Notu aç", systemImage: "arrow.up.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Tema.ikincil)
                }
                Spacer()
                YuvarlakDugme(niyet: AforizmaFavori(kimlik: a.id), sembol: a.favori ? "heart.fill" : "heart", renk: r, boy: 32)
                YuvarlakDugme(niyet: SonrakiAforizma(), sembol: "arrow.right", renk: Tema.ikincil, boy: 32)
            }
        }
    }

    private func cokBuyuk(_ a: WAforizma) -> some View {
        HStack(alignment: .top, spacing: 22) {
            buyuk(a)
            VStack(alignment: .leading, spacing: 12) {
                Etiket(metin: "Sırada", sembol: "text.quote", renk: Tema.ikincil)
                ForEach(Array(anlik.aforizmalar.prefix(sira % max(anlik.aforizmalar.count, 1) + 5).suffix(4))) { x in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(x.metin).font(.system(size: 14, design: .serif)).foregroundStyle(Tema.metin).lineLimit(3)
                        Text(x.kaynak).font(.system(size: 10)).foregroundStyle(Tema.soluk)
                    }
                    Divider()
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - 2 · Hatırla (önce hatırla, sonra bak)

struct HatirlaWidgetGorunum: View {
    let anlik: WidgetAnlik
    let sira: Int
    let acik: Bool
    var zorla: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var ortamAile
    private var aile: WidgetFamily { zorla ?? ortamAile }

    var kart: WHatirla? {
        guard !anlik.hatirla.isEmpty else { return nil }
        return anlik.hatirla[abs(sira) % anlik.hatirla.count]
    }

    static func renk(_ a: WidgetAnlik, _ sira: Int) -> Color { Tema.hat(.hatirla) }

    var body: some View {
        if let k = kart {
            switch aile {
            case .accessoryInline:
                Text(acik ? "✓ \(k.cevap)" : "Hatırla: \(k.soru)")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text("HATIRLA").font(.system(size: 10, weight: .bold)).widgetAccentable()
                    Text(acik ? k.cevap : k.soru).font(.system(.footnote, design: .serif)).lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "brain.head.profile").font(.title3).widgetAccentable()
                }
            case .systemSmall: kucuk(k)
            case .systemMedium: orta(k)
            default: buyuk(k)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "brain.head.profile").font(.title2).foregroundStyle(Tema.hat(.hatirla))
                Text("İlk kürden sonra burada hatırlayacağın kavramlar dönecek.")
                    .font(.caption).multilineTextAlignment(.center).foregroundStyle(Tema.ikincil)
            }
        }
    }

    private var r: Color { Tema.hat(.hatirla) }

    private func cevapAlani(_ k: WHatirla, boy: CGFloat) -> some View {
        Group {
            if acik {
                VStack(alignment: .leading, spacing: 8) {
                    Text(k.cevap).font(.system(size: boy, weight: .semibold, design: .serif)).foregroundStyle(r)
                        .minimumScaleFactor(0.6).lineLimit(2).widgetAccentable()
                    HStack(spacing: 8) {
                        Button(intent: HatirlaCevap(kart: k.id, hatirladi: false)) {
                            Label("Bilemedim", systemImage: "xmark").font(.system(size: 12, weight: .semibold))
                                .frame(maxWidth: .infinity).padding(.vertical, 7)
                                .background(Capsule().fill(Tema.uyari.opacity(0.15))).foregroundStyle(Tema.uyari)
                        }.buttonStyle(.plain)
                        Button(intent: HatirlaCevap(kart: k.id, hatirladi: true)) {
                            Label("Hatırladım", systemImage: "checkmark").font(.system(size: 12, weight: .semibold))
                                .frame(maxWidth: .infinity).padding(.vertical, 7)
                                .background(Capsule().fill(Tema.basari.opacity(0.16))).foregroundStyle(Tema.basari)
                        }.buttonStyle(.plain)
                    }
                }
            } else {
                Button(intent: CevabiGoster()) {
                    HStack(spacing: 6) {
                        Image(systemName: "eye")
                        Text("Önce hatırla, sonra bak")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(Capsule().fill(r.opacity(0.14))).foregroundStyle(r)
                }.buttonStyle(.plain)
            }
        }
    }

    private func kucuk(_ k: WHatirla) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Etiket(metin: "Hatırla", sembol: "brain.head.profile", renk: r)
            if acik {
                Text(k.cevap).font(.system(size: 19, weight: .semibold, design: .serif)).foregroundStyle(r)
                    .minimumScaleFactor(0.6).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                HStack(spacing: 6) {
                    YuvarlakDugme(niyet: HatirlaCevap(kart: k.id, hatirladi: false), sembol: "xmark", renk: Tema.uyari, boy: 34)
                    Spacer()
                    YuvarlakDugme(niyet: HatirlaCevap(kart: k.id, hatirladi: true), sembol: "checkmark", renk: Tema.basari, boy: 34)
                }
            } else {
                Text(k.soru).font(.system(size: 13, design: .serif)).foregroundStyle(Tema.metin)
                    .minimumScaleFactor(0.75).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                HStack {
                    Text("?").font(.system(size: 22, weight: .bold, design: .serif)).foregroundStyle(r.opacity(0.5))
                    Spacer()
                    YuvarlakDugme(niyet: CevabiGoster(), sembol: "eye", renk: r, boy: 34)
                }
            }
        }
    }

    private func orta(_ k: WHatirla) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Etiket(metin: "Hatırla", sembol: "brain.head.profile", renk: r)
                Spacer()
                Text(k.kaynak).font(.system(size: 10, weight: .medium)).foregroundStyle(Tema.soluk).lineLimit(1)
            }
            Text(k.soru).font(.system(size: 15, design: .serif)).foregroundStyle(Tema.metin)
                .minimumScaleFactor(0.75).lineLimit(3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            cevapAlani(k, boy: 18)
        }
    }

    private func buyuk(_ k: WHatirla) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Etiket(metin: "Hatırla", sembol: "brain.head.profile", renk: r)
                Spacer()
                Text("K\(anlik.kademe(.hatirla)) · \(Evre.of(anlik.kademe(.hatirla)).rawValue)")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(Tema.soluk)
            }
            Text(k.kaynak).font(.system(size: 12, weight: .semibold)).foregroundStyle(Tema.renk(k.renk))
            if let b = k.baglam {
                Text(b).font(.system(size: 13)).foregroundStyle(Tema.ikincil).lineLimit(2)
            }
            Text(k.soru).font(.system(size: 21, weight: .regular, design: .serif)).foregroundStyle(Tema.metin)
                .minimumScaleFactor(0.65).frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 4)
                .overlay(alignment: .trailing) {
                    if !acik {
                        Text("?").font(.system(size: 120, weight: .bold, design: .serif))
                            .foregroundStyle(r.opacity(0.10)).offset(y: 6)
                    }
                }
            cevapAlani(k, boy: 26)
            if let o = k.ornek, !o.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Label("AYNI KİTAPTAN", systemImage: "quote.opening").font(.system(size: 10, weight: .bold)).tracking(0.6)
                        .foregroundStyle(Tema.renk(k.renk))
                    Text(o).font(.system(size: 12.5, design: .serif)).foregroundStyle(Tema.metin.opacity(0.85)).lineLimit(3)
                }
            }
        }
    }
}

// MARK: - 3 · Okuma durumu

struct OkumaWidgetGorunum: View {
    let anlik: WidgetAnlik
    var zorla: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var ortamAile
    private var aile: WidgetFamily { zorla ?? ortamAile }

    var suren: [WKitap] {
        let s = anlik.kitaplar.filter(\.suruyor).sorted { $0.son > $1.son }
        return s.isEmpty ? Array(anlik.kitaplar.prefix(4)) : s
    }

    static func renk(_ a: WidgetAnlik) -> Color {
        Tema.renk(a.kitaplar.filter(\.suruyor).sorted { $0.son > $1.son }.first?.renk ?? "amber")
    }

    var body: some View {
        switch aile {
        case .accessoryInline:
            if let k = suren.first { Text("📖 \(k.baslik) %\(k.yuzde)") } else { Text("Teoria") }
        case .accessoryCircular:
            if let k = suren.first {
                Gauge(value: Double(k.yuzde), in: 0...100) {
                    Text(String(k.baslik.prefix(1)))
                } currentValueLabel: {
                    Text("\(k.yuzde)").font(.system(size: 14, weight: .semibold))
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .widgetAccentable()
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 3) {
                ForEach(suren.prefix(2)) { k in
                    HStack(spacing: 6) {
                        Text(k.baslik).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 2)
                        Text("%\(k.yuzde)").font(.system(size: 11)).monospacedDigit()
                    }
                    ProgressView(value: Double(k.yuzde), total: 100).tint(.primary).widgetAccentable()
                }
            }
        case .systemSmall: kucuk
        case .systemMedium: orta
        case .systemExtraLarge: buyuk(genis: true)
        default: buyuk(genis: false)
        }
    }

    private var kucuk: some View {
        let k = suren.first
        let r = Tema.renk(k?.renk)
        return VStack(alignment: .leading, spacing: 8) {
            Etiket(metin: "Okuma", sembol: "book.pages", renk: r)
            ZStack {
                Halka(oran: Double(k?.yuzde ?? 0) / 100, renk: r, kalinlik: 9).widgetAccentable()
                VStack(spacing: 0) {
                    Text("%\(k?.yuzde ?? 0)").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(Tema.metin)
                    Text("\(k?.isaret ?? 0) işaret").font(.system(size: 9, weight: .medium)).foregroundStyle(Tema.ikincil)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(k?.baslik ?? "—").font(.system(size: 12, weight: .semibold, design: .serif)).foregroundStyle(Tema.metin).lineLimit(1)
        }
    }

    private var orta: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Etiket(metin: "Süren kitaplar", sembol: "book.pages", renk: Tema.ikincil)
                Spacer()
                Text("Bu hafta \(anlik.isaretHafta.last ?? 0) işaret").font(.system(size: 10, weight: .medium)).foregroundStyle(Tema.soluk)
            }
            HStack(alignment: .top, spacing: 12) {
                ForEach(suren.prefix(3)) { k in
                    VStack(spacing: 6) {
                        ZStack {
                            Halka(oran: Double(k.yuzde) / 100, renk: Tema.renk(k.renk), kalinlik: 7).widgetAccentable()
                            Text("%\(k.yuzde)").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Tema.metin)
                        }
                        .frame(width: 58, height: 58)
                        Text(k.baslik).font(.system(size: 11, weight: .semibold, design: .serif)).foregroundStyle(Tema.metin)
                            .lineLimit(2).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func buyuk(genis: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Etiket(metin: "Okuma", sembol: "book.pages", renk: Tema.ikincil)
                Spacer()
                Text("\(anlik.kitaplar.count) kitap · \(anlik.kitaplar.reduce(0) { $0 + $1.isaret }) işaret")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(Tema.soluk)
            }
            VStack(spacing: 10) {
                ForEach(suren.prefix(genis ? 6 : 4)) { k in
                    let r = Tema.renk(k.renk)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(k.baslik).font(.system(size: 14, weight: .semibold, design: .serif)).foregroundStyle(Tema.metin).lineLimit(1)
                            Spacer(minLength: 4)
                            Text("%\(k.yuzde)").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(r).monospacedDigit()
                        }
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Tema.cizgi)
                                Capsule().fill(r.gradient).frame(width: max(6, g.size.width * CGFloat(k.yuzde) / 100)).widgetAccentable()
                            }
                        }
                        .frame(height: 6)
                        Text("\(k.isaret) işaret · \(Tarih.goreli(k.son, simdi: anlik.guncel))")
                            .font(.system(size: 10)).foregroundStyle(Tema.soluk)
                    }
                }
            }
            Spacer(minLength: 2)
            VStack(alignment: .leading, spacing: 6) {
                Text("Son 8 hafta · işaretler").font(.system(size: 10, weight: .bold)).foregroundStyle(Tema.soluk)
                let tepe = max(anlik.isaretHafta.max() ?? 1, 1)
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(Array(anlik.isaretHafta.enumerated()), id: \.offset) { i, v in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(i == anlik.isaretHafta.count - 1 ? Tema.vurgu : Tema.vurgu.opacity(0.35))
                            .frame(height: max(3, 34 * CGFloat(v) / CGFloat(tepe)))
                            .frame(maxWidth: .infinity)
                            .widgetAccentable()
                    }
                }
                .frame(height: 34)
                if !anlik.gundem.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles").font(.system(size: 9)).foregroundStyle(Tema.altin)
                        Text(anlik.gundem.prefix(4).joined(separator: " · ")).font(.system(size: 11, weight: .medium, design: .serif))
                            .foregroundStyle(Tema.ikincil).lineLimit(1)
                    }
                }
            }
        }
    }
}

// MARK: - 4 · Kür

struct KurWidgetGorunum: View {
    let anlik: WidgetAnlik
    var zorla: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var ortamAile
    private var aile: WidgetFamily { zorla ?? ortamAile }

    var oran: Double { min(anlik.bugunDakika / Double(max(anlik.hedefDakika, 1)), 1) }
    var bitti: Bool { anlik.bugunDakika >= Double(anlik.hedefDakika) }

    static func renk(_ a: WidgetAnlik) -> Color { Tema.vurgu }

    var body: some View {
        switch aile {
        case .accessoryInline:
            Text(bitti ? "Teoria · bugünkü kür tamam ✓" : "Teoria · \(anlik.hedefDakika) dk kür")
        case .accessoryCircular:
            Gauge(value: oran) {
                Image(systemName: "circle.dashed")
            } currentValueLabel: {
                if bitti { Image(systemName: "checkmark") } else { Text("\(Int(anlik.bugunDakika.rounded()))") }
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 3) {
                Text(bitti ? "Kür tamam" : "Kür · \(Int(anlik.bugunDakika))/\(anlik.hedefDakika) dk").font(.system(size: 12, weight: .semibold))
                ForEach(Hat.allCases) { h in
                    HStack(spacing: 4) {
                        Text(h.ad).font(.system(size: 9)).frame(width: 46, alignment: .leading)
                        KademeCubugu(kademe: anlik.kademe(h), renk: .primary, yukseklik: 3).widgetAccentable()
                    }
                }
            }
        case .systemSmall: kucuk
        case .systemMedium: orta
        default: buyuk
        }
    }

    private var halka: some View {
        ZStack {
            Halka(oran: oran, renk: bitti ? Tema.basari : Tema.vurgu, kalinlik: 10).widgetAccentable()
            VStack(spacing: -2) {
                if bitti {
                    Image(systemName: "checkmark").font(.system(size: 22, weight: .bold)).foregroundStyle(Tema.basari)
                } else {
                    Text("\(Int(anlik.bugunDakika.rounded()))").font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(Tema.metin)
                    Text("/ \(anlik.hedefDakika) dk").font(.system(size: 10, weight: .medium)).foregroundStyle(Tema.ikincil)
                }
            }
        }
    }

    private var haftaNoktalari: some View {
        HStack(spacing: 5) {
            ForEach(Array(anlik.hafta.enumerated()), id: \.offset) { i, v in
                Circle().fill(v > 0 ? Tema.vurgu : Tema.cizgi)
                    .frame(width: i == anlik.hafta.count - 1 ? 8 : 6, height: i == anlik.hafta.count - 1 ? 8 : 6)
                    .widgetAccentable()
            }
        }
    }

    private var kucuk: some View {
        VStack(spacing: 8) {
            HStack {
                Etiket(metin: "Kür", sembol: "circle.dashed.inset.filled", renk: Tema.vurgu)
                Spacer()
            }
            halka.frame(maxWidth: .infinity, maxHeight: .infinity)
            haftaNoktalari
        }
        .widgetURL(URL(string: "teoria://kur"))
    }

    private var orta: some View {
        HStack(spacing: 18) {
            halka.frame(width: 104, height: 104)
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Hat.allCases) { h in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(h.ad).font(.system(size: 12, weight: .semibold)).foregroundStyle(Tema.metin)
                            Spacer()
                            Text("K\(anlik.kademe(h))").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(Tema.hat(h))
                        }
                        KademeCubugu(kademe: anlik.kademe(h), renk: Tema.hat(h), yukseklik: 5).widgetAccentable()
                    }
                }
                HStack {
                    haftaNoktalari
                    Spacer()
                    Text("Bu hafta \(anlik.buHaftaKur) kür").font(.system(size: 10, weight: .medium)).foregroundStyle(Tema.soluk)
                }
            }
        }
        .widgetURL(URL(string: "teoria://kur"))
    }

    private var buyuk: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Etiket(metin: "Teoria", sembol: "sparkle", renk: Tema.vurgu)
                Spacer()
                Text(bitti ? "Bugünün işi tamam" : "Bugün \(anlik.hedefDakika) dakika").font(.system(size: 11, weight: .semibold)).foregroundStyle(Tema.ikincil)
            }
            orta
            GokyuzuMini(oturmus: anlik.oturmus, toplam: anlik.toplamKavram)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Tema.vurgu.opacity(0.06)))
            HStack {
                Image(systemName: "play.fill")
                Text(bitti ? "Bir kür daha" : "Kürü başlat").fontWeight(.semibold)
            }
            .font(.system(size: 14))
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(Capsule().fill(Tema.vurgu)).foregroundStyle(.white)
            .widgetAccentable()
        }
        .widgetURL(URL(string: "teoria://kur"))
    }
}

/// Widget için durağan gökyüzü: oturmuş kavram sayısı kadar parlak yıldız.
struct GokyuzuMini: View {
    let oturmus: Int
    let toplam: Int

    var body: some View {
        Canvas { c, boyut in
            for i in 0..<max(toplam, 1) {
                let x = CGFloat(Gokyuzu.hash(i * 7 + 3)) * boyut.width
                let y = CGFloat(Gokyuzu.hash(i * 13 + 5)) * boyut.height
                let parlak = i < oturmus
                let r: CGFloat = parlak ? 2.6 : 1.2
                let renk: Color = parlak ? Tema.altin : Tema.soluk.opacity(0.5)
                c.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(renk))
                if parlak {
                    c.fill(Path(ellipseIn: CGRect(x: x - r * 3, y: y - r * 3, width: r * 6, height: r * 6)), with: .color(Tema.altin.opacity(0.12)))
                }
            }
        }
        .overlay(alignment: .bottomLeading) {
            Text("\(oturmus) / \(toplam) kavram oturdu").font(.system(size: 10, weight: .semibold)).foregroundStyle(Tema.ikincil).padding(8)
        }
    }
}

enum Gokyuzu {
    /// 0..<say arası belirlenimli indeks (aynı gün aynı seçim).
    static func hashIndeks(_ n: Int, _ say: Int) -> Int { min(say - 1, Int(hash(n) * Double(say))) }

    /// 0…1 arası belirlenimli sözde rastgele (aynı kavram hep aynı yerde doğar).
    static func hash(_ n: Int) -> Double {
        var x = UInt64(truncatingIfNeeded: n &* 2654435761 &+ 1013904223)
        x ^= x >> 13; x = x &* 0x5bd1e995; x ^= x >> 15
        return Double(x % 10_000) / 10_000 * 0.9 + 0.05
    }
}
