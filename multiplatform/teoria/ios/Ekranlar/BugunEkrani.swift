// Bugün — tek bakışta: halka, kür, son okuduğun gün, üç hattın merdiveni, günün aforizması, geçmişte bugün.
// Kavram gökyüzü kalktı: kavramlar Kitaplar › Sözlük'te. Kartlar tembel kurulur (aşağı indikçe).
// Mac'te (genis) iki sütun: solda kür ve son gün, sağda merdiven, aforizma, hafta.
// Burada borç yok: kaçırılan gün sayılmaz, "bekleyen" sayısı yok, kırmızı yok.
import SwiftUI

struct BugunEkrani: View {
    @EnvironmentObject var depo: Depo
    var kurBaslat: (Int) -> Void
    var sesAc: (String?) -> Void
    var genis = false

    @State private var sonGunAcik = false
    @State private var ayarlar = false

    var d: Durum { depo.durum }
    var oran: Double { min(d.bugunDakika / Double(max(depo.kurDakika, 1)), 1) }
    var bitti: Bool { d.bugunDakika >= Double(depo.kurDakika) }

    var body: some View {
        ScrollView {
            if genis {
                VStack(alignment: .leading, spacing: 22) {
                    baslik
                    HStack(alignment: .top, spacing: 22) {
                        VStack(spacing: 18) {
                            kurKarti
                            sonGunKarti
                            if let (i, ad) = gecmis { gecmisKarti(i, ad) }
                        }
                        .frame(maxWidth: .infinity)
                        VStack(spacing: 18) {
                            aforizmaKarti
                            hatlarKarti
                            haftaKarti
                            if !d.kendiCumleler.isEmpty { kendiSesinKarti }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 32).padding(.bottom, 32)
                .frame(maxWidth: 1400)
                .frame(maxWidth: .infinity)
            } else {
                LazyVStack(alignment: .leading, spacing: 18) {
                    baslik
                    kurKarti
                    sonGunKarti
                    hatlarKarti
                    aforizmaKarti
                    if let (i, ad) = gecmis { gecmisKarti(i, ad) }
                    haftaKarti
                    if !d.kendiCumleler.isEmpty { kendiSesinKarti }
                }
                .padding(.horizontal, 18).padding(.bottom, 30)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Tema.arka.ignoresSafeArea())
        .refreshable { await depo.guncelle() }
    }

    @State private var gecmis: (Isaret, String)? = nil

    // MARK: Son gün — kürün ilk durağı

    @ViewBuilder
    private var sonGunKarti: some View {
        if let (gun, l) = Kurgu.sonGun(depo.akis.isaretler, d), let ilk = l.first {
            let ad = Tarih.takvim.isDate(gun, inSameDayAs: Date()) ? "Bugün" : Tarih.goreli(gun).capitalized(with: Dil.tr)
            let aday = Uretec.isaretKarti(ilk, 3)
            let soru = aday?.yap()
            Yuzey {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        KitapKapagi(id: ilk.kitap, baslik: ilk.baslik, genislik: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Bolumbasi(metin: "Son okuduğun · \(ad)", sembol: "clock.arrow.circlepath", renk: Tema.vurgu)
                            Text(ilk.baslik.kodsuz).font(Tema.serif(.headline)).foregroundStyle(Tema.metin).lineLimit(2)
                            Text("\(l.count) işaret · kürde önce bunlar gelir").font(.caption).foregroundStyle(Tema.ikincil)
                        }
                    }
                    Text(sonGunAcik ? ilk.metin : (soru?.baglam ?? ilk.metin))
                        .font(Tema.serif(.body)).foregroundStyle(Tema.metin).lineSpacing(3)
                        .lineLimit(sonGunAcik ? nil : 6)
                        .contentTransition(.opacity)
                    HStack(spacing: 10) {
                        if soru != nil {
                            Button { withAnimation(.snappy) { sonGunAcik.toggle() } } label: {
                                Label(sonGunAcik ? "Gizle" : "Hatırla, sonra bak", systemImage: sonGunAcik ? "eye.slash" : "eye")
                            }
                            .buttonStyle(IkinciDugme())
                        }
                        Button { kurBaslat(depo.kurDakika) } label: { Label("Kürle başla", systemImage: "play.fill") }
                            .buttonStyle(IkinciDugme(renk: Tema.basari))
                    }
                }
            }
        }
    }

    private var baslik: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Dil.tr)).uppercased(with: Dil.tr))
                    .font(.system(size: 12, weight: .bold)).tracking(0.6).foregroundStyle(Tema.soluk)
                Text("Teoria").font(Tema.serif(.largeTitle, .bold)).foregroundStyle(Tema.metin)
            }
            Spacer()
            if !depo.kasa.bagli {
                Image(systemName: "icloud.slash").foregroundStyle(Tema.soluk).accessibilityLabel("Vault bağlı değil")
            }
            #if os(iOS)
            GuncelleDugmesi(cam: true)
            Button { ayarlar = true } label: {
                Image(systemName: "gearshape").font(.system(size: 15, weight: .semibold)).foregroundStyle(Tema.metin)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(.ultraThinMaterial))
                    .overlay(Circle().strokeBorder(Tema.cizgi.opacity(0.7), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ayarlar")
            #endif
        }
        .padding(.top, 8)
        #if os(iOS)
        .sheet(isPresented: $ayarlar) {
            AyarlarEkrani(kasa: depo.kasa).environmentObject(depo).preferredColorScheme(depo.tema.sema)
        }
        #endif
        .onAppear { if gecmis == nil { gecmis = depo.gecmisteBugun() } }
    }

    // MARK: Kür

    private var kurKarti: some View {
        Yuzey(dolgu: 20) {
            VStack(spacing: 18) {
                HStack(spacing: 20) {
                    ZStack {
                        Halka(oran: oran, renk: bitti ? Tema.basari : Tema.vurgu, kalinlik: 12)
                        VStack(spacing: 0) {
                            if bitti {
                                Image(systemName: "checkmark").font(.system(size: 30, weight: .bold)).foregroundStyle(Tema.basari)
                            } else {
                                Text("\(Int(d.bugunDakika.rounded()))").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(Tema.metin)
                                Text("/ \(depo.kurDakika) dk").font(.caption.weight(.medium)).foregroundStyle(Tema.ikincil)
                            }
                        }
                    }
                    .frame(width: 112, height: 112)
                    .animation(.spring(response: 0.8), value: oran)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(bitti ? "Bugünün işi tamam." : (d.bugunKur > 0 ? "Bir kür daha?" : "Bugünün kürü"))
                            .font(Tema.serif(.title2, .semibold)).foregroundStyle(Tema.metin)
                        Text(bitti ? "İstersen bir kür daha; istemezsen yarın." : altYazi)
                            .font(.subheadline).foregroundStyle(Tema.ikincil)
                    }
                    Spacer(minLength: 0)
                }
                SimgeSecici(secenekler: [5, 10, 15].map { .init(deger: $0, ad: "\($0) dk", sembol: "\($0).circle") },
                            secili: $depo.kurDakika)
                Button { Dokunus.kurBasla(); kurBaslat(depo.kurDakika) } label: {
                    Label(bitti ? "Bir kür daha" : "Kürü başlat", systemImage: "play.fill")
                }
                .buttonStyle(AnaDugme())
                if oneri10 {
                    Text("İki haftadır 5 dakikadasın. 10 dakikayı denemek istersen yukarıdan seç; istemezsen 5 dakika da yeter.")
                        .font(.footnote).foregroundStyle(Tema.ikincil)
                }
            }
        }
    }

    private var altYazi: String {
        if d.uzunAra { return "Hoş geldin. Bugün bir kademe hafif başlarız." }
        return "\(depo.kurDakika) dakika. Önce son okuduğun, sonra tekrar, sonra kademende iş."
    }

    private var oneri10: Bool {
        guard depo.kurDakika == 5, let ilk = Tarih.coz(depo.ilkGun) else { return false }
        return Date().timeIntervalSince(ilk) > 14 * 86_400 && d.kurlar.count >= 10
    }

    // MARK: Hatlar

    private var hatlarKarti: some View {
        Yuzey {
            VStack(alignment: .leading, spacing: 16) {
                Bolumbasi(metin: "Merdiven", sembol: "stairs")
                ForEach(Hat.allCases) { h in
                    let k = d.kademe(h)
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: h.sembol).foregroundStyle(Tema.hat(h)).frame(width: 22)
                            Text(h.ad).font(.headline).foregroundStyle(Tema.metin)
                            Text(Evre.of(k).rawValue).font(.caption).foregroundStyle(Tema.soluk)
                            Spacer()
                            Text("K\(k)").font(.system(.subheadline, design: .rounded).weight(.bold)).foregroundStyle(Tema.hat(h))
                        }
                        KademeCubugu(kademe: k, renk: Tema.hat(h), yukseklik: 7)
                        if let hd = d.hatlar[h], hd.yukari > 0 {
                            Text("+1 için \(3 - hd.yukari) kür daha hedefte").font(.caption2).foregroundStyle(Tema.soluk)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: Aforizma

    private var gunAforizmasi: Aforizma? {
        let a = depo.paket.aforizmalar
        guard !a.isEmpty else { return nil }
        let gun = Tarih.takvim.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return a[gun % a.count]
    }

    @ViewBuilder
    private var aforizmaKarti: some View {
        if let a = gunAforizmasi {
            let r = Tema.renk(depo.paket.kitap(a.kitap)?.renk)
            Yuzey(dolgu: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "quote.opening").font(.title2.weight(.bold)).foregroundStyle(r)
                    Text(a.metin).font(Tema.serif(.title2, .medium)).foregroundStyle(Tema.metin).lineSpacing(3)
                        .textSelection(.enabled)
                    HStack {
                        Text("— " + a.kaynak).font(.footnote.weight(.medium)).foregroundStyle(Tema.ikincil)
                        Spacer()
                        Button { depo.favori(a.id) } label: {
                            Image(systemName: d.favoriler.contains(a.id) ? "heart.fill" : "heart").foregroundStyle(r)
                        }
                        .buttonStyle(.plain)
                        .dokun(.impact(weight: .light), d.favoriler.contains(a.id))
                        ShareLink(item: "“\(a.metin)” — \(a.kaynak)") { Image(systemName: "square.and.arrow.up").foregroundStyle(Tema.ikincil) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .background(RadialGradient(colors: [r.opacity(0.15), .clear], center: .topLeading, startRadius: 0, endRadius: 260)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous)))
        }
    }

    private func gecmisKarti(_ i: Isaret, _ ad: String) -> some View {
        Yuzey {
            VStack(alignment: .leading, spacing: 8) {
                Bolumbasi(metin: ad + " bugün", sembol: "clock.arrow.circlepath", renk: Tema.altin)
                Text(i.metin).font(Tema.serif(.body)).foregroundStyle(Tema.metin).lineLimit(5)
                HStack {
                    Text("\(i.baslik) · \(Tarih.kisa(i.zaman))").font(.caption).foregroundStyle(Tema.soluk).lineLimit(1)
                    Spacer()
                    Button { depo.hatirlat(i.id) } label: {
                        Image(systemName: d.hatirlatmalar.contains(i.id) ? "bell.fill" : "bell")
                    }.buttonStyle(.plain).foregroundStyle(Tema.vurgu)
                    Button { sesAc(i.id) } label: { Image(systemName: "mic") }.buttonStyle(.plain).foregroundStyle(Tema.vurgu)
                }
            }
        }
    }

    // MARK: Hafta

    private var haftaKarti: some View {
        Yuzey {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Bolumbasi(metin: "Son 7 gün", sembol: "calendar")
                    Spacer()
                    Text("bu hafta \(d.buHaftaKur) kür").font(.subheadline.weight(.semibold)).foregroundStyle(Tema.metin)
                }
                HStack(spacing: 0) {
                    ForEach(Array(d.hafta.enumerated()), id: \.offset) { i, dk in
                        let gun = Date().gun(i - 6)
                        VStack(spacing: 6) {
                            ZStack {
                                Circle().fill(dk > 0 ? Tema.vurgu.opacity(0.15) : Color.clear)
                                Circle().strokeBorder(dk > 0 ? Tema.vurgu : Tema.cizgi, lineWidth: dk > 0 ? 2 : 1)
                                if dk > 0 { Text("\(Int(dk.rounded()))").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(Tema.vurgu) }
                            }
                            .frame(width: 34, height: 34)
                            Text(gun.formatted(.dateTime.weekday(.narrow).locale(Dil.tr))).font(.caption2.weight(.semibold))
                                .foregroundStyle(i == 6 ? Tema.metin : Tema.soluk)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private var kendiSesinKarti: some View {
        Yuzey {
            VStack(alignment: .leading, spacing: 12) {
                Bolumbasi(metin: "Senin cümlelerin", sembol: "pencil.line", renk: Tema.hat(.kur))
                ForEach(d.kendiCumleler.prefix(2)) { o in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(o.metin ?? "").font(Tema.serif(.body)).foregroundStyle(Tema.metin)
                        Text(Tarih.goreli(o.t)).font(.caption2).foregroundStyle(Tema.soluk)
                    }
                }
            }
        }
    }
}
