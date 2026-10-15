// İlerleme biçimine göre görselleştirme — uygulama ve widget aynı parçaları kullanır.
//   halka    : müfredat a/b — tek bitiş noktası olan süreçler
//   merdiven : basamaklı ilerleme (Teoria'nın 3 hattı × 6 kademe, Mühendis'in 12 alanı)
//   depo     : üretim ile tüketim arasındaki fark (hatlar, Memories tamponu) — eşik çizgisi
//   kitaplik : aynı anda süren birden çok metin (İdrak)
//   akis     : yalnız ritim önemli olan süreçler (Günlük, Kelime Eki) — iz şeridi
import SwiftUI

struct Halka: View {
    var oran: Double
    var renk: Color
    var kalinlik: CGFloat = 6
    var body: some View {
        ZStack {
            Circle().stroke(renk.opacity(0.18), lineWidth: kalinlik)
            Circle().trim(from: 0, to: max(0.001, oran))
                .stroke(renk, style: StrokeStyle(lineWidth: kalinlik, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct NabizHalkasi: View {
    var nabiz: Int
    var boy: CGFloat = 64
    var body: some View {
        ZStack {
            Halka(oran: Double(nabiz) / 100, renk: Tema.nabiz(nabiz), kalinlik: boy * 0.11)
            VStack(spacing: -2) {
                Text("\(nabiz)").font(.yuvarlak(boy * 0.34, .bold)).monospacedDigit()
                Text("nabız").font(.system(size: max(7, boy * 0.12), weight: .medium)).foregroundStyle(.secondary)
            }
        }
        .frame(width: boy, height: boy)
    }
}

struct DurumNoktasi: View {
    var durum: Durum
    var boy: CGFloat = 8
    var body: some View {
        Circle().fill(Tema.durum(durum)).frame(width: boy, height: boy)
            .overlay(durum == .gorunmuyor ? Circle().stroke(Color.gray, style: StrokeStyle(lineWidth: 1, dash: [2])) : nil)
    }
}

/// Son N günün izi — her gün bir sütun; yükseklik = o günün yoğunluğu.
struct IzSeridi: View {
    var iz: [Int]
    var gun: Int = 28
    var renk: Color
    var yukseklik: CGFloat = 18
    var body: some View {
        let parca = Array(iz.suffix(gun))
        let tepe = max(1, parca.max() ?? 1)
        GeometryReader { g in
            let w = g.size.width / CGFloat(max(1, parca.count))
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(parca.indices, id: \.self) { i in
                    let v = parca[i]
                    RoundedRectangle(cornerRadius: 1.2)
                        .fill(v > 0 ? renk.opacity(0.35 + 0.65 * Double(v) / Double(tepe)) : renk.opacity(0.10))
                        .frame(width: max(1, w - 1.2), height: v > 0 ? max(3, yukseklik * CGFloat(v) / CGFloat(tepe)) : 2)
                        .frame(width: w, alignment: .center)
                }
            }
            .frame(height: yukseklik, alignment: .bottom)
        }
        .frame(height: yukseklik)
    }
}

/// 12 haftalık takvim ısı haritası (sütun = hafta, satır = gün).
struct IzTakvimi: View {
    var iz: [Int]
    var renk: Color
    var hucre: CGFloat = 11
    var body: some View {
        let tepe = max(1, iz.max() ?? 1)
        let hafta = Int(ceil(Double(iz.count) / 7))
        HStack(spacing: 3) {
            ForEach(0..<hafta, id: \.self) { h in
                VStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { g in
                        let i = h * 7 + g
                        let v = i < iz.count ? iz[i] : -1
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(v < 0 ? .clear : v == 0 ? Color.primary.opacity(0.07) : renk.opacity(0.3 + 0.7 * Double(v) / Double(tepe)))
                            .frame(width: hucre, height: hucre)
                    }
                }
            }
        }
    }
}

struct MiniCubuk: View {
    var oran: Double
    var renk: Color
    var yukseklik: CGFloat = 5
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(renk.opacity(0.16))
                Capsule().fill(renk).frame(width: max(yukseklik, g.size.width * oran))
            }
        }
        .frame(height: yukseklik)
    }
}

/// Merdiven: her basamak bir sıra; dolu kareler = ulaşılan kademe.
struct Merdiven: View {
    var basamaklar: [Basamak]
    var renk: Color
    var sinir = 6
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(basamaklar.prefix(sinir)) { b in
                HStack(spacing: 6) {
                    Text(b.ad).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading).lineLimit(1)
                    if b.b <= 8 {
                        HStack(spacing: 2) {
                            ForEach(0..<b.b, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(i < b.a ? renk : renk.opacity(0.14))
                                    .frame(height: 8)
                                    .offset(y: CGFloat(-i) * 0.6)
                            }
                        }
                    } else {
                        MiniCubuk(oran: b.oran, renk: renk, yukseklik: 6)
                    }
                    Text("\(b.a)/\(b.b)").font(.system(size: 9, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary).frame(width: 30, alignment: .trailing)
                }
            }
        }
    }
}

/// Depo: üretilen hacim içinde bekleyen (tüketilmemiş) seviye; kırmızı çizgi = birikme eşiği.
struct DepoGorseli: View {
    var ilerleme: Ilerleme?
    var birikme: Birikme?
    var renk: Color
    var body: some View {
        let bekleyen = Double(birikme?.bekleyen ?? 0)
        let olcek = max(Double(birikme?.esik ?? 3) * 2, bekleyen, 1)
        GeometryReader { g in
            let h = g.size.height
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 7).stroke(renk.opacity(0.35), lineWidth: 1.5)
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(colors: [renk.opacity(birikme?.asildi == true ? 0.95 : 0.55), renk.opacity(0.25)],
                                         startPoint: .bottom, endPoint: .top))
                    .frame(height: max(3, h * bekleyen / olcek))
                    .padding(2)
                if let e = birikme?.esik {
                    Rectangle().fill(Tema.durum(.tikali)).frame(height: 1.5)
                        .offset(y: -h * Double(e) / olcek)
                }
            }
        }
    }
}

/// Kitaplık: süren metinler kitap sırtı gibi; sırt boyu = dinlenen yüzde.
struct Kitaplik: View {
    var kitaplar: [Basamak]
    var renk: Color
    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(kitaplar.prefix(6).enumerated()), id: \.offset) { i, k in
                VStack(spacing: 2) {
                    GeometryReader { g in
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 2.5).fill(renk.opacity(0.12))
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(renk.opacity(0.45 + 0.09 * Double(i % 4)))
                                .frame(height: g.size.height * k.oran)
                        }
                    }
                    Text("%\(k.a)").font(.system(size: 7, weight: .semibold).monospacedDigit()).foregroundStyle(.secondary)
                }
                .frame(width: 16)
            }
        }
    }
}

/// Bir sürecin biçimine göre küçük görseli.
struct BicimGorseli: View {
    var s: Surec
    var renk: Color
    var body: some View {
        switch s.bicim {
        case "merdiven": Merdiven(basamaklar: s.basamaklar, renk: renk, sinir: 4)
        case "depo":
            HStack(alignment: .bottom, spacing: 10) {
                DepoGorseli(ilerleme: s.ilerleme, birikme: s.birikme, renk: renk).frame(width: 26, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    if let b = s.birikme {
                        Text("\(b.bekleyen ?? 0)").font(.yuvarlak(20, .bold))
                            .foregroundStyle(b.asildi ? Tema.durum(.tikali) : .primary)
                        Text("\(b.birim) · eşik \(b.esik)").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    if let i = s.ilerleme {
                        Text("\(i.a)/\(i.b) \(i.birim)").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }
        case "kitaplik":
            Kitaplik(kitaplar: s.basamaklar, renk: renk).frame(height: 44)
        case "halka":
            HStack(spacing: 10) {
                Halka(oran: s.ilerleme?.oran ?? 0, renk: renk, kalinlik: 5).frame(width: 40, height: 40)
                    .overlay(Text("%\(Int((s.ilerleme?.oran ?? 0) * 100))").font(.system(size: 10, weight: .bold).monospacedDigit()))
                if let i = s.ilerleme {
                    Text("\(i.a)/\(i.b)\n\(i.birim)").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        default:
            IzTakvimi(iz: Array(s.iz.suffix(56)), renk: renk, hucre: 7)
        }
    }
}
