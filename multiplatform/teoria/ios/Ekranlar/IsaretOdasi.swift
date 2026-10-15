// İşaret odası — bildirimden, widget'tan ya da Akış'tan bir nota gelince açılan okuma sayfası.
// Akış listesinde aranmaz: not doğrudan, kitabın renginde, bağlamıyla açılır.
//   1 · not (büyük serif)            2 · BAĞLAM (işaretin geçtiği paragraf)
//   3 · "O oturumda" — aynı kitapta, aynı yarım saatte işaretlediklerin, sırasıyla (notun öncesi ve sonrası)
//   4 · "Aynı kitaptan" — zamanca en yakın öteki işaretler; dokun = o nota geç
import SwiftUI

struct IsaretOdasi: View {
    @EnvironmentObject var depo: Depo
    @Environment(\.dismiss) private var kapat
    @State var kimlik: String
    var sesAc: (String?) -> Void = { _ in }
    @State private var recall: Isaret?

    var body: some View {
        NavigationStack {
            Group {
                if let i = depo.isaret(kimlik) { oda(i) } else { yok }
            }
            .background(Tema.arka.ignoresSafeArea())
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Bitti") { kapat() } }
            }
            .sheet(item: $recall) { i in RecallSayfasi(isaret: i).environmentObject(depo) }
        }
    }

    private var yok: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.quote").font(.system(size: 34)).foregroundStyle(Tema.soluk)
            Text("Bu işaret artık akışta değil.").foregroundStyle(Tema.ikincil)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func oda(_ i: Isaret) -> some View {
        let d = depo.durum
        let kr = Tema.kitap(i.kitap)
        let kisa = i.metin.count <= 180
        let fav = d.favoriler.contains(i.id), hat = d.hatirlatmalar.contains(i.id), yer = d.yerIsaretleri.contains(i.id)
        let yazdiklarin = d.kendiCumleler.filter { $0.hedef == i.id }
        return ScrollViewReader { kaydir in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 14) {
                        KitapKapagi(id: i.kitap, baslik: i.baslik, genislik: 44)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(i.kisaBaslik).font(.system(size: 17, weight: .semibold, design: .serif)).foregroundStyle(Tema.metin).lineLimit(2)
                            HStack(spacing: 8) {
                                TurRozeti(renk: i.renk)
                                Text(i.zaman.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(Dil.tr)))
                                    .font(.system(size: 12)).foregroundStyle(Tema.soluk)
                            }
                        }
                    }
                    .padding(.bottom, 18).id("ust")

                    // Önce üret, sonra oku: metne bakmadan çağırmak ve yeniden kurmak burada başlar.
                    Button { recall = i } label: {
                        Label("Kapat · hatırla · yeniden kur", systemImage: "brain.head.profile")
                    }
                    .buttonStyle(AnaDugme(renk: kr))
                    .padding(.bottom, 22)

                    Text(i.metin)
                        .font(.system(size: kisa ? 26 : 19, design: .serif)).lineSpacing(kisa ? 8 : 7)
                        .foregroundStyle(Tema.metin).textSelection(.enabled).tamGenislik()
                        .padding(.leading, 18)
                        .overlay(alignment: .leading) { Capsule().fill(kr).frame(width: 3.5) }
                        .padding(.bottom, 26)

                    if let b = i.baglam, !b.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("BAĞLAM").font(.system(size: 10.5, weight: .bold)).tracking(1.4).foregroundStyle(Tema.soluk)
                            Text(b).font(.system(size: 16, design: .serif)).foregroundStyle(Tema.ikincil).lineSpacing(6).textSelection(.enabled)
                        }
                        .padding(.leading, 18).tamGenislik()
                        .overlay(alignment: .leading) { Capsule().fill(kr.opacity(0.35)).frame(width: 2) }
                        .padding(.bottom, 26)
                    }

                    HStack(spacing: 10) {
                        dugme(fav ? "heart.fill" : "heart", fav ? .pink : Tema.ikincil, "Favori") { depo.favori(i.id) }
                        dugme(hat ? "bell.fill" : "bell", hat ? Tema.vurgu : Tema.ikincil, "Tekrar havuzu") { depo.hatirlat(i.id) }
                        dugme(yer ? "bookmark.fill" : "bookmark", yer ? Tema.vurgu : Tema.ikincil, "Yer işareti") { depo.yerIsareti(i.id) }
                        dugme("mic", Tema.uyari, "Sesli not") { sesAc(i.id) }
                        Spacer(minLength: 0)
                        ShareLink(item: "“\(i.metin)” — \(i.kisaBaslik)") {
                            Image(systemName: "square.and.arrow.up").font(.system(size: 14)).foregroundStyle(Tema.ikincil)
                                .frame(width: 38, height: 38)
                        }
                    }
                    .padding(.bottom, 8)

                    if !yazdiklarin.isEmpty {
                        Bolumbasi(metin: "Senin yazdıkların · \(yazdiklarin.count)", sembol: "person").padding(.top, 22).padding(.bottom, 10)
                        VStack(spacing: 10) { ForEach(yazdiklarin) { o in SenGonderisi(olay: o, alintiGoster: false) } }
                    }
                    oturum(i, kr) { kimlik = $0.id; kaydir.scrollTo("ust", anchor: .top) }
                    komsular(i, kr) { kimlik = $0.id; kaydir.scrollTo("ust", anchor: .top) }
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 48)
                .frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
            .background(alignment: .top) { KitapTulu(kitap: i.kitap, yukseklik: 420).padding(.top, -120) }
        }
    }

    private func dugme(_ s: String, _ r: Color, _ ad: String, _ f: @escaping () -> Void) -> some View {
        Button(action: f) {
            Image(systemName: s).font(.system(size: 14, weight: .medium)).foregroundStyle(r)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 38, height: 38)
                .background(Circle().fill(Tema.yuzey))
                .overlay(Circle().strokeBorder(Tema.cizgi, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ad)
    }

    /// Notun öncesi ve sonrası: aynı kitapta, ±30 dakika içinde işaretlediklerin; not kendi yerinde vurgulu.
    @ViewBuilder
    private func oturum(_ i: Isaret, _ kr: Color, git: @escaping (Isaret) -> Void) -> some View {
        let l = depo.akis.isaretler.filter { $0.kitap == i.kitap && abs($0.zaman.timeIntervalSince(i.zaman)) <= 1800 }
            .sorted { $0.zaman < $1.zaman }
        if l.count > 1 {
            Bolumbasi(metin: "O oturumda · \(l.count) işaret", sembol: "clock").padding(.top, 30).padding(.bottom, 12)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(l) { k in
                    let bu = k.id == i.id
                    Button { if !bu { git(k) } } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Circle().fill(bu ? kr : kr.opacity(0.3)).frame(width: 9, height: 9).padding(.top, 7)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(k.metin).font(.system(size: 14.5, design: .serif))
                                    .foregroundStyle(bu ? Tema.metin : Tema.ikincil).lineLimit(bu ? 3 : 2).multilineTextAlignment(.leading)
                                Text(k.zaman.formatted(.dateTime.hour().minute().locale(Dil.tr)))
                                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(Tema.soluk)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 4)
        }
    }

    @ViewBuilder
    private func komsular(_ i: Isaret, _ kr: Color, git: @escaping (Isaret) -> Void) -> some View {
        let l = depo.akis.isaretler.filter { $0.kitap == i.kitap && $0.id != i.id && abs($0.zaman.timeIntervalSince(i.zaman)) > 1800 }
            .sorted { abs($0.zaman.timeIntervalSince(i.zaman)) < abs($1.zaman.timeIntervalSince(i.zaman)) }
            .prefix(6)
        if !l.isEmpty {
            Bolumbasi(metin: "Aynı kitaptan", sembol: "books.vertical").padding(.top, 30).padding(.bottom, 12)
            VStack(spacing: 10) {
                ForEach(Array(l)) { k in
                    Button { git(k) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(k.metin).font(.system(size: 14, design: .serif)).foregroundStyle(Tema.metin)
                                .lineSpacing(3).lineLimit(4).multilineTextAlignment(.leading)
                            Text(Tarih.kisa(k.zaman)).font(.system(size: 11)).foregroundStyle(Tema.soluk)
                        }
                        .padding(.leading, 18).padding(.trailing, 14).padding(.vertical, 12)
                        .tamGenislik()
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Tema.yuzey))
                        .overlay(alignment: .leading) { Capsule().fill(kr.opacity(0.7)).frame(width: 2.5).padding(.vertical, 12).padding(.leading, 7) }
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Tema.cizgi, lineWidth: 0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
