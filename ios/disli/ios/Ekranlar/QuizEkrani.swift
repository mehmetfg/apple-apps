// Mini quiz: 4-5 soru, tek tek. Soru kipi konunun kademesinden gelir (Depo.kip):
//   seç (şık) · bul (hatalı kelimeye dokun) · diz (taşla kur) · yaz (klavyeyle).
// Yanlışta cevap değil önce doğrusu ve "neden"i gösterilir; konu oturum sayısına bağlı olarak yakında yine gelir.
import SwiftUI

struct QuizEkrani: View {
    @Environment(Depo.self) private var depo
    @Environment(\.dismiss) private var kapat
    let ogeler: [QuizOgesi]
    let gunluk: Bool
    @State private var i = 0
    @State private var sonuclar: [Bool] = []
    @State private var bitti = false

    var body: some View {
        VStack(spacing: 0) {
            if let o = ogeler[safe: i], !bitti {
                OyunUstu(baslik: gunluk ? "Mini quiz" : "Soru", alt: o.konu.tr, renk: depo.renk(o.konu),
                         ilerleme: Double(i) / Double(max(1, ogeler.count))) { kapat() }
                SoruGorunum(oge: o) { dogru, kip in
                    depo.kaydet(konu: o.konu.id, kip: kip, dogru: dogru)
                    sonuclar.append(dogru)
                } devam: {
                    withAnimation(.snappy) {
                        if i + 1 < ogeler.count { i += 1 } else { bitir() }
                    }
                }
                .id(o.id)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
            } else {
                ozet
            }
        }
        .background(Lekeler(renkler: [depo.renk(ogeler.first?.konu ?? depo.veri.konular[0]), Tema.vurgu, Tema.renk("turkuaz")]))
        .overlay { if bitti && sonuclar.filter({ $0 }).count >= max(1, ogeler.count - 1) { Konfeti() } }
    }

    private func bitir() {
        bitti = true
        if gunluk {
            depo.oturumuKapat(sunulanlar: ogeler.map(\.konu.id))
            depo.bitti("quiz")
        }
        Dokunus.basari()
    }

    private var ozet: some View {
        let d = sonuclar.filter { $0 }.count
        return ScrollView {
            VStack(spacing: 18) {
                Spacer(minLength: 30)
                Text("\(d) / \(ogeler.count)").font(.system(size: 64, weight: .heavy, design: .rounded))
                    .foregroundStyle(Tema.egim)
                Text(d == ogeler.count ? "Hepsi yerine oturdu." : d >= ogeler.count - 1 ? "Neredeyse kusursuz." : "Takıldıkların birkaç oturum sonra yine gelecek.")
                    .font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                VStack(spacing: 10) {
                    ForEach(Array(ogeler.enumerated()), id: \.offset) { n, o in
                        HStack(spacing: 12) {
                            Image(systemName: sonuclar[safe: n] == true ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath.circle.fill")
                                .foregroundStyle(sonuclar[safe: n] == true ? Tema.dogru : Tema.renk("turuncu")).font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(o.konu.tr).font(.subheadline.weight(.semibold))
                                Text(kipAdi(o.kip)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            KademeHalkasi(kademe: depo.kademe(o.konu.id), renk: depo.renk(o.konu), boy: 26)
                        }
                        .kart(12, yaricap: 16)
                    }
                }
                Text("Halka dört dilimdir: gördüm · taklit · üretim · özerk. Tanıma üç kez tutunca o konuya artık şık gelmez, yalnız kurarsın.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                Button { kapat() } label: {
                    Text("Bitti").font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 52)
                        .background(Capsule().fill(Tema.egim))
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
    }

    private func kipAdi(_ k: SoruKipi) -> String {
        switch k { case .sec: "tanıma · seç"; case .bul: "tanıma · hatayı bul"; case .diz: "kurma · taşla"; case .yaz: "kurma · yaz" }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// MARK: - Tek soru

struct SoruGorunum: View {
    @Environment(Depo.self) private var depo
    let oge: QuizOgesi
    let cevaplandi: (Bool, SoruKipi) -> Void
    let devam: () -> Void

    @State private var sonuc: Bool?
    @State private var secilen: String?
    @State private var secenekler: [String] = []
    @State private var dokunulan: Int?
    @State private var dizi: [Tas] = []
    @State private var banka: [Tas] = []
    @State private var yazi = ""
    @State private var ipucu = false
    @State private var sallan = 0
    @FocusState private var odak: Bool

    private var s: Soru { oge.soru }
    private var renk: Color { depo.renk(oge.konu) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(yonerge).font(.subheadline.weight(.semibold)).foregroundStyle(renk).padding(.top, 18)
                    govde
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            if let sonuc { geriBildirim(sonuc).transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .onAppear(perform: hazirla)
        .modifier(Salla(adim: CGFloat(sallan)))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: sonuc)
    }

    private var yonerge: String {
        switch oge.kip {
        case .sec: "Boşluğa hangisi gelir?"
        case .bul: "Bu cümlede bir hata var. Hatalı kelimeye dokun."
        case .diz: s.tur == .sirala ? "Taşları dizip cümleyi kur." : s.tur == .donustur ? (s.talimat ?? "Dönüştür") : "Boşluğu taşlarla doldur."
        case .yaz: s.tur == .donustur ? (s.talimat ?? "Dönüştür") + " — yaz" : "Boşluğu yaz."
        }
    }

    // MARK: Gövde

    @ViewBuilder
    private var govde: some View {
        switch oge.kip {
        case .sec: secGovde
        case .bul: bulGovde
        case .diz: dizGovde
        case .yaz: yazGovde
        }
    }

    private var secGovde: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(bosluklu(s.s ?? "", dolgu: secilen.map { [$0] } ?? [])).font(Tema.ingilizce(.title2)).fixedSize(horizontal: false, vertical: true)
                .kart(18)
            ForEach(secenekler, id: \.self) { x in
                Button {
                    guard sonuc == nil else { return }
                    secilen = x
                    cevapla((s.cevaplar ?? []).contains { Metin.esit($0, x) })
                } label: {
                    HStack {
                        Text(x).font(Tema.ingilizce(.title3, .medium))
                        Spacer()
                        if sonuc != nil && (s.cevaplar ?? []).contains(where: { Metin.esit($0, x) }) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Tema.dogru)
                        } else if sonuc == false && secilen == x {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Tema.yanlis)
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(secenekZemini(x)))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(renk.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func secenekZemini(_ x: String) -> Color {
        guard sonuc != nil else { return Tema.yuzey }
        if (s.cevaplar ?? []).contains(where: { Metin.esit($0, x) }) { return Tema.dogru.opacity(0.15) }
        if secilen == x { return Tema.yanlis.opacity(0.15) }
        return Tema.yuzey
    }

    private var bulGovde: some View {
        let kelimeler = (s.yanlis ?? "").split(separator: " ").map(String.init)
        let hedef = Set(s.hataKelime ?? [])
        return VStack(alignment: .leading, spacing: 18) {
            Akis(aralik: 8, satirAraligi: 10) {
                ForEach(Array(kelimeler.enumerated()), id: \.offset) { n, w in
                    Button {
                        guard sonuc == nil else { return }
                        dokunulan = n
                        cevapla(hedef.contains(n))
                    } label: {
                        Text(w).font(Tema.ingilizce(.title3, .medium))
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(kelimeZemini(n, hedef)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
            .kart(18)
        }
    }

    private func kelimeZemini(_ n: Int, _ hedef: Set<Int>) -> Color {
        if sonuc != nil && hedef.contains(n) { return Tema.yanlis.opacity(0.18) }
        if dokunulan == n { return sonuc == true ? Tema.dogru.opacity(0.2) : Color(.tertiarySystemFill) }
        return Color(.tertiarySystemFill).opacity(0.6)
    }

    @ViewBuilder
    private var dizGovde: some View {
        VStack(alignment: .leading, spacing: 18) {
            if s.tur == .donustur, let k = s.kaynak {
                Text(k).font(Tema.ingilizce(.title3)).foregroundStyle(.secondary).kart(16)
            }
            if s.tur == .bosluk {
                Text(bosluklu(s.s ?? "", dolgu: bosluguDoldur())).font(Tema.ingilizce(.title2)).fixedSize(horizontal: false, vertical: true)
                    .kart(18)
                TasTezgahi(dizi: $dizi, banka: $banka, renk: renk, kilitli: sonuc != nil)
            } else {
                TasTezgahi(dizi: $dizi, banka: $banka, renk: renk, kilitli: sonuc != nil)
            }
            if sonuc == nil {
                HStack {
                    Button("Temizle") { withAnimation { banka += dizi; dizi = [] } }
                        .disabled(dizi.isEmpty)
                    Spacer()
                    Button("Kontrol et") { kontrolDiz() }
                        .buttonStyle(.borderedProminent).tint(renk)
                        .disabled(dizi.isEmpty)
                }
            }
        }
        .onChange(of: dizi) { _, d in
            if sonuc == nil, d.count == (s.tas?.count ?? -1) { kontrolDiz() }
        }
    }

    private var yazGovde: some View {
        VStack(alignment: .leading, spacing: 18) {
            if s.tur == .donustur, let k = s.kaynak {
                Text(k).font(Tema.ingilizce(.title3)).foregroundStyle(.secondary).kart(16)
            } else {
                Text(bosluklu(s.s ?? "", dolgu: [])).font(Tema.ingilizce(.title2)).fixedSize(horizontal: false, vertical: true).kart(18)
            }
            TextField(s.tur == .donustur ? "Cümleyi yaz" : "Boşluğa gelen", text: $yazi, axis: .vertical)
                .font(Tema.ingilizce(.title3))
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($odak)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Tema.yuzey))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(renk.opacity(0.4), lineWidth: 1.2))
                .disabled(sonuc != nil)
                .onSubmit(kontrolYaz)
            if ipucu, let c = s.cevaplar?.first {
                Text(ilkHarfler(c)).font(.system(.title3, design: .monospaced)).foregroundStyle(renk)
                    .transition(.opacity)
            }
            if sonuc == nil {
                HStack {
                    Button(ipucu ? "İpucu açık" : "İlk harfleri göster") { withAnimation { ipucu = true } }.disabled(ipucu)
                    Spacer()
                    Button("Kontrol et", action: kontrolYaz).buttonStyle(.borderedProminent).tint(renk)
                        .disabled(yazi.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { odak = true } }
    }

    // MARK: Geri bildirim

    private func geriBildirim(_ dogru: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: dogru ? "checkmark.seal.fill" : "lightbulb.fill").font(.title2)
                Text(dogru ? ["Oturdu!", "Tam isabet", "Yerine oturdu"].randomElement()! : "Doğrusu şöyle").font(.title3.weight(.bold))
                Spacer()
                Button { Ses.konus(dogruCumle) } label: { Image(systemName: "speaker.wave.2.fill").font(.title3) }
                    .buttonStyle(.plain)
            }
            .foregroundStyle(dogru ? Tema.dogru : Tema.renk("turuncu"))
            Text(dogruCumle).font(Tema.ingilizce(.title3, .semibold)).fixedSize(horizontal: false, vertical: true)
            if !dogru {
                FormulMetni(formul: oge.konu.formul, font: .system(.footnote, design: .monospaced))
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.tertiarySystemFill)))
            }
            Button(action: devam) {
                Text("Devam").font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 50)
                    .background(Capsule().fill(dogru ? Tema.dogru : renk))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    // MARK: Mantık

    private func hazirla() {
        guard secenekler.isEmpty && banka.isEmpty && dizi.isEmpty else { return }
        switch oge.kip {
        case .sec:
            secenekler = ([s.cevaplar?.first ?? ""] + (s.secenek ?? [])).shuffled()
        case .diz:
            let taslar = (s.tas ?? []) + (s.tur == .sirala ? [] : (s.fazla ?? []).prefix(4))
            var k = taslar.map { Tas(metin: $0) }.shuffled()
            // sıralamada taşlar doğru sırayla gelmesin
            if k.map(\.metin) == (s.tas ?? []) && k.count > 1 { k.swapAt(0, k.count - 1) }
            banka = k
        default: break
        }
    }

    private func cevapla(_ dogru: Bool, kip: SoruKipi? = nil) {
        sonuc = dogru
        cevaplandi(dogru, kip ?? oge.kip)
        if dogru { Dokunus.basari() } else { Dokunus.hata(); withAnimation(.default) { sallan += 1 } }
        odak = false
        Ses.konus(dogruCumle)
    }

    private func kontrolDiz() {
        let kurulan = dizi.map(\.metin).joined(separator: " ")
        cevapla((s.cevaplar ?? []).contains { Metin.esit($0, kurulan) })
    }

    private func kontrolYaz() {
        guard sonuc == nil, !yazi.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let dogru = (s.cevaplar ?? []).contains { Metin.esit($0, yazi) }
        // ipucuyla yazılan özerk sayılmaz: kurma olarak işlenir
        cevapla(dogru, kip: ipucu ? .diz : .yaz)
    }

    /// taş kipinde boşluklara yerleşen kelimeler
    private func bosluguDoldur() -> [String] {
        var sonuc: [String] = []
        var kalan = dizi.map(\.metin)[...]
        for n in s.parcaSayisi ?? [1] {
            let p = kalan.prefix(n)
            sonuc.append(p.joined(separator: " "))
            kalan = kalan.dropFirst(n)
        }
        return sonuc
    }

    private var dogruCumle: String {
        switch s.tur {
        case .bosluk: return Self.doldur(s.s ?? "", s.cevaplar?.first ?? "")
        case .hata: return s.dogru ?? ""
        case .sirala, .donustur:
            if let c = s.cevaplar?.first {
                let x = c.prefix(1).uppercased() + c.dropFirst()
                return x.last.map { ".?!".contains($0) } == true ? x : x + (s.son ?? "")
            }
            return ""
        }
    }

    static func doldur(_ cumle: String, _ cevap: String) -> String {
        var out = cumle
        for p in cevap.components(separatedBy: "·").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if let r = out.range(of: "____") { out.replaceSubrange(r, with: p) }
        }
        out = out.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
        return out.replacingOccurrences(of: " .", with: ".").replacingOccurrences(of: " ?", with: "?")
    }

    private func bosluklu(_ cumle: String, dolgu: [String]) -> AttributedString {
        var sonuc = AttributedString()
        let parcalar = cumle.components(separatedBy: "____")
        for (n, p) in parcalar.enumerated() {
            sonuc += AttributedString(p)
            if n < parcalar.count - 1 {
                let d = dolgu[safe: n] ?? ""
                var b = AttributedString(d.isEmpty ? " _____ " : " \(d) ")
                b.foregroundColor = renk
                b.backgroundColor = renk.opacity(0.12)
                b.font = Tema.ingilizce(.title2, .bold)
                sonuc += b
            }
        }
        return sonuc
    }

    private func ilkHarfler(_ c: String) -> String {
        c.components(separatedBy: "·").joined(separator: " ").split(separator: " ")
            .map { (w: Substring) -> String in w.prefix(1) + String(repeating: "_", count: max(0, w.count - 1)) }.joined(separator: "  ")
    }
}

/// Yanlışta küçük sallanma
struct Salla: GeometryEffect {
    var adim: CGFloat
    var animatableData: CGFloat { get { adim } set { adim = newValue } }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(adim * .pi * 4), y: 0))
    }
}
