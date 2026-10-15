// Vault: köken halkası, 26 haftalık ısı haritası (dokun → o gün), son dokunulan notlar,
// bu haftanın klasörleri, değişiklik günlüğü.
import SwiftUI
import Charts

struct VaultEkrani: View {
    @EnvironmentObject var depo: VeriDeposu
    @State private var suzgec = "hepsi"

    var body: some View {
        let v = depo.veri?.vault
        Ekran {
            EkranBasligi(ust: "Personel Data Management", baslik: "Vault",
                         alt: "\(Bicim.sayi(v?.toplam_not)) not · \(Bicim.kisa(v?.toplam_kelime)) kelime")
            if let h = v?.hata {
                BolumHatasi(ad: "Vault", hata: h)
            } else if let v {
                KokenKarti(v: v).belirerek()
                IsiHaritasi(gunler: v.gunler ?? []).belirerek()
                SonNotlar(notlar: v.son ?? [], suzgec: $suzgec)
                KlasorKarti(klasorler: v.klasorler ?? []).belirerek()
                if let k = v.kayitlar, !k.isEmpty { KayitListesi(baslik: "Değişiklik günlüğü", kayitlar: k, renk: T.vault) }
            }
        }
    }
}

// MARK: - Köken

struct KokenKarti: View {
    let v: VaultBolum
    @State private var ciz = false
    @Environment(\.statik) private var statik

    var body: some View {
        let ciz = self.ciz || statik
        let k = v.koken ?? [:]
        let dilim = ["ben", "yz", "dis", "ortak", "belirsiz"].map { ($0, k[$0] ?? 0) }.filter { $0.1 > 0 }
        let toplam = max(1, dilim.reduce(0) { $0 + $1.1 })
        KartKutu {
            HStack(spacing: 18) {
                ZStack {
                    Chart(dilim, id: \.0) { d in
                        SectorMark(angle: .value("n", ciz ? d.1 : (d.0 == "belirsiz" ? 1 : 0)),
                                   innerRadius: .ratio(0.62), angularInset: 1.5)
                            .foregroundStyle(T.koken(d.0)).cornerRadius(4)
                    }
                    VStack(spacing: 0) {
                        Text("%\(Int((Double(k["ben"] ?? 0) / Double(toplam) * 100).rounded()))")
                            .font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(T.vault)
                        Text("senin").font(.caption2).foregroundStyle(T.soluk)
                    }
                }
                .frame(width: 118, height: 118)
                VStack(alignment: .leading, spacing: 7) {
                    Text("Kim yazdı").font(.headline)
                    ForEach(dilim, id: \.0) { d in
                        HStack(spacing: 8) {
                            Circle().fill(T.koken(d.0)).frame(width: 9, height: 9)
                            Text(T.kokenAd(d.0)).font(.subheadline)
                            Spacer()
                            Text(Bicim.sayi(d.1)).font(.subheadline.monospacedDigit()).foregroundStyle(T.yumusak)
                        }
                    }
                }
            }
            Divider().overlay(T.cizgi).padding(.vertical, 10)
            HStack {
                BuyukSayi(deger: Bicim.kisa(v.baglar), etiket: "bağ")
                BuyukSayi(deger: Bicim.sayi(v.kirik), etiket: "kırık bağlı not", renk: T.idrak)
                BuyukSayi(deger: "\(v.bugun?.yeni ?? 0)", etiket: "bugün doğan", renk: T.vault)
            }
        }
        .onAppear { withAnimation(.easeInOut(duration: 1).delay(0.1)) { self.ciz = true } }
    }
}

// MARK: - Isı haritası

struct IsiHaritasi: View {
    let gunler: [VaultGun]
    @State private var kip = 0          // 0 sen · 1 YZ · 2 hepsi
    @State private var secili: VaultGun?
    @State private var goster = false
    @Environment(\.statik) private var statik

    var body: some View {
        let goster = self.goster || statik
        let haftalar = haftala(gunler)
        let mx = max(1, gunler.map(deger).max() ?? 1)
        let renk = kip == 1 ? T.soluk : T.vault
        KartKutu {
            HStack {
                Text("Son 26 hafta").font(.headline)
                Spacer()
                Picker("", selection: $kip.animation(T.yay)) {
                    Text("Sen").tag(0); Text("YZ").tag(1); Text("Hepsi").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
            }
            GeometryReader { g in
                let k = (g.size.width - CGFloat(haftalar.count - 1) * 2.5) / CGFloat(max(1, haftalar.count))
                HStack(alignment: .top, spacing: 2.5) {
                    ForEach(Array(haftalar.enumerated()), id: \.offset) { hi, hafta in
                        VStack(spacing: 2.5) {
                            ForEach(Array(hafta.enumerated()), id: \.offset) { _, gun in
                                let d = gun.map(deger) ?? 0
                                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                    .fill(gun == nil ? .clear : d == 0 ? T.tint : renk.opacity(0.25 + 0.75 * min(1, Double(d) / Double(mx) * 1.6)))
                                    .overlay(RoundedRectangle(cornerRadius: 2.5).strokeBorder(T.murekkep, lineWidth: gun != nil && gun?.id == secili?.id ? 1.5 : 0))
                                    .frame(width: k, height: k)
                                    .onTapGesture { if let gun { withAnimation(T.yay) { secili = gun } } }
                            }
                        }
                        .opacity(goster ? 1 : 0)
                        .offset(y: goster ? 0 : 8)
                        .animation(.spring(response: 0.45, dampingFraction: 0.8).delay(Double(hi) * 0.02), value: goster)
                    }
                }
            }
            .frame(height: hucreYuksekligi)
            .padding(.top, 8)
            .sensoryFeedback(.selection, trigger: secili)
            Group {
                if let s = secili {
                    HStack(spacing: 14) {
                        Text(Bicim.kisaTarih(s.tarih)).font(.subheadline.weight(.semibold))
                        Label("\(s.ben)", systemImage: "person.fill").foregroundStyle(T.vault)
                        Label("\(s.yz)", systemImage: "sparkles").foregroundStyle(T.soluk)
                        Label("\(s.yeni) yeni", systemImage: "plus.circle").foregroundStyle(T.yumusak)
                        Spacer()
                    }
                    .font(.footnote)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    Text("Bir güne dokun · kare = o gün dokunulan not").font(.caption).foregroundStyle(T.soluk)
                }
            }
            .padding(.top, 8)
        }
        .onAppear { self.goster = true }
    }

    var hucreYuksekligi: CGFloat { 7 * 11 + 6 * 2.5 }

    func deger(_ g: VaultGun) -> Int { kip == 0 ? g.ben : kip == 1 ? g.yz : g.toplam }

    /// Pazartesi başlayan haftalar; ilk haftanın boş günleri nil.
    func haftala(_ g: [VaultGun]) -> [[VaultGun?]] {
        guard let ilk = g.first, let d = Bicim.gun(ilk.tarih) else { return [] }
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let bos = (cal.component(.weekday, from: d) + 5) % 7
        var hucre: [VaultGun?] = Array(repeating: nil, count: bos) + g.map { Optional($0) }
        while hucre.count % 7 != 0 { hucre.append(nil) }
        return stride(from: 0, to: hucre.count, by: 7).map { Array(hucre[$0..<$0 + 7]) }
    }
}

// MARK: - Son notlar

struct SonNotlar: View {
    let notlar: [VaultNot]
    @Binding var suzgec: String
    @State private var hepsi = false

    var body: some View {
        let l = notlar.filter { suzgec == "hepsi" || $0.koken == suzgec }
        let gosterilen = hepsi ? l : Array(l.prefix(8))
        BolumBasligi(baslik: "Son dokunulanlar")
        HStack(spacing: 8) {
            Group {
                ForEach([("hepsi", "Hepsi"), ("ben", "Sen"), ("yz", "YZ"), ("dis", "Dış")], id: \.0) { k, ad in
                    Button { withAnimation(T.yay) { suzgec = k } } label: {
                        Text(ad).font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(suzgec == k ? T.vault : T.yuzey, in: Capsule())
                            .foregroundStyle(suzgec == k ? .white : T.murekkep)
                            .overlay(Capsule().strokeBorder(T.cizgi, lineWidth: suzgec == k ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: suzgec)
        KartKutu(dolgu: 6) {
            if gosterilen.isEmpty {
                BosDurum(simge: "doc.text.magnifyingglass", metin: "Bu süzgeçte not yok.")
            }
            VStack(spacing: 0) {
                ForEach(Array(gosterilen.enumerated()), id: \.element.id) { i, n in
                    NotSatiri(not: n)
                    if i < gosterilen.count - 1 { Divider().padding(.leading, 44) }
                }
                if l.count > 8 {
                    Button(hepsi ? "Daha az" : "Tümünü göster (\(l.count))") { withAnimation(T.yay) { hepsi.toggle() } }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(T.vault).padding(12)
                }
            }
        }
    }
}

struct NotSatiri: View {
    let not: VaultNot
    @State private var acik = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: simge)
                .font(.footnote.weight(.semibold))
                .frame(width: 28, height: 28)
                .background(T.koken(not.koken).opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(not.koken == "ben" ? T.vault : T.yumusak)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(not.ad).font(.subheadline.weight(.medium)).lineLimit(1)
                    if not.yeni == true { Rozet(metin: "yeni", renk: T.vault) }
                }
                Text("\(not.klasor ?? "") · \(Bicim.once(not.zaman)) · \(T.kokenAd(not.koken))")
                    .font(.caption).foregroundStyle(T.soluk).lineLimit(1)
                if acik {
                    if let o = not.ozet, !o.isEmpty { Text(o).font(.footnote).foregroundStyle(T.yumusak).padding(.top, 4) }
                    Text(not.yol).font(.caption2.monospaced()).foregroundStyle(T.soluk).padding(.top, 2)
                    Text("\(Bicim.sayi(not.kelime)) kelime").font(.caption2).foregroundStyle(T.soluk)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(T.yay) { acik.toggle() } }
        .contextMenu {
            if let u = obsidianURL { Link(destination: u) { Label("Obsidian'da aç", systemImage: "arrow.up.forward.app") } }
        }
    }

    var simge: String {
        switch not.tur {
        case "gunluk": return "calendar"
        default: return not.koken == "ben" ? "pencil" : not.koken == "yz" ? "sparkles" : "doc.text"
        }
    }

    /// obsidian://open?vault=…&file=… — Obsidian iPhone'da kuruluysa notu doğrudan açar.
    var obsidianURL: URL? {
        var c = URLComponents()
        c.scheme = "obsidian"
        c.host = "open"
        c.queryItems = [URLQueryItem(name: "vault", value: "Personel Data Management"),
                        URLQueryItem(name: "file", value: String(not.yol.dropLast(not.yol.hasSuffix(".md") ? 3 : 0)))]
        return c.url
    }
}

// MARK: - Klasörler

struct KlasorKarti: View {
    let klasorler: [Klasor]
    var body: some View {
        let mx = Double(max(1, klasorler.map(\.hafta).max() ?? 1))
        KartKutu {
            HStack {
                Text("Bu hafta hangi alanlar").font(.headline)
                Spacer()
                Text("7 gün").font(.footnote).foregroundStyle(T.soluk)
            }
            VStack(spacing: 6) {
                ForEach(klasorler.filter { $0.hafta > 0 }.prefix(8)) { k in
                    OranSatiri(ad: k.ad, deger: "\(k.hafta) / \(k.not)", oran: Double(k.hafta) / mx, renk: T.vault)
                }
            }
            .padding(.top, 8)
        }
    }
}
