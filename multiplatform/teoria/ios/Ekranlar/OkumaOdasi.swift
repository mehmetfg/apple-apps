// Okuma odası (iPhone, 2026-10-30) — Akış'ta bir gönderiye dokununca tam ekran açılır: Mac'teki sağ bölmenin telefon hâli.
// Üstte cümle büyük serifle; altında üç eylem: Kopyala · Kitapta aç (geçtiği bölüm, o sayfada) · Paylaş.
// Sonra üretim masası: Yaz (fikrim · yorum · alıntı) ya da Ses (yerinde kayıt, kayıt sürerken metin kapalı).
// En altta senin yazdıkların, sesli notların ve aynı kitaptan komşu işaretler (dokun = o işarete geç).
// Kopyala ve Kitapta aç akıştaki kartın menüsünde de var (Mac'te de).
import SwiftUI

enum Pano {
    static func kopyala(_ s: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = s
        #else
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string)
        #endif
    }
}

// MARK: - Cümlenin kitaptaki yeri

extension Book {
    /// Akıştaki bir işaretin kitaptaki yeri: önce kitabın kendi işaretleri (aynı alıntı), sonra metnin içinde ilk 60 harf.
    /// Akış kimlikleri kitap işaretlerininkiyle aynı değil; eşleşme metinden kurulur.
    func yer(_ metin: String) -> (ch: Int, b: Int)? {
        let q = Dil.normal(metin)
        guard !q.isEmpty else { return nil }
        if let h = highlights.first(where: { Dil.normal($0.quote) == q }), let p = h.at.first { return (p.ch, p.b) }
        let parca = String(q.prefix(60))
        guard parca.count >= 12 else { return nil }
        for (ci, c) in chapters.enumerated() {
            for (bi, bl) in c.blocks.enumerated() where !bl.isHeading && Dil.normal(bl.x).contains(parca) { return (ci, bi) }
        }
        return nil
    }
}

extension LibraryStore {
    /// İşaretin kitabı: aynı kimlik ya da aynı başlık.
    func entry(forIsaret i: Isaret) -> LibraryEntry? {
        entry(i.kitap) ?? index.books.first { Dil.normal($0.title) == Dil.normal(i.baslik) }
    }
}

struct KitapKonumu: Identifiable {
    let book: Book
    let yer: (ch: Int, b: Int)?
    var find: String? = nil         // a searched phrase to mark and step through (Search.swift)
    var id: String { "\(book.id).\(yer?.ch ?? -1).\(yer?.b ?? -1).\(find ?? "")" }
    var bolum: String? { yer.flatMap { book.chapters[safe: $0.ch]?.title } }

    @MainActor
    static func bul(_ i: Isaret, kasa: Kasa) async -> KitapKonumu? {
        let lib = LibraryStore.shared
        guard let e = lib.entry(forIsaret: i), let ham = await lib.book(e.id, kasa: kasa) else { return nil }
        let b = lib.withMarks(ham)
        let metin = i.metin
        let y = await Task.detached(priority: .userInitiated) { b.yer(metin) }.value
        return KitapKonumu(book: b, yer: y)
    }
}

/// `isaret` verilince kitabı yükler, cümlenin geçtiği sayfada okuyucuyu açar. Kitap kütüphanede yoksa kısa bilgi düşer.
struct KitaptaAc: ViewModifier {
    @EnvironmentObject var depo: Depo
    @Binding var isaret: Isaret?
    @State private var konum: KitapKonumu?

    func body(content: Content) -> some View {
        content
            .task(id: isaret?.id) {
                guard let i = isaret else { return }
                let k = await KitapKonumu.bul(i, kasa: depo.kasa)
                isaret = nil
                guard let k else { depo.bildirim = "Bu kitap kütüphanede yok"; return }
                if k.yer == nil { depo.bildirim = "Cümlenin yeri bulunamadı; kitap kaldığın yerden açıldı" }
                konum = k
            }
            #if os(iOS)
            .fullScreenCover(item: $konum) { okuyucu($0) }
            #else
            .sheet(item: $konum) { okuyucu($0).frame(minWidth: 900, minHeight: 700) }
            #endif
    }

    private func okuyucu(_ k: KitapKonumu) -> some View {
        ReaderView(book: k.book, mode: .full, jump: k.yer.map { ($0.ch, $0.b) }).environmentObject(depo)
    }
}

extension View {
    func kitaptaAc(_ isaret: Binding<Isaret?>) -> some View { modifier(KitaptaAc(isaret: isaret)) }
}

// MARK: - Oda

struct OdaIstegi: Identifiable {
    let isaret: Isaret
    var yaz = false                 // açılınca yazma kutusuna odaklan
    var id: String { isaret.id }
}

#if os(iOS)
struct OkumaOdasi: View {
    @EnvironmentObject var depo: Depo
    @Environment(\.dismiss) private var kapat
    @Environment(\.openURL) private var ac
    @StateObject private var ses = SesKayit()

    @State private var i: Isaret
    private let yazarakAc: Bool

    @State private var kip = "yaz"              // üretim masası: yaz · ses
    @State private var rol = "fikir"
    @State private var yazi = ""
    @State private var goster = true            // Mac'teki gibi açık gelir; Buzlandır kullanıcının tercihi
    @State private var bakti = false
    @State private var kopyalandi = false
    @State private var konum: KitapKonumu?      // önceden yüklenir: düğmede bölüm adı görünsün
    @State private var konumAraniyor = true
    @State private var okuyucu: KitapKonumu?
    @State private var bekleyen: (() -> Void)?
    @State private var uyari = false
    @FocusState private var odak: Bool

    init(istek: OdaIstegi) {
        _i = State(initialValue: istek.isaret)
        yazarakAc = istek.yaz
    }

    private var kaydedilmemis: Bool {
        !yazi.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ses.hal == .kayit || ses.hal == .bitti
    }

    var body: some View {
        let kr = Tema.kitap(i.kitap)
        NavigationStack {
            ScrollViewReader { kaydir in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        basBolum.id("ust").padding(.bottom, 26)
                        if depo.gununCumlesi()?.id == i.id {
                            Label("GÜNÜN CÜMLESİ", systemImage: "sparkle")
                                .font(.system(size: 11, weight: .bold)).tracking(1.4).foregroundStyle(kr)
                                .padding(.bottom, 22)
                        }
                        HatirlamaPerdesi(acik: $goster, bakti: $bakti, kilitli: ses.hal == .kayit,
                                         ipucu: HatirlamaPerdesi<EmptyView>.ilkKelimeler(i.metin)) {
                            cumle(kr)
                        }
                        .padding(.bottom, 18)
                        eylemSeridi(kr).padding(.bottom, 30)
                        Rectangle().fill(Tema.cizgi).frame(height: 0.5).padding(.bottom, 22)
                        masa.id("masa")
                        gecmis
                        komsular(kr)
                    }
                    .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 48)
                    .frame(maxWidth: 680).frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .background(alignment: .top) { KitapTulu(kitap: i.kitap, yukseklik: 520).id(i.kitap) }
                .background(Tema.arka.ignoresSafeArea())
                .onChange(of: odak) { _, o in
                    if o { withAnimation(.snappy) { kaydir.scrollTo("masa", anchor: .top) } }
                }
                .onChange(of: i.id) { _, _ in withAnimation(.snappy) { kaydir.scrollTo("ust", anchor: .top) } }
                .onAppear {
                    if yazarakAc { DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { odak = true } }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ustCubuk }
        }
        .task(id: i.id) {
            konumAraniyor = true
            konum = await KitapKonumu.bul(i, kasa: depo.kasa)
            konumAraniyor = false
        }
        .fullScreenCover(item: $okuyucu) { k in
            ReaderView(book: k.book, mode: .full, jump: k.yer.map { ($0.ch, $0.b) }).environmentObject(depo)
        }
        .confirmationDialog("Kaydedilmemiş üretimin var", isPresented: $uyari, titleVisibility: .visible) {
            Button("Bırak ve devam et", role: .destructive) {
                if ses.hal == .kayit || ses.hal == .bitti { ses.vazgec() }
                yazi = ""
                bekleyen?(); bekleyen = nil
            }
            Button("Kalayım", role: .cancel) { bekleyen = nil }
        } message: {
            Text("Yazdığın ya da kaydettiğin henüz saklanmadı.")
        }
        .onDisappear { if ses.hal == .kayit { ses.durdur() } }
    }

    /// Kaydedilmemiş bir şey varsa önce sorar.
    private func sorarak(_ f: @escaping () -> Void) {
        if kaydedilmemis { bekleyen = f; uyari = true } else { f() }
    }

    // MARK: üst çubuk

    @ToolbarContentBuilder
    private var ustCubuk: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { sorarak { kapat() } } label: {
                Image(systemName: "chevron.down").font(.system(size: 15, weight: .semibold))
            }
            .accessibilityLabel("Kapat")
        }
        ToolbarItem(placement: .principal) {
            Text(i.kisaBaslik).font(.system(size: 14, weight: .semibold)).foregroundStyle(Tema.ikincil).lineLimit(1)
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            let d = depo.durum
            let fav = d.favoriler.contains(i.id), hat = d.hatirlatmalar.contains(i.id), yer = d.yerIsaretleri.contains(i.id)
            Button { if !fav { Dokunus.kalp() }; depo.favori(i.id) } label: {
                Image(systemName: fav ? "heart.fill" : "heart").foregroundStyle(fav ? Color.pink : Tema.ikincil)
            }.accessibilityLabel("Favori")
            Button { depo.hatirlat(i.id) } label: {
                Image(systemName: hat ? "bell.fill" : "bell").foregroundStyle(hat ? Tema.vurgu : Tema.ikincil)
            }.accessibilityLabel("Tekrar havuzuna al")
            Button { depo.yerIsareti(i.id) } label: {
                Image(systemName: yer ? "bookmark.fill" : "bookmark").foregroundStyle(yer ? Tema.vurgu : Tema.ikincil)
            }.accessibilityLabel("Yer işareti")
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Bitti") { odak = false }
        }
    }

    // MARK: cümle

    private var basBolum: some View {
        HStack(alignment: .center, spacing: 14) {
            KitapKapagi(id: i.kitap, baslik: i.baslik, genislik: 46)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
            VStack(alignment: .leading, spacing: 6) {
                Text(i.kisaBaslik).font(.system(size: 18, weight: .semibold, design: .serif)).foregroundStyle(Tema.metin)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    TurRozeti(renk: i.renk)
                    Text(i.zaman.formatted(.dateTime.day().month(.abbreviated).year().hour().minute().locale(Dil.tr)))
                        .font(.system(size: 12)).foregroundStyle(Tema.soluk).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 12)
    }

    private func cumle(_ kr: Color) -> some View {
        let kisa = i.metin.count <= 180
        return VStack(alignment: .leading, spacing: 24) {
            Text(i.metin)
                .font(.system(size: kisa ? 26 : 20, design: .serif)).lineSpacing(kisa ? 8 : 6)
                .foregroundStyle(Tema.metin)
                .textSelection(.enabled).tamGenislik()
                .overlay(alignment: .topLeading) {
                    Text("“").font(.system(size: kisa ? 84 : 70, weight: .bold, design: .serif)).foregroundStyle(kr.opacity(0.25))
                        .offset(x: -6, y: kisa ? -46 : -40).allowsHitTesting(false).accessibilityHidden(true)
                }
                .padding(.top, 30)
            if let b = i.baglam, !b.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("BAĞLAM").font(.system(size: 10.5, weight: .bold)).tracking(1.4).foregroundStyle(Tema.soluk)
                    Text(b).font(.system(size: 15.5, design: .serif)).foregroundStyle(Tema.ikincil).lineSpacing(5)
                        .textSelection(.enabled)
                }
                .padding(.leading, 16).tamGenislik()
                .overlay(alignment: .leading) { Capsule().fill(kr.opacity(0.35)).frame(width: 2) }
            }
        }
    }

    // MARK: eylemler — kopyala · kitapta aç · paylaş

    private func eylemSeridi(_ kr: Color) -> some View {
        HStack(spacing: 10) {
            eylemKarti(kopyalandi ? "checkmark" : "doc.on.doc", kopyalandi ? "Kopyalandı" : "Kopyala", nil,
                       kopyalandi ? Tema.basari : Tema.metin) {
                Pano.kopyala("“\(i.metin)” — \(i.kisaBaslik)")
                Dokunus.basari()
                withAnimation(.snappy) { kopyalandi = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { withAnimation(.snappy) { kopyalandi = false } }
            }
            eylemKarti("book", "Kitapta aç", kitapAlti, konum == nil ? Tema.soluk : kr, yukleniyor: konumAraniyor) {
                if let konum { okuyucu = konum }
            }
            .disabled(konum == nil)
            Menu {
                Button {
                    if let u = XPaylas.adres(XPaylas.sigdir(yorum: "", alinti: i.metin, kaynak: i.kisaBaslik)) { ac(u) }
                } label: { Label("X'te paylaş", systemImage: "paperplane") }
                ShareLink(item: "“\(i.metin)” — \(i.kisaBaslik)") { Label("Paylaş…", systemImage: "square.and.arrow.up") }
            } label: {
                eylemGovde("square.and.arrow.up", "Paylaş", nil, Tema.metin, yukleniyor: false)
            }
            .buttonStyle(.plain)
        }
    }

    private var kitapAlti: String {
        if konumAraniyor { return "aranıyor…" }
        guard let konum else { return "kütüphanede yok" }
        return konum.bolum ?? "yeri bulunamadı"
    }

    private func eylemKarti(_ s: String, _ ad: String, _ alt: String?, _ r: Color, yukleniyor: Bool = false,
                            _ f: @escaping () -> Void) -> some View {
        Button(action: f) { eylemGovde(s, ad, alt, r, yukleniyor: yukleniyor) }
            .buttonStyle(.plain)
    }

    private func eylemGovde(_ s: String, _ ad: String, _ alt: String?, _ r: Color, yukleniyor: Bool) -> some View {
        VStack(spacing: 5) {
            ZStack {
                if yukleniyor { ProgressView().controlSize(.small) }
                else { Image(systemName: s).font(.system(size: 17, weight: .medium)).contentTransition(.symbolEffect(.replace)) }
            }
            .frame(height: 22)
            .foregroundStyle(r)
            Text(ad).font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.metin)
            if let alt {
                Text(alt).font(.system(size: 10.5)).foregroundStyle(Tema.soluk).lineLimit(1).truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 74)
        .padding(.horizontal, 6)
        .background { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Tema.yuzey) }
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Tema.cizgi, lineWidth: 0.6) }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: üretim masası

    private var masa: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("ÜRETİM").font(.system(size: 11, weight: .bold)).tracking(1.4).foregroundStyle(Tema.soluk)
                Spacer()
                SimgeSecici(secenekler: [.init(deger: "yaz", ad: "Yaz", sembol: "pencil.line"),
                                         .init(deger: "ses", ad: "Ses", sembol: "mic")],
                            secili: Binding(get: { kip }, set: { y in
                                if y == "ses" { odak = false }
                                withAnimation(.snappy) { kip = y }
                            }), sikisik: true)
                    .frame(width: 170)
                    .disabled(ses.hal == .kayit)
            }
            if kip == "yaz" { yazmaMasasi.transition(.opacity) } else { sesMasasi.transition(.opacity) }
        }
    }

    private var yerTutucu: String {
        switch rol {
        case "yorum": "Bu işarete yorumun: katılıyor musun, neden?"
        case "alinti": "Alıntılarken ne eklersin?"
        default: "Bu işaret ne diyor, sen ne düşünüyorsun? Kendi cümlelerinle yaz."
        }
    }

    private var yazmaMasasi: some View {
        VStack(alignment: .leading, spacing: 12) {
            SimgeSecici(secenekler: [.init(deger: "fikir", ad: "Fikrim", sembol: "lightbulb"),
                                     .init(deger: "yorum", ad: "Yorum", sembol: "text.bubble"),
                                     .init(deger: "alinti", ad: "Alıntı", sembol: "arrow.2.squarepath")],
                        secili: $rol, sikisik: true)
            ZStack(alignment: .topLeading) {
                if yazi.isEmpty {
                    Text(yerTutucu).font(.system(size: 17, design: .serif)).foregroundStyle(Tema.soluk)
                        .padding(.top, 14).padding(.leading, 15).allowsHitTesting(false)
                }
                TextEditor(text: $yazi)
                    .font(.system(size: 17, design: .serif)).lineSpacing(4)
                    .scrollContentBackground(.hidden)
                    .focused($odak)
                    .padding(8)
                    .frame(minHeight: 170)
            }
            .background { RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Tema.yuzey) }
            .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(odak ? Tema.vurgu.opacity(0.5) : Tema.cizgi, lineWidth: odak ? 1.2 : 0.7) }
            HStack(spacing: 8) {
                Text(goster ? (bakti ? "Buzlandırıp sonra baktın." : "Metin açık · istersen Buzlandır.") : "Metin buzlu — hatırlayarak yazıyorsun.")
                    .font(.system(size: 12)).foregroundStyle(goster ? Tema.soluk : Tema.basari).lineLimit(2)
                Spacer(minLength: 4)
                Text("\(yazi.split(whereSeparator: \.isWhitespace).count) kelime").font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Tema.soluk).fixedSize()
            }
            Button {
                let m = yazi.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !m.isEmpty else { return }
                depo.ekle(Olay(tur: .kendiCumle, hedef: i.id, deger: goster || bakti, metin: m, rol: rol))   // deger: metne bakıldı mı
                Dokunus.basari()
                yazi = ""; bakti = false; odak = false
            } label: { Label("Kaydet", systemImage: "checkmark") }
            .buttonStyle(AnaDugme())
            .disabled(yazi.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var sesMasasi: some View {
        VStack(spacing: 14) {
            dalga
            Text(SesKayit.sureYazi(ses.sure) + " / 3:00").font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit().foregroundStyle(Tema.metin)
            kayitDugmesi
            sesDurumu
            if ses.hal == .bitti, let u = ses.dosya {
                HStack(spacing: 10) {
                    Button { ses.cal(u, kimlik: "onizleme") } label: {
                        Label(ses.calan == "onizleme" ? "Durdur" : "Dinle", systemImage: ses.calan == "onizleme" ? "stop.fill" : "play.fill")
                    }.buttonStyle(IkinciDugme())
                    Button(role: .destructive) { ses.vazgec() } label: { Label("Sil", systemImage: "trash") }
                        .buttonStyle(IkinciDugme(renk: Tema.uyari))
                }
                Button {
                    depo.ekle(Olay(tur: .sesNot, hedef: i.id, deger: goster || bakti, metin: u.lastPathComponent, sure: ses.sure))
                    depo.esitle(gecikme: 1)
                    Dokunus.basari()
                    ses.sifirla()
                } label: { Label("Kaydet · \(SesKayit.boyut(u))", systemImage: "checkmark") }
                .buttonStyle(AnaDugme())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18).padding(.horizontal, 14)
        .background { RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Tema.yuzey) }
        .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Tema.cizgi, lineWidth: 0.6) }
    }

    private var dalga: some View {
        HStack(alignment: .center, spacing: 3) {
            let s = ses.seviyeler.suffix(40)
            ForEach(Array(s.enumerated()), id: \.offset) { _, v in
                Capsule().fill(Tema.uyari.opacity(0.35 + Double(v) * 0.65))
                    .frame(width: 4, height: max(4, CGFloat(v) * 54))
            }
            if s.isEmpty { Capsule().fill(Tema.cizgi).frame(height: 4) }
        }
        .frame(height: 58)
        .animation(.linear(duration: 0.1), value: ses.seviyeler.count)
    }

    private var kayitDugmesi: some View {
        Button {
            switch ses.hal {
            case .kayit: Dokunus.kayit(false); ses.durdur()
            case .bitti: break
            default: odak = false; Dokunus.kayit(true); Task { await ses.baslat(klasor: depo.sesKlasoru) }
            }
        } label: {
            ZStack {
                Circle().fill(Tema.uyari.opacity(0.15)).frame(width: 84, height: 84)
                    .scaleEffect(ses.hal == .kayit ? 1 + CGFloat(ses.seviye) * 0.25 : 1)
                if ses.hal == .kayit {
                    RoundedRectangle(cornerRadius: 7).fill(Tema.uyari).frame(width: 28, height: 28)
                } else {
                    Circle().fill(ses.hal == .bitti ? Tema.soluk : Tema.uyari).frame(width: 56, height: 56)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(ses.hal == .bitti)
        .accessibilityLabel(ses.hal == .kayit ? "Kaydı durdur" : "Kaydı başlat")
    }

    @ViewBuilder
    private var sesDurumu: some View {
        switch ses.hal {
        case .izinYok:
            Text("Mikrofon izni yok. Ayarlar › Teoria › Mikrofon. O zamana kadar Yaz ile not alabilirsin.")
                .font(.footnote).multilineTextAlignment(.center).foregroundStyle(Tema.uyari)
        case .hata(let h):
            Text(h).font(.footnote).multilineTextAlignment(.center).foregroundStyle(Tema.uyari)
        case .kayit:
            Text("Metne bakmadan anlat: ne diyordu, sen ne diyorsun? 3 dakikada kendiliğinden durur.")
                .font(.footnote).multilineTextAlignment(.center).foregroundStyle(Tema.soluk)
        case .bitti:
            Text("Dinle, istersen sil, sonra kaydet.").font(.footnote).foregroundStyle(Tema.soluk)
        case .bos:
            Text("Dokun ve anlat. Kayıt sürerken cümle kapanır.").font(.footnote).foregroundStyle(Tema.soluk)
        }
    }

    // MARK: geçmiş ve komşular

    @ViewBuilder
    private var gecmis: some View {
        let d = depo.durum
        let yazdiklarin = d.kendiCumleler.filter { $0.hedef == i.id }
        let sesler = d.sesNotlari.filter { $0.hedef == i.id }
        if !yazdiklarin.isEmpty || !sesler.isEmpty {
            Bolumbasi(metin: "Senin ürettiklerin · \(yazdiklarin.count + sesler.count)", sembol: "person")
                .padding(.top, 34).padding(.bottom, 10)
            VStack(spacing: 10) {
                ForEach(sesler) { o in SesSatiri(olay: o) }
                ForEach(yazdiklarin) { o in SenGonderisi(olay: o, alintiGoster: false, yogunluk: .kompakt) }
            }
        }
    }

    /// Aynı kitaptan, zamanca en yakın sekiz işaret: dokun = o işarete geç.
    @ViewBuilder
    private func komsular(_ kr: Color) -> some View {
        let l = depo.akis.isaretler.filter { $0.kitap == i.kitap && $0.id != i.id }
            .sorted { abs($0.zaman.timeIntervalSince(i.zaman)) < abs($1.zaman.timeIntervalSince(i.zaman)) }
            .prefix(8)
        if !l.isEmpty {
            Bolumbasi(metin: "Aynı kitaptan", sembol: "books.vertical").padding(.top, 34).padding(.bottom, 12)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(l)) { k in
                        Button { sorarak { gec(k) } } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(k.metin).font(.system(size: 14, design: .serif)).foregroundStyle(Tema.metin)
                                    .lineSpacing(3).lineLimit(5).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                Text(Tarih.kisa(k.zaman)).font(.system(size: 11)).foregroundStyle(Tema.soluk)
                            }
                            .padding(.leading, 16).padding(.trailing, 14).padding(.vertical, 14)
                            .frame(width: 220, height: 150, alignment: .topLeading)
                            .background { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Tema.yuzey) }
                            .overlay(alignment: .leading) { Capsule().fill(kr.opacity(0.7)).frame(width: 2.5).padding(.vertical, 14).padding(.leading, 7) }
                            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Tema.cizgi, lineWidth: 0.6) }
                            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 22).padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -22)
        }
    }

    private func gec(_ k: Isaret) {
        Dokunus.secim()
        withAnimation(.snappy) {
            i = k
            goster = true; bakti = false; yazi = ""; konum = nil
        }
    }
}
#endif
