// HAFIZA — kart çevir, eşle. Üç deste: konu ↔ örnek · tuzak ↔ doğrusu · konu ↔ imge.
// Eşleşen çift o konunun bölge rengine bürünür (renk = mekanizma; renk de hafızaya yardım eder).
import SwiftUI

struct HafizaKarti: Identifiable, Equatable {
    let id = UUID()
    let cift: Int
    let metin: String
    let ingilizce: Bool
    let renk: Color
    let sembol: String
    var acik = false
    var eslesti = false
}

struct HafizaOyunu: View {
    @Environment(Depo.self) private var depo
    @Environment(\.dismiss) private var kapat
    @State private var kartlar: [HafizaKarti] = []
    @State private var secili: [Int] = []
    @State private var hamle = 0
    @State private var deste = 0
    @State private var bitti = false
    @State private var kilit = false

    private let desteler = ["Konu ↔ örnek", "Yanlış ↔ doğru", "Konu ↔ imge"]

    var body: some View {
        if bitti {
            OyunSonu(oyun: .hafiza, buyuk: "\(hamle) hamle", aciklama: "6 çift buldun",
                     ders: hamle <= 9 ? "Çok az hamle: konular zihninde örnekleriyle birlikte duruyor." : "Her eşleşme bir bağ: konu adı ile cümle aynı rafta durmaya başlıyor.",
                     tekrar: { bitti = false; kur() }, kapat: { kapat() })
        } else {
            VStack(spacing: 12) {
                OyunUstu(baslik: "Hafıza", alt: "\(desteler[deste]) · \(hamle) hamle", renk: Oyun.hafiza.renk,
                         ilerleme: Double(kartlar.filter(\.eslesti).count) / 12) { kapat() }
                Picker("Deste", selection: $deste) { ForEach(0..<3) { Text(desteler[$0]).tag($0) } }
                    .pickerStyle(.segmented).padding(.horizontal)
                    .onChange(of: deste) { _, _ in kur() }
                GeometryReader { g in
                    let gen = (g.size.width - 32 - 16) / 3
                    let yuk = (g.size.height - 24) / 4
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(gen), spacing: 8), count: 3), spacing: 8) {
                        ForEach(Array(kartlar.enumerated()), id: \.element.id) { i, k in
                            KartYuzu(kart: k)
                                .frame(width: gen, height: yuk)
                                .onTapGesture { cevir(i) }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 8)
            }
            .background(Lekeler(renkler: [Oyun.hafiza.renk, Tema.vurgu, Tema.renk("turkuaz")]))
            .onAppear { if kartlar.isEmpty { kur() } }
        }
    }

    private func kur() {
        var havuz = depo.oyunHavuzu().shuffled()
        var yeni: [HafizaKarti] = []
        var cift = 0
        while cift < 6, let k = havuz.popLast() {
            let r = depo.renk(k)
            let s = depo.bolge(k.bolge)?.sembol ?? "circle"
            let ab: (String, Bool, String, Bool)?
            switch deste {
            case 0:
                let o = k.ornek.map { $0.first ?? "" }.filter { $0.count <= 58 }.min { $0.count < $1.count }
                ab = o.map { (k.tr, false, $0, true) }
            case 1:
                let t = k.tuzakAyrik
                ab = (!t.y.isEmpty && t.y.count <= 52 && t.d.count <= 52) ? ("✗ " + t.y, true, "✓ " + t.d, true) : nil
            default:
                let imge = k.imge.components(separatedBy: ":").first ?? k.imge
                ab = imge.count <= 44 ? (k.tr, false, imge, false) : nil
            }
            guard let ab else { continue }
            yeni.append(HafizaKarti(cift: cift, metin: ab.0, ingilizce: ab.1, renk: r, sembol: s))
            yeni.append(HafizaKarti(cift: cift, metin: ab.2, ingilizce: ab.3, renk: r, sembol: s))
            cift += 1
        }
        withAnimation { kartlar = yeni.shuffled(); secili = []; hamle = 0 }
    }

    private func cevir(_ i: Int) {
        guard !kilit, !kartlar[i].acik, !kartlar[i].eslesti, secili.count < 2 else { return }
        Dokunus.hafif()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { kartlar[i].acik = true }
        secili.append(i)
        guard secili.count == 2 else { return }
        hamle += 1
        let (a, b) = (secili[0], secili[1])
        if kartlar[a].cift == kartlar[b].cift {
            Dokunus.basari()
            if kartlar[a].ingilizce { Ses.konus(kartlar[a].metin.replacingOccurrences(of: "✗ ", with: "")) }
            else if kartlar[b].ingilizce { Ses.konus(kartlar[b].metin.replacingOccurrences(of: "✓ ", with: "")) }
            withAnimation(.spring) { kartlar[a].eslesti = true; kartlar[b].eslesti = true }
            secili = []
            if kartlar.allSatisfy(\.eslesti) { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { bitti = true } }
        } else {
            kilit = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { kartlar[a].acik = false; kartlar[b].acik = false }
                secili = []; kilit = false
            }
        }
    }
}

private struct KartYuzu: View {
    let kart: HafizaKarti
    var body: some View {
        ZStack {
            // arka yüz
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Oyun.hafiza.renk, Tema.vurgu], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Image(systemName: "gearshape.2.fill").font(.title).foregroundStyle(.white.opacity(0.35)))
                .opacity(kart.acik || kart.eslesti ? 0 : 1)
            // ön yüz
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(kart.eslesti ? kart.renk.opacity(0.22) : Tema.yuzey)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(kart.renk.opacity(kart.eslesti ? 0.9 : 0.35), lineWidth: kart.eslesti ? 2 : 1))
                .overlay(
                    VStack(spacing: 4) {
                        Circle().fill(kart.renk).frame(width: 6, height: 6)
                        Text(kart.metin)
                            .font(kart.ingilizce ? Tema.ingilizce(.footnote, .medium) : .system(.footnote, design: .rounded).weight(.bold))
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(6)
                )
                .scaleEffect(x: -1)   // dönüşte ters görünmesin
                .opacity(kart.acik || kart.eslesti ? 1 : 0)
        }
        .rotation3DEffect(.degrees(kart.acik || kart.eslesti ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        .scaleEffect(kart.eslesti ? 0.96 : 1)
    }
}
