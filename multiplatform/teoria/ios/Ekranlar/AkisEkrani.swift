// Akış — X gibi: işaretlerin ve kendi alıntıların, en yeniden eskiye, tek sütun.
// Üst satır: Akış · Favoriler · Hatırlatmalar · Yer işaretleri · Benim; sağda ⌕ (arama) ve ☰ (zaman + tür).
// Arama ve süzgeçler varsayılan olarak gizli. Grafik, gündem kartı, ikinci süzgeç satırı yok.
// Yükleme tembel: 20'şer gönderi, aşağı inmeden sonrakiler kurulmaz. İlk açılışta gönderiler alttan kayarak gelir.
// Alıntıla → kendi yorumun olay günlüğüne yazılır, akışta "Sen" gönderisi olur; istersen X'te paylaşırsın.
// iPhone (2026-10-07): üst çubuk sabit durmaz — başlık kayarak gider, yerine küçük bir konum kapsülü kalır.
//   Başlıkta "Okuduğun" şeridi (dokun = o kitabın işaretleri), sekme hapları, güncelle düğmesi.
// Gün değişince araya sessiz gün ayracı girer. Kendi gönderini (yorum · alıntı · fikir) silebilirsin.
import SwiftUI

enum AkisSekmesi: String, CaseIterable, Identifiable {
    case akis, favori, hatirlat, yer, benim
    var id: String { rawValue }
    var ad: String {
        switch self {
        case .akis: "Akış"
        case .favori: "Favoriler"
        case .hatirlat: "Hatırlatmalar"
        case .yer: "Yer işaretleri"
        case .benim: "Benim"
        }
    }
    var sembol: String {
        switch self {
        case .akis: "text.bubble"
        case .favori: "heart"
        case .hatirlat: "bell"
        case .yer: "bookmark"
        case .benim: "person.crop.circle"
        }
    }
}

/// Soldaki akışın yoğunluğu: Kart (geniş, eski) · Kompakt (küçük yazı, dar kart) · Satır (tek bakışta çok içerik).
enum AkisGorunumu: String, CaseIterable, Identifiable {
    case kart, kompakt, satir
    var id: String { rawValue }
    var ad: String { switch self { case .kart: "Kart"; case .kompakt: "Kompakt"; case .satir: "Satır" } }
    var sembol: String { switch self { case .kart: "rectangle.grid.1x2"; case .kompakt: "list.bullet.rectangle"; case .satir: "list.bullet" } }
    static var varsayilan: AkisGorunumu {
        #if os(macOS)
        .kompakt
        #else
        .kart
        #endif
    }
}

enum Donem: String, CaseIterable, Identifiable {
    case tumu, hafta, ay, gecenAy, ikiAy, ucAy, gecenYil, ozel
    var id: String { rawValue }
    var ad: String {
        switch self {
        case .tumu: "Tüm zamanlar"
        case .hafta: "Bu hafta"
        case .ay: "Bu ay"
        case .gecenAy: "Geçen ay"
        case .ikiAy: "İki ay önce"
        case .ucAy: "Üç ay önce"
        case .gecenYil: "Geçen yıl"
        case .ozel: "Özel aralık…"
        }
    }

    func aralik(_ ozel: ClosedRange<Date>, simdi: Date = Date()) -> ClosedRange<Date>? {
        let t = Tarih.takvim
        func ay(_ geri: Int) -> ClosedRange<Date>? {
            guard let a = t.date(byAdding: .month, value: -geri, to: simdi), let i = t.dateInterval(of: .month, for: a) else { return nil }
            return i.start...i.end
        }
        switch self {
        case .tumu: return nil
        case .hafta: return (t.dateInterval(of: .weekOfYear, for: simdi)?.start ?? simdi.gun(-7))...simdi
        case .ay: return ay(0)
        case .gecenAy: return ay(1)
        case .ikiAy: return ay(2)
        case .ucAy: return ay(3)
        case .gecenYil:
            guard let a = t.date(byAdding: .year, value: -1, to: simdi), let i = t.dateInterval(of: .year, for: a) else { return nil }
            return i.start...i.end
        case .ozel: return ozel
        }
    }
}

/// Akıştaki bir gönderi: kitap işareti ya da senin alıntın / yorumun.
enum AkisOgesi: Identifiable {
    case isaret(Isaret)
    case sen(Olay)
    case ses(Olay)
    var id: String { switch self { case .isaret(let i): i.id; case .sen(let o), .ses(let o): o.id } }
    var zaman: Date { switch self { case .isaret(let i): i.zaman; case .sen(let o), .ses(let o): o.t } }
}

/// iPhone: kendi gezinme yığını içinde akış.
struct AkisEkrani: View {
    var sesAc: (String?) -> Void

    var body: some View {
        NavigationStack {
            AkisListesi(sesAc: sesAc)
                .background(Tema.arka.ignoresSafeArea())
                #if os(iOS)
                .toolbar(.hidden, for: .navigationBar)
                #endif
        }
    }
}

/// Akışın kendisi. Mac'te `sec` verilir: dokunuş gönderiyi sağ bölmede açar.
struct AkisListesi: View {
    @EnvironmentObject var depo: Depo
    var sesAc: (String?) -> Void
    var secili: String? = nil
    var sec: ((Isaret) -> Void)? = nil
    var perdeli: String? = nil                 // Mac: sağda yazılırken soldaki aynı gönderinin metni de buzlu

    @State private var sekme: AkisSekmesi = .akis
    @State private var donem: Donem = .tumu
    @State private var ozelBas = Date().gun(-60)
    @State private var ozelSon = Date()
    @State private var ozelSayfa = false
    @State private var renk: Int?
    @State private var arama = ""
    @State private var aramaAcik = false
    @State private var suzgecAcik = false
    @State private var sinir = 20
    @State private var acik: String?
    @State private var alinti: AlintiHedefi?
    @State private var kitapSuzgec: String?
    @State private var ustGecti = false
    @FocusState private var aramaOdak: Bool
    @Namespace private var cizgi
    @AppStorage("teoria.akis.gorunum") private var gorunumHam = ""

    private static let sayfa = 20

    var gorunum: AkisGorunumu { AkisGorunumu(rawValue: gorunumHam) ?? .varsayilan }

    var aralik: ClosedRange<Date>? { donem.aralik(min(ozelBas, ozelSon)...max(ozelBas, ozelSon)) }
    var suzgecVar: Bool { donem != .tumu || renk != nil }

    var ogeler: [AkisOgesi] {
        let d = depo.durum
        var l: [Isaret] = depo.akis.isaretler
        switch sekme {
        case .favori: l = l.filter { d.favoriler.contains($0.id) }
        case .hatirlat: l = l.filter { d.hatirlatmalar.contains($0.id) }
        case .yer: l = l.filter { d.yerIsaretleri.contains($0.id) }
        default: break
        }
        if sekme == .benim { l = [] }
        var sen: [Olay] = []
        if sekme == .benim { sen = d.kendiCumleler }
        else if sekme == .akis && renk == nil { sen = d.kendiCumleler.filter { $0.rol == "alinti" || $0.rol == "yorum" || $0.rol == "fikir" } }
        if let k = kitapSuzgec {
            l = l.filter { $0.kitap == k }
            sen = sen.filter { o in o.hedef.flatMap { depo.isaret($0) }?.kitap == k }
        }
        if let a = aralik {
            l = l.filter { a.contains($0.zaman) }
            sen = sen.filter { a.contains($0.t) }
        }
        if let r = renk { l = l.filter { $0.renk == r } }
        let q = Dil.normal(arama)
        if !q.isEmpty {
            l = l.filter { Dil.normal($0.metin + " " + $0.baslik).contains(q) }
            sen = sen.filter { Dil.normal($0.metin ?? "").contains(q) }
        }
        var ses: [Olay] = sekme == .benim ? d.sesNotlari : []
        if let a = aralik { ses = ses.filter { a.contains($0.t) } }
        if !q.isEmpty { ses = [] }
        let hepsi: [AkisOgesi] = l.map { .isaret($0) } + sen.map { .sen($0) } + ses.map { .ses($0) }
        return hepsi.sorted { $0.zaman > $1.zaman }
    }

    var body: some View {
        Group {
            #if os(iOS)
            telefonGovde
            #else
            masaustuGovde
            #endif
        }
        .sheet(item: $alinti) { h in
            AlintiSayfasi(hedef: h).environmentObject(depo)
        }
        .sheet(isPresented: $ozelSayfa) { ozelAralik }
    }

    // MARK: iPhone — kayan başlık + konum kapsülü

    #if os(iOS)
    private var telefonGovde: some View {
        ScrollViewReader { kaydir in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    kapak.id("ust")
                        .background(GeometryReader { g in
                            Color.clear.preference(key: AkisKaydirma.self, value: g.frame(in: .named("akis")).maxY)
                        })
                    LazyVStack(alignment: .leading, spacing: 0) { icerik }
                }
                .frame(maxWidth: 640).frame(maxWidth: .infinity)
                .background(alignment: .top) {
                    if seckiGorunur, let x = depo.gununCumlesi() { KitapTulu(kitap: x.kitap, yukseklik: 520).padding(.top, -200) }
                }
            }
            .coordinateSpace(name: "akis")
            .onPreferenceChange(AkisKaydirma.self) { y in ustGectiMi(y < 30) }
            .modifier(KaydirmaOlcer { ustGectiMi($0) })
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    // Saat ve çentik bölgesinde içerik yazıyla çakışmasın: üst kenarda yumuşak solma.
                    GeometryReader { g in
                        let ust = g.safeAreaInsets.top
                        LinearGradient(stops: [.init(color: Tema.arka, location: 0),
                                               .init(color: Tema.arka, location: ust / (ust + 34)),
                                               .init(color: Tema.arka.opacity(0), location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: ust + 34)
                            .offset(y: -ust)
                    }
                    .allowsHitTesting(false)
                    if ustGecti {
                        konumKapsulu { withAnimation(.snappy) { kaydir.scrollTo("ust", anchor: .top) } }
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
            .refreshable { await depo.guncelle() }
            .onChange(of: sekme) { _, _ in sinir = Self.sayfa; kaydir.scrollTo("ust", anchor: .top) }
            .onChange(of: kitapSuzgec) { _, _ in sinir = Self.sayfa }
            .onChange(of: donem) { _, y in sinir = Self.sayfa; if y == .ozel { ozelSayfa = true } }
            .onChange(of: renk) { _, _ in sinir = Self.sayfa }
        }
    }

    private func ustGectiMi(_ g: Bool) {
        if g != ustGecti { withAnimation(.snappy(duration: 0.25)) { ustGecti = g } }
    }

    private var bugunSayisi: Int { depo.akis.isaretler.filter { Tarih.takvim.isDateInToday($0.zaman) }.count }
    private var altBaslik: String {
        var p: [String] = []
        let b = bugunSayisi
        p.append(b == 0 ? "Bugün işaret yok" : "Bugün \(b) işaret")
        let s = depo.akis.kitaplar.filter(\.suruyor).count
        if s > 0 { p.append("\(s) kitap okunuyor") }
        let o = depo.akis.kitaplar.filter(\.okunmadi).count
        if o > 0 { p.append("\(o) okunmamış") }
        return p.joined(separator: " · ")
    }

    private var kapak: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Dil.tr)).uppercased(with: Dil.tr))
                        .font(.system(size: 12, weight: .bold)).tracking(0.6).foregroundStyle(Tema.soluk)
                    Text("Akış").font(Tema.serif(.largeTitle, .bold)).foregroundStyle(Tema.metin)
                }
                Spacer(minLength: 0)
                camDugme(aramaAcik ? "xmark" : "magnifyingglass", etkin: !arama.isEmpty) {
                    withAnimation(.snappy) { aramaAcik.toggle() }
                    Dokunus.secim()
                    if aramaAcik { aramaOdak = true } else { arama = "" }
                }
                .accessibilityLabel(aramaAcik ? "Aramayı kapat" : "Ara")
                camDugme(suzgecVar ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease", etkin: suzgecVar) {
                    withAnimation(.snappy) { suzgecAcik.toggle() }
                    Dokunus.secim()
                }
                .accessibilityLabel("Zaman ve tür süzgeci")
                gorunumMenusu
                GuncelleDugmesi(cam: true)
            }
            Text(altBaslik).font(.system(size: 14)).foregroundStyle(Tema.ikincil).padding(.top, -8)
            if aramaAcik { aramaAlani.transition(.move(edge: .top).combined(with: .opacity)) }
            if suzgecAcik && sekme != .benim {
                HStack(spacing: 8) { zamanMenusu; turMenusu; Spacer() }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if !surenKitaplar.isEmpty && sekme != .benim { okudugunSeridi }
            sekmeHaplari
        }
        .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 4)
    }

    private func camDugme(_ s: String, etkin: Bool, _ f: @escaping () -> Void) -> some View {
        Button(action: f) {
            Image(systemName: s)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(etkin ? Tema.vurgu : Tema.metin)
                .frame(width: 38, height: 38)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().strokeBorder(Tema.cizgi.opacity(0.7), lineWidth: 0.5))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
    }

    private var okudugunSeridi: some View { kitapSuzgeci(boy: 54, yazili: true) }

    private var sekmeHaplari: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AkisSekmesi.allCases) { s in
                    let sec = sekme == s
                    Button {
                        withAnimation(.snappy(duration: 0.3)) { sekme = s }
                    } label: {
                        Label(s.ad, systemImage: sec ? s.sembol + ".fill" : s.sembol)
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(sec ? Tema.metin : Tema.yuzey))
                            .overlay(Capsule().strokeBorder(Tema.cizgi.opacity(sec ? 0 : 0.8), lineWidth: 0.6))
                            .foregroundStyle(sec ? Tema.arka : Tema.ikincil)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .dokun(.selection, sekme)
                }
            }
            .padding(.horizontal, 18)
        }
        .padding(.horizontal, -18)
    }

    /// Başlık kaydıktan sonra nerede olduğunu söyleyen küçük kapsül; dokun = başa dön.
    private func konumKapsulu(_ f: @escaping () -> Void) -> some View {
        Button(action: f) {
            HStack(spacing: 7) {
                Image(systemName: sekme.sembol + ".fill").foregroundStyle(Tema.vurgu)
                Text(sekme.ad).foregroundStyle(Tema.metin)
                if let k = kitapSuzgec, let kk = depo.akis.kitaplar.first(where: { $0.id == k }) {
                    Text("· \(kk.baslik.kodsuz)").foregroundStyle(Tema.ikincil).lineLimit(1)
                }
                if suzgecVar { Image(systemName: "line.3.horizontal.decrease").foregroundStyle(Tema.vurgu) }
                Image(systemName: "chevron.up").font(.system(size: 10, weight: .bold)).foregroundStyle(Tema.soluk)
            }
            .font(.system(size: 13.5, weight: .semibold))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(.regularMaterial))
            .overlay(Capsule().strokeBorder(Tema.cizgi.opacity(0.6), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
            .frame(maxWidth: 300)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
        .accessibilityLabel("\(sekme.ad) — başa dön")
    }
    #endif

    private var surenKitaplar: [OkumaKitabi] {
        Array(depo.akis.kitaplar.filter(\.suruyor).sorted { $0.sonZaman > $1.sonZaman }.prefix(12))
    }

    /// Okuduğun kitaplar — yuvarlak kapak, halka okunan yüzdeyi çizer. Dokun: akış o kitaba süzülür; yine dokun: süzgeç kalkar.
    private func kitapSuzgeci(boy: CGFloat, yazili: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: yazili ? 14 : 10) {
                ForEach(surenKitaplar) { k in
                    let sec = kitapSuzgec == k.id
                    let r = Tema.kitap(k.id)
                    Button {
                        withAnimation(.snappy) { kitapSuzgec = sec ? nil : k.id }
                        Dokunus.secim()
                    } label: {
                        VStack(spacing: yazili ? 6 : 0) {
                            ZStack {
                                Circle().stroke(Tema.cizgi, lineWidth: yazili ? 3 : 2.5)
                                Circle().trim(from: 0, to: max(0.02, Double(k.yuzde) / 100))
                                    .stroke(sec ? Tema.vurgu : r, style: StrokeStyle(lineWidth: yazili ? 3 : 2.5, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                KitapAvatari(id: k.id, baslik: k.baslik, boy: boy)
                            }
                            .frame(width: boy + 10, height: boy + 10)
                            .scaleEffect(sec ? 1.06 : 1)
                            if yazili {
                                Text(k.baslik.kodsuz).font(.system(size: 11, weight: sec ? .bold : .medium))
                                    .foregroundStyle(sec ? Tema.metin : Tema.ikincil).lineLimit(1).frame(width: 70)
                                Text("%\(k.yuzde)").font(.system(size: 10, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(Tema.soluk)
                            }
                        }
                        .opacity(kitapSuzgec == nil || sec ? 1 : 0.4)
                    }
                    .buttonStyle(.plain)
                    .help("\(k.baslik.kodsuz) · %\(k.yuzde)")
                    .accessibilityLabel("\(k.baslik), yüzde \(k.yuzde)")
                }
            }
            .padding(.horizontal, yazili ? 18 : 14).padding(.vertical, 2)
        }
        .padding(.horizontal, yazili ? -18 : 0)
    }

    /// Kart · Kompakt · Satır seçici (arama ve süzgeç düğmelerinin yanında).
    private var gorunumMenusu: some View {
        Menu {
            Picker("Görünüm", selection: Binding(get: { gorunum }, set: { gorunumHam = $0.rawValue })) {
                ForEach(AkisGorunumu.allCases) { g in Label(g.ad, systemImage: g.sembol).tag(g) }
            }
        } label: {
            Image(systemName: gorunum.sembol).font(.system(size: 15, weight: .semibold)).foregroundStyle(Tema.metin)
                #if os(iOS)
                .frame(width: 38, height: 38)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().strokeBorder(Tema.cizgi.opacity(0.7), lineWidth: 0.5))
                #else
                .frame(width: 36, height: 36)
                #endif
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help("Görünüm: Kart · Kompakt · Satır")
    }

    private var aramaAlani: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Tema.ikincil)
            TextField("İşaretlerde ara", text: $arama)
                .textFieldStyle(.plain)
                .focused($aramaOdak)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !arama.isEmpty {
                Button { arama = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Tema.soluk) }.buttonStyle(.plain)
            }
        }
        .font(.system(size: 15))
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(Capsule().fill(Tema.yuzey2))
    }

    // MARK: Mac — sabit üst satır

    private var masaustuGovde: some View {
        ScrollViewReader { kaydir in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        icerik
                    } header: {
                        ustSatir.id("ust")
                    }
                }
                .frame(maxWidth: sec == nil ? 640 : .infinity)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: sekme) { _, _ in sinir = Self.sayfa; kaydir.scrollTo("ust", anchor: .top) }
            .onChange(of: donem) { _, y in sinir = Self.sayfa; if y == .ozel { ozelSayfa = true } }
            .onChange(of: renk) { _, _ in sinir = Self.sayfa }
            .onChange(of: kitapSuzgec) { _, _ in sinir = Self.sayfa }
        }
    }

    // MARK: Üst satır

    private var ustSatir: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: sec == nil ? 20 : 16) {
                        ForEach(AkisSekmesi.allCases) { s in sekmeDugmesi(s) }
                    }
                    .padding(.leading, 16).padding(.trailing, 8)
                }
                if suzgecAcik && sekme != .benim {
                    zamanMenusu.transition(.move(edge: .trailing).combined(with: .opacity))
                    turMenusu.transition(.move(edge: .trailing).combined(with: .opacity))
                }
                ikonDugme(aramaAcik ? "xmark" : "magnifyingglass", etkin: !arama.isEmpty) {
                    withAnimation(.snappy) { aramaAcik.toggle() }
                    Dokunus.secim()
                    if aramaAcik { aramaOdak = true } else { arama = "" }
                }
                .accessibilityLabel(aramaAcik ? "Aramayı kapat" : "Ara")
                ikonDugme(suzgecVar ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease", etkin: suzgecVar) {
                    withAnimation(.snappy) { suzgecAcik.toggle() }
                    Dokunus.secim()
                }
                .accessibilityLabel("Zaman ve tür süzgeci")
                gorunumMenusu
                    .padding(.trailing, 10)
            }
            .frame(height: 50)
            if !surenKitaplar.isEmpty && sekme != .benim {
                kitapSuzgeci(boy: 30, yazili: false)
                    .padding(.bottom, 8)
            }
            if aramaAcik {
                aramaAlani
                    .padding(.horizontal, 16).padding(.bottom, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Rectangle().fill(Tema.cizgi).frame(height: 0.5)
        }
        .background(.bar)
    }

    private func sekmeDugmesi(_ s: AkisSekmesi) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.3)) { sekme = s }
        } label: {
            VStack(spacing: 10) {
                HStack(spacing: 5) {
                    Image(systemName: sekme == s ? s.sembol + ".fill" : s.sembol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(sekme == s ? Tema.vurgu : Tema.ikincil)
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: sekme == s)
                    if sekme == s || sec == nil {
                        Text(s.ad)
                            .font(.system(size: 14, weight: sekme == s ? .semibold : .regular))
                            .foregroundStyle(sekme == s ? Tema.metin : Tema.ikincil)
                    }
                }
                .help(s.ad)
                .fixedSize()
                ZStack {
                    Capsule().fill(Color.clear).frame(height: 4)
                    if sekme == s {
                        Capsule().fill(Tema.vurgu).frame(height: 4)
                            .matchedGeometryEffect(id: "cizgi", in: cizgi)
                    }
                }
            }
            .padding(.top, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dokun(.selection, sekme)
    }

    private func ikonDugme(_ s: String, etkin: Bool, _ f: @escaping () -> Void) -> some View {
        Button(action: f) {
            Image(systemName: s)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(etkin ? Tema.vurgu : Tema.metin)
                .frame(width: 36, height: 36)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
    }

    private var zamanMenusu: some View {
        Menu {
            Picker("Zaman", selection: $donem) { ForEach(Donem.allCases) { Text($0.ad).tag($0) } }
        } label: {
            kucukHap(donem == .tumu ? "Zaman" : (donem == .ozel ? "\(Tarih.kisa(ozelBas))–\(Tarih.kisa(ozelSon))" : donem.ad),
                     "calendar", donem != .tumu)
        }
        .menuStyle(.button).buttonStyle(.plain)
        .fixedSize()
    }

    private var turMenusu: some View {
        Menu {
            Button("Bütün türler") { renk = nil }
            ForEach(IsaretRengi.allCases) { r in
                Button { renk = r.rawValue } label: { Label(r.ad, systemImage: renk == r.rawValue ? "checkmark" : "circle.fill") }
            }
        } label: {
            kucukHap(renk.flatMap { IsaretRengi(rawValue: $0)?.ad } ?? "Tür", "highlighter", renk != nil)
        }
        .menuStyle(.button).buttonStyle(.plain)
        .fixedSize()
    }

    private func kucukHap(_ m: String, _ s: String, _ etkin: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: s).font(.system(size: 11, weight: .semibold))
            Text(m).font(.system(size: 13, weight: .semibold)).lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(etkin ? Tema.vurgu.opacity(0.14) : Tema.yuzey2))
        .foregroundStyle(etkin ? Tema.vurgu : Tema.metin)
    }

    private var ozelAralik: some View {
        NavigationStack {
            Form {
                DatePicker("Başlangıç", selection: $ozelBas, displayedComponents: .date)
                DatePicker("Bitiş", selection: $ozelSon, displayedComponents: .date)
                if let ilk = depo.akis.isaretler.map(\.zaman).min() {
                    Text("En eski işaretin: \(Tarih.kisa(ilk)) \(ilk.formatted(.dateTime.year()))").font(.footnote).foregroundStyle(Tema.ikincil)
                }
            }
            .navigationTitle("Özel aralık")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Tamam") { ozelSayfa = false } } }
        }
        .presentationDetents([.medium])
    }

    // MARK: İçerik (tembel)

    @ViewBuilder
    private var icerik: some View {
        let l = ogeler
        if sekme == .benim {
            if let g = depo.genelDegerlendirmeler.first {
                GenelDegerlendirmeKarti(d: g).padding(.horizontal, 12).padding(.top, 12)
            } else {
                Label("Yazdıkların ve sesli notların birikince Mac'te Claude'a “Teoria değerlendir” de; değerlendirme burada belirir.",
                      systemImage: "sparkles")
                    .font(.system(size: 13)).foregroundStyle(Tema.ikincil)
                    .padding(.horizontal, 16).padding(.top, 14)
            }
            Button { sesAc(nil) } label: { Label("Yeni sesli not", systemImage: "mic.fill") }
                .buttonStyle(IkinciDugme(renk: Tema.uyari))
                .padding(.horizontal, 16).padding(.vertical, 12)
        }
        if seckiGorunur, let x = depo.gununCumlesi() {
            SeckiKarti(isaret: x, boy: seckiBoy,
                       ac: { if let sec { sec(x) } },
                       yaz: { if let sec { sec(x) } else { alinti = AlintiHedefi(isaret: x, rol: "yorum") } })
                .padding(.horizontal, 12).padding(.top, 12)
                .belirme(0, etkin: depo.hareket)
        }
        if l.isEmpty {
            bos
        } else {
            let bloklar = AkisBlogu.kur(Array(l.prefix(sinir)), grupla: gorunum != .satir)
            ForEach(Array(bloklar.enumerated()), id: \.element.id) { n, b in
                Group {
                    switch b {
                    case .gun(let g, let i, let k):
                        GunBasligi(gun: g, isaret: i, kitap: k, kucuk: gorunum != .kart)
                    case .seri(let x):
                        if gorunum == .satir, let i = x.first {
                            isaretGonderisi(i)
                        } else {
                            SeriKarti(isaretler: x, kucuk: gorunum != .kart) { i, _ in isaretGonderisi(i) }
                        }
                    case .tek(.ses(let olay)):
                        SesSatiri(olay: olay).padding(.horizontal, 12).padding(.vertical, 8).akisKarti()
                    case .tek(.sen(let olay)):
                        SenGonderisi(olay: olay, alintila: { i in alinti = AlintiHedefi(isaret: i, rol: "alinti") },
                                     perde: perdeli != nil && olay.hedef == perdeli, yogunluk: gorunum)
                            .contentShape(Rectangle())
                            .onTapGesture { if let sec, let h = olay.hedef, let x = depo.isaret(h) { sec(x) } }
                    case .tek(.isaret(let i)):
                        isaretGonderisi(i)
                    }
                }
                .padding(.horizontal, blokKenar(b)).padding(.bottom, blokAlt(b))
                .belirme(n, etkin: n < 14 && depo.hareket)
            }
            if l.count > sinir {
                HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                    .padding(.vertical, 24)
                    .onAppear {
                        // Kullanıcı gerçekten dibe indiğinde bir sonraki sayfa kurulur.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { sinir += Self.sayfa }
                    }
            } else {
                VStack(spacing: 8) {
                    Text("❧").font(.system(size: 22, design: .serif)).foregroundStyle(Tema.soluk)
                    Text(l.count == 1 ? "Tek gönderi" : "\(l.count) gönderi · hepsi bu")
                        .font(.system(size: 13)).foregroundStyle(Tema.soluk)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 32)
            }
        }
    }

    private var seckiBoy: SeckiKarti.Boy {
        #if os(iOS)
        .telefon
        #else
        .dar
        #endif
    }

    /// Akışın başında günün cümlesi: yalnız ana akışta, süzgeçsiz ve aramasızken.
    private var seckiGorunur: Bool {
        sec == nil && sekme == .akis && !suzgecVar && arama.isEmpty && kitapSuzgec == nil   // Mac: sağdaki sahnede
    }

    private func blokKenar(_ b: AkisBlogu) -> CGFloat {
        if case .gun = b { return 0 }
        return gorunum == .satir ? 8 : 12
    }

    private func blokAlt(_ b: AkisBlogu) -> CGFloat {
        if case .gun = b { return 0 }
        return gorunum == .kart ? 14 : (gorunum == .kompakt ? 10 : 4)
    }

    private func isaretGonderisi(_ x: Isaret) -> some View {
        GonderiSatiri(isaret: x, acik: acik == x.id, secili: secili == x.id, perde: perdeli == x.id,
                      secilebilir: sec == nil, yogunluk: gorunum, sesAc: sesAc,
                      alintila: { alinti = AlintiHedefi(isaret: x, rol: $0) })
            .contentShape(Rectangle())
            .onTapGesture {
                if let sec { sec(x) } else { withAnimation(.snappy) { acik = acik == x.id ? nil : x.id } }
            }
    }

    private var bos: some View {
        VStack(spacing: 10) {
            Image(systemName: bosSembol).font(.largeTitle).foregroundStyle(Tema.soluk)
            Text(bosMetin).font(.system(size: 15)).multilineTextAlignment(.center).foregroundStyle(Tema.ikincil)
            if suzgecVar || !arama.isEmpty {
                Button("Süzgeçleri temizle") { donem = .tumu; renk = nil; arama = "" }.font(.system(size: 15, weight: .semibold))
            }
        }
        .frame(maxWidth: .infinity).padding(48)
    }

    private var bosSembol: String {
        switch sekme {
        case .favori: "heart"
        case .hatirlat: "bell"
        case .yer: "bookmark"
        case .benim: "person"
        case .akis: "text.bubble"
        }
    }

    private var bosMetin: String {
        if suzgecVar || !arama.isEmpty { return "Bu süzgeçle gönderi yok." }
        switch sekme {
        case .favori: return "Bir işarete ♥ dokununca burada durur."
        case .hatirlat: return "🔔 dokunduğun işaretler kürde ve bildirimde sana geri döner."
        case .yer: return "🔖 yer işaretleri: sonra dönmek istediğin yerler."
        case .benim: return "Alıntıladıkların, yorumların ve kürde yazdığın kendi cümlelerin burada."
        case .akis: return "Henüz işaret yok. Voice Dream'de işaretlediklerin Mac'teki akış betiğiyle buraya gelir."
        }
    }
}

// MARK: - Avatar

/// Gönderi avatarı: kitabın kapağından yuvarlak kesit; kapak yoksa kitap renginde baş harf.
struct KitapAvatari: View {
    let id: String
    let baslik: String
    var boy: CGFloat = 40
    @State private var resim: Resim?

    var body: some View {
        let r = Tema.kitap(id)
        ZStack {
            if let resim {
                #if canImport(UIKit)
                Image(uiImage: resim).resizable().scaledToFill()
                #else
                Image(nsImage: resim).resizable().scaledToFill()
                #endif
            } else {
                Circle().fill(r.opacity(0.18))
                Text(String(kisa.prefix(1)).uppercased(with: Dil.tr))
                    .font(.system(size: boy * 0.42, weight: .bold, design: .serif)).foregroundStyle(r)
            }
        }
        .frame(width: boy, height: boy)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.08)))
        .onAppear { if resim == nil { resim = KapakDeposu.resim(id) } }
    }

    private var kisa: String { baslik.kodsuz.trimmingCharacters(in: .whitespaces) }
}

extension Isaret {
    /// "H01-G08 — Duhem-Quine ve Gerçekçilik" → "Duhem-Quine ve Gerçekçilik"
    var kisaBaslik: String { baslik.kodsuz }
}

// MARK: - Gönderi (işaret)

/// Bir işaret. Kart ve Kompakt'ta kendi kartı yoktur: `SeriKarti`nın (ya da kitap sayfasının) içinde bir parça olur —
/// kitap adı seride bir kez yazılır. Satır görünümünde kendi küçük kartıyla durur.
/// Kısa işaret (≤ 140 karakter) büyük serifle, alıntı gibi; uzun olan normal boyda ve kısaltılmış.
/// Eylemler sessiz: soluk simgeler; Mac'te yalnız fare üstündeyken ya da seçiliyken görünür (açık olanlar hep görünür).
struct GonderiSatiri: View {
    @EnvironmentObject var depo: Depo
    @Environment(\.openURL) private var ac
    let isaret: Isaret
    var acik: Bool
    var secili = false
    var perde = false                       // yalnız kullanıcı buzlandırdıysa: sağda bu işarete yazılırken metin buzlu
    var secilebilir = true                  // Mac'te kapalı: tıklama metin seçmesin, gönderiyi açsın
    var yogunluk: AkisGorunumu = .kart
    var sesAc: (String?) -> Void
    var alintila: (String) -> Void = { _ in }   // yalnız sağ bölme ve iPhone alıntı sayfası kullanır; soldaki kartta düğmesi yok
    @State private var ustunde = false

    private var kucuk: Bool { yogunluk != .kart }
    private var kisa: Bool { isaret.metin.count <= 140 }

    var body: some View {
        let d = depo.durum
        let kr = Tema.kitap(isaret.kitap)
        Group {
            if yogunluk == .satir { satir(d, kr) } else { parca(d, kr) }
        }
        #if os(macOS)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { ustunde = h } }
        #endif
        .contextMenu {
            Button { sesAc(isaret.id) } label: { Label("Sesli not", systemImage: "mic") }
            Button { depo.hatirlat(isaret.id) } label: { Label("Tekrar havuzuna al", systemImage: "bell") }
            Button { depo.favori(isaret.id) } label: { Label("Favori", systemImage: "heart") }
            Button { depo.yerIsareti(isaret.id) } label: { Label("Yer işareti", systemImage: "bookmark") }
            Text(isaret.kaynak)
        }
    }

    // Kart · Kompakt: seri içindeki parça
    private func parca(_ d: Durum, _ kr: Color) -> some View {
        VStack(alignment: .leading, spacing: kucuk ? 6 : 10) {
            if let t = IsaretRengi(rawValue: isaret.renk), t == .terim || t == .itiraz {
                Label(t.ad, systemImage: t.sembol)
                    .font(.system(size: kucuk ? 10.5 : 11.5, weight: .semibold))
                    .foregroundStyle(Tema.isaretRengi(isaret.renk))
                    .padding(.leading, kucuk ? 13 : 16)
            }
            metin(kr)
            baglamKutusu
            eylemler(d)
        }
        .padding(.horizontal, kucuk ? 13 : 18).padding(.top, kucuk ? 9 : 12).padding(.bottom, kucuk ? 5 : 6)
        .background {
            RoundedRectangle(cornerRadius: kucuk ? 12 : 16, style: .continuous)
                .fill(kr.opacity(secili ? 0.10 : 0))
                .padding(.horizontal, 6)
        }
        .contentShape(Rectangle())
        .animation(.snappy(duration: 0.25), value: secili)
    }

    private func metin(_ kr: Color) -> some View {
        let boyut: CGFloat = kisa ? (kucuk ? 16.5 : 21) : (kucuk ? 14 : 17)
        return HStack(alignment: .top, spacing: kucuk ? 10 : 13) {
            // çekirdek iddia: tam renk; öteki işaretler soluk çizgi — tür etiketsiz okunur
            let cekirdek = isaret.renk == IsaretRengi.cekirdek.rawValue
            Capsule().fill(kr.opacity(secili || cekirdek ? 1 : 0.4)).frame(width: secili ? 3.5 : (kucuk ? 2.5 : 3))
            Text(isaret.metin)
                .font(.system(size: boyut, design: .serif)).foregroundStyle(Tema.metin)
                .lineSpacing(boyut * (kisa ? 0.3 : 0.24))
                .lineLimit(acik ? nil : (kucuk ? 5 : 7))
                .secilebilir(secilebilir && !perde)
                .fixedSize(horizontal: false, vertical: true)
                .redacted(reason: perde ? .placeholder : [])
                .blur(radius: perde ? 8 : 0)
                .animation(.snappy(duration: 0.3), value: perde)
        }
    }

    // Satır: tek bakışta en çok içerik; eylemler sağ tık menüsünde
    private func satir(_ d: Durum, _ kr: Color) -> some View {
        HStack(alignment: .top, spacing: 9) {
            KitapAvatari(id: isaret.kitap, baslik: isaret.baslik, boy: 20).padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(isaret.metin).font(.system(size: 13, design: .serif)).foregroundStyle(Tema.metin).lineLimit(2).lineSpacing(1.5)
                    .redacted(reason: perde ? .placeholder : []).blur(radius: perde ? 6 : 0)
                Text(isaret.kisaBaslik).font(.system(size: 11)).foregroundStyle(kr).lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 3) {
                Text(isaret.zaman.formatted(.dateTime.hour().minute().locale(Dil.tr))).font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Tema.soluk).fixedSize()
                HStack(spacing: 4) {
                    if d.favoriler.contains(isaret.id) { Image(systemName: "heart.fill").foregroundStyle(Color.pink) }
                    if d.hatirlatmalar.contains(isaret.id) { Image(systemName: "bell.fill").foregroundStyle(Tema.vurgu) }
                    if d.yerIsaretleri.contains(isaret.id) { Image(systemName: "bookmark.fill").foregroundStyle(Tema.vurgu) }
                }
                .font(.system(size: 9))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .akisKarti(secili: secili, vurgu: kr, yaricap: 11)
    }

    @ViewBuilder private var baglamKutusu: some View {
        if acik, let b = isaret.baglam, !b.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text("BAĞLAM").font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(Tema.soluk)
                Text(b).font(.system(size: kucuk ? 13 : 14.5, design: .serif)).foregroundStyle(Tema.ikincil).lineSpacing(3)
            }
            .padding(.leading, kucuk ? 13 : 16).padding(.vertical, 4)
            .tamGenislik()
            .transition(.opacity)
        }
    }

    /// Soldaki kartta yorum ve alıntı yok: onlar sağ bölmede. Yerine mikrofon: sesli not (kayıt sürerken metin kapanır).
    private func eylemler(_ d: Durum) -> some View {
        let fav = d.favoriler.contains(isaret.id)
        let hat = d.hatirlatmalar.contains(isaret.id)
        let yer = d.yerIsaretleri.contains(isaret.id)
        let ses = d.sesSayisi(isaret.id)
        return HStack(spacing: kucuk ? 16 : 22) {
            if gorunur(ses != nil) > 0 { eylem("mic", ses, ses == nil ? Tema.soluk : Tema.uyari, "Sesli not") { sesAc(isaret.id) } }
            if gorunur(fav) > 0 { eylem(fav ? "heart.fill" : "heart", nil, fav ? Color.pink : Tema.soluk, "Favori") { if !fav { Dokunus.kalp() }; depo.favori(isaret.id) } }
            if gorunur(hat) > 0 { eylem(hat ? "bell.fill" : "bell", nil, hat ? Tema.vurgu : Tema.soluk, "Hatırlat") { depo.hatirlat(isaret.id) } }
            if gorunur(yer) > 0 { eylem(yer ? "bookmark.fill" : "bookmark", nil, yer ? Tema.vurgu : Tema.soluk, "Yer işareti") { depo.yerIsareti(isaret.id) } }
            Spacer(minLength: 0)
            Menu {
                Button {
                    if let u = XPaylas.adres(XPaylas.sigdir(yorum: "", alinti: isaret.metin, kaynak: isaret.kisaBaslik)) { ac(u) }
                } label: { Label("X'te paylaş", systemImage: "paperplane") }
                ShareLink(item: "“\(isaret.metin)” — \(isaret.kisaBaslik)") { Label("Paylaş…", systemImage: "square.and.arrow.up") }
            } label: {
                Image(systemName: "square.and.arrow.up").font(.system(size: kucuk ? 11.5 : 13)).foregroundStyle(Tema.soluk)
                    .frame(width: kucuk ? 22 : 28, height: kucuk ? 22 : 28)
            }
            .menuStyle(.button).buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(gorunur(false))
        }
        .padding(.leading, kucuk ? 13 : 16)
    }

    /// iPhone'da hep; Mac'te fare üstündeyken, seçiliyken ya da eylem açıksa.
    private func gorunur(_ etkin: Bool) -> Double {
        #if os(macOS)
        etkin || ustunde || secili ? 1 : 0
        #else
        1
        #endif
    }

    private func eylem(_ s: String, _ sayi: String?, _ r: Color, _ ad: String, _ f: @escaping () -> Void) -> some View {
        Button(action: f) {
            HStack(spacing: 4) {
                Image(systemName: s).font(.system(size: kucuk ? 11.5 : 13.5)).contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: s)
                if let sayi { Text(sayi).font(.system(size: kucuk ? 10.5 : 12)).monospacedDigit() }
            }
            .foregroundStyle(r)
            .frame(minWidth: kucuk ? 18 : 24, minHeight: kucuk ? 22 : 30, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .transition(.opacity)
        .accessibilityLabel(ad)
        .help(ad)
        .dokun(.impact(weight: .light), s)
    }
}

// MARK: - Senin gönderin (alıntı, yorum, kürde yazdığın cümle)

struct SenGonderisi: View {
    @EnvironmentObject var depo: Depo
    @Environment(\.openURL) private var ac
    let olay: Olay
    var alintila: (Isaret) -> Void = { _ in }
    var alintiGoster = true                 // Mac sağ bölmede kapalı: asıl metin perdenin altında kalsın
    var perde = false                       // Mac: kullanıcı buzlandırdıysa alıntı kartı buzlu
    var yogunluk: AkisGorunumu = .kart
    @State private var silinsinMi = false

    private var kucuk: Bool { yogunluk != .kart }

    var body: some View {
        let hedef = olay.hedef.flatMap { depo.isaret($0) }
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Tema.vurgu.gradient)
                Text("θ").font(.system(size: 19, weight: .bold, design: .serif)).foregroundStyle(.white)
            }
            .frame(width: kucuk ? 26 : 40, height: kucuk ? 26 : 40)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("Sen").font(.system(size: kucuk ? 13 : 15, weight: .semibold)).foregroundStyle(Tema.metin)
                    Text(etiket).font(.system(size: kucuk ? 12.5 : 15)).foregroundStyle(Tema.ikincil).lineLimit(1)
                    Text("· \(Tarih.goreli(olay.t))").font(.system(size: kucuk ? 12 : 15)).foregroundStyle(Tema.ikincil).fixedSize()
                    Spacer(minLength: 0)
                    Menu {
                        Button(role: .destructive) { silinsinMi = true } label: { Label("Sil", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 14)).foregroundStyle(Tema.soluk).frame(width: 26, height: 20)
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                }
                if olay.rol == "fikir" || olay.rol == "yorum", olay.deger == false {
                    Label("metne bakmadan", systemImage: "brain.head.profile")
                        .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Tema.basari)
                }
                Text(olay.metin ?? "")
                    .font(.system(size: kucuk ? 13.5 : 16)).foregroundStyle(Tema.metin).lineSpacing(kucuk ? 2.5 : 3.5)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if alintiGoster, let h = hedef, yogunluk != .satir {
                    AlintiKarti(isaret: h, satir: kucuk ? 2 : 4).padding(.top, 8)
                        .redacted(reason: perde ? .placeholder : []).blur(radius: perde ? 8 : 0)
                }
                #if os(iOS)
                HStack(spacing: 22) {
                    if let h = hedef {
                        Button { alintila(h) } label: { Image(systemName: "arrow.2.squarepath") }.buttonStyle(.plain)
                    }
                    Button {
                        let m = hedef.map { XPaylas.sigdir(yorum: olay.metin ?? "", alinti: $0.metin, kaynak: $0.kisaBaslik) } ?? String((olay.metin ?? "").prefix(280))
                        if let u = XPaylas.adres(m) { ac(u) }
                    } label: { Label("X'te paylaş", systemImage: "paperplane").labelStyle(.iconOnly) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("X'te paylaş")
                    ShareLink(item: olay.metin ?? "") { Image(systemName: "square.and.arrow.up") }.buttonStyle(.plain)
                }
                .font(.system(size: 14)).foregroundStyle(Tema.ikincil)
                .padding(.top, 8)
                #endif
            }
        }
        .padding(.horizontal, kucuk ? 12 : 16).padding(.top, kucuk ? 9 : 14).padding(.bottom, kucuk ? 9 : 12)
        .akisKarti(vurgu: Tema.vurgu, sen: true, yaricap: kucuk ? 16 : 24)
        .contextMenu {
            Button(role: .destructive) { silinsinMi = true } label: { Label("Sil", systemImage: "trash") }
        }
        .confirmationDialog("Bu gönderi silinsin mi?", isPresented: $silinsinMi, titleVisibility: .visible) {
            Button("Sil", role: .destructive) { withAnimation(.snappy) { depo.sil(olay) } }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Akıştan ve Benim sekmesinden kalkar; öbür cihazlarda da silinir.")
        }
    }

    private var etiket: String {
        switch olay.rol {
        case "alinti": "alıntıladı"
        case "yorum": "yorumladı"
        case "fikir": "fikrini yazdı"
        case "recall": "zihninden çağırdı"
        case "yeniden": "yeniden kurdu"
        default: olay.hat.map { "· \($0.ad) K\(olay.kademe ?? 0)" } ?? ""
        }
    }
}

/// X'teki gibi alıntılanan gönderinin küçük kartı.
struct AlintiKarti: View {
    let isaret: Isaret
    var satir = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                KitapKapagi(id: isaret.kitap, baslik: isaret.baslik, genislik: 16)
                Text(isaret.kisaBaslik).font(.system(size: 13.5, weight: .bold)).foregroundStyle(Tema.metin).lineLimit(1)
                Text("· \(Tarih.kisa(isaret.zaman))").font(.system(size: 13)).foregroundStyle(Tema.ikincil).fixedSize()
            }
            HStack(alignment: .top, spacing: 10) {
                Capsule().fill(Tema.kitap(isaret.kitap)).frame(width: 2.5)
                Text(isaret.metin).font(.system(size: 14.5, design: .serif)).foregroundStyle(Tema.metin).lineSpacing(2.5).lineLimit(satir)
            }
            .padding(.top, 4)
        }
        .padding(12).tamGenislik()
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Tema.arka.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Tema.cizgi))
    }
}

// MARK: - Alıntıla / yorum yaz

struct AlintiHedefi: Identifiable {
    let isaret: Isaret
    let rol: String          // "alinti" · "yorum"
    var id: String { isaret.id + rol }
}

/// iPhone'da sayfa olarak açılan yazma yüzeyi. Mac'te aynı `AlintiYazici` sağ bölmede gömülü durur.
struct AlintiSayfasi: View {
    @EnvironmentObject var depo: Depo
    @Environment(\.dismiss) private var kapat
    let hedef: AlintiHedefi

    var body: some View {
        NavigationStack {
            ScrollView {
                AlintiYazici(isaret: hedef.isaret, rol: hedef.rol, odakla: true) { kapat() }
                    .padding(16)
            }
            .background(Tema.arka.ignoresSafeArea())
            .navigationTitle(hedef.rol == "alinti" ? "Alıntıla" : "Yorum yaz")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } } }
        }
        .presentationDetents([.large])
    }
}

struct AlintiYazici: View {
    @EnvironmentObject var depo: Depo
    @Environment(\.openURL) private var ac
    let isaret: Isaret
    var rol: String = "alinti"
    var odakla = false
    var bitti: () -> Void = {}

    @State private var yazi = ""
    @State private var goster = false
    @State private var bakti = false
    @FocusState private var odak: Bool

    var xMetni: String { XPaylas.metin(yorum: yazi, alinti: isaret.metin, kaynak: isaret.kisaBaslik) }
    var oran: Double { Double(xMetni.count) / Double(XPaylas.sinir) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(Tema.vurgu.gradient)
                    Text("θ").font(.system(size: 19, weight: .bold, design: .serif)).foregroundStyle(.white)
                }
                .frame(width: 40, height: 40)
                ZStack(alignment: .topLeading) {
                    if yazi.isEmpty {
                        Text(rol == "alinti" ? "Yorumunu ekle" : "Bu işaret sana ne düşündürdü?")
                            .font(.system(size: 17)).foregroundStyle(Tema.soluk)
                            .padding(.top, 8).padding(.leading, 5)
                    }
                    TextEditor(text: $yazi)
                        .font(.system(size: 17))
                        .scrollContentBackground(.hidden)
                        .focused($odak)
                        .frame(minHeight: 110)
                }
            }
            HatirlamaPerdesi(acik: $goster, bakti: $bakti, ipucu: HatirlamaPerdesi<EmptyView>.ilkKelimeler(isaret.metin)) {
                AlintiKarti(isaret: isaret, satir: 8)
            }
            .padding(.leading, 52)
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Tema.cizgi, lineWidth: 2.5)
                    Circle().trim(from: 0, to: min(oran, 1))
                        .stroke(oran > 1 ? Tema.uyari : (oran > 0.9 ? Tema.altin : Tema.vurgu), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 22, height: 22)
                .animation(.snappy, value: oran)
                Text(oran > 1 ? "X için \(xMetni.count - XPaylas.sinir) karakter fazla; alıntı kısaltılır" : "\(XPaylas.sinir - xMetni.count) karakter kaldı")
                    .font(.system(size: 13)).foregroundStyle(oran > 1 ? Tema.uyari : Tema.soluk)
                Spacer()
            }
            .padding(.leading, 52)
            HStack(spacing: 10) {
                Button {
                    let u = XPaylas.adres(XPaylas.sigdir(yorum: yazi, alinti: isaret.metin, kaynak: isaret.kisaBaslik))
                    kaydet()
                    if let u { ac(u) }
                    bitti()
                } label: { Label("X'te paylaş", systemImage: "paperplane") }
                .buttonStyle(IkinciDugme())
                Button { kaydet(); bitti() } label: { Text("Kaydet") }
                    .buttonStyle(AnaDugme())
                    .disabled(yazi.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            Text("Kaydettiğin yorum Benim sekmesinde ve akışta durur. X'te paylaş, X'in paylaşım sayfasını metinle açar; göndere sen basarsın.")
                .font(.system(size: 12)).foregroundStyle(Tema.soluk)
        }
        .onAppear { if odakla { odak = true } }
        .onChange(of: isaret.id) { _, _ in yazi = ""; goster = false; bakti = false }
        .onChange(of: yazi) { _, _ in if goster { withAnimation(.snappy) { goster = false } } }   // yazarken metin kapanır
    }

    private func kaydet() {
        let m = yazi.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !m.isEmpty else { return }
        depo.ekle(Olay(tur: .kendiCumle, hedef: isaret.id, deger: bakti, metin: m, rol: rol))
        Dokunus.basari()
        yazi = ""
        bakti = false
    }
}


// MARK: - Akış kartı ve tür rozeti

/// İşaretin türü: renkli hap, simge + ad (çekirdek iddia · katılıyorum · terim · itiraz).
struct TurRozeti: View {
    let renk: Int
    var body: some View {
        let r = Tema.isaretRengi(renk)
        let t = IsaretRengi(rawValue: renk)
        HStack(spacing: 4) {
            Image(systemName: t?.sembol ?? "highlighter").font(.system(size: 9.5, weight: .bold))
            Text(t?.ad ?? "işaret").font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(r.opacity(0.13)))
        .foregroundStyle(r)
        .fixedSize()
    }
}

/// Akıştaki her öğe kendi kartında: yüzey, ince kenar, yumuşak gölge. Seçili/sen gönderisi vurgu renginde kenar alır.
private struct AkisKarti: ViewModifier {
    var secili = false
    var vurgu: Color = Tema.vurgu
    var sen = false
    var yaricap: CGFloat = 24
    @Environment(\.colorScheme) private var sema

    func body(content: Content) -> some View {
        let sekil = RoundedRectangle(cornerRadius: yaricap, style: .continuous)
        content
            .background {
                sekil.fill(Tema.yuzey)
                    .overlay {
                        if sen {
                            sekil.fill(LinearGradient(colors: [vurgu.opacity(0.09), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                    }
                    .shadow(color: .black.opacity(sema == .dark ? 0.35 : 0.06), radius: 14, y: 6)
            }
            .overlay {
                sekil.strokeBorder(secili ? vurgu.opacity(0.55) : (sen ? vurgu.opacity(0.22) : Tema.cizgi.opacity(0.8)),
                                   lineWidth: secili ? 1.5 : 0.6)
            }
            .contentShape(sekil)
            #if os(iOS)
            .contentShape(.contextMenuPreview, sekil)
            #endif
    }
}

extension View {
    func akisKarti(secili: Bool = false, vurgu: Color = Tema.vurgu, sen: Bool = false, yaricap: CGFloat = 24) -> some View {
        modifier(AkisKarti(secili: secili, vurgu: vurgu, sen: sen, yaricap: yaricap))
    }
}

/// Akış başlığının alt kenarı (iPhone): kaydıkça küçülür; eşik geçilince konum kapsülü belirir.
struct AkisKaydirma: PreferenceKey {
    static var defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

extension View {
    /// Mac'te metin seçimi tıklamayı yutar; gönderi açılsın diye kapatılabilir.
    @ViewBuilder func secilebilir(_ e: Bool) -> some View {
        if e { textSelection(.enabled) } else { self }
    }
}

#if os(iOS)
/// iOS 18+: kaydırma konumunu sistemden okur (başlık ≈ 340 nokta kaydığında kapsül belirir). iOS 17: tercih anahtarı.
struct KaydirmaOlcer: ViewModifier {
    var gecti: (Bool) -> Void
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 340 } action: { _, y in gecti(y) }
        } else {
            content
        }
    }
}
#endif
