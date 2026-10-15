// MOTOR — "Sıra ve talep" yasasının oyunu (Gramer Motoru v2'nin telefondaki hâli).
// Fiil öbeği: [modal] [have] [be süreç] [be edilgen] ana fiil. Her parça bir sonrakinin biçimini ister;
// zaman ve kişi yalnız ilk parçaya biner. Beş anahtarı çevir: 12 zaman, edilgen ve kipler aynı makine.
import SwiftUI

// MARK: - Motor

struct MotorAyar: Equatable {
    var gecmis = false
    var modal: String? = nil
    var perfect = false
    var surec = false
    var edilgen = false
}

enum MKisi { case ben, tekil, cogul }

struct MFiil { let yalin, s3, v2, v3, ing: String }

struct MSahne {
    let ozne: String; let kisi: MKisi
    let fiil: MFiil
    let nesne: String; let nesneKisi: MKisi
    let ajan: String
}

enum MParcaTur { case ozne, modal, perfect, surec, edilgen, ana, nesne, ajan }

struct MParca: Identifiable, Equatable {
    var id: String { "\(tur)" }
    let tur: MParcaTur
    let metin: String
    var talep: String? = nil     // bir sonrakine dayattığı biçim
    var zaman = false            // zaman + kişi bu parçada

    var renk: Color {
        switch tur {
        case .modal: Tema.modal
        case .perfect: Tema.perfect
        case .surec: Tema.surec
        case .edilgen: Tema.edilgen
        case .ana: .primary
        default: .secondary
        }
    }
}

enum Motor {
    static let sahneler: [MSahne] = [
        MSahne(ozne: "The workers", kisi: .cogul, fiil: MFiil(yalin: "build", s3: "builds", v2: "built", v3: "built", ing: "building"),
               nesne: "the bridge", nesneKisi: .tekil, ajan: "by the workers"),
        MSahne(ozne: "Anna", kisi: .tekil, fiil: MFiil(yalin: "write", s3: "writes", v2: "wrote", v3: "written", ing: "writing"),
               nesne: "the letters", nesneKisi: .cogul, ajan: "by Anna"),
        MSahne(ozne: "I", kisi: .ben, fiil: MFiil(yalin: "paint", s3: "paints", v2: "painted", v3: "painted", ing: "painting"),
               nesne: "the kitchen", nesneKisi: .tekil, ajan: "by me"),
        MSahne(ozne: "The police", kisi: .cogul, fiil: MFiil(yalin: "catch", s3: "catches", v2: "caught", v3: "caught", ing: "catching"),
               nesne: "the thief", nesneKisi: .tekil, ajan: "by the police"),
        MSahne(ozne: "My sister", kisi: .tekil, fiil: MFiil(yalin: "make", s3: "makes", v2: "made", v3: "made", ing: "making"),
               nesne: "the cakes", nesneKisi: .cogul, ajan: "by my sister"),
        MSahne(ozne: "Tom", kisi: .tekil, fiil: MFiil(yalin: "repair", s3: "repairs", v2: "repaired", v3: "repaired", ing: "repairing"),
               nesne: "the car", nesneKisi: .tekil, ajan: "by Tom"),
        MSahne(ozne: "We", kisi: .cogul, fiil: MFiil(yalin: "clean", s3: "cleans", v2: "cleaned", v3: "cleaned", ing: "cleaning"),
               nesne: "the windows", nesneKisi: .cogul, ajan: "by us"),
        MSahne(ozne: "The company", kisi: .tekil, fiil: MFiil(yalin: "sell", s3: "sells", v2: "sold", v3: "sold", ing: "selling"),
               nesne: "the old phones", nesneKisi: .cogul, ajan: "by the company"),
    ]

    static let modallar = ["will", "can", "may", "should", "must"]
    static func modalBicim(_ m: String, gecmis: Bool) -> String {
        guard gecmis else { return m }
        return ["will": "would", "can": "could", "may": "might"][m] ?? m
    }

    enum Talep { case cekimli, yalin, v3, ing }

    static func kur(_ s: MSahne, _ a: MotorAyar) -> [MParca] {
        let ozne = a.edilgen ? s.nesne.prefix(1).uppercased() + s.nesne.dropFirst() : s.ozne
        let kisi = a.edilgen ? s.nesneKisi : s.kisi
        var p: [MParca] = [MParca(tur: .ozne, metin: ozne)]
        var talep: Talep = .cekimli

        func bicim(_ yalin: String, _ s3: String, _ v2: String, _ v3: String, _ ing: String) -> String {
            switch talep {
            case .yalin: return yalin
            case .v3: return v3
            case .ing: return ing
            case .cekimli:
                if yalin == "be" {
                    if a.gecmis { return kisi == .cogul ? "were" : "was" }
                    return kisi == .ben ? "am" : kisi == .tekil ? "is" : "are"
                }
                if a.gecmis { return v2 }
                return kisi == .tekil ? s3 : yalin
            }
        }
        let ilk = { (t: Talep) in t == .cekimli }

        if let m = a.modal {
            p.append(MParca(tur: .modal, metin: modalBicim(m, gecmis: a.gecmis), talep: "yalın", zaman: true))
            talep = .yalin
        }
        if a.perfect {
            p.append(MParca(tur: .perfect, metin: bicim("have", "has", "had", "had", "having"), talep: "V3", zaman: ilk(talep)))
            talep = .v3
        }
        if a.surec {
            p.append(MParca(tur: .surec, metin: bicim("be", "is", "was", "been", "being"), talep: "-ing", zaman: ilk(talep)))
            talep = .ing
        }
        if a.edilgen {
            p.append(MParca(tur: .edilgen, metin: bicim("be", "is", "was", "been", "being"), talep: "V3", zaman: ilk(talep)))
            talep = .v3
        }
        let f = s.fiil
        p.append(MParca(tur: .ana, metin: bicim(f.yalin, f.s3, f.v2, f.v3, f.ing), zaman: ilk(talep)))
        if a.edilgen { p.append(MParca(tur: .ajan, metin: s.ajan)) } else { p.append(MParca(tur: .nesne, metin: s.nesne)) }
        return p
    }

    static func cumle(_ s: MSahne, _ a: MotorAyar) -> String {
        kur(s, a).map(\.metin).joined(separator: " ") + "."
    }

    /// Ayarın Türkçe okunuşu
    static func okunus(_ a: MotorAyar) -> [(String, Color)] {
        var r: [(String, Color)] = []
        let anlam = ["will": "tahmin · gelecek", "can": "yetenek · olasılık", "may": "olasılık", "should": "beklenti · öneri", "must": "zorunluluk · çıkarım"]
        r.append((a.gecmis ? (a.modal == nil ? "geçmiş" : "uzak / kibar") : "şimdi", Tema.zaman))
        if let m = a.modal { r.append((anlam[m] ?? m, Tema.modal)) }
        if a.perfect { r.append(("geriye bakış", Tema.perfect)) }
        if a.surec { r.append(("süren", Tema.surec)) }
        if a.edilgen { r.append(("yapılan", Tema.edilgen)) }
        if !a.perfect && !a.surec && a.modal == nil { r.append(("yalın olay", .secondary)) }
        return r
    }

    static func rastgeleAyar() -> MotorAyar {
        var a = MotorAyar()
        a.gecmis = Bool.random()
        a.modal = Bool.random() ? modallar.randomElement() : nil
        a.perfect = Bool.random()
        a.surec = Int.random(in: 0..<3) == 0
        a.edilgen = Bool.random()
        if a.perfect && a.surec && a.edilgen { a.surec = false }   // nadir yapıyı görevde sorma
        if a.modal == "should" || a.modal == "must" { a.gecmis = false }   // geçmişte biçim değişmiyor: görev anlamsız olur
        if a.modal == nil && !a.perfect && !a.surec && !a.edilgen { a.perfect = true }
        return a
    }
}

// MARK: - Oyun

struct MotorOyunu: View {
    @Environment(\.dismiss) private var kapat
    @State private var ayar = MotorAyar()
    @State private var sahneNo = 0
    @State private var kip = 0          // 0 serbest · 1 görev
    @State private var tur = 0
    @State private var hedef = MotorAyar()
    @State private var hedefSahne = 0
    @State private var hamle = 0
    @State private var basari = false
    @State private var bitti = false
    private let turSayisi = 8

    private var sahne: MSahne { Motor.sahneler[(kip == 1 ? hedefSahne : sahneNo) % Motor.sahneler.count] }
    private var parcalar: [MParca] { Motor.kur(sahne, ayar) }

    var body: some View {
        if bitti {
            OyunSonu(oyun: .motor, buyuk: "\(turSayisi)/\(turSayisi)", aciklama: "\(hamle) hamlede bütün görevler",
                     ders: "Hep aynı kural çalıştı: her parça bir sonrakinin biçimini istedi; zaman yalnız ilk parçaya bindi.",
                     tekrar: { bitti = false; turuBaslat(0) }, kapat: { kapat() })
        } else {
            VStack(spacing: 14) {
                OyunUstu(baslik: "Motor", alt: kip == 1 ? "Görev \(tur + 1) / \(turSayisi)" : "Serbest", renk: Oyun.motor.renk,
                         ilerleme: kip == 1 ? Double(tur) / Double(turSayisi) : nil) { kapat() }
                Picker("Kip", selection: $kip) { Text("Serbest").tag(0); Text("Görev").tag(1) }
                    .pickerStyle(.segmented).padding(.horizontal)
                    .onChange(of: kip) { _, k in if k == 1 { turuBaslat(0) } }
                ScrollView {
                    VStack(spacing: 14) {
                        if kip == 1 { gorevKarti }
                        cumleKarti
                        anahtarlar
                        zincir
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
            .background(Lekeler(renkler: [Tema.zaman, Tema.modal, Tema.perfect]))
            .overlay { if basari { Konfeti() } }
        }
    }

    // MARK: Görev

    private var gorevKarti: some View {
        let cumleGorevi = tur % 2 == 1
        return VStack(alignment: .leading, spacing: 10) {
            Text(cumleGorevi ? "Bu cümleyi motorda kur" : "Bu anlamı ver").font(.caption.weight(.bold)).textCase(.uppercase)
                .foregroundStyle(.secondary)
            if cumleGorevi {
                Text(Motor.cumle(Motor.sahneler[hedefSahne], hedef)).font(Tema.ingilizce(.title3, .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Akis(aralik: 6, satirAraligi: 6) {
                    ForEach(Motor.okunus(hedef), id: \.0) { ad, r in
                        Text(ad).font(.subheadline.weight(.bold)).padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(r.opacity(0.15))).foregroundStyle(r)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if basari {
                Label("Oturdu", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(Tema.dogru)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kart(16)
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(basari ? Tema.dogru : Oyun.motor.renk.opacity(0.3), lineWidth: basari ? 2 : 1))
    }

    private func turuBaslat(_ n: Int) {
        tur = n
        if n == 0 { hamle = 0 }
        hedefSahne = Int.random(in: 0..<Motor.sahneler.count)
        repeat { hedef = Motor.rastgeleAyar() } while Motor.cumle(Motor.sahneler[hedefSahne], hedef) == Motor.cumle(Motor.sahneler[hedefSahne], MotorAyar())
        withAnimation { ayar = MotorAyar(); basari = false }
    }

    private func denetle() {
        guard kip == 1, !basari else { return }
        hamle += 1
        let tamam = tur % 2 == 1
            ? Motor.cumle(sahne, ayar) == Motor.cumle(Motor.sahneler[hedefSahne], hedef)
            : Motor.okunus(ayar).map(\.0) == Motor.okunus(hedef).map(\.0)
        if tamam {
            Dokunus.basari()
            Ses.konus(Motor.cumle(sahne, ayar))
            withAnimation(.spring) { basari = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                if tur + 1 >= turSayisi { bitti = true } else { turuBaslat(tur + 1) }
            }
        }
    }

    // MARK: Cümle

    private var cumleKarti: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Cümle").font(.caption.weight(.bold)).textCase(.uppercase).foregroundStyle(.secondary)
                Spacer()
                Button { Ses.konus(Motor.cumle(sahne, ayar)) } label: { Image(systemName: "speaker.wave.2.fill") }
                if kip == 0 {
                    Button {
                        Dokunus.hafif()
                        withAnimation(.snappy) { sahneNo += 1 }
                    } label: { Image(systemName: "dice.fill") }
                    .accessibilityLabel("Yeni cümle")
                }
            }
            .foregroundStyle(Oyun.motor.renk)
            Akis(aralik: 6, satirAraligi: 12) {
                ForEach(parcalar) { p in
                    VStack(spacing: 3) {
                        Text(p.metin)
                            .font(Tema.ingilizce(.title2, p.tur == .ozne || p.tur == .nesne || p.tur == .ajan ? .regular : .bold))
                            .foregroundStyle(p.renk)
                            .contentTransition(.interpolate)
                            .padding(.horizontal, p.tur == .ozne || p.tur == .nesne || p.tur == .ajan ? 0 : 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 8).fill(p.tur == .ana || p.tur == .ozne || p.tur == .nesne || p.tur == .ajan ? .clear : p.renk.opacity(0.12)))
                            .overlay(alignment: .bottom) {
                                if p.zaman { Capsule().fill(Tema.zaman).frame(height: 3).offset(y: 5) }
                            }
                        Text(p.talep.map { "→ \($0)" } ?? (p.zaman ? "zaman" : " "))
                            .font(.caption2.weight(.semibold)).foregroundStyle(p.talep != nil ? p.renk : Tema.zaman)
                    }
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: parcalar)
            Divider()
            Akis(aralik: 6, satirAraligi: 6) {
                ForEach(Motor.okunus(ayar), id: \.0) { ad, r in
                    Text(ad).font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(r.opacity(0.13))).foregroundStyle(r)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if ayar.perfect && ayar.surec && ayar.edilgen {
                Text("Dilbilgisi açısından doğru ama günlük dilde çok nadir.").font(.caption).foregroundStyle(.secondary)
            }
            if ayar.modal == "must" && ayar.gecmis {
                Text("must'ın geçmiş biçimi yok: geçmiş zorunluluk için had to, geçmiş çıkarım için must have + V3.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .kart(18)
    }

    // MARK: Talep zinciri — yasanın kendisi, yazıyla

    private var zincir: some View {
        let fiiller = parcalar.filter { [.modal, .perfect, .surec, .edilgen, .ana].contains($0.tur) }
        let ciftler = Array(zip(fiiller, fiiller.dropFirst()))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) { Cizim(ad: "talep", renk: .secondary, boy: 18, zemin: false); Text("Talep zinciri") }
                .font(.caption.weight(.bold)).textCase(.uppercase)
                .foregroundStyle(.secondary)
            if let ilk = fiiller.first {
                (Text("Zaman ve kişi yalnız ilk dişliye biner: ") + Text(ilk.metin).bold().foregroundColor(Tema.zaman))
                    .font(.subheadline)
            }
            ForEach(Array(ciftler.enumerated()), id: \.offset) { _, c in
                HStack(spacing: 8) {
                    Text(c.0.metin).font(Tema.ingilizce(.body, .bold)).foregroundStyle(c.0.renk)
                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
                    Text(c.0.talep ?? "").font(.system(.caption, design: .monospaced).weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(c.0.renk.opacity(0.14))).foregroundStyle(c.0.renk)
                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
                    Text(c.1.metin).font(Tema.ingilizce(.body, .bold)).foregroundStyle(c.1.renk == .primary ? Color.primary : c.1.renk)
                }
            }
            if ciftler.isEmpty {
                Text("Tek dişli: yardımcı fiil yok, zaman doğrudan ana fiile biner.").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .kart(16)
        .animation(.snappy, value: parcalar)
    }

    // MARK: Anahtarlar

    private var anahtarlar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                anahtarDugme("Şimdi", acik: !ayar.gecmis, renk: Tema.zaman) { ayar.gecmis = false }
                anahtarDugme("Geçmiş", acik: ayar.gecmis, renk: Tema.zaman) { ayar.gecmis = true }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    anahtarDugme("modal yok", acik: ayar.modal == nil, renk: Tema.modal) { ayar.modal = nil }
                    ForEach(Motor.modallar, id: \.self) { m in
                        anahtarDugme(Motor.modalBicim(m, gecmis: ayar.gecmis), acik: ayar.modal == m, renk: Tema.modal) { ayar.modal = m }
                    }
                }
            }
            HStack(spacing: 8) {
                kutuAnahtar("have + V3", alt: "geriye bakış", acik: ayar.perfect, renk: Tema.perfect) { ayar.perfect.toggle() }
                kutuAnahtar("be + -ing", alt: "süren", acik: ayar.surec, renk: Tema.surec) { ayar.surec.toggle() }
                kutuAnahtar("be + V3", alt: "edilgen", acik: ayar.edilgen, renk: Tema.edilgen) { ayar.edilgen.toggle() }
            }
        }
        .kart(14)
    }

    private func anahtarDugme(_ ad: String, acik: Bool, renk: Color, _ eylem: @escaping () -> Void) -> some View {
        Button {
            Dokunus.secim()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { eylem() }
            denetle()
        } label: {
            Text(ad).font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).frame(minHeight: 40).frame(maxWidth: ad.count < 8 ? .infinity : nil)
                .background(Capsule().fill(acik ? renk : renk.opacity(0.1)))
                .foregroundStyle(acik ? .white : renk)
        }
        .buttonStyle(.plain)
        .contentTransition(.interpolate)
    }

    private func kutuAnahtar(_ ad: String, alt: String, acik: Bool, renk: Color, _ eylem: @escaping () -> Void) -> some View {
        Button {
            Dokunus.orta()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { eylem() }
            denetle()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: acik ? "power.circle.fill" : "power.circle").font(.title2)
                Text(ad).font(.system(.footnote, design: .monospaced).weight(.bold))
                Text(alt).font(.caption2)
            }
            .frame(maxWidth: .infinity, minHeight: 86)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(acik ? renk : renk.opacity(0.1)))
            .foregroundStyle(acik ? .white : renk)
        }
        .buttonStyle(BasinStil())
    }
}
