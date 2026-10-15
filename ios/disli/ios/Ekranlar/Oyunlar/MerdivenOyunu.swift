// MERDİVEN — "Bir adım geri" yasasının oyunu. Aktarılan söz, koşul tipleri, wish ve zaman aynı merdiveni iner.
// Bir basamaktaki cümleyi görürsün; bir alttakinin fiil yuvalarını taşlarla doldurursun.
import SwiftUI

struct MerdivenOyunu: View {
    @Environment(\.dismiss) private var kapat
    @Environment(Depo.self) private var depo
    @State private var zincirler: [Merdiven] = []
    @State private var zi = 0
    @State private var bi = 1
    @State private var dizi: [Tas] = []
    @State private var banka: [Tas] = []
    @State private var sonuc: Bool?
    @State private var dogrular = 0
    @State private var toplam = 0
    @State private var bitti = false
    private let zincirSayisi = 6
    private let renk = Oyun.merdiven.renk

    private var z: Merdiven? { zincirler[safe: zi] }

    var body: some View {
        if bitti {
            OyunSonu(oyun: .merdiven, buyuk: "\(dogrular)/\(toplam)", aciklama: "basamak ilk denemede indi",
                     ders: "Aktarırken, hayal kurarken ve 'keşke' derken aynı hareketi yaptın: fiili bir basamak aşağı indirdin. am → was · will → would · did → had done.",
                     tekrar: { bitti = false; kur() }, kapat: { kapat() })
        } else {
            VStack(spacing: 12) {
                OyunUstu(baslik: "Merdiven", alt: z.map { "\(turAdi($0.tur)) · \($0.ad)" }, renk: renk,
                         ilerleme: Double(zi) / Double(zincirSayisi)) { kapat() }
                if let z {
                    ScrollView {
                        VStack(spacing: 16) {
                            merdiven(z)
                            if let sonuc {
                                geriBildirim(z, sonuc)
                            } else {
                                TasTezgahi(dizi: $dizi, banka: $banka, renk: renk)
                                HStack {
                                    Text("Yuvaları sırayla doldur").font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Temizle") { withAnimation { banka += dizi; dizi = [] } }.disabled(dizi.isEmpty).font(.subheadline)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                    .onChange(of: dizi) { _, d in if sonuc == nil, d.count == cevap(z).count { denetle(z) } }
                }
            }
            .background(Lekeler(renkler: [renk, Tema.renk("mor"), Tema.renk("kehribar")]))
            .onAppear { if zincirler.isEmpty { kur() } }
        }
    }

    // MARK: Merdiven çizimi

    private func merdiven(_ z: Merdiven) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(z.basamaklar.enumerated()), id: \.offset) { n, b in
                HStack(alignment: .center, spacing: 10) {
                    // korkuluk + basamak
                    VStack(spacing: 0) {
                        Rectangle().fill(renk.opacity(0.35)).frame(width: 3)
                        Circle().fill(n < bi || (n == bi && sonuc == true) ? renk : renk.opacity(0.25)).frame(width: 14, height: 14)
                        Rectangle().fill(renk.opacity(0.35)).frame(width: 3)
                    }
                    .frame(width: 14)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(basamakAdi(z.tur, n)).font(.caption2.weight(.bold)).textCase(.uppercase).foregroundStyle(renk)
                        if n < bi || (n == bi && sonuc != nil) {
                            Text(dolu(b)).font(Tema.ingilizce(.title3)).fixedSize(horizontal: false, vertical: true)
                        } else if n == bi {
                            Text(yuvali(b)).font(Tema.ingilizce(.title3)).fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("· · ·").font(.title3).foregroundStyle(.tertiary)
                        }
                        if n >= 1 && (n < bi || (n == bi && sonuc != nil)) {
                            Text(z.notlar[n - 1]).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(n == bi && sonuc == nil ? renk.opacity(0.1) : Tema.yuzey))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(n == bi ? renk.opacity(0.6) : .clear, lineWidth: 1.5))
                    .padding(.leading, CGFloat(n) * 14)   // basamaklar aşağı doğru iner
                    .opacity(n > bi ? 0.5 : 1)
                }
                .padding(.vertical, 4)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: bi)
    }

    /// Önceki ve tamamlanmış basamak: yuvalar renkli
    private func dolu(_ b: String) -> AttributedString {
        let (p, y) = Metin.yuvalar(b)
        var s = AttributedString()
        for (n, parca) in p.enumerated() {
            s += AttributedString(parca)
            if let w = y[safe: n] {
                var a = AttributedString(w); a.foregroundColor = renk; a.font = Tema.ingilizce(.title3, .bold); s += a
            }
        }
        return s
    }

    /// Çalışılan basamak: yuvalara yerleşen taşlar
    private func yuvali(_ b: String) -> AttributedString {
        let (p, y) = Metin.yuvalar(b)
        var kalan = dizi.map(\.metin)[...]
        var s = AttributedString()
        for (n, parca) in p.enumerated() {
            s += AttributedString(parca)
            if let w = y[safe: n] {
                let k = w.split(separator: " ").count
                let yer = kalan.prefix(k); kalan = kalan.dropFirst(k)
                let metin = yer.isEmpty ? String(repeating: "_", count: max(4, w.count)) : yer.joined(separator: " ") + (yer.count < k ? " _" : "")
                var a = AttributedString(metin); a.foregroundColor = renk; a.font = Tema.ingilizce(.title3, .bold)
                a.backgroundColor = renk.opacity(0.12)
                s += a
            }
        }
        return s
    }

    private func geriBildirim(_ z: Merdiven, _ d: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(d ? "Bir basamak indi" : "Doğrusu", systemImage: d ? "checkmark.seal.fill" : "arrow.down.circle.fill")
                .font(.headline).foregroundStyle(d ? Tema.dogru : Tema.renk("turuncu"))
            if !d { Text(Metin.koseliSil(z.basamaklar[bi])).font(Tema.ingilizce(.title3, .semibold)) }
            Button { ilerle(z) } label: {
                Text(bi + 1 < z.basamaklar.count ? "Bir basamak daha" : "Sonraki merdiven")
                    .font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 50)
                    .background(Capsule().fill(renk))
            }
            .buttonStyle(.plain)
        }
        .kart(16)
    }

    // MARK: Akış

    private func kur() {
        // türleri karıştır: her türden en az bir zincir
        let gruplar = Dictionary(grouping: depo.veri.merdiven.shuffled(), by: \.tur)
        var secim = gruplar.values.compactMap(\.first)
        let geri = depo.veri.merdiven.shuffled().filter { m in !secim.contains(m) }
        secim += geri.prefix(max(0, zincirSayisi - secim.count))
        zincirler = Array(secim.shuffled().prefix(zincirSayisi))
        zi = 0; bi = 1; dogrular = 0; toplam = 0
        hazirla()
    }

    private func cevap(_ z: Merdiven) -> [String] {
        Metin.yuvalar(z.basamaklar[bi]).yuvalar.flatMap { $0.split(separator: " ").map(String.init) }
    }

    private func hazirla() {
        guard let z else { return }
        let c = cevap(z)
        let onceki = Metin.yuvalar(z.basamaklar[bi - 1]).yuvalar.flatMap { $0.split(separator: " ").map(String.init) }
        var fazla: [String] = []
        for w in onceki + z.d where !c.contains(w) && !fazla.contains(w) { fazla.append(w) }
        var t = (c + fazla.prefix(4)).map { Tas(metin: $0) }.shuffled()
        if t.map(\.metin) == c && t.count > 1 { t.swapAt(0, t.count - 1) }
        banka = t; dizi = []; sonuc = nil
    }

    private func denetle(_ z: Merdiven) {
        let d = dizi.map { Metin.norm($0.metin) } == cevap(z).map { Metin.norm($0) }
        toplam += 1
        if d { dogrular += 1; Dokunus.basari() } else { Dokunus.hata() }
        Ses.konus(Metin.koseliSil(z.basamaklar[bi]))
        withAnimation(.spring) { sonuc = d }
    }

    private func ilerle(_ z: Merdiven) {
        withAnimation(.snappy) {
            if bi + 1 < z.basamaklar.count { bi += 1 }
            else if zi + 1 < zincirler.count { zi += 1; bi = 1 }
            else { bitti = true; return }
            hazirla()
        }
    }

    private func turAdi(_ t: String) -> String {
        ["kosul": "Koşul", "aktarma": "Aktarma", "wish": "Keşke", "zaman": "Zaman"][t] ?? t
    }

    private func basamakAdi(_ t: String, _ n: Int) -> String {
        let adlar: [String: [String]] = [
            "kosul": ["1. tip · gerçek", "2. tip · hayal", "3. tip · geçmiş hayal"],
            "aktarma": ["tırnak içi", "aktarılan söz"],
            "wish": ["gerçek", "keşke · şimdi", "keşke · geçmiş"],
            "zaman": ["şimdi", "geçmiş", "geçmişin geçmişi"],
        ]
        return adlar[t]?[safe: n] ?? "basamak \(n + 1)"
    }
}
