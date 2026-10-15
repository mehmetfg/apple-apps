// Yasalar: konuları birbirine bağlayan on hareket. Her yasa kendi küçük çizimiyle (önce → sonra) ve hep aynı tonla görünür.
import SwiftUI

struct YasalarEkrani: View {
    @Environment(Depo.self) private var depo
    let ac: (Acilan) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Altmış konu, on yasa. Bir yasayı kavradığında ona bağlı bütün konuların yarısı hazırdır.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    bolum("Fiil motoru", "Gramer Motoru'nun beş yasası", Array(depo.veri.yasalar.prefix(5)))
                    bolum("Cümlenin geri kalanı", "İsim, sıra, soru, edat", Array(depo.veri.yasalar.dropFirst(5)))
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
            .background(Lekeler(renkler: [Tema.renk("kehribar"), Tema.renk("yesil")]))
            .navigationTitle("Yasalar")
            .navigationDestination(for: String.self) { YasaDetay(yasaId: $0, ac: ac) }
        }
    }

    private func bolum(_ baslik: String, _ alt: String, _ ys: [Yasa]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(baslik).font(Tema.baslik(.title3))
                Text(alt).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.top, 8)
            ForEach(ys) { y in
                NavigationLink(value: y.id) { YasaKarti(yasa: y) }.buttonStyle(BasinStil())
            }
        }
    }
}

struct YasaKarti: View {
    @Environment(Depo.self) private var depo
    let yasa: Yasa
    var body: some View {
        let r = Tema.renk(yasa.renk)
        let calisilan = yasa.konular.filter { depo.kademe($0) >= 2 }.count
        HStack(spacing: 14) {
            Cizim(ad: yasa.id, renk: r, boy: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(yasa.ad).font(.headline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                Text(yasa.ozet).font(.subheadline).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
                Text("\(yasa.konular.count) konu" + (calisilan > 0 ? " · \(calisilan) çalışıldı" : ""))
                    .font(.caption.weight(.medium)).foregroundStyle(r)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .kart(14, yaricap: 22)
    }
}

struct YasaDetay: View {
    @Environment(Depo.self) private var depo
    let yasaId: String
    let ac: (Acilan) -> Void

    var body: some View {
        if let y = depo.yasa(yasaId) {
            let r = Tema.renk(y.renk)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 10) {
                        Cizim(ad: y.id, renk: r, boy: 120)
                        Text(y.imge).font(.caption.weight(.bold)).textCase(.uppercase).foregroundStyle(r).padding(.top, 4)
                        Text(y.ad).font(.system(.title, design: .rounded).weight(.bold)).multilineTextAlignment(.center)
                        Text(y.ozet).font(.title3).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)

                    Text(y.aciklama).font(.body).lineSpacing(3).fixedSize(horizontal: false, vertical: true).kart(18)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Aynı hareket, üç konuda").font(Tema.baslik(.title3))
                        Text("Renkli kelimeler değişen parça. Çift dokun, dinle.").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(y.ornekler, id: \.self) { o in
                        if let k = depo.konu(o.konu) {
                            Button { ac(.konu(k.id)) } label: {
                                OrnekKutusu(baslik: k.tr, en: o.en, hareket: o.tr, renk: r, gidilir: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if let oyun = Oyun.allCases.first(where: { $0.yasaId == y.id }) {
                        Button { ac(.oyun(oyun)) } label: {
                            HStack(spacing: 10) {
                                Cizim(ad: "oyun-" + oyun.rawValue, renk: .white, boy: 30, zemin: false)
                                Text("\(oyun.ad) ile oyna").font(.headline)
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 52).background(Capsule().fill(r))
                        }
                        .buttonStyle(.plain)
                    }

                    Text("Bu yasayla dönen \(y.konular.count) konu").font(Tema.baslik(.title3))
                    let konular = y.konular.compactMap { depo.konu($0) }
                    ForEach(depo.veri.bolgeler) { b in
                        let ic = konular.filter { $0.bolge == b.id }
                        if !ic.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(spacing: 6) {
                                    Circle().fill(Tema.renk(b.renk)).frame(width: 7, height: 7)
                                    Text(b.ad).font(.caption.weight(.bold)).foregroundStyle(Tema.renk(b.renk))
                                }
                                .padding(.bottom, 6)
                                ForEach(Array(ic.enumerated()), id: \.element.id) { i, k in
                                    Button { ac(.konu(k.id)) } label: {
                                        HStack(alignment: .top, spacing: 10) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(k.tr).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                                if let not = k.yasalar.first(where: { $0.id == y.id })?.not {
                                                    Text(not).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                                                }
                                            }
                                            Spacer(minLength: 0)
                                            KademeHalkasi(kademe: depo.kademe(k.id), renk: depo.renk(k), boy: 18)
                                        }
                                        .padding(.vertical, 8)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    if i < ic.count - 1 { Divider() }
                                }
                            }
                            .kart(14, yaricap: 18)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
            .background(Lekeler(renkler: [r, Tema.vurgu]))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
