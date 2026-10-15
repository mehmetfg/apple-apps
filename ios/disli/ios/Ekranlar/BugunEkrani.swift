// Bugün: tek konu, üç küçük adım (kart · mini quiz · oyun). Seri yok, bekleyen sayısı yok; yarım bırakmak serbest.
import SwiftUI

struct BugunEkrani: View {
    @Environment(Depo.self) private var depo
    let ac: (Acilan) -> Void
    let sekmeyeGit: (Int) -> Void
    @State private var ayarlar = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let k = depo.gununKonusu {
                        KahramanKart(konu: k) { ac(.konu(k.id)) }
                        adimlar(k)
                        if !depo.donenKonular.isEmpty { donenler }
                    }
                    miniHarita
                    Text("Vade yok, seri yok. Ara verdiğinde hiçbir şey birikmez; kaldığın konudan devam edersin.")
                        .font(.footnote).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
            .background(Lekeler(renkler: [depo.gununKonusu.map { depo.renk($0) } ?? Tema.vurgu, Tema.renk("turuncu")]))
            .navigationTitle(tarihBasligi)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { ayarlar = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Ayarlar")
                }
            }
            .sheet(isPresented: $ayarlar) { AyarlarEkrani() }
        }
    }

    private var tarihBasligi: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR"); f.dateFormat = "d MMMM"
        return f.string(from: .now)
    }

    // MARK: Üç adım

    @ViewBuilder
    private func adimlar(_ k: Konu) -> some View {
        let renk = depo.renk(k)
        let oyun = Oyun.oneri(k)
        VStack(spacing: 10) {
            AdimSatiri(no: 1, baslik: "Kartı aç", alt: "Fikir · formül · örnek · tuzak · bağlar", cizim: "adim-kart",
                       renk: renk, bitti: depo.durum.bugunBitti.contains("kart")) { ac(.konu(k.id)) }
            AdimSatiri(no: 2, baslik: "Mini quiz", alt: "5 soru · bugünün konusu + geri dönenler", cizim: "adim-quiz",
                       renk: renk, bitti: depo.durum.bugunBitti.contains("quiz")) {
                ac(.quiz(depo.gununQuizi(), gunluk: true))
            }
            AdimSatiri(no: 3, baslik: oyun.ad, alt: oyun.neden(k, depo), cizim: "oyun-" + oyun.rawValue,
                       renk: oyun.renk, bitti: depo.durum.bugunBitti.contains("oyun")) { ac(.oyun(oyun)) }
        }
    }

    private var donenler: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bugün yine uğrayanlar").font(Tema.baslik(.headline))
            Text("Mini quiz'de birer soruyla dönerler.").font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(depo.donenKonular.prefix(8)) { k in
                        Button { ac(.konu(k.id)) } label: {
                            HStack(spacing: 6) {
                                KademeHalkasi(kademe: depo.kademe(k.id), renk: depo.renk(k), boy: 16)
                                Text(k.tr).font(.subheadline.weight(.medium)).lineLimit(1)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(Tema.yuzey))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: 60 dişlinin küçük haritası (ölçüm değil, aşinalığın görüntüsü)

    private var miniHarita: some View {
        Button { sekmeyeGit(1) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Aşinalık").font(Tema.baslik(.headline))
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                ForEach(depo.veri.bolgeler) { b in
                    HStack(spacing: 10) {
                        Text(b.ad).font(.caption2).foregroundStyle(.secondary).lineLimit(1).frame(width: 92, alignment: .leading)
                        HStack(spacing: 4) {
                            ForEach(depo.konular(bolge: b.id)) { k in
                                let kad = depo.kademe(k.id)
                                Circle()
                                    .fill(kad == 0 ? Color(.tertiarySystemFill) : Tema.renk(b.renk).opacity(0.25 + 0.19 * Double(kad)))
                                    .frame(width: 11, height: 11)
                                    .overlay(Circle().stroke(k.id == depo.durum.gununKonusu ? Color.primary : .clear, lineWidth: 1.5))
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                HStack(spacing: 14) {
                    ForEach(1..<5) { i in
                        HStack(spacing: 4) {
                            Circle().fill(Tema.vurgu.opacity(0.25 + 0.19 * Double(i))).frame(width: 8, height: 8)
                            Text(Tema.kademeAdi(i)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .kart()
        }
        .buttonStyle(.plain)
    }
}

struct KahramanKart: View {
    @Environment(Depo.self) private var depo
    let konu: Konu
    let ac: () -> Void

    var body: some View {
        let renk = depo.renk(konu)
        Button(action: ac) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    NoktaEtiket(metin: depo.bolge(konu.bolge)?.ad ?? "", renk: renk)
                        .font(.caption.weight(.bold)).textCase(.uppercase).foregroundStyle(renk)
                    Spacer()
                    KademeHalkasi(kademe: depo.kademe(konu.id), renk: renk, boy: 28)
                }
                Text("Bugünün konusu").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Text(konu.tr).font(.system(.largeTitle, design: .rounded).weight(.bold)).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(konu.ad).font(Tema.ingilizce(.title3).italic()).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(konu.imge).font(.callout).foregroundStyle(.primary.opacity(0.85))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Tema.yuzey.opacity(0.7)))
                Akis(aralik: 6, satirAraligi: 6, ortala: false) {
                    ForEach(konu.yasalar, id: \.id) { ky in
                        if let y = depo.yasa(ky.id) {
                            YasaRozeti(yasa: y, kucuk: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
            .background(
                ZStack {
                    Tema.yuzey
                    LinearGradient(colors: [renk.opacity(0.20), renk.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(renk.opacity(0.18)))
            .shadow(color: renk.opacity(0.12), radius: 14, y: 8)
        }
        .buttonStyle(.plain)
    }
}

struct AdimSatiri: View {
    let no: Int
    let baslik: String
    let alt: String
    let cizim: String
    let renk: Color
    let bitti: Bool
    let eylem: () -> Void

    var body: some View {
        Button(action: { Dokunus.hafif(); eylem() }) {
            HStack(spacing: 14) {
                ZStack {
                    if bitti {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Tema.dogru.opacity(0.85)).frame(width: 48, height: 48)
                        Image(systemName: "checkmark").font(.title3.weight(.semibold)).foregroundStyle(.white)
                    } else {
                        Cizim(ad: cizim, renk: renk, boy: 48)
                    }
                }
                .animation(.snappy, value: bitti)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(no) · \(baslik)").font(.headline)
                    Text(alt).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .kart(14, yaricap: 20)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Ayarlar

struct AyarlarEkrani: View {
    @Environment(Depo.self) private var depo
    @Environment(\.dismiss) private var kapat
    @State private var sifirSor = false

    var body: some View {
        @Bindable var depo = depo
        NavigationStack {
            Form {
                Section("Ses ve dokunuş") {
                    Toggle("İngilizce cümleleri seslendir", isOn: $depo.durum.ayar.ses)
                    VStack(alignment: .leading) {
                        Text("Konuşma hızı").font(.subheadline)
                        Slider(value: $depo.durum.ayar.sesHizi, in: 0.32...0.58) { Text("Hız") } onEditingChanged: { bitti in
                            if !bitti { return }
                            Ses.hiz = Float(depo.durum.ayar.sesHizi); Ses.konus("This is how fast I will speak.")
                        }
                    }
                    Toggle("Titreşim", isOn: $depo.durum.ayar.haptik)
                }
                Section("Görünüm") {
                    Picker("Tema", selection: $depo.durum.ayar.gorunum) {
                        Text("Sistem").tag(0); Text("Açık").tag(1); Text("Koyu").tag(2)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    LabeledContent("Konu", value: "\(depo.veri.konular.count)")
                    LabeledContent("Soru", value: "\(depo.veri.konular.reduce(0) { $0 + $1.sorular.count })")
                    LabeledContent("Yasa", value: "\(depo.veri.yasalar.count)")
                    LabeledContent("Tamamlanan oturum", value: "\(depo.durum.oturum)")
                } header: { Text("GramerApp") } footer: {
                    Text("41 konu Cümle Tezgâhı'nın gramer kartlarından, 19'u bu uygulamada yazıldı. Bir konu tanımada üç kez tutunca ona artık şık sorusu gelmez; yalnız kurdurulur.")
                }
                Section {
                    Button("İlerlemeyi sıfırla", role: .destructive) { sifirSor = true }
                }
            }
            .navigationTitle("Ayarlar")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { kapat() } } }
            .confirmationDialog("Bütün aşinalık kayıtları silinsin mi?", isPresented: $sifirSor, titleVisibility: .visible) {
                Button("Sıfırla", role: .destructive) { depo.sifirla() }
            }
            .onChange(of: depo.durum.ayar.ses) { _, v in Ses.acik = v }
            .onChange(of: depo.durum.ayar.haptik) { _, v in Dokunus.acik = v }
            .onChange(of: depo.durum.ayar.sesHizi) { _, v in Ses.hiz = Float(v) }
        }
    }
}
