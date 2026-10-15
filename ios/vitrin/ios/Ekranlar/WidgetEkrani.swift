// Widget Atölyesi: tasarımlar burada kurulur; telefonda widget'ı düzenlerken "Tasarım" listesinden seçilir.
import SwiftUI
import WidgetKit

struct WidgetlarEkrani: View {
    @EnvironmentObject var m: Merkez
    @Binding var acilacak: UUID?
    @State private var duzenlenen: WidgetTasarim?
    @State private var yardim = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Button { yardim.toggle() } label: {
                        Kart {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "questionmark.circle").foregroundStyle(Renkler.vurgu)
                                    Text("Telefona nasıl eklenir").font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Image(systemName: yardim ? "chevron.up" : "chevron.down").font(.footnote)
                                }
                                if yardim {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("1. Ana ekranda boş bir yere basılı tut › sol üstte **+** › **Araç Takımı Ekle** (iOS 26'da widget'ın adı)")
                                        Text("2. Aramaya **Vitrin** yaz, boyutu kaydırarak seç › **Araç Takımını Ekle** (kilit ekranı için: kilit ekranına basılı tut › Özelleştir › Kilitli Ekran)")
                                        Text("3. Widget'a basılı tut › **Araç Takımını Düzenle** › **Tasarım** › buradaki tasarımlardan birini seç")
                                        Text("Aynı tasarım her boyda kendine göre dizilir. Düğmeler: göz = anlamı aç, ok = sonraki, hoparlör = telaffuz.")
                                            .foregroundStyle(Renkler.ikincil)
                                    }
                                    .font(.footnote)
                                    .multilineTextAlignment(.leading)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Button { duzenlenen = yeni() } label: {
                        Label("Yeni widget tasarımı", systemImage: "plus")
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 18).fill(Renkler.vurgu))
                            .foregroundStyle(.black).fontWeight(.semibold)
                    }
                    .buttonStyle(.plain)

                    ForEach(m.kayit.widgetlar) { w in
                        Button { duzenlenen = w } label: { satir(w) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    var k = w; k.id = UUID(); k.ad = w.ad + " kopya"; m.kaydet(k)
                                } label: { Label("Kopyala", systemImage: "plus.square.on.square") }
                                Button(role: .destructive) { m.sil(w) } label: { Label("Sil", systemImage: "trash") }
                            }
                    }
                }
                .padding(16)
            }
            .background(Renkler.zemin)
            .navigationTitle("Widget")
            .fullScreenCover(item: $duzenlenen) { w in
                WidgetEditoru(t: w) { m.kaydet($0) }
            }
            .task(id: acilacak) {
                // widget'tan soğuk açılışta değer görünüm kurulmadan gelir; task(id:) ilk değeri de yakalar
                if let id = acilacak, let w = m.kayit.widgetlar.first(where: { $0.id == id }) { duzenlenen = w }
                acilacak = nil
            }
        }
    }

    private func satir(_ w: WidgetTasarim) -> some View {
        let g = m.gosterilen(w)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                WidgetOnizleme(t: w, g: g, aile: .systemSmall, veri: m.veri, bilinen: m.bilinen)
                    .scaleEffect(0.8, anchor: .topLeading).frame(width: 136, height: 136, alignment: .topLeading)
                WidgetOnizleme(t: w, g: g, aile: .systemMedium, veri: m.veri, bilinen: m.bilinen)
                    .scaleEffect(0.8 * 0.6, anchor: .topLeading).frame(width: 175, height: 82, alignment: .topLeading)
                    .opacity(0.9)
            }
            HStack {
                Image(systemName: w.icerik.simge).foregroundStyle(Renkler.vurgu)
                Text(w.ad).font(.subheadline.weight(.semibold))
                Spacer()
                Text(w.icerik.ad).font(.caption).foregroundStyle(Renkler.ikincil)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Renkler.kart))
    }

    private func yeni() -> WidgetTasarim {
        var w = (Tema.hepsi.randomElement() ?? Tema.hepsi[0]).widgetlar()[0]
        w.ad = "Yeni widget"
        return w
    }
}

struct WidgetEditoru: View {
    @EnvironmentObject var m: Merkez
    @Environment(\.dismiss) var kapat
    @State var t: WidgetTasarim
    var kaydet: (WidgetTasarim) -> Void
    @State private var bolum: EditorBolum = .icerik
    @State private var cevrik = false
    @State private var adim = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                onizleme.frame(height: 300).background(Renkler.zemin)
                Picker("", selection: $bolum) {
                    ForEach(EditorBolum.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.vertical, 8)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch bolum {
                        case .zemin:
                            ZeminPaneli(z: $t.zemin) { p in
                                t.yazi.renk = RenkHesap.yaziRengi(p, tur: t.zemin.tur)
                                t.yazi.vurgu = RenkHesap.vurgu(p, yazi: t.yazi.renk, tur: t.zemin.tur)
                            }
                        case .icerik: icerikPaneli
                        case .yazi: YaziPaneli(y: $t.yazi, palet: t.zemin.renkler)
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
                    TextField("Ad", text: $t.ad).multilineTextAlignment(.center).font(.headline).frame(maxWidth: 200)
                }
                ToolbarItem(placement: .confirmationAction) { Button("Kaydet") { kaydet(t); kapat() }.fontWeight(.semibold) }
            }
        }
    }

    private var onizleme: some View {
        let g = Gosterilen.hesapla(t.icerik, veri: m.veri, tarih: .now, adim: Secici.dilim(.now, dongu: t.dongu) + adim,
                                   bilinen: m.bilinen, metin: t.metin)
        return VStack(spacing: 8) {
            TabView {
                ForEach(WidgetOlcu.ana, id: \.self) { a in
                    VStack(spacing: 10) {
                        WidgetOnizleme(t: t, g: g, aile: a, veri: m.veri, bilinen: m.bilinen, cevrik: cevrik)
                            .scaleEffect(a == .systemLarge ? 0.62 : 1)
                            .frame(height: a == .systemLarge ? 240 : 180)
                            .animation(.smooth, value: g)
                        Text(WidgetOlcu.ad(a)).font(.caption).foregroundStyle(Renkler.ikincil)
                    }
                }
                kilitOnizleme(g)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            if t.icerik.donen || t.dugmeler {
                HStack(spacing: 10) {
                    if t.icerik == .kelime || t.icerik == .kavram {
                        Button { withAnimation(.smooth) { cevrik.toggle() } } label: { Image(systemName: "eye") }
                    }
                    Button { withAnimation(.smooth) { adim += 1; cevrik = false } } label: { Image(systemName: "arrow.forward") }
                    if t.icerik == .kelime {
                        Button { Task { await Ses.ortak.soyle(g.ana, url: g.ses) } } label: { Image(systemName: "speaker.wave.2.fill") }
                    }
                    Text("Önizlemede düğmeleri dene").font(.caption2).foregroundStyle(Renkler.ikincil)
                }
                .buttonStyle(.bordered).controlSize(.small)
                .padding(.bottom, 6)
            }
        }
    }

    private func kilitOnizleme(_ g: Gosterilen) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                WidgetOnizleme(t: t, g: g, aile: .accessoryCircular, veri: m.veri, bilinen: m.bilinen, cevrik: cevrik)
                WidgetOnizleme(t: t, g: g, aile: .accessoryRectangular, veri: m.veri, bilinen: m.bilinen, cevrik: cevrik)
            }
            WidgetOnizleme(t: t, g: g, aile: .accessoryInline, veri: m.veri, bilinen: m.bilinen, cevrik: cevrik)
                .font(.system(size: 15, weight: .medium))
            Text("Kilit ekranı — sistem tek renk çizer").font(.caption).foregroundStyle(Renkler.ikincil)
        }
        .padding(18)
        .background(
            ZeminGorunum(zemin: { var z = t.zemin; z.karartma = max(0.25, z.karartma); return z }(), fotoBoyu: 800)
                .clipShape(RoundedRectangle(cornerRadius: 24))
        )
    }

    private var icerikPaneli: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                ForEach(IcerikTuru.widgetIcin) { k in
                    Cip(ad: k.ad, simge: k.simge, secili: t.icerik == k) { withAnimation(.smooth) { t.icerik = k } }
                }
            }
            switch t.icerik {
            case .metin:
                TextField("Kendi cümlen", text: $t.metin, axis: .vertical)
                    .lineLimit(2...5)
                    .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Renkler.kart2))
            case .geriSayim:
                TextField("Ne için", text: $t.hedefAd)
                    .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Renkler.kart2))
                DatePicker("Tarih", selection: $t.hedefTarih, displayedComponents: .date)
            case .ilerleme:
                Text("Yön Belgesi'nin sonraki ölçüm günü: \(m.veri.odak.sonraki_olcum.isEmpty ? "—" : m.veri.odak.sonraki_olcum)")
                    .font(.footnote).foregroundStyle(Renkler.ikincil)
            default: EmptyView()
            }
            if t.icerik.donen {
                Picker("Değişim", selection: $t.dongu) {
                    Text("30 dk").tag(30); Text("1 saat").tag(60); Text("3 saat").tag(180); Text("Günde bir").tag(1440)
                }
                .pickerStyle(.segmented)
                Toggle("Düğmeler (çevir · sonraki · dinle)", isOn: $t.dugmeler)
                if t.icerik == .kelime || t.icerik == .kavram {
                    Toggle(isOn: $t.gizliBasla) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Önce hatırla")
                            Text("Anlam kapalı gelir; göz düğmesiyle açılır").font(.caption).foregroundStyle(Renkler.ikincil)
                        }
                    }
                }
            }
            if [.kelime, .alinti, .kavram, .saat].contains(t.icerik) {
                Toggle(t.icerik == .saat ? "Altta günün kelimesi" : "İkincil satır (örnek · kaynak)", isOn: $t.ikincil)
            }
        }
    }
}
