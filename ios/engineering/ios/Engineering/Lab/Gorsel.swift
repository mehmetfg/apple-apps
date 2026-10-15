import SwiftUI

// Bir karenin çizimi. Renk dili her yerde aynı (Tema): kehribar karşılaştır, mercan takas, mor pivot,
// gök yaz/anahtar, su yeşili en küçük/sınır, adaçayı yerinde.

struct CubukAlani: View {
    let kare: Kare
    let maks: Int
    var degerler = true

    var body: some View {
        GeometryReader { g in
            let n = max(kare.dizi.count, 1)
            let ara: CGFloat = n > 24 ? 2 : (n > 14 ? 3 : 5)
            let w = max(2, (g.size.width - ara * CGFloat(n - 1)) / CGFloat(n))
            let yazili = degerler && w >= 14
            let tepe = g.size.height - (yazili ? 16 : 0)
            HStack(alignment: .bottom, spacing: ara) {
                ForEach(0..<kare.dizi.count, id: \.self) { i in
                    let v = kare.dizi[i]
                    VStack(spacing: 3) {
                        Spacer(minLength: 0)
                        if yazili {
                            Text(v == 0 ? " " : "\(v)")
                                .font(.system(size: w > 26 ? 12 : 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(kare.isaret[i] != nil ? renk(i) : Tema.soluk)
                                .lineLimit(1).minimumScaleFactor(0.6)
                        }
                        RoundedRectangle(cornerRadius: min(6, w / 3), style: .continuous)
                            .fill(renk(i))
                            .frame(height: v == 0 ? 0 : max(4, tepe * CGFloat(v) / CGFloat(max(maks, 1))))
                    }
                    .frame(width: w)
                    .opacity(soluk(i) ? 0.3 : 1)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    private func renk(_ i: Int) -> Color {
        if let s = kare.isaret[i] { return Tema.renk(s) }
        if kare.sirali.contains(i) { return Tema.sirali }
        return Tema.cubuk
    }

    private func soluk(_ i: Int) -> Bool {
        if kare.isaret[i] != nil { return false }
        if let r = kare.aralik, !r.contains(i), !kare.sirali.contains(i) { return true }
        return false
    }
}

/// Merge'ün tamponu (küçük çubuklar) ya da counting'in sayaçları (kutular).
struct EkSerit: View {
    let kare: Kare
    let maks: Int
    let sayac: Bool

    var body: some View {
        if let ek = kare.ek {
            if sayac {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(0..<ek.count, id: \.self) { v in
                            VStack(spacing: 2) {
                                Text("\(ek[v])")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .frame(width: 30, height: 30)
                                    .background(kare.ekIsaret.contains(v) ? Tema.karsilastir.opacity(0.35) : Tema.kart2,
                                                in: RoundedRectangle(cornerRadius: 7))
                                Text("\(v)").font(.system(size: 9, design: .monospaced)).foregroundStyle(Tema.soluk)
                            }
                        }
                    }
                }
            } else {
                GeometryReader { g in
                    let n = ek.count
                    let w = max(2, (g.size.width - 3 * CGFloat(n - 1)) / CGFloat(n))
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(0..<n, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(kare.ekIsaret.contains(i) ? Tema.karsilastir : Tema.cubuk.opacity(ek[i] == 0 ? 0 : 0.55))
                                .frame(width: w, height: ek[i] == 0 ? 0 : max(3, g.size.height * CGFloat(ek[i]) / CGFloat(max(maks, 1))))
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
    }
}

/// Heap'i ağaç olarak çizer: dizinin içindeki ağaç. Yalnız heap bölgesi (heapBoyu) ağaçta durur.
struct HeapAgaci: View {
    let kare: Kare

    var body: some View {
        GeometryReader { g in
            let n = kare.heapBoyu ?? kare.dizi.count
            let seviye = max(1, Int(log2(Double(max(n, 1)))) + 1)
            let h = g.size.height / CGFloat(seviye)
            let r = min(15, h / 2.6)
            ZStack {
                Path { p in
                    for i in 1..<max(n, 1) where i < n {
                        p.move(to: konum(i, g.size, h)); p.addLine(to: konum((i - 1) / 2, g.size, h))
                    }
                }
                .stroke(Tema.cizgi, lineWidth: 1.5)
                ForEach(0..<n, id: \.self) { i in
                    Text("\(kare.dizi[i])")
                        .font(.system(size: r * 0.85, weight: .bold, design: .rounded))
                        .foregroundStyle(kare.isaret[i] != nil ? Color.white : Tema.murekkep)
                        .frame(width: r * 2, height: r * 2)
                        .background(kare.isaret[i].map { Tema.renk($0) } ?? Tema.kart2, in: Circle())
                        .overlay(Circle().strokeBorder(Tema.cizgi, lineWidth: 0.5))
                        .position(konum(i, g.size, h))
                }
            }
        }
    }

    private func konum(_ i: Int, _ s: CGSize, _ h: CGFloat) -> CGPoint {
        let lv = Int(log2(Double(i + 1)))
        let ilk = (1 << lv) - 1
        let say = 1 << lv
        let x = (CGFloat(i - ilk) + 0.5) / CGFloat(say) * s.width
        return CGPoint(x: x, y: h * (CGFloat(lv) + 0.5))
    }
}

/// Python kodu, yanan satırla. Etiket → satır eşlemesi dersin JSON'undan gelir.
struct KodPaneli: View {
    let kod: Kod
    var satir: Int? = nil
    var yukseklik: CGFloat = 170

    var body: some View {
        ScrollViewReader { okuyucu in
            ScrollView([.vertical, .horizontal], showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(kod.satirlar.enumerated()), id: \.offset) { i, s in
                        HStack(spacing: 10) {
                            Text("\(i + 1)").foregroundStyle(Tema.kodYazi.opacity(0.35)).frame(width: 18, alignment: .trailing)
                            Text(s.isEmpty ? " " : s).foregroundStyle(Tema.kodYazi)
                            Spacer(minLength: 0)
                        }
                        .font(Tema.kodKucuk)
                        .padding(.vertical, 2.5).padding(.horizontal, 8)
                        .background(satir == i + 1 ? Tema.vurgu.opacity(0.32) : .clear)
                        .id(i + 1)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(height: yukseklik)
            .background(Tema.kodZemin, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onChange(of: satir) { _, s in
                guard let s else { return }
                withAnimation(.easeInOut(duration: 0.2)) { okuyucu.scrollTo(s, anchor: .center) }
            }
        }
    }
}

struct Sayaclar: View {
    let kare: Kare
    var adim: (Int, Int)? = nil
    var body: some View {
        HStack(spacing: 14) {
            sayi("\(kare.karsilastirma)", "compares", Tema.karsilastir)
            sayi("\(kare.yazma)", "writes", Tema.takas)
            if let (i, n) = adim {
                Spacer()
                Text("\(i)/\(n)").font(.system(.caption, design: .monospaced)).foregroundStyle(Tema.soluk)
            }
        }
    }
    private func sayi(_ d: String, _ ad: String, _ r: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(r).frame(width: 7, height: 7)
            Text(d).font(.system(.subheadline, design: .rounded, weight: .bold)).monospacedDigit()
            Text(ad).font(.caption).foregroundStyle(Tema.soluk)
        }
    }
}

/// Bir karenin tam sahnesi: çubuklar + (heap ağacı) + (tampon/sayaç) — İzle ve CPU oyunu paylaşır.
struct Sahne: View {
    let algoritma: Algoritma
    let kare: Kare
    let maks: Int
    var yukseklik: CGFloat = 190
    var agac = true

    var body: some View {
        VStack(spacing: 10) {
            if agac && algoritma == .heap && kare.dizi.count <= 15 {
                HeapAgaci(kare: kare).frame(height: 128)
            }
            CubukAlani(kare: kare, maks: maks).frame(height: agac && algoritma == .heap ? yukseklik * 0.62 : yukseklik)
            if kare.ek != nil {
                EkSerit(kare: kare, maks: maks, sayac: algoritma == .counting)
                    .frame(height: algoritma == .counting ? 46 : 42)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: kare)
    }
}
