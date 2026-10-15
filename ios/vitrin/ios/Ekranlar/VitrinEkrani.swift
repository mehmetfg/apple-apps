// Ana sayfa: iki telefon (kilit · ana ekran) canlı önizleme, bugünün öğrenme kartı, otomasyon durumu, temalar.
import SwiftUI
import PhotosUI

struct VitrinEkrani: View {
    @EnvironmentObject var m: Merkez
    @Binding var sekme: Sekme
    @State private var ayarlar = false
    @State private var rehber = false
    @State private var secilenTema: Tema?
    @State private var fotoSecim: PhotosPickerItem?
    @State private var hareket = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    vitrin
                    bugun
                    otomasyon
                    temalar
                }
                .padding(.horizontal, 16).padding(.bottom, 30)
            }
            .background(Renkler.zemin)
            .navigationTitle("Vitrin")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { ayarlar = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $ayarlar) { AyarlarEkrani() }
            .sheet(isPresented: $rehber) { KestirmeRehberi() }
            .sheet(item: $secilenTema) { t in TemaDetay(t: t) }
            .onChange(of: fotoSecim) { _, yeni in
                guard let yeni else { return }
                Task {
                    if let veri = try? await yeni.loadTransferable(type: Data.self), let ad = Depo.gorselKaydet(veri),
                       let img = Depo.gorsel(ad, enUzun: 400) {
                        let (d, w) = Tema.fotograftan(palet: PaletCikar.renkler(img), foto: ad)
                        m.uygula(duvar: d, widgetlar: w)
                        m.duyur("Fotoğraftan tema kuruldu")
                        sekme = .duvar
                    }
                    fotoSecim = nil
                }
            }
        }
    }

    // MARK: iki telefon
    private var vitrin: some View {
        let d = m.gunlukDuvar()
        let w = Array(m.kayit.widgetlar.prefix(3))
        return VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 8) {
                    Canli(acik: hareket, sure: 8) { faz in
                        Telefon(yukseklik: 330) { u in
                            ZStack {
                                if let d { DuvarGorunum(duvar: d, g: m.gosterilen(d), faz: faz, fotoBoyu: 1200) } else { Color.black }
                                KilitKatmani(u: u)
                            }
                        }
                    }
                    Text("Kilit").font(.caption).foregroundStyle(Renkler.ikincil)
                }
                VStack(spacing: 8) {
                    Telefon(yukseklik: 330) { u in
                        ZStack {
                            if let d {
                                DuvarGorunum(duvar: { var a = d; a.icerik = .yok; return a }(), g: Gosterilen(), fotoBoyu: 1200)
                                    .blur(radius: 6 * u)
                            }
                            AnaKatmani(u: u, widgetler: anaWidgetlar(w, u: u))
                        }
                    }
                    Text("Ana ekran").font(.caption).foregroundStyle(Renkler.ikincil)
                }
            }
            .frame(maxWidth: .infinity)
            Button { withAnimation { hareket.toggle() } } label: {
                Label(hareket ? "Hareketi durdur" : "Hareketi oynat", systemImage: hareket ? "pause.fill" : "play.fill").font(.caption)
            }
            .buttonStyle(.bordered).controlSize(.small)
        }
        .padding(.top, 6)
    }

    private func anaWidgetlar(_ w: [WidgetTasarim], u: CGFloat) -> [AnyView] {
        guard let ilk = w.first else { return [] }
        let olcek = (430 - 56) * u / WidgetOlcu.boy(.systemMedium).width
        var a: [AnyView] = [AnyView(
            WidgetOnizleme(t: ilk, g: m.gosterilen(ilk), aile: .systemMedium, veri: m.veri, bilinen: m.bilinen)
                .scaleEffect(olcek).frame(width: 364 * olcek, height: 170 * olcek)
        )]
        if w.count > 2 {
            a.append(AnyView(HStack(spacing: 22 * u) {
                ForEach(w[1...2]) { t in
                    WidgetOnizleme(t: t, g: m.gosterilen(t), aile: .systemSmall, veri: m.veri, bilinen: m.bilinen)
                        .scaleEffect(olcek).frame(width: 170 * olcek, height: 170 * olcek)
                }
            }))
        }
        return a
    }

    // MARK: bugün
    @ViewBuilder private var bugun: some View {
        let kelimeler = Secici.gununKelimeleri(m.veri, .now, bilinen: m.bilinen)
        Baslik(ad: "Bugün", alt: "Duvar, widget ve kestirme aynı içeriği görür")
        if let k = kelimeler.first {
            Kart {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(k.c) · \(k.p)".uppercased()).font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Renkler.vurgu)
                        Spacer()
                        Button { Task { await Ses.ortak.soyle(k.w, url: k.au) } } label: { Image(systemName: "speaker.wave.2.fill") }
                        Button { m.biliyorum(k.w) } label: { Image(systemName: "checkmark.seal") }
                    }
                    Text(k.w).font(.system(size: 38, weight: .medium, design: .serif))
                    Text(k.ipa).foregroundStyle(Renkler.ikincil)
                    Text(k.trTam).font(.title3)
                    if !k.x.isEmpty { Text(k.x).italic().foregroundStyle(Renkler.ikincil) }
                    Divider().overlay(Renkler.cizgi).padding(.vertical, 4)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(kelimeler.dropFirst(), id: \.w) { x in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(x.w).font(.subheadline.weight(.semibold))
                                    Text(x.tr).font(.caption).foregroundStyle(Renkler.ikincil)
                                }
                                .padding(10).background(RoundedRectangle(cornerRadius: 12).fill(Renkler.kart2))
                                .onTapGesture { Task { await Ses.ortak.soyle(x.w, url: x.au) } }
                            }
                        }
                    }
                    Text("Widget'ta bu altı kelime gün boyunca sırayla döner.").font(.caption2).foregroundStyle(Renkler.ikincil)
                }
            }
        }
        HStack(alignment: .top, spacing: 12) {
            if let a = Secici.alinti(m.veri, .now) {
                Kart {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ALINTI").font(.caption2.weight(.bold)).tracking(1.2).foregroundStyle(Renkler.vurgu)
                        Text(a.metin).font(.system(.subheadline, design: .serif)).lineLimit(6)
                        Text(a.kaynak).font(.caption2).foregroundStyle(Renkler.ikincil).lineLimit(1)
                    }
                }
            }
            if let k = Secici.kavram(m.veri, .now) {
                Kart {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("KAVRAM").font(.caption2.weight(.bold)).tracking(1.2).foregroundStyle(Renkler.vurgu)
                        Text(k.terim).font(.system(.title3, design: .serif))
                        Text(k.tanim).font(.footnote).lineLimit(5)
                    }
                }
            }
        }
    }

    // MARK: otomasyon
    private var otomasyon: some View {
        Kart {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "wand.and.stars").font(.title2).foregroundStyle(Renkler.vurgu)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Her sabah yeni duvar").font(.headline)
                        Text("Kestirmeler 06:00'da günün duvarını üretir ve kilit ekranına koyar.").font(.footnote).foregroundStyle(Renkler.ikincil)
                    }
                }
                HStack(spacing: 10) {
                    Button { rehber = true } label: {
                        Label("Kurulum", systemImage: "list.number").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(Renkler.vurgu).foregroundStyle(.black)
                    Button {
                        Task {
                            guard let (img, _) = Cizer.gununDuvari() else { return }
                            do { try await Fotograflar.kaydet(img); m.duyur("Bugünün duvarı Fotoğraflar'da") } catch { m.duyur(error.localizedDescription) }
                        }
                    } label: { Label("Şimdi üret", systemImage: "photo.badge.arrow.down").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: temalar
    private var temalar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Baslik(ad: "Temalar", alt: "Duvar + dört widget, tek dokunuşla")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    PhotosPicker(selection: $fotoSecim, matching: .images) {
                        VStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 26, style: .continuous)
                                    .fill(LinearGradient(colors: [Renkler.kart2, Renkler.kart], startPoint: .top, endPoint: .bottom))
                                VStack(spacing: 8) {
                                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 30))
                                    Text("Fotoğrafından\ntema").font(.footnote).multilineTextAlignment(.center)
                                }
                            }
                            .frame(width: 120, height: 250)
                            Text("Kendi fotoğrafın").font(.caption.weight(.semibold))
                        }
                    }
                    .buttonStyle(.plain)
                    ForEach(Tema.hepsi) { t in
                        Button { secilenTema = t } label: {
                            VStack(spacing: 10) {
                                Telefon(yukseklik: 250) { u in
                                    ZStack {
                                        let d = t.duvar()
                                        DuvarGorunum(duvar: d, g: m.gosterilen(d), fotoBoyu: 600)
                                        KilitKatmani(u: u).opacity(0.9)
                                    }
                                }
                                VStack(spacing: 1) {
                                    Text(t.ad).font(.caption.weight(.semibold))
                                    Text(t.not).font(.caption2).foregroundStyle(Renkler.ikincil).lineLimit(1).frame(width: 130)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }
}

struct TemaDetay: View {
    @EnvironmentObject var m: Merkez
    @Environment(\.dismiss) var kapat
    var t: Tema

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    let d = t.duvar()
                    Canli(acik: true, sure: 6) { faz in
                        Telefon(yukseklik: 420) { u in
                            ZStack {
                                DuvarGorunum(duvar: d, g: m.gosterilen(d), faz: faz, fotoBoyu: 1200)
                                KilitKatmani(u: u)
                            }
                        }
                    }
                    let w = t.widgetlar()
                    WidgetOnizleme(t: w[0], g: m.gosterilen(w[0]), aile: .systemMedium, veri: m.veri, bilinen: m.bilinen)
                    HStack(spacing: 16) {
                        ForEach(w[1...2]) { x in
                            WidgetOnizleme(t: x, g: m.gosterilen(x), aile: .systemSmall, veri: m.veri, bilinen: m.bilinen)
                        }
                    }
                    WidgetOnizleme(t: w[3], g: m.gosterilen(w[3]), aile: .systemMedium, veri: m.veri, bilinen: m.bilinen)
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            }
            .background(Renkler.zemin)
            .navigationTitle(t.ad)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { kapat() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    m.uygula(t); kapat()
                } label: {
                    Text("Temayı ekle").fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 18).fill(Renkler.vurgu)).foregroundStyle(.black)
                }
                .padding(16)
                .background(.ultraThinMaterial)
            }
        }
    }
}
