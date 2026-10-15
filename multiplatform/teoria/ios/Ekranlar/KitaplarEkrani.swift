// Kitaplar — kapaklı raf (süren · biten), Sözlük (kavram gökyüzünün yerine, A–Z) ve Teoria paketleri.
// Tembel: yalnız seçili bölüm kurulur; haftalık işaret grafiği "İstatistik" açılınca çizilir.
import SwiftUI
import Charts

enum KitapSekmesi: String, CaseIterable, Identifiable {
    case suren, okunmamis, biten, arsiv, sozluk, teoria
    var id: String { rawValue }
    var ad: String { switch self { case .suren: "Süren"; case .okunmamis: "Okunmamış"; case .biten: "Biten"; case .arsiv: "Arşiv"; case .sozluk: "Sözlük"; case .teoria: "Paketler" } }
    var sembol: String { switch self { case .suren: "book"; case .okunmamis: "tray"; case .biten: "checkmark.seal"; case .arsiv: "books.vertical"; case .sozluk: "character.book.closed"; case .teoria: "shippingbox" } }
}

struct KitaplarEkrani: View {
    @EnvironmentObject var depo: Depo
    @ObservedObject private var library = LibraryStore.shared
    var sesAc: (String?) -> Void
    var ilkSekme: KitapSekmesi = .suren
    @State private var sekme: KitapSekmesi?
    @State private var istatistik = false
    @State private var vitrinOrta: String?

    var secili: KitapSekmesi { sekme ?? ilkSekme }
    var suren: [OkumaKitabi] { depo.akis.kitaplar.filter(\.suruyor).sorted { $0.sonZaman > $1.sonZaman } }
    var biten: [OkumaKitabi] { depo.akis.kitaplar.filter { !$0.suruyor && !$0.okunmadi }.sorted { $0.sonZaman > $1.sonZaman } }
    /// Voice Dream'e eklenip henüz açılmamış metinler (son 45 gün) — en yeni eklenen başta.
    var okunmamis: [OkumaKitabi] { depo.akis.kitaplar.filter(\.okunmadi).sorted { $0.ilk > $1.ilk } }

    #if os(macOS)
    private let telefon = false
    private let enGenis: CGFloat = .infinity
    #else
    private let telefon = true
    private let enGenis: CGFloat = 760
    #endif

    var body: some View {
        NavigationStack {
            Group {
                if secili == .sozluk {
                    VStack(spacing: 0) {
                        secici.padding(.horizontal, 18).padding(.vertical, 10)
                        SozlukEkrani()
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            secici
                            switch secili {
                            case .suren: vitrin(suren); ozet; izgara(suren, bos: "Süren kitap yok. Voice Dream'de dinlemeye başladığın kitap burada durur.")
                            case .okunmamis:
                                Text("Voice Dream'e eklenmiş, henüz dinlemeye başlamadığın metinler. Başlayınca Süren'e geçer.")
                                    .font(.footnote).foregroundStyle(Tema.ikincil)
                                izgara(okunmamis, bos: "Bekleyen metin yok — Voice Dream'deki her şeye başlamışsın.")
                            case .biten: izgara(biten, bos: "Henüz biten kitap yok.")
                            case .arsiv: ArsivRafi()
                            case .teoria: teoriaPaketleri
                            case .sozluk: EmptyView()
                            }
                        }
                        .padding(18)
                        .frame(maxWidth: enGenis).frame(maxWidth: .infinity)
                    }
                    .refreshable { await depo.guncelle() }
                }
            }
            .background(Tema.arka.ignoresSafeArea())
            .navigationTitle("Kitaplar")
            #if os(iOS)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { GuncelleDugmesi() } }
            #endif
            .navigationDestination(for: String.self) { id in
                if let k = depo.akis.kitaplar.first(where: { $0.id == id }), let e = library.entry(forAkis: k) { BookScreen(entry: e) }
                else if let e = library.entry(id) { BookScreen(entry: e) }
                else { KitapDetay(kitapId: id, sesAc: sesAc) }
            }
        }
    }

    private var secici: some View {
        // iPhone'da beş sekme sığsın: seçili olmayanlarda yalnız simge.
        SimgeSecici(secenekler: KitapSekmesi.allCases.map { .init(deger: $0, ad: $0.ad, sembol: $0.sembol) },
                    secili: Binding(get: { secili }, set: { sekme = $0 }), sikisik: telefon)
    }

    // MARK: Özet (istatistik istenirse açılır)

    private var ozet: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                sayi("\(suren.count)", "süren")
                sayi("\(biten.count)", "biten")
                sayi("\(depo.akis.isaretler.count)", "işaret")
                sayi("\(depo.durum.oturmusKavramlar(depo.paket).count)", "oturan kavram")
            }
            DisclosureGroup(isExpanded: $istatistik.animation(.snappy)) {
                if istatistik { haftalik.padding(.top, 8) }
            } label: {
                Text("İstatistik").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.ikincil)
            }
            .tint(Tema.ikincil)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Tema.yuzey))
    }

    private var haftalik: some View {
        let haftalar: [(Date, Int)] = (0..<12).reversed().map { h in
            let bas = (Tarih.takvim.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()).gun(-7 * h)
            return (bas, depo.akis.isaretler.filter { $0.zaman >= bas && $0.zaman < bas.gun(7) }.count)
        }
        return VStack(alignment: .leading, spacing: 6) {
            Chart(haftalar, id: \.0) { h in
                AreaMark(x: .value("Hafta", h.0), y: .value("İşaret", h.1))
                    .foregroundStyle(LinearGradient(colors: [Tema.vurgu.opacity(0.35), Tema.vurgu.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Hafta", h.0), y: .value("İşaret", h.1))
                    .foregroundStyle(Tema.vurgu).interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
            .chartYAxis(.hidden)
            .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
            .frame(height: 90)
            Text("Son 12 hafta · haftalık işaret").font(.caption).foregroundStyle(Tema.soluk)
        }
    }

    private func sayi(_ s: String, _ ad: String) -> some View {
        VStack(spacing: 2) {
            Text(s).font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(Tema.metin)
            Text(ad).font(.caption2).foregroundStyle(Tema.ikincil)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Vitrin — süren kitaplar, 3B kayan raf

    /// Büyük kapaklar yatay kayar; ortadaki düz ve parlak durur, kenara kaydıkça cilt gibi döner ve geri çekilir.
    @ViewBuilder
    private func vitrin(_ l: [OkumaKitabi]) -> some View {
        if l.count > 1 {
            VStack(alignment: .leading, spacing: 10) {
                Label("Okuduğun", systemImage: "book.pages").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.ikincil)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 18) {
                        ForEach(l.prefix(10)) { k in
                            NavigationLink(value: k.id) {
                                VStack(alignment: .leading, spacing: 10) {
                                    KitapKapagi(id: k.id, baslik: k.baslik, genislik: 150)
                                        .overlay(alignment: .bottomTrailing) { IlerlemeRozeti(kitap: k).padding(8) }
                                    Text(k.baslik.kodsuz).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Tema.metin)
                                        .lineLimit(2).frame(width: 150, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                                    Text("\(k.isaret) işaret · \(Tarih.kisa(k.sonZaman))")
                                        .font(.system(size: 11.5)).foregroundStyle(Tema.soluk)
                                }
                            }
                            .buttonStyle(KapakBasma())
                            .scrollTransition(.interactive, axis: .horizontal) { v, f in
                                v.rotation3DEffect(.degrees(f.value * -16), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                                    .scaleEffect(1 - abs(f.value) * 0.12)
                                    .opacity(1 - abs(f.value) * 0.35)
                                    .offset(y: abs(f.value) * 10)
                            }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 24).padding(.vertical, 14)
                }
                .scrollTargetBehavior(.viewAligned)
                .padding(.horizontal, -18)
                .scrollPosition(id: $vitrinOrta)
                .onChange(of: vitrinOrta) { _, _ in Dokunus.secim() }
            }
        }
    }

    // MARK: Kapaklı ızgara

    @ViewBuilder
    private func izgara(_ l: [OkumaKitabi], bos: String) -> some View {
        if l.isEmpty {
            Text(bos).font(.subheadline).foregroundStyle(Tema.ikincil).padding(.vertical, 30)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 140), spacing: 14, alignment: .top)], spacing: 22) {
                ForEach(Array(l.enumerated()), id: \.element.id) { i, k in
                    NavigationLink(value: k.id) { KitapKarti(kitap: k) }
                        .buttonStyle(KapakBasma())
                        .belirme(i, etkin: i < 9 && depo.hareket)
                }
            }
        }
    }

    // MARK: Teoria paketleri

    private var teoriaPaketleri: some View {
        VStack(spacing: 12) {
            ForEach(depo.paket.kitaplar) { k in
                let kav = depo.paket.kavramlar.filter { $0.kitap == k.id }
                let otur = kav.filter { depo.durum.kartlar["hatirla:\($0.id)"]?.oturmus ?? false }.count
                let gorulen = kav.filter { depo.durum.kartlar["hatirla:\($0.id)"] != nil }.count
                let cum = depo.paket.cumleler.filter { $0.kitap == k.id }
                let kurulan = cum.filter { (depo.durum.kartlar["kur:\($0.id)"]?.tekrar ?? 0) > 0 }.count
                let r = Tema.renk(k.renk)
                Yuzey {
                    HStack(spacing: 16) {
                        ZStack {
                            Halka(oran: kav.isEmpty ? 0 : Double(gorulen) / Double(kav.count), renk: r.opacity(0.45), kalinlik: 7)
                            Halka(oran: kav.isEmpty ? 0 : Double(otur) / Double(kav.count), renk: r, kalinlik: 7).padding(11)
                            Image(systemName: k.sembol).font(.system(size: 15, weight: .semibold)).foregroundStyle(r)
                        }
                        .frame(width: 74, height: 74)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(k.baslik).font(Tema.serif(.headline)).foregroundStyle(Tema.metin)
                            Text(k.seri).font(.caption).foregroundStyle(Tema.soluk)
                            Text("\(gorulen)/\(kav.count) kavramla tanıştın · \(otur) oturdu · \(kurulan)/\(cum.count) cümle kuruldu")
                                .font(.caption).foregroundStyle(Tema.ikincil)
                            Text(k.oz).font(Tema.serif(.footnote)).foregroundStyle(Tema.ikincil).italic()
                        }
                    }
                }
            }
            Text("Dış halka: tanıştığın kavramlar. İç halka: kalıcı hafızaya geçenler (21 gün).")
                .font(.caption).foregroundStyle(Tema.soluk)
        }
    }
}

/// Raftaki kitap: Tezgâh'taki gibi düz kapak (sağ altta ilerleme halkası, bitince mühür), altında başlık ve işaret sayısı.
struct KitapKarti: View {
    let kitap: OkumaKitabi

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            KitapKapagi(id: kitap.id, baslik: kitap.baslik, genislik: 104)
                .overlay(alignment: .bottomTrailing) { IlerlemeRozeti(kitap: kitap, boy: 26).padding(6) }
            Text(kitap.baslik.kodsuz)
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.metin)
                .lineLimit(2).frame(width: 110, alignment: .leading)
            HStack(spacing: 4) {
                Image(systemName: "highlighter").font(.system(size: 9, weight: .semibold))
                Text("\(kitap.isaret) işaret")
            }
            .font(.system(size: 11)).foregroundStyle(Tema.soluk)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .accessibilityElement(children: .combine)
        .accessibilityValue("yüzde \(kitap.yuzde)")
    }
}

/// Kapak üstünde cam bir halka: okunma yüzdesi; bitince yeşil mühür.
struct IlerlemeRozeti: View {
    let kitap: OkumaKitabi
    var boy: CGFloat = 32

    var body: some View {
        let r = Tema.renk(Tema.renkAdi(kitap.id))
        ZStack {
            Circle().fill(.ultraThinMaterial)
            if kitap.yuzde >= 100 {
                Image(systemName: "checkmark.seal.fill").font(.system(size: boy * 0.55)).foregroundStyle(.white, Tema.basari)
                    .symbolRenderingMode(.palette)
            } else {
                Halka(oran: Double(kitap.yuzde) / 100, renk: r, kalinlik: boy * 0.11, iz: .white.opacity(0.35)).padding(boy * 0.12)
                Text("\(kitap.yuzde)").font(.system(size: boy * 0.3, weight: .bold, design: .rounded)).foregroundStyle(.primary)
            }
        }
        .frame(width: boy, height: boy)
        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
    }
}

/// Kapağa basınca: hafifçe içeri çöker ve düzleşir; bırakınca yaylanır. Dokunuşta sayfa hissi.
struct KapakBasma: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.65), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, basili in if basili { Dokunus.hafif(0.45) } }
    }
}

struct KitapDetay: View {
    @EnvironmentObject var depo: Depo
    let kitapId: String
    var sesAc: (String?) -> Void
    @State private var alinti: AlintiHedefi?
    @State private var acik: String?

    var body: some View {
        let k = depo.akis.kitaplar.first { $0.id == kitapId }
        let isaretler = depo.akis.isaretler.filter { $0.kitap == kitapId }.sorted { $0.zaman > $1.zaman }
        let r = Tema.renk(Tema.renkAdi(kitapId))
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if let k {
                    HStack(alignment: .top, spacing: 22) {
                        KitapKapagi(id: k.id, baslik: k.baslik, genislik: 120, egim: -10)
                            .padding(.bottom, 8)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(k.baslik.kodsuz)
                                .font(Tema.serif(.title2, .semibold)).foregroundStyle(Tema.metin)
                            if let t = k.tema { Text(t).font(Tema.serif(.footnote)).italic().foregroundStyle(Tema.ikincil) }
                            HStack(spacing: 10) {
                                ZStack {
                                    Halka(oran: Double(k.yuzde) / 100, renk: r, kalinlik: 5)
                                    Text("%\(k.yuzde)").font(.system(size: 11, weight: .bold, design: .rounded))
                                }
                                .frame(width: 44, height: 44)
                                Text("\(k.isaret) işaret · \(k.kelime.formatted()) kelime").font(.footnote).foregroundStyle(Tema.ikincil)
                            }
                        }
                    }
                    if k.okumalar.count > 1 {
                        Yuzey {
                            VStack(alignment: .leading, spacing: 8) {
                                Bolumbasi(metin: "İlerleme", sembol: "chart.line.uptrend.xyaxis")
                                Chart(k.okumalar.compactMap { o in Tarih.coz(o.tarih).map { ($0, o.yuzde ?? 0, o.yeni ?? 0) } }, id: \.0) { o in
                                    LineMark(x: .value("Gün", o.0), y: .value("%", o.1)).foregroundStyle(r)
                                    PointMark(x: .value("Gün", o.0), y: .value("%", o.1)).foregroundStyle(r)
                                        .symbolSize(CGFloat(30 + o.2 * 20))
                                }
                                .chartYScale(domain: 0...100)
                                .frame(height: 130)
                                Text("Nokta büyüklüğü: o oturumdaki yeni işaret sayısı").font(.caption2).foregroundStyle(Tema.soluk)
                            }
                        }
                    }
                }
                Bolumbasi(metin: "İşaretler", sembol: "highlighter")
                VStack(spacing: 0) {
                    ForEach(isaretler) { x in
                        GonderiSatiri(isaret: x, acik: acik == x.id, sesAc: sesAc, alintila: { alinti = AlintiHedefi(isaret: x, rol: $0) })
                            .onTapGesture { withAnimation(.snappy) { acik = acik == x.id ? nil : x.id } }
                        Rectangle().fill(Tema.cizgi).frame(height: 0.5)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Tema.yuzey))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .padding(18)
            .frame(maxWidth: 820).frame(maxWidth: .infinity)
        }
        .background(Tema.arka.ignoresSafeArea())
        .navigationTitle(k?.baslik.kodsuz ?? "")
        .onAppear { Dokunus.sayfa() }
        .sheet(item: $alinti) { AlintiSayfasi(hedef: $0).environmentObject(depo) }
    }
}

// MARK: - Arşiv — every listened book, kept even after Voice Dream drops it

struct ArsivRafi: View {
    @EnvironmentObject var depo: Depo
    @ObservedObject private var library = LibraryStore.shared
    @State private var arama = ""
    @State private var dis = false

    var body: some View {
        let q = Dil.normal(arama)
        let all = library.index.books.filter { (dis || $0.claude || $0.percent > 0 || $0.highlights > 0) && (q.isEmpty || Dil.normal($0.title).contains(q)) }
        let groups: [(String, String, [LibraryEntry])] = [
            ("Okunuyor", "book", all.filter { $0.inVD && $0.percent > 0 && $0.percent < 90 }),
            ("Bitti", "checkmark.seal", all.filter { $0.inVD && $0.percent >= 90 }),
            ("Voice Dream'den silinenler", "archivebox", all.filter { !$0.inVD }),
            ("Açılmamış", "tray", all.filter { $0.inVD && $0.percent == 0 }),
        ]
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Tema.ikincil)
                TextField("Kitap ara", text: $arama).textFieldStyle(.plain).autocorrectionDisabled()
                Toggle("Dış kitaplar", isOn: $dis).toggleStyle(.switch).font(.caption).fixedSize()
            }
            .font(.system(size: 15))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Capsule().fill(Tema.yuzey2))
            Text("\(library.index.books.count) kitap · \(library.index.books.reduce(0) { $0 + $1.highlights }) işaret · \(library.insights.count) özet. Voice Dream'den silinse de burada kalır.")
                .font(.caption).foregroundStyle(Tema.soluk)
            if library.index.books.isEmpty {
                Text("Kütüphane henüz eşitlenmedi. Mac'te ↻ Güncelle'ye bas ya da vault klasörünü bağla.")
                    .font(.subheadline).foregroundStyle(Tema.ikincil).padding(.vertical, 24)
            }
            ForEach(groups, id: \.0) { ad, sembol, l in
                if !l.isEmpty {
                    Label("\(ad) · \(l.count)", systemImage: sembol).font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.ikincil)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 140), spacing: 14, alignment: .top)], spacing: 22) {
                        ForEach(l) { e in
                            NavigationLink(value: e.id) { ArsivKarti(entry: e) }.buttonStyle(KapakBasma())
                        }
                    }
                }
            }
        }
    }
}

struct ArsivKarti: View {
    @ObservedObject private var library = LibraryStore.shared
    let entry: LibraryEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            KitapKapagi(id: entry.id, baslik: entry.titleParts.title, genislik: 104)
                .overlay(alignment: .topLeading) {
                    if library.insights[entry.id] != nil {
                        Image(systemName: "text.alignleft").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                            .padding(5).background(Circle().fill(Tema.vurgu)).padding(6)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if entry.percent > 0 {
                        ZStack {
                            Circle().fill(.ultraThinMaterial)
                            if entry.percent >= 90 { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Tema.basari) }
                            else { Halka(oran: Double(entry.percent) / 100, renk: Tema.kitap(entry.id), kalinlik: 2.5).padding(4) }
                        }
                        .frame(width: 24, height: 24).padding(6)
                    }
                }
            Text(entry.titleParts.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.metin).lineLimit(2).frame(width: 110, alignment: .leading)
            Text(entry.titleParts.author ?? (entry.highlights > 0 ? "\(entry.highlights) işaret" : "\(entry.chapters) bölüm"))
                .font(.system(size: 11)).foregroundStyle(Tema.soluk).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

// MARK: - Sözlük (kavram gökyüzünün yerine)

/// Bütün kavramlar A–Z. Satırda kitap rengi şerit, kavram, kısa tanım ve kalıcılık çubuğu.
/// iPhone'da dokununca kart sayfası açılır; Mac'te (genis) sağda ayrıntı durur.
struct SozlukEkrani: View {
    @EnvironmentObject var depo: Depo
    var genis = false
    @State private var arama = ""
    @State private var kitap: String?
    @State private var secili: Kavram?

    static let alfabe = Array("ABCÇDEFGĞHIİJKLMNOÖPRSŞTUÜVYZ").map(String.init)

    var kavramlar: [Kavram] {
        var l = depo.paket.kavramlar
        if let k = kitap { l = l.filter { $0.kitap == k } }
        let q = Dil.normal(arama)
        if !q.isEmpty { l = l.filter { Dil.normal($0.terim + " " + $0.tanim).contains(q) } }
        return l.sorted { $0.terim.compare($1.terim, locale: Dil.tr) == .orderedAscending }
    }

    static func harf(_ s: String) -> String {
        let h = String(s.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased(with: Dil.tr)
        return alfabe.contains(h) ? h : "#"
    }

    var body: some View {
        if genis {
            HStack(spacing: 0) {
                liste.frame(minWidth: 340, idealWidth: 420, maxWidth: 480)
                Rectangle().fill(Tema.cizgi).frame(width: 0.5)
                Group {
                    if let s = secili { ScrollView { KavramKarti(kavram: s).padding(32).frame(maxWidth: 760, alignment: .leading) } }
                    else {
                        VStack(spacing: 10) {
                            Image(systemName: "character.book.closed").font(.system(size: 40)).foregroundStyle(Tema.soluk)
                            Text("Soldan bir kavram seç.").foregroundStyle(Tema.ikincil)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            liste.sheet(item: $secili) { k in
                NavigationStack {
                    ScrollView { KavramKarti(kavram: k).padding(20) }
                        .background(Tema.arka.ignoresSafeArea())
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { secili = nil } } }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private var liste: some View {
        let l = kavramlar
        let gruplar = Dictionary(grouping: l) { Self.harf($0.terim) }
        let harfler = (Self.alfabe + ["#"]).filter { gruplar[$0] != nil }
        return ScrollViewReader { kaydir in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ustBilgi
                    ForEach(harfler, id: \.self) { h in
                        Section {
                            ForEach(gruplar[h] ?? []) { k in
                                Button { Dokunus.secim(); secili = k } label: { satir(k) }.buttonStyle(.plain)
                                Rectangle().fill(Tema.cizgi).frame(height: 0.5).padding(.leading, 34)
                            }
                        } header: {
                            Text(h).font(.system(size: 13, weight: .bold)).foregroundStyle(Tema.ikincil)
                                .padding(.horizontal, 18).padding(.vertical, 5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Tema.arka.opacity(0.96))
                                .id(h)
                        }
                    }
                    if l.isEmpty {
                        Text(depo.paket.kavramlar.isEmpty ? "Kart paketi henüz yüklenmedi." : "Bu aramayla kavram yok.")
                            .foregroundStyle(Tema.ikincil).frame(maxWidth: .infinity).padding(40)
                    }
                }
                .padding(.bottom, 24)
            }
            .overlay(alignment: .trailing) {
                // Harf şeridi: dokununca o harfe atlar
                VStack(spacing: 1) {
                    ForEach(harfler, id: \.self) { h in
                        Button { Dokunus.secim(); withAnimation(.snappy) { kaydir.scrollTo(h, anchor: .top) } } label: {
                            Text(h).font(.system(size: 10, weight: .semibold)).foregroundStyle(Tema.vurgu).frame(width: 18, height: 14)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.trailing, 2)
                .opacity(harfler.count > 6 ? 1 : 0)
            }
        }
    }

    private var ustBilgi: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Tema.ikincil)
                TextField("Kavram ara", text: $arama).textFieldStyle(.plain).autocorrectionDisabled()
            }
            .font(.system(size: 15))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Capsule().fill(Tema.yuzey2))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    kitapHapi(nil, "Hepsi", Tema.metin)
                    ForEach(depo.paket.kitaplar) { k in kitapHapi(k.id, k.baslik, Tema.renk(k.renk)) }
                }
            }
            let otur = depo.durum.oturmusKavramlar(depo.paket).count
            Text("\(depo.paket.kavramlar.count) kavram · \(otur) tanesi kalıcı hafızada (★)")
                .font(.system(size: 12)).foregroundStyle(Tema.soluk)
        }
        .padding(.horizontal, 18).padding(.vertical, 8)
    }

    private func kitapHapi(_ id: String?, _ ad: String, _ r: Color) -> some View {
        Button { Dokunus.secim(); withAnimation(.snappy) { kitap = id } } label: {
            Text(ad).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(kitap == id ? r.opacity(0.18) : Tema.yuzey))
                .overlay(Capsule().strokeBorder(kitap == id ? r.opacity(0.5) : Tema.cizgi))
                .foregroundStyle(kitap == id ? r : Tema.metin)
        }
        .buttonStyle(.plain)
    }

    private func satir(_ k: Kavram) -> some View {
        let kart = depo.durum.kartlar["hatirla:\(k.id)"]
        let r = Tema.renk(depo.paket.kitap(k.kitap)?.renk)
        let oran = min((kart?.kararlilik ?? 0) / 21, 1)
        return HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(r).frame(width: 4, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(k.terim).font(Tema.serif(.headline)).foregroundStyle(Tema.metin)
                    if kart?.oturmus == true { Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(Tema.altin) }
                }
                Text(k.tanim).font(.system(size: 13)).foregroundStyle(Tema.ikincil).lineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                ZStack(alignment: .leading) {
                    Capsule().fill(Tema.cizgi)
                    Capsule().fill(kart?.oturmus == true ? Tema.altin : r).frame(width: max(kart == nil ? 0 : 3, 44 * oran))
                }
                .frame(width: 44, height: 4)
                Text(kart == nil ? "yeni" : "\(Int(kart!.kararlilik)) g").font(.system(size: 10)).foregroundStyle(Tema.soluk).monospacedDigit()
            }
        }
        .padding(.leading, 18).padding(.trailing, 26).padding(.vertical, 10)
        .background(secili?.id == k.id && genis ? Tema.vurgu.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
    }
}

/// Bir kavramın kartı: tanım, ipucu, karıştırılan kavram, anahtar kelimeler, kalıcılık.
struct KavramKarti: View {
    @EnvironmentObject var depo: Depo
    let kavram: Kavram

    var body: some View {
        let kitap = depo.paket.kitap(kavram.kitap)
        let r = Tema.renk(kitap?.renk)
        let kart = depo.durum.kartlar["hatirla:\(kavram.id)"]
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(kitap?.baslik ?? "").font(.system(size: 13, weight: .semibold)).foregroundStyle(r)
                Text(kavram.terim).font(Tema.serif(.largeTitle, .semibold)).foregroundStyle(Tema.metin)
            }
            Text(kavram.tanim).font(Tema.serif(.title3)).foregroundStyle(Tema.metin).lineSpacing(3).textSelection(.enabled)
            if !kavram.ipucu.isEmpty {
                Label(kavram.ipucu, systemImage: "lightbulb").font(.callout).foregroundStyle(Tema.altin)
            }
            if let a = kavram.ayirt {
                VStack(alignment: .leading, spacing: 6) {
                    Bolumbasi(metin: "Karıştırma: \(a.karsi)", sembol: "arrow.left.arrow.right", renk: Tema.uyari)
                    Text(a.fark).font(.callout).foregroundStyle(Tema.ikincil)
                }
                .padding(14).tamGenislik()
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Tema.uyari.opacity(0.07)))
            }
            if !kavram.anahtar.isEmpty {
                AkanYerlesim(aralik: 6) { ForEach(kavram.anahtar, id: \.self) { Hap(metin: $0, renk: r) } }
            }
            Divider()
            if let kart {
                Label(kart.oturmus ? "Kalıcı hafızada · \(Int(kart.kararlilik)) gün" : "Kalıcılık \(Int(kart.kararlilik)) gün · \(kart.tekrar) karşılaşma",
                      systemImage: kart.oturmus ? "star.fill" : "star.leadinghalf.filled")
                    .font(.footnote).foregroundStyle(kart.oturmus ? Tema.altin : Tema.ikincil)
            } else {
                Label("Henüz kürde karşılaşmadın.", systemImage: "circle.dotted").font(.footnote).foregroundStyle(Tema.soluk)
            }
        }
    }
}
