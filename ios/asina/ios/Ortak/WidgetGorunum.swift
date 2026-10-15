// Widget görünümleri — widget'ın kendisi ve (yalnız DEBUG'da) uygulamanın ön izleme çizicisi ortak kullanır.
//
// Tasarım: koyu kipte Apple'ın kendi widget'ları gibi derin, neredeyse siyah zemin; üstünde bandın rengiyle
// soluk bir ışıma (Hava Durumu / Müzik'teki gibi) ve sağ altta dev bir filigran harf. Kelime beyaz ve iri,
// anlam bandın rengiyle. Açık kipte kâğıt zemin + aynı ışıma. Deyimsel fiiller gök mavisi.
import WidgetKit
import SwiftUI
import AppIntents

struct Giris: TimelineEntry {
    let date: Date
    let kelime: WKelime?
    let sonrakiler: [WKelime]
    let anlik: Anlik?
    let acik: Bool
    let onceHatirla: Bool
}

// MARK: Zeminler

struct KelimeZemini: View {
    let c: String
    let pv: Bool
    let harf: String
    @Environment(\.colorScheme) private var sema

    var body: some View {
        let ton = R.ton(c, pv: pv)
        let koyu = sema == .dark
        ZStack {
            if koyu {
                LinearGradient(colors: [Color.hex(R.derin(c, pv: pv)), Color.hex(0x050508)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [ton.opacity(0.42), .clear], center: .topLeading, startRadius: 2, endRadius: 300)
                RadialGradient(colors: [ton.opacity(0.16), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 220)
            } else {
                R.yuzey
                LinearGradient(colors: [ton.opacity(0.20), ton.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [ton.opacity(0.20), .clear], center: .topLeading, startRadius: 2, endRadius: 280)
            }
            Color.clear.overlay(alignment: .bottomTrailing) {
                if !harf.isEmpty {
                    Text(harf)
                        .font(.system(size: 330, weight: .black, design: .serif))
                        .foregroundStyle((koyu ? Color.white : ton).opacity(koyu ? 0.055 : 0.07))
                        .offset(x: 48, y: 96)
                        .fixedSize()
                }
            }
            .clipped()
        }
    }
}

struct IlerlemeZemini: View {
    @Environment(\.colorScheme) private var sema
    var body: some View {
        if sema == .dark {
            ZStack {
                LinearGradient(colors: [Color.hex(0x1B120F), Color.hex(0x050508)], startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [R.vurgu.opacity(0.30), .clear], center: .topTrailing, startRadius: 2, endRadius: 200)
            }
        } else {
            ZStack {
                R.yuzey
                RadialGradient(colors: [R.vurgu.opacity(0.14), .clear], center: .topTrailing, startRadius: 2, endRadius: 200)
            }
        }
    }
}

// MARK: Kelime

struct KelimeGorunumu: View {
    let g: Giris
    var zorla: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var ortamAilesi
    @Environment(\.colorScheme) private var sema
    var aile: WidgetFamily { zorla ?? ortamAilesi }

    private var koyu: Bool { sema == .dark }
    private var gizli: Bool { g.onceHatirla && !g.acik }
    private var ana: Color { koyu ? .white : R.murekkep }
    private var ikinci: Color { koyu ? Color.white.opacity(0.62) : R.ikincil }
    private var soluk: Color { koyu ? Color.white.opacity(0.42) : R.soluk }

    var body: some View {
        if let k = g.kelime {
            switch aile {
            case .systemSmall: kucuk(k)
            case .systemMedium: orta(k)
            case .systemLarge: buyuk(k)
            case .accessoryRectangular: kilitDikdortgen(k)
            case .accessoryInline: Text("\(k.w) · \(gizli ? "?" : k.tr)")
            case .accessoryCircular: kilitYuvarlak
            default: kucuk(k)
            }
        } else {
            VStack(spacing: 6) {
                Text("aşina").font(.kelime(22)).foregroundStyle(R.vurgu)
                Text("Uygulamayı bir kez aç").font(.caption2).foregroundStyle(ikinci)
            }
        }
    }

    // MARK: parçalar

    private func ton(_ k: WKelime) -> Color { R.ton(k.c, pv: k.pv) }
    private func vurguRengi(_ k: WKelime) -> Color { k.pv ? R.pv : R.vurgu }

    private func rozet(_ k: WKelime) -> some View {
        HStack(spacing: 5) {
            Text(k.pv ? "DEYİMSEL" : (k.c.isEmpty ? "—" : k.c))
                .font(.system(size: 10, weight: .heavy)).tracking(k.pv ? 0.5 : 0)
                .foregroundStyle(ton(k))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(ton(k).opacity(koyu ? 0.22 : 0.15), in: Capsule())
            if k.asama < 0 {
                Text("YENİ").font(.system(size: 9, weight: .heavy)).tracking(0.4).foregroundStyle(R.vurgu)
            }
        }
    }

    private func anlam(_ k: WKelime, _ boyut: CGFloat) -> some View {
        Group {
            if gizli {
                Text("• • •").font(.system(size: boyut, weight: .bold, design: .rounded)).foregroundStyle(soluk)
            } else {
                Text(k.tr).font(.system(size: boyut, weight: .bold, design: .rounded)).foregroundStyle(vurguRengi(k))
            }
        }
    }

    private func dugme<I: AppIntent>(_ simge: String, _ niyet: I, _ boyut: CGFloat, vurgulu: Bool = false,
                                     _ renk: Color = R.vurgu) -> some View {
        Button(intent: niyet) {
            Image(systemName: simge)
                .font(.system(size: boyut * 0.42, weight: .bold))
                .foregroundStyle(vurgulu ? Color.white : ana)
                .frame(width: boyut, height: boyut)
                .background(Circle().fill(vurgulu ? renk : (koyu ? Color.white.opacity(0.14) : Color.black.opacity(0.06))))
        }
        .buttonStyle(.plain)
    }

    private func ses(_ k: WKelime, _ boyut: CGFloat) -> some View {
        dugme("speaker.wave.2.fill", SeslendirKelime(kelime: k.w, ses: k.au), boyut, vurgulu: true, ton(k))
    }

    private func halka(_ boyut: CGFloat) -> some View {
        let a = g.anlik
        let hedef = max(1, a?.bugunHedef ?? 1)
        let oran = min(1, Double(a?.bugunYapilan ?? 0) / Double(hedef))
        return ZStack {
            Circle().stroke(ana.opacity(0.14), lineWidth: 3.5)
            Circle().trim(from: 0, to: oran)
                .stroke(oran >= 1 ? R.dogru : R.vurgu, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if oran >= 1 {
                Image(systemName: "checkmark").font(.system(size: boyut * 0.34, weight: .bold)).foregroundStyle(R.dogru)
            } else {
                Text("\(max(0, hedef - (a?.bugunYapilan ?? 0)))")
                    .font(.system(size: boyut * 0.36, weight: .bold, design: .rounded)).foregroundStyle(ana)
            }
        }
        .frame(width: boyut, height: boyut)
    }

    private func altYazi(_ k: WKelime) -> String {
        k.pv ? "deyimsel fiil" : (k.ipa.isEmpty ? k.p : "\(k.ipa) · \(k.p)")
    }

    // MARK: küçük

    private func kucuk(_ k: WKelime) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                rozet(k)
                Spacer(minLength: 0)
                ses(k, 30)
            }
            Spacer(minLength: 0)
            Text(k.w).font(.kelime(28, .bold)).foregroundStyle(ana)
                .minimumScaleFactor(0.4).lineLimit(1)
                .shadow(color: koyu ? ton(k).opacity(0.5) : .clear, radius: 8)
            Text(k.pv ? "deyimsel fiil" : k.ipa).font(.system(size: 11)).foregroundStyle(soluk).lineLimit(1)
            anlam(k, 15).lineLimit(2).minimumScaleFactor(0.75).padding(.top, 3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: "asina://kelime/\(k.i)"))
    }

    // MARK: orta

    private func orta(_ k: WKelime) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                rozet(k)
                Spacer(minLength: 0)
                Text(k.w).font(.kelime(36, .bold)).foregroundStyle(ana)
                    .minimumScaleFactor(0.4).lineLimit(1)
                    .shadow(color: koyu ? ton(k).opacity(0.5) : .clear, radius: 9)
                Text(altYazi(k)).font(.system(size: 11)).foregroundStyle(soluk).lineLimit(1)
                anlam(k, 17).lineLimit(2).minimumScaleFactor(0.75).padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                if let x = k.x, !gizli {
                    HStack(alignment: .top, spacing: 8) {
                        RoundedRectangle(cornerRadius: 1.5).fill(ton(k)).frame(width: 3)
                        Text(Vurgu.metin(x, k.w, renk: ton(k)))
                            .font(.kelime(12.5, .regular)).foregroundStyle(ikinci)
                            .lineLimit(5).minimumScaleFactor(0.85)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(gizli ? "Anlamını hatırlamaya çalış, sonra göze dokun." : k.d)
                        .font(.system(size: 12)).foregroundStyle(ikinci).lineLimit(5)
                }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    ses(k, 32)
                    if g.onceHatirla { dugme(g.acik ? "eye.slash" : "eye", AnlaminiGoster(), 32) }
                    dugme("chevron.right", SonrakiKelime(), 32)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .widgetURL(URL(string: "asina://kelime/\(k.i)"))
    }

    // MARK: büyük

    private func buyuk(_ k: WKelime) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                rozet(k)
                Spacer()
                halka(30)
            }
            Spacer(minLength: 2)
            Text(k.w)
                .font(.kelime(60, .bold)).foregroundStyle(ana)
                .minimumScaleFactor(0.38).lineLimit(1)
                .shadow(color: koyu ? ton(k).opacity(0.65) : ton(k).opacity(0.18), radius: koyu ? 16 : 10, y: 2)
            HStack(alignment: .center) {
                Text(altYazi(k)).font(.system(size: 13, weight: .medium)).foregroundStyle(soluk).lineLimit(1)
                Spacer()
                ses(k, 40)
            }
            .padding(.top, 2)
            anlam(k, 26).lineLimit(2).minimumScaleFactor(0.7).padding(.top, 6)
            if let x = k.x, !gizli {
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 2).fill(ton(k)).frame(width: 3)
                    Text(Vurgu.metin(x, k.w, renk: ton(k)))
                        .font(.kelime(15, .regular)).foregroundStyle(ikinci)
                        .lineLimit(3).minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(11)
                .background(koyu ? Color.white.opacity(0.07) : ton(k).opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 10)
            } else if gizli {
                Text("Önce hatırlamaya çalış, sonra göze dokun.")
                    .font(.system(size: 13)).foregroundStyle(soluk).padding(.top, 10)
            }
            Spacer(minLength: 6)
            HStack(spacing: 8) {
                Text("SIRADA").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(soluk)
                ForEach(g.sonrakiler.prefix(2)) { s in
                    Text(s.w).font(.kelime(12.5, .medium)).foregroundStyle(ikinci)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(koyu ? Color.white.opacity(0.09) : Color.black.opacity(0.05), in: Capsule())
                }
                Spacer(minLength: 0)
                if g.onceHatirla { dugme(g.acik ? "eye.slash" : "eye", AnlaminiGoster(), 34) }
                dugme("chevron.right", SonrakiKelime(), 34)
            }
        }
        .widgetURL(URL(string: "asina://kelime/\(k.i)"))
    }

    // MARK: kilit ekranı

    private func kilitDikdortgen(_ k: WKelime) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(k.w).font(.kelime(17)).widgetAccentable().lineLimit(1).minimumScaleFactor(0.6)
            Text(gizli ? altYazi(k) : k.tr).font(.system(size: 13)).lineLimit(1)
            if let x = k.x, !gizli {
                Text(x).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text(altYazi(k)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(URL(string: "asina://kelime/\(k.i)"))
    }

    private var kilitYuvarlak: some View {
        let a = g.anlik
        let hedef = max(1, a?.bugunHedef ?? 1)
        return Gauge(value: Double(min(a?.bugunYapilan ?? 0, hedef)), in: 0...Double(hedef)) {
            Text("aş")
        } currentValueLabel: {
            Text("\(max(0, hedef - (a?.bugunYapilan ?? 0)))")
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }
}

// MARK: İlerleme

struct IlerlemeGorunumu: View {
    let a: Anlik?
    var zorla: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var ortamAilesi
    @Environment(\.colorScheme) private var sema
    var aile: WidgetFamily { zorla ?? ortamAilesi }

    var body: some View {
        let koyu = sema == .dark
        let ana: Color = koyu ? .white : R.murekkep
        let yapilan = a?.bugunYapilan ?? 0
        let hedef = max(1, a?.bugunHedef ?? 1)
        let oran = min(1, Double(yapilan) / Double(hedef))
        if aile == .accessoryCircular {
            Gauge(value: oran) { Image(systemName: "flame") } currentValueLabel: { Text("\(a?.seri ?? 0)") }
                .gaugeStyle(.accessoryCircular)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ZStack {
                        Circle().stroke(R.vurgu.opacity(0.18), lineWidth: 7)
                        Circle().trim(from: 0, to: oran)
                            .stroke(oran >= 1 ? R.dogru : R.vurgu, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        if oran >= 1 {
                            Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).foregroundStyle(R.dogru)
                        } else {
                            Text("\(hedef - yapilan)").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(ana)
                        }
                    }
                    .frame(width: 52, height: 52)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Label("\(a?.seri ?? 0)", systemImage: "flame.fill")
                            .font(.system(size: 14, weight: .bold)).foregroundStyle(R.vurgu)
                        Text("gün").font(.system(size: 10)).foregroundStyle(koyu ? Color.white.opacity(0.5) : R.soluk)
                    }
                }
                Spacer(minLength: 0)
                Text("\(a?.asina ?? 0) aşina · \(a?.oturmus ?? 0) oturmuş")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(koyu ? Color.white.opacity(0.65) : R.ikincil)
                    .lineLimit(1).minimumScaleFactor(0.8)
                let h = a?.hafta ?? Array(repeating: 0, count: 7)
                let enCok = max(5, h.max() ?? 0)
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(h.enumerated()), id: \.offset) { i, d in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(d > 0 ? R.vurgu.opacity(i == 6 ? 1 : 0.5) : ana.opacity(0.12))
                            .frame(height: max(4, 26 * CGFloat(d) / CGFloat(enCok)))
                    }
                }
                .frame(height: 26, alignment: .bottom)
            }
            .widgetURL(URL(string: "asina://bugun"))
        }
    }
}
