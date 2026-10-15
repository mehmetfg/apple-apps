// Partisyon — her süreç bir çalgı, her gün bir ölçü. Altında vault aksiyonları ve senin kararını bekleyenler.
import SwiftUI

struct ZamanEkrani: View {
    @EnvironmentObject var merkez: Merkez
    @EnvironmentObject var rota: Rota
    @State private var hafta = 4
    @State private var acik: Set<String> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                if let d = merkez.durum {
                    VStack(alignment: .leading, spacing: 14) {
                        if let h = d.veri.hacim {
                            Button { rota.hacim = true } label: { HacimOzeti(h: h) }.buttonStyle(.plain)
                        }
                        Picker("Süre", selection: $hafta) {
                            Text("4 hafta").tag(4)
                            Text("12 hafta").tag(12)
                        }
                        .pickerStyle(.segmented)
                        partisyon(d)
                        kararlar(d)
                        aksiyonlar(d)
                    }
                    .padding(.horizontal, 16).padding(.bottom, 30)
                }
            }
            .background(Tema.zemin)
            .navigationTitle("Partisyon")
            .navigationDestination(for: String.self) { SurecDetay(id: $0) }
            .navigationDestination(isPresented: $rota.hacim) { HacimEkrani() }
        }
    }

    func partisyon(_ d: Durumlar) -> some View {
        let gun = hafta * 7
        let aktif = d.hukumler.filter { $0.durum.hukumVar }
            .sorted { x, y in
                (d.veri.alanlar.firstIndex { $0.id == x.surec.alan } ?? 0, x.surec.ad)
                    < (d.veri.alanlar.firstIndex { $0.id == y.surec.alan } ?? 0, y.surec.ad)
            }
        let birlesik = (0..<gun).map { i in aktif.filter { $0.surec.iz.suffix(gun)[safe: i] ?? 0 > 0 }.count }
        return Kart(baslik: "Son \(hafta) hafta", simge: "music.quarternote.3") {
            VStack(alignment: .leading, spacing: 7) {
                // birleşik nabız: o gün kaç süreç çaldı
                HStack(spacing: 6) {
                    Text("tutti").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary).frame(width: 84, alignment: .leading)
                    IzSeridi(iz: birlesik, gun: gun, renk: .accentColor, yukseklik: 22)
                }
                Divider()
                ForEach(aktif) { h in
                    NavigationLink(value: h.id) {
                        HStack(spacing: 6) {
                            HStack(spacing: 4) {
                                DurumNoktasi(durum: h.durum, boy: 6)
                                Text(h.surec.ad).font(.system(size: 11, weight: .medium)).lineLimit(1)
                            }
                            .frame(width: 84, alignment: .leading)
                            notalar(Array(h.surec.iz.suffix(gun)), Tema.alan(h.surec.alan))
                        }
                    }
                    .buttonStyle(.plain)
                }
                HStack {
                    Spacer().frame(width: 90)
                    Text(Tarih.kisa(Tarih.takvim.date(byAdding: .day, value: -(gun - 1), to: d.simdi) ?? d.simdi))
                    Spacer()
                    Text("bugün")
                }
                .font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
    }

    func notalar(_ iz: [Int], _ renk: Color) -> some View {
        let tepe = max(1, iz.max() ?? 1)
        return GeometryReader { g in
            let w = g.size.width / CGFloat(max(1, iz.count))
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
                ForEach(iz.indices, id: \.self) { i in
                    if iz[i] > 0 {
                        Circle().fill(renk.opacity(0.45 + 0.55 * Double(iz[i]) / Double(tepe)))
                            .frame(width: min(w * 0.9, 4 + 5 * CGFloat(iz[i]) / CGFloat(tepe)))
                            .position(x: w * (CGFloat(i) + 0.5), y: g.size.height / 2)
                    }
                }
                // bugün çizgisi
                Rectangle().fill(Color.accentColor.opacity(0.35)).frame(width: 1)
                    .position(x: w * (CGFloat(iz.count) - 0.5), y: g.size.height / 2)
            }
        }
        .frame(height: 14)
    }

    func kararlar(_ d: Durumlar) -> some View {
        Kart(baslik: "Senin kararını bekleyenler · \(d.veri.kararlar.count)", simge: "hand.raised") {
            Text("Orkestra bunları hatırlatır ama karar vermez. Karar verilene kadar ilgili süreç uyarı üretmez.")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
            ForEach(d.veri.kararlar) { k in
                VStack(alignment: .leading, spacing: 2) {
                    Text(k.metin).font(.system(size: 14, weight: .semibold))
                    if !k.ayrinti.isEmpty { Text(k.ayrinti).font(.system(size: 12)).foregroundStyle(.secondary) }
                    Text(k.kaynak).font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                if k.id != d.veri.kararlar.last?.id { Divider() }
            }
        }
    }

    func aksiyonlar(_ d: Durumlar) -> some View {
        Kart(baslik: "Vault aksiyonları", simge: "clock.arrow.circlepath") {
            ForEach(d.veri.aksiyonlar) { a in
                Button { withAnimation(.snappy) { if acik.contains(a.id) { acik.remove(a.id) } else { acik.insert(a.id) } } } label: {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(spacing: 0) {
                            Circle().fill(Tema.alan("vault")).frame(width: 8, height: 8).padding(.top, 5)
                            Rectangle().fill(Tema.alan("vault").opacity(0.25)).frame(width: 2)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(Tarih.coz(a.tarih).map(Tarih.kisa) ?? a.tarih).font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(a.baslik).font(.system(size: 14, weight: .semibold)).multilineTextAlignment(.leading)
                            if acik.contains(a.id) {
                                Text(a.ozet).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

extension ArraySlice {
    subscript(safe i: Int) -> Element? {
        let j = startIndex + i
        return indices.contains(j) ? self[j] : nil
    }
}
