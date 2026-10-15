// Bugün: başlangıç kartı → ① oku ve dinle (+ sesli oku) → ② cümle turu → ③ paragraf.
// (④ test, ⑤ kendi cümlen, ⑥ hesap: Test.swift)
import SwiftUI

struct BugunGorunum: View {
    @EnvironmentObject var t: Tezgah
    var body: some View {
        if let o = t.o {
            Group {
                switch o.adim {
                case .oku: OkuEkrani()
                case .cumle: CumleEkrani()
                case .paragraf: ParagrafEkrani()
                case .recall: RecallEkrani()
                case .kendi: KendiEkrani()
                case .bitis: BitisEkrani()
                }
            }
            .id(o.adim)
        } else {
            Baslangic()
        }
    }
}

/// Tek sütun, ortada, okunur genişlik.
struct Sutun<I: View>: View {
    var genislik: CGFloat = 760
    @ViewBuilder var icerik: I
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) { icerik }
                .frame(maxWidth: genislik, alignment: .leading)
                .padding(.horizontal, 32).padding(.vertical, 26)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Başlangıç

struct Baslangic: View {
    @EnvironmentObject var t: Tezgah
    var body: some View {
        Sutun {
            if let g = t.gunMasa {
                let yapildi = t.calisildi(g)
                VStack(alignment: .leading, spacing: 12) {
                    Text(yapildi != nil ? "GÜN \(g.no) · ÇALIŞILDI" : t.atlananGunler.contains(g.no) ? "GÜN \(g.no) · GEÇİLMİŞ" : "GÜN \(g.no) · HAZIR").font(.caption.weight(.semibold)).foregroundStyle(Renk.vurgu).tracking(0.6)
                    Text("Gün \(g.no) · \(g.ad)").font(.system(size: 30, weight: .bold))
                    if let z = g.ozet ?? g.tema { Text(z).font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                    Akis {
                        ForEach(g.sahne, id: \.self) { Cip(metin: $0, renk: Renk.vurgu, simge: "textformat") }
                        Cip(metin: "\(g.cumleler.count) cümle · \(Metin.kelimeler(g.cumleler.map(\.en).joined(separator: " ")).count) kelime")
                        if let n = g.yeni?.count, n > 0 { Cip(metin: "\(n) yeni", renk: .blue) }
                        if let n = g.tanidik?.count, n > 0 { Cip(metin: "\(n) tanıdık", renk: Renk.yesil) }
                        if let n = g.yanki?.count, n > 0 { Cip(metin: "\(n) yankı", renk: Renk.sari) }
                    }
                    if let y = yapildi {
                        HStack {
                            Button("Yine de çalış (tekrar)") {
                                t.baslat(g, tekrar: true, hatirlatma: y.hatirlatma.isEmpty ? nil : Hatirlatma(konular: y.hatirlatma, dongu: nil, gun: nil))
                            }
                            Button("Geçmişte aç") { t.gorunum = .gecmis }.buttonStyle(.borderless)
                        }
                        Text(y.tarih.isEmpty ? "Bu gün yazıldı; sonucu sabah görevi sicile işler. Sıradaki güne «Sonraki gün» ile geçebilirsin. Tekrar çalışma sicile işlenmez."
                             : "Bu gün \(Gun.trKisa(y.tarih)) tarihinde çalışıldı (cümle \(y.tutma.map { "%\($0)" } ?? "—")). Sıradaki güne «Sonraki gün» ile geç. Tekrar çalışma sicile işlenmez.")
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
                        // kısayol yok: uygulama öne gelirken başka pencereye basılan ⌘↩ oturum açmasın
                        Button { t.baslat(g) } label: { Text("Başlat").font(.headline).padding(.horizontal, 22).padding(.vertical, 6) }
                            .buttonStyle(.borderedProminent)
                        Text(t.atlananGunler.contains(g.no)
                             ? "Bu günü «Yaptım, geç» ile geçmiştin; şimdi çalışırsan sonuç yine sicile işlenir."
                             : "~20 dk · oku ve sesli oku → cümle turu → paragraf → hatırlama testi → kendi cümlen → hesap")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    GunGezgini(g: g, yapildi: yapildi != nil)
                }
                HazirlikKarti(gun: g.no)
                let d = t.hatirDurum(), gunler = t.gecmis()
                HStack(spacing: 10) {
                    Kutu(k: "seri", v: "\(t.seri(gunler)) gün")
                    Kutu(k: "çalışılan", v: "\(gunler.count) gün")
                    Kutu(k: "son cümle turu", v: gunler.first?.tutma.map { "%\($0)" } ?? "—")
                    Kutu(k: "gramer döngüsü", v: "\(d.konum)/60")
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Açık gün yok").font(.title.bold())
                    Text("Haftalık paket sabah görevinden gelir (oncalisma/paket/gun-NNN/). İstersen elinde olan gün JSON'unu kenar çubuğundaki «İçe aktar…» ile ya da pencereye sürükleyerek ekleyebilirsin.")
                        .foregroundStyle(.secondary)
                    Button { t.iceAktarPaneli() } label: { Label("Gün JSON'u içe aktar…", systemImage: "square.and.arrow.down") }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

/// Önceki · sonraki · «Yaptım, geç» — masadaki dosyaya bağlı kalmadan günler arasında gezinme.
struct GunGezgini: View {
    var g: GunVeri
    var yapildi: Bool
    @EnvironmentObject var t: Tezgah
    var body: some View {
        HStack(spacing: 10) {
            Button { t.oncekiGun() } label: { Label("Önceki", systemImage: "chevron.left") }
            Button { t.sonrakiGun() } label: { Label("Sonraki gün", systemImage: "chevron.right") }
            if !yapildi && !t.atlananGunler.contains(g.no) {
                Button { t.atla(g) } label: { Label("Yaptım, geç", systemImage: "arrowshape.turn.up.right") }
                    .help("Bu günü başka yerde yaptın ya da tekrar etmek istemiyorsun: sicile girmez, sıradaki gün açılır; telefon da görür")
            }
            Button { t.iceAktarPaneli() } label: { Label("İçe aktar…", systemImage: "square.and.arrow.down") }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }
}

/// Telefondaki ön çalışmanın canlı özeti + yol haritası. Oturum boyunca birkaç saniyede bir tazelenir.
struct HazirlikKarti: View {
    var gun: Int
    @EnvironmentObject var t: Tezgah
    var body: some View {
        let h = t.hazirlik
        Kart {
            HStack {
                Baslik(metin: "Ön çalışma · telefon", alt: h.basladi ? "çalışmış olarak giriyorsun" : "telefonda henüz yok")
                Spacer()
                if h.basladi { Image(systemName: "checkmark.seal.fill").foregroundStyle(Renk.yesil) }
            }
            HStack(spacing: 10) {
                adim("headphones", h.dinleme > 0 ? "\(h.dinleme)× dinlendi" : "dinlenmedi", h.dinleme > 0)
                adim("book", h.okuma ? "ekrandan okundu" : "okunmadı", h.okuma)
                adim("mic", h.kayit > 0 ? "\(h.kayit) kayıt" : "kayıt yok", h.kayit > 0)
            }
            if !h.takildi.isEmpty {
                Text("Telefonda takıldığın cümleler: " + h.takildi.keys.sorted().map { "\($0 + 1)" }.joined(separator: ", ")
                     + " — cümle turunda haritada işaretli.")
                    .font(.callout)
            }
            if !h.takilan.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Okurken takıldığın kelimeler").font(.callout).foregroundStyle(.secondary)
                    Akis { ForEach(h.takilan, id: \.self) { KelimeDugmesi(kelime: $0, renk: Renk.sari) } }
                }
            }
            if !h.basladi, h.paket {
                let u = Yol.paketKlasoru(gun).appendingPathComponent("ses.m4a")
                if FileManager.default.fileExists(atPath: u.path) {
                    HStack {
                        Button { t.ses.dur(); t.calici.cal(u) } label: {
                            Label(t.calici.calan == u ? "Durdur" : "Paketi burada dinle", systemImage: t.calici.calan == u ? "stop.fill" : "play.fill")
                        }
                        Text("açıklama → metin → kelimeler ve yapılar · telefondaki sesin aynısı").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !t.rota.isEmpty {
                Divider()
                Text("Yol haritası — son günlerde en çok tekrarlanan").font(.callout.weight(.semibold))
                ForEach(Array(t.rota.enumerated()), id: \.offset) { n, r in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(n + 1).").foregroundStyle(.secondary).monospacedDigit()
                        Text(r.tur).bold()
                        Text(r.not).foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
        }
    }
    func adim(_ s: String, _ y: String, _ ok: Bool) -> some View {
        Label(y, systemImage: s).font(.callout)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(ok ? Renk.yesil.opacity(0.14) : Color.secondary.opacity(0.1)))
            .foregroundStyle(ok ? Renk.yesil : .secondary)
    }
}

struct GramerSeridi: View {
    @EnvironmentObject var t: Tezgah
    var body: some View {
        let h = t.o?.hatirlatma ?? t.hatirAta()
        HStack(spacing: 8) {
            Image(systemName: "book.closed").foregroundStyle(Renk.vurgu)
            Text("Bugünün gramer konuları: ") + Text(h.konular.map(Gramer.kisa).joined(separator: " · ")).bold()
            Spacer()
            Button("aç") { t.gramerAc() }.buttonStyle(.borderless).keyboardShortcut("g", modifiers: .option)
        }
        .font(.callout)
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10).fill(Renk.vurgu.opacity(0.08)))
    }
}

// MARK: - ① Oku ve dinle

struct OkuEkrani: View {
    @EnvironmentObject var t: Tezgah
    @ObservedObject var ses: Ses
    @ObservedObject var k: Kaydedici
    @State private var tanima = true
    @State private var trAcik = false

    init() {
        // @EnvironmentObject init'te okunamaz; paylaşılan nesneler AppDelegate'teki tek Tezgâh'tan
        _ses = ObservedObject(wrappedValue: TezgahKok.t.ses)
        _k = ObservedObject(wrappedValue: TezgahKok.t.kaydedici)
    }

    var body: some View {
        if let o = t.o {
            Sutun {
                Baslik(metin: "① Oku, dinle, sesli oku")
                if !o.tekrar { HazirlikKarti(gun: o.gun.no) }
                Kart {
                    Baslik(metin: "Mesele ne?")
                    Text(o.gun.ozet ?? o.gun.tema ?? "").font(.title3).fixedSize(horizontal: false, vertical: true)
                    if o.gun.ozet != nil, let tm = o.gun.tema { Text(tm).font(.callout).foregroundStyle(.secondary) }
                    DisclosureGroup("Türkçe metnin tamamını oku", isExpanded: $trAcik) {
                        Text(o.gun.cumleler.compactMap(\.tr).joined(separator: " ")).font(.body).padding(.top, 6)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                }
                GramerSeridi()
                if !o.gun.sahne.isEmpty {
                    Kart {
                        Baslik(metin: "Paragrafın yapıları", alt: "metin boyunca bunları ara")
                        ForEach(Array(o.gun.sahne.enumerated()), id: \.offset) { n, s in
                            HStack {
                                Text("\(n + 1)").font(.headline).foregroundStyle(Renk.vurgu).frame(width: 22)
                                VStack(alignment: .leading) {
                                    Text(s).font(.body.weight(.semibold))
                                    Text("\(o.gun.cumleler.filter { $0.konu == s }.count) cümlede işaretli").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                HStack {
                    Button { ses.zincirde ? ses.dur() : ses.zincir(o.gun.cumleler.map(\.en)) } label: {
                        Label(ses.zincirde ? "Dur" : "Paragrafı dinle", systemImage: ses.zincirde ? "stop.fill" : "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    Text("cümleye tıkla → o cümleyi dinle").font(.caption).foregroundStyle(.secondary)
                }
                metin(o)
                kelimeler(o)
                SesliOkuma(tanima: $tanima)
                Button { t.ses.dur(); t.adimaGit(.cumle); t.cumleGit(0) } label: {
                    Text("Okudum, yazmaya başla →").padding(.horizontal, 12).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    /// Metin tek akan paragraf; cümleye tıkla → o cümle okunur. Kayıttan sonra tanınan yeşil, takılan sarı.
    func metin(_ o: Oturum) -> some View {
        var a = AttributedString()
        var n = 0
        let isaretli = k.hal == .bitti && k.sonuc != nil
        for (i, c) in o.gun.cumleler.enumerated() {
            var p = boya(c.en, bas: n, isaretli: isaretli)
            n += Metin.kelimeler(c.en).count
            p.link = URL(string: "cumle://s/\(i)")
            if ses.calanCumle == i { p.backgroundColor = Renk.vurgu.opacity(0.18) }
            a += p
            a += AttributedString(" ")
        }
        return Text(a)
            .font(.serif(20)).lineSpacing(7)
            .tint(.primary)
            .textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { u in
                if let i = Int(u.lastPathComponent), i < o.gun.cumleler.count { ses.soyle(o.gun.cumleler[i].en, cumle: i) }
                return .handled
            })
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 14).fill(Renk.kart))
    }

    func boya(_ en: String, bas: Int, isaretli: Bool) -> AttributedString {
        var a = AttributedString(en)
        guard isaretli else { return a }
        let son = k.okunan - 1
        var arama = a.startIndex
        for (j, (w, _)) in Metin.araliklar(en).enumerated() {
            let idx = bas + j
            guard let r = a[arama...].range(of: w) else { continue }
            if k.eslesen.contains(idx) { a[r].foregroundColor = Renk.yesil }
            else if idx <= son { a[r].backgroundColor = Renk.sari.opacity(0.35) }
            arama = r.upperBound
        }
        return a
    }

    @ViewBuilder func kelimeler(_ o: Oturum) -> some View {
        let y = o.gun.yeni ?? [], tn = o.gun.tanidik ?? [], yk = o.gun.yanki ?? []
        if !(y + tn + yk).isEmpty {
            Kart {
                Baslik(metin: "Hedef kelimeler", alt: "tıkla → anlam ve Oxford kaydı")
                Akis {
                    ForEach(y, id: \.self) { KelimeDugmesi(kelime: $0, renk: .blue) }
                    ForEach(tn, id: \.self) { KelimeDugmesi(kelime: $0, renk: Renk.yesil) }
                    ForEach(yk, id: \.self) { KelimeDugmesi(kelime: $0, renk: Renk.sari) }
                }
                Text("mavi yeni · yeşil tanıdık · turuncu daha önce zorlandığın").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Mac'te sesli okuma: kayıt telefonla aynı klasöre gider; kayıtlar iki cihazdan birlikte listelenir.
struct SesliOkuma: View {
    @Binding var tanima: Bool
    @EnvironmentObject var t: Tezgah
    @ObservedObject var k = TezgahKok.t.kaydedici
    @ObservedObject var c = TezgahKok.t.calici
    var body: some View {
        Kart {
            HStack {
                Baslik(metin: "🎙 Sesli okuma")
                Spacer()
                Toggle("okuduğumu işaretle (cihaz içi tanıma)", isOn: $tanima).toggleStyle(.checkbox).font(.caption)
            }
            HStack(spacing: 14) {
                switch k.hal {
                case .kayit:
                    Button { Task { await t.kayitBitir(tanima: tanima) } } label: { Label("Bitir", systemImage: "stop.fill") }
                        .buttonStyle(.borderedProminent).tint(Renk.kirmizi)
                    Button("Vazgeç") { k.vazgec() }
                    ProgressView(value: Double(k.seviye)).frame(width: 120)
                    Text(String(format: "%d:%02d", Int(k.sure) / 60, Int(k.sure) % 60)).monospacedDigit().foregroundStyle(Renk.kirmizi)
                case .cozuluyor:
                    ProgressView().controlSize(.small); Text("Cihazda yazıya çevriliyor…").foregroundStyle(.secondary)
                default:
                    Button { Task { await t.kayitBaslat() } } label: { Label("Sesli oku ve kaydet", systemImage: "mic.fill") }
                        .buttonStyle(.borderedProminent).tint(Renk.kirmizi)
                }
            }
            Group {
                if case .hata(let m) = k.hal { Text(m) }
                else if let s = k.sonuc, k.hal == .bitti {
                    Text("Okuduğun \(s.okunan) kelimenin %\(s.yuzde)'i tanındı. ") + Text(s.takilan.isEmpty ? "Takılan kelime yok." : "Sarılar tanıyıcının duymadığı kelimeler — tıkla, Oxford kaydını dinle, sonra bir daha oku.")
                } else if k.hal == .bitti { Text("Kayıt alındı. Aşağıdan dinle, sonra \"Paragrafı dinle\" ile doğru okunuşla karşılaştır.") }
                else { Text("Paragrafı baştan sona, acele etmeden oku. Bitince düğmeye yeniden bas. Kayıt telefonla aynı klasöre gider.") }
            }
            .font(.callout).foregroundStyle(.secondary)
            if let s = k.sonuc, !s.takilan.isEmpty, k.hal == .bitti {
                Akis { ForEach(s.takilan.prefix(24), id: \.self) { KelimeDugmesi(kelime: $0, renk: Renk.sari) } }
            }
            if !t.kayitlar.isEmpty {
                Divider()
                Text("Bu günün kayıtları — iPhone ve Mac").font(.caption).foregroundStyle(.secondary)
                ForEach(t.kayitlar) { r in
                    HStack(spacing: 10) {
                        Image(systemName: r.cihaz == "iphone" ? "iphone" : "laptopcomputer").foregroundStyle(Renk.vurgu).frame(width: 18)
                        Text(r.zaman.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                        if let s = r.sure { Text(String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)).monospacedDigit().foregroundStyle(.secondary) }
                        if let ta = r.tanima { Text("tanınan %\(Int(ta * 100))").foregroundStyle(.secondary) }
                        Spacer()
                        Button { t.ses.dur(); c.cal(r.url) } label: { Image(systemName: c.calan == r.url ? "stop.circle.fill" : "play.circle") }
                            .buttonStyle(.borderless).font(.title3)
                    }
                    .font(.callout)
                }
            }
        }
    }
}

// MARK: - ② Cümle turu

struct CumleEkrani: View {
    @EnvironmentObject var t: Tezgah
    @State private var yazi = ""

    var body: some View {
        if let o = t.o {
            let c = o.cumle(o.i), tr = o.tur(o.i), bitti = tr?.y != nil
            Sutun {
                HStack {
                    Baslik(metin: "② Cümle turu · \(o.i + 1) / \(o.toplam)")
                    Spacer()
                    Button { t.cumleGit(o.i - 1) } label: { Image(systemName: "chevron.left") }.disabled(o.i == 0)
                        .keyboardShortcut("[", modifiers: .command).help("Önceki cümle (⌘[)")
                    Button { t.ileri() } label: { Text(o.i == o.toplam - 1 ? "paragraf turu" : "sıradaki"); Image(systemName: "chevron.right") }
                        .keyboardShortcut("]", modifiers: .command).help("Sıradaki (⌘])")
                }
                Text(bitti ? "Bu cümleyi tamamladın" : "İngilizce yaz").font(.title.bold())
                trKart(o, c, tr, bitti)
                if let y = tr?.y { sonuc(o, c, tr!, y) } else { yazmaAlani(o) }
            }
            .onAppear { yazi = o.taslakI == o.i ? o.taslakCumle : "" }
            .onChange(of: o.i) { _, i in yazi = t.o?.taslakI == i ? (t.o?.taslakCumle ?? "") : "" }
        }
    }

    func trKart(_ o: Oturum, _ c: GunCumle, _ tr: Tur?, _ bitti: Bool) -> some View {
        let lv = min(2, tr?.ipucu ?? 0)
        return Kart {
            if !bitti {
                HStack(spacing: 8) {
                    Button { t.cumleTikla() } label: { Label(t.cumleAcik ? "Gizle" : "Cümle", systemImage: t.cumleAcik ? "eye.slash" : "eye") }
                        .help("⌥E — tam cümleye göz at; bakmak kayda geçer")
                    Button { t.ipucuTikla() } label: { Label(lv == 0 ? "İpucu" : (t.ipucuAcik ? "Gizle" : "İpucu"), systemImage: "lightbulb") }
                        .help("⌥H — ① yapı ② iskelet")
                    if t.ipucuAcik && lv < 2 { Button("+ iskelet") { t.ipucuDaha() }.help("bir ipucu daha: her kelimenin ilk harfi") }
                    Spacer(minLength: 4)
                    HStack(spacing: 3) {
                        ForEach(0..<3) { n in
                            Circle().fill(n < lv && n < 2 ? Renk.sari : (n == 2 && tr?.baktim == true) ? Renk.kirmizi : Color.secondary.opacity(0.25)).frame(width: 7)
                        }
                    }.help("kullanılan yardım: yapı · iskelet · tam cümle")
                }
                .controlSize(.small)
                HStack {
                    Text(iz(tr)).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Toggle("açık kalsın", isOn: $t.ipucuSabit).toggleStyle(.checkbox).font(.caption).controlSize(.small)
                        .help("kapalıyken yazmaya başlayınca göz atma kendiliğinden kapanır")
                }
                Divider()
            }
            HStack(alignment: .firstTextBaseline) {
                Baslik(metin: "Türkçe")
                if let k = c.konu { Cip(metin: k, renk: Renk.vurgu) }
                if tr?.baktim == true { Cip(metin: "bakıldı", renk: Renk.kirmizi) }
                if let n = t.hazirlik.takildi[o.i] { Cip(metin: n > 1 ? "telefonda \(n) kez yineledin" : "telefonda takıldın", renk: Renk.sari, simge: "iphone") }
                Spacer()
                Button { t.ses.soyle(c.en, cumle: o.i) } label: { Image(systemName: "speaker.wave.2") }.buttonStyle(.borderless).help("doğru İngilizcesini dinle")
            }
            Text(c.tr ?? "(bu cümlenin Türkçesi yok)").font(.title2).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            if t.ipucuAcik && !bitti && lv >= 1 {
                let g = c.konu.flatMap { t.gramerMap[$0] }, gt = Sezici.tespit(c.en)
                VStack(alignment: .leading, spacing: 4) {
                    Text(c.konu ?? gt.etiket).bold() + Text(" — " + (g?.ne ?? gt.aciklama))
                    if let g { Text(g.formul).font(.callout.monospaced()).foregroundStyle(.secondary) }
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Renk.sari.opacity(0.1)))
                if lv >= 2 {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Metin.iskelet(c.en)).font(.serif(19)).tracking(1)
                        Text("\(Metin.kelimeler(c.en).count) kelime · her kelimenin ilk harfi").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Renk.sari.opacity(0.1)))
                }
            }
            if t.cumleAcik && !bitti {
                Text(c.en).font(.serif(19)).foregroundStyle(.secondary).padding(.top, 4).transition(.opacity)
            }
        }
    }

    func iz(_ tr: Tur?) -> String {
        guard let tr, tr.y == nil else { return "önce kendin dene" }
        let k = [tr.ipucu >= 1 ? "yapı" : nil, tr.ipucu >= 2 ? "iskelet" : nil, tr.baktim ? "tam cümle" : nil].compactMap { $0 }
        return k.isEmpty ? "önce kendin dene" : "kullanıldı: " + k.joined(separator: " · ")
    }

    func yazmaAlani(_ o: Oturum) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Editor(metin: $yazi, yerTutucu: "İngilizcesini buraya yaz…", boyut: 21, odak: t.editorOdak,
                   gonder: { t.cumleTamamla(yazi) },
                   klavye: { k in
                       switch k { case .ipucu: t.ipucuTikla(); return true; case .cumle: t.cumleTikla(); return true; default: return false }
                   },
                   degisti: { t.yaziyor($0) })
                .frame(minHeight: 110, maxHeight: 180)
                .background(RoundedRectangle(cornerRadius: 12).fill(Renk.kart2))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Renk.vurgu.opacity(0.5), lineWidth: 1.5))
            HStack(spacing: 14) {
                Button("Kontrol et") { t.cumleTamamla(yazi) }.disabled(yazi.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("↩ kontrol et · ⇧↩ alt satır · ⌥H ipucu · ⌥E cümle · ⌘[ ⌘] gezin")
                Spacer()
                let n = Metin.kelimeler(yazi).count
                if n > 0 { Text("\(n) kelime").monospacedDigit() }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    func sonuc(_ o: Oturum, _ c: GunCumle, _ tr: Tur, _ y: CumleYazim) -> some View {
        let f = Metin.fark(c.en, y.metin)
        return Kart {
            HStack {
                Baslik(metin: "Senin yazdığın")
                if tr.baktim { Cip(metin: "bakıldı", renk: Renk.kirmizi) } else if tr.ipucu > 0 { Cip(metin: "ipucu \(min(2, tr.ipucu))", renk: Renk.sari) }
                Spacer()
                Button { t.ses.soyle(c.en, cumle: o.i) } label: { Image(systemName: "speaker.wave.2") }.buttonStyle(.borderless).help("doğrusunu dinle")
            }
            FarkGorunum(fark: f)
            HtSatir(ht: y.ht)
            if !f.tam {
                Baslik(metin: "Doğrusu").padding(.top, 6)
                HStack(alignment: .center, spacing: 14) {
                    Text(c.en).font(.serif(19)).textSelection(.enabled)
                    Spacer()
                    SkorHalka(yuzde: f.yuzde)
                }
                Text("\(f.ayni) / \(f.toplam) kelime tuttu · farkı oku — aynı hata yarın geri gelir.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button { t.ileri() } label: { Text(o.i >= o.toplam - 1 ? "Paragraf turuna geç →" : "Sıradaki cümle →").padding(.horizontal, 8) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: [])
                Button("bu cümleyi tekrar dene") { t.tekrarDene() }.buttonStyle(.borderless)
            }
            .padding(.top, 6)
        }
    }
}

// MARK: - ③ Paragraf turu

struct ParagrafEkrani: View {
    @EnvironmentObject var t: Tezgah
    @State private var yazi = ""
    @State private var hepsi = false
    @State private var soru: Double?

    var body: some View {
        if let o = t.o {
            Sutun {
                Baslik(metin: "③ Paragraf turu")
                Text("Tüm paragrafı hafızandan çevir").font(.title.bold())
                if let p = o.paragraf {
                    let f = Metin.fark(o.asil, p.metin)
                    Kart {
                        HStack { Baslik(metin: "Paragraf farkı"); Spacer(); SkorHalka(yuzde: f.yuzde) }
                        FarkGorunum(fark: f, boyut: 17)
                        HtSatir(ht: p.ht)
                        Button { t.recallBasla() } label: { Text("Hatırlama testine geç →").padding(.horizontal, 8) }
                            .buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: [])
                    }
                } else {
                    Text("Yalnız üzerinde olduğun cümle açık — gerisi kapalı ki yerini kaybetme. Nokta koyduğunda odak kendiliğinden ilerler.")
                        .foregroundStyle(.secondary)
                    Kart {
                        HStack {
                            Baslik(metin: "Türkçe paragraf · \(o.paraOdak + 1) / \(o.toplam)")
                            Spacer()
                            Button { t.o?.paraOdak = max(0, o.paraOdak - 1) } label: { Image(systemName: "chevron.up") }.disabled(o.paraOdak == 0)
                            Button { t.o?.paraOdak = min(o.toplam - 1, o.paraOdak + 1) } label: { Image(systemName: "chevron.down") }.disabled(o.paraOdak >= o.toplam - 1)
                            Button { t.ses.soyle(o.cumle(o.paraOdak).en) } label: { Image(systemName: "speaker.wave.2") }.help("bu cümlenin İngilizcesini dinle")
                            Toggle("hepsini göster", isOn: $hepsi).toggleStyle(.checkbox).font(.caption)
                        }
                        .controlSize(.small)
                        // sabit yükseklik: yazma alanı ekranda kalsın; odak satırı kendiliğinden ortalanır
                        ScrollViewReader { sv in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(0..<o.toplam, id: \.self) { i in
                                        let odak = i == o.paraOdak
                                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                                            Text("\(i + 1)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary).frame(width: 18)
                                            Text(o.cumle(i).tr ?? o.cumle(i).en)
                                                .font(odak ? .title3 : .callout)
                                                .foregroundStyle(odak ? .primary : i < o.paraOdak ? .tertiary : .secondary)
                                                .blur(radius: odak || hepsi ? 0 : 4)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .id(i)
                                        .contentShape(Rectangle())
                                        .onTapGesture { t.o?.paraOdak = i }
                                    }
                                }
                            }
                            .frame(height: hepsi ? 300 : 150)
                            .onAppear { sv.scrollTo(o.paraOdak, anchor: .center) }
                            .onChange(of: o.paraOdak) { _, i in withAnimation { sv.scrollTo(i, anchor: .center) } }
                        }
                    }
                    Editor(metin: $yazi, yerTutucu: "Tüm paragrafın İngilizcesini yaz…", boyut: 19, odak: t.editorOdak,
                           gonder: nil,
                           klavye: { k in
                               switch k {
                               case .yukari: t.o?.paraOdak = max(0, o.paraOdak - 1); return true
                               case .asagi: t.o?.paraOdak = min(o.toplam - 1, o.paraOdak + 1); return true
                               default: return false
                               }
                           },
                           degisti: { t.paraYaziyor($0) })
                        .frame(minHeight: 220)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Renk.kart2))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Renk.vurgu.opacity(0.5), lineWidth: 1.5))
                    HStack {
                        Button { bitir(false) } label: { Text("Karşılaştır").padding(.horizontal, 8) }
                            .buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command)
                        Text("⌘↩ karşılaştır · ↩ alt satır · ⌥↑/↓ odak").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        let n = Metin.kelimeler(yazi).count
                        if n > 0 { Text("\(n) kelime").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                    }
                }
            }
            .onAppear { yazi = o.taslakParagraf }
            .alert("Paragrafın yalnız ~%\(Int((soru ?? 0) * 100))'i kadar yazdın", isPresented: Binding(get: { soru != nil }, set: { if !$0 { soru = nil } })) {
                Button("Devam et", role: .cancel) { soru = nil }
                Button("Yine de bitir") { soru = nil; bitir(true) }
            } message: { Text("Bitirirsen fark yazdığın kadarıyla hesaplanır.") }
        }
    }
    func bitir(_ zorla: Bool) { if let r = t.paragrafBitir(yazi, zorla: zorla) { soru = r } }
}

/// Komutların ve init'te ortam nesnesine erişemeyen görünümlerin ulaştığı tek Tezgâh.
enum TezgahKok { @MainActor static let t = Tezgah() }
