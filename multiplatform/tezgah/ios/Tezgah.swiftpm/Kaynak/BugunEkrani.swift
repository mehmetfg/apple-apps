// Bugün: etkinlik halkaları, sayfa sayfa kayan tezgâh kartları, vault'un bugünü, son dört hafta.
import SwiftUI

struct BugunEkrani: View {
    @EnvironmentObject var depo: VeriDeposu
    @Environment(\.sekmeyeGit) private var git
    @State private var muhendisAcik = false
    @State private var secili: String?

    var body: some View {
        let b = depo.veri?.bugun
        Ekran {
            EkranBasligi(ust: Bicim.uzunTarih(Date()), baslik: "Bugün", alt: ozet(b))
            if let h = b?.hata {
                BolumHatasi(ad: "Pano", hata: h)
            } else if let b {
                HalkaKarti(aktivite: b.aktivite ?? [], git: git)
                    .belirerek()
                KartSeridi(kartlar: b.kartlar ?? [], secili: $secili) { k in
                    switch k.kod {
                    case "cumle": git(.ingilizce)
                    case "idrak": git(.idrak)
                    default: muhendisAcik = true
                    }
                }
                VaultBugunKarti().belirerek()
                    .onTapGesture { git(.vault) }
                DortHafta(aktivite: b.aktivite ?? []).belirerek()
            }
        }
        .sheet(isPresented: $muhendisAcik) {
            MuhendisSayfasi().presentationDetents([.medium, .large]).presentationCornerRadius(28)
        }
    }

    func ozet(_ b: BugunBolum?) -> String {
        let n = (b?.kartlar ?? []).filter { $0.durum == "bekliyor" || $0.durum == "suruyor" }.count
        return n == 0 ? "Bugünün işi tamam." : "\(n) masa seni bekliyor."
    }
}

// MARK: - Halkalar

struct HalkaKarti: View {
    let aktivite: [Aktivite]
    let git: (Sekme) -> Void

    var body: some View {
        KartKutu {
            HStack(spacing: 18) {
                ZStack {
                    ForEach(Array(aktivite.prefix(4).enumerated()), id: \.element.id) { i, a in
                        Halka(oran: Double(a.toplam ?? 0) / 28, renk: T.renk(a.kod), kalinlik: 11)
                            .padding(CGFloat(i) * 14)
                    }
                }
                .frame(width: 128, height: 128)
                VStack(alignment: .leading, spacing: 9) {
                    Text("Son 28 gün").font(.caption.weight(.semibold)).foregroundStyle(T.soluk)
                    ForEach(aktivite.prefix(4)) { a in
                        Button { git(sekme(a.kod)) } label: {
                            HStack(spacing: 8) {
                                Circle().fill(T.renk(a.kod)).frame(width: 8, height: 8)
                                Text(a.ad ?? a.kod).font(.subheadline.weight(.medium)).foregroundStyle(T.murekkep)
                                Spacer(minLength: 4)
                                Text("\(a.toplam ?? 0)")
                                    .font(.system(.subheadline, design: .rounded).weight(.bold).monospacedDigit())
                                    .foregroundStyle(T.renk(a.kod))
                                + Text(" gün").font(.caption).foregroundStyle(T.soluk)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    func sekme(_ kod: String) -> Sekme {
        switch kod {
        case "cumle": return .ingilizce
        case "idrak": return .idrak
        case "vault": return .vault
        default: return .bugun
        }
    }
}

// MARK: - Kart şeridi (yatay, sayfa sayfa oturur)

struct KartSeridi: View {
    let kartlar: [Kart]
    @Binding var secili: String?
    let ac: (Kart) -> Void

    var body: some View {
        VStack(spacing: 10) {
            Serit(ogeler: kartlar, konum: $secili) { k in
                TezgahKarti(kart: k)
                    .modifier(SeritGenisligi())
                    .modifier(SeritGecisi())
                    .onTapGesture { ac(k) }
            }
            HStack(spacing: 7) {
                ForEach(kartlar) { k in
                    Capsule()
                        .fill(k.kod == (secili ?? kartlar.first?.kod) ? T.renk(k.kod) : T.cizgi)
                        .frame(width: k.kod == (secili ?? kartlar.first?.kod) ? 20 : 7, height: 7)
                }
            }
            .animation(T.yay, value: secili)
        }
        .padding(.horizontal, -16)
    }
}

struct TezgahKarti: View {
    let kart: Kart

    var body: some View {
        let renk = T.renk(kart.kod)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(kart.ad ?? "") · \(kart.alt ?? "")".uppercased(with: Bicim.tr))
                    .font(.caption.weight(.bold)).tracking(0.5).foregroundStyle(renk)
                Spacer()
                DurumRozeti(durum: kart.durum)
            }
            if let h = kart.hata {
                Text(h).font(.footnote).foregroundStyle(T.idrak).padding(.top, 12)
                Spacer(minLength: 0)
            } else {
                Text(kart.baslik ?? "—")
                    .font(.system(size: 28, weight: .bold)).padding(.top, 12)
                Text(kart.is ?? "").font(.headline).lineLimit(2).padding(.top, 4)
                Text(kart.not ?? "").font(.subheadline).foregroundStyle(T.yumusak).lineLimit(2).padding(.top, 2)
                Spacer(minLength: 14)
                if let i = kart.ilerleme {
                    Cubuk(oran: i.oran, renk: renk, kalinlik: 7)
                    Text("\(Int(i.a ?? 0)) / \(Int(i.b ?? 0)) \(i.etiket ?? "")")
                        .font(.caption).foregroundStyle(T.yumusak).padding(.top, 6)
                }
                Divider().overlay(T.cizgi).padding(.vertical, 12)
                HStack {
                    ForEach(kart.sayilar ?? [], id: \.self) { s in
                        BuyukSayi(deger: s.deger ?? "—", etiket: s.etiket ?? "")
                    }
                }
            }
        }
        .padding(20)
        .frame(height: 300)
        .background(
            ZStack(alignment: .topTrailing) {
                T.yuzey
                Circle().fill(renk.opacity(0.14)).frame(width: 220).blur(radius: 50).offset(x: 80, y: -90)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(T.cizgi))
        .shadow(color: renk.opacity(0.12), radius: 16, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 26))
    }
}

// MARK: - Vault'un bugünü

struct VaultBugunKarti: View {
    @EnvironmentObject var depo: VeriDeposu
    var body: some View {
        let v = depo.veri?.vault?.bugun
        KartKutu {
            HStack {
                Label("Vault bugün", systemImage: "square.stack.3d.up.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(T.vault)
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(T.soluk)
            }
            HStack {
                BuyukSayi(deger: "\(v?.yeni ?? 0)", etiket: "not doğdu")
                BuyukSayi(deger: "\(v?.degisen ?? 0)", etiket: "değişti")
                BuyukSayi(deger: "\(v?.ben ?? 0)", etiket: "senin", renk: T.vault)
                BuyukSayi(deger: "\(v?.yz ?? 0)", etiket: "YZ", renk: T.soluk)
            }
            .padding(.top, 10)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Son dört hafta

struct DortHafta: View {
    let aktivite: [Aktivite]
    var body: some View {
        KartKutu {
            Text("Son dört hafta").font(.headline)
            VStack(spacing: 9) {
                ForEach(aktivite) { a in
                    HStack(spacing: 10) {
                        Text(a.ad ?? a.kod).font(.caption.weight(.semibold)).foregroundStyle(T.yumusak)
                            .frame(width: 62, alignment: .leading)
                        IsiSatiri(gunler: a.gunler ?? [], renk: T.renk(a.kod))
                    }
                }
            }
            .padding(.top, 10)
            HStack {
                Text(Bicim.kisaTarih(Calendar.current.date(byAdding: .day, value: -27, to: Date()) ?? Date()))
                Spacer()
                Text("bugün")
            }
            .font(.caption2).foregroundStyle(T.soluk)
            .padding(.leading, 72).padding(.top, 4)
        }
    }
}

// MARK: - Mühendis (yarım sayfa)

struct MuhendisSayfasi: View {
    @EnvironmentObject var depo: VeriDeposu
    var body: some View {
        let m = depo.veri?.muhendis
        Kaydir {
            VStack(alignment: .leading, spacing: 14) {
                Text("MÜHENDİS · GÜNÜN MESELESİ").font(.caption.weight(.bold)).tracking(0.5).foregroundStyle(T.muhendis)
                if let h = m?.hata {
                    BolumHatasi(ad: "Mühendis", hata: h)
                } else {
                    Text(m?.bugun?.id ?? "—").font(.system(size: 30, weight: .bold))
                    Text(m?.bugun?.baslik ?? "").font(.title3.weight(.semibold))
                    if let s = m?.bugun?.soru { Text(s).font(.body).foregroundStyle(T.yumusak) }
                    HStack {
                        BuyukSayi(deger: "\(m?.calisilan ?? 0)/\(m?.toplam ?? 0)", etiket: "mesele", renk: T.muhendis)
                        BuyukSayi(deger: "\(m?.uretilen ?? 0)", etiket: "üretilen")
                        BuyukSayi(deger: "\((m?.alanlar ?? []).filter { $0.calisilan > 0 }.count)/\(m?.alanlar?.count ?? 12)",
                                  etiket: "alan")
                    }
                    .padding(.vertical, 6)
                    Text("Alanlar").font(.headline).padding(.top, 6)
                    ForEach(m?.alanlar ?? []) { a in
                        OranSatiri(ad: a.ad, deger: "\(a.calisilan)/\(a.toplam)",
                                   oran: a.toplam > 0 ? Double(a.calisilan) / Double(a.toplam) : 0, renk: T.muhendis)
                    }
                }
            }
            .padding(24)
        }
        .background(T.zemin.ignoresSafeArea())
    }
}
