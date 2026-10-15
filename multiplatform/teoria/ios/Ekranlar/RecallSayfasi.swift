// Recall — kapat · çağır · karşılaştır · yeniden kur. Bir işaretin "gördüm, tanıdım" olmaktan çıkıp "üretebiliyorum" olması için.
//   1 · ÇAĞIR       metin tamamen kapalı; zihninden, kendi cümlenle yaz (boş bırakmak da dürüst bir cevap)
//   2 · KARŞILAŞTIR asıl metin açılır: yakaladığın kelimeler yeşil, kaçırdıkların turuncu; sen dürüstçe puanlarsın
//   3 · YENİDEN KUR aynı fikri/yapıyı kendi konunda yeni bir cümleyle kur (modele bakmak isteğe bağlı, işaretlenir)
//   4 · FARK        yeni cümlenin asıla ne kadar yakın olduğu: kopya mı, yeniden yaratma mı
// Kayıt (recall defteri = olay günlüğü): recall → `cevap` olayı (rol "recall", FSRS kartı "hatirla:isaret:<id>" ilerler);
// yeniden kurulan cümle → `kendiCumle` (rol "yeniden"). İkisi de Benim sekmesinde ve BEKLEYEN.md değerlendirmesinde görünür.
import SwiftUI
import AVFoundation

struct RecallSayfasi: View {
    @EnvironmentObject var depo: Depo
    @Environment(\.dismiss) private var kapat
    let isaret: Isaret

    private enum Adim { case cagir, karsilastir, kur, fark }
    @State private var adim: Adim = .cagir
    @State private var cagri = ""
    @State private var yeni = ""
    @State private var modeleBaktim = false
    @State private var puan: Double?
    @State private var baslangic = Date()
    @State private var cagriSes: URL?
    @State private var yeniSes: URL?
    @FocusState private var odak: Bool

    private var kr: Color { Tema.kitap(isaret.kitap) }

    // Kelime düzeyinde yakalama: içerik kelimeleri (>3 harf). Türkçe ek alır: iki kelimenin ortak başı
    // en az 4 harf ve kısa olanın neredeyse tamamıysa aynı kök sayılır ("soru" ~ "soruyu", "anlam" ~ "anlamı").
    private var cagriKelimeleri: [String] { Dil.kelimeler(cagri).filter { $0.count > 2 } }
    private var asilKelimeler: [String] { isaret.metin.split(whereSeparator: \.isWhitespace).map(String.init) }
    private func icerik(_ w: String) -> Bool { Dil.normal(w).count > 3 }
    private static func ayniKok(_ a: String, _ b: String) -> Bool {
        let ortak = zip(a, b).prefix { $0 == $1 }.count
        return ortak >= min(5, max(4, min(a.count, b.count) - 1))
    }
    private func yakalandi(_ w: String, _ u: [String]) -> Bool {
        let n = Dil.normal(w).replacingOccurrences(of: " ", with: "")
        return u.contains { Self.ayniKok(n, $0) }
    }
    private var yakalanan: Double {
        let ic = asilKelimeler.filter(icerik)
        guard !ic.isEmpty else { return 0 }
        let u = cagriKelimeleri
        return Double(ic.filter { yakalandi($0, u) }.count) / Double(ic.count)
    }
    private var kacirilan: [String] {
        let u = cagriKelimeleri
        var goruldu = Set<String>(), l: [String] = []
        for w in asilKelimeler where icerik(w) && !yakalandi(w, u) {
            let n = Dil.normal(w)
            if goruldu.insert(n).inserted { l.append(n) }
        }
        return Array(l.prefix(8))
    }
    private var onerilenPuan: Double { let o = yakalanan; return o >= 0.8 ? 1 : (o >= 0.5 ? 0.85 : (o >= 0.2 ? 0.5 : 0)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ilerleme
                    switch adim {
                    case .cagir: cagirAdimi
                    case .karsilastir: karsilastirAdimi
                    case .kur: kurAdimi
                    case .fark: farkAdimi
                    }
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 40)
                .frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Tema.arka.ignoresSafeArea())
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } } }
        }
        .onAppear { baslangic = Date(); odak = true }
    }

    private var ilerleme: some View {
        let a = [Adim.cagir, .karsilastir, .kur, .fark]
        let i = a.firstIndex(of: adim) ?? 0
        return HStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { n in
                Capsule().fill(n <= i ? kr : Tema.yuzey2).frame(height: 4)
            }
        }
    }

    private func baslik(_ s: String, _ alt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(s).font(Tema.serif(.title2, .semibold)).foregroundStyle(Tema.metin)
            Text(alt).font(.subheadline).foregroundStyle(Tema.ikincil)
        }
    }

    private func kutu(_ metin: Binding<String>, _ yerTutucu: String, yukseklik: CGFloat = 180) -> some View {
        ZStack(alignment: .topLeading) {
            if metin.wrappedValue.isEmpty {
                Text(yerTutucu).font(.system(size: 17, design: .serif)).foregroundStyle(Tema.soluk).padding(.top, 14).padding(.leading, 17)
                    .allowsHitTesting(false)
            }
            TextEditor(text: metin).font(.system(size: 17, design: .serif)).lineSpacing(4)
                .scrollContentBackground(.hidden).focused($odak).padding(10).frame(minHeight: yukseklik)
        }
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Tema.yuzey))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(odak ? Tema.vurgu.opacity(0.5) : Tema.cizgi, lineWidth: odak ? 1.2 : 0.7))
    }

    // MARK: 1 · Çağır

    private var cagirAdimi: some View {
        VStack(alignment: .leading, spacing: 18) {
            baslik("Metin kapalı. Ne hatırlıyorsun?",
                   "\(isaret.kisaBaslik) kitabından bir not. Kendi cümlelerinle, bakmadan yaz. Tam olması gerekmez; boş bırakmak da dürüst bir cevap.")
            SesleYaz(metin: $cagri, dosya: $cagriSes, renk: kr)
            kutu($cagri, "Bu not ne diyordu? Yaz ya da sesle anlat…")
            Button {
                odak = false
                withAnimation(.snappy) { adim = .karsilastir; puan = onerilenPuan }
            } label: { Text(cagri.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Hatırlayamadım — metni göster" : "Karşılaştır") }
            .buttonStyle(AnaDugme(renk: kr))
        }
    }

    // MARK: 2 · Karşılaştır

    private var vurgulu: Text {
        let u = cagriKelimeleri
        return asilKelimeler.reduce(Text("")) { t, w in
            let r: Color = !icerik(w) ? Tema.metin : (yakalandi(w, u) ? Tema.basari : Tema.uyari)
            return t + Text(w + " ").foregroundColor(r)
        }
    }

    private var karsilastirAdimi: some View {
        VStack(alignment: .leading, spacing: 18) {
            baslik("Asıl metin",
                   cagri.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Boş bıraktın; şimdi metne bak."
                   : "Yeşil: yakaladığın. Turuncu: kaçırdığın.")
            vurgulu.font(.system(size: 19, design: .serif)).lineSpacing(7)
                .padding(.leading, 16).tamGenislik()
                .overlay(alignment: .leading) { Capsule().fill(kr).frame(width: 3) }
            if !cagri.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SENİN CÜMLEN").font(.system(size: 10.5, weight: .bold)).tracking(1.2).foregroundStyle(Tema.soluk)
                    Text(cagri).font(.system(size: 16, design: .serif)).foregroundStyle(Tema.ikincil).lineSpacing(5)
                }
                .tamGenislik()
            }
            Text("Anahtar kelimelerin yaklaşık %\(Int(yakalanan * 100))'ini yakaladın.")
                .font(.footnote.weight(.medium)).foregroundStyle(Tema.ikincil)
            if !kacirilan.isEmpty {
                Text("Kaçan: " + kacirilan.joined(separator: " · ")).font(.footnote).foregroundStyle(Tema.uyari)
            }
            Text("Dürüstçe işaretle:").font(.footnote).foregroundStyle(Tema.ikincil)
            HStack(spacing: 8) {
                ForEach([(0.0, "Kaçırdım"), (0.5, "Kısmen"), (0.85, "Yakaladım"), (1.0, "Tam")], id: \.0) { s in
                    Button { puan = s.0; Dokunus.secim() } label: {
                        Text(s.1).font(.system(size: 13.5, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Capsule().fill(puan == s.0 ? kr : kr.opacity(0.12)))
                            .foregroundStyle(puan == s.0 ? Color.white : kr)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button {
                kaydetCagri()
                withAnimation(.snappy) { adim = .kur; odak = true }
            } label: { Text("Şimdi kendin kur") }
            .buttonStyle(AnaDugme(renk: kr)).disabled(puan == nil)
        }
    }

    // MARK: 3 · Yeniden kur

    private var kurAdimi: some View {
        VStack(alignment: .leading, spacing: 18) {
            baslik("Aynı fikri, kendi konunda kur.",
                   "Asılın yapısını al; örneği, kelimeleri ve konuyu kendi hayatından seç. Kopyalamak değil, yeniden yaratmak.")
            if modeleBaktim {
                Text(isaret.metin).font(.system(size: 15, design: .serif)).foregroundStyle(Tema.ikincil).lineSpacing(5)
                    .padding(.leading, 14).tamGenislik()
                    .overlay(alignment: .leading) { Capsule().fill(kr.opacity(0.4)).frame(width: 2) }
            } else {
                Button { withAnimation(.snappy) { modeleBaktim = true } } label: {
                    Label("Modele bak (işaretlenir)", systemImage: "eye")
                }
                .buttonStyle(PerdeDugmesi())
            }
            SesleYaz(metin: $yeni, dosya: $yeniSes, renk: kr)
            kutu($yeni, "Benzer bir cümle kur…", yukseklik: 130)
            Button {
                kaydetYeni()
                odak = false
                withAnimation(.snappy) { adim = .fark }
            } label: { Text("Kaydet ve farkı gör") }
            .buttonStyle(AnaDugme(renk: kr))
            .disabled(yeni.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    // MARK: 4 · Fark

    private var benzerlik: Double { Dil.benzerlik(yeni, isaret.metin) }

    private var farkAdimi: some View {
        let b = benzerlik
        let yorum = b >= 0.6 ? "Asıla çok yakın: büyük ölçüde onu söyledin. Bir dahaki sefer konuyu da değiştir."
            : (b >= 0.25 ? "Yapıyı korudun ama kendi sözcüklerini getirdin. Yeniden yaratma tam burada başlar."
               : "Asıldan epey uzaklaştın. Fikir hâlâ aynı mı, kendin bak: aşağıdaki iki cümleyi yan yana oku.")
        return VStack(alignment: .leading, spacing: 18) {
            baslik("Kaydedildi", "Recall defterine iki kayıt düştü: hatırladığın ve yeniden kurduğun.")
            VStack(alignment: .leading, spacing: 6) {
                Text("ASIL").font(.system(size: 10.5, weight: .bold)).tracking(1.2).foregroundStyle(Tema.soluk)
                Text(isaret.metin).font(.system(size: 15, design: .serif)).foregroundStyle(Tema.ikincil).lineSpacing(5)
            }.tamGenislik()
            VStack(alignment: .leading, spacing: 6) {
                Text("SENİN YENİDEN KURDUĞUN").font(.system(size: 10.5, weight: .bold)).tracking(1.2).foregroundStyle(kr)
                Text(yeni).font(.system(size: 18, design: .serif)).foregroundStyle(Tema.metin).lineSpacing(6)
            }
            .padding(.leading, 14).tamGenislik()
            .overlay(alignment: .leading) { Capsule().fill(kr).frame(width: 3) }
            Text("Kelime benzerliği %\(Int(b * 100)) · \(modeleBaktim ? "modele baktın" : "modele bakmadın")")
                .font(.footnote.weight(.medium)).foregroundStyle(Tema.ikincil)
            Text(yorum).font(Tema.serif(.body)).foregroundStyle(Tema.metin)
            Button("Bitti") { kapat() }.buttonStyle(AnaDugme(renk: kr))
        }
    }

    // MARK: Kayıt

    private func kaydetCagri() {
        guard let p = puan else { return }
        let m = cagri.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = Olcum.not(p, guven: nil)
        depo.ekle(Olay(tur: .cevap, hedef: "hatirla:isaret:\(isaret.id)", hat: .hatirla, kademe: 5, puan: p, not: n.rawValue,
                       metin: m.isEmpty ? "(boş)" : m, sure: Date().timeIntervalSince(baslangic), rol: "recall"))
        sesiKaydet(cagriSes)
    }

    /// Kaydedilen ses, sesli not olarak deftere girer (vault'a gider, Mac'te Whisper dökümü + değerlendirme).
    private func sesiKaydet(_ u: URL?) {
        guard let u, FileManager.default.fileExists(atPath: u.path) else { return }
        let sure = (try? AVAudioPlayer(contentsOf: u))?.duration
        depo.ekle(Olay(tur: .sesNot, hedef: isaret.id, deger: false, metin: u.lastPathComponent, sure: sure, rol: "recall"))
        depo.esitle(gecikme: 2)
    }

    private func kaydetYeni() {
        let m = yeni.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !m.isEmpty else { return }
        depo.ekle(Olay(tur: .kendiCumle, hedef: isaret.id, deger: modeleBaktim, metin: m, rol: "yeniden"))
        sesiKaydet(yeniSes)
        Dokunus.basari()
    }
}
