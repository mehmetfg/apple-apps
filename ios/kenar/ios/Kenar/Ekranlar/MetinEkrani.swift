// Metin: tek metnin iskeleti. Beş bölüm, her birinin iddiası, kanıtı, kelimesi; en üstte sıradaki tek hamle.
import SwiftUI

struct MetinEkrani: View {
    @EnvironmentObject var merkez: Merkez
    @EnvironmentObject var rota: Rota
    @State private var yol = NavigationPath()
    @State private var ayarlar = false
    @State private var uretimSorusu = false
    @State private var uretimHatasi: String?

    var body: some View {
        NavigationStack(path: $yol) {
            ScrollView {
                if let m = merkez.d.metin {
                    VStack(alignment: .leading, spacing: 18) {
                        ust(m)
                        hamleKarti
                        ForEach(m.bolumler) { b in
                            NavigationLink(value: b.id) { BolumKarti(b: b, kanit: merkez.d.kanitlar(b.id).count) }
                                .buttonStyle(.plain)
                        }
                        if m.bittiSayisi == m.bolumler.count { uretimKarti(m) }
                        alt
                    }
                    .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 30)
                }
            }
            .kagitZemin()
            .refreshable { await merkez.esitle() }
            .navigationDestination(for: String.self) { BolumEkrani(bolumId: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { ayarlar = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $ayarlar) { AyarlarEkrani() }
        }
        .onChange(of: rota.bolum) { _, b in ac(b) }
        .onAppear { ac(rota.bolum) }
    }

    private func ac(_ b: String?) {
        guard let b else { return }
        yol = NavigationPath(); yol.append(b); rota.bolum = nil
    }

    private func ust(_ m: Metin) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("TEK METİN").font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(Color.kalem)
                Text(m.baslik).font(.serif(30, .semibold)).foregroundStyle(Color.murekkep).fixedSize(horizontal: false, vertical: true)
                Text(m.soru).font(.serif(17).italic()).foregroundStyle(Color.soluk).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            ZStack {
                Halka(oran: Double(m.kelime) / Double(m.hedef), kalinlik: 8)
                VStack(spacing: 0) {
                    Text("\(m.kelime)").font(.system(size: 20, weight: .bold, design: .serif)).monospacedDigit()
                    Text("/ \(m.hedef)").font(.caption2).foregroundStyle(Color.soluk)
                }
            }
            .frame(width: 78, height: 78)
        }
        .padding(.top, 8)
    }

    private var hamleKarti: some View {
        let h = merkez.d.hamle
        return Button { rota.git(h.adres) } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.turn.down.right").font(.title3.weight(.semibold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(Circle().fill(Color.kalem))
                VStack(alignment: .leading, spacing: 2) {
                    Text("SIRADAKİ HAMLE").font(.caption2.weight(.bold)).tracking(1).foregroundStyle(Color.kalem)
                    Text(h.cumle).font(.callout.weight(.medium)).foregroundStyle(Color.murekkep).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.kalem.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private func uretimKarti(_ m: Metin) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(m.uretimeGitti == nil ? "Beş bölüm bitti." : "Metin Üretim'de.").font(.serif(20, .semibold))
            Text(m.uretimeGitti == nil
                 ? "Üretim'e gönderince `02 - Eudomonia/Üretim/\(m.baslik).md` yazılır. Dışarı çıkarmak — yayımlamak, birine okutmak — sende."
                 : "Gönderildi: \(m.uretimeGitti!.formatted(date: .abbreviated, time: .shortened)). Yön Belgesi'nin ölçütü: dışarıdan okunabilir olması.")
                .font(.footnote).foregroundStyle(Color.soluk)
            if m.uretimeGitti == nil {
                Button { uretimSorusu = true } label: { Label("Üretim'e gönder", systemImage: "paperplane.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
            if let h = uretimHatasi { Text(h).font(.footnote).foregroundStyle(.red) }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.kart))
        .confirmationDialog("Metin Üretim klasörüne bitmiş iş olarak yazılsın mı?", isPresented: $uretimSorusu, titleVisibility: .visible) {
            Button("Gönder") { Task { uretimHatasi = await merkez.uretimeGonder() } }
        }
    }

    private var alt: some View {
        HStack(spacing: 6) {
            if merkez.esitleniyor { ProgressView().controlSize(.mini) }
            if let z = merkez.sonEsitleme { Text("Eşitlendi \(z.formatted(.relative(presentation: .named)))") }
            if let h = merkez.hata { Text(h).foregroundStyle(.red) }
        }
        .font(.caption2).foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity)
    }
}

struct BolumKarti: View {
    let b: Bolum
    let kanit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                BolumRozeti(no: b.no, boy: 30, dolu: b.bitti)
                Text(b.baslik).font(.serif(19, .semibold)).foregroundStyle(Color.murekkep)
                Spacer()
                if b.bitti { Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.bolum(b.no)) }
            }
            Text(b.iddia).font(.serif(15)).foregroundStyle(Color.soluk).lineLimit(3).multilineTextAlignment(.leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.cizgi)
                    Capsule().fill(Color.bolum(b.no)).frame(width: g.size.width * min(1, Double(b.kelime) / Double(max(1, b.hedef))))
                }
            }
            .frame(height: 5)
            HStack(spacing: 8) {
                Cip(metin: "\(kanit) kanıt", simge: "quote.opening", renk: kanit == 0 ? .soluk : Color.bolum(b.no))
                Cip(metin: "\(b.kelime)/\(b.hedef)", simge: "pencil.line")
                if b.ingilizce != nil { Cip(metin: "EN", simge: "globe", renk: .blue) }
                Spacer()
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.kart))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(b.bitti ? Color.bolum(b.no).opacity(0.5) : Color.cizgi, lineWidth: b.bitti ? 1.2 : 0.6))
    }
}
