// Oku: metni ekrandan bir kez oku (dinleme sesin tanınmasını öğretir, yazımın değil).
// · Hedef kelimeler (yeni · tekrar · tanıdık) renkli; dokun → okunuş, tanım, Türkçe, Oxford örneği, sesli okuma.
// · Her cümlenin altında: 🔊 Dinle (paketin kendi sesinden) · 🎙 Kur (İngilizce gizlenir, Türkçesinden kendin söyle;
//   widget'taki kurmayla aynı kayıt ve değerlendirme) · Kopyala · ✨ YZ istemi (widget'takiyle aynı istem).
// · Cümleye uzun bas → Türkçesi açılır; araç çubuğundaki düğme bütün Türkçeleri açar.
// · Gramer yapısı cümlenin altında adıyla. Sona kadar okununca "okudum" kendiliğinden yazılır (en az 20 sn sonra).
import SwiftUI
import AVFoundation

struct OkuEkrani: View {
    @EnvironmentObject var depo: Depo
    @EnvironmentObject var oynatici: Oynatici
    @State private var turkce: Set<Int> = []
    @State private var secili: Sozcuk?
    @State private var acilis = Date()
    @State private var sonaGeldi = false
    @State private var kopyalanan: String?
    @State private var izinYok = false
    @ObservedObject private var kurucu = SentenceRecorder.shared
    /// Widget'ın YZ düğmesi uygulamayı açınca o cümleye kaydırılır.
    @Binding var hedef: Int?

    var body: some View {
        NavigationStack {
            Group {
                if let p = depo.guncel { metin(p) }
                else { BosDurum(simge: "text.alignleft", baslik: "Okunacak metin yok", metin: "Paket telefona inince burada okunur.") }
            }
            .background(Tema.arka)
            .navigationTitle("Oku")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let p = depo.guncel {
                    Button {
                        withAnimation { turkce = turkce.count == p.cumleler.count ? [] : Set(p.cumleler.map(\.i)) }
                    } label: {
                        Image(systemName: turkce.isEmpty ? "character.bubble" : "character.bubble.fill")
                    }
                    .accessibilityLabel(turkce.isEmpty ? "Bütün Türkçeleri göster" : "Türkçeleri gizle")
                }
            }
            .sheet(item: $secili) { s in SozcukSayfasi(s: s).presentationDetents([.medium]) }
            .alert("Mikrofon izni yok", isPresented: $izinYok) {
                Button("Tamam", role: .cancel) {}
            } message: { Text("Ayarlar › Memories › Mikrofon'dan açabilirsin.") }
        }
        .onAppear { acilis = Date() }
    }

    private func metin(_ p: Paket) -> some View {
        let h = depo.hazirlik(p.gun)
        return ScrollViewReader { kaydir in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("GÜN \(p.gun) · MESELE NE?").font(.caption.weight(.bold)).tracking(1.1).foregroundStyle(.secondary)
                        Text(p.ozet ?? "").font(.callout).foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 4)

                    Text(p.ad).font(.system(.title, design: .serif).weight(.semibold))

                    ForEach(p.cumleler) { c in
                        satir(p, c).id(c.i)
                    }

                    if !(p.sozluk ?? []).isEmpty {
                        sozlukListesi(p)
                    }

                    Button {
                        depo.okudu(p)
                    } label: {
                        Label(h.okuma ? "Okundu" : "Okudum", systemImage: h.okuma ? "checkmark.circle.fill" : "checkmark.circle")
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(h.okuma ? Tema.yesil : Tema.kehribar)
                    .disabled(h.okuma)
                    .padding(.top, 8)
                    .onAppear {
                        // Sona kadar kaydırıldı ve gerçekten okumaya yetecek süre geçti
                        if !h.okuma, Date().timeIntervalSince(acilis) > 20 { depo.okudu(p) }
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
            }
            .onChange(of: hedef, initial: true) { _, i in
                guard let i else { return }
                withAnimation { kaydir.scrollTo(i, anchor: .top) }
                hedef = nil
            }
        }
    }

    private func satir(_ p: Paket, _ c: Cumle) -> some View {
        let kuruyor = kurucu.activeKey == RebuildState.key(p.gun, c.i)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(c.i + 1)").font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(.tertiary).frame(width: 18, alignment: .trailing)
                if kuruyor {
                    // Kurarken İngilizce yok: Türkçesine bakıp kendin söylersin
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Şimdi kendin söyle").font(.caption.weight(.bold)).foregroundStyle(Tema.kehribarYazi)
                        Text(c.tr ?? "—").font(Tema.ingilizce(.title3)).lineSpacing(3)
                    }
                } else {
                    Text(isaretli(c.en ?? "", p))
                        .font(Tema.ingilizce(.title3))
                        .lineSpacing(3)
                        .environment(\.openURL, OpenURLAction { url in
                            if let w = url.host(), let s = p.kelime(w.removingPercentEncoding ?? w) { secili = s }
                            return .handled
                        })
                }
                Spacer(minLength: 0)
            }
            Group {
                if turkce.contains(c.i), !kuruyor, let tr = c.tr {
                    Text(tr).font(.callout).foregroundStyle(.secondary)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if let k = c.konu {
                    Cip(metin: k, renk: Tema.vurgu.opacity(0.85), simge: "textformat")
                }
                if !kuruyor, let t = RebuildState.attempt(p.gun, c.i) { deneme(t) }
                araclar(p, c, kuruyor: kuruyor)
            }
            .padding(.leading, 28)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.35) {
            withAnimation(.easeInOut(duration: 0.2)) {
                if turkce.contains(c.i) { turkce.remove(c.i) } else { turkce.insert(c.i); depo.takildi(p, cumle: c.i, nasil: "turkce") }
            }
        }
        .dokun(depo, turkce.contains(c.i))
    }

    /// Cümlenin araçları: dinle · kur · kopyala · YZ istemi. Tek sıra, başparmakla ulaşılır boyda.
    private func araclar(_ p: Paket, _ c: Cumle, kuruyor: Bool) -> some View {
        let caliyor = oynatici.tekCumle == c.i && oynatici.caliyor
        let en = c.en ?? ""
        return HStack(spacing: 8) {
            Arac(simge: caliyor ? "stop.fill" : "speaker.wave.2.fill", yazi: "Dinle", renk: caliyor ? Tema.kehribarYazi : Tema.vurgu) {
                oynatici.cumleCal(p, c.i); depo.takildi(p, cumle: c.i, nasil: "dinle")
            }
            .disabled(kuruyor)
            Arac(simge: kuruyor ? "stop.fill" : "mic.fill", yazi: kuruyor ? "Bitir" : "Kur", renk: kuruyor ? .red : Tema.yesil, dolu: kuruyor) {
                Task {
                    oynatici.duraklat()
                    guard await kurucu.askPermissions() else { izinYok = true; return }
                    await kurucu.toggle(day: p.gun, index: c.i, en: en, tr: c.tr)
                }
            }
            .overlay(alignment: .topTrailing) {
                if kuruyor, let t = RebuildState.activeStart {
                    Text(timerInterval: t...t.addingTimeInterval(RebuildState.tavan), countsDown: false)
                        .font(.caption2.monospacedDigit().weight(.semibold)).foregroundStyle(.red)
                        .offset(x: 4, y: -14)
                }
            }
            Arac(simge: kopyalanan == "c\(c.i)" ? "checkmark" : "doc.on.doc", yazi: "Kopyala", renk: .secondary) {
                kopyala(en, "c\(c.i)", not: "Cümle panoda")
            }
            .disabled(kuruyor)
            Arac(simge: kopyalanan == "y\(c.i)" ? "checkmark" : "sparkles", yazi: "YZ istemi", renk: Tema.kehribarYazi) {
                kopyala(SentencePrompt.text(en: en, tr: c.tr), "y\(c.i)", not: "YZ istemi panoda · bir YZ uygulamasına yapıştır")
            }
            .disabled(kuruyor)
        }
        .padding(.top, 2)
    }

    private func deneme(_ t: RebuildAttempt) -> some View {
        let r = t.ratio
        let iyi = (r ?? 0) >= 0.85
        let yazi: String = {
            guard let r else { return "Kuruldu · Mac'te değerlendirilecek" }
            let yuzde = "%\(Int((r * 100).rounded()))"
            return t.missed.isEmpty ? "Son kurman \(yuzde) · tam oturdu" : "Son kurman \(yuzde) · takıldın: " + t.missed.prefix(4).joined(separator: ", ")
        }()
        return Label(yazi, systemImage: iyi ? "checkmark.seal.fill" : "arrow.triangle.2.circlepath")
            .font(.caption.weight(.medium)).foregroundStyle(iyi ? Tema.yesil : Tema.kehribarYazi)
    }

    private func kopyala(_ metin: String, _ kimlik: String, not: String) {
        guard PasteboardCopy.write(metin, note: not) else { return }
        withAnimation { kopyalanan = kimlik }
        Task {
            try? await Task.sleep(for: .seconds(2))
            if kopyalanan == kimlik { withAnimation { kopyalanan = nil } }
        }
    }

    /// Hedef kelimeleri bağlantıya çevirir (memories-kelime://<kelime>).
    private func isaretli(_ en: String, _ p: Paket) -> AttributedString {
        var a = AttributedString(en)
        let kelimeler = en.split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "’" })
        var arama = a.startIndex
        for k in kelimeler {
            let w = String(k)
            guard let s = p.kelime(w), let r = a[arama...].range(of: w) else { continue }
            a[r].link = URL(string: "memories-kelime://\(w.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? w)")
            a[r].foregroundColor = s.tur == "yeni" ? Tema.kehribarYazi : Tema.vurgu
            a[r].underlineStyle = .single
            arama = r.upperBound
        }
        return a
    }

    private func sozlukListesi(_ p: Paket) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Kelimeler").font(.headline)
            ForEach(p.sozluk ?? []) { s in
                Button { secili = s } label: {
                    HStack {
                        Text(s.w).font(Tema.ingilizce(.body).weight(.semibold)).foregroundStyle(s.tur == "yeni" ? Tema.kehribarYazi : Tema.vurgu)
                        if let i = s.ipa { Text(i).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Text(s.tr ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Text(s.turAdi).font(.caption2).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
        .kart()
        .padding(.top, 10)
    }
}

/// Kelime kartı: okunuş, tanım (İngilizce), Türkçe, Oxford örneği; cihazın sesiyle okunur.
struct SozcukSayfasi: View {
    var s: Sozcuk
    @State private var konusucu = AVSpeechSynthesizer()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(s.w).font(.system(.largeTitle, design: .serif).weight(.semibold))
                Button { soyle(s.w) } label: { Image(systemName: "speaker.wave.2.fill").font(.title2) }
                    .accessibilityLabel("Kelimeyi dinle")
                Spacer()
                if let c = s.cefr { Cip(metin: c, renk: Tema.vurgu) }
            }
            HStack(spacing: 8) {
                if let i = s.ipa { Text(i).font(.title3).foregroundStyle(.secondary) }
                if let p = s.pos { Text(p).font(.callout.italic()).foregroundStyle(.secondary) }
                if !s.turAdi.isEmpty { Cip(metin: s.turAdi, renk: s.tur == "yeni" ? Tema.kehribarYazi : Tema.vurgu) }
            }
            if let t = s.tanim { Text(t).font(Tema.ingilizce(.title3)) }
            if let tr = s.tr { Label(tr, systemImage: "character.bubble").font(.body).foregroundStyle(.secondary) }
            if let o = s.ornek {
                Button { soyle(o) } label: {
                    Text(o).font(Tema.ingilizce(.callout).italic()).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(24)
    }

    private func soyle(_ m: String) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        let u = AVSpeechUtterance(string: m)
        u.voice = AVSpeechSynthesisVoice(language: "en-US")
        u.rate = 0.45
        konusucu.stopSpeaking(at: .immediate)
        konusucu.speak(u)
    }
}

/// Cümle altındaki küçük araç düğmesi: simge + yazı, dolu ya da açık kapsül.
struct Arac: View {
    var simge: String
    var yazi: String
    var renk: Color
    var dolu = false
    var eylem: () -> Void
    @Environment(\.isEnabled) private var acik
    var body: some View {
        Button(action: eylem) {
            HStack(spacing: 4) {
                Image(systemName: simge).font(.caption.weight(.semibold))
                Text(yazi).font(.caption.weight(.semibold)).lineLimit(1)
            }
            .padding(.horizontal, 10).frame(height: 30)
            .foregroundStyle(dolu ? .white : renk)
            .background { Capsule().fill(dolu ? AnyShapeStyle(renk) : AnyShapeStyle(renk.opacity(0.12))) }
            .opacity(acik ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
    }
}
