// ④ Hatırlama testi (seçenek yok) · ⑤ Kendi cümlen (atlanabilir) · ⑥ Hesap · Kuiz promptu · Gramer sayfası
import SwiftUI
import AppKit

// MARK: - ④ Hatırlama testi

struct RecallEkrani: View {
    @EnvironmentObject var t: Tezgah
    @State private var giris = ""
    @State private var uyari: String?
    @FocusState private var odak: Bool

    var body: some View {
        if let o = t.o, let r = o.recall {
            Sutun {
                Baslik(metin: "④ Hatırlama testi · \(min(r.j + 1, r.sorular.count)) / \(r.sorular.count)")
                Text("Boşlukları doldur").font(.title.bold())
                Text("Seçenek yok — kelimeyi ya da yapıyı hafızandan yazacaksın. Bugünün kalıcı olup olmadığının ölçüsü.").foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(Array(r.sorular.enumerated()), id: \.offset) { n, s in
                        Circle().fill(s.sonuc == "tam" ? Renk.yesil : s.sonuc == "kismi" ? Renk.sari : s.sonuc != nil ? Renk.kirmizi : Color.secondary.opacity(0.25))
                            .frame(width: 11, height: 11)
                            .overlay(Circle().strokeBorder(Renk.vurgu, lineWidth: n == (r.bakilan ?? r.j) ? 2 : 0).padding(-3))
                            .onTapGesture { if s.sonuc != nil { t.o?.recall?.bakilan = n } }
                    }
                }
                if let b = r.bakilan { sonucKart(o, r.sorular[b], geri: true) }
                else if r.j >= r.sorular.count { liste(o, r) }
                else {
                    let s = r.sorular[r.j]
                    if s.sonuc != nil { sonucKart(o, s, geri: false) } else { soruKart(o, s) }
                }
            }
        }
    }

    func cumle(_ s: Soru, dolu: Bool, durum: String?) -> some View {
        let bos = String(repeating: "_", count: min(14, max(4, Metin.kelimeler(s.cevap).joined().count)))
        let ic = dolu ? s.cevap : bos
        let renk: Color = durum == "tam" ? Renk.yesil : durum == nil ? Renk.vurgu : Renk.kirmizi
        return (Text(s.once) + Text(ic).foregroundColor(renk).bold().underline() + Text(s.sonra)).font(.serif(22))
            .fixedSize(horizontal: false, vertical: true)
    }

    func soruKart(_ o: Oturum, _ s: Soru) -> some View {
        Kart {
            HStack {
                Text("Soru \(s.no)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Cip(metin: s.tip == "yapı" ? "yapı" : s.kaynak, renk: s.tip == "yapı" ? Renk.mor : Renk.vurgu)
                Spacer()
                Button { t.ses.soyle(s.once + " blank " + s.sonra) } label: { Image(systemName: "speaker.wave.2") }.buttonStyle(.borderless).help("cümleyi dinle (boşluk dahil)")
            }
            cumle(s, dolu: false, durum: nil)
            Text(s.tr).foregroundStyle(.secondary)
            TextField(s.tip == "yapı" ? "eksik yapıyı yaz…" : "eksik kelimeyi yaz…", text: $giris)
                .textFieldStyle(.roundedBorder).font(.serif(19)).focused($odak)
                .autocorrectionDisabled()
                .onSubmit { kontrol(false) }
            let ip = s.tip == "yapı" ? "Yapı: \(s.hedef) · \(Metin.kelimeler(s.cevap).count) kelime"
                : s.deneme >= 1 ? "İlk harf: \(s.cevap.prefix(1)) · \(s.cevap.count) harf" : "\(s.cevap.count) harf"
            Text(ip + " · ↩ kontrol et").font(.caption).foregroundStyle(.secondary)
            if let u = uyari { Text(u).font(.callout).foregroundStyle(Renk.sari) }
            HStack {
                Button("Kontrol et") { kontrol(false) }.buttonStyle(.borderedProminent)
                Button("bilmiyorum, göster") { kontrol(true) }.buttonStyle(.borderless)
            }
        }
        .onAppear { odak = true }
    }

    func kontrol(_ pas: Bool) {
        let v = giris
        if let m = t.recallKontrol(pas ? "" : v, pas: pas) { uyari = m; odak = true } else { uyari = nil; giris = "" }
    }

    func sonucKart(_ o: Oturum, _ s: Soru, geri: Bool) -> some View {
        let h = s.sonuc ?? "yok"
        return Kart {
            HStack {
                Text("Soru \(s.no)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if geri { Text("geri bakıyorsun").font(.caption).foregroundStyle(Renk.vurgu) }
            }
            cumle(s, dolu: true, durum: h)
            Text(s.tr).foregroundStyle(.secondary)
            HStack {
                Text(h == "tam" ? "✓ Doğru" : h == "kismi" ? "~ Doğru kelime, yanlış biçim" : "✗ Tutmadı").font(.headline)
                    .foregroundStyle(h == "tam" ? Renk.yesil : h == "kismi" ? Renk.sari : Renk.kirmizi)
                Button { t.ses.soyle(o.cumle(s.cumleIdx).en) } label: { Image(systemName: "speaker.wave.2") }.buttonStyle(.borderless)
            }
            let ver = s.verilen.filter { !$0.isEmpty }
            (Text("Doğrusu: ") + Text(s.cevap).bold() + Text(ver.isEmpty ? " · boş bıraktın" : " · senin yazdığın: " + ver.joined(separator: " → ")))
                .font(.callout)
            if let a = s.aciklama { Text(a).font(.callout).foregroundStyle(.secondary) }
            HStack {
                if geri {
                    Button(o.recall?.bitti == true ? "Tüm sorulara dön" : "Teste geri dön") { t.o?.recall?.bakilan = nil }.buttonStyle(.borderedProminent)
                } else {
                    Button { t.recallSonraki() } label: { Text(s.no >= (o.recall?.sorular.count ?? 0) ? "Testi bitir →" : "Sıradaki soru →").padding(.horizontal, 8) }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: [])
                }
            }
        }
    }

    func liste(_ o: Oturum, _ r: Recall) -> some View {
        let z = t.recallOzeti() ?? [:]
        return VStack(alignment: .leading, spacing: 14) {
            Kart {
                HStack {
                    Baslik(metin: "Testi bitirdin")
                    Spacer()
                    Text("tam \(z["tam"] ?? 0) · biçim \(z["kismi"] ?? 0) · tutmadı \(z["yok"] ?? 0) → %\(z["yuzde"] ?? 0)").font(.callout).foregroundStyle(.secondary)
                }
                HStack {
                    Button { t.kendiBasla() } label: { Text("Kendi cümlene geç →").padding(.horizontal, 8) }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: [])
                    Button("testi baştan kur") { t.recallYenidenKur() }.buttonStyle(.borderless)
                }
            }
            ForEach(Array(r.sorular.enumerated()), id: \.offset) { n, s in
                let h = s.sonuc ?? "yok"
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(h == "tam" ? "✓" : h == "kismi" ? "~" : "✗").font(.headline).foregroundStyle(h == "tam" ? Renk.yesil : h == "kismi" ? Renk.sari : Renk.kirmizi)
                    VStack(alignment: .leading, spacing: 2) {
                        (Text(s.once) + Text(s.cevap).bold() + Text(s.sonra)).font(.serif(16))
                        Text(h == "tam" ? (s.deneme == 1 ? "ilk denemede" : "\(s.deneme). denemede")
                             : s.verilen.filter { !$0.isEmpty }.isEmpty ? "boş bıraktın" : "yazdığın: " + s.verilen.filter { !$0.isEmpty }.joined(separator: " → "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { t.ses.soyle(o.cumle(s.cumleIdx).en) } label: { Image(systemName: "speaker.wave.2") }.buttonStyle(.borderless)
                }
                .contentShape(Rectangle())
                .onTapGesture { t.o?.recall?.bakilan = n }
            }
        }
    }
}

// MARK: - ⑤ Kendi cümlen

struct KendiEkrani: View {
    @EnvironmentObject var t: Tezgah
    var body: some View {
        if let o = t.o {
            Sutun {
                Baslik(metin: "⑤ Kendi cümlen")
                Text("Bugünün iki yapısıyla kendi cümleni kur").font(.title.bold())
                Text("Referans yok, Türkçe yok. Kendi hayatından birer cümle yaz. Yapı kabaca sezilir; doğruluğunu kuiz promptu ayrıca değerlendirtir. İstersen atla.")
                    .foregroundStyle(.secondary)
                ForEach(Array((o.kendi ?? []).enumerated()), id: \.offset) { n, k in
                    let g = t.gramerMap[k.konu]
                    Kart {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(n + 1)").font(.title3.bold()).foregroundStyle(Renk.vurgu)
                            VStack(alignment: .leading) {
                                Text(k.konu).font(.headline)
                                if let g { Text(g.tr).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Button("kart") { t.gramerAc([k.konu]) }.buttonStyle(.borderless)
                        }
                        if let g { Text(g.formul).font(.callout.monospaced()).foregroundStyle(.secondary) }
                        Editor(metin: Binding(get: { t.o?.kendi?[n].metin ?? "" }, set: { t.kendiYaz(n, $0) }),
                               yerTutucu: "Kendi hayatından bir cümle…", boyut: 18, odak: n == 0 ? t.editorOdak : UUID(uuidString: "00000000-0000-0000-0000-00000000000\(n)")!,
                               gonder: nil)
                            .frame(minHeight: 70, maxHeight: 120)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Renk.kart2))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
                        durum(k)
                    }
                }
                HStack {
                    Button { t.bitis() } label: { Text("Hesaba geç →").padding(.horizontal, 8) }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command)
                    Button("bugün atla") { t.bitis() }.buttonStyle(.borderless)
                }
            }
        }
    }
    @ViewBuilder func durum(_ k: Kendi) -> some View {
        let m = k.metin.trimmingCharacters(in: .whitespacesAndNewlines)
        if m.isEmpty { Text("Bir cümle yeter. Kartın örneğini kopyalama — kendi gününden yaz.").font(.caption).foregroundStyle(.secondary) }
        else {
            HStack(spacing: 6) {
                Text(k.sezildi ? "✓ yapı sezildi" : "yapı sezilmedi — formüle bir daha bak").foregroundStyle(k.sezildi ? Renk.yesil : Renk.sari)
                if t.kendiKopya(k) { Text("· kartın örneğiyle aynı").foregroundStyle(Renk.sari) }
                if !k.yazim.isEmpty { Text("· yazımı kontrol et: " + k.yazim.joined(separator: ", ")) }
                Text("· \(Metin.kelimeler(m).count) kelime")
            }
            .font(.caption)
        }
    }
}

// MARK: - ⑥ Hesap

struct BitisEkrani: View {
    @EnvironmentObject var t: Tezgah
    var body: some View {
        if let o = t.o {
            let rc = t.recallOzeti()
            Sutun {
                Baslik(metin: "⑥ Modül tamam")
                Text("Bugünkü hesap").font(.largeTitle.bold())
                Text("Zorlandığın kelimeler yarının metninde geri gelecek.").foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Kutu(k: "süre", v: "\(t.aktifDk) dk")
                    Kutu(k: "cümle turu", v: t.cumleOrt.map { "%\($0)" } ?? "—")
                    Kutu(k: "paragraf", v: o.paragraf.map { "%\($0.yuzde)" } ?? "—")
                    Kutu(k: "hatırlama", v: rc.map { "%\($0["yuzde"]!)" } ?? "—")
                    Kutu(k: "bakılan", v: "\(o.turlar.filter(\.baktim).count) / \(o.toplam)")
                }
                cikti(o)
                Kart {
                    Baslik(metin: "Kuiz", alt: "paragraf + yapılar + zor kelimeler + hata profilin")
                    HStack {
                        Button("Prompt → Gemini") { gemini() }.buttonStyle(.borderedProminent)
                        Button("önizle ⌘K") { t.kuizAcik = true }
                    }
                }
                IkiliSira {
                    Kart { Baslik(metin: "Hata türleri", alt: "cümle turu"); HtCubuk(ht: t.oturumHT()) }
                } b: {
                    Kart {
                        Baslik(metin: "İpucu ve sesli okuma")
                        let ip = (0..<4).map { s in o.turlar.filter { $0.y != nil && t.ipucuSeviye($0.i) == s }.count }
                        HStack(spacing: 8) { Kutu(k: "ipucusuz", v: "\(ip[0])"); Kutu(k: "yapı", v: "\(ip[1])"); Kutu(k: "iskelet", v: "\(ip[2])"); Kutu(k: "tam cümle", v: "\(ip[3])") }
                        if let s = o.sesli {
                            Text("🎙 \(s.kayit) kayıt · \(s.sure_sn) sn" + (s.tanima_yuzde.map { " · tanınan %\($0)" } ?? "")).font(.callout).foregroundStyle(.secondary)
                        } else if t.hazirlik.kayit > 0 {
                            Text("🎙 telefonda \(t.hazirlik.kayit) kayıt").font(.callout).foregroundStyle(.secondary)
                        } else { Text("Bugün sesli okuma kaydı yok.").font(.callout).foregroundStyle(.secondary) }
                    }
                }
                if let r = o.recall {
                    Kart {
                        Baslik(metin: "Hatırlama testi")
                        Akis { ForEach(r.sorular) { s in Cip(metin: s.cevap, renk: s.sonuc == "tam" ? Renk.yesil : s.sonuc == "kismi" ? Renk.sari : Renk.kirmizi) } }
                    }
                }
                let ys = t.yapiSkorlari()
                if !ys.isEmpty {
                    Kart {
                        Baslik(metin: "Yapı başına tutturma")
                        ForEach(Array(ys.enumerated()), id: \.offset) { _, y in
                            HStack {
                                Text((y["skor"] as? Int).map { "%\($0)" } ?? "—").font(.headline.monospacedDigit()).frame(width: 52, alignment: .leading)
                                VStack(alignment: .leading) {
                                    Text(y["konu"] as? String ?? "").bold()
                                    let b = y["bakilan"] as? Int ?? 0
                                    Text("\(y["cumle"] as? Int ?? 0) cümle" + (b > 0 ? " · \(b) tanesinde İngilizceye bakıldı" : "")).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Kart {
                    Baslik(metin: "Hatırlatma yapıları · kendi cümlelerin")
                    Akis { ForEach(o.hatirlatma?.konular ?? [], id: \.self) { Cip(metin: $0) } }
                    let kd = (o.kendi ?? []).filter { !$0.metin.trimmingCharacters(in: .whitespaces).isEmpty }
                    if kd.isEmpty { Button("Kendi cümle yazılmadı — şimdi yaz") { t.kendiBasla() }.buttonStyle(.borderless) }
                    ForEach(kd, id: \.self) { k in
                        HStack { Text(k.metin).font(.serif(16)); Cip(metin: k.sezildi ? "yapı ✓" : "yapı ?", renk: k.sezildi ? Renk.yesil : Renk.sari) }
                    }
                }
                Kart {
                    Baslik(metin: "Kaçırdığın kelimeler", alt: "yazman gerekirken yazmadıkların")
                    let z = t.zorKelimeler()
                    if z.isEmpty { Cip(metin: "hiçbiri — hepsi tuttu", renk: Renk.yesil) }
                    Akis { ForEach(z, id: \.0) { w, n in KelimeDugmesi(kelime: w, renk: Renk.kirmizi).overlay(alignment: .topTrailing) { Text("×\(n)").font(.caption2).offset(x: 6, y: -6) } } }
                    Baslik(metin: "Fazladan yazdıkların", alt: "sicile hata olarak girmez").padding(.top, 8)
                    let f = t.fazlaKelimeler()
                    Akis { ForEach(f, id: \.0) { w, n in Cip(metin: "\(w) ×\(n)") }; if f.isEmpty { Cip(metin: "yok") } }
                }
                Kart {
                    Baslik(metin: "Geri dön", alt: "hiçbir şey silinmez")
                    HStack {
                        Button("Metni yeniden oku") { t.adimaGit(.oku) }
                        Button("Cümlelerime bak") { t.adimaGit(.cumle) }
                        Button("Paragraf farkı") { t.adimaGit(.paragraf) }
                        Button("Test sorularım") { t.adimaGit(.recall) }
                        Button("Kendi cümlelerim") { t.adimaGit(.kendi) }
                    }
                }
                Button("Oturumu kapat — başlangıca dön") { t.birak() }.buttonStyle(.borderless).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder func cikti(_ o: Oturum) -> some View {
        Kart {
            Baslik(metin: "Çıktı")
            if let d = o.dosya {
                Label("Sonuç kaydedildi: \((d as NSString).lastPathComponent)", systemImage: "checkmark.circle.fill").foregroundStyle(Renk.yesil)
                Text("İndirilenler'de. Sabah 07:10 görevi oradan alıp sicile işler; Geçmiş o an güncellenir.").font(.callout).foregroundStyle(.secondary)
            } else {
                Label("Sonuç dosyası yazılamadı", systemImage: "exclamationmark.triangle").foregroundStyle(Renk.sari)
            }
            if !o.tekrar && o.gun.no > 0 {
                Label("Telefona gitti — Memories bugün \"Mac'te yazdın\" kartını gösterir", systemImage: "iphone").font(.callout).foregroundStyle(.secondary)
            } else if o.tekrar {
                Text("Tekrar çalışma: sicile işlenmez, döngüyü ilerletmez, telefona gitmez.").font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Button("Yeniden kaydet") { t.sonucYaz(); t.kaydet() }
                if let d = o.dosya { Button("Finder'da göster") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: d)]) } }
            }
        }
    }

    func gemini() {
        t.panoya(t.kuizPrompt())
        t.duyur("Prompt panoya kopyalandı — Gemini açılıyor, yapıştır")
        NSWorkspace.shared.open(URL(string: "https://gemini.google.com/app")!)
    }
}

// MARK: - Kuiz promptu

struct KuizSayfasi: View {
    @EnvironmentObject var t: Tezgah
    @Environment(\.dismiss) var kapat
    @State private var metin = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Kuiz promptu").font(.title2.bold())
            Text("Kopyalamadan önce düzenleyebilirsin. Paragrafı, sahne ve hatırlatma yapılarını, zorlandığın kelimeleri ve hata profilini taşır.")
                .font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $metin).font(.system(.callout, design: .monospaced)).frame(minHeight: 380)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            HStack {
                Button("Kopyala → Gemini") {
                    t.panoya(metin); NSWorkspace.shared.open(URL(string: "https://gemini.google.com/app")!)
                    t.duyur("Prompt panoya kopyalandı — Gemini'ye yapıştır"); kapat()
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command)
                Button("Yalnız kopyala") { t.panoya(metin); t.duyur("Prompt panoya kopyalandı"); kapat() }
                Spacer()
                Button("Kapat") { kapat() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(22)
        .frame(width: 720)
        .onAppear { metin = t.kuizPrompt() }
    }
}

// MARK: - Gramer sayfası: yazarken göz önünde durmaz; istenince açılır. Bugün · Döngü

struct GramerSayfasi: View {
    @EnvironmentObject var t: Tezgah
    @Environment(\.dismiss) var kapat
    @State private var sekme = 0
    @State private var cevap = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $sekme) {
                    ForEach(Array((t.gramerSayfa ?? []).enumerated()), id: \.offset) { n, k in Text("\(n + 1) · \(Gramer.kisa(k))").tag(n) }
                    Text("Döngü").tag(-1)
                }
                .pickerStyle(.segmented).labelsHidden()
                Spacer()
                Button("Kapat") { kapat() }.keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Divider()
            ScrollView {
                Group {
                    if sekme == -1 { DonguGorunum(ac: { k in t.gramerSayfa = [k]; sekme = 0; cevap = false }) }
                    else if let ad = t.gramerSayfa?[safe: sekme] { kart(ad) }
                }
                .padding(26)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(width: 760, height: 640)
        .onAppear { sekme = t.gramerI }
        .onChange(of: sekme) { _, _ in cevap = false }
    }

    @ViewBuilder func kart(_ ad: String) -> some View {
        if let g = t.gramerMap[ad] {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FAZ \(g.faz)" + (g.yildiz ? " · KALICI BOŞLUK ⭐" : "")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(g.ad).font(.largeTitle.bold())
                    Text(g.tr).font(.title3).foregroundStyle(.secondary)
                }
                bolum("Ne zaman kullanılır") { Text(g.ne).font(.title3) }
                bolum("Kalıp") {
                    Text(g.formul.components(separatedBy: " · ").joined(separator: "\n")).font(.system(.title3, design: .monospaced))
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 8).fill(Renk.vurgu.opacity(0.08)))
                }
                bolum("Örnek") {
                    ForEach(g.ornek, id: \.self) { o in
                        HStack(alignment: .top) {
                            Button { t.ses.soyle(o.first ?? "") } label: { Image(systemName: "speaker.wave.2") }.buttonStyle(.borderless)
                            VStack(alignment: .leading) { Text(o.first ?? "").font(.serif(19)); Text(o.last ?? "").foregroundStyle(.secondary) }
                        }
                    }
                }
                bolum("Dikkat") { Text(g.tuzak).font(.title3).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 8).fill(Renk.sari.opacity(0.1))) }
                bolum("Kendini yokla") {
                    HStack(alignment: .firstTextBaseline) {
                        Text(g.yoklaS).font(.serif(19))
                        Button(cevap ? "gizle" : "cevabı göster") { cevap.toggle() }
                        if cevap { Text(g.yoklaC).font(.serif(19)).bold().foregroundStyle(Renk.yesil) }
                    }
                }
            }
        } else { Text("Bu konunun kartı yok.").foregroundStyle(.secondary) }
    }
    func bolum<I: View>(_ b: String, @ViewBuilder _ i: () -> I) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(b.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary).tracking(0.6); i() }
    }
}

/// 30 günlük döngü takvimi + bütün konular. Takvime değil çalışılan güne bağlı; vade yok.
struct DonguGorunum: View {
    var ac: (String) -> Void
    @EnvironmentObject var t: Tezgah
    var body: some View {
        let d = t.hatirDurum()
        let hs = Dictionary(d.duz.map { ($0, 1) }, uniquingKeysWith: +)
        VStack(alignment: .leading, spacing: 16) {
            Text("Gramer döngüsü").font(.largeTitle.bold())
            Text("41 konu, günde ikişer, sırayla; kalan 19 yuva ⭐ ve sicilde zayıf görünen konulara gider. Gün atlarsan konu kaybolmaz; döngü kaldığı yerden sürer.")
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Kutu(k: "döngü · \(d.konum)/60 yuva", v: "\(d.dongu)")
                Kutu(k: "bu döngüde hatırlatılan", v: "\(min(t.gramer.count, Set(d.buDongu).filter { k in t.gramer.contains { $0.ad == k } }.count)) / \(t.gramer.count)")
                Kutu(k: "çalışma günü kaldı", v: "\((60 - d.konum + 1) / 2)")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                ForEach(0..<30, id: \.self) { i in
                    let a = 2 * i, b = a + 1
                    let ad1 = a < d.konum ? d.buDongu[safe: a] : d.sira[safe: a], ad2 = b < d.konum ? d.buDongu[safe: b] : d.sira[safe: b]
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(i + 1)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                        ForEach([ad1, ad2].compactMap { $0 }, id: \.self) { ad in
                            Text(Gramer.kisa(ad)).font(.caption2).lineLimit(1).onTapGesture { ac(ad) }
                        }
                    }
                    .padding(6).frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(b < d.konum ? Renk.yesil.opacity(0.12) : a == d.konum ? Renk.vurgu.opacity(0.18) : Color.secondary.opacity(0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(a >= t.gramer.count ? Renk.sari.opacity(0.5) : .clear))
                }
            }
            ForEach([1, 2, 3], id: \.self) { faz in
                Text("FAZ \(faz)").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 6)
                ForEach(t.gramer.filter { $0.faz == faz }) { g in
                    let gunler = t.arsiv.kurmaYapilar[g.ad] ?? []
                    let sk = gunler.compactMap(\.skor)
                    Button { ac(g.ad) } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(g.ad + (g.yildiz ? " ⭐" : "")).font(.callout.weight(.medium))
                                Text(g.tr).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(hs[g.ad].map { "hatırlatma ×\($0)" } ?? "—").font(.caption).foregroundStyle(.secondary)
                            Text(gunler.isEmpty ? "paragrafta yok" : "gün " + gunler.map { String($0.gun) }.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).frame(width: 140, alignment: .trailing).lineLimit(1)
                            Text(sk.isEmpty ? "—" : "%\(Int((Double(sk.reduce(0, +)) / Double(sk.count)).rounded()))").font(.callout.monospacedDigit()).frame(width: 44, alignment: .trailing)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
        }
    }
}

extension Array { subscript(safe i: Int) -> Element? { i >= 0 && i < count ? self[i] : nil } }
