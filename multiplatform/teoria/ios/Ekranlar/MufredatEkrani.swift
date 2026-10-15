// Müfredat — vault'taki bütün müfredatlı üretim hatları tek yerde: süren, bekleyen, başlamamış, biten, kapanan.
// Veri: veri/mufredat.py → veri/mufredat.json (hat klasörleri + müfredat dosyaları + Voice Dream'deki gerçek dinleme).
// Üç görünüm: Hatlar (ilerleme şeridi, tahmini bitiş) · Zaman (bütün hatlar tek takvimde) · Sırada (kulağındakiler,
// dinlenmeyi bekleyenler, her hattın sıradaki metni). Hat detayı metro hattı gibi: faz → grup → durak.
// Salt okur: burada hiçbir şey işaretlenmez, puan ya da borç yok; durum Voice Dream'den ve dosyalardan gelir.
import SwiftUI
import Charts

// MARK: - Model

struct Mufredat: Codable {
    var surum: String
    var bugun: String?
    var hatlar: [MHat]
    static let bos = Mufredat(surum: "0", bugun: nil, hatlar: [])
}

struct MHat: Codable, Identifiable, Hashable {
    var kod: String
    var ad: String
    var alt: String?
    var alan: String
    var tur: String
    var birim: String
    var durum: String
    var durumNot: String?
    var kurulus: String?
    var hedef: String?
    var olcut: String?
    var kapanis: String?
    var neden: String?
    var onceki: String?
    var tempo: Double?
    var konum: String?
    var yazim: Bool?
    var toplam: Int
    var uretilen: Int
    var dinlenen: Int
    var dinleniyor: Int
    var atlanan: Int?
    var siradaki: String?
    var ilk: String?
    var son: String?
    var hiz: Double?
    var dinlemeHizi: Double?
    var birimler: [MBirim]

    enum CodingKeys: String, CodingKey {
        case kod, ad, alt, alan, tur, birim, durum, kurulus, hedef, olcut, kapanis, neden, onceki, tempo, konum, yazim,
             toplam, uretilen, dinlenen, dinleniyor, atlanan, siradaki, ilk, son, hiz, birimler
        case durumNot = "durum_not"
        case dinlemeHizi = "dinleme_hizi"
    }

    var id: String { kod }
    var renk: Color { MAlan.renk(alan) }
    var acik: Bool { durum != "kapandi" && durum != "bitti" }
    /// Hazır ama hiç açılmamış: Voice Dream'de duran, dinlenmemiş metinler. Yazım işi (taslak) ve VD'de kaydı olmayanlar sayılmaz.
    var bekleyenler: [MBirim] { yazim == true ? [] : birimler.filter { $0.d == .uretildi && !$0.vdYok(tur) } }
    var bekleyen: Int { bekleyenler.count }
    var vdYok: Int { birimler.filter { $0.d == .uretildi && $0.vdYok(tur) }.count }
    var kalan: Int { max(0, toplam - uretilen - (atlanan ?? 0)) }
    var siradakiBirim: MBirim? { siradaki.flatMap { k in birimler.first { $0.kod == k } } }
    var kulakta: [MBirim] { birimler.filter { $0.d == .dinleniyor } }
    var dinlenmeOrani: Double { toplam > 0 ? Double(dinlenen) / Double(toplam) : 0 }
    var uretimOrani: Double { toplam > 0 ? Double(uretilen) / Double(toplam) : 0 }
    var fazlar: [String] { var g: [String] = []; for b in birimler { if let f = b.faz, g.last != f { g.append(f) } }; return g }

    /// Birimleri sırayı bozmadan (faz, grup) bloklarına böler.
    var gruplar: [MGrup] {
        var out: [MGrup] = []
        for b in birimler {
            let anahtar = (b.faz ?? "") + "|" + (b.grup ?? "")
            if let son = out.last, son.anahtar == anahtar { out[out.count - 1].birimler.append(b) }
            else { out.append(MGrup(sira: out.count, faz: b.faz, ad: b.grup, birimler: [b])) }
        }
        return out
    }

    /// Haftalık üretim hızı: son üç haftada en az üç birim üretildiyse gerçekleşen; yoksa planın temposu.
    var etkinHiz: Double? {
        if hizGercek, let h = hiz { return h }
        if let t = tempo, t > 0 { return t }
        return nil
    }

    /// Bu hızla son birimin üretileceği gün (kapanan/biten hat için nil).
    func tahminiBitis(_ bugun: Date = Date()) -> Date? {
        guard acik, kalan > 0, let h = etkinHiz else { return nil }
        return bugun.gun(Int((Double(kalan) / h * 7).rounded()))
    }

    var hizGercek: Bool { (hiz ?? 0) >= 1 || ((hiz ?? 0) > 0.2 && tempo == nil) }
}

struct MBirim: Codable, Identifiable, Hashable {
    var kod: String
    var ad: String
    var alt: String?
    var faz: String?
    var grup: String?
    var durum: String
    var yuzde: Int?
    var isaret: Int?
    var teslim: String?
    var dinleme: String?
    var uretilenAd: String?
    var kelime: Int?
    var vd: Bool?

    enum CodingKeys: String, CodingKey {
        case kod, ad, alt, faz, grup, durum, yuzde, isaret, teslim, dinleme, kelime, vd
        case uretilenAd = "uretilen_ad"
    }

    var id: String { kod }
    var d: MDurum { MDurum(rawValue: durum) ?? .plan }
    /// Üretilen başlık plandan farklıysa (sıra değişmiş) asıl gösterilen odur.
    var gosterilenAd: String {
        guard let u = uretilenAd, !u.isEmpty, Dil.normal(u) != Dil.normal(ad), !Dil.normal(ad).contains(Dil.normal(u)) else { return ad }
        return u
    }
    var planFarkli: Bool { gosterilenAd != ad }
    /// Dinleme hattında yazılmış ama Voice Dream'de kaydı yok: dinlenip silinmiş ya da hiç yüklenmemiş olabilir.
    func vdYok(_ tur: String) -> Bool { tur == "dinleme" && vd != true }
}

struct MGrup: Identifiable, Hashable {
    var sira: Int
    var faz: String?
    var ad: String?
    var birimler: [MBirim]
    var anahtar: String { (faz ?? "") + "|" + (ad ?? "") }
    var id: Int { sira }
    var dinlenen: Int { birimler.filter { $0.d == .dinlendi }.count }
    var uretilen: Int { birimler.filter { $0.d.uretildi }.count }
}

enum MDurum: String {
    case plan, uretildi, dinleniyor, dinlendi, atlandi
    var uretildi: Bool { self == .uretildi || self == .dinleniyor || self == .dinlendi }
    var ad: String {
        switch self {
        case .plan: "planda"
        case .uretildi: "hazır, dinlenmedi"
        case .dinleniyor: "dinleniyor"
        case .dinlendi: "dinlendi"
        case .atlandi: "atlandı"
        }
    }
}

enum MAlan {
    static func renk(_ a: String) -> Color {
        switch a {
        case "felsefe": Tema.renk("indigo")
        case "sistem": Tema.renk("camgobegi")
        case "dil": Tema.renk("yesil")
        case "finans": Tema.renk("amber")
        case "yazarlik": Tema.renk("gul")
        case "kutuphane": Tema.renk("turuncu")
        case "pratik": Tema.renk("amber")      // Bir Yöne · Kanal II
        case "mesleki": Tema.renk("camgobegi") // Bir Yöne · Kanal III
        default: Tema.renk(nil)
        }
    }
    static func ad(_ a: String) -> String {
        switch a {
        case "felsefe": "Felsefe"
        case "sistem": "Yazılım"
        case "dil": "İngilizce"
        case "finans": "Finans"
        case "yazarlik": "Yazarlık"
        case "kutuphane": "Kütüphane"
        case "pratik": "Pratik Hayat"
        case "mesleki": "Mesleki"
        default: a.capitalized
        }
    }
    static func durumAd(_ d: String) -> String {
        switch d {
        case "suruyor": "Sürüyor"
        case "beklemede": "Beklemede"
        case "baslamadi": "Başlamadı"
        case "bitti": "Bitti"
        case "kapandi": "Kapandı"
        default: d
        }
    }
    static func durumSembol(_ d: String) -> String {
        switch d {
        case "suruyor": "play.circle.fill"
        case "beklemede": "pause.circle"
        case "baslamadi": "circle.dashed"
        case "bitti": "checkmark.seal.fill"
        case "kapandi": "archivebox"
        default: "circle"
        }
    }
    static let durumSirasi = ["suruyor", "beklemede", "baslamadi", "bitti", "kapandi"]
    /// Sort rank of a line's status; an unknown status (a new one written by mufredat.py) goes last instead of crashing.
    static func statusRank(_ d: String) -> Int { durumSirasi.firstIndex(of: d) ?? durumSirasi.count }
}

private func gunTarih(_ s: String?) -> Date? { Tarih.coz(s).map(\.gunBasi) }
private func kisaTarih(_ s: String?) -> String { gunTarih(s).map(Tarih.kisa) ?? "—" }
private func ayYil(_ d: Date) -> String { d.formatted(.dateTime.month(.wide).year().locale(Dil.tr)) }

// MARK: - Ana ekran

enum MSekme: String, CaseIterable, Identifiable {
    case hatlar, zaman, sira
    var id: String { rawValue }
    var ad: String { switch self { case .hatlar: "Hatlar"; case .zaman: "Zaman"; case .sira: "Sırada" } }
    var sembol: String { switch self { case .hatlar: "square.stack.3d.up"; case .zaman: "calendar.day.timeline.left"; case .sira: "list.number" } }
}

struct MufredatEkrani: View {
    @EnvironmentObject var depo: Depo
    var genis = false
    @AppStorage("teoria.mufredat.sekme") private var sekme: MSekme = .hatlar
    @AppStorage("teoria.mufredat.secili") private var seciliHam = ""
    private var secili: String? { get { seciliHam.isEmpty ? nil : seciliHam } nonmutating set { seciliHam = newValue ?? "" } }
    @State private var yol: [MHat] = []
    @State private var kapananAcik = false

    var hatlar: [MHat] { depo.mufredat.hatlar }
    var seciliHat: MHat? { hatlar.first { $0.kod == secili } ?? hatlar.first { $0.durum == "suruyor" } ?? hatlar.first }

    var body: some View {
        #if os(macOS)
        macGovde
        #else
        NavigationStack(path: $yol) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    baslik
                    if hatlar.isEmpty { bosDurum } else {
                        ozetKarti
                        SimgeSecici(secenekler: MSekme.allCases.map { .init(deger: $0, ad: $0.ad, sembol: $0.sembol) }, secili: $sekme)
                        switch sekme {
                        case .hatlar: hatListesi { yol.append($0) }
                        case .zaman: ZamanGorunumu(hatlar: hatlar, gunGenislik: 4) { yol.append($0) }
                        case .sira: SiraGorunumu(hatlar: hatlar, sutunlu: false) { yol.append($0) }
                        }
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 30)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .background(Tema.arka)
            .refreshable { await depo.guncelle() }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: MHat.self) { h in HatDetay(hat: h) }
        }
        #endif
    }

    #if os(macOS)
    private var macGovde: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Müfredat").font(Tema.serif(.largeTitle, .bold))
                    Text(altBaslik).font(.callout).foregroundStyle(Tema.ikincil)
                }
                Spacer()
                SimgeSecici(secenekler: MSekme.allCases.map { .init(deger: $0, ad: $0.ad, sembol: $0.sembol) }, secili: $sekme, esit: false)
                    .fixedSize()
            }
            .padding(.horizontal, 26).padding(.top, 18).padding(.bottom, 14)
            Divider().opacity(0.5)
            if hatlar.isEmpty { bosDurum.padding(40); Spacer() } else {
                switch sekme {
                case .hatlar:
                    HStack(spacing: 0) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                ozetKarti
                                hatListesi(kompakt: true) { secili = $0.kod }
                            }
                            .padding(18)
                        }
                        .frame(width: 400)
                        .background(Tema.arka)
                        Divider().opacity(0.5)
                        if let h = seciliHat {
                            HatDetay(hat: h, genis: true).id(h.kod)
                        }
                    }
                case .zaman:
                    ScrollView {
                        ZamanGorunumu(hatlar: hatlar, gunGenislik: 7) { secili = $0.kod; sekme = .hatlar }
                            .padding(24)
                    }
                case .sira:
                    ScrollView {
                        SiraGorunumu(hatlar: hatlar, sutunlu: true) { secili = $0.kod; sekme = .hatlar }
                            .padding(24)
                    }
                }
            }
        }
        .background(Tema.arka)
    }
    #endif

    private var altBaslik: String {
        let acik = hatlar.filter(\.acik)
        let s = acik.filter { $0.durum == "suruyor" }.count
        return "\(acik.count) açık hat · \(s) sürüyor · güncelleme \(depo.mufredat.surum.replacingOccurrences(of: ".", with: " "))"
    }

    private var baslik: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("BÜTÜN HATLAR").font(.system(size: 12, weight: .bold)).tracking(0.6).foregroundStyle(Tema.soluk)
                Text("Müfredat").font(Tema.serif(.largeTitle, .bold)).foregroundStyle(Tema.metin)
            }
            Spacer()
            #if os(iOS)
            GuncelleDugmesi(cam: true)
            #endif
        }
        .padding(.top, 8)
    }

    private var bosDurum: some View {
        Yuzey {
            VStack(alignment: .leading, spacing: 8) {
                Text("Müfredat verisi henüz yok").font(Tema.serif(.title3, .semibold))
                Text("Mac'te ↻ Güncelle'ye bas ya da sabah görevini bekle: `veri/mufredat.py` hatları ve Voice Dream'i okuyup buraya yazar.")
                    .font(.callout).foregroundStyle(Tema.ikincil)
            }
        }
    }

    // MARK: Özet

    private var ozetKarti: some View {
        let acik = hatlar.filter(\.acik)
        let uretilen = acik.reduce(0) { $0 + $1.uretilen }
        let dinlenen = acik.reduce(0) { $0 + $1.dinlenen }
        let toplam = acik.reduce(0) { $0 + $1.toplam }
        let bekleyen = acik.reduce(0) { $0 + $1.bekleyen }
        let kulakta = acik.reduce(0) { $0 + $1.dinleniyor }
        let hafta = haftaOzeti
        return Yuzey(dolgu: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 16) {
                    ZStack {
                        Halka(oran: toplam > 0 ? Double(uretilen) / Double(toplam) : 0, renk: Tema.vurgu.opacity(0.35), kalinlik: 9)
                        Halka(oran: toplam > 0 ? Double(dinlenen) / Double(toplam) : 0, renk: Tema.vurgu, kalinlik: 9, iz: .clear)
                        VStack(spacing: -2) {
                            Text("\(dinlenen)").font(.system(size: 20, weight: .bold, design: .rounded))
                            Text("/ \(toplam)").font(.system(size: 10, weight: .semibold)).foregroundStyle(Tema.soluk)
                        }
                    }
                    .frame(width: 74, height: 74)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(acik.count) açık hat, \(toplam) birim").font(Tema.serif(.headline))
                        Text("\(uretilen) üretildi · \(dinlenen) dinlendi · \(kulakta) kulağında")
                            .font(.footnote).foregroundStyle(Tema.ikincil)
                        if bekleyen > 0 {
                            Label("\(bekleyen) hazır metin dinlenmeyi bekliyor", systemImage: "tray.full")
                                .font(.footnote.weight(.semibold)).foregroundStyle(Tema.uyari)
                        }
                    }
                }
                HStack(spacing: 0) {
                    ozetSayi("\(hafta.0)", "7 günde üretildi")
                    Divider().frame(height: 30)
                    ozetSayi("\(hafta.1)", "7 günde dinlendi")
                    Divider().frame(height: 30)
                    ozetSayi("\(hatlar.filter { $0.durum == "suruyor" }.count)", "sürüyor")
                    Divider().frame(height: 30)
                    ozetSayi("\(hatlar.filter { $0.durum == "beklemede" || $0.durum == "baslamadi" }.count)", "bekliyor")
                }
            }
        }
    }

    /// Son yedi günde üretilen ve dinlenen birim sayısı (bütün hatlar).
    private var haftaOzeti: (Int, Int) {
        let sinir = Date().gunBasi.gun(-6)
        var u = 0, d = 0
        for h in hatlar { for b in h.birimler {
            if let t = gunTarih(b.teslim), t >= sinir { u += 1 }
            if b.d == .dinlendi, let t = gunTarih(b.dinleme), t >= sinir { d += 1 }
        } }
        return (u, d)
    }

    private func ozetSayi(_ s: String, _ e: String) -> some View {
        VStack(spacing: 2) {
            Text(s).font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(Tema.metin)
            Text(e).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Tema.soluk).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Hat listesi (duruma göre)

    @ViewBuilder
    private func hatListesi(kompakt: Bool = false, ac: @escaping (MHat) -> Void) -> some View {
        ForEach(MAlan.durumSirasi, id: \.self) { d in
            let grup = hatlar.filter { $0.durum == d }
            if !grup.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        if d == "kapandi" { withAnimation(.snappy) { kapananAcik.toggle() } }
                    } label: {
                        HStack {
                            Bolumbasi(metin: "\(MAlan.durumAd(d)) · \(grup.count)", sembol: MAlan.durumSembol(d))
                            Spacer()
                            if d == "kapandi" {
                                Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(Tema.soluk)
                                    .rotationEffect(.degrees(kapananAcik ? 0 : -90))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if d != "kapandi" || kapananAcik {
                        ForEach(grup) { h in
                            Button { Dokunus.hafif(0.4); ac(h) } label: {
                                HatKarti(hat: h, kompakt: kompakt, secili: kompakt && h.kod == seciliHat?.kod)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - Hat kartı

struct HatKarti: View {
    let hat: MHat
    var kompakt = false
    var secili = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(hat.renk.opacity(hat.acik ? 1 : 0.4)).frame(width: 4)
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(hat.kod).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(hat.renk)
                    Text(hat.ad).font(Tema.serif(.headline, .semibold)).foregroundStyle(Tema.metin).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(MAlan.ad(hat.alan)).font(.system(size: 11, weight: .semibold)).foregroundStyle(Tema.soluk)
                }
                if !kompakt, let a = hat.alt {
                    Text(a).font(.footnote).foregroundStyle(Tema.ikincil).lineLimit(2)
                }
                IlerlemeSeridi(hat: hat)
                HStack(spacing: 10) {
                    Text("\(hat.uretilen)/\(hat.toplam) \(hat.birim)").font(.caption.weight(.semibold)).foregroundStyle(Tema.metin)
                    Text("\(hat.dinlenen) dinlendi").font(.caption).foregroundStyle(Tema.ikincil)
                    if hat.bekleyen > 0 && hat.acik {
                        Text("\(hat.bekleyen) bekliyor").font(.caption.weight(.semibold)).foregroundStyle(Tema.uyari)
                    }
                    Spacer(minLength: 0)
                    if let b = hat.tahminiBitis() {
                        Text("≈ \(ayYil(b))").font(.caption2.weight(.semibold)).foregroundStyle(Tema.soluk)
                            .help(hat.hizGercek ? "Son üç haftanın hızıyla" : "Planın temposuyla, üretim sürerse")
                    } else if hat.durum == "kapandi", let k = hat.kapanis {
                        Text("kapandı \(kisaTarih(k))").font(.caption2).foregroundStyle(Tema.soluk)
                    }
                }
                if let s = hat.siradakiBirim, hat.acik {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.turn.down.right").font(.system(size: 10, weight: .bold))
                        Text("Sıradaki").font(.caption2.weight(.bold)).textCase(.uppercase)
                        Text("\(s.kod) · \(s.ad)").font(.caption).lineLimit(1)
                    }
                    .foregroundStyle(Tema.ikincil)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Tema.yuzey))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(secili ? hat.renk.opacity(0.7) : Tema.cizgi.opacity(0.6), lineWidth: secili ? 1.5 : 0.5))
        .opacity(hat.acik ? 1 : 0.75)
        .contentShape(RoundedRectangle(cornerRadius: 20))
    }
}

/// Bir hattın bütün birimleri tek şeritte: dinlendi · kulakta · hazır · atlandı · planda.
struct IlerlemeSeridi: View {
    let hat: MHat
    var yukseklik: CGFloat = 8

    var body: some View {
        let t = max(hat.toplam, 1)
        let parcalar: [(Int, Color)] = [
            (hat.dinlenen, hat.renk),
            (hat.dinleniyor, hat.renk.opacity(0.55)),
            (hat.bekleyen, hat.renk.opacity(0.22)),
            (hat.atlanan ?? 0, Tema.soluk.opacity(0.35)),
        ]
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Tema.cizgi.opacity(0.7))
                HStack(spacing: 0) {
                    ForEach(Array(parcalar.enumerated()), id: \.offset) { _, p in
                        if p.0 > 0 {
                            Rectangle().fill(p.1).frame(width: max(2, g.size.width * CGFloat(p.0) / CGFloat(t)))
                        }
                    }
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: yukseklik)
        .accessibilityLabel("\(hat.toplam) birimden \(hat.uretilen) üretildi, \(hat.dinlenen) dinlendi")
    }
}

// MARK: - Zaman çizelgesi (bütün hatlar)

struct ZamanGorunumu: View {
    let hatlar: [MHat]
    @State var gunGenislik: CGFloat
    var ac: (MHat) -> Void
    @State private var kapananlar = false

    private let satir: CGFloat = 46
    private var etiket: CGFloat { gunGenislik >= 6 ? 168 : 112 }
    private let ust: CGFloat = 30

    var gorunen: [MHat] {
        let acik = hatlar.filter(\.acik).sorted { MAlan.statusRank($0.durum) < MAlan.statusRank($1.durum) }
        return acik + (kapananlar ? hatlar.filter { !$0.acik } : [])
    }

    var bugun: Date { Date().gunBasi }
    var bas: Date {
        let t = hatlar.compactMap { gunTarih($0.kurulus) ?? gunTarih($0.ilk) }.min() ?? bugun.gun(-60)
        return Tarih.takvim.dateInterval(of: .month, for: t)?.start ?? t
    }
    var son: Date {
        var t = bugun.gun(75)
        for h in gorunen {
            if let x = gunTarih(h.hedef), x > t { t = x }
            if let x = h.tahminiBitis(), x > t { t = min(x, bugun.gun(420)) }
        }
        return Tarih.takvim.dateInterval(of: .month, for: t)?.end ?? t
    }
    var gunSayisi: Int { max(1, Tarih.takvim.dateComponents([.day], from: bas, to: son).day ?? 1) }
    func x(_ d: Date) -> CGFloat { CGFloat(Tarih.takvim.dateComponents([.day], from: bas, to: d.gunBasi).day ?? 0) * gunGenislik }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            haftalikRitim
            HStack {
                Bolumbasi(metin: "Takvim", sembol: "calendar")
                Spacer()
                Button { withAnimation(.snappy) { gunGenislik = max(2, gunGenislik / 1.6) } } label: { Image(systemName: "minus.magnifyingglass") }
                    .buttonStyle(.borderless)
                Button { withAnimation(.snappy) { gunGenislik = min(24, gunGenislik * 1.6) } } label: { Image(systemName: "plus.magnifyingglass") }
                    .buttonStyle(.borderless)
            }
            .foregroundStyle(Tema.ikincil)
            Yuzey(dolgu: 0) {
                HStack(alignment: .top, spacing: 0) {
                    // Sabit sol sütun: hat adları
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: ust)
                        ForEach(gorunen) { h in
                            Button { ac(h) } label: {
                                HStack(spacing: 6) {
                                    Circle().fill(h.renk.opacity(h.acik ? 1 : 0.4)).frame(width: 7, height: 7)
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(h.kod).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(h.renk)
                                        Text(h.ad).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Tema.metin).lineLimit(1)
                                    }
                                }
                                .frame(width: etiket - 10, height: satir, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 10)
                        }
                    }
                    .frame(width: etiket)
                    .background(Tema.yuzey)
                    Divider()
                    ScrollViewReader { okuyucu in
                        ScrollView(.horizontal, showsIndicators: false) {
                            ZStack(alignment: .topLeading) {
                                Canvas { c, boyut in ciz(c, boyut) }
                                    .frame(width: CGFloat(gunSayisi) * gunGenislik, height: ust + satir * CGFloat(gorunen.count))
                                // Satıra dokununca hat açılır
                                VStack(spacing: 0) {
                                    Color.clear.frame(height: ust)
                                    ForEach(gorunen) { h in
                                        Color.clear.frame(height: satir).contentShape(Rectangle()).onTapGesture { ac(h) }
                                    }
                                }
                                Color.clear.frame(width: 1, height: 1).padding(.leading, max(0, x(bugun) - 140)).id("bugun")
                            }
                        }
                        .defaultScrollAnchor(UnitPoint(x: min(1, max(0, x(bugun) / max(CGFloat(gunSayisi) * gunGenislik, 1))), y: 0))
                        .task(id: gunGenislik) {
                            try? await Task.sleep(nanoseconds: 80_000_000)
                            okuyucu.scrollTo("bugun", anchor: .leading)
                        }
                    }
                }
            }
            HStack(spacing: 14) {
                lejant(dolu: false, "teslim (Loader'a düştü)")
                lejant(dolu: true, "dinlendi")
                HStack(spacing: 4) { Image(systemName: "flag.fill").font(.system(size: 9)); Text("hedef / ölçüt").font(.caption2) }
                Spacer()
                Toggle("Kapananlar", isOn: $kapananlar.animation(.snappy)).toggleStyle(.switch).controlSize(.mini).font(.caption2)
                    .fixedSize()
            }
            .foregroundStyle(Tema.ikincil)
            Text("Kesik çizgi: bu hızla son birimin üretileceği gün. Sürüyorsa son üç haftanın hızı, bekleyen hatta planın temposu kullanılır.")
                .font(.caption2).foregroundStyle(Tema.soluk)
        }
    }

    private func lejant(dolu: Bool, _ s: String) -> some View {
        HStack(spacing: 4) {
            Circle().strokeBorder(Tema.ikincil, lineWidth: 1.2).background(Circle().fill(dolu ? Tema.ikincil : .clear)).frame(width: 8, height: 8)
            Text(s).font(.caption2)
        }
    }

    private func ciz(_ c: GraphicsContext, _ boyut: CGSize) {
        let t = Tarih.takvim
        // Ay şeritleri ve adları
        var ay = bas
        var tek = false
        while ay < son {
            let sonraki = t.date(byAdding: .month, value: 1, to: ay) ?? son
            let r = CGRect(x: x(ay), y: 0, width: x(sonraki) - x(ay), height: boyut.height)
            if tek { c.fill(Path(r), with: .color(Tema.yuzey2.opacity(0.45))) }
            c.draw(Text(ay.formatted(.dateTime.month(.abbreviated).locale(Dil.tr)).uppercased(with: Dil.tr))
                    .font(.system(size: 9.5, weight: .bold)).foregroundColor(Tema.soluk),
                   at: CGPoint(x: x(ay) + 6, y: 12), anchor: .leading)
            tek.toggle()
            ay = sonraki
        }
        // Haftalık ince çizgiler
        if gunGenislik >= 4 {
            var h = t.dateInterval(of: .weekOfYear, for: bas)?.start ?? bas
            while h < son {
                var p = Path(); p.move(to: CGPoint(x: x(h), y: ust - 6)); p.addLine(to: CGPoint(x: x(h), y: boyut.height))
                c.stroke(p, with: .color(Tema.cizgi.opacity(0.35)), lineWidth: 0.5)
                h = h.gun(7)
            }
        }
        // Satırlar
        for (i, h) in gorunen.enumerated() {
            let y = ust + CGFloat(i) * satir + satir / 2
            let renk = h.renk.opacity(h.acik ? 1 : 0.45)
            if i > 0 {
                var ayrac = Path(); ayrac.move(to: CGPoint(x: 0, y: y - satir / 2)); ayrac.addLine(to: CGPoint(x: boyut.width, y: y - satir / 2))
                c.stroke(ayrac, with: .color(Tema.cizgi.opacity(0.5)), lineWidth: 0.5)
            }
            let basT = gunTarih(h.kurulus) ?? gunTarih(h.ilk) ?? bugun
            let bitisGercek = h.acik ? bugun : (gunTarih(h.kapanis) ?? gunTarih(h.son) ?? bugun)
            // geçmiş şerit
            let serit = CGRect(x: x(basT), y: y - 3, width: max(3, x(bitisGercek) - x(basT)), height: 6)
            c.fill(Path(roundedRect: serit, cornerRadius: 3), with: .color(renk.opacity(0.18)))
            // gelecek: tahmini bitişe kesik çizgi
            if let tb = h.tahminiBitis() {
                var p = Path(); p.move(to: CGPoint(x: x(bugun), y: y)); p.addLine(to: CGPoint(x: x(min(tb, son)), y: y))
                c.stroke(p, with: .color(renk.opacity(h.durum == "suruyor" ? 0.7 : 0.35)),
                         style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 4]))
                if tb <= son {
                    c.draw(Text(Tarih.kisa(tb)).font(.system(size: 8.5, weight: .semibold)).foregroundColor(renk),
                           at: CGPoint(x: x(tb) + 4, y: y - 9), anchor: .leading)
                }
            }
            // hedef bayrağı
            if let hd = gunTarih(h.hedef), h.acik {
                var p = Path(); p.move(to: CGPoint(x: x(hd), y: y - 14)); p.addLine(to: CGPoint(x: x(hd), y: y + 10))
                c.stroke(p, with: .color(renk), lineWidth: 1)
                var bayrak = Path(); bayrak.move(to: CGPoint(x: x(hd), y: y - 14))
                bayrak.addLine(to: CGPoint(x: x(hd) + 8, y: y - 11)); bayrak.addLine(to: CGPoint(x: x(hd), y: y - 8)); bayrak.closeSubpath()
                c.fill(bayrak, with: .color(renk))
            }
            // kapanış işareti
            if h.durum == "kapandi", let k = gunTarih(h.kapanis) {
                c.draw(Text("✕").font(.system(size: 10, weight: .bold)).foregroundColor(Tema.soluk), at: CGPoint(x: x(k) + 6, y: y))
            }
            // noktalar: aynı güne düşenler üst üste değil yan yana küçük kayarak
            var sayac: [Int: Int] = [:]
            for b in h.birimler {
                if let t1 = gunTarih(b.teslim) {
                    let gx = Int(x(t1)); let n = sayac[gx, default: 0]; sayac[gx] = n + 1
                    let r = CGRect(x: x(t1) - 3.5, y: y - 3.5 - CGFloat(n % 3) * 4 + 4, width: 7, height: 7)
                    c.stroke(Path(ellipseIn: r), with: .color(renk), lineWidth: 1.2)
                }
                if b.d == .dinlendi, let t2 = gunTarih(b.dinleme) {
                    let gx = Int(x(t2)) + 100_000; let n = sayac[gx, default: 0]; sayac[gx] = n + 1
                    let r = CGRect(x: x(t2) - 3.5, y: y - 3.5 + CGFloat(n % 3) * 4 + 7, width: 7, height: 7)
                    c.fill(Path(ellipseIn: r), with: .color(renk))
                }
            }
        }
        // bugün çizgisi
        var p = Path(); p.move(to: CGPoint(x: x(bugun), y: 18)); p.addLine(to: CGPoint(x: x(bugun), y: boyut.height))
        c.stroke(p, with: .color(Tema.vurgu), lineWidth: 1.5)
        c.draw(Text("bugün").font(.system(size: 9, weight: .bold)).foregroundColor(Tema.vurgu), at: CGPoint(x: x(bugun) + 4, y: 24), anchor: .leading)
    }

    // Son 12 haftanın ritmi: üretilen ve dinlenen birim (bütün hatlar)
    private struct Ritim: Identifiable { let hafta: Date; let tur: String; let sayi: Int; var id: String { "\(hafta)\(tur)" } }

    private var ritim: [Ritim] {
        let t = Tarih.takvim
        let buHafta = t.dateInterval(of: .weekOfYear, for: bugun)?.start ?? bugun
        let haftalar = (0..<12).reversed().map { buHafta.gun(-7 * $0) }
        var u = [Date: Int](), d = [Date: Int]()
        for h in hatlar { for b in h.birimler {
            if let x = gunTarih(b.teslim), let w = t.dateInterval(of: .weekOfYear, for: x)?.start { u[w, default: 0] += 1 }
            if b.d == .dinlendi, let x = gunTarih(b.dinleme), let w = t.dateInterval(of: .weekOfYear, for: x)?.start { d[w, default: 0] += 1 }
        } }
        return haftalar.flatMap { [Ritim(hafta: $0, tur: "Üretilen", sayi: u[$0] ?? 0), Ritim(hafta: $0, tur: "Dinlenen", sayi: d[$0] ?? 0)] }
    }

    private var haftalikRitim: some View {
        Yuzey(dolgu: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Bolumbasi(metin: "Son 12 hafta", sembol: "waveform.path.ecg")
                    Spacer()
                    Text("üretim ↔ dinleme").font(.caption2).foregroundStyle(Tema.soluk)
                }
                Chart(ritim) { r in
                    BarMark(x: .value("Hafta", r.hafta, unit: .weekOfYear), y: .value("Birim", r.sayi))
                        .foregroundStyle(by: .value("Tür", r.tur))
                        .position(by: .value("Tür", r.tur))
                        .cornerRadius(2)
                }
                .chartForegroundStyleScale(["Üretilen": Tema.vurgu.opacity(0.35), "Dinlenen": Tema.vurgu])
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated).locale(Dil.tr))
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 130)
            }
        }
    }
}

// MARK: - Sırada

struct SiraGorunumu: View {
    let hatlar: [MHat]
    var sutunlu: Bool
    var ac: (MHat) -> Void

    struct Satir: Identifiable { let hat: MHat; let birim: MBirim; var id: String { hat.kod + birim.kod } }

    var kulakta: [Satir] {
        hatlar.filter(\.acik).flatMap { h in h.kulakta.map { Satir(hat: h, birim: $0) } }
            .sorted { ($0.birim.dinleme ?? "") > ($1.birim.dinleme ?? "") }
    }
    var bekleyen: [(MHat, [MBirim])] {
        hatlar.filter(\.acik).compactMap { h in
            let b = h.bekleyenler
            return b.isEmpty ? nil : (h, b)
        }
        .sorted { $0.1.count > $1.1.count }
    }
    var siradaki: [Satir] {
        hatlar.filter(\.acik).compactMap { h in h.siradakiBirim.map { Satir(hat: h, birim: $0) } }
            .sorted { MAlan.statusRank($0.hat.durum) < MAlan.statusRank($1.hat.durum) }
    }

    var body: some View {
        if sutunlu {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 14) { kulaktaBolum }.frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(alignment: .leading, spacing: 14) { bekleyenBolum }.frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(alignment: .leading, spacing: 14) { siradakiBolum }.frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 12) { kulaktaBolum }
                VStack(alignment: .leading, spacing: 12) { bekleyenBolum }
                VStack(alignment: .leading, spacing: 12) { siradakiBolum }
            }
        }
    }

    @ViewBuilder private var kulaktaBolum: some View {
        Bolumbasi(metin: "Kulağında · \(kulakta.count)", sembol: "headphones")
        Text("Voice Dream'de yarıda duran metinler, en son açılan üstte.").font(.caption).foregroundStyle(Tema.soluk)
        if kulakta.isEmpty { bos("Yarıda kalan metin yok.") }
        ForEach(kulakta) { s in
            Button { ac(s.hat) } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Halka(oran: Double(s.birim.yuzde ?? 0) / 100, renk: s.hat.renk, kalinlik: 4)
                        Text("\(s.birim.yuzde ?? 0)").font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.birim.gosterilenAd).font(Tema.serif(.subheadline, .semibold)).foregroundStyle(Tema.metin).lineLimit(2)
                        Text("\(s.hat.ad) · \(s.birim.kod) · \(kisaTarih(s.birim.dinleme))").font(.caption2).foregroundStyle(Tema.ikincil)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Tema.yuzey))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var bekleyenBolum: some View {
        let toplam = bekleyen.reduce(0) { $0 + $1.1.count }
        Bolumbasi(metin: "Dinlenmeyi bekleyen · \(toplam)", sembol: "tray.full")
        Text("Hazır ama hiç açılmamış metinler, en eski teslim önde.").font(.caption).foregroundStyle(Tema.soluk)
        if bekleyen.isEmpty { bos("Bekleyen metin yok.") }
        ForEach(bekleyen, id: \.0.kod) { h, b in
            Button { ac(h) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Circle().fill(h.renk).frame(width: 8, height: 8)
                        Text(h.ad).font(.subheadline.weight(.semibold)).foregroundStyle(Tema.metin)
                        Spacer()
                        Text("\(b.count)").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(h.renk)
                    }
                    ForEach(b.sorted { ($0.teslim ?? "") < ($1.teslim ?? "") }.prefix(4)) { x in
                        HStack(spacing: 6) {
                            Text(x.kod).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(Tema.soluk)
                                .frame(width: 58, alignment: .leading)
                            Text(x.gosterilenAd).font(.caption).foregroundStyle(Tema.ikincil).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(kisaTarih(x.teslim)).font(.caption2).foregroundStyle(Tema.soluk)
                        }
                    }
                    if b.count > 4 { Text("+\(b.count - 4) daha").font(.caption2).foregroundStyle(Tema.soluk) }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Tema.yuzey))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var siradakiBolum: some View {
        Bolumbasi(metin: "Sıradaki üretim", sembol: "arrow.turn.down.right")
        Text("Her açık hattın müfredattaki bir sonraki birimi.").font(.caption).foregroundStyle(Tema.soluk)
        ForEach(siradaki) { s in
            Button { ac(s.hat) } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: MAlan.durumSembol(s.hat.durum)).foregroundStyle(s.hat.renk).font(.system(size: 15))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.birim.ad).font(Tema.serif(.subheadline, .semibold)).foregroundStyle(Tema.metin).lineLimit(2)
                        if let a = s.birim.alt { Text(a).font(.caption).foregroundStyle(Tema.ikincil).lineLimit(2) }
                        Text("\(s.hat.ad) · \(s.birim.kod) · \(MAlan.durumAd(s.hat.durum).lowercased(with: Dil.tr))")
                            .font(.caption2).foregroundStyle(Tema.soluk)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Tema.yuzey))
            }
            .buttonStyle(.plain)
        }
    }

    private func bos(_ s: String) -> some View {
        Text(s).font(.footnote).foregroundStyle(Tema.soluk).padding(.vertical, 6)
    }
}

// MARK: - Hat detayı (metro hattı)

struct HatDetay: View {
    let hat: MHat
    var genis = false
    @State private var acik: Set<Int> = []
    @State private var hepsi = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                kunye
                sayilar
                if hat.fazlar.count > 1 || hat.gruplar.count > 1 { fazSeridi }
                metro
            }
            .padding(genis ? 26 : 18)
            .frame(maxWidth: genis ? 860 : 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Tema.arka)
        #if os(iOS)
        .navigationTitle(hat.ad)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { if acik.isEmpty { acik = Set(baslangicAcik) } }
    }

    /// Kulakta olan, sıradaki ve son dinlenen birimin grupları açık başlar.
    private var baslangicAcik: [Int] {
        let g = hat.gruplar
        var s = Set<Int>()
        for x in g {
            if x.birimler.contains(where: { $0.d == .dinleniyor || $0.kod == hat.siradaki }) { s.insert(x.sira) }
        }
        if let son = g.last(where: { $0.birimler.contains { $0.d.uretildi } }) { s.insert(son.sira) }
        if s.isEmpty, let ilk = g.first { s.insert(ilk.sira) }
        if g.count <= 2 { g.forEach { s.insert($0.sira) } }
        return Array(s)
    }

    private var kunye: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(hat.kod).font(.system(size: 12, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(hat.renk.opacity(0.15))).foregroundStyle(hat.renk)
                Label(MAlan.durumAd(hat.durum), systemImage: MAlan.durumSembol(hat.durum))
                    .font(.caption.weight(.semibold)).foregroundStyle(hat.durum == "suruyor" ? Tema.basari : Tema.ikincil)
                Text("· \(MAlan.ad(hat.alan))").font(.caption).foregroundStyle(Tema.soluk)
            }
            Text(hat.ad).font(Tema.serif(genis ? .largeTitle : .title, .bold)).foregroundStyle(Tema.metin)
            if let a = hat.alt { Text(a).font(Tema.serif(.body)).foregroundStyle(Tema.ikincil) }
            if let n = hat.durumNot {
                Label(n, systemImage: "info.circle").font(.footnote).foregroundStyle(Tema.ikincil)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Tema.yuzey2.opacity(0.7)))
            }
            if hat.durum == "kapandi", let n = hat.neden {
                Label("Kapandı \(kisaTarih(hat.kapanis)) — \(n)", systemImage: "archivebox").font(.footnote).foregroundStyle(Tema.ikincil)
            }
            if let o = hat.onceki { Text(o).font(.caption).foregroundStyle(Tema.soluk) }
        }
    }

    private var sayilar: some View {
        Yuzey(dolgu: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    ZStack {
                        Halka(oran: hat.uretimOrani, renk: hat.renk.opacity(0.35), kalinlik: 10)
                        Halka(oran: hat.dinlenmeOrani, renk: hat.renk, kalinlik: 10, iz: .clear)
                        VStack(spacing: -2) {
                            Text("%\(Int((hat.dinlenmeOrani * 100).rounded()))").font(.system(size: 18, weight: .bold, design: .rounded))
                            Text("dinlendi").font(.system(size: 9, weight: .semibold)).foregroundStyle(Tema.soluk)
                        }
                    }
                    .frame(width: 84, height: 84)
                    VStack(alignment: .leading, spacing: 6) {
                        satir("Üretilen", "\(hat.uretilen) / \(hat.toplam) \(hat.birim)")
                        satir("Dinlenen", "\(hat.dinlenen)" + (hat.dinleniyor > 0 ? " · \(hat.dinleniyor) kulakta" : ""))
                        if hat.bekleyen > 0 { satir("Bekleyen", "\(hat.bekleyen) hazır, açılmadı", Tema.uyari) }
                        if hat.yazim == true, hat.uretilen > 0 { satir("Yazılan", "\(hat.uretilen) bölüm taslakta") }
                        if hat.vdYok > 0 { satir("VD'de yok", "\(hat.vdYok) yazılmış metnin Voice Dream kaydı yok") }
                        if let a = hat.atlanan, a > 0 { satir("Atlanan", "\(a)") }
                    }
                }
                Divider().opacity(0.5)
                VStack(alignment: .leading, spacing: 6) {
                    if let k = hat.kurulus { satir("Kuruluş", kisaTarih(k) + (hat.son.map { " · son hareket \(kisaTarih($0))" } ?? "")) }
                    if let h = hat.hedef { satir("Hedef", kisaTarih(h)) }
                    if let o = hat.olcut { satir("Ölçüt", o) }
                    if hat.acik {
                        let tempo = hat.hizGercek ? String(format: "son 3 haftada haftada %.1f", hat.hiz ?? 0)
                            : (hat.tempo.map { "plan: haftada \(Int($0))" } ?? "—")
                        satir("Tempo", tempo + (hat.dinlemeHizi.map { $0 > 0 ? String(format: " · dinleme %.1f/hf", $0) : "" } ?? ""))
                        if let b = hat.tahminiBitis() {
                            satir("Tahmini bitiş", "\(ayYil(b)) · \(hat.kalan) \(hat.birim) kaldı", hat.renk)
                        }
                    }
                    if let k = hat.konum { satir("Klasör", k).textSelection(.enabled) }
                }
            }
        }
    }

    private func satir(_ e: String, _ d: String, _ renk: Color = Tema.metin) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(e).font(.caption.weight(.semibold)).foregroundStyle(Tema.soluk).frame(width: 92, alignment: .leading)
            Text(d).font(.callout).foregroundStyle(renk).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Fazlar ve gruplar orantılı bir şeritte: her blok kendi tamamlanma oranıyla dolar. Dokununca o blok açılır.
    private var fazSeridi: some View {
        VStack(alignment: .leading, spacing: 8) {
            Bolumbasi(metin: "Yolun bütünü", sembol: "point.topleft.down.to.point.bottomright.curvepath")
            GeometryReader { g in
                let gruplar = hat.gruplar
                let toplam = CGFloat(max(hat.birimler.count, 1))
                let bosluk: CGFloat = 2
                let kullanilir = g.size.width - bosluk * CGFloat(max(gruplar.count - 1, 0))
                HStack(spacing: bosluk) {
                    ForEach(gruplar) { gr in
                        let w = max(3, kullanilir * CGFloat(gr.birimler.count) / toplam)
                        let o = Double(gr.dinlenen) / Double(max(gr.birimler.count, 1))
                        let u = Double(gr.uretilen) / Double(max(gr.birimler.count, 1))
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Tema.cizgi.opacity(0.7))
                            Rectangle().fill(hat.renk.opacity(0.3)).frame(width: w * u)
                            Rectangle().fill(hat.renk).frame(width: w * o)
                        }
                        .frame(width: w)
                        .onTapGesture { withAnimation(.snappy) { _ = acik.insert(gr.sira) } }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .frame(height: 22)
            if hat.fazlar.count > 1 {
                HStack(spacing: 6) {
                    ForEach(hat.fazlar, id: \.self) { f in
                        let b = hat.birimler.filter { $0.faz == f }
                        Text("\(f) · \(b.filter { $0.d == .dinlendi }.count)/\(b.count)")
                            .font(.caption2.weight(.semibold)).foregroundStyle(Tema.ikincil)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Tema.yuzey2))
                    }
                }
            }
        }
    }

    private var metro: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Bolumbasi(metin: "Duraklar", sembol: "tram")
                Spacer()
                Button(hepsi ? "Hepsini kapat" : "Hepsini aç") {
                    withAnimation(.snappy) {
                        hepsi.toggle()
                        acik = hepsi ? Set(hat.gruplar.map(\.sira)) : Set(baslangicAcik)
                    }
                }
                .font(.caption.weight(.semibold)).buttonStyle(.borderless)
            }
            let gruplar = hat.gruplar
            ForEach(gruplar) { g in
                let oncekiFaz = g.sira > 0 ? gruplar[g.sira - 1].faz : nil
                if let f = g.faz, f != oncekiFaz {
                    Text(f.uppercased(with: Dil.tr)).font(.system(size: 11, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(hat.renk).padding(.top, g.sira > 0 ? 14 : 0)
                }
                grupKarti(g)
            }
        }
    }

    private func grupKarti(_ g: MGrup) -> some View {
        let acikMi = acik.contains(g.sira)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy) { if acikMi { acik.remove(g.sira) } else { acik.insert(g.sira) } }
                Dokunus.hafif(0.3)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(g.ad ?? "Duraklar").font(.subheadline.weight(.semibold)).foregroundStyle(Tema.metin).multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Text("\(g.dinlenen)/\(g.birimler.count)").font(.caption.weight(.bold)).foregroundStyle(g.dinlenen == g.birimler.count ? hat.renk : Tema.soluk)
                        Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(Tema.soluk)
                            .rotationEffect(.degrees(acikMi ? 0 : -90))
                    }
                    if !acikMi { NoktaSeridi(birimler: g.birimler, renk: hat.renk, siradaki: hat.siradaki) }
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if acikMi {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(g.birimler.enumerated()), id: \.element.id) { i, b in
                        Durak(birim: b, renk: hat.renk, ilk: i == 0, son: i == g.birimler.count - 1,
                              siradaki: b.kod == hat.siradaki, tezgah: hat.tur != "dinleme", vdYok: b.vdYok(hat.tur))
                    }
                }
                .padding(.horizontal, 14).padding(.bottom, 10)
                .transition(.opacity)
            }
        }
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Tema.yuzey))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Tema.cizgi.opacity(0.6), lineWidth: 0.5))
    }
}

/// Kapalı grubun özeti: her birim bir nokta.
struct NoktaSeridi: View {
    let birimler: [MBirim]
    let renk: Color
    var siradaki: String?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 9, maximum: 9), spacing: 4)], alignment: .leading, spacing: 4) {
            ForEach(birimler) { b in
                ZStack {
                    switch b.d {
                    case .dinlendi: Circle().fill(renk)
                    case .dinleniyor: Circle().fill(renk.opacity(0.25)); Circle().trim(from: 0, to: Double(b.yuzde ?? 0) / 100).fill(renk)
                    case .uretildi: Circle().strokeBorder(renk, lineWidth: 1.5)
                    case .atlandi: Circle().strokeBorder(Tema.soluk.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [1.5, 1.5]))
                    case .plan: Circle().fill(Tema.cizgi)
                    }
                    if b.kod == siradaki { Circle().strokeBorder(Tema.vurgu, lineWidth: 1.5).padding(-2.5) }
                }
                .frame(width: 9, height: 9)
            }
        }
    }
}

/// Metro durağı: solda dikey hat ve durum dairesi, sağda kod, ad, açıklama ve Voice Dream bilgisi.
struct Durak: View {
    let birim: MBirim
    let renk: Color
    var ilk = false
    var son = false
    var siradaki = false
    var tezgah = false
    var vdYok = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    Rectangle().fill(ilk ? .clear : cizgiRengi).frame(width: 2, height: 12)
                    Rectangle().fill(son ? .clear : cizgiRengi).frame(width: 2)
                }
                daire.padding(.top, 5)
            }
            .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(birim.kod).font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(birim.d == .plan ? Tema.soluk : renk)
                    if siradaki { Hap(metin: "sıradaki", renk: Tema.vurgu) .scaleEffect(0.85, anchor: .leading) }
                    if birim.d == .dinleniyor { Hap(metin: "kulakta %\(birim.yuzde ?? 0)", renk: renk).scaleEffect(0.85, anchor: .leading) }
                    Spacer(minLength: 0)
                    meta
                }
                Text(birim.gosterilenAd).font(Tema.serif(.subheadline, birim.d == .plan ? .regular : .semibold))
                    .foregroundStyle(birim.d == .plan || birim.d == .atlandi ? Tema.ikincil : Tema.metin)
                    .strikethrough(birim.d == .atlandi, color: Tema.soluk)
                if birim.planFarkli {
                    Text("planda: \(birim.ad)").font(.caption2).foregroundStyle(Tema.soluk).lineLimit(1)
                } else if let a = birim.alt, !a.isEmpty {
                    Text(a).font(.caption).foregroundStyle(Tema.ikincil).lineLimit(2)
                }
            }
            .padding(.vertical, 7)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(birim.kod) \(birim.gosterilenAd), \(birim.d.ad)")
    }

    private var cizgiRengi: Color { birim.d == .dinlendi ? renk.opacity(0.7) : Tema.cizgi }

    @ViewBuilder private var daire: some View {
        ZStack {
            switch birim.d {
            case .dinlendi:
                Circle().fill(renk)
                Image(systemName: "checkmark").font(.system(size: 7.5, weight: .heavy)).foregroundStyle(.white)
            case .dinleniyor:
                Circle().fill(Tema.yuzey)
                Circle().stroke(renk.opacity(0.25), lineWidth: 3)
                Circle().trim(from: 0, to: Double(birim.yuzde ?? 0) / 100).stroke(renk, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            case .uretildi:
                Circle().fill(Tema.yuzey); Circle().strokeBorder(renk, lineWidth: 2)
            case .atlandi:
                Circle().fill(Tema.yuzey); Circle().strokeBorder(Tema.soluk, style: StrokeStyle(lineWidth: 1.2, dash: [2, 2]))
            case .plan:
                Circle().fill(Tema.yuzey); Circle().strokeBorder(Tema.cizgi, lineWidth: 1.5)
            }
            if siradaki { Circle().strokeBorder(Tema.vurgu, lineWidth: 2).padding(-4) }
        }
        .frame(width: 14, height: 14)
        .background(Tema.yuzey.clipShape(Circle()))
    }

    @ViewBuilder private var meta: some View {
        HStack(spacing: 6) {
            if let i = birim.isaret, i > 0 {
                Label("\(i)", systemImage: "highlighter").font(.caption2).foregroundStyle(Tema.soluk).labelStyle(.titleAndIcon)
            }
            switch birim.d {
            case .dinlendi:
                Text((tezgah ? "" : "dinlendi ") + kisaTarih(birim.dinleme)).font(.caption2).foregroundStyle(Tema.soluk)
            case .dinleniyor, .uretildi:
                Text((vdYok ? "VD'de yok · " : "") + kisaTarih(birim.teslim)).font(.caption2).foregroundStyle(Tema.soluk)
            default: EmptyView()
            }
        }
    }
}
