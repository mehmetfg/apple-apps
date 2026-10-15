// Oku: metni ekrandan bir kez oku (dinleme sesin tanınmasını öğretir, yazımın değil).
// · Hedef kelimeler (yeni · tekrar · tanıdık) renkli; dokun → okunuş, tanım, Türkçe, Oxford örneği, sesli okuma.
// · Cümlenin 🔊'ına dokun → yalnız o cümle çalar (paketin kendi sesinden).
// · Cümleye uzun bas → Türkçesi açılır (yazarken Türkçe yok; burada yalnız göz atma).
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

    var body: some View {
        NavigationStack {
            Group {
                if let p = depo.guncel { metin(p) }
                else { BosDurum(simge: "text.alignleft", baslik: "Okunacak metin yok", metin: "Paket telefona inince burada okunur.") }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Oku")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $secili) { s in SozcukSayfasi(s: s).presentationDetents([.medium]) }
        }
        .onAppear { acilis = Date() }
    }

    private func metin(_ p: Paket) -> some View {
        let h = depo.hazirlik(p.gun)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("GÜN \(p.gun) · MESELE NE?").font(.caption.weight(.bold)).tracking(1.1).foregroundStyle(.secondary)
                    Text(p.ozet ?? "").font(.callout).foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)

                Text(p.ad).font(.system(.title, design: .serif).weight(.semibold))

                ForEach(p.cumleler) { c in
                    satir(p, c)
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
    }

    private func satir(_ p: Paket, _ c: Cumle) -> some View {
        let caliyor = oynatici.tekCumle == c.i && oynatici.caliyor
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(c.i + 1)").font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(.tertiary).frame(width: 18, alignment: .trailing)
                Text(isaretli(c.en ?? "", p))
                    .font(Tema.ingilizce(.title3))
                    .lineSpacing(3)
                    .environment(\.openURL, OpenURLAction { url in
                        if let w = url.host(), let s = p.kelime(w.removingPercentEncoding ?? w) { secili = s }
                        return .handled
                    })
                Spacer(minLength: 0)
                Button { oynatici.cumleCal(p, c.i); depo.takildi(p, cumle: c.i, nasil: "dinle") } label: {
                    Image(systemName: caliyor ? "stop.circle.fill" : "speaker.wave.2.circle")
                        .font(.title2).foregroundStyle(caliyor ? Tema.kehribar : Tema.vurgu)
                        .symbolEffect(.variableColor.iterative, isActive: caliyor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cümleyi dinle")
            }
            if turkce.contains(c.i), let tr = c.tr {
                Text(tr).font(.callout).foregroundStyle(.secondary).padding(.leading, 28)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let k = c.konu {
                Cip(metin: k, renk: Tema.vurgu.opacity(0.85), simge: "textformat").padding(.leading, 28)
            }
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
