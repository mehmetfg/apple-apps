// Kabuk (sekmeler) ve Bugün ekranı.
import SwiftUI

struct Kabuk: View {
    @EnvironmentObject var depo: Depo
    @State private var sekme = 0

    var body: some View {
        Group {
            if depo.yuklendi {
                TabView(selection: $sekme) {
                    BugunEkrani().tag(0)
                        .tabItem { Label("Bugün", systemImage: "sun.max") }
                    DeyimselEkrani().tag(3)
                        .tabItem { Label("Fiiller", systemImage: "arrow.triangle.branch") }
                    DepoEkrani().tag(1)
                        .tabItem { Label("Depo", systemImage: "books.vertical") }
                    IlerlemeEkrani().tag(2)
                        .tabItem { Label("İlerleme", systemImage: "chart.line.uptrend.xyaxis") }
                }
                .tint(R.vurgu)
            } else {
                VStack(spacing: 14) {
                    Text("aşina").font(.kelime(44)).foregroundStyle(R.vurgu)
                    ProgressView()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(R.zemin.ignoresSafeArea())
            }
        }
        .sheet(item: $depo.acilacakKelime) { k in
            KelimeDetay(k: k).presentationDetents([.large])
        }
    }
}

struct BugunEkrani: View {
    @EnvironmentObject var depo: Depo
    @State private var oturum: Oturum?
    @State private var ayarlar = false
    @State private var ayikla = false
    @State private var goster = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    baslik
                    gununKarti
                    gununKelimeleri
                    ayiklaKarti
                    haftaSeridi
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .background(R.zemin.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(item: $oturum) { o in
            OturumEkrani(oturum: o).environmentObject(depo)
        }
        .sheet(isPresented: $ayarlar) { AyarlarEkrani() }
        .fullScreenCover(isPresented: $ayikla) { AyiklaEkrani() }
        .onAppear { goster = true }
    }

    private var baslik: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date().uzunGun.uppercased(with: Locale(identifier: "tr_TR")))
                    .font(.caption.weight(.semibold)).foregroundStyle(R.soluk).tracking(0.6)
                Text("Bugün").font(.system(size: 34, weight: .bold, design: .rounded))
            }
            Spacer()
            Button { ayarlar = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.body.weight(.semibold)).foregroundStyle(R.murekkep)
                    .frame(width: 40, height: 40).background(R.yuzey, in: Circle())
            }
        }
        .padding(.top, 12)
    }

    private var gununKarti: some View {
        let yeni = depo.bekleyenYeniler.count
        let tekrar = depo.bekleyenTekrarlar.count
        let hedef = max(1, depo.bugunHedef)
        let yapilan = depo.bugunYapilan
        let bitti = yeni + tekrar == 0
        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 20) {
                ZStack {
                    Halka(oran: bitti ? 1 : Double(yapilan) / Double(hedef), kalinlik: 13,
                          renk: bitti ? R.dogru : R.vurgu)
                    if bitti {
                        Image(systemName: "checkmark").font(.system(size: 34, weight: .bold)).foregroundStyle(R.dogru)
                    } else {
                        VStack(spacing: 0) {
                            Text("\(yeni + tekrar)").font(.system(size: 32, weight: .bold, design: .rounded))
                            Text("kelime").font(.caption2).foregroundStyle(R.soluk)
                        }
                    }
                }
                .frame(width: 104, height: 104)
                VStack(alignment: .leading, spacing: 10) {
                    if bitti {
                        Text("Bugün tamam").font(.title3.weight(.bold))
                        Text("Kelimeler gün boyu widget'ta ve bildirimlerde dolaşacak.")
                            .font(.footnote).foregroundStyle(R.ikincil)
                    } else {
                        satir("sparkles", "\(yeni) yeni", R.vurgu)
                        satir("arrow.triangle.2.circlepath", "\(tekrar) tekrar", R.asama(.asina))
                        satir("clock", "~\(max(1, (yeni * 25 + tekrar * 8) / 60)) dakika", R.soluk)
                    }
                }
                Spacer(minLength: 0)
            }
            if bitti {
                Button { depo.dahaFazla(5); baslat() } label: {
                    Label("5 yeni kelime daha", systemImage: "plus")
                        .font(.headline).foregroundStyle(R.vurgu)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(R.vurgu.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(Bas())
            } else {
                AnaDugme(baslik: yapilan > 0 ? "Devam et" : "Başla", simge: "play.fill") { baslat() }
            }
        }
        .kart(20)
        .opacity(goster ? 1 : 0).offset(y: goster ? 0 : 12)
        .animation(.easeOut(duration: 0.5), value: goster)
    }

    private func satir(_ simge: String, _ metin: String, _ renk: Color) -> some View {
        Label {
            Text(metin).font(.subheadline.weight(.medium)).foregroundStyle(R.murekkep)
        } icon: {
            Image(systemName: simge).foregroundStyle(renk).frame(width: 20)
        }
    }

    private func baslat() {
        let o = Oturum(depo: depo, yeniler: depo.bekleyenYeniler, tekrarlar: depo.bekleyenTekrarlar)
        oturum = o
    }

    private var gununKelimeleri: some View {
        let l = depo.yeniler()
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Bugünün kelimeleri").font(.headline)
                Spacer()
                Text("dokun → çevir").font(.caption).foregroundStyle(R.soluk)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(l) { k in CevirKart(k: k) }
                }
                .scrollTargetLayout()
                .padding(.vertical, 4)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
    }

    private var ayiklaKarti: some View {
        Button { ayikla = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "rectangle.stack.badge.minus")
                    .font(.title2).foregroundStyle(R.bant("B1"))
                    .frame(width: 48, height: 48)
                    .background(R.bant("B1").opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Depoyu ayıkla").font(.headline).foregroundStyle(R.murekkep)
                    Text("\(depo.depoKalan.formatted()) kelime sırada. Bildiklerini kaydırarak at; sıra sana kalsın.")
                        .font(.footnote).foregroundStyle(R.ikincil).multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(R.soluk)
            }
            .kart(16)
        }
        .buttonStyle(Bas())
    }

    private var haftaSeridi: some View {
        let gunler = (0..<14).reversed().map { Date().gun(-$0) }
        let degerler = gunler.map { g -> Int in
            let k = depo.kayit.gunler[g.gunAnahtari]
            return (k?.yeni ?? 0) + (k?.tekrar ?? 0)
        }
        let enCok = max(10, degerler.max() ?? 0)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Son iki hafta").font(.headline)
                Spacer()
                if depo.seri > 0 {
                    Label("\(depo.seri) gün", systemImage: "flame.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(R.vurgu)
                }
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(degerler.enumerated()), id: \.offset) { i, d in
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(d > 0 ? R.vurgu.opacity(i == 13 ? 1 : 0.55) : R.cizgi)
                            .frame(height: max(6, 70 * CGFloat(d) / CGFloat(enCok)))
                        Text(gunler[i].formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 9)).foregroundStyle(R.soluk)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 90, alignment: .bottom)
        }
        .kart(18)
    }
}

extension Oturum: Identifiable {
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}

/// Dokununca çevrilen kelime kartı (bugünün yenileri).
struct CevirKart: View {
    @EnvironmentObject var depo: Depo
    let k: Kelime
    @State private var arka = false

    var body: some View {
        ZStack {
            on.opacity(arka ? 0 : 1)
            arkaYuz.opacity(arka ? 1 : 0).rotation3DEffect(.degrees(180), axis: (0, 1, 0))
        }
        .frame(width: 210, height: 150)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(R.yuzey)
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(R.bantZemin(k.c, pv: k.isPV)))
        )
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(R.ton(k.c, pv: k.isPV).opacity(0.25), lineWidth: 1))
        .rotation3DEffect(.degrees(arka ? 180 : 0), axis: (0, 1, 0), perspective: 0.6)
        .onTapGesture {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) { arka.toggle() }
            if arka { Ses.ortak.soyle(k, oxford: depo.ayar.oxfordSesi) }
        }
        .onLongPressGesture { depo.acilacakKelime = k }
        .sensoryFeedback(.impact(weight: .light), trigger: arka)
    }

    private var on: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                RozetKelime(k: k)
                Spacer()
                if depo.kart(k) != nil { Image(systemName: "checkmark.seal.fill").foregroundStyle(R.dogru) }
            }
            Spacer()
            Text(k.w).font(.kelime(30)).foregroundStyle(R.murekkep).minimumScaleFactor(0.5).lineLimit(1)
            Text(k.ipa.isEmpty ? k.turAdi : k.ipa).font(.footnote).foregroundStyle(R.soluk)
        }
        .padding(16)
    }

    private var arkaYuz: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(k.tr).font(.system(size: 19, weight: .semibold, design: .rounded)).foregroundStyle(R.vurgu)
                .lineLimit(2)
            if let x = k.ilkCumle {
                Text(Vurgu.metin(x, k.w, renk: R.murekkep))
                    .font(.kelime(13, .regular)).foregroundStyle(R.ikincil).lineLimit(4)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
