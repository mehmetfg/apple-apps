// Ortak parçalar: telefon çerçevesi, kilit/ana ekran katmanları, widget önizlemesi, çipler, kartlar.
import SwiftUI
import WidgetKit

/// Telefon biçiminde çerçeve; içerik ekran oranında (430×932) çizilir, verilen yüksekliğe ölçeklenir.
struct Telefon<Icerik: View>: View {
    var yukseklik: CGFloat
    @ViewBuilder var icerik: (CGFloat) -> Icerik

    var body: some View {
        let oran = Cizer.ekran.width / Cizer.ekran.height
        let gen = yukseklik * oran
        let u = gen / 430
        icerik(u)
            .frame(width: gen, height: yukseklik)
            .clipShape(RoundedRectangle(cornerRadius: 56 * u, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 56 * u, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: max(1, 5 * u))
            )
            .overlay(alignment: .top) {
                Capsule().fill(.black).frame(width: 124 * u, height: 36 * u).padding(.top, 11 * u)
            }
            .shadow(color: .black.opacity(0.5), radius: 18 * u, y: 10 * u)
    }
}

struct KilitKatmani: View {
    var u: CGFloat
    var tarih: Date = .now

    var body: some View {
        VStack(spacing: 0) {
            Text(tarih.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "tr_TR"))))
                .font(.system(size: 20 * u, weight: .semibold))
                .padding(.top, 72 * u)
            Text(tarih.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
                .font(.system(size: 104 * u, weight: .semibold, design: .rounded))
                .lineLimit(1).fixedSize()
                .padding(.top, -6 * u)
            HStack(spacing: 10 * u) {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 18 * u).fill(.white.opacity(0.13)).frame(width: 74 * u, height: 70 * u)
                }
                RoundedRectangle(cornerRadius: 18 * u).fill(.white.opacity(0.13)).frame(width: 158 * u, height: 70 * u)
            }
            .padding(.top, 4 * u)
            Spacer()
            HStack {
                Circle().fill(.black.opacity(0.35)).frame(width: 50 * u, height: 50 * u)
                    .overlay(Image(systemName: "flashlight.off.fill").font(.system(size: 18 * u)))
                Spacer()
                Circle().fill(.black.opacity(0.35)).frame(width: 50 * u, height: 50 * u)
                    .overlay(Image(systemName: "camera.fill").font(.system(size: 18 * u)))
            }
            .padding(.horizontal, 46 * u)
            Capsule().fill(.white).frame(width: 140 * u, height: 5 * u).padding(.top, 22 * u).padding(.bottom, 10 * u)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.25), radius: 6 * u)
    }
}

struct AnaKatmani: View {
    var u: CGFloat
    var widgetler: [AnyView] = []

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 70 * u)
            if !widgetler.isEmpty {
                VStack(spacing: 22 * u) { ForEach(widgetler.indices, id: \.self) { widgetler[$0] } }
                    .padding(.horizontal, 28 * u)
                    .padding(.bottom, 24 * u)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 26 * u), count: 4), spacing: 30 * u) {
                ForEach(0..<(widgetler.isEmpty ? 20 : 8), id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 15 * u, style: .continuous).fill(.white.opacity(0.17))
                        .frame(width: 64 * u, height: 64 * u)
                }
            }
            .padding(.horizontal, 28 * u)
            Spacer()
            HStack(spacing: 26 * u) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 15 * u, style: .continuous).fill(.white.opacity(0.22)).frame(width: 64 * u, height: 64 * u)
                }
            }
            .padding(14 * u)
            .background(RoundedRectangle(cornerRadius: 34 * u, style: .continuous).fill(.white.opacity(0.12)))
            .padding(.bottom, 14 * u)
        }
    }
}

/// Uygulamada widget'ın kendisi gibi: zemin + yüz, köşe yarıçapı ve kenar boşluğu sistemdekiyle aynı.
struct WidgetOnizleme: View {
    var t: WidgetTasarim
    var g: Gosterilen
    var aile: WidgetFamily
    var tarih: Date = .now
    var veri: VitrinVeri
    var bilinen: Set<String>
    var cevrik = false

    var body: some View {
        let s = WidgetOlcu.boy(aile)
        if WidgetOlcu.kilit.contains(aile) {
            WidgetGorunum(t: t, g: g, aile: aile, tarih: tarih, cevrik: cevrik, veri: veri, bilinen: bilinen, canli: false)
                .foregroundStyle(.white)
                .frame(width: s.width, height: s.height)
        } else {
            WidgetGorunum(t: t, g: g, aile: aile, tarih: tarih, cevrik: cevrik, veri: veri, bilinen: bilinen, canli: false)
                .padding(16)
                .frame(width: s.width, height: s.height)
                .background(ZeminGorunum(zemin: t.zemin, fotoBoyu: 900))
                .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
        }
    }
}

struct Cip: View {
    var ad: String
    var simge: String? = nil
    var secili: Bool
    var eylem: () -> Void

    var body: some View {
        Button(action: eylem) {
            HStack(spacing: 6) {
                if let simge { Image(systemName: simge).font(.system(size: 12, weight: .semibold)) }
                Text(ad).font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().fill(secili ? Renkler.vurgu : Renkler.kart2))
            .foregroundStyle(secili ? Color.black : Color.white)
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: secili)
    }
}

struct Baslik: View {
    var ad: String
    var alt: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ad).font(.system(.title3, design: .serif).weight(.semibold))
            if let alt { Text(alt).font(.footnote).foregroundStyle(Renkler.ikincil) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Kart<Icerik: View>: View {
    @ViewBuilder var icerik: Icerik
    var body: some View {
        icerik
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Renkler.kart))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Renkler.cizgi))
    }
}

struct Kaydirici: View {
    var ad: String
    @Binding var deger: Double
    var aralik: ClosedRange<Double>
    var bicim: (Double) -> String = { String(format: "%.0f%%", $0 * 100) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(ad).font(.subheadline)
                Spacer()
                Text(bicim(deger)).font(.footnote.monospacedDigit()).foregroundStyle(Renkler.ikincil)
            }
            Slider(value: $deger, in: aralik)
        }
    }
}

/// Hareketli önizleme: faz 0→1, `sure` saniyede bir döner
struct Canli<Icerik: View>: View {
    var acik: Bool
    var sure: Double = 6
    @ViewBuilder var icerik: (Double) -> Icerik

    var body: some View {
        if acik {
            TimelineView(.animation(minimumInterval: 1 / 30)) { z in
                icerik(z.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: sure) / sure)
            }
        } else {
            icerik(0)
        }
    }
}
