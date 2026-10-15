// İdrak: kapak şeridi (süren kitaplar), günün alıntısı, biten raf ve kitap odası.
import SwiftUI
import Charts
#if canImport(UIKit)
import UIKit
#endif

struct IdrakEkrani: View {
    @EnvironmentObject var depo: VeriDeposu

    var body: some View {
        let i = depo.veri?.idrak
        let kitaplar = i?.kitaplar ?? []
        let suren = kitaplar.filter { !$0.bitti }
        let biten = kitaplar.filter(\.bitti)
        Ekran {
            EkranBasligi(ust: "Dinlediğin kitaplar", baslik: "İdrak",
                         alt: "\(kitaplar.count) kitap · \(Bicim.sayi(i?.toplam_isaret)) işaret")
            if let h = i?.hata {
                BolumHatasi(ad: "İdrak", hata: h)
            } else if kitaplar.isEmpty {
                BosDurum(simge: "books.vertical", metin: "Henüz kitap yok.")
            } else {
                HStack {
                    BuyukSayi(deger: "\(suren.count)", etiket: "sürüyor", renk: T.idrak)
                    BuyukSayi(deger: "\(biten.count)", etiket: "bitti")
                    BuyukSayi(deger: Bicim.sayi(i?.toplam_isaret), etiket: "işaret")
                    BuyukSayi(deger: Bicim.kisa(kitaplar.reduce(0) { $0 + ($1.kelime ?? 0) }), etiket: "kelime")
                }
                .padding(.horizontal, 4)
                if !suren.isEmpty {
                    BolumBasligi(baslik: "Sürenler", alt: "kaydır")
                    KapakSeridi(kitaplar: suren)
                }
                if let (k, s) = gununAlintisi(kitaplar) {
                    GununAlintisi(kitap: k, isaret: s).belirerek()
                }
                if !biten.isEmpty {
                    BolumBasligi(baslik: "Biten raf", alt: "\(biten.count)")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 16) {
                        ForEach(biten) { k in
                            NavigationLink(value: k) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Kapak(kitap: k).aspectRatio(2 / 3, contentMode: .fit)
                                    Text(k.baslik ?? "").font(.caption.weight(.medium)).lineLimit(2)
                                        .foregroundStyle(T.murekkep)
                                }
                            }
                            .buttonStyle(BasilmaStili())
                            .belirerek()
                        }
                    }
                }
            }
        }
        .navigationDestination(for: Kitap.self) { KitapOdasi(kitap: $0) }
    }

    /// Her gün aynı, ertesi gün başka bir işaret.
    func gununAlintisi(_ k: [Kitap]) -> (Kitap, Isaret)? {
        let hepsi = k.flatMap { b in (b.isaretler ?? []).filter { ($0.alinti ?? "").count > 30 }.map { (b, $0) } }
        guard !hepsi.isEmpty else { return nil }
        let gun = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return hepsi[gun % hepsi.count]
    }
}

/// Basınca hafifçe küçülen düğme.
struct BasilmaStili: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Kapak

struct Kapak: View {
    @EnvironmentObject var depo: VeriDeposu
    let kitap: Kitap
    var kose: CGFloat = 12

    var body: some View {
        ZStack {
            if let i = depo.kapak(kitap.kapak) {
                i.resizable().scaledToFill()
            } else {
                LinearGradient(colors: [renk.opacity(0.95), renk.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(alignment: .leading) {
                    Text(kitap.baslik ?? "").font(.system(.subheadline, design: .serif).weight(.bold))
                        .foregroundStyle(.white).lineLimit(5)
                    Spacer()
                    Rectangle().fill(.white.opacity(0.5)).frame(width: 24, height: 2)
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: kose, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: kose, style: .continuous).strokeBorder(.black.opacity(0.08)))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 5)
    }

    var renk: Color {
        let p: [UInt32] = [0xB0543C, 0x3D6E60, 0xA1732F, 0x4F5D95, 0x7A4E7E, 0x5E7A3C]
        let h = (kitap.kume ?? kitap.id).unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Color.hex(p[h % p.count])
    }
}

// MARK: - Kapak şeridi

struct KapakSeridi: View {
    let kitaplar: [Kitap]
    @State private var konum: String?

    var body: some View {
        VStack(spacing: 12) {
            Serit(ogeler: kitaplar, bosluk: 18, konum: $konum) { k in
                        NavigationLink(value: k) {
                            VStack(alignment: .leading, spacing: 10) {
                                Kapak(kitap: k, kose: 16)
                                    .frame(width: 170, height: 255)
                                    .overlay(alignment: .bottomTrailing) {
                                        ZStack {
                                            Circle().fill(.ultraThinMaterial)
                                            Halka(oran: Double(k.yuzde ?? 0) / 100, renk: T.idrak, kalinlik: 4).padding(5)
                                            Text("\(k.yuzde ?? 0)").font(.system(size: 12, weight: .bold, design: .rounded))
                                        }
                                        .frame(width: 46, height: 46)
                                        .padding(8)
                                    }
                                Text(k.baslik ?? "").font(.subheadline.weight(.semibold)).lineLimit(2)
                                    .foregroundStyle(T.murekkep).frame(width: 170, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("\(k.isaret ?? 0) işaret · \(Bicim.kisaTarih(k.son))")
                                    .font(.caption).foregroundStyle(T.soluk)
                            }
                        }
                        .buttonStyle(BasilmaStili())
                        .modifier(SeritGecisi(olcek: 0.9, donus: 18, solma: 0.75))
            }
        }
        .padding(.horizontal, -16)
    }
}

// MARK: - Günün alıntısı

struct GununAlintisi: View {
    let kitap: Kitap
    let isaret: Isaret

    var body: some View {
        NavigationLink(value: kitap) {
            VStack(alignment: .leading, spacing: 12) {
                Text("GÜNÜN İŞARETİ").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(T.idrak)
                Text("“\(isaret.alinti ?? "")”")
                    .font(.system(.title3, design: .serif).weight(.medium))
                    .foregroundStyle(T.murekkep)
                    .multilineTextAlignment(.leading)
                    .lineLimit(9)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Kapak(kitap: kitap, kose: 5).frame(width: 26, height: 39)
                    Text(kitap.baslik ?? "").font(.footnote.weight(.medium)).foregroundStyle(T.yumusak).lineLimit(2)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack(alignment: .topTrailing) {
                    T.yuzey
                    Image(systemName: "quote.closing").font(.system(size: 90, weight: .black))
                        .foregroundStyle(T.idrak.opacity(0.08)).padding(8)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 24).fill(T.idrak).frame(width: 5)
            }
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(T.cizgi))
        }
        .buttonStyle(BasilmaStili())
    }
}

// MARK: - Kitap odası

struct KitapOdasi: View {
    let kitap: Kitap
    @State private var sekme = 0

    var body: some View {
        Kaydir {
            VStack(alignment: .leading, spacing: 16) {
                ust
                if let o = kitap.okumalar, o.count > 1 { okumaGrafigi(o) }
                Picker("", selection: $sekme.animation(T.yay)) {
                    Text("İşaretler (\(kitap.isaretler?.count ?? 0))").tag(0)
                    Text("Can alıcı").tag(1)
                    Text("Harita").tag(2)
                }
                .pickerStyle(.segmented)
                .sensoryFeedback(.selection, trigger: sekme)
                Group {
                    switch sekme {
                    case 0: isaretler
                    case 1: canAlici
                    default: harita
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            .padding(16)
        }
        .background(T.zemin.ignoresSafeArea())
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    var ust: some View {
        VStack(spacing: 14) {
            Kapak(kitap: kitap, kose: 14).frame(width: 150, height: 225)
                .padding(.top, 8)
            Text(kitap.baslik ?? "").font(.system(.title2, design: .serif).weight(.bold)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if let d = kitap.disiplin { Rozet(metin: d, renk: T.idrak) }
                Rozet(metin: kitap.bitti ? "bitti" : "sürüyor", renk: kitap.bitti ? T.muhendis : T.cumle)
            }
            Cubuk(oran: Double(kitap.yuzde ?? 0) / 100, renk: T.idrak, kalinlik: 7).padding(.horizontal, 30)
            HStack {
                BuyukSayi(deger: "%\(kitap.yuzde ?? 0)", etiket: "dinlendi", renk: T.idrak)
                BuyukSayi(deger: "\(kitap.isaret ?? 0)", etiket: "işaret")
                BuyukSayi(deger: Bicim.kisa(kitap.kelime), etiket: "kelime")
                BuyukSayi(deger: Bicim.kisaTarih(kitap.son), etiket: "son dinleme")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
        .background(alignment: .top) {
            Circle().fill(T.idrak.opacity(0.16)).frame(width: 320, height: 320).blur(radius: 70)
                .offset(y: -60).allowsHitTesting(false)
        }
    }

    func okumaGrafigi(_ o: [Okuma]) -> some View {
        KartKutu {
            Text("Dinleme seyri").font(.headline)
            Chart(Array(o.enumerated()), id: \.offset) { _, x in
                LineMark(x: .value("Tarih", Bicim.gun(x.tarih) ?? Date()), y: .value("%", x.yuzde ?? 0))
                    .foregroundStyle(T.idrak).interpolationMethod(.monotone)
                PointMark(x: .value("Tarih", Bicim.gun(x.tarih) ?? Date()), y: .value("%", x.yuzde ?? 0))
                    .foregroundStyle(T.idrak).symbolSize(CGFloat(20 + (x.yeni ?? 0) * 12))
            }
            .chartYScale(domain: 0...100)
            .frame(height: 130)
            Text("Nokta büyüklüğü = o dinlemede yeni işaret").font(.caption).foregroundStyle(T.soluk)
        }
    }

    @ViewBuilder var isaretler: some View {
        let l = kitap.isaretler ?? []
        if l.isEmpty {
            BosDurum(simge: "highlighter", metin: "Bu kitapta henüz işaret yok.")
        } else {
            ForEach(Array(l.enumerated()), id: \.offset) { i, s in
                IsaretKarti(isaret: s, sira: i + 1).belirerek()
            }
        }
    }

    @ViewBuilder var canAlici: some View {
        let l = kitap.cumleler ?? []
        if l.isEmpty {
            BosDurum(simge: "text.badge.star", metin: "Can alıcı cümleler oda çalışılınca gelir.")
        } else {
            KartKutu {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(l.enumerated()), id: \.offset) { i, c in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(i + 1)").font(.system(.caption, design: .rounded).bold())
                                .frame(width: 24, height: 24).background(T.idrak.opacity(0.12), in: Circle())
                                .foregroundStyle(T.idrak)
                            Text(c).font(.system(.callout, design: .serif))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder var harita: some View {
        let l = kitap.harita ?? []
        if l.isEmpty {
            BosDurum(simge: "map", metin: "Bölüm haritası yok.")
        } else {
            KartKutu {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(l.enumerated()), id: \.offset) { i, o in
                        HStack(spacing: 12) {
                            VStack(spacing: 0) {
                                Rectangle().fill(i == 0 ? .clear : T.cizgi).frame(width: 2, height: 10)
                                Circle().fill((o.isaret ?? 0) > 0 ? T.idrak : T.cizgi).frame(width: 10, height: 10)
                                Rectangle().fill(i == l.count - 1 ? .clear : T.cizgi).frame(width: 2, height: 10)
                            }
                            Text("\(o.kod ?? "") \(o.ad ?? "")").font(.subheadline).lineLimit(2)
                            Spacer()
                            if let n = o.isaret, n > 0 { Rozet(metin: "\(n)", renk: T.idrak) }
                        }
                    }
                }
            }
        }
    }
}

struct IsaretKarti: View {
    let isaret: Isaret
    let sira: Int
    @State private var acik = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("“\(isaret.alinti ?? "")”").font(.system(.body, design: .serif).weight(.medium))
            if let b = isaret.baglam, !b.isEmpty {
                Text(b).font(.footnote).foregroundStyle(T.yumusak).lineLimit(acik ? nil : 2)
                Text(acik ? "daha az" : "bağlamı göster").font(.caption.weight(.semibold)).foregroundStyle(T.idrak)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(T.yuzey, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18).fill(T.idrak).frame(width: 4)
        }
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(T.cizgi))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(T.yay) { acik.toggle() } }
        .contextMenu {
            Button { panoya(isaret.alinti ?? "") } label: { Label("Alıntıyı kopyala", systemImage: "doc.on.doc") }
        }
    }

    func panoya(_ s: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = s
        #endif
    }
}
