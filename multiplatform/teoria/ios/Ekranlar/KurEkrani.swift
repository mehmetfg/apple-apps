// Kür — günlük oturum. Süreyle biter, desteyle değil. Yarım kür yok: en az bir kart yapıldıysa kür sayılır.
// Akış: son okuduğun günün işaretleri → vadesi gelen tekrarlar → kademendeki iş → bir esneme kartı (+1) → kolay kapanış → özet.
// Her kartta önce "ne kadar eminsin?" (tek dokunuş), sonra cevap. Hata kırmızı değil; doğru cevap yumuşakça gösterilir.
import SwiftUI

struct KurEkrani: View {
    @EnvironmentObject var depo: Depo
    let dakika: Int
    var kapat: () -> Void

    @Environment(\.scenePhase) private var faz
    @State private var plan: KurPlani?
    @State private var sira = 0
    @State private var kapanista = false
    @State private var ozet = false
    @State private var kurId = UUID().uuidString
    @State private var baslangic = Date()
    @State private var duraklama: TimeInterval = 0
    @State private var arkaPlan: Date?
    @State private var kartBasi = Date()
    @State private var yapilan: [Olay] = []
    @State private var oncekiKademe: [Hat: Int] = [:]

    // Kart durumu
    @State private var guven: Int?
    @State private var ipucu = 0
    @State private var secilen: String?
    @State private var yazi = ""
    @State private var dizilen: [String] = []
    @State private var puan: Double?
    @State private var esleme: Dil.Esleme?
    @State private var karsilastir = false
    @State private var oneri: Double = 0
    @FocusState private var odak: Bool

    // Haptik tetikleri
    @State private var dogruT = 0
    @State private var yanlisT = 0
    @State private var secimT = 0
    @State private var kademeT = 0

    var kart: Alistirma? {
        guard let p = plan else { return nil }
        if kapanista { return p.kapanis }
        return sira < p.alistirmalar.count ? p.alistirmalar[sira] : nil
    }

    /// Kürün ilk kartında, bu hattın neye yaradığı: sebebi bilinen iş sürdürülür.
    static func fayda(_ h: Hat) -> String {
        switch h {
        case .hatirla: "Okuduğun, hafta sonra da elinde kalsın diye: unutmaya yaklaşanı tam zamanında yokluyorum."
        case .donustur: "Gündelik düşünceyi kavramla söyleyebilmen için: aynı fikir, daha keskin cümle."
        case .kur: "Fikrini kendi cümlenle kurabilmen için: yazarken takılmanın ilacı bu."
        }
    }

    var gecen: TimeInterval { Date().timeIntervalSince(baslangic) - duraklama }

    var body: some View {
        ZStack {
            Tema.arka.ignoresSafeArea()
            if ozet {
                KurOzetEkrani(kurId: kurId, yapilan: yapilan, oncekiKademe: oncekiKademe, kapat: kapat)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else if let k = kart {
                VStack(spacing: 0) {
                    ustBar
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if plan?.hosgeldin == true && sira == 0 && !kapanista {
                                Label("Hoş geldin. Bugün bir kademe hafif başlıyoruz.", systemImage: "sun.horizon")
                                    .font(.subheadline.weight(.medium)).foregroundStyle(Tema.altin)
                            }
                            if sira == 0 && !kapanista && puan == nil {
                                Label(Self.fayda(k.hat), systemImage: "target")
                                    .font(.footnote).foregroundStyle(Tema.ikincil)
                            }
                            kartBasligi(k)
                            soruAlani(k)
                            if guven == nil && puan == nil { guvenAlani } else { cevapAlani(k) }
                            if let p = puan, !(k.tip == .yaz && !karsilastir) { geriBildirim(k, p) }
                        }
                        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 140)
                        .frame(maxWidth: 680)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
                .id(k.id)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
                .safeAreaInset(edge: .bottom) { altEylem(k) }
            } else {
                ProgressView().onAppear(perform: hazirla)
            }
        }
        .dokun(.success, dogruT)
        .dokun(.warning, yanlisT)
        .dokun(.selection, secimT)
        .onChange(of: faz) { _, yeni in
            if yeni == .background || yeni == .inactive {
                if arkaPlan == nil { arkaPlan = Date() }
            } else if yeni == .active, let a = arkaPlan {
                let ara = Date().timeIntervalSince(a)
                duraklama += ara
                arkaPlan = nil
                // 10 dakikadan uzun ara: kür yapılan kadarıyla kapanır (yarım değil, tamam).
                if ara > 600 && !yapilan.isEmpty && !ozet { bitir() }
            }
        }
    }

    // MARK: Üst bar

    private var ustBar: some View {
        HStack(spacing: 14) {
            Button {
                if yapilan.isEmpty { kapat() } else { bitir() }
            } label: {
                Image(systemName: yapilan.isEmpty ? "xmark" : "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Tema.yuzey2))
                    .foregroundStyle(Tema.ikincil)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(yapilan.isEmpty ? "Kapat" : "Kürü bitir")
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let oran = min(gecen / Double(dakika * 60), 1)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Tema.yuzey2)
                        Capsule().fill(LinearGradient(colors: [Tema.vurgu.opacity(0.7), Tema.vurgu], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(8, g.size.width * oran))
                            .animation(.linear(duration: 1), value: oran)
                    }
                }
                .frame(height: 8)
                .accessibilityLabel("Süre: \(Int(gecen / 60)) dakika geçti, \(dakika) dakikalık kür")
            }
            Text("\(yapilan.count)")
                .font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(Tema.ikincil)
                .frame(minWidth: 28)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    // MARK: Kart

    private func kartBasligi(_ k: Alistirma) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Hap(metin: k.hat.ad, renk: Tema.hat(k.hat))
                Text("K\(k.kademe) · \(Evre.of(k.kademe).rawValue)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Tema.soluk)
                if k.rol == "esneme" { Hap(metin: "+1 esneme", renk: Tema.altin) }
                if k.rol == "isinma" { Hap(metin: "ısınma", renk: Tema.ikincil) }
                if k.rol == "songun" { Hap(metin: "son gün", renk: Tema.vurgu, dolu: true) }
                if k.rol == "tekrar" { Hap(metin: "aralıklı tekrar", renk: Tema.hat(.hatirla)) }
                if k.rol == "kapanis" { Hap(metin: "son kart", renk: Tema.basari) }
                Spacer()
            }
            Text(k.baslik).font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.ikincil)
            if !k.kaynak.isEmpty {
                Text(k.kaynak).font(.system(size: 12)).foregroundStyle(Tema.renk(depo.paket.kitap(k.kitap)?.renk))
            }
        }
    }

    private func soruAlani(_ k: Alistirma) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let b = k.baglam {
                Text(b)
                    .font(Tema.serif(k.tip == .yaz && k.kademe >= 5 ? .title3 : .title2))
                    .foregroundStyle(Tema.metin)
                    .lineSpacing(3)
                    .padding(18)
                    .tamGenislik()
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Tema.yuzey))
                    .textSelection(.enabled)
            }
            Text(k.soru)
                .font(k.baglam == nil ? Tema.serif(.title, .medium) : .system(.title3, weight: .semibold))
                .foregroundStyle(Tema.metin)
                .fixedSize(horizontal: false, vertical: true)
            if ipucu > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(k.ipuclari.prefix(ipucu).enumerated()), id: \.offset) { _, i in
                        Label(i, systemImage: "lightbulb").font(.callout).foregroundStyle(Tema.altin)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var guvenAlani: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Önce zihninde cevapla. Ne kadar eminsin?").font(.subheadline).foregroundStyle(Tema.ikincil)
            HStack(spacing: 8) {
                ForEach([(1, "Emin değilim"), (2, "Biraz"), (3, "Eminim")], id: \.0) { g in
                    Button {
                        secimT += 1
                        withAnimation(.spring(response: 0.35)) { guven = g.0 }
                        if kart?.tip == .yaz || kart?.tip == .bosluk { odak = true }
                    } label: { Text(g.1) }
                    .buttonStyle(IkinciDugme(renk: Tema.vurgu))
                }
            }
        }
    }

    @ViewBuilder
    private func cevapAlani(_ k: Alistirma) -> some View {
        switch k.tip {
        case .sec: secenekler(k)
        case .diz: diz(k)
        case .bosluk: bosluk(k)
        case .yaz: yaz(k)
        }
    }

    private func secenekler(_ k: Alistirma) -> some View {
        VStack(spacing: 10) {
            ForEach(k.secenekler, id: \.self) { s in
                let sec = secilen == s, dogru = s == k.dogru
                Button {
                    guard puan == nil else { return }
                    secilen = s
                    sonuclandir(k, Olcum.sec(s, k))
                } label: {
                    HStack(alignment: .top) {
                        Text(s).font(k.secenekler.map(\.count).max() ?? 0 > 40 ? .body : Tema.serif(.title3))
                            .multilineTextAlignment(.leading).foregroundStyle(Tema.metin)
                        Spacer(minLength: 8)
                        if puan != nil && dogru { Image(systemName: "checkmark.circle.fill").foregroundStyle(Tema.basari) }
                        else if puan != nil && sec { Image(systemName: "arrow.uturn.left.circle").foregroundStyle(Tema.uyari) }
                    }
                    .padding(16)
                    .tamGenislik()
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(puan != nil && dogru ? Tema.basari.opacity(0.12) : (puan != nil && sec ? Tema.uyari.opacity(0.10) : Tema.yuzey)))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(puan != nil && dogru ? Tema.basari.opacity(0.5) : Tema.cizgi, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(puan != nil)
            }
        }
    }

    private func diz(_ k: Alistirma) -> some View {
        let havuz = k.secenekler.filter { s in dizilen.filter { $0 == s }.count < k.secenekler.filter { $0 == s }.count }
        return VStack(alignment: .leading, spacing: 14) {
            // Kurulan cümle
            AkanYerlesim(aralik: 8) {
                ForEach(Array(dizilen.enumerated()), id: \.offset) { i, p in
                    Button { if puan == nil { secimT += 1; dizilen.remove(at: i) } } label: {
                        Text(p).font(Tema.serif(.body)).padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(Tema.vurgu.opacity(0.14))).foregroundStyle(Tema.metin)
                    }.buttonStyle(.plain)
                }
            }
            .frame(minHeight: 50, alignment: .topLeading)
            .padding(12).tamGenislik()
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Tema.cizgi, style: StrokeStyle(lineWidth: 1, dash: [5])))
            AkanYerlesim(aralik: 8) {
                ForEach(Array(havuz.enumerated()), id: \.offset) { _, p in
                    Button { secimT += 1; withAnimation(.snappy) { dizilen.append(p) } } label: {
                        Text(p).font(Tema.serif(.body)).padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(Tema.yuzey)).overlay(Capsule().strokeBorder(Tema.cizgi))
                            .foregroundStyle(Tema.metin)
                    }.buttonStyle(.plain).disabled(puan != nil)
                }
            }
        }
    }

    private func bosluk(_ k: Alistirma) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Cevabın", text: $yazi)
                .font(Tema.serif(.title2))
                .textFieldStyle(.plain)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Tema.yuzey))
                .focused($odak)
                .autocorrectionDisabled()
                .disabled(puan != nil)
                .onSubmit { if puan == nil && !yazi.isEmpty { kontrolEt(k) } }
            if let e = esleme, e == .yakin {
                Label("Neredeyse — yazım farkı: \(k.dogru)", systemImage: "checkmark.seal").font(.callout).foregroundStyle(Tema.basari)
            }
        }
    }

    private func yaz(_ k: Alistirma) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                if yazi.isEmpty {
                    Text(k.kademe >= 5 ? "Kendi cümlen…" : "Hatırladığını yaz…").font(Tema.serif(.title3)).foregroundStyle(Tema.soluk)
                        .padding(.horizontal, 5).padding(.vertical, 8)
                }
                TextEditor(text: $yazi)
                    .font(Tema.serif(.title3))
                    .scrollContentBackground(.hidden)
                    .focused($odak)
                    .frame(minHeight: k.kademe >= 5 ? 170 : 120)
                    .disabled(karsilastir)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Tema.yuzey))
            if karsilastir {
                VStack(alignment: .leading, spacing: 10) {
                    Bolumbasi(metin: k.kademe >= 5 ? "Bir örnek ses" : "Kaynak", sembol: "text.quote", renk: Tema.basari)
                    Text(k.model).font(Tema.serif(.title3)).foregroundStyle(Tema.metin).textSelection(.enabled)
                    if !k.anahtar.isEmpty {
                        let b = Dil.kapsam(yazi, k.anahtar).bulunan
                        AkanYerlesim(aralik: 6) {
                            ForEach(k.anahtar, id: \.self) { a in
                                Hap(metin: (b.contains(a) ? "✓ " : "") + a, renk: b.contains(a) ? Tema.basari : Tema.soluk)
                            }
                        }
                    }
                    if let a = k.aciklama { Text(a).font(.callout).foregroundStyle(Tema.ikincil) }
                }
                .padding(16).tamGenislik()
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Tema.basari.opacity(0.07)))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    private func geriBildirim(_ k: Alistirma, _ p: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if p >= 0.7 {
                Label(p >= 1 ? "Kendi zihninden." : "Yakaladın.", systemImage: "sparkle")
                    .font(.headline).foregroundStyle(Tema.basari)
            } else {
                Label("Şimdi gördün; bir dahakine kendin çağıracaksın.", systemImage: "arrow.uturn.forward")
                    .font(.headline).foregroundStyle(Tema.uyari)
                if k.tip != .yaz { Text(k.model).font(Tema.serif(.title3)).foregroundStyle(Tema.metin) }
            }
            if let a = k.aciklama, k.tip != .yaz { Text(a).font(.callout).foregroundStyle(Tema.ikincil) }
        }
        .padding(16).tamGenislik()
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill((p >= 0.7 ? Tema.basari : Tema.uyari).opacity(0.08)))
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    // MARK: Alt eylem (başparmak bölgesi)

    @ViewBuilder
    private func altEylem(_ k: Alistirma) -> some View {
        VStack(spacing: 10) {
            if puan != nil && k.tip != .yaz {
                Button("Devam") { ilerle() }.buttonStyle(AnaDugme())
                    .keyboardShortcut(.defaultAction)
            } else if guven != nil {
                switch k.tip {
                case .sec:
                    ipucuDugmesi(k)
                case .diz:
                    HStack(spacing: 10) {
                        Button("Temizle") { dizilen = [] }.buttonStyle(IkinciDugme(renk: Tema.ikincil))
                        Button("Kontrol et") { sonuclandir(k, Olcum.diz(dizilen, k)) }
                            .buttonStyle(AnaDugme()).disabled(dizilen.count < k.parcalar.count)
                    }
                case .bosluk:
                    HStack(spacing: 10) {
                        ipucuDugmesi(k)
                        Button("Kontrol et") { kontrolEt(k) }.buttonStyle(AnaDugme()).disabled(yazi.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                case .yaz:
                    if karsilastir {
                        ozDegerlendirme(k)
                    } else {
                        HStack(spacing: 10) {
                            ipucuDugmesi(k)
                            Button("Kaynakla karşılaştır") {
                                odak = false
                                oneri = Olcum.oneri(yazi, k)
                                withAnimation(.spring(response: 0.4)) { karsilastir = true }
                            }
                            .buttonStyle(AnaDugme())
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, guven == nil && puan == nil ? 0 : 10).padding(.bottom, 8)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
        .background { if guven != nil || puan != nil { Rectangle().fill(.bar).ignoresSafeArea() } }
    }

    @ViewBuilder
    private func ipucuDugmesi(_ k: Alistirma) -> some View {
        if ipucu < k.ipuclari.count && puan == nil {
            Button {
                Dokunus.hafif(0.5)
                withAnimation(.snappy) { ipucu += 1 }
            } label: { Label("İpucu \(ipucu + 1)/\(k.ipuclari.count)", systemImage: "lightbulb") }
            .buttonStyle(IkinciDugme(renk: Tema.altin))
        }
    }

    private func ozDegerlendirme(_ k: Alistirma) -> some View {
        VStack(spacing: 8) {
            Text("Kendi cevabını kaynakla karşılaştır ve dürüstçe işaretle.")
                .font(.footnote).foregroundStyle(Tema.ikincil)
            HStack(spacing: 8) {
                ForEach([(0.0, "Kaçırdım"), (0.5, "Kısmen"), (0.85, "Yakaladım"), (1.0, "Tam")], id: \.0) { s in
                    Button {
                        sonuclandir(k, s.0)
                        ilerle()
                    } label: {
                        Text(s.1).font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(Capsule().fill(oneri == s.0 ? Tema.vurgu : Tema.vurgu.opacity(0.12)))
                            .foregroundStyle(oneri == s.0 ? Color.white : Tema.vurgu)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Akış

    private func hazirla() {
        oncekiKademe = Dictionary(uniqueKeysWithValues: Hat.allCases.map { ($0, depo.durum.kademe($0)) })
        plan = Kurgu.plan(depo.paket, depo.durum, dakika: dakika, akis: depo.akis.isaretler)
        baslangic = Date()
        kartBasi = Date()
        if plan?.alistirmalar.isEmpty ?? true { kapanista = true }
    }

    private func kontrolEt(_ k: Alistirma) {
        let (p, e) = Olcum.bosluk(yazi, k, ipucu: ipucu)
        esleme = e
        odak = false
        sonuclandir(k, p)
    }

    private func sonuclandir(_ k: Alistirma, _ p: Double) {
        guard puan == nil else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { puan = p }
        if p >= 0.7 { dogruT += 1 } else { yanlisT += 1 }
        let n = Olcum.not(p, guven: guven)
        let o = Olay(tur: .cevap, hedef: k.kartAnahtari, hat: k.hat, kademe: k.kademe, puan: p, guven: guven,
                     not: n.rawValue, metin: k.tip == .yaz || k.tip == .bosluk ? yazi : nil,
                     sure: Date().timeIntervalSince(kartBasi), kurId: kurId, rol: k.rol)
        yapilan.append(o)
        depo.ekle(o)
    }

    private func ilerle() {
        guard let p = plan else { return }
        let sureBitti = gecen >= Double(dakika * 60)
        let sonraki = sira + 1
        Dokunus.sayfa()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            sifirla()
            if kapanista {
                bitir()
            } else if sureBitti || sonraki >= p.alistirmalar.count {
                if p.kapanis != nil { kapanista = true } else { bitir() }
            } else {
                sira = sonraki
            }
        }
    }

    private func sifirla() {
        guven = nil; ipucu = 0; secilen = nil; yazi = ""; dizilen = []; puan = nil; esleme = nil
        karsilastir = false; oneri = 0; kartBasi = Date()
    }

    private func bitir() {
        guard !ozet else { return }
        if !yapilan.isEmpty {
            depo.ekle(Olay(tur: .kur, sure: min(gecen, 20 * 60), kurId: kurId))
        }
        withAnimation(.spring(response: 0.5)) { ozet = true }
        if Hat.allCases.contains(where: { depo.durum.kademe($0) > (oncekiKademe[$0] ?? 1) }) {
            Dokunus.kademeAtladi()
        } else if !yapilan.isEmpty {
            Dokunus.basari()
        }
    }
}

// MARK: - Özet

struct KurOzetEkrani: View {
    @EnvironmentObject var depo: Depo
    let kurId: String
    let yapilan: [Olay]
    let oncekiKademe: [Hat: Int]
    var kapat: () -> Void
    @State private var halka: Double = 0
    @State private var parca = false

    var ozet: KurOzeti? { depo.durum.kurlar.first { $0.id == kurId } }

    var body: some View {
        VStack(spacing: 26) {
            Spacer()
            ZStack {
                Halka(oran: halka, renk: Tema.basari, kalinlik: 14).frame(width: 180, height: 180)
                VStack(spacing: 2) {
                    Image(systemName: "checkmark").font(.system(size: 44, weight: .bold)).foregroundStyle(Tema.basari)
                        .scaleEffect(parca ? 1 : 0.4).opacity(parca ? 1 : 0)
                    Text(yapilan.isEmpty ? "" : "\(yapilan.count) kart").font(.subheadline.weight(.semibold)).foregroundStyle(Tema.ikincil)
                }
                if parca { Pirilti().frame(width: 280, height: 280).allowsHitTesting(false) }
            }
            VStack(spacing: 10) {
                Text("Kür tamam").font(Tema.serif(.largeTitle, .semibold)).foregroundStyle(Tema.metin)
                Text(ozet?.kazanc ?? Durum.kazanc(yapilan))
                    .font(Tema.serif(.title3)).multilineTextAlignment(.center).foregroundStyle(Tema.ikincil)
                    .padding(.horizontal, 30)
            }
            ForEach(Hat.allCases) { h in
                let simdi = depo.durum.kademe(h), once = oncekiKademe[h] ?? simdi
                if simdi > once {
                    Label("\(h.ad) K\(simdi)'ya çıktı · \(Evre.of(simdi).rawValue)", systemImage: "arrow.up.circle.fill")
                        .font(.headline).foregroundStyle(Tema.hat(h))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().fill(Tema.hat(h).opacity(0.12)))
                }
            }
            Text("Bu hafta \(depo.durum.buHaftaKur) kür.").font(.footnote).foregroundStyle(Tema.soluk)
            Spacer()
            Button("Tamam", action: kapat).buttonStyle(AnaDugme(renk: Tema.basari)).padding(.horizontal, 24)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.bottom, 20)
        .onAppear {
            withAnimation(.easeOut(duration: 1.1)) { halka = 1 }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.7)) { parca = true }
        }
        .dokun(.success, parca)
    }
}

/// Kür sonunda halkanın etrafında açılan altın kıvılcımlar.
struct Pirilti: View {
    @State private var t = false
    var body: some View {
        ZStack {
            ForEach(0..<14, id: \.self) { i in
                let aci = Double(i) / 14 * 2 * .pi
                Image(systemName: i % 3 == 0 ? "sparkle" : "circle.fill")
                    .font(.system(size: i % 3 == 0 ? 14 : 5))
                    .foregroundStyle(i % 2 == 0 ? Tema.altin : Tema.basari)
                    .offset(x: CGFloat(cos(aci)) * (t ? 130 : 70), y: CGFloat(sin(aci)) * (t ? 130 : 70))
                    .opacity(t ? 0 : 1)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 1.2)) { t = true } }
    }
}

// MARK: - Akan yerleşim (etiket bulutu)

struct AkanYerlesim: Layout {
    var aralik: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let gen = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, satir: CGFloat = 0
        for s in subviews {
            let b = s.sizeThatFits(.unspecified)
            if x + b.width > gen && x > 0 { x = 0; y += satir + aralik; satir = 0 }
            x += b.width + aralik
            satir = max(satir, b.height)
        }
        return CGSize(width: gen, height: y + satir)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, satir: CGFloat = 0
        for s in subviews {
            let b = s.sizeThatFits(.unspecified)
            if x + b.width > bounds.maxX && x > bounds.minX { x = bounds.minX; y += satir + aralik; satir = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(b))
            x += b.width + aralik
            satir = max(satir, b.height)
        }
    }
}
