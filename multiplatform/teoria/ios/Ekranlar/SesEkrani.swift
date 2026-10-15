// Sesli notlar: bir fikri kendi sesinle anlat. Amaç hatırlamak ve yorum yapabilmek.
// Not cihaza yazılır → vault'a gider → Mac'te yazıya dökülür → Claude değerlendirir → değerlendirme buraya döner.
import SwiftUI

struct SesKayitSayfasi: View {
    @EnvironmentObject var depo: Depo
    @Environment(\.dismiss) private var kapat
    let hedef: String?
    @StateObject private var ses = SesKayit()
    @State private var yaziNot = ""
    @State private var yaziKipi = false
    @State private var goster = false
    @State private var bakti = false

    var hedefMetni: (String, String)? {
        guard let h = hedef else { return nil }
        if let i = depo.isaret(h) { return (i.metin, i.baslik) }
        if let k = depo.paket.kavram(h) { return ("\(k.terim): \(k.tanim)", depo.paket.kitap(k.kitap)?.baslik ?? "") }
        if let a = depo.paket.aforizmalar.first(where: { $0.id == h }) { return (a.metin, a.kaynak) }
        return nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                if let (m, k) = hedefMetni {
                    // Yeniden üretim: metin kapalı gelir; kayıt sürerken açılamaz.
                    HatirlamaPerdesi(acik: $goster, bakti: $bakti, kilitli: ses.hal == .kayit,
                                     ipucu: HatirlamaPerdesi<EmptyView>.ilkKelimeler(m)) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(m).font(Tema.serif(.body)).foregroundStyle(Tema.metin).lineLimit(6)
                            Text(k).font(.caption).foregroundStyle(Tema.soluk)
                        }
                        .padding(16).tamGenislik()
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Tema.yuzey))
                    }
                }
                Text(hedef == nil ? "Aklındaki fikri anlat: ne düşünüyorsun, neden?" :
                        "Metne bakmadan anlat: ne diyordu, sen ne diyorsun?")
                    .font(Tema.serif(.title3)).multilineTextAlignment(.center).foregroundStyle(Tema.ikincil)

                if yaziKipi {
                    TextEditor(text: $yaziNot).font(Tema.serif(.title3)).scrollContentBackground(.hidden)
                        .padding(12).frame(minHeight: 180)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Tema.yuzey))
                    Button("Notu kaydet") {
                        depo.ekle(Olay(tur: .kendiCumle, hedef: hedef, deger: hedef == nil ? nil : bakti, metin: yaziNot,
                                       rol: hedef == nil ? nil : "fikir"))
                        kapat()
                    }
                    .buttonStyle(AnaDugme()).disabled(yaziNot.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                } else {
                    Spacer()
                    dalga
                    Text(SesKayit.sureYazi(ses.sure) + " / 3:00").font(.system(.title2, design: .rounded).weight(.semibold))
                        .monospacedDigit().foregroundStyle(Tema.metin)
                    kayitDugmesi
                    durumYazisi
                    Spacer()
                    if ses.hal == .bitti, let u = ses.dosya {
                        HStack(spacing: 10) {
                            Button { ses.cal(u, kimlik: "onizleme") } label: {
                                Label(ses.calan == "onizleme" ? "Durdur" : "Dinle", systemImage: ses.calan == "onizleme" ? "stop.fill" : "play.fill")
                            }.buttonStyle(IkinciDugme())
                            Button(role: .destructive) { ses.vazgec() } label: { Label("Sil", systemImage: "trash") }
                                .buttonStyle(IkinciDugme(renk: Tema.uyari))
                        }
                        Button("Kaydet · \(SesKayit.boyut(u))") {
                            depo.ekle(Olay(tur: .sesNot, hedef: hedef, deger: hedef == nil ? nil : bakti,
                                           metin: u.lastPathComponent, sure: ses.sure))
                            depo.esitle(gecikme: 1)
                            ses.sifirla()
                            kapat()
                        }
                        .buttonStyle(AnaDugme())
                    }
                }
            }
            .padding(20)
            .background(Tema.arka.ignoresSafeArea())
            .navigationTitle("Sesli not")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { ses.vazgec(); kapat() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { yaziKipi.toggle() } label: { Image(systemName: yaziKipi ? "mic" : "keyboard") }
                        .accessibilityLabel(yaziKipi ? "Sesle not" : "Yazarak not")
                }
            }
        }
        .onDisappear { if ses.hal == .kayit { ses.durdur() } }
    }

    private var dalga: some View {
        HStack(alignment: .center, spacing: 3) {
            let s = ses.seviyeler.suffix(48)
            ForEach(Array(s.enumerated()), id: \.offset) { _, v in
                Capsule().fill(Tema.vurgu.opacity(0.4 + Double(v) * 0.6))
                    .frame(width: 4, height: max(4, CGFloat(v) * 70))
            }
            if s.isEmpty { Capsule().fill(Tema.cizgi).frame(height: 4) }
        }
        .frame(height: 76)
        .animation(.linear(duration: 0.1), value: ses.seviyeler.count)
    }

    private var kayitDugmesi: some View {
        Button {
            switch ses.hal {
            case .kayit: Dokunus.kayit(false); ses.durdur()
            case .bitti: break
            default: Dokunus.kayit(true); Task { await ses.baslat(klasor: depo.sesKlasoru) }
            }
        } label: {
            ZStack {
                Circle().fill(Tema.uyari.opacity(0.15)).frame(width: 96, height: 96)
                    .scaleEffect(ses.hal == .kayit ? 1 + CGFloat(ses.seviye) * 0.25 : 1)
                if ses.hal == .kayit {
                    RoundedRectangle(cornerRadius: 8).fill(Tema.uyari).frame(width: 32, height: 32)
                } else {
                    Circle().fill(ses.hal == .bitti ? Tema.soluk : Tema.uyari).frame(width: 64, height: 64)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(ses.hal == .bitti)
        .accessibilityLabel(ses.hal == .kayit ? "Kaydı durdur" : "Kaydı başlat")
    }

    @ViewBuilder
    private var durumYazisi: some View {
        switch ses.hal {
        case .izinYok:
            Text("Mikrofon izni yok. Ayarlar › Teoria › Mikrofon. O zamana kadar ⌨︎ ile yazarak not alabilirsin.")
                .font(.footnote).multilineTextAlignment(.center).foregroundStyle(Tema.uyari)
        case .hata(let h):
            Text(h).font(.footnote).multilineTextAlignment(.center).foregroundStyle(Tema.uyari)
        case .kayit:
            Text("Konuş; 3 dakikada kendiliğinden durur.").font(.footnote).foregroundStyle(Tema.soluk)
        case .bitti:
            Text("Dinle, istersen sil, sonra kaydet.").font(.footnote).foregroundStyle(Tema.soluk)
        case .bos:
            Text("Dokun ve anlat. Az yer kaplar: dakikası ~180 KB.").font(.footnote).foregroundStyle(Tema.soluk)
        }
    }
}

// MARK: - Sesli not satırı

struct SesSatiri: View {
    @EnvironmentObject var depo: Depo
    @StateObject private var oynatici = SesKayit()
    let olay: Olay
    @State private var acik = false

    var bilgi: SesBilgisi? { depo.sesler[olay.id] }
    var dosya: URL { depo.sesKlasoru.appendingPathComponent(olay.metin ?? "") }

    var body: some View {
        Yuzey {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Button { oynatici.cal(dosya, kimlik: olay.id) } label: {
                        Image(systemName: oynatici.calan == olay.id ? "stop.fill" : "play.fill")
                            .font(.system(size: 15, weight: .bold)).frame(width: 40, height: 40)
                            .background(Circle().fill(Tema.vurgu.opacity(0.14))).foregroundStyle(Tema.vurgu)
                    }
                    .buttonStyle(.plain)
                    .disabled(!FileManager.default.fileExists(atPath: dosya.path))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Sesli not · \(SesKayit.sureYazi(olay.sure ?? 0))").font(.subheadline.weight(.semibold)).foregroundStyle(Tema.metin)
                        Text(Tarih.goreli(olay.t)).font(.caption).foregroundStyle(Tema.soluk)
                    }
                    Spacer()
                    durumHapi
                }
                if let h = olay.hedef, let i = depo.isaret(h) {
                    Text("↳ " + i.metin).font(.footnote).foregroundStyle(Tema.ikincil).lineLimit(2)
                }
                if let d = bilgi?.degerlendirme {
                    degerlendirme(d)
                }
                if acik, let t = bilgi?.dokum {
                    Text(t).font(Tema.serif(.callout)).foregroundStyle(Tema.metin).textSelection(.enabled)
                        .padding(12).background(RoundedRectangle(cornerRadius: 14).fill(Tema.yuzey2))
                }
                if bilgi?.dokum != nil {
                    Button(acik ? "Dökümü gizle" : "Dökümü göster") { withAnimation(.snappy) { acik.toggle() } }
                        .font(.footnote.weight(.semibold))
                }
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                try? FileManager.default.removeItem(at: dosya)
                depo.ekle(Olay(tur: .sesSil, hedef: olay.id))
            } label: { Label("Bu notu sil", systemImage: "trash") }
        }
    }

    @ViewBuilder
    private var durumHapi: some View {
        if bilgi?.degerlendirme != nil { Hap(metin: "değerlendirildi", renk: Tema.basari) }
        else if bilgi?.dokum != nil { Hap(metin: "yazıya döküldü", renk: Tema.vurgu) }
        else if bilgi?.vaultta == true { Hap(metin: "vault'ta", renk: Tema.ikincil) }
        else { Hap(metin: "cihazda", renk: Tema.soluk) }
    }

    private func degerlendirme(_ d: SesDegerlendirme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(d.ozet).font(Tema.serif(.callout)).foregroundStyle(Tema.metin)
            HStack(spacing: 16) {
                if let h = d.hatirlama { puan("Hatırlama", h) }
                if let y = d.yorum { puan("Yorum", y) }
            }
            ForEach(d.guclu ?? [], id: \.self) { Label($0, systemImage: "plus.circle").font(.footnote).foregroundStyle(Tema.basari) }
            ForEach(d.eksik ?? [], id: \.self) { Label($0, systemImage: "circle.dashed").font(.footnote).foregroundStyle(Tema.uyari) }
            if let s = d.soru { Label(s, systemImage: "questionmark.bubble").font(.footnote.weight(.medium)).foregroundStyle(Tema.vurgu) }
        }
        .padding(12).tamGenislik()
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Tema.basari.opacity(0.07)))
    }

    private func puan(_ ad: String, _ p: Int) -> some View {
        HStack(spacing: 4) {
            Text(ad).font(.caption.weight(.semibold)).foregroundStyle(Tema.ikincil)
            ForEach(1...5, id: \.self) { i in Circle().fill(i <= p ? Tema.basari : Tema.cizgi).frame(width: 6, height: 6) }
        }
    }
}

struct SesListesi: View {
    @EnvironmentObject var depo: Depo
    var sesAc: (String?) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Button { sesAc(nil) } label: { Label("Yeni sesli not", systemImage: "mic.fill") }
                        .buttonStyle(AnaDugme(renk: Tema.uyari))
                    Text("Bir fikri kendi sesinle anlatmak, onu hatırlamanın ve yorumlamanın en kısa yolu. Notlar Mac'te yazıya dökülür ve değerlendirilir; değerlendirme buraya döner.")
                        .font(.footnote).foregroundStyle(Tema.ikincil)
                    if depo.durum.sesNotlari.isEmpty {
                        Text("Henüz sesli not yok.").font(.subheadline).foregroundStyle(Tema.soluk).padding(.vertical, 30)
                    }
                    ForEach(depo.durum.sesNotlari) { SesSatiri(olay: $0) }
                }
                .padding(18)
                .frame(maxWidth: 720).frame(maxWidth: .infinity)
            }
            .background(Tema.arka.ignoresSafeArea())
            .navigationTitle("Sesli notlar")
            .refreshable { await depo.esitleSimdi() }
        }
    }
}
