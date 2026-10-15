// Duvar Stüdyosu: tasarım listesi + katmanlı düzenleyici (zemin · içerik · yazı).
import SwiftUI

struct DuvarlarEkrani: View {
    @EnvironmentObject var m: Merkez
    @State private var duzenlenen: Duvar?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Kart {
                        HStack(spacing: 12) {
                            Image(systemName: "calendar.badge.clock").font(.title2).foregroundStyle(Renkler.vurgu)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Günün duvarı listesi").font(.subheadline.weight(.semibold))
                                Text(m.kayit.gunlukListe.isEmpty ? "Boş — ilk tasarım kullanılır"
                                     : "\(m.kayit.gunlukListe.count) tasarım her gün sırayla · bugün: \(m.gunlukDuvar()?.ad ?? "—")")
                                    .font(.footnote).foregroundStyle(Renkler.ikincil)
                            }
                        }
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 20) {
                        Button { duzenlenen = yeni() } label: {
                            VStack(spacing: 10) {
                                Image(systemName: "plus").font(.system(size: 30, weight: .light))
                                Text("Yeni duvar").font(.subheadline)
                            }
                            .frame(maxWidth: .infinity).frame(height: 300)
                            .background(RoundedRectangle(cornerRadius: 28).stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6, 6])).foregroundStyle(Renkler.cizgi.opacity(3)))
                        }
                        .buttonStyle(.plain)
                        ForEach(m.kayit.duvarlar) { d in
                            Button { duzenlenen = d } label: { kucukResim(d) }
                                .buttonStyle(.plain)
                                .contextMenu { menu(d) }
                        }
                    }
                }
                .padding(16)
            }
            .background(Renkler.zemin)
            .navigationTitle("Duvar")
            .fullScreenCover(item: $duzenlenen) { d in
                DuvarEditoru(d: d) { m.kaydet($0) }
            }
        }
    }

    private func kucukResim(_ d: Duvar) -> some View {
        VStack(spacing: 8) {
            Telefon(yukseklik: 300) { u in
                ZStack {
                    DuvarGorunum(duvar: d, g: m.gosterilen(d), fotoBoyu: 900)
                    if d.hedef == .kilit { KilitKatmani(u: u).opacity(0.85) }
                }
            }
            HStack(spacing: 4) {
                if m.gunlukte(d) { Image(systemName: "calendar.badge.checkmark").foregroundStyle(Renkler.vurgu) }
                Text(d.ad).font(.footnote.weight(.medium)).lineLimit(1)
            }
        }
    }

    @ViewBuilder private func menu(_ d: Duvar) -> some View {
        Button { m.gunlukDegistir(d) } label: {
            Label(m.gunlukte(d) ? "Günlük listeden çıkar" : "Günlük listeye ekle", systemImage: "calendar")
        }
        Button {
            var k = d; k.id = UUID(); k.ad = d.ad + " kopya"
            m.kaydet(k)
        } label: { Label("Kopyala", systemImage: "plus.square.on.square") }
        Button {
            Task {
                guard let img = Cizer.duvar(d, g: m.gosterilen(d)) else { return }
                do { try await Fotograflar.kaydet(img); m.duyur("Fotoğraflar'a kaydedildi") } catch { m.duyur(error.localizedDescription) }
            }
        } label: { Label("Fotoğraflar'a kaydet", systemImage: "square.and.arrow.down") }
        Button(role: .destructive) { m.sil(d) } label: { Label("Sil", systemImage: "trash") }
    }

    private func yeni() -> Duvar {
        let t = Tema.hepsi.randomElement() ?? Tema.hepsi[0]
        var d = t.duvar()
        d.ad = "Yeni duvar"
        d.zemin.tohum = Int.random(in: 0...999)
        return d
    }
}

enum EditorBolum: String, CaseIterable, Identifiable {
    case zemin = "Zemin", icerik = "İçerik", yazi = "Yazı"
    var id: String { rawValue }
}

struct DuvarEditoru: View {
    @EnvironmentObject var m: Merkez
    @Environment(\.dismiss) var kapat
    @State var d: Duvar
    var kaydet: (Duvar) -> Void

    @State private var bolum: EditorBolum = .zemin
    @State private var katman: Hedef? = .kilit
    @State private var hareket = false
    @State private var gunKaydir = 0
    @State private var ayriliyor = false
    @State private var ozneDurum: String?

    private var tarih: Date { Calendar.current.date(byAdding: .day, value: gunKaydir, to: .now) ?? .now }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                onizleme
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(Renkler.zemin)
                Picker("", selection: $bolum) {
                    ForEach(EditorBolum.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.bottom, 8)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch bolum {
                        case .zemin:
                            ZeminPaneli(z: $d.zemin) { p in
                                d.yazi.renk = RenkHesap.yaziRengi(p, tur: d.zemin.tur, kart: d.kart)
                                d.yazi.vurgu = RenkHesap.vurgu(p, yazi: d.yazi.renk, tur: d.zemin.tur, kart: d.kart)
                            }
                        case .icerik: icerikPaneli
                        case .yazi: YaziPaneli(y: $d.yazi, palet: d.zemin.renkler)
                        }
                    }
                    .padding(16)
                }
                .background(Renkler.kart.ignoresSafeArea())
            }
            .background(Renkler.zemin)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } }
                ToolbarItem(placement: .principal) {
                    TextField("Ad", text: $d.ad).multilineTextAlignment(.center).font(.headline).frame(maxWidth: 200)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { kaydet(d); kapat() }.fontWeight(.semibold)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        Task {
                            guard let img = Cizer.duvar(d, g: Gosterilen.hesapla(d.icerik, veri: m.veri, tarih: tarih, adim: 0, bilinen: m.bilinen, metin: d.metin), tarih: tarih) else { return }
                            do { try await Fotograflar.kaydet(img); m.duyur("Fotoğraflar'a kaydedildi") } catch { m.duyur(error.localizedDescription) }
                        }
                    } label: { Label("Fotoğraflar'a kaydet", systemImage: "square.and.arrow.down") }
                    Spacer()
                    Button {
                        kaydet(d)
                        if !m.gunlukte(d) { m.gunlukDegistir(d) }
                        m.duyur("Günün duvarı listesine eklendi")
                    } label: { Label("Günlük", systemImage: m.gunlukte(d) ? "calendar.badge.checkmark" : "calendar.badge.plus") }
                }
            }
        }
    }

    private var onizleme: some View {
        let g = Gosterilen.hesapla(d.icerik, veri: m.veri, tarih: tarih, adim: 0, bilinen: m.bilinen, metin: d.metin)
        return VStack(spacing: 10) {
            Canli(acik: hareket, sure: 3) { faz in
                Telefon(yukseklik: 360) { u in
                    ZStack {
                        DuvarGorunum(duvar: d, g: g, tarih: tarih, faz: faz, fotoBoyu: 1400)
                        if katman == .kilit { KilitKatmani(u: u, tarih: tarih).allowsHitTesting(false) }
                        if katman == .ana { AnaKatmani(u: u).allowsHitTesting(false) }
                    }
                }
            }
            .animation(.smooth, value: d)
            HStack(spacing: 8) {
                Menu {
                    Picker("Katman", selection: $katman) {
                        Text("Kilit ekranı").tag(Hedef?.some(.kilit))
                        Text("Ana ekran").tag(Hedef?.some(.ana))
                        Text("Yalnız duvar").tag(Hedef?.none)
                    }
                } label: {
                    Label(katman?.ad ?? "Yalnız duvar", systemImage: "rectangle.on.rectangle").font(.footnote)
                }
                Button { hareket.toggle() } label: {
                    Label("Hareket", systemImage: hareket ? "pause.circle.fill" : "play.circle").font(.footnote)
                }
                if d.icerik.donen || d.icerik == .odak {
                    Stepper(value: $gunKaydir, in: -7...30) {
                        Text(gunKaydir == 0 ? "Bugün" : gunKaydir == 1 ? "Yarın" : "\(gunKaydir > 0 ? "+" : "")\(gunKaydir) gün").font(.footnote)
                    }
                    .fixedSize()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var icerikPaneli: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                ForEach(IcerikTuru.duvarIcin) { t in
                    Cip(ad: t.ad, simge: t.simge, secili: d.icerik == t) { withAnimation(.smooth) { d.icerik = t } }
                }
            }
            if d.icerik == .metin {
                TextField("Kendi cümlen", text: $d.metin, axis: .vertical)
                    .lineLimit(2...5)
                    .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Renkler.kart2))
            }
            if d.icerik != .yok {
                Kaydirici(ad: "Dikey konum", deger: $d.konum, aralik: 0.15...0.9, bicim: { String(format: "%.0f%%", $0 * 100) })
                Text(d.konum < 0.36 ? "Saat bu bölgede — kilit ekranında üst üste biner." : "Saatin ve widget sırasının altında.")
                    .font(.caption).foregroundStyle(d.konum < 0.36 ? .orange : Renkler.ikincil)
                HStack(spacing: 8) {
                    ForEach(KartStili.allCases) { k in Cip(ad: k.ad, secili: d.kart == k) { d.kart = k } }
                }
            }
            if d.zemin.tur == .foto, d.icerik != .yok {
                Toggle(isOn: Binding(get: { d.derinlik }, set: { yeni in
                    d.derinlik = yeni
                    guard yeni, let foto = d.zemin.foto, !Depo.ozneVar(foto) else { return }
                    ayriliyor = true; ozneDurum = nil
                    Task {
                        let ok = await OzneAyir.ayir(foto: foto)
                        ayriliyor = false
                        if !ok { d.derinlik = false; ozneDurum = "Bu fotoğrafta belirgin bir özne bulunamadı." }
                        else { d.zemin = d.zemin }   // önizlemeyi yenile
                    }
                })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Derinlik — metin öznenin arkasında")
                        Text("Fotoğraftaki kişi/nesne yazının önüne geçer").font(.caption).foregroundStyle(Renkler.ikincil)
                    }
                }
                if ayriliyor { ProgressView("Özne ayrılıyor…").font(.caption) }
                if let ozneDurum { Text(ozneDurum).font(.caption).foregroundStyle(.orange) }
            }
            Picker("Nerede", selection: $d.hedef) {
                ForEach(Hedef.allCases) { Text($0.ad).tag($0) }
            }
            .pickerStyle(.segmented)
            if d.icerik == .kelime, let k = Secici.kelime(m.veri, tarih, bilinen: m.bilinen) {
                Button { m.biliyorum(k.w) } label: {
                    Label("“\(k.w)” kelimesini biliyorum — bir daha çıkmasın", systemImage: "checkmark.seal")
                        .font(.footnote)
                }
            }
        }
    }
}
