// Metin Atölyesi (2026-11-05). Kullanıcının isteği (Kıvılcım, 5 Kasım 12:42 ve 13:12):
// · uzun bir dinleme metni, içinde 15 çalışma cümlesi; ara parçalar katlanınca çalışma metni yine tek hikâye kalır,
//   açılınca anlam bütünüyle ortaya çıkar;
// · bütün oyunlar aynı 15 cümle üzerinde, her biri 5 dakika; bir oyunu bitirmek = bugünün işi tamam (tik),
//   vakit varsa ikinci, üçüncü oyun;
// · kelime odağı (yeni + dün + 7 gün + 30 gün), gramer odağı (gramer motoru: bir cümlenin başka biçimleri),
//   cümleyi kendin kur (anlamdan cümleye);
// · sürdürülebilir zorluk; puan, seri, borç yok. Kayıt: `oyun` olayı (rol = adım, oran = isabet, sure = saniye).
import SwiftUI

// MARK: - Adımlar

enum AtolyeAdim: String, CaseIterable, Identifiable, Hashable {
    case metin, kelime, gramer, kur
    var id: String { rawValue }
    var ad: String {
        switch self { case .metin: "Hikâye"; case .kelime: "Kelime"; case .gramer: "Gramer"; case .kur: "Kur" }
    }
    var simge: String {
        switch self {
        case .metin: "book.pages"; case .kelime: "character.textbox"; case .gramer: "gearshape.2"; case .kur: "square.stack.3d.up"
        }
    }
    var renk: Color {
        switch self { case .metin: Tema.bolumRengi("dinleme"); case .kelime: Tema.yesil; case .gramer: Tema.vurgu; case .kur: Tema.kehribarYazi }
    }
    var aciklama: String {
        switch self {
        case .metin: "Bütün hikâye ya da yalnız çalışma cümleleri"
        case .kelime: "Boşluğa doğru kelime: yeni, dün, geçen hafta"
        case .gramer: "Aynı cümleyi başka biçimde kur"
        case .kur: "Türkçesinden İngilizce cümleyi kur"
        }
    }
    static let sure: TimeInterval = 5 * 60
}

extension Depo {
    func atolyeBitti(_ p: Paket, _ a: AtolyeAdim) -> Bool {
        olaylar.contains { $0.gun == p.gun && $0.tur == .oyun && $0.rol == a.rawValue }
    }
    func atolyeYaz(_ p: Paket, _ a: AtolyeAdim, oran: Double?, sure: Double) {
        var o = Olay(gun: p.gun, surum: p.surum, tur: .oyun)
        o.rol = a.rawValue
        o.oran = oran.map { ($0 * 100).rounded() / 100 }
        o.sure = sure.rounded()
        ekle(o)
    }
}

/// Liquid Glass (iOS 26) varsa cam, yoksa ince malzeme.
private struct Cam: ViewModifier {
    var radius: CGFloat = 16
    var tint: Color?
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(tint.map { .regular.tint($0.opacity(0.35)).interactive() } ?? .regular.interactive(),
                                in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay { if let tint { RoundedRectangle(cornerRadius: radius, style: .continuous).fill(tint.opacity(0.18)) } }
        }
    }
}

extension View {
    fileprivate func cam(_ radius: CGFloat = 16, tint: Color? = nil) -> some View { modifier(Cam(radius: radius, tint: tint)) }
}

// MARK: - Bugün kartı: şerit

struct AtolyeKarti: View {
    @EnvironmentObject var depo: Depo
    let p: Paket
    @Binding var sekme: Sekme
    @State private var acilan: AtolyeAdim?

    var body: some View {
        let h = depo.hazirlik(p.gun)
        let bitti = AtolyeAdim.allCases.filter { depo.atolyeBitti(p, $0) }
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Metin Atölyesi").font(.headline)
                    Text(bitti.isEmpty ? "Her oyun 5 dakika. Biri bitince bugünün işi tamam."
                         : bitti.count == AtolyeAdim.allCases.count ? "Hepsi bitti. Metin artık senin."
                         : "Bugün tamam ✓  Vaktin varsa bir oyun daha.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !bitti.isEmpty {
                    Image(systemName: "checkmark.seal.fill").font(.title2).foregroundStyle(Tema.yesil)
                        .symbolEffect(.bounce, value: bitti.count)
                        .accessibilityLabel("Bugünün işi tamam")
                }
            }
            serit(h)
            if p.dinleme == nil {
                Text("Bu günün uzun dinleme metni yok; atölye çalışma cümleleriyle açılır.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .kart()
        .sheet(item: $acilan) { a in
            AtolyeEkrani(p: p, adim: a).environmentObject(depo)
        }
    }

    /// Dinle → Metin → Kelime → Gramer → Kur → Sesinle: her düğüm bitince dolar, aradaki çizgi yeşerir.
    private func serit(_ h: Hazirlik) -> some View {
        let dugum: [(String, String, Color, Bool, () -> Void)] =
            [("Dinle", "headphones", Tema.vurgu, h.dinleme > 0, { sekme = .dinle })]
            + AtolyeAdim.allCases.map { a in (a.ad, a.simge, a.renk, depo.atolyeBitti(p, a), { acilan = a }) }
            + [("Sesinle", "mic", Tema.yesil, h.kayit > 0, { sekme = .kaydet })]
        return HStack(spacing: 0) {
            ForEach(Array(dugum.enumerated()), id: \.offset) { i, d in
                if i > 0 {
                    Capsule().fill(d.3 && dugum[i - 1].3 ? Tema.yesil : Tema.cizgi).frame(height: 3).frame(minWidth: 4, maxWidth: .infinity)
                        .padding(.bottom, 20)
                }
                Button(action: d.4) {
                    VStack(spacing: 5) {
                        ZStack {
                            Circle().fill(d.3 ? d.2 : d.2.opacity(0.12)).frame(width: 36, height: 36)
                            Image(systemName: d.3 ? "checkmark" : d.1)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(d.3 ? Color.white : d.2)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        Text(d.0).font(.caption2.weight(.medium)).foregroundStyle(d.3 ? Tema.metin : Tema.ikincil)
                            .lineLimit(1).fixedSize()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(d.0)\(d.3 ? ", yapıldı" : "")")
            }
        }
        .animation(.spring(duration: 0.5), value: dugum.map(\.3))
    }
}

// MARK: - Atölye ekranı

struct AtolyeEkrani: View {
    @EnvironmentObject var depo: Depo
    @Environment(\.dismiss) private var kapat
    let p: Paket
    @State var adim: AtolyeAdim

    var body: some View {
        NavigationStack {
            Group {
                switch adim {
                case .metin: UzunMetin(p: p) { bitir(.metin, oran: nil, sure: $0) }
                case .kelime: KelimeOyunu(p: p) { bitir(.kelime, oran: $0, sure: $1) }
                case .gramer: GramerOyunu(p: p) { bitir(.gramer, oran: $0, sure: $1) }
                case .kur: KurOyunu(p: p) { bitir(.kur, oran: $0, sure: $1) }
                }
            }
            .id(adim)
            .background(Tema.arka)
            .navigationTitle(adim.ad)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { kapat() } }
                ToolbarItem(placement: .principal) {
                    Picker("Adım", selection: $adim) {
                        ForEach(AtolyeAdim.allCases) { a in
                            Text(a.ad).tag(a)
                        }
                    }
                    .pickerStyle(.segmented).frame(maxWidth: 280)
                }
            }
        }
    }

    private func bitir(_ a: AtolyeAdim, oran: Double?, sure: Double) {
        if !depo.atolyeBitti(p, a) || sure > 20 { depo.atolyeYaz(p, a, oran: oran, sure: sure) }
    }
}

/// Oyunun sonundaki kart: büyük tik, kısa sonuç, sıradaki oyun.
private struct BitisKarti: View {
    @EnvironmentObject var depo: Depo
    let p: Paket
    let adim: AtolyeAdim
    let ozet: String
    var tekrar: () -> Void
    @State private var goster = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 76, weight: .semibold))
                .foregroundStyle(Tema.yesil)
                .symbolEffect(.bounce, value: goster)
                .scaleEffect(goster ? 1 : 0.6).opacity(goster ? 1 : 0)
            Text("\(adim.ad) bitti").font(.system(.title, design: .serif).weight(.semibold))
            Text(ozet).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            let kalan = AtolyeAdim.allCases.filter { $0 != adim && !depo.atolyeBitti(p, $0) }
            if let s = kalan.first {
                Text("Vaktin varsa sıradaki: \(s.ad) · 5 dk").font(.footnote).foregroundStyle(.tertiary)
            }
            Button("Bir tur daha", action: tekrar).buttonStyle(.bordered)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sensoryFeedback(.success, trigger: goster) { _, yeni in yeni && depo.haptik }
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { goster = true } }
    }
}

/// Beş dakikalık kum saati (üstte ince çizgi). Süre dolunca oyun biter, yarım tur sayılır.
private struct Sayac: View {
    let baslangic: Date
    var bitti: () -> Void
    @State private var tetik = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { c in
            let gecen = c.date.timeIntervalSince(baslangic)
            let kalan = max(0, AtolyeAdim.sure - gecen)
            HStack(spacing: 8) {
                ProgressView(value: min(1, gecen / AtolyeAdim.sure)).tint(kalan < 60 ? Tema.kehribar : Tema.vurgu)
                Text(String(format: "%d:%02d", Int(kalan) / 60, Int(kalan) % 60))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .onChange(of: kalan == 0) { _, sifir in if sifir && !tetik { tetik = true; bitti() } }
        }
    }
}

// MARK: - Metin: uzun hikâye, katlanır

struct UzunMetin: View {
    @EnvironmentObject var depo: Depo
    let p: Paket
    var okudu: (Double) -> Void
    @AppStorage("atolye.butun") private var butun = true
    @State private var secili: Int?
    @State private var acildi = Date()
    @State private var bitti = false

    private var parcalar: [Parca] {
        p.dinleme ?? p.cumleler.map { Parca(en: $0.en, tr: $0.tr, cumle: $0.i) }
    }

    /// Paragraflar: her üç çalışma cümlesinden sonra yeni paragraf.
    private var paragraflar: [[Parca]] {
        var out: [[Parca]] = [[]], n = 0
        for x in parcalar {
            out[out.count - 1].append(x)
            if x.cumle != nil { n += 1; if n % 3 == 0 { out.append([]) } }
        }
        return out.filter { !$0.isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if p.dinleme != nil {
                    Picker("Görünüm", selection: $butun.animation(.easeInOut(duration: 0.35))) {
                        Text("Bütün hikâye").tag(true)
                        Text("Çalışma metni").tag(false)
                    }
                    .pickerStyle(.segmented)
                    Text(butun ? "Vurgulu cümleler çalıştığın 15 cümle. Arası hikâyeyi tamamlar."
                               : "Ara parçalar katlandı. Cümleler kendi başına da bir hikâye.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(Array(paragraflar.enumerated()), id: \.offset) { i, par in
                    Text(paragraf(par))
                        .font(Tema.ingilizce(.title3)).lineSpacing(7)
                        .foregroundStyle(Tema.metin)
                        .fixedSize(horizontal: false, vertical: true)
                        .environment(\.openURL, OpenURLAction { u in
                            if u.scheme == "cumle", let i = Int(u.host() ?? "") {
                                withAnimation(.snappy) { secili = secili == i ? nil : i }
                            }
                            return .handled
                        })
                        .id("\(butun)-\(i)")
                        .transition(.opacity)
                }
                if let i = secili, let c = p.cumleler.first(where: { $0.i == i }) { ceviri(c) }
                Button {
                    bitti = true
                    okudu(Date().timeIntervalSince(acildi))
                } label: {
                    Label(depo.atolyeBitti(p, .metin) ? "Yeniden okudum" : "Okudum", systemImage: "checkmark")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent).tint(Tema.bolumRengi("dinleme"))
                .padding(.top, 8)
            }
            .padding(20)
        }
        .overlay {
            if bitti {
                BitisKarti(p: p, adim: .metin, ozet: "Hikâyenin bütünü zihninden geçti.") { bitti = false; acildi = Date() }
                    .background(Tema.arka)
            }
        }
    }

    private func paragraf(_ par: [Parca]) -> AttributedString {
        var a = AttributedString()
        for x in par {
            guard let en = x.en, !en.isEmpty else { continue }
            if let i = x.cumle {
                var s = AttributedString(en + " ")
                s.foregroundColor = Tema.metin
                s.backgroundColor = Tema.kehribar.opacity(secili == i ? 0.38 : 0.16)
                s.link = URL(string: "cumle://\(i)")
                a += s
            } else if butun {
                var s = AttributedString(en + " ")
                s.foregroundColor = Tema.ikincil
                a += s
            }
        }
        return a
    }

    private func ceviri(_ c: Cumle) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Cümle \(c.i + 1)").font(.caption.weight(.bold)).foregroundStyle(Tema.kehribarYazi)
                Spacer()
                if let k = c.konu { Cip(metin: k, renk: Tema.vurgu, simge: "textformat") }
            }
            Text(c.tr ?? "").font(.callout).foregroundStyle(Tema.metin)
        }
        .padding(14)
        .cam(16, tint: Tema.kehribar)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Kelime: boşluğa doğru kelime

private struct KelimeSorusu: Hashable {
    var cumle: String          // boşluklu
    var tr: String?
    var dogru: String          // seçenekte görünen yalın biçim
    var yer: String            // cümledeki biçimi (çekimli olabilir)
    var secenekler: [String]
    var kart: Sozcuk
    var kaynak: String         // yeni · dün · 7 gün önce …
}

struct KelimeOyunu: View {
    @EnvironmentObject var depo: Depo
    let p: Paket
    var bitti: (Double, Double) -> Void
    @State private var sorular: [KelimeSorusu] = []
    @State private var sira = 0
    @State private var secim: String?
    @State private var dogru = 0
    @State private var basla = Date()
    @State private var son = false
    @State private var turkce = false

    var body: some View {
        VStack(spacing: 0) {
            if son {
                EmptyView()
            } else if sorular.isEmpty {
                BosDurum(simge: "character.textbox", baslik: "Bu günde hedef kelime yok", metin: "Paketin sözlüğü boş görünüyor.")
            } else {
                Sayac(baslangic: basla) { sonla() }.padding(.horizontal, 20).padding(.top, 10)
                soru(sorular[sira])
            }
        }
        .overlay {
            if son {
                BitisKarti(p: p, adim: .kelime, ozet: "\(secim == nil ? sira : sira + 1) kelimeden \(dogru) tanesi ilk denemede.") { yeniden() }
                    .background(Tema.arka)
            }
        }
        .onAppear { if sorular.isEmpty { kur() } }
    }

    private func soru(_ s: KelimeSorusu) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Cip(metin: s.kaynak, renk: Tema.yesil, simge: "clock.arrow.circlepath")
                    Spacer()
                    Text("\(sira + 1)/\(sorular.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(secim == nil ? s.cumle : s.cumle.replacingOccurrences(of: "_____", with: s.yer))
                    .font(Tema.ingilizce(.title2)).lineSpacing(6)
                    .contentTransition(.opacity)
                if let tr = s.tr {
                    Button { withAnimation { turkce.toggle() } } label: {
                        Text(turkce ? tr : "Türkçesi").font(.callout).foregroundStyle(turkce ? Tema.metin : Tema.vurgu)
                    }
                    .buttonStyle(.plain)
                }
                VStack(spacing: 10) {
                    ForEach(s.secenekler, id: \.self) { w in
                        Button { if secim == nil { sec(w, s) } } label: {
                            HStack {
                                Text(w).font(.title3.weight(.medium))
                                Spacer()
                                if secim != nil && w == s.dogru { Image(systemName: "checkmark.circle.fill").foregroundStyle(Tema.yesil) }
                                else if secim == w { Image(systemName: "xmark.circle.fill").foregroundStyle(.red) }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 14)
                            .foregroundStyle(Tema.metin)
                            .cam(16, tint: secim == nil ? nil : (w == s.dogru ? Tema.yesil : (secim == w ? .red : nil)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if secim != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(s.kart.w).font(.headline)
                            if let ipa = s.kart.ipa { Text(ipa).font(.caption).foregroundStyle(.secondary) }
                        }
                        if let tr = s.kart.tr { Text(tr).font(.callout) }
                        if let t = s.kart.tanim { Text(t).font(.caption).foregroundStyle(.secondary) }
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading).cam(16)
                    Button { ileri() } label: {
                        Text(sira + 1 < sorular.count ? "Sonraki" : "Bitir").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent).tint(Tema.yesil)
                }
            }
            .padding(20)
        }
        .sensoryFeedback(.selection, trigger: secim) { _, y in y != nil && depo.haptik }
    }

    private func sec(_ w: String, _ s: KelimeSorusu) {
        withAnimation(.snappy) { secim = w }
        if w == s.dogru { dogru += 1 }
    }
    private func ileri() {
        if sira + 1 < sorular.count { withAnimation { sira += 1; secim = nil; turkce = false } } else { sonla() }
    }
    private func sonla() {
        guard !son else { return }
        withAnimation { son = true }
        let n = max(1, secim == nil ? sira : sira + 1)
        bitti(Double(dogru) / Double(n), Date().timeIntervalSince(basla))
    }
    private func yeniden() { kur(); sira = 0; secim = nil; dogru = 0; basla = Date(); son = false }

    /// Sözlükteki hedef kelimeler (yeni önce, sonra dün, 7 gün, 30 gün, yankı): önce çalışma cümlesinde, yoksa hikâyede ara.
    private func kur() {
        let sira: [String: Int] = ["yeni": 0, "tekrar-dun": 1, "yanki": 2, "tekrar-hafta": 3, "tekrar-ay": 4, "tanidik": 5]
        let kelimeler = (p.sozluk ?? []).sorted { (sira[$0.tur ?? ""] ?? 9) < (sira[$1.tur ?? ""] ?? 9) }
        let yerler: [(String, String?)] = p.cumleler.compactMap { c in c.en.map { ($0, c.tr) } }
            + (p.dinleme ?? []).filter { $0.cumle == nil }.compactMap { x in x.en.map { ($0, x.tr) } }
        var out: [KelimeSorusu] = [], kullanilan = Set<String>()
        for k in kelimeler {
            guard !kullanilan.contains(k.w.lowercased()) else { continue }
            for (en, tr) in yerler {
                guard let r = eslesen(k.w, en) else { continue }
                let bos = en.replacingCharacters(in: r, with: "_____")
                let digerleri = kelimeler.map(\.w).filter { $0.lowercased() != k.w.lowercased() }.shuffled().prefix(3)
                out.append(KelimeSorusu(cumle: bos, tr: tr, dogru: k.w, yer: String(en[r]), secenekler: ([k.w] + digerleri).shuffled(),
                                        kart: k, kaynak: k.turAdi.isEmpty ? "kelime" : k.turAdi))
                kullanilan.insert(k.w.lowercased())
                break
            }
            if out.count >= 10 { break }
        }
        sorular = out
    }

    /// Kelimenin cümledeki yeri (çekimleriyle: -s, -ed, -ing, -ly).
    private func eslesen(_ w: String, _ en: String) -> Range<String.Index>? {
        let kok = NSRegularExpression.escapedPattern(for: w.lowercased())
        let govde = w.lowercased().hasSuffix("e") ? NSRegularExpression.escapedPattern(for: String(w.lowercased().dropLast())) + "(?:e|ing)" : kok
        let desen = "\\b(?:\(kok)(?:s|es|d|ed|ing|ly)?|\(govde))\\b"
        return en.range(of: desen, options: [.regularExpression, .caseInsensitive])
    }
}

// MARK: - Dizici: kelimelerden cümle kur (Gramer ve Kur oyunlarının ortak aleti)

/// Üretim aleti. Kullanıcının kuralı (2026-08-24 ölçümü): tanımada tutan yapıya şık sorusu konmaz, kurdurulur.
private struct Dizici: View {
    @EnvironmentObject var depo: Depo
    let hedef: String
    let parcalar: [String]         // hedefin parçaları + varsa çeldiriciler
    var renk: Color = Tema.kehribar
    var sonuc: (Bool) -> Void      // true: ilk denemede kuruldu; false: yanlıştan sonra ya da gösterilerek

    struct Parcacik: Identifiable, Hashable { var id: Int; var metin: String }
    enum Durum { case kuruyor, dogru, yanlis, gosterildi }

    @State private var havuz: [Parcacik] = []
    @State private var dizilen: [Parcacik] = []
    @State private var durum: Durum = .kuruyor
    @State private var yanlisVar = false
    @State private var dolu = 0     // hedefteki parça sayısı

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AkisDuzeni(aralik: 8) {
                ForEach(dizilen) { x in
                    Button { geriAl(x) } label: { parcacik(x.metin, tint: durum == .yanlis ? .red : renk) }
                        .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            .padding(12)
            .background { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Tema.cizgi, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])) }
            if durum == .dogru || durum == .gosterildi {
                VStack(alignment: .leading, spacing: 6) {
                    Label(durum == .dogru ? "Doğru" : "Doğrusu", systemImage: durum == .dogru ? "checkmark.circle.fill" : "eye")
                        .font(.headline).foregroundStyle(durum == .dogru ? Tema.yesil : Tema.ikincil)
                    Text(hedef).font(Tema.ingilizce(.body))
                }
            } else {
                AkisDuzeni(aralik: 8) {
                    ForEach(havuz) { x in
                        Button { ekle(x) } label: { parcacik(x.metin, tint: nil) }.buttonStyle(.plain)
                    }
                }
                HStack {
                    if durum == .yanlis {
                        Text("Sıra tutmadı. Bir parçaya dokunup geri al.").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Göster") {
                        withAnimation { durum = .gosterildi }
                        sonuc(false)
                    }
                    .font(.callout)
                }
            }
        }
        .sensoryFeedback(.success, trigger: durum == .dogru) { _, y in y && depo.haptik }
        .sensoryFeedback(.error, trigger: durum == .yanlis) { _, y in y && depo.haptik }
        .onAppear { hazirla() }
    }

    private func parcacik(_ s: String, tint: Color?) -> some View {
        Text(s).font(Tema.ingilizce(.body).weight(.medium))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .foregroundStyle(Tema.metin)
            // flat on purpose: a glass effect on every tile makes the animation stutter
            .background { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.map { $0.opacity(0.28) } ?? Tema.yuzey) }
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Tema.cizgi, lineWidth: 1) }
    }

    private func hazirla() {
        var k = parcalar.enumerated().map { Parcacik(id: $0.offset, metin: $0.element) }.shuffled()
        if k.map(\.metin) == parcalar, k.count > 1 { k.swapAt(0, 1) }
        havuz = k; dizilen = []; durum = .kuruyor; yanlisVar = false
        dolu = Dizici.kelimeSayisi(hedef)
    }
    private func ekle(_ x: Parcacik) {
        // a tile that is still fading out can be tapped again: take it only once
        guard durum == .kuruyor || durum == .yanlis, havuz.contains(where: { $0.id == x.id }) else { return }
        withAnimation(.snappy(duration: 0.2)) {
            havuz.removeAll { $0.id == x.id }
            dizilen.append(x)
            let n = dizilen.reduce(0) { $0 + Dizici.kelimeSayisi($1.metin) }
            if n == dolu { denetle() } else if n > dolu { durum = .yanlis; yanlisVar = true }
        }
    }
    private func geriAl(_ x: Parcacik) {
        guard durum == .kuruyor || durum == .yanlis, dizilen.contains(where: { $0.id == x.id }) else { return }
        withAnimation(.snappy(duration: 0.2)) {
            dizilen.removeAll { $0.id == x.id }
            havuz.append(x)
            durum = .kuruyor
        }
    }
    private func denetle() {
        if Dizici.norm(dizilen.map(\.metin).joined(separator: " ")) == Dizici.norm(hedef) {
            durum = .dogru
            sonuc(!yanlisVar)
        } else {
            durum = .yanlis; yanlisVar = true
        }
    }
    static func kelimeSayisi(_ s: String) -> Int { s.split(separator: " ").count }
    static func norm(_ s: String) -> String { s.lowercased().split(separator: " ").joined(separator: " ") }
}

// MARK: - Gramer: aynı cümle, başka biçim (gramer motoru)

struct GramerOyunu: View {
    @EnvironmentObject var depo: Depo
    @Environment(\.openURL) private var ac
    let p: Paket
    var bitti: (Double, Double) -> Void
    @State private var sorular: [Donusum] = []
    @State private var sira = 0
    @State private var cozuldu = false
    @State private var dogru = 0
    @State private var basla = Date()
    @State private var son = false

    var body: some View {
        Group {
            if sorular.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        BosDurum(simge: "gearshape.2", baslik: "Bu günün dönüşüm alıştırması yok",
                                 metin: "Yeni biçimdeki günlerde her gün 3-6 dönüşüm gelir. Bugün GramerApp'te yapıya 5 dakika bak.")
                        gramerBaglari
                        Button { son = true; bitti(1, Date().timeIntervalSince(basla)) } label: {
                            Text("Baktım, bitti").frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(20)
                }
            } else {
                VStack(spacing: 0) {
                    Sayac(baslangic: basla) { sonla() }.padding(.horizontal, 20).padding(.top, 10)
                    soru(sorular[sira])
                }
            }
        }
        .overlay {
            if son && !sorular.isEmpty {
                VStack {
                    BitisKarti(p: p, adim: .gramer, ozet: "\(cozuldu ? sira + 1 : sira) dönüşüm kurdun, \(dogru) tanesi ilk denemede.") { yeniden() }
                    gramerBaglari.padding(.horizontal, 20).padding(.bottom, 24)
                }
                .background(Tema.arka)
            }
        }
        .onAppear { if sorular.isEmpty { yeniden() } }
    }

    private var gramerBaglari: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach((p.gramer ?? []).filter { $0.id != nil }, id: \.konu) { g in
                Button { if let id = g.id, let u = URL(string: "disli://konu/\(id)") { ac(u) } } label: {
                    HStack {
                        Image(systemName: "arrow.up.forward.app")
                        VStack(alignment: .leading) {
                            Text("GramerApp'te 5 dakika").font(.caption).foregroundStyle(.secondary)
                            Text(g.konu).font(.subheadline.weight(.semibold))
                        }
                        Spacer()
                    }
                    .padding(12).foregroundStyle(Tema.metin).cam(14, tint: Tema.vurgu)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func soru(_ d: Donusum) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    if let k = d.konu { Cip(metin: k, renk: Tema.vurgu, simge: "textformat") }
                    Spacer()
                    Text("\(sira + 1)/\(sorular.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Cümle \(d.cumle + 1)").font(.caption.weight(.bold)).foregroundStyle(Tema.kehribarYazi)
                    Text(p.cumleler.first { $0.i == d.cumle }?.en ?? "").font(Tema.ingilizce(.title3)).lineSpacing(5)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading).cam(16, tint: Tema.kehribar)
                Label(d.istem, systemImage: "arrow.triangle.2.circlepath").font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Dizici(hedef: d.cevap, parcalar: GramerOyunu.parcalar(d), renk: Tema.vurgu) { ilkte in
                    if ilkte { dogru += 1 }
                    withAnimation { cozuldu = true }
                }
                .id(sira)
                if cozuldu {
                    Button { ileri() } label: {
                        Text(sira + 1 < sorular.count ? "Sonraki" : "Bitir").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
    }

    /// Cevabın kelimeleri + yanlış seçeneklerden gelen en çok üç çeldirici: yapı kararı kurarken verilir.
    static func parcalar(_ d: Donusum) -> [String] {
        let dogru = d.cevap.split(separator: " ").map(String.init)
        let bilinen = Set(dogru.map { $0.lowercased() })
        var cel: [String] = []
        for s in d.secenekler ?? [] where s != d.cevap {
            for w in s.split(separator: " ").map(String.init) where !bilinen.contains(w.lowercased()) && !cel.contains(w) { cel.append(w) }
        }
        return dogru + cel.prefix(3)
    }

    private func ileri() {
        if sira + 1 < sorular.count { withAnimation { sira += 1; cozuldu = false } } else { sonla() }
    }
    private func sonla() {
        guard !son else { return }
        withAnimation { son = true }
        bitti(Double(dogru) / Double(max(1, cozuldu ? sira + 1 : sira)), Date().timeIntervalSince(basla))
    }
    private func yeniden() {
        sorular = (p.donusum ?? []).shuffled()
        sira = 0; cozuldu = false; dogru = 0; basla = Date(); son = false
    }
}

// MARK: - Kur: Türkçesinden cümleyi kur

struct KurOyunu: View {
    @EnvironmentObject var depo: Depo
    let p: Paket
    var bitti: (Double, Double) -> Void
    @State private var cumleler: [Cumle] = []
    @State private var sira = 0
    @State private var cozuldu = false
    @State private var ilkte = 0
    @State private var tur = 0
    @State private var basla = Date()
    @State private var son = false

    var body: some View {
        VStack(spacing: 0) {
            if cumleler.isEmpty {
                BosDurum(simge: "square.stack.3d.up", baslik: "Cümle yok", metin: "Paketin çalışma cümleleri gelmemiş.")
            } else {
                Sayac(baslangic: basla) { sonla() }.padding(.horizontal, 20).padding(.top, 10)
                kur(cumleler[sira])
            }
        }
        .overlay {
            if son {
                BitisKarti(p: p, adim: .kur, ozet: "\(cozuldu ? sira + 1 : sira) cümle kurdun, \(ilkte) tanesi ilk denemede.") { yeniden() }
                    .background(Tema.arka)
            }
        }
        .onAppear { if cumleler.isEmpty { yeniden() } }
    }

    private func kur(_ c: Cumle) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    if let k = c.konu { Cip(metin: k, renk: Tema.vurgu, simge: "textformat") }
                    Spacer()
                    Text("\(sira + 1)/\(cumleler.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(c.tr ?? "").font(.title3.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                Dizici(hedef: c.en ?? "", parcalar: KurOyunu.parcalar(c.en ?? "")) { ilk in
                    if ilk { ilkte += 1 }
                    withAnimation { cozuldu = true }
                }
                .id("\(tur)-\(sira)")
                if cozuldu {
                    Button { ileri() } label: {
                        Text(sira + 1 < cumleler.count ? "Sonraki" : "Bitir").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent).tint(Tema.kehribarYazi)
                }
            }
            .padding(20)
        }
    }

    /// Cümleyi ikişer kelimelik parçalara böler (uzun cümlede üçer).
    static func parcalar(_ en: String) -> [String] {
        let w = en.split(separator: " ").map(String.init)
        let boy = w.count > 14 ? 3 : 2
        return stride(from: 0, to: w.count, by: boy).map { w[$0..<min(w.count, $0 + boy)].joined(separator: " ") }
    }

    private func ileri() {
        if sira + 1 < cumleler.count { withAnimation { sira += 1; cozuldu = false } } else { sonla() }
    }
    private func sonla() {
        guard !son else { return }
        withAnimation { son = true }
        bitti(Double(ilkte) / Double(max(1, cozuldu ? sira + 1 : sira)), Date().timeIntervalSince(basla))
    }
    private func yeniden() {
        // önce gramer yapısını taşıyanlar, sonra takıldıkların, sonra öbürleri; en çok 6
        let takilan = Set(depo.olaylar.filter { $0.gun == p.gun && $0.tur == .takildi }.compactMap(\.cumle))
        let sirali = p.cumleler.filter { $0.en?.isEmpty == false }.sorted {
            let a = ($0.konu != nil ? 0 : 2) - (takilan.contains($0.i) ? 1 : 0)
            let b = ($1.konu != nil ? 0 : 2) - (takilan.contains($1.i) ? 1 : 0)
            return a == b ? $0.i < $1.i : a < b
        }
        cumleler = Array(sirali.prefix(6)).sorted { $0.i < $1.i }
        sira = 0; cozuldu = false; ilkte = 0; tur += 1; basla = Date(); son = false
    }
}
